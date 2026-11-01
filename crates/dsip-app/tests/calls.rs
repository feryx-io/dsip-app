//! Two apps on one in-process relay (`dsip-testkit`), each with the tone host for its devices: Alice calls Bob, Bob's
//! app rings, Bob answers by command, each side's tone reaches the other's speaker through Opus and the call's
//! WebRTC leg, and the hang-up ends both. The control socket drives the same app.

use std::time::Duration;

use dsip_app::{App, CallState, Change, Command, Config, Direction, HostKind, Response};
use dsip_testkit::Network;

async fn app(net: &Network, name: &str) -> App {
    let mut cfg = Config::new(net.identity(name), "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = Some(HostKind::Tone);
    App::start(cfg).await.expect("the app starts")
}

/// Wait until `app`'s state satisfies `want`.
async fn until(app: &App, what: &str, want: impl Fn(&dsip_app::State) -> bool) {
    tokio::time::timeout(Duration::from_secs(15), async {
        while !want(&app.state()) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().calls));
}

fn call_of(r: Response) -> u64 {
    match r {
        Response::Call { call } => call,
        other => panic!("not a call: {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_call_rings_is_answered_carries_sound_both_ways_and_hangs_up() {
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    let mut bob_changes = bob.subscribe();
    let id = call_of(alice.command(Command::Call { to: bob.state().me.identity }).await);

    // Bob's app rings: the call is added, incoming, from Alice
    let added = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if let Ok(Change::CallAdded { call }) = bob_changes.recv().await {
                return call;
            }
        }
    })
    .await
    .expect("Bob's app was told of the call");
    assert_eq!((added.direction, added.peer.as_str()), (Direction::Incoming, alice.state().me.identity.as_str()));
    until(&bob, "Bob's call rings", |s| s.calls.values().any(|c| c.state == CallState::Ringing)).await;
    until(&alice, "Alice hears it ring", |s| s.calls[&id].state == CallState::Ringing).await;

    // answered by command, the one ringing (no id given)
    call_of(bob.command(Command::Answer { call: None }).await);
    let answered = |s: &dsip_app::State| s.calls.values().any(|c| matches!(c.state, CallState::Answered { .. }));
    until(&alice, "answered at Alice", answered).await;
    until(&bob, "answered at Bob", answered).await;

    // each side's tone reaches the other's speaker
    for (who, a) in [("Alice", &alice), ("Bob", &bob)] {
        tokio::time::timeout(Duration::from_secs(15), async {
            loop {
                let (frames, peak) = a.tone_heard().unwrap();
                if frames > 25 && peak > 0.05 {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{who} heard nothing: {:?}", a.tone_heard()));
        until(a, "media flag", |s| s.calls.values().any(|c| c.media)).await;
    }

    // mute shows in the state
    call_of(alice.command(Command::Mute { call: Some(id) }).await);
    assert!(alice.state().calls[&id].muted);

    // Alice hangs up; both end
    call_of(alice.command(Command::Hangup { call: None }).await);
    until(&alice, "ended at Alice", |s| s.calls[&id].state.ended()).await;
    until(&bob, "ended at Bob", |s| s.calls.values().all(|c| c.state.ended())).await;
    assert!(matches!(alice.command(Command::Hangup { call: None }).await, Response::Error { .. }), "nothing left to hang up");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_declined_call_ends_at_the_caller() {
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    let id = call_of(alice.command(Command::Call { to: bob.state().me.identity }).await);
    until(&bob, "Bob's call rings", |s| s.calls.values().any(|c| c.state == CallState::Ringing)).await;
    call_of(bob.command(Command::Decline { call: None }).await);
    until(&alice, "declined at Alice", |s| s.calls[&id].state.ended()).await;
    let CallState::Ended { reason } = &alice.state().calls[&id].state else { unreachable!() };
    assert!(reason.starts_with("user."), "{reason}");
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn the_control_socket_drives_the_same_app() {
    let net = Network::new();
    let (alice, bob) = (app(&net, "Alice").await, app(&net, "Bob").await);
    let dir = std::env::temp_dir().join(format!("dsip-app-control-{}", std::process::id()));
    let path = dir.join("control.sock");
    let served = alice.clone();
    let p = path.clone();
    let server = tokio::spawn(async move { dsip_app::control::serve(served, &p).await });
    tokio::time::timeout(Duration::from_secs(5), async {
        while !path.exists() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .unwrap();
    use std::os::unix::fs::PermissionsExt;
    assert_eq!(std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777, 0o700, "the directory is the user's alone");

    let Response::State { state } = dsip_app::control::request(&path, &Command::State).await.unwrap() else { panic!() };
    assert_eq!(state.me.identity, alice.state().me.identity);

    // a watcher sees the state, then the call it places through the socket
    let watch_path = path.clone();
    let watcher = tokio::spawn(async move {
        let mut lines = vec![];
        dsip_app::control::watch(&watch_path, |l| {
            lines.push(l.to_string());
            !l.contains("call_added")
        })
        .await
        .unwrap();
        lines
    });
    tokio::time::sleep(Duration::from_millis(200)).await;
    let r = dsip_app::control::request(&path, &Command::Call { to: bob.state().me.identity }).await.unwrap();
    assert!(matches!(r, Response::Call { .. }), "{r:?}");
    let lines = tokio::time::timeout(Duration::from_secs(10), watcher).await.unwrap().unwrap();
    assert!(lines[0].contains("\"response\":\"state\""), "{lines:?}");
    assert!(lines.last().unwrap().contains("\"direction\":\"outgoing\""), "{lines:?}");

    let r = dsip_app::control::request(&path, &Command::Answer { call: None }).await.unwrap();
    assert!(matches!(r, Response::Error { .. }), "nothing rings at Alice: {r:?}");
    assert!(matches!(dsip_app::control::request(&path, &Command::Quit).await.unwrap(), Response::Ok));
    tokio::time::timeout(Duration::from_secs(10), server).await.unwrap().unwrap().unwrap();
    assert!(!path.exists(), "the socket is removed when the app stops");
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_call_to_someone_on_another_relay_goes_through_theirs_and_carries_sound() {
    // §8.1: each app publishes its hint naming its relay; Alice's finds Bob's, and the call goes through his relay
    let (mine, theirs) = (Network::new(), Network::new());
    let node = dsip_testkit::hints_node().await;
    let start = |net: &Network, name: &str| {
        let mut cfg = Config::new(net.identity(name), net.url());
        cfg.dialer = Some(net.dialer());
        cfg.audio = Some(HostKind::Tone);
        cfg.hints = Some(dsip_transport::hints::HintsClient::new(vec![node.clone()], None).unwrap());
        cfg.peer_dialer = Some(Network::peers(&[&mine, &theirs]));
        App::start(cfg)
    };
    let alice = start(&mine, "Alice").await.unwrap();
    let bob = start(&theirs, "Bob").await.unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await; // each has published its hint

    let id = call_of(alice.command(Command::Call { to: bob.state().me.identity }).await);
    assert_eq!(alice.state().calls[&id].via.as_deref(), Some(theirs.url()), "through Bob's relay");
    until(&bob, "Bob's call rings", |s| s.calls.values().any(|c| c.state == CallState::Ringing)).await;
    call_of(bob.command(Command::Answer { call: None }).await);
    until(&alice, "answered at Alice", |s| matches!(s.calls[&id].state, CallState::Answered { .. })).await;
    for (who, a) in [("Alice", &alice), ("Bob", &bob)] {
        tokio::time::timeout(Duration::from_secs(15), async {
            while !a.tone_heard().is_some_and(|(frames, peak)| frames > 25 && peak > 0.05) {
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{who} heard nothing: {:?}", a.tone_heard()));
    }
    call_of(alice.command(Command::Hangup { call: Some(id) }).await);
    until(&bob, "ended at Bob", |s| s.calls.values().all(|c| c.state.ended())).await;
}
