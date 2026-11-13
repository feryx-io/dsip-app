//! A call's sound: the microphone, encoded with Opus, into the call's media leg, and what the other side sends,
//! decoded, to the speaker. The devices are Anvil's (`anvil-audio`: cpal, with echo cancellation and noise
//! suppression, app plan decision 4); the leg is dsip-media's, fed Opus frames through [`dsip_media::Source::Feed`]
//! and tapping the frames it receives ([`dsip_media::MediaConfig::tap_in`]).
//!
//! Voice messages and voicemail (M§8.2, M§13) use the same devices outside calls: the microphone recorded to an
//! Ogg/Opus file ([`Audio::record`]), and a file played to the speaker ([`Audio::play`]).
//!
//! Impl: one call has the devices at a time, the one answered last; a call put aside keeps its leg and sends nothing.
//! Muted, the call sends Opus-encoded silence, so its stream does not stop. A call taking the devices stops a recording
//! (kept, as far as it got) and a playing.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use anvil_core::audio::{AudioFormat, AudioFrame, AudioHost};
use bytes::Bytes;
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

/// Samples in one 20 ms frame at 48 kHz mono: what one Opus frame of a call's leg carries.
pub const FRAME_SAMPLES: usize = 960;

/// 48 kHz mono, 20 ms: one Opus frame.
pub const FORMAT: AudioFormat = AudioFormat { sample_rate: 48_000, channels: 1, frame_ms: 20 };

/// The ringback tone's two frequencies, Hz: North America's (440 + 480 Hz).
pub const RINGBACK_HZ: (f32, f32) = (440.0, 480.0);
/// Its cadence: on, then off, milliseconds (2 s on, 4 s off).
pub const RINGBACK_CADENCE_MS: (u64, u64) = (2_000, 4_000);

/// Which audio host the app uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum HostKind {
    /// The platform's microphone and speaker (cpal).
    #[default]
    System,
    /// A 440 Hz tone for the microphone, and a speaker that only measures what it is given: headless use and tests.
    Tone,
}

impl HostKind {
    /// Its name in [`crate::state::Audio::host`].
    pub fn name(self) -> &'static str {
        match self {
            HostKind::System => "system",
            HostKind::Tone => "tone",
        }
    }
}

/// The audio of the app's calls.
pub struct Audio {
    host: Arc<dyn AudioHost>,
    kind: HostKind,
    feed: mpsc::UnboundedSender<Bytes>,
    feed_rx: dsip_media::Feed,
    heard: Arc<Mutex<mpsc::UnboundedReceiver<Bytes>>>,
    tap: mpsc::UnboundedSender<Bytes>,
    active: std::sync::Mutex<Option<(u64, Vec<JoinHandle<()>>)>>,
    /// The ringback tone playing, and for which call.
    ringback: std::sync::Mutex<Option<(u64, JoinHandle<()>)>>,
    /// The recording under way: told to stop through its sender, it answers with how long it is.
    recording: std::sync::Mutex<Option<Recording>>,
    /// The file playing, and its task.
    playing: std::sync::Mutex<Option<(std::path::PathBuf, JoinHandle<()>)>>,
    tone: Option<Arc<anvil_audio::ToneStats>>,
    /// What the sound did ([`Audio::sound`]).
    counters: Arc<Counters>,
}

/// The counts behind [`crate::CallSound`]: the call holding the devices, from [`Audio::start`], and the ringback
/// tone, from [`Audio::ringback`].
#[derive(Default)]
struct Counters {
    mic: AtomicU64,
    sent: AtomicU64,
    heard: AtomicU64,
    decoded: AtomicU64,
    played: AtomicU64,
    ringback: AtomicU64,
    mic_error: std::sync::Mutex<Option<String>>,
    speaker_error: std::sync::Mutex<Option<String>>,
}

impl Counters {
    fn add(n: &AtomicU64) {
        n.fetch_add(1, Ordering::Relaxed);
    }

