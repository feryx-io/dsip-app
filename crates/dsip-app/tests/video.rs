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
    let far = |app: &App| app.state().calls.values().any(|c| c.far_video);
    until("each sees the other's pictures come in", || far(&alice) && far(&bob)).await;
    // the camera off: Alice's view says so, and her frames stop
    assert_eq!(alice.command(Command::Camera { call: Some(id), on: false }).await, Response::Ok);
    assert!(!alice.state().calls[&id].camera);
    tokio::time::sleep(Duration::from_millis(300)).await;
    let sent = alice.video_frames().unwrap().0;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(alice.video_frames().unwrap().0, sent, "no frames with the camera off");
    // Bob's view says her pictures stopped coming (a screen shows none, not the last one); his still reach her
    until("Bob sees Alice's pictures stop", || !far(&bob)).await;
    assert!(far(&alice));
    // and on again
    assert_eq!(alice.command(Command::Camera { call: None, on: true }).await, Response::Ok);
    until("frames again", || alice.video_frames().unwrap().0 >= sent + 5).await;
    until("Bob sees Alice's pictures again", || far(&bob)).await;
    // the pictures' counters on the call's view, nothing stalled
    until("the pictures counted", || {
        alice.state().calls[&id].pictures.as_ref().is_some_and(|p| p.sent > 0 && p.received > 0 && p.stalled.is_none())
    })
    .await;
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
    until("the call in both histories", || alice.state().history.len() == 1 && bob.state().history.len() == 1).await;
    assert!(!alice.state().history[0].video && !bob.state().history[0].video, "kept as an audio call");
}

/// The camera's frames reach every video call, not only the first: a call over lets go of the camera's feed (dsip-media
/// 0.2.1). Seen on devices: after the first video call, each side saw its own camera, neither the other's.
#[tokio::test(flavor = "multi_thread")]
async fn a_second_video_call_carries_frames_too() {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    for round in 1..=2 {
        let id = call_of(alice.command(Command::Call { to: bob.state().me.identity, video: true }).await);
        until("Bob's call rings", || bob.state().calls.values().any(|c| c.state == CallState::Ringing)).await;
        call_of(bob.command(Command::Answer { call: None }).await);
        until("answered", || answered(&alice) && answered(&bob)).await;
        let (a0, b0) = (alice.video_frames().unwrap(), bob.video_frames().unwrap());
        until(&format!("call {round}: frames both ways"), || {
            let (a, b) = (alice.video_frames().unwrap(), bob.video_frames().unwrap());
            a.1 >= a0.1 + 10 && b.1 >= b0.1 + 10
        })
        .await;
        alice.command(Command::Hangup { call: Some(id) }).await;
        until("both ended", || !answered(&alice) && !answered(&bob)).await;
    }
    // kept as video calls, where they were placed and where they were answered
    until("both calls in both histories", || alice.state().history.len() == 2 && bob.state().history.len() == 2).await;
    assert!(alice.state().history.iter().chain(&bob.state().history).all(|c| c.video));
}
