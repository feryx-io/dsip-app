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
    CodedFrame, Encoding, EncodingId, ReceiveConfig, Resolution, SendConfig, StreamId, VideoCodec, VideoHost, VideoKind,
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
    /// The call the camera sends to, and its task: it ends when the camera stops giving pictures (a phone takes it
    /// away from an app off the screen).
    sending: std::sync::Mutex<Option<(u64, JoinHandle<()>)>>,
    /// The call the camera is wanted for, until turned off: [`Video::heal`] opens it again when it stopped.
    wanted: std::sync::Mutex<Option<u64>>,
    /// Held while the camera is opened or stopped: one at a time. Two that open it at once (the call's own start and
    /// the screen's "camera on", which a phone sends as the call's video appears) each find it not yet sending, and
    /// the second open takes the camera from the first, whose failure is then said for a call whose camera works.
    opening: std::sync::Mutex<()>,
    /// Frames sent and received, for the call's view.
    pub(crate) counters: Arc<Counters>,
    /// The call whose camera or picture would not start, and why, each reason once ([`Video::errors`]).
    failed: std::sync::Mutex<(u64, Vec<String>)>,
    /// The platform's host, whose tiles the app's textures show ([`Video::tiles`]).
    #[cfg(any(target_os = "android", windows))]
    desktop: Option<anvil_video::DesktopVideoHost>,
}

/// What a call's video did.
#[derive(Default)]
pub(crate) struct Counters {
    pub(crate) sent: AtomicU64,
    pub(crate) received: AtomicU64,
    /// Of those received, the keyframes; and the first frame and the last keyframe as [`describe`] has them.
    keyframes: AtomicU64,
    first: std::sync::Mutex<Option<String>>,
    keyframe: std::sync::Mutex<Option<String>>,
}