    fn set(slot: &std::sync::Mutex<Option<String>>, why: String) {
        tracing::warn!("audio: {why}");
        *slot.lock().unwrap_or_else(|e| e.into_inner()) = Some(why);
    }

    /// Back to nothing, for the call taking the devices; the ringback's count stays (it rang before).
    fn reset_call(&self) {
        for n in [&self.mic, &self.sent, &self.heard, &self.decoded, &self.played] {
            n.store(0, Ordering::Relaxed);
        }
        *self.mic_error.lock().unwrap_or_else(|e| e.into_inner()) = None;
        *self.speaker_error.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

impl Audio {
    /// The audio of `kind`'s host.
    pub fn new(kind: HostKind) -> Result<Audio, String> {
        let (host, tone): (Arc<dyn AudioHost>, _) = match kind {
            HostKind::System => (Arc::new(anvil_audio::CpalHost::new().map_err(|e| e.to_string())?), None),
            HostKind::Tone => {
                let t = anvil_audio::ToneHost::new();
                let stats = t.stats();
                (Arc::new(t), Some(stats))
            }
        };
        let (feed, feed_rx) = dsip_media::Feed::channel();
        let (tap, heard) = mpsc::unbounded_channel();
        Ok(Audio { host, kind, feed, feed_rx, heard: Arc::new(Mutex::new(heard)), tap, active: std::sync::Mutex::new(None),
                   ringback: std::sync::Mutex::new(None), recording: std::sync::Mutex::new(None),
                   playing: std::sync::Mutex::new(None), tone, counters: Arc::default() })
    }

    /// The media every call's leg is made from: it sends what the microphone gives and taps what it receives.
    pub fn media(&self, stun: Vec<String>) -> dsip_media::MediaConfig {
        dsip_media::MediaConfig {
            source: dsip_media::Source::Feed(self.feed_rx.clone()),
            tap_in: Some(self.tap.clone()),
            stun,
            ..Default::default()
        }
    }

    /// The host's kind.
    pub fn kind(&self) -> HostKind {
        self.kind
    }

    /// What the sound of the call holding the devices, and of the ringback tone, did so far.
    pub fn sound(&self) -> crate::CallSound {
        let c = &self.counters;
        let n = |a: &AtomicU64| a.load(Ordering::Relaxed);
        let s = |m: &std::sync::Mutex<Option<String>>| m.lock().unwrap_or_else(|e| e.into_inner()).clone();
        crate::CallSound {
            mic: n(&c.mic),
            sent: n(&c.sent),
            heard: n(&c.heard),
            decoded: n(&c.decoded),
            played: n(&c.played),
            ringback: n(&c.ringback),
            mic_error: s(&c.mic_error),
            speaker_error: s(&c.speaker_error),
            stalled: None,
        }
    }

    /// The devices the host offers.
    pub fn devices(&self) -> Vec<crate::state::AudioDevice> {
        self.host
            .devices()
            .into_iter()
            .map(|d| crate::state::AudioDevice { id: d.id, name: d.name, kind: if d.is_input { "input" } else { "output" }.into(), default: d.is_default })
            .collect()
    }

    /// Use these devices (by id; `None`: the system's default) for the streams opened from now on; the open ones move.
    /// The tone host has no choice of device and refuses.
    pub fn choose(&self, input: Option<&str>, output: Option<&str>) -> Result<(), String> {
        self.host.choose_devices(input, output).map_err(|e| e.to_string())
    }

    /// The devices chosen, `None` for the system's default.
    pub fn chosen(&self) -> (Option<String>, Option<String>) {
        self.host.chosen_devices()
    }

    /// The audio's part of the state: the host, its devices, those chosen.
    pub fn view(&self) -> crate::state::Audio {
        let (input, output) = self.chosen();
        crate::state::Audio { host: self.kind.name().into(), devices: self.devices(), input, output }
    }

    /// With the tone host: frames the speaker was given and their peak level (0–1), to see sound arrive.
    pub fn tone_heard(&self) -> Option<(u64, f32)> {
        self.tone.as_ref().map(|s| (s.frames(), s.peak_rms()))
    }

    /// Play the ringback tone on the speaker for call `id`, placed here and ringing at the callee (§12.4's
    /// `ringing` progress): [`RINGBACK_HZ`] in [`RINGBACK_CADENCE_MS`], until [`Audio::stop_ringback`], the call's
    /// [`Audio::start`], or another call's ringback. Made here: nothing comes from the callee before the answer.
    pub fn ringback(&self, id: u64) -> Result<(), String> {
        let mut playback = self.host.make_playback(FORMAT).map_err(|e| e.to_string())?;
        let counters = self.counters.clone();
        counters.ringback.store(0, Ordering::Relaxed);
        let task = tokio::spawn(async move {
            let (on, off) = (RINGBACK_CADENCE_MS.0 / 20, RINGBACK_CADENCE_MS.1 / 20); // in 20 ms frames
            let rate = FORMAT.sample_rate as f32;
            let mut n: u64 = 0; // samples since the tone started
            let mut clock = tokio::time::interval(std::time::Duration::from_millis(20));
            loop {
                clock.tick().await;
                let frame_no = n / FRAME_SAMPLES as u64;
                let sounding = frame_no % (on + off) < on;
                let samples: Vec<i16> = (0..FRAME_SAMPLES as u64)
                    .map(|i| {
                        if !sounding {
                            return 0;
                        }
                        let t = (n + i) as f32 / rate;
                        let v = (2.0 * std::f32::consts::PI * RINGBACK_HZ.0 * t).sin() + (2.0 * std::f32::consts::PI * RINGBACK_HZ.1 * t).sin();
                        (v * 0.15 * i16::MAX as f32) as i16
                    })
                    .collect();
                n += FRAME_SAMPLES as u64;
                if let Err(e) = playback.write_frame(&AudioFrame { samples, format: FORMAT }).await {
                    Counters::set(&counters.speaker_error, format!("ringback: {e}"));
                    return;
                }
                Counters::add(&counters.ringback);
            }
        });
        if let Some((_, old)) = self.ringback.lock().unwrap_or_else(|e| e.into_inner()).replace((id, task)) {
            old.abort();
        }
        Ok(())
    }

    /// Stop call `id`'s ringback tone, if it plays.
    pub fn stop_ringback(&self, id: u64) {
        let mut r = self.ringback.lock().unwrap_or_else(|e| e.into_inner());
        if r.as_ref().is_some_and(|(a, _)| *a == id) {
            if let Some((_, t)) = r.take() {
                t.abort();
            }
        }
    }

    /// Whether call `id`'s ringback tone plays.
    pub fn ringing_back(&self, id: u64) -> bool {
        self.ringback.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(a, t)| *a == id && !t.is_finished())
    }

    /// Give the devices to call `id`, `muted` read for every frame. A call that had them stops, and so does `id`'s
    /// ringback tone.
    pub fn start(&self, id: u64, muted: Arc<AtomicBool>) -> Result<(), String> {
        self.stop_ringback(id);
        self.stop_any();
        // frames left over from a call before this one
        if let Ok(mut rx) = self.feed_rx.0.try_lock() {
            while rx.try_recv().is_ok() {}
        }
        self.counters.reset_call();
        let mut capture = self.host.make_capture(FORMAT).map_err(|e| e.to_string())?;
        let mut playback = self.host.make_playback(FORMAT).map_err(|e| e.to_string())?;
        let feed = self.feed.clone();
        let counters = self.counters.clone();
        let send = tokio::spawn(async move {
            let Ok(enc) = audiopus::coder::Encoder::new(audiopus::SampleRate::Hz48000, audiopus::Channels::Mono, audiopus::Application::Voip) else {
                tracing::warn!("audio: no Opus encoder");
                return;
            };
            let silence = vec![0i16; FRAME_SAMPLES];
            let mut out = vec![0u8; 1500];
            while let Some(frame) = capture.next_frame().await {
                Counters::add(&counters.mic);
                if frame.samples.len() != FRAME_SAMPLES {
                    continue; // the host gives 20 ms at 48 kHz mono, as asked
                }
                let pcm = if muted.load(Ordering::Relaxed) { &silence } else { &frame.samples };
                match enc.encode(pcm, &mut out) {
                    Ok(n) => {
                        if feed.send(Bytes::copy_from_slice(&out[..n])).is_err() {
                            return;
                        }
                        Counters::add(&counters.sent);
                    }
                    Err(e) => tracing::warn!("audio: Opus encode: {e}"),
                }
            }
            Counters::set(&counters.mic_error, "the microphone stopped".into());
        });
        let counters = self.counters.clone();
        let heard = self.heard.clone();
        let play = tokio::spawn(async move {
            let Ok(mut dec) = audiopus::coder::Decoder::new(audiopus::SampleRate::Hz48000, audiopus::Channels::Mono) else {
                tracing::warn!("audio: no Opus decoder");
                return;
            };
            let mut heard = heard.lock().await;
            while heard.try_recv().is_ok() {}
            let mut pcm = vec![0i16; FRAME_SAMPLES * 6]; // Opus frames are at most 120 ms
            while let Some(packet) = heard.recv().await {
                Counters::add(&counters.heard);
                let n = match (audiopus::packet::Packet::try_from(&packet[..]), audiopus::MutSignals::try_from(&mut pcm[..])) {
                    (Ok(p), Ok(s)) => dec.decode(Some(p), s, false).unwrap_or(0),
                    _ => 0,
                };
                if n > 0 {
                    Counters::add(&counters.decoded);
                }
                // the speaker takes 20 ms frames
                for chunk in pcm[..n].chunks(FRAME_SAMPLES) {
                    let frame = AudioFrame { samples: chunk.to_vec(), format: FORMAT };
                    if let Err(e) = playback.write_frame(&frame).await {
                        Counters::set(&counters.speaker_error, format!("speaker: {e}"));
                        return;
                    }
                    Counters::add(&counters.played);
                }
            }
        });
        *self.active.lock().unwrap_or_else(|e| e.into_inner()) = Some((id, vec![send, play]));
        Ok(())
    }

    /// Take the devices from call `id`, if it has them.
    pub fn stop(&self, id: u64) {
        let mut active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        if active.as_ref().is_some_and(|(a, _)| *a == id) {
            for t in active.take().map(|(_, t)| t).unwrap_or_default() {
                t.abort();
            }
        }
    }

    /// Record the microphone to `path`, an Ogg/Opus file (48 kHz mono, 20 ms frames: `audio/ogg; codecs=opus`, which
    /// M§13.2 requires), until [`Audio::stop_recording`] or `max_ms` (M§13.2: a voicemail stops at the callee's
    /// `max_duration_s`). `ended` is called with its length, milliseconds, when it stops for any reason. Refused while
    /// a call has the devices, or another recording runs.
    pub fn record(&self, path: &std::path::Path, max_ms: Option<u64>, ended: impl FnOnce(u64) + Send + 'static) -> Result<(), String> {
        if self.active.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
            return Err("a call has the microphone".into());
        }
        let mut slot = self.recording.lock().unwrap_or_else(|e| e.into_inner());
        if slot.as_ref().is_some_and(|r| !r.task.is_finished()) {
            return Err("already recording".into());
        }
        self.stop_playing();
        let file = std::fs::File::create(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let mut capture = self.host.make_capture(FORMAT).map_err(|e| e.to_string())?;
        let (stop, mut stopped) = tokio::sync::oneshot::channel::<()>();
        let done = Arc::new(std::sync::atomic::AtomicU64::new(0));
        let ms = done.clone();
        let task = tokio::spawn(async move {
            let Ok(enc) = audiopus::coder::Encoder::new(audiopus::SampleRate::Hz48000, audiopus::Channels::Mono, audiopus::Application::Voip) else {
                tracing::warn!("audio: no Opus encoder");
                return;
            };
            let pre_skip = enc.lookahead().map(|l| l as u16).unwrap_or(312);
            let mut ogg = match OggOpus::new(std::io::BufWriter::new(file), pre_skip) {
                Ok(w) => w,
                Err(e) => {
                    tracing::warn!("audio: recording: {e}");
                    return;
                }
            };
            let mut out = vec![0u8; 1500];
            let mut frames = 0u64;
            loop {
                let frame = tokio::select! {
                    f = capture.next_frame() => f,
                    _ = &mut stopped => None,
                };
                let Some(frame) = frame else { break };
                if frame.samples.len() != FRAME_SAMPLES {
                    continue;
                }
                match enc.encode(&frame.samples, &mut out) {
                    Ok(n) => {
                        if let Err(e) = ogg.push(&out[..n], FRAME_SAMPLES as u64) {
                            tracing::warn!("audio: recording: {e}");
                            break;
                        }
                        frames += 1;
                        ms.store(frames * 20, Ordering::Relaxed);
                    }
                    Err(e) => tracing::warn!("audio: Opus encode: {e}"),
                }
                if max_ms.is_some_and(|m| frames * 20 >= m) {
                    break;
                }
            }
            if let Err(e) = ogg.finish() {
                tracing::warn!("audio: recording: {e}");
            }
            ended(frames * 20);
        });
        *slot = Some(Recording { path: path.to_path_buf(), stop: Some(stop), task, ms: done });
        Ok(())
    }

    /// The recording under way, or ended and not yet taken: its file, and its length so far, milliseconds.
    pub fn recording(&self) -> Option<(std::path::PathBuf, u64, bool)> {
        let r = self.recording.lock().unwrap_or_else(|e| e.into_inner());
        r.as_ref().map(|r| (r.path.clone(), r.ms.load(Ordering::Relaxed), !r.task.is_finished()))
    }

    /// Stop the recording and take it: its file, and its length in milliseconds, once the file is complete.
    pub async fn stop_recording(&self) -> Option<(std::path::PathBuf, u64)> {
        let mut r = self.recording.lock().unwrap_or_else(|e| e.into_inner()).take()?;
        if let Some(stop) = r.stop.take() {
            let _ = stop.send(());
        }
        let _ = (&mut r.task).await;
        Some((r.path, r.ms.load(Ordering::Relaxed)))
    }

    /// Play the Ogg/Opus file at `path` to the speaker; `done` is called when it has played out, or stopped. A file
    /// playing before stops. Refused while a call has the devices.
    pub fn play(&self, path: &std::path::Path, done: impl FnOnce() + Send + 'static) -> Result<(), String> {
        if self.active.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
            return Err("a call has the speaker".into());
        }
        let mut source = dsip_media::ogg::FileSource::open(path).map_err(|e| e.to_string())?;
        let mut playback = self.host.make_playback(FORMAT).map_err(|e| e.to_string())?;
        self.stop_playing();
        struct Done<F: FnOnce()>(Option<F>);
        impl<F: FnOnce()> Drop for Done<F> {
            fn drop(&mut self) {
                if let Some(f) = self.0.take() {
                    f();
                }
            }
        }
        let task = tokio::spawn(async move {
            let _done = Done(Some(done)); // told when it ends, aborted too
            let Ok(mut dec) = audiopus::coder::Decoder::new(audiopus::SampleRate::Hz48000, audiopus::Channels::Mono) else {
                tracing::warn!("audio: no Opus decoder");
                return;
            };
            let mut pcm = vec![0i16; FRAME_SAMPLES * 6];
            let mut clock = tokio::time::interval(std::time::Duration::from_millis(20));
            while let Some(packet) = source.next_frame() {
                let n = match (audiopus::packet::Packet::try_from(&packet[..]), audiopus::MutSignals::try_from(&mut pcm[..])) {
                    (Ok(p), Ok(s)) => dec.decode(Some(p), s, false).unwrap_or(0),
                    _ => 0,
                };
                for chunk in pcm[..n].chunks(FRAME_SAMPLES) {
                    clock.tick().await; // at the pace it was recorded
                    let mut samples = chunk.to_vec();
                    samples.resize(FRAME_SAMPLES, 0);
                    if let Err(e) = playback.write_frame(&AudioFrame { samples, format: FORMAT }).await {
                        tracing::warn!("audio: speaker: {e}");
                        return;
                    }
                }
            }
            // what the speaker holds yet
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        });
        *self.playing.lock().unwrap_or_else(|e| e.into_inner()) = Some((path.to_path_buf(), task));
        Ok(())
    }

