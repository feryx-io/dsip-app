//! Two apps on one in-process relay with the tone host for sound and the synthetic video host (numbered H.264
//! frames, no camera or codec): a video call carries frames both ways through the call's leg; a plain call between
//! the same apps carries none.

use std::time::Duration;

use dsip_app::{App, CallState, Command, Config, HostKind, Response};
use dsip_testkit::Network;

async fn app(net: &Network, name: &str) -> App {
    let mut cfg = Config::new(net.identity(name), "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = Some(HostKind::Tone);
    cfg.video = Some(HostKind::Tone);
    App::start(cfg).await.expect("the app starts")
}

async fn until(what: &str, want: impl Fn() -> bool) {
    tokio::time::timeout(Duration::from_secs(20), async {
        while !want() {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what}"));
}

fn call_of(r: Response) -> u64 {
    match r {
        Response::Call { call } => call,
        other => panic!("not a call: {other:?}"),
    }
}

fn answered(app: &App) -> bool {
    app.state().calls.values().any(|c| matches!(c.state, CallState::Answered { .. }))
}

#[tokio::test(flavor = "multi_thread")]
async fn a_video_call_carries_frames_both_ways() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    assert!(alice.video_frames().is_some(), "the synthetic host gives the app video");
    let id = call_of(alice.command(Command::Call { to: bob.state().me.identity, video: true }).await);
    until("Bob's call rings", || bob.state().calls.values().any(|c| c.state == CallState::Ringing)).await;
    call_of(bob.command(Command::Answer { call: None }).await);
    until("answered", || answered(&alice) && answered(&bob)).await;
    // both views say video, and each camera's frames reach the other's decoder
    until("a video call on both sides", || alice.state().calls[&id].video && bob.state().calls.values().any(|c| c.video)).await;
    until("frames both ways", || {
        let (a, b) = (alice.video_frames().unwrap(), bob.video_frames().unwrap());
        a.0 >= 10 && a.1 >= 10 && b.0 >= 10 && b.1 >= 10
    })
    .await;
    assert!(alice.state().calls[&id].camera, "a video call's camera starts with it");
    // the camera off: Alice's view says so, and her frames stop
    assert_eq!(alice.command(Command::Camera { call: Some(id), on: false }).await, Response::Ok);
    assert!(!alice.state().calls[&id].camera);
    tokio::time::sleep(Duration::from_millis(300)).await;
    let sent = alice.video_frames().unwrap().0;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(alice.video_frames().unwrap().0, sent, "no frames with the camera off");
    // and on again
    assert_eq!(alice.command(Command::Camera { call: None, on: true }).await, Response::Ok);
    until("frames again", || alice.video_frames().unwrap().0 >= 5).await;
    alice.command(Command::Hangup { call: Some(id) }).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_plain_call_carries_no_video() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    let id = call_of(alice.command(Command::Call { to: bob.state().me.identity, video: false }).await);
    until("Bob's call rings", || bob.state().calls.values().any(|c| c.state == CallState::Ringing)).await;
    call_of(bob.command(Command::Answer { call: None }).await);
    until("answered and heard", || answered(&alice) && answered(&bob) && alice.state().calls[&id].media).await;
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert!(!alice.state().calls[&id].video, "an audio call is not a video one");
    assert_eq!(alice.video_frames(), Some((0, 0)), "no camera, nothing received");
    assert_eq!(bob.video_frames(), Some((0, 0)));
    assert!(matches!(alice.command(Command::Camera { call: Some(id), on: true }).await, Response::Error { .. }),
            "no camera in an audio call");
    alice.command(Command::Hangup { call: Some(id) }).await;
}