/// An H.264 frame for [`Video::report`]: its size and its NAL units' types in order (7 and 8 the parameter sets, 5 an
/// IDR slice, 1 any other, 9 a delimiter, 6 SEI), the first twelve, and its first bytes.
fn describe(data: &[u8]) -> String {
    let mut types = Vec::new();
    let mut i = 0;
    while i + 3 < data.len() && types.len() < 12 {
        if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
            types.push((data[i + 3] & 0x1f).to_string());
            i += 3;
        } else {
            i += 1;
        }
    }
    let head: Vec<String> = data.iter().take(5).map(|b| format!("{b:02x}")).collect();
    format!("{} B, NALs [{}], starts {}", data.len(), types.join(" "), head.join(""))
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
                wanted: Default::default(), opening: Default::default(), counters: Arc::default(), failed: Default::default(),
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
            .map_err(|e| self.fail(id, "picture", e.to_string()))?;
        let (received, counters) = (self.received.clone(), self.counters.clone());
        counters.received.store(0, Ordering::Relaxed);
        counters.keyframes.store(0, Ordering::Relaxed);
        *counters.first.lock().unwrap_or_else(|e| e.into_inner()) = None;
        *counters.keyframe.lock().unwrap_or_else(|e| e.into_inner()) = None;
        let task = tokio::spawn(async move {
            // what came before this, the call's own first frames and its keyframe among them: the far end sends the
            // next keyframe only when asked, and its leg asks only for one it lost (the last call's are gone, `stop`)
            let mut received = received.lock().await;
            while let Some(f) = received.recv().await {
                if counters.received.fetch_add(1, Ordering::Relaxed) == 0 {
                    *counters.first.lock().unwrap_or_else(|e| e.into_inner()) = Some(describe(&f.data));
                }
                if f.keyframe {
                    counters.keyframes.fetch_add(1, Ordering::Relaxed);
                    *counters.keyframe.lock().unwrap_or_else(|e| e.into_inner()) = Some(describe(&f.data));
                }
                let now = Instant::now();
                sink.frame(CodedFrame { data: f.data, keyframe: f.keyframe, captured: now }, now);
            }
        });
        *self.showing.lock().unwrap_or_else(|e| e.into_inner()) = Some((id, task));
        Ok(())
    }

    /// Send the camera to call `id`: captured, encoded as H.264, into its leg; the far end's keyframe and bitrate
    /// requests go to the encoder. Wanted from now on, even if it will not open yet ([`Video::heal`]); already sending
    /// to `id`, it goes on as it is (a camera opened twice is busy), as it does when another caller is opening it now:
    /// this one waits and finds it sending.
    pub fn send(&self, id: u64) -> Result<(), String> {
        let _one = self.opening.lock().unwrap_or_else(|e| e.into_inner());
        *self.wanted.lock().unwrap_or_else(|e| e.into_inner()) = Some(id);
        if self.sending_to(id) {
            return Ok(());
        }
        self.start_sending(id).map_err(|e| self.fail(id, "camera", e))
    }

    /// Keep why call `id`'s `what` (its camera, its picture) would not start, for its view, and give the reason back.
    /// Trying again where a phone took the camera away ([`Video::heal`]) is not kept: that is a phone's ordinary life.
    fn fail(&self, id: u64, what: &str, e: String) -> String {
        let mut failed = self.failed.lock().unwrap_or_else(|e| e.into_inner());
        if failed.0 != id {
            *failed = (id, Vec::new());
        }
        let line = format!("{what}: {e}");
        if !failed.1.contains(&line) && failed.1.len() < 6 {
            failed.1.push(line);
        }
        e
    }

    /// Why call `id`'s camera or picture would not start, a reason a line, in the host's own words, to read off the
    /// screen of a phone whose log cannot be reached. The camera's reasons are kept until it opens; the picture's for
    /// the whole call.
    pub fn errors(&self, id: u64) -> Option<String> {
        let failed = self.failed.lock().unwrap_or_else(|e| e.into_inner());
        (failed.0 == id && !failed.1.is_empty()).then(|| failed.1.join("\n"))
    }

    /// Open the camera again for call `id` if it is wanted there and stopped: a phone gives the camera back once the
    /// app is on the screen again. True when it was opened again.
    pub fn heal(&self, id: u64) -> bool {
        let _one = self.opening.lock().unwrap_or_else(|e| e.into_inner());
        let wanted = *self.wanted.lock().unwrap_or_else(|e| e.into_inner()) == Some(id);
        if !wanted || self.sending_to(id) {
            return false;
        }
        match self.start_sending(id) {
            Ok(()) => {
                tracing::info!("call {id}: the camera is back");
                true
            }
            Err(e) => {
                tracing::debug!("call {id}: the camera will not open again yet: {e}");
                false
            }
        }
    }

    fn start_sending(&self, id: u64) -> Result<(), String> {
        self.abort_sending();
        let cfg = SendConfig { codec: VideoCodec::H264, kind: VideoKind::Camera, camera: None, max: MAX, kbps: START_KBPS,
                               fps: FPS, encodings: vec![Encoding { id: EncodingId(0), max: MAX, kbps: START_KBPS }] };
        let mut source = self.host.start_send(cfg).map_err(|e| e.to_string())?;
        // it opened: why it would not before is no longer the call's to show (a phone refuses the camera to an app not
        // yet on the screen, and gives it a moment later)
        {
            let mut failed = self.failed.lock().unwrap_or_else(|e| e.into_inner());
            if failed.0 == id {
                failed.1.retain(|line| !line.starts_with("camera: "));
            }
        }
        let (feed, requests, counters) = (self.feed.clone(), self.requests_rx.clone(), self.counters.clone());
        let task = tokio::spawn(async move {
            let mut requests = requests.lock().await;
            while requests.try_recv().is_ok() {}
            let start = Instant::now();
            loop {
                tokio::select! {
                    frame = source.next_frame() => {
                        let Some((_, f)) = frame else {
                            tracing::warn!("call {id}: the camera stopped");
                            break;
                        };
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

    /// Stop the camera, until asked for again; the call's picture stays shown.
    pub fn stop_sending(&self) {
        let _one = self.opening.lock().unwrap_or_else(|e| e.into_inner());
        *self.wanted.lock().unwrap_or_else(|e| e.into_inner()) = None;
        self.abort_sending();
    }

    fn abort_sending(&self) {
        if let Some((_, t)) = self.sending.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
    }

    fn stop_showing(&self) {
        if let Some((_, t)) = self.showing.lock().unwrap_or_else(|e| e.into_inner()).take() {
            t.abort();
        }
    }

    /// Whether the camera sends to call `id`: started for it, and still giving pictures.
    pub fn sending_to(&self, id: u64) -> bool {
        self.sending.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(c, t)| *c == id && !t.is_finished())
    }

    /// Stop call `id`'s video, sent and shown.
    pub fn stop(&self, id: u64) {
        let ours = |c: &Option<u64>| *c == Some(id);
        if ours(&self.wanted.lock().unwrap_or_else(|e| e.into_inner()))
            || self.sending.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(c, _)| *c == id)
        {
            self.stop_sending();
        }
        if self.showing.lock().unwrap_or_else(|e| e.into_inner()).as_ref().is_some_and(|(c, _)| *c == id) {
            self.stop_showing();
            // its frames still on the way, not the next call's to show (once the aborted task lets go of them)
            let received = self.received.clone();
            if let Ok(rt) = tokio::runtime::Handle::try_current() {
                rt.spawn(async move {
                    let mut received = received.lock().await;
                    while received.try_recv().is_ok() {}
                });
            }
        }
    }

    /// Frames sent and received so far by the call holding the video.
    pub fn frames(&self) -> (u64, u64) {
        (self.counters.sent.load(Ordering::Relaxed), self.counters.received.load(Ordering::Relaxed))
    }

    /// Call `id`'s pictures so far, for its view. Where the host has no tiles (tests' synthetic host), what was
    /// captured and shown is what was sent and received.
    pub fn pictures(&self, id: u64) -> crate::state::CallPictures {
        let (sent, received) = self.frames();
        #[allow(unused_mut)]
        let (mut captured, mut shown) = (sent, received);
        #[cfg(any(target_os = "android", windows))]
        if let Some(tiles) = self.tiles() {
            let presented = |k| tiles.stats(k).map_or(0, |s| s.presented);
            captured = presented(anvil_video::TileKey::SelfView);
            shown = presented(anvil_video::TileKey::Stream(stream(id)));
        }
        let _ = id;
        crate::state::CallPictures { captured, sent, received, shown, stalled: None, report: None, errors: self.errors(id) }
    }
}

impl Video {
    /// What became of the frames call `id` received, for a picture that is not shown: what the leg gave (frames,
    /// keyframes, the first frame and the last keyframe with their size and NAL unit types), then, where the platform's host
    /// decodes, its sink's and its decoder's own accounts (anvil-video's `Received`).
    pub fn report(&self, id: u64) -> String {
        let c = &self.counters;
        let note = |m: &std::sync::Mutex<Option<String>>| m.lock().unwrap_or_else(|e| e.into_inner()).clone().unwrap_or_else(|| "none".into());
        #[allow(unused_mut)]
        let mut text = format!("leg: {} frames, {} keyframes; first frame {}; last keyframe {}", c.received.load(Ordering::Relaxed),
                               c.keyframes.load(Ordering::Relaxed), note(&c.first), note(&c.keyframe));
        #[cfg(any(target_os = "android", windows))]
        if let Some(tiles) = self.tiles() {
            match tiles.received(anvil_video::TileKey::Stream(stream(id))) {
                Some(r) => {
                    text += &format!("\nsink: {} frames, {} keyframes, {} waiting for a keyframe, {} failed, {} without a picture, {} pictures",
                                     r.frames, r.keyframes, r.skipped, r.failed, r.empty, r.pictures);
                    if let Some(e) = r.error {
                        text += &format!("\nlast error: {e}");
                    }
                    if let Some(d) = r.decoder {
                        text += &format!("\ndecoder: {d}");
                    }
                }
                None => text += "\nsink: none for this call",
            }
        }
        let _ = id;
        text
    }
}

/// The tile a call's picture is drawn on.
pub fn stream(id: u64) -> StreamId {
    StreamId(id as u32)
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicUsize;
    use std::time::Duration;

    use anvil_core::error::AnvilError;
    use anvil_core::video::host::{CameraInfo, VideoCodecCaps, VideoSink, VideoSource};
    use anvil_core::video::synthetic::SyntheticVideoHost;

    use super::*;

    /// The synthetic host whose first camera stops after a few frames, as a phone's does when it takes the camera
    /// away; the ones opened after go on.
    struct Taken {
        host: SyntheticVideoHost,
        opened: AtomicUsize,
    }

    struct Stops {
        source: Box<dyn VideoSource>,
        left: u32,
    }

    #[async_trait::async_trait]
    impl VideoSource for Stops {
        async fn next_frame(&mut self) -> Option<(EncodingId, CodedFrame)> {
            if self.left == 0 {
                return None;
            }
            self.left -= 1;
            self.source.next_frame().await
        }
        fn request_keyframe(&self) {
            self.source.request_keyframe();
        }
        fn set_target(&self, kbps: u32, max: Resolution, fps: u32) {
            self.source.set_target(kbps, max, fps);
        }
    }

    impl VideoHost for Taken {
        fn codecs(&self) -> Vec<VideoCodecCaps> {
            self.host.codecs()
        }
        fn cameras(&self) -> Vec<CameraInfo> {
            self.host.cameras()
        }
        fn start_send(&self, cfg: SendConfig) -> Result<Box<dyn VideoSource>, AnvilError> {
            let source = self.host.start_send(cfg)?;
            Ok(match self.opened.fetch_add(1, Ordering::Relaxed) {
                0 => Box::new(Stops { source, left: 3 }),
                _ => source,
            })
        }
        fn start_receive(&self, stream: StreamId, cfg: ReceiveConfig) -> Result<Box<dyn VideoSink>, AnvilError> {
            self.host.start_receive(stream, cfg)
        }
    }

    async fn until(what: &str, want: impl Fn() -> bool) {
        tokio::time::timeout(Duration::from_secs(10), async {
            while !want() {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{what}"));
    }

    #[tokio::test]
    async fn a_camera_taken_away_comes_back_until_turned_off() {
        let host = Arc::new(Taken { host: SyntheticVideoHost::new(&[VideoCodec::H264]), opened: AtomicUsize::new(0) });
        let video = Video::with_host(host.clone());
        video.send(1).unwrap();
        // asked again while it sends: the camera is not opened twice
        video.send(1).unwrap();
        assert_eq!(host.opened.load(Ordering::Relaxed), 1);
        until("the camera stops", || !video.sending_to(1)).await;
        assert!(!video.heal(2), "only the call it is wanted for");
        assert!(video.heal(1), "opened again");
        assert!(video.sending_to(1));
        assert_eq!(host.opened.load(Ordering::Relaxed), 2);
        assert_eq!(video.errors(1), None, "a camera taken away and back is no error");
        until("frames again", || video.frames().0 > 3).await;
        // turned off, it stays off
        video.stop_sending();
        assert!(!video.sending_to(1));
        assert!(!video.heal(1));
    }

    /// A host whose encoder will not start the first time.
    struct Refuses {
        host: SyntheticVideoHost,
        opened: AtomicUsize,
    }

    impl VideoHost for Refuses {
        fn codecs(&self) -> Vec<VideoCodecCaps> {
            self.host.codecs()
        }
        fn cameras(&self) -> Vec<CameraInfo> {
            self.host.cameras()
        }
        fn start_send(&self, cfg: SendConfig) -> Result<Box<dyn VideoSource>, AnvilError> {
            match self.opened.fetch_add(1, Ordering::Relaxed) {
                0 => Err(AnvilError::Codec("no encoder".into())),
                _ => self.host.start_send(cfg),
            }
        }
        fn start_receive(&self, stream: StreamId, cfg: ReceiveConfig) -> Result<Box<dyn VideoSink>, AnvilError> {
            self.host.start_receive(stream, cfg)
        }
    }

    #[tokio::test]
    async fn a_camera_that_would_not_start_is_said_for_its_call_until_it_does() {
        let video = Video::with_host(Arc::new(Refuses { host: SyntheticVideoHost::new(&[VideoCodec::H264]), opened: AtomicUsize::new(0) }));
        assert_eq!(video.errors(1), None);
        assert!(video.send(1).is_err());
        assert_eq!(video.errors(1).as_deref(), Some("camera: codec error: no encoder"));
        assert_eq!(video.pictures(1).errors.as_deref(), Some("camera: codec error: no encoder"));
        assert_eq!(video.errors(2), None, "for this call and no other");
        // the next try works: the camera is on, and what failed before is no longer said
        video.send(1).unwrap();
        assert!(video.sending_to(1));
        assert_eq!(video.errors(1), None);
        video.stop_sending();
    }

    /// A host whose camera takes a moment to open and, as a phone's does, fails an open made while another is under
    /// way.
    struct OneAtATime {
        host: SyntheticVideoHost,
        opening: AtomicUsize,
        opened: AtomicUsize,
    }

    impl VideoHost for OneAtATime {
        fn codecs(&self) -> Vec<VideoCodecCaps> {
            self.host.codecs()
        }
        fn cameras(&self) -> Vec<CameraInfo> {
            self.host.cameras()
        }
        fn start_send(&self, cfg: SendConfig) -> Result<Box<dyn VideoSource>, AnvilError> {
            let others = self.opening.fetch_add(1, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(200));
            let now = self.opening.fetch_sub(1, Ordering::SeqCst);
            if others > 0 || now > 1 {
                return Err(AnvilError::Codec("request: camera status -10000".into()));
            }
            self.opened.fetch_add(1, Ordering::SeqCst);
            self.host.start_send(cfg)
        }
        fn start_receive(&self, stream: StreamId, cfg: ReceiveConfig) -> Result<Box<dyn VideoSink>, AnvilError> {
            self.host.start_receive(stream, cfg)
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_camera_asked_for_twice_at_once_is_opened_once() {
        let host = Arc::new(OneAtATime { host: SyntheticVideoHost::new(&[VideoCodec::H264]), opening: AtomicUsize::new(0),
                                         opened: AtomicUsize::new(0) });
        let video = Arc::new(Video::with_host(host.clone()));
        // the call's own start and the screen's "camera on", together
        let asks: Vec<_> = (0..2).map(|_| { let v = video.clone(); tokio::task::spawn_blocking(move || v.send(1)) }).collect();
        for a in asks {
            a.await.unwrap().unwrap();
        }
        assert_eq!(host.opened.load(Ordering::SeqCst), 1, "opened once");
        assert!(video.sending_to(1));
        assert_eq!(video.errors(1), None, "neither ask failed");
        video.stop_sending();
    }

    /// The far end's camera: what the leg hands this side, first frame a keyframe.
    async fn far_frames(n: usize) -> Vec<VideoFrame> {
        let cfg = SendConfig { codec: VideoCodec::H264, kind: VideoKind::Camera, camera: None, max: MAX, kbps: START_KBPS,
                               fps: FPS, encodings: vec![Encoding { id: EncodingId(0), max: MAX, kbps: START_KBPS }] };
        let mut camera = SyntheticVideoHost::new(&[VideoCodec::H264]).start_send(cfg).unwrap();
        let mut frames = vec![];
        for _ in 0..n {
            let (_, f) = camera.next_frame().await.unwrap();
            frames.push(VideoFrame { data: f.data, keyframe: f.keyframe, timestamp: 0 });
        }
        frames
    }

    #[tokio::test]
    async fn a_call_is_shown_from_its_first_keyframe_however_late_it_is_shown() {
        let host = SyntheticVideoHost::new(&[VideoCodec::H264]);
        let video = Video::with_host(Arc::new(host.clone()));
        // the leg hands over the far end's first frames before the call's poll sees its video and shows it; its
        // keyframe among them: the far end sends the next only when asked, and nothing asks
        let frames = far_frames(8).await;
        for f in &frames[..5] {
            video.sink.send(f.clone()).unwrap();
        }
        video.show(1).unwrap();
        for f in &frames[5..] {
            video.sink.send(f.clone()).unwrap();
        }
        let shown = |id| host.record().received.get(&stream(id)).map(|s| s.frames.clone()).unwrap_or_default();
        until("all eight", || shown(1).len() == 8).await;
        assert!(shown(1)[0].1, "from the keyframe: {:?}", shown(1));
        // the call over with frames of it still queued: not the next call's to show
        video.stop_showing();
        for f in &frames[5..] {
            video.sink.send(f.clone()).unwrap();
        }
        // (its picture's task already gone, as an aborted one is, when `stop` comes)
        *video.showing.lock().unwrap() = Some((1, tokio::spawn(async {})));
        video.stop(1);
        tokio::time::sleep(Duration::from_millis(100)).await;
        video.show(2).unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(shown(2).is_empty(), "the last call's frames: {:?}", shown(2));
    }

    #[tokio::test]
    async fn a_picture_not_shown_is_accounted_for_from_the_frames_the_leg_gave() {
        let video = Video::with_host(Arc::new(SyntheticVideoHost::new(&[VideoCodec::H264])));
        video.show(1).unwrap();
        let frame = |keyframe, data: &[u8]| VideoFrame { data: data.to_vec().into(), keyframe, timestamp: 0 };
        video.sink.send(frame(true, &[0, 0, 0, 1, 0x67, 9, 0, 0, 0, 1, 0x68, 9, 0, 0, 1, 0x65, 9])).unwrap();
        video.sink.send(frame(false, &[0, 0, 0, 1, 0x41, 9])).unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(video.report(1), "leg: 2 frames, 1 keyframes; first frame 17 B, NALs [7 8 5], starts 0000000167; \
                                     last keyframe 17 B, NALs [7 8 5], starts 0000000167");
    }

    #[test]
    fn a_stage_that_stops_counting_is_where_the_picture_stops() {
        use crate::state::CallPictures;
        let at = |captured, sent, received, shown| CallPictures { captured, sent, received, shown, stalled: None, report: None, errors: None };
        assert_eq!(at(60, 60, 60, 60).stall(&at(30, 30, 30, 30), true), None);
        assert_eq!(at(0, 0, 60, 60).stall(&at(0, 0, 30, 30), true), Some("captured"));
        assert_eq!(at(60, 0, 60, 60).stall(&at(30, 0, 30, 30), true), Some("sent"));
        assert_eq!(at(60, 60, 60, 0).stall(&at(30, 30, 30, 0), true), Some("shown"));
        // the camera off, or the far end's: neither is a stall here
        assert_eq!(at(0, 0, 60, 60).stall(&at(0, 0, 30, 30), false), None);
        assert_eq!(at(60, 60, 30, 30).stall(&at(30, 30, 30, 30), true), None);
    }
}