    /// The file playing.
    pub fn playing(&self) -> Option<std::path::PathBuf> {
        let p = self.playing.lock().unwrap_or_else(|e| e.into_inner());
        p.as_ref().filter(|(_, t)| !t.is_finished()).map(|(p, _)| p.clone())
    }

    /// Stop the file playing, if one is.
    pub fn stop_playing(&self) {
        if let Some((_, t)) = self.playing.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
    }

    fn stop_any(&self) {
        self.stop_playing();
        if let Some(r) = self.recording.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
            if let Some(stop) = r.stop.take() {
                let _ = stop.send(());
            }
        }
        if let Some((_, t)) = self.ringback.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
        let mut active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        for t in active.take().map(|(_, t)| t).unwrap_or_default() {
            t.abort();
        }
    }
}

/// A recording under way ([`Audio::record`]).
struct Recording {
    path: std::path::PathBuf,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
    task: JoinHandle<()>,
    /// Its length so far, milliseconds.
    ms: Arc<std::sync::atomic::AtomicU64>,
}

/// An Ogg Opus stream being written (RFC 7845, RFC 3533): the `OpusHead` and `OpusTags` pages, then the audio on
/// pages of up to [`OggOpus::PAGE_PACKETS`] packets, each page's granule position the samples to its end counting the
/// pre-skip, the last page marked the stream's end.
pub struct OggOpus<W: std::io::Write> {
    out: W,
    serial: u32,
    seq: u32,
    granule: u64,
    pending: Vec<Vec<u8>>,
}

