//! The video of the app's calls: the camera, encoded, into the call's leg, and what the far end sends, decoded and
//! shown. The leg moves coded frames (dsip-media); the host captures, encodes, decodes and draws (anvil-video on
//! Android and Windows, a synthetic host in tests).
//!
//! Impl: calls carry H.264 only. It is the codec every endpoint doing video supports (B§3.4, spec-gap 181), Android
//! and Windows encode it in hardware, and with one codec the camera's encoder and the decoder never need to learn
//! which one a call settled on.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use anvil_core::video::host::{
    CodedFrame, EncodingId, ReceiveConfig, Resolution, SendConfig, StreamId, VideoCodec, VideoHost, VideoKind,
};
use dsip_media::{VideoFeed, VideoFrame, VideoRequest};
use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::audio::HostKind;

/// The most a call's camera sends: VGA at 30 frames a second.
pub const MAX: Resolution = Resolution { width: 640, height: 480 };
/// Frames a second.
pub const FPS: u32 = 30;
/// The bitrate a call's camera starts at, kb/s, until the far end says what it takes.
pub const START_KBPS: u32 = 800;
/// The most this side takes, said in its offer or answer (`b=AS`), kb/s.
pub const MAX_KBPS: u32 = 1_500;

/// RTP's video clock, Hz.
const CLOCK: u64 = 90_000;

/// The video of the app's calls, one call at a time (the one holding the devices, as for audio).
pub struct Video {
    host: Arc<dyn VideoHost>,
    feed: mpsc::UnboundedSender<VideoFrame>,
    feed_rx: VideoFeed,
    sink: mpsc::UnboundedSender<VideoFrame>,
    received: Arc<Mutex<mpsc::UnboundedReceiver<VideoFrame>>>,
    requests: mpsc::UnboundedSender<VideoRequest>,
    requests_rx: Arc<Mutex<mpsc::UnboundedReceiver<VideoRequest>>>,
    /// The call shown, and its decoder's task.
    showing: std::sync::Mutex<Option<(u64, JoinHandle<()>)>>,
    /// The call the camera sends to, and its task.
    sending: std::sync::Mutex<Option<(u64, JoinHandle<()>)>>,
    /// Frames sent and received, for the call's view.
    pub(crate) counters: Arc<Counters>,
    /// The platform's host, whose tiles the app's textures show ([`Video::tiles`]).
    #[cfg(any(target_os = "android", windows))]
    desktop: Option<anvil_video::DesktopVideoHost>,
}

/// What a call's video did.
#[derive(Default)]
pub(crate) struct Counters {
    pub(crate) sent: AtomicU64,
    pub(crate) received: AtomicU64,
}

/// The platform's video host, where the app has one.
#[cfg(any(target_os = "android", windows))]
fn platform() -> Option<anvil_video::DesktopVideoHost> {
    // OpenH264 is not used here: Android and Windows encode H.264 in hardware (MediaCodec, Media Foundation)
    let dir = std::env::temp_dir().join("dsip-openh264");
    Some(anvil_video::DesktopVideoHost::platform(&dir))
}

impl Video {
    /// The video of `kind`'s host: the platform's camera and codecs, or numbered frames for tests. `None` where the
    /// platform has no video yet, or its host cannot both encode and decode H.264.
    pub fn new(kind: HostKind) -> Option<Video> {
        #[cfg(any(target_os = "android", windows))]
        let desktop = match kind {
            HostKind::System => Some(platform()?),
            HostKind::Tone => None,
        };
        let host: Arc<dyn VideoHost> = match kind {
            #[cfg(any(target_os = "android", windows))]
            HostKind::System => Arc::new(desktop.clone()?),
            #[cfg(not(any(target_os = "android", windows)))]
            HostKind::System => return None,
            HostKind::Tone => Arc::new(anvil_core::video::synthetic::SyntheticVideoHost::new(&[VideoCodec::H264])),
        };
        if !host.codecs().iter().any(|c| c.codec == VideoCodec::H264 && c.encode && c.decode) {
            tracing::warn!("video: the host cannot encode and decode H.264; calls are audio only");
            return None;
        }
        #[allow(unused_mut)]
        let mut video = Video::with_host(host);
        #[cfg(any(target_os = "android", windows))]
        {
            video.desktop = desktop;
        }
        Some(video)
    }

    /// The tiles the platform host draws calls' pictures on (each call's stream, and this side's camera as its
    /// self-view), for the app's textures.
    #[cfg(any(target_os = "android", windows))]
    pub fn tiles(&self) -> Option<anvil_video::Tiles> {
        self.desktop.as_ref().map(anvil_video::DesktopVideoHost::tiles)
    }

    /// The call whose video is shown, if any.
    pub fn showing(&self) -> Option<u64> {
        self.showing.lock().unwrap_or_else(|e| e.into_inner()).as_ref().map(|(id, _)| *id)
    }

