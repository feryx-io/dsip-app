//! Presence between two apps, each with its own mailbox, found through hints: Alice introduces herself, Bob accepts,
//! and the grant his phone issued (calls, messages and presence) reaches Alice through her mailbox. Her app hands it to
//! her phone and follows Bob, so his relay admits her: she sees his relay's claim, then the state he picks, then the
//! next. Bob, who holds no grant of hers, sees nothing of hers.
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
    let mut cfg = Config::new(net.identity(name), "wss://relay.invalid/dsip");
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
    tokio::time::sleep(Duration::from_millis(500)).await; // each has published its hint once bound

    let mut a_changes = alice.subscribe();
    assert_eq!(alice.command(Command::Introduce { to: bob_did.clone(), purpose: "hello".into() }).await, Response::Ok);
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

    // P§6: Bob holds no grant of Alice's: following her shows nothing
    assert_eq!(bob.command(Command::WatchPresence { identity: alice_did.clone() }).await, Response::Ok);
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert_eq!(shown(&bob, &alice_did).and_then(|p| p.state), None);

    assert!(matches!(bob.command(Command::SetPresence { state: Some("asleep".into()) }).await, Response::Error { .. }));
    assert_eq!(alice.command(Command::UnwatchPresence { identity: bob_did.clone() }).await, Response::Ok);
    assert!(shown(&alice, &bob_did).is_none());
    alice.stop().await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