impl<W: std::io::Write> OggOpus<W> {
    /// Packets on one audio page: a second of 20 ms frames.
    pub const PAGE_PACKETS: usize = 50;

    /// Start a mono 48 kHz stream whose decoder drops `pre_skip` samples first (the encoder's lookahead).
    pub fn new(out: W, pre_skip: u16) -> std::io::Result<OggOpus<W>> {
        let mut w = OggOpus { out, serial: 0x6473_6970, seq: 0, granule: u64::from(pre_skip), pending: vec![] };
        let mut head = b"OpusHead".to_vec();
        head.extend_from_slice(&[1, 1]); // version, one channel
        head.extend_from_slice(&pre_skip.to_le_bytes());
        head.extend_from_slice(&48_000u32.to_le_bytes()); // the input's rate
        head.extend_from_slice(&[0, 0, 0]); // output gain, channel mapping family 0
        w.page(&[head], 0x02, 0)?;
        let vendor = b"dsip-app";
        let mut tags = b"OpusTags".to_vec();
        tags.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
        tags.extend_from_slice(vendor);
        tags.extend_from_slice(&0u32.to_le_bytes());
        w.page(&[tags], 0, 0)?;
        Ok(w)
    }

    /// Add one Opus packet of `samples` samples (at 48 kHz).
    pub fn push(&mut self, packet: &[u8], samples: u64) -> std::io::Result<()> {
        // a page's segment table holds 255 lacing values: a packet that would overflow it starts the next page
        let laced = |p: &[u8]| p.len() / 255 + 1;
        if self.pending.iter().map(|p| laced(p)).sum::<usize>() + laced(packet) > 255 {
            let packets = std::mem::take(&mut self.pending);
            self.page(&packets, 0, self.granule)?;
        }
        self.pending.push(packet.to_vec());
        self.granule += samples;
        if self.pending.len() >= Self::PAGE_PACKETS {
            let packets = std::mem::take(&mut self.pending);
            self.page(&packets, 0, self.granule)?;
        }
        Ok(())
    }

