//! A group conversation between apps, each identity with its own mailbox, found through hints: Alice makes one with
//! Bob and Carol, who granted her (M§14.2), and each reads what the others send; she adds Dave and removes Carol, and
//! Bob leaves (M§7.3).
#![cfg(target_os = "linux")]

use std::path::Path;
use std::time::Duration;

use dsip_app::{App, Change, Command, Config, MessagingConfig, Response};
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

async fn app(net: &Network, dir: &Path, name: &str, tls: &tokio_rustls::TlsAcceptor, hints: &str) -> App {
    let mut cfg = Config::new(net.identity(name), "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    cfg.messaging = Some(MessagingConfig {
        mailbox: mailbox(dir, &format!("mailbox-{name}"), tls, hints).await,
        hints_nodes: vec![hints.into()],
        ca: Some(dir.join("cert.pem")),
        state_dir: dir.join(format!("{name}-messaging")),
        fetch_did_web: false,
    });
    App::start(cfg).await.expect("the app starts")
}

async fn until(app: &App, what: &str, want: impl Fn(&dsip_app::State) -> bool) {
    tokio::time::timeout(Duration::from_secs(30), async {
        while !want(&app.state()) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().messaging));
}

/// `from` introduces itself to `to`, which accepts; the grant reaches `from`.
async fn granted(from: &App, to: &App) {
    let to_did = to.state().me.identity;
    let mut changes = from.subscribe();
    assert_eq!(from.command(Command::Introduce { to: to_did.clone(), purpose: "hello".into() }).await, Response::Ok);
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

/// The members `app` lists for the group `gid`, sorted; `None` while it lists no such conversation.
fn members(app: &App, gid: &str) -> Option<Vec<String>> {
    app.state().messaging.conversations.into_iter().find(|c| c.group == gid).map(|c| {
        assert_eq!(c.kind, "group");
        c.members
    })
}

fn sorted(ids: &[&str]) -> Vec<String> {
    let mut v: Vec<String> = ids.iter().map(|s| s.to_string()).collect();
    v.sort();
    v
}

/// Wait for a text in `gid` on `app`'s change stream.
async fn hears(rx: &mut tokio::sync::broadcast::Receiver<Change>, who: &str, gid: &str, text: &str) {
    tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            if let Ok(Change::Message { message }) = rx.recv().await {
                if message.conversation == gid && message.text.as_deref() == Some(text) {
                    return;
                }
            }
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{who} never heard {text:?}"));
}

#[tokio::test(flavor = "multi_thread")]
async fn a_group_made_grown_shrunk_and_left() {
    let dir = std::env::temp_dir().join(format!("dsip-app-groups-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", &tls, &hints).await;
    let bob = app(&net, &dir, "Bob", &tls, &hints).await;
    let carol = app(&net, &dir, "Carol", &tls, &hints).await;
    let dave = app(&net, &dir, "Dave", &tls, &hints).await;
    let [a, b, c, d] = [&alice, &bob, &carol, &dave].map(|x| x.state().me.identity);
    for (who, x) in [("Alice", &alice), ("Bob", &bob), ("Carol", &carol), ("Dave", &dave)] {
        until(x, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    tokio::time::sleep(Duration::from_millis(500)).await; // each has published its hint once bound
    for x in [&bob, &carol, &dave] {
        granted(&alice, x).await;
    }

    // M§7.3: the group, with Bob and Carol, hubbed at Alice's mailbox
    let Response::Conversation { conversation: gid } = alice.command(Command::CreateGroup { members: vec![b.clone(), c.clone()] }).await else {
        panic!("no group")
    };
    for (who, x) in [("Alice", &alice), ("Bob", &bob), ("Carol", &carol)] {
        until(x, &format!("{who} lists the group of three"), |_| members(x, &gid) == Some(sorted(&[&a, &b, &c]))).await;
    }
    let (mut b_rx, mut c_rx, mut a_rx) = (bob.subscribe(), carol.subscribe(), alice.subscribe());
    assert_eq!(alice.command(Command::Message { to: gid.clone(), text: "hello, both".into() }).await, Response::Conversation { conversation: gid.clone() });
    hears(&mut b_rx, "Bob", &gid, "hello, both").await;
    hears(&mut c_rx, "Carol", &gid, "hello, both").await;
    assert_eq!(bob.command(Command::Message { to: gid.clone(), text: "hi from Bob".into() }).await, Response::Conversation { conversation: gid.clone() });
    hears(&mut a_rx, "Alice", &gid, "hi from Bob").await;
    hears(&mut c_rx, "Carol", &gid, "hi from Bob").await;

    // any member adds another it holds a grant from
    assert_eq!(alice.command(Command::AddMember { conversation: gid.clone(), identity: d.clone() }).await, Response::Ok);
    until(&dave, "Dave lists the group of four", |_| members(&dave, &gid) == Some(sorted(&[&a, &b, &c, &d]))).await;
    assert!(matches!(alice.command(Command::AddMember { conversation: gid.clone(), identity: d.clone() }).await, Response::Error { .. }));
    let mut d_rx = dave.subscribe();
    assert_eq!(carol.command(Command::Message { to: gid.clone(), text: "welcome, Dave".into() }).await, Response::Conversation { conversation: gid.clone() });
    hears(&mut d_rx, "Dave", &gid, "welcome, Dave").await;

    // and removes one: every device of it; Carol is told, and no longer lists it
    let mut c_rx = carol.subscribe();
    assert_eq!(alice.command(Command::RemoveMember { conversation: gid.clone(), identity: c.clone() }).await, Response::Ok);
    let by = tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            if let Ok(Change::Removed { conversation, by }) = c_rx.recv().await {
                if conversation == gid {
                    return by;
                }
            }
        }
    })
    .await
    .expect("Carol told she was removed");
    assert_eq!(by, a);
    until(&carol, "Carol no longer lists the group", |_| members(&carol, &gid).is_none()).await;
    for (who, x) in [("Alice", &alice), ("Bob", &bob), ("Dave", &dave)] {
        until(x, &format!("{who} lists the group without Carol"), |_| members(x, &gid) == Some(sorted(&[&a, &b, &d]))).await;
    }

    // Bob leaves: it is no longer listed for him, and another member commits his removal
    assert_eq!(bob.command(Command::Leave { conversation: gid.clone() }).await, Response::Ok);
    assert_eq!(members(&bob, &gid), None);
    for (who, x) in [("Alice", &alice), ("Dave", &dave)] {
        until(x, &format!("{who} lists the group without Bob"), |_| members(x, &gid) == Some(sorted(&[&a, &d]))).await;
    }
    assert_eq!(dave.command(Command::Message { to: gid.clone(), text: "just us".into() }).await, Response::Conversation { conversation: gid.clone() });
    hears(&mut a_rx, "Alice", &gid, "just us").await;
    for x in [&alice, &bob, &carol, &dave] {
        x.stop().await;
    }
    let _ = std::fs::remove_dir_all(&dir);
}