    /// Video on `host`.
    pub fn with_host(host: Arc<dyn VideoHost>) -> Video {
        let (feed, feed_rx) = VideoFeed::channel();
        let (sink, received) = mpsc::unbounded_channel();
        let (requests, requests_rx) = mpsc::unbounded_channel();
        Video { host, feed, feed_rx, sink, received: Arc::new(Mutex::new(received)), requests,
                requests_rx: Arc::new(Mutex::new(requests_rx)), showing: Default::default(), sending: Default::default(),
                counters: Arc::default(),
                #[cfg(any(target_os = "android", windows))]
                desktop: None }
    }

    /// The host, for showing calls' pictures.
    pub fn host(&self) -> &Arc<dyn VideoHost> {
        &self.host
    }

    /// The video section every video call's leg is made with: H.264, frames from the camera, frames to the decoder.
    pub fn media(&self) -> dsip_media::VideoConfig {
        dsip_media::VideoConfig {
            codecs: vec![dsip_media::video::H264.into()],
            source: Some(self.feed_rx.clone()),
            sink: Some(self.sink.clone()),
            requests: Some(self.requests.clone()),
            max_kbps: Some(MAX_KBPS),
        }
    }

    /// Show call `id`'s video: what arrives is decoded and drawn on its tile (stream `id`).
    pub fn show(&self, id: u64) -> Result<(), String> {
        self.stop_showing();
        let mut sink = self.host.start_receive(stream(id), ReceiveConfig { codec: VideoCodec::H264, kind: VideoKind::Camera })
            .map_err(|e| e.to_string())?;
        let (received, counters) = (self.received.clone(), self.counters.clone());
        counters.received.store(0, Ordering::Relaxed);
        let task = tokio::spawn(async move {
            let mut received = received.lock().await;
            while received.try_recv().is_ok() {} // a call before this one's
            while let Some(f) = received.recv().await {
                counters.received.fetch_add(1, Ordering::Relaxed);
                let now = Instant::now();
                sink.frame(CodedFrame { data: f.data, keyframe: f.keyframe, captured: now }, now);
            }
        });
        *self.showing.lock().unwrap_or_else(|e| e.into_inner()) = Some((id, task));
        Ok(())
    }

    /// Send the camera to call `id`: captured, encoded as H.264, into its leg; the far end's keyframe and bitrate
    /// requests go to the encoder.
    pub fn send(&self, id: u64) -> Result<(), String> {
        self.stop_sending();
        let cfg = SendConfig { codec: VideoCodec::H264, kind: VideoKind::Camera, camera: None, max: MAX, kbps: START_KBPS,
                               fps: FPS, encodings: vec![EncodingId(0)] };
        let mut source = self.host.start_send(cfg).map_err(|e| e.to_string())?;
        let (feed, requests, counters) = (self.feed.clone(), self.requests_rx.clone(), self.counters.clone());
        counters.sent.store(0, Ordering::Relaxed);
        let task = tokio::spawn(async move {
            let mut requests = requests.lock().await;
            while requests.try_recv().is_ok() {}
            let start = Instant::now();
            loop {
                tokio::select! {
                    frame = source.next_frame() => {
                        let Some((_, f)) = frame else { break };
                        let ticks = f.captured.saturating_duration_since(start).as_micros() as u64 * CLOCK / 1_000_000;
                        if feed.send(VideoFrame { data: f.data, keyframe: f.keyframe, timestamp: ticks as u32 }).is_err() {
                            break;
                        }
                        counters.sent.fetch_add(1, Ordering::Relaxed);
                    }
                    Some(r) = requests.recv() => match r {
                        VideoRequest::Keyframe => source.request_keyframe(),
                        VideoRequest::Bitrate(kbps) => source.set_target(kbps.min(MAX_KBPS), MAX, FPS),
                    },
                }
            }
        });
        *self.sending.lock().unwrap_or_else(|e| e.into_inner()) = Some((id, task));
        Ok(())
    }

    /// Stop the camera; the call's picture stays shown.
    pub fn stop_sending(&self) {
        if let Some((_, t)) = self.sending.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
    }

    fn stop_showing(&self) {
        if let Some((_, t)) = self.showing.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
    }

    /// Whether the camera sends to call `id`.
    pub fn sending_to(&self, id: u64) -> bool {
        self.sending.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(c, _)| *c == id)
    }

    /// Stop call `id`'s video, sent and shown.
    pub fn stop(&self, id: u64) {
        if self.sending_to(id) {
            self.stop_sending();
        }
        if self.showing.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(c, _)| *c == id) {
            self.stop_showing();
        }
    }

    /// Frames sent and received so far by the call holding the video.
    pub fn frames(&self) -> (u64, u64) {
        (self.counters.sent.load(Ordering::Relaxed), self.counters.received.load(Ordering::Relaxed))
    }
}

/// The tile a call's picture is drawn on.
pub fn stream(id: u64) -> StreamId {
    StreamId(id as u32)
}