    /// Write what is left on the last page, marked the stream's end, and flush.
    pub fn finish(mut self) -> std::io::Result<()> {
        let packets = std::mem::take(&mut self.pending);
        self.page(&packets, 0x04, self.granule)?;
        self.out.flush()
    }

    fn page(&mut self, packets: &[Vec<u8>], flags: u8, granule: u64) -> std::io::Result<()> {
        let mut lacing = vec![];
        for p in packets {
            lacing.extend(std::iter::repeat_n(255u8, p.len() / 255));
            lacing.push((p.len() % 255) as u8);
        }
        let mut page = b"OggS".to_vec();
        page.push(0);
        page.push(flags);
        page.extend_from_slice(&granule.to_le_bytes());
        page.extend_from_slice(&self.serial.to_le_bytes());
        page.extend_from_slice(&self.seq.to_le_bytes());
        page.extend_from_slice(&[0; 4]); // the checksum, below
        page.push(lacing.len() as u8);
        page.extend_from_slice(&lacing);
        for p in packets {
            page.extend_from_slice(p);
        }
        let crc = ogg_crc(&page);
        page[22..26].copy_from_slice(&crc.to_le_bytes());
        self.seq += 1;
        self.out.write_all(&page)
    }
}

/// The Ogg page checksum (RFC 3533): CRC-32, polynomial 0x04c11db7, unreflected, initial value 0.
fn ogg_crc(data: &[u8]) -> u32 {
    let mut crc = 0u32;
    for &b in data {
        crc ^= u32::from(b) << 24;
        for _ in 0..8 {
            crc = if crc & 0x8000_0000 != 0 { (crc << 1) ^ 0x04c1_1db7 } else { crc << 1 };
        }
    }
    crc
}

