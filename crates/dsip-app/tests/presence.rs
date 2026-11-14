//! Presence between two apps, each with its own mailbox, found through hints: Alice introduces herself, Bob accepts,
//! and the grant his phone issued (calls, messages and presence) reaches Alice through her mailbox. Her app hands it to
//! her phone and follows Bob, so his relay admits her: she sees his relay's claim, then the state he picks, then the
//! next. Accepting introduces Bob to Alice in turn, which her app accepts by itself (she asked first): he follows her
//! too.
#![cfg(target_os = "linux")]

use std::path::Path;
use std::time::Duration;

use dsip_app::{App, Change, Command, Config, MessagingConfig, PresenceView, Response};
use dsip_mailbox::{MailboxConfig, MailboxServer};
use dsip_testkit::Network;

/// A mailbox enrolling identities that bind, on 127.0.0.1 under the shared test certificate.
async fn mailbox(dir: &Path, name: &str, tls: &tokio_rustls::TlsAcceptor, hints: &str) -> (String, String) {
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    let mut cfg = MailboxConfig::new(dir.join(name), format!("https://127.0.0.1:{port}/blobs"));
    cfg.serve_any = Some(4);
    cfg.hints_nodes = vec![hints.to_string()];
    cfg.ca = Some(dir.join("cert.pem"));
    let server = MailboxServer::open(cfg).unwrap();
    server.spawn_tasks();
    let did = server.did().to_string();
    let acceptor = tls.clone();
    tokio::spawn(async move { server.serve_tls(tcp, acceptor).await });
    (did, format!("wss://127.0.0.1:{port}/dsip"))
}

async fn app(net: &Network, dir: &Path, name: &str, mailbox: (String, String), hints: &str) -> App {
    app_as(net, net.identity(name), dir, name, mailbox, hints).await
}

async fn app_as(net: &Network, identity: dsip_phone::Identity, dir: &Path, name: &str, mailbox: (String, String), hints: &str) -> App {
    let mut cfg = Config::new(identity, "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    cfg.messaging = Some(MessagingConfig {
        mailbox,
        hints_nodes: vec![hints.into()],
        ca: Some(dir.join("cert.pem")),
        state_dir: dir.join(format!("{name}-messaging")),
        fetch_did_web: false,
    });
    App::start(cfg).await.expect("the app starts")
}

async fn until(app: &App, what: &str, want: impl Fn(&dsip_app::State) -> bool) {
    tokio::time::timeout(Duration::from_secs(20), async {
        while !want(&app.state()) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().presence));
}

fn shown(app: &App, identity: &str) -> Option<PresenceView> {
    app.state().presence.following.into_iter().find(|p| p.identity == identity)
}

