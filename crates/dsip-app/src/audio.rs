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
        Ok(Audio { host, kind, feed, feed_rx, heard: Arc::new(Mutex::new(heard)), tap, active: std::sync::Mutex::new(None), tone })
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

    /// With the tone host: frames the speaker was given and their peak level (0–1), to see sound arrive.
    pub fn tone_heard(&self) -> Option<(u64, f32)> {
        self.tone.as_ref().map(|s| (s.frames(), s.peak_rms()))
    }

    /// Give the devices to call `id`, `muted` read for every frame. A call that had them stops.
    pub fn start(&self, id: u64, muted: Arc<AtomicBool>) -> Result<(), String> {
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