/// The length of the Ogg Opus file at `path`, milliseconds: its last page's granule position less the pre-skip
/// (RFC 7845 §4); `None` when it is not one.
pub fn duration_ms(path: &std::path::Path) -> Option<u64> {
    let data = std::fs::read(path).ok()?;
    let mut pre_skip = None;
    let mut last = None;
    let mut i = 0;
    while i + 27 <= data.len() {
        if &data[i..i + 4] != b"OggS" {
            i += 1;
            continue;
        }
        let segments = data[i + 26] as usize;
        let body = i + 27 + segments;
        let len: usize = data.get(i + 27..body)?.iter().map(|&l| l as usize).sum();
        if pre_skip.is_none() {
            let head = data.get(body..body + 19)?;
            if &head[..8] != b"OpusHead" {
                return None;
            }
            pre_skip = Some(u64::from(u16::from_le_bytes([head[10], head[11]])));
        }
        let granule = u64::from_le_bytes(data[i + 6..i + 14].try_into().ok()?);
        if granule != u64::MAX {
            last = Some(granule);
        }
        i = body + len;
    }
    Some(last?.saturating_sub(pre_skip?) / 48)
}

impl Drop for Audio {
    fn drop(&mut self) {
        self.stop_any();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn written(packets: &[Vec<u8>]) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!("dsip-app-ogg-{}-{}.ogg", std::process::id(), packets.len()));
        let mut w = OggOpus::new(std::fs::File::create(&path).unwrap(), 312).unwrap();
        for p in packets {
            w.push(p, FRAME_SAMPLES as u64).unwrap();
        }
        w.finish().unwrap();
        path
    }

    #[test]
    fn an_ogg_opus_file_reads_back_packet_for_packet_and_its_length_is_its_granule() {
        // 2.5 s of 20 ms packets, one larger than a lacing value and one a multiple of it
        let mut packets: Vec<Vec<u8>> = (0..125u32).map(|i| vec![(i % 251) as u8; 40 + (i as usize % 30)]).collect();
        packets[7] = vec![9; 300];
        packets[60] = vec![3; 510];
        let path = written(&packets);
        let mut src = dsip_media::ogg::FileSource::open(&path).unwrap();
        let mut back = vec![];
        while let Some(p) = src.next_frame() {
            back.push(p.to_vec());
        }
        assert_eq!(back, packets, "every packet once, in order");
        assert_eq!(duration_ms(&path), Some(2_500));

        let data = std::fs::read(&path).unwrap();
        let pages: Vec<usize> = (0..data.len() - 3).filter(|&i| &data[i..i + 4] == b"OggS").collect();
        assert_eq!(data[pages[0] + 5], 0x02, "the first page begins the stream");
        assert_eq!(data[*pages.last().unwrap() + 5], 0x04, "the last ends it");
        for (n, &at) in pages.iter().enumerate() {
            let end = pages.get(n + 1).copied().unwrap_or(data.len());
            let mut page = data[at..end].to_vec();
            let crc = u32::from_le_bytes(page[22..26].try_into().unwrap());
            page[22..26].copy_from_slice(&[0; 4]);
            assert_eq!(ogg_crc(&page), crc, "page {n}'s checksum");
            assert_eq!(u32::from_le_bytes(page[18..22].try_into().unwrap()), n as u32, "page {n} in sequence");
        }
        let _ = std::fs::remove_file(path);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn the_microphone_recorded_stops_at_its_limit_and_plays_back() {
        let audio = Audio::new(HostKind::Tone).unwrap();
        let path = std::env::var_os("DSIP_KEEP_RECORDING")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| std::env::temp_dir().join(format!("dsip-app-rec-{}.ogg", std::process::id())));
        let (tx, rx) = tokio::sync::oneshot::channel();
        audio.record(&path, Some(600), move |ms| { let _ = tx.send(ms); }).unwrap();
        assert!(audio.record(&path, None, |_| {}).is_err(), "one recording at a time");
        assert_eq!(tokio::time::timeout(std::time::Duration::from_secs(5), rx).await.unwrap().unwrap(), 600);
        assert_eq!(audio.stop_recording().await.map(|(_, ms)| ms), Some(600));
        assert_eq!(duration_ms(&path), Some(600));

        let (tx, rx) = tokio::sync::oneshot::channel();
        audio.play(&path, move || { let _ = tx.send(()); }).unwrap();
        assert!(audio.playing().is_some());
        tokio::time::timeout(std::time::Duration::from_secs(5), rx).await.unwrap().unwrap();
        let (frames, peak) = audio.tone_heard().unwrap();
        assert!(frames >= 25 && peak > 0.05, "the tone came back out: {frames} frames, peak {peak}");
        if std::env::var_os("DSIP_KEEP_RECORDING").is_none() {
            let _ = std::fs::remove_file(path);
        }
    }

    #[test]
    fn the_checksum_is_ogg_s() {
        // RFC 3533's CRC: the CRC-32/MPEG-2 polynomial, unreflected, from 0 and not inverted ("123456789" → 0x89a1897f)
        assert_eq!(ogg_crc(b"123456789"), 0x89a1_897f);
    }

    #[test]
    fn a_file_that_is_not_ogg_opus_has_no_length() {
        let path = std::env::temp_dir().join(format!("dsip-app-not-ogg-{}", std::process::id()));
        std::fs::write(&path, b"not an ogg file at all, just words").unwrap();
        assert_eq!(duration_ms(&path), None);
        let _ = std::fs::remove_file(path);
    }
}
