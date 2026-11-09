//! A call's sound: the microphone, encoded with Opus, into the call's media leg, and what the other side sends,
//! decoded, to the speaker. The devices are Anvil's (`anvil-audio`: cpal, with echo cancellation and noise
//! suppression, app plan decision 4); the leg is dsip-media's, fed Opus frames through [`dsip_media::Source::Feed`]
//! and tapping the frames it receives ([`dsip_media::MediaConfig::tap_in`]).
//!
//! Impl: one call has the devices at a time, the one answered last; a call put aside keeps its leg and sends nothing.
//! Muted, the call sends Opus-encoded silence, so its stream does not stop.

use std::sync::atomic::{AtomicBool, Ordering};
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
    tone: Option<Arc<anvil_audio::ToneStats>>,
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
                   ringback: std::sync::Mutex::new(None), tone })
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
                    tracing::warn!("audio: ringback: {e}");
                    return;
                }
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
        let mut capture = self.host.make_capture(FORMAT).map_err(|e| e.to_string())?;
        let mut playback = self.host.make_playback(FORMAT).map_err(|e| e.to_string())?;
        let feed = self.feed.clone();
        let send = tokio::spawn(async move {
            let Ok(enc) = audiopus::coder::Encoder::new(audiopus::SampleRate::Hz48000, audiopus::Channels::Mono, audiopus::Application::Voip) else {
                tracing::warn!("audio: no Opus encoder");
                return;
            };
            let silence = vec![0i16; FRAME_SAMPLES];
            let mut out = vec![0u8; 1500];
            while let Some(frame) = capture.next_frame().await {
                if frame.samples.len() != FRAME_SAMPLES {
                    continue; // the host gives 20 ms at 48 kHz mono, as asked
                }
                let pcm = if muted.load(Ordering::Relaxed) { &silence } else { &frame.samples };
                match enc.encode(pcm, &mut out) {
                    Ok(n) => {
                        if feed.send(Bytes::copy_from_slice(&out[..n])).is_err() {
                            return;
                        }
                    }
                    Err(e) => tracing::warn!("audio: Opus encode: {e}"),
                }
            }
        });
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
                let n = match (audiopus::packet::Packet::try_from(&packet[..]), audiopus::MutSignals::try_from(&mut pcm[..])) {
                    (Ok(p), Ok(s)) => dec.decode(Some(p), s, false).unwrap_or(0),
                    _ => 0,
                };
                // the speaker takes 20 ms frames
                for chunk in pcm[..n].chunks(FRAME_SAMPLES) {
                    let frame = AudioFrame { samples: chunk.to_vec(), format: FORMAT };
                    if let Err(e) = playback.write_frame(&frame).await {
                        tracing::warn!("audio: speaker: {e}");
                        return;
                    }
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

    fn stop_any(&self) {
        if let Some((_, t)) = self.ringback.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
        let mut active = self.active.lock().unwrap_or_else(|e| e.into_inner());
        for t in active.take().map(|(_, t)| t).unwrap_or_default() {
            t.abort();
        }
    }
}

impl Drop for Audio {
    fn drop(&mut self) {
        self.stop_any();
    }
}