/// Each of `apps` once its hint (with its mailbox) is on the hints node and verifies there: an introduction finds the
/// other's mailbox through it. A fixed wait raced the publishing (seen in CI).
async fn hints_published(hints: &str, apps: &[&App]) {
    let client = dsip_transport::hints::HintsClient::new(vec![hints.to_string()], None).expect("a hints client");
    for app in apps {
        let did = app.state().me.identity;
        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let now = dsip_transport::now_s();
                if client.lookup(&did, &dsip_core::did::StaticResolver::default(), now).await.is_some() {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{did}'s hint never reached the hints node"));
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn accepting_an_introduction_shares_presence_with_the_one_who_asked() {
    let dir = std::env::temp_dir().join(format!("dsip-app-presence-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", mailbox(&dir, "mailbox-a", &tls, &hints).await, &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let (alice_did, bob_did) = (alice.state().me.identity, bob.state().me.identity);
    for (who, a) in [("Alice", &alice), ("Bob", &bob)] {
        until(a, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    hints_published(&hints, &[&alice, &bob]).await;

    let mut a_changes = alice.subscribe();
    assert_eq!(alice.command(Command::Introduce { to: bob_did.clone(), purpose: "hello".into(), name: None }).await, Response::Ok);
    until(&bob, "Bob sees the request", |s| !s.messaging.requests.is_empty()).await;
    let id = bob.state().messaging.requests[0].id.clone();
    assert_eq!(bob.command(Command::AcceptRequest { id }).await, Response::Ok);
    tokio::time::timeout(Duration::from_secs(20), async {
        while !matches!(a_changes.recv().await, Ok(Change::Granted { by }) if by == bob_did) {}
    })
    .await
    .expect("Alice's grant");

    // the grant shares presence: Alice follows Bob, and his relay says he is there (§9.3)
    until(&alice, "Bob's relay's claim", |_| shown(&alice, &bob_did).is_some_and(|p| p.source.as_deref() == Some("assertion"))).await;
    assert_eq!(shown(&alice, &bob_did).unwrap().state.as_deref(), Some("available"));

    // P§3: the state Bob picks, signed by his device
    assert_eq!(bob.command(Command::SetPresence { state: Some("busy".into()) }).await, Response::Ok);
    assert_eq!(bob.state().presence.mine.as_deref(), Some("busy"));
    until(&alice, "Bob busy", |_| shown(&alice, &bob_did).is_some_and(|p| p.state.as_deref() == Some("busy") && p.source.as_deref() == Some("record"))).await;
    // P§8: a change within the publish interval is held back, then sent
    assert_eq!(bob.command(Command::SetPresence { state: Some("dnd".into()) }).await, Response::Ok);
    until(&alice, "Bob dnd", |_| shown(&alice, &bob_did).is_some_and(|p| p.state.as_deref() == Some("dnd"))).await;

    // and the other way: Bob's app introduced him back, Alice's accepted it by itself, and he follows her (P§6)
    until(&bob, "Bob holds Alice's grant", |s| s.messaging.introduced.iter().any(|i| i.to == alice_did && i.accepted)).await;
    assert!(alice.state().messaging.requests.is_empty(), "accepted by itself, never left waiting");
    assert_eq!(alice.state().names.get(&bob_did).map(String::as_str), Some("Bob"), "Bob is Alice's contact, by his name");
    assert_eq!(alice.command(Command::SetPresence { state: Some("away".into()) }).await, Response::Ok);
    until(&bob, "Alice away", |_| shown(&bob, &alice_did).is_some_and(|p| p.state.as_deref() == Some("away"))).await;
    // no further round: each holds the other's grant, and neither introduces itself again
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert!(alice.state().messaging.requests.is_empty() && bob.state().messaging.requests.is_empty());
    assert_eq!(alice.state().messaging.introduced.len(), 1);
    assert_eq!(bob.state().messaging.introduced.len(), 1);

    assert!(matches!(bob.command(Command::SetPresence { state: Some("asleep".into()) }).await, Response::Error { .. }));
    assert_eq!(alice.command(Command::UnwatchPresence { identity: bob_did.clone() }).await, Response::Ok);
    assert!(shown(&alice, &bob_did).is_none());
    alice.stop().await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// Introduce `from` to `to`, accept it there, and wait for the grant to reach `from`.
async fn granted(from: &App, to: &App) {
    let to_did = to.state().me.identity;
    let mut changes = from.subscribe();
    assert_eq!(from.command(Command::Introduce { to: to_did.clone(), purpose: "hello".into(), name: None }).await, Response::Ok);
    let me = from.state().me.identity;
    until(to, "the request", |s| s.messaging.requests.iter().any(|r| r.from == me)).await;
    let id = to.state().messaging.requests.iter().find(|r| r.from == me).unwrap().id.clone();
    assert_eq!(to.command(Command::AcceptRequest { id }).await, Response::Ok);
    tokio::time::timeout(Duration::from_secs(20), async {
        while !matches!(changes.recv().await, Ok(Change::Granted { by }) if by == to_did) {}
    })
    .await
    .expect("the grant");
}

#[tokio::test(flavor = "multi_thread")]
async fn revoking_a_grant_sends_the_others_new_keys_through_their_mailboxes() {
    let dir = std::env::temp_dir().join(format!("dsip-app-sealed-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", mailbox(&dir, "mailbox-a", &tls, &hints).await, &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let carol = app(&net, &dir, "Carol", mailbox(&dir, "mailbox-c", &tls, &hints).await, &hints).await;
    let (bob_did, carol_did) = (bob.state().me.identity, carol.state().me.identity);
    for (who, a) in [("Alice", &alice), ("Bob", &bob), ("Carol", &carol)] {
        until(a, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    hints_published(&hints, &[&alice, &bob, &carol]).await;
    granted(&alice, &bob).await;
    granted(&carol, &bob).await;

    // P§12.3: Bob's record is sealed; the keys his grants carried open it for both
    assert_eq!(bob.command(Command::SetPresence { state: Some("busy".into()) }).await, Response::Ok);
    for (who, a) in [("Alice", &alice), ("Carol", &carol)] {
        until(a, &format!("{who} reads Bob busy"), |_| {
            shown(a, &bob_did).is_some_and(|p| p.state.as_deref() == Some("busy") && p.source.as_deref() == Some("record") && p.unreadable == 0)
        })
        .await;
    }

    // P§12.5: withdrawing Carol's grant rotates the keys; Alice's new grant is deposited at her mailbox
    let mut a_changes = alice.subscribe();
    assert_eq!(bob.command(Command::RevokeGrants { identity: carol_did.clone() }).await, Response::Revoked { count: 1 });
    tokio::time::timeout(Duration::from_secs(20), async {
        while !matches!(a_changes.recv().await, Ok(Change::Granted { by }) if by == bob_did) {}
    })
    .await
    .expect("Alice's grant with the new keys, at her mailbox");
    assert_eq!(bob.command(Command::SetPresence { state: Some("away".into()) }).await, Response::Ok);
    until(&alice, "Alice reads Bob away", |_| shown(&alice, &bob_did).is_some_and(|p| p.state.as_deref() == Some("away") && p.unreadable == 0)).await;
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert_ne!(shown(&carol, &bob_did).and_then(|p| p.state).as_deref(), Some("away"), "Carol no longer reads Bob");
    assert_eq!(bob.command(Command::RevokeGrants { identity: carol_did }).await, Response::Revoked { count: 0 });
    for a in [&alice, &bob, &carol] {
        a.stop().await;
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn following_resumes_when_the_app_starts_again() {
    let dir = std::env::temp_dir().join(format!("dsip-app-resume-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice_id = net.identity("Alice");
    let alice_dir = alice_id.dir.clone();
    let alice_mailbox = mailbox(&dir, "mailbox-a", &tls, &hints).await;
    let alice = app_as(&net, alice_id, &dir, "Alice", alice_mailbox.clone(), &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let carol = app(&net, &dir, "Carol", mailbox(&dir, "mailbox-c", &tls, &hints).await, &hints).await;
    let (bob_did, carol_did) = (bob.state().me.identity, carol.state().me.identity);
    for (who, a) in [("Alice", &alice), ("Bob", &bob), ("Carol", &carol)] {
        until(a, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    hints_published(&hints, &[&alice, &bob, &carol]).await;
    granted(&alice, &bob).await;
    granted(&alice, &carol).await;
    assert_eq!(bob.command(Command::SetPresence { state: Some("busy".into()) }).await, Response::Ok);
    until(&alice, "Bob busy", |_| shown(&alice, &bob_did).is_some_and(|p| p.state.as_deref() == Some("busy"))).await;
    // unfollowed, Carol is not followed again
    assert_eq!(alice.command(Command::UnwatchPresence { identity: carol_did.clone() }).await, Response::Ok);
    alice.stop().await;

    // the same identity, started again: it follows Bob, with the grant its phone kept, and reads his sealed record
    let alice = app_as(&net, dsip_phone::Identity::load(&alice_dir).unwrap(), &dir, "Alice", alice_mailbox, &hints).await;
    until(&alice, "Bob busy, after the restart", |_| {
        shown(&alice, &bob_did).is_some_and(|p| p.state.as_deref() == Some("busy") && p.source.as_deref() == Some("record"))
    })
    .await;
    assert!(shown(&alice, &carol_did).is_none(), "{:?}", alice.state().presence);
    for a in [&alice, &bob, &carol] {
        a.stop().await;
    }
    let _ = std::fs::remove_dir_all(&dir);
}

/// Found on devices: with presence automatic, a call showed neither side as on a call. Now each says `busy` while the
/// call is up, and `available` once it is over; a state the user chose is left as chosen.
#[tokio::test(flavor = "multi_thread")]
async fn on_automatic_a_call_shows_both_busy_until_it_ends() {
    let dir = std::env::temp_dir().join(format!("dsip-app-auto-busy-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", mailbox(&dir, "mailbox-a", &tls, &hints).await, &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let (alice_did, bob_did) = (alice.state().me.identity, bob.state().me.identity);
    for (who, a) in [("Alice", &alice), ("Bob", &bob)] {
        until(a, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    hints_published(&hints, &[&alice, &bob]).await;
    granted(&alice, &bob).await;
    until(&bob, "Bob holds Alice's grant", |s| s.messaging.introduced.iter().any(|i| i.to == alice_did && i.accepted)).await;
    let is = |app: &App, who: &str, state: &str| shown(app, who).is_some_and(|p| p.state.as_deref() == Some(state));
    until(&alice, "Bob there", |_| is(&alice, &bob_did, "available")).await;
    until(&bob, "Alice there", |_| is(&bob, &alice_did, "available")).await;

    let call = |r: Response| match r {
        Response::Call { call } => call,
        other => panic!("not a call: {other:?}"),
    };
    call(alice.command(Command::Call { to: bob_did.clone(), video: false }).await);
    until(&bob, "Bob's call rings", |s| s.calls.values().any(|c| c.state == dsip_app::CallState::Ringing)).await;
    call(bob.command(Command::Answer { call: None }).await);
    until(&alice, "Bob on a call", |_| is(&alice, &bob_did, "busy")).await;
    until(&bob, "Alice on a call", |_| is(&bob, &alice_did, "busy")).await;
    assert_eq!((alice.state().presence.mine, bob.state().presence.mine), (None, None), "still automatic");

    // P§8: hung up within the publish interval, the end is still told
    call(alice.command(Command::Hangup { call: None }).await);
    until(&alice, "Bob off the call", |_| is(&alice, &bob_did, "available")).await;
    until(&bob, "Alice off the call", |_| is(&bob, &alice_did, "available")).await;

    // a state Bob chose stays through a call
    assert_eq!(bob.command(Command::SetPresence { state: Some("dnd".into()) }).await, Response::Ok);
    until(&alice, "Bob dnd", |_| is(&alice, &bob_did, "dnd")).await;
    call(alice.command(Command::Call { to: bob_did.clone(), video: false }).await);
    until(&bob, "Bob's call rings", |s| s.calls.values().any(|c| c.state == dsip_app::CallState::Ringing)).await;
    call(bob.command(Command::Answer { call: None }).await);
    until(&bob, "Alice on a call", |_| is(&bob, &alice_did, "busy")).await;
    tokio::time::sleep(Duration::from_secs(7)).await;
    assert!(is(&alice, &bob_did, "dnd"), "Bob's own choice stands");
    call(alice.command(Command::Hangup { call: None }).await);
    alice.stop().await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
