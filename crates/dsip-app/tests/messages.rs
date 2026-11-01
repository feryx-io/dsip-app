//! Two apps, `did:key` identities each with its own mailbox, messaging by command alone: Alice introduces herself to
//! Bob, his app shows the request and he accepts it, her app is told of the grant, she messages him (the direct
//! conversation made on the way), he answers in it, and the thread holds both. No DID documents: each app publishes its
//! hint naming its mailbox on a hints node, and every mailbox is found through those.
#![cfg(target_os = "linux")]

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use dsip_app::{App, Change, Command, Config, MessagingConfig, Response};
use dsip_mailbox::{MailboxConfig, MailboxServer};
use dsip_testkit::Network;

/// A hints node's HTTP API, reduced to the latest frame per subject (every reader verifies, §8.3).
async fn hints_node() -> String {
    let held: Arc<Mutex<HashMap<String, String>>> = Arc::default();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", tcp.local_addr().unwrap());
    tokio::spawn(async move {
        loop {
            let Ok((mut s, _)) = tcp.accept().await else { return };
            let held = held.clone();
            tokio::spawn(async move {
                let mut buf = vec![];
                let mut chunk = [0u8; 8192];
                let (head, body) = loop {
                    let n = s.read(&mut chunk).await.unwrap_or(0);
                    if n == 0 {
                        return;
                    }
                    buf.extend_from_slice(&chunk[..n]);
                    let text = String::from_utf8_lossy(&buf).to_string();
                    if let Some(i) = text.find("\r\n\r\n") {
                        let len = text[..i].lines().find_map(|l| l.to_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse::<usize>().unwrap_or(0))).unwrap_or(0);
                        if buf.len() >= i + 4 + len {
                            break (text[..i].to_string(), String::from_utf8_lossy(&buf[i + 4..i + 4 + len]).to_string());
                        }
                    }
                };
                let line = head.lines().next().unwrap_or("").to_string();
                let (status, reply) = if let Some(did) = line.strip_prefix("GET /dsip/v1/hints/").and_then(|r| r.split(' ').next()) {
                    match held.lock().unwrap().get(did) {
                        Some(f) => ("200 OK", json!({"hints": [f]}).to_string()),
                        None => ("404 Not Found", "{}".to_string()),
                    }
                } else if line.starts_with("POST /dsip/v1/hints ") {
                    let subject = dsip_core::envelope::Envelope::from_frame(&body).ok()
                        .and_then(|e| dsip_core::b64::decode(&e.payload))
                        .and_then(|p| serde_json::from_slice::<Value>(&p).ok())
                        .and_then(|p| p["subject"].as_str().map(String::from));
                    match subject {
                        Some(sub) => {
                            held.lock().unwrap().insert(sub, body);
                            ("202 Accepted", json!({"acknowledged": 0}).to_string())
                        }
                        None => ("400 Bad Request", "{}".to_string()),
                    }
                } else {
                    ("404 Not Found", "{}".to_string())
                };
                let resp = format!("HTTP/1.1 {status}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{reply}", reply.len());
                let _ = s.write_all(resp.as_bytes()).await;
            });
        }
    });
    url
}

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
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().messaging));
}

/// The next change `pick` takes, among `rx`'s.
async fn next<T>(rx: &mut tokio::sync::broadcast::Receiver<Change>, what: &str, pick: impl Fn(&Change) -> Option<T>) -> T {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let Ok(c) = rx.recv().await {
                if let Some(t) = pick(&c) {
                    return t;
                }
            }
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what} never came"))
}

#[tokio::test(flavor = "multi_thread")]
async fn introduced_granted_messaged_and_answered_through_mailboxes_found_by_hints() {
    let dir = std::env::temp_dir().join(format!("dsip-app-messages-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", mailbox(&dir, "mailbox-a", &tls, &hints).await, &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let (alice_did, bob_did) = (alice.state().me.identity, bob.state().me.identity);
    for (who, a) in [("Alice", &alice), ("Bob", &bob)] {
        until(a, &format!("{who} bound to the mailbox"), |s| s.messaging.connected).await;
    }
    tokio::time::sleep(Duration::from_millis(500)).await; // each has published its hint once bound
    let mut a_changes = alice.subscribe();
    let mut b_changes = bob.subscribe();

    // first contact: Alice asks, Bob's app shows it, he grants
    let r = alice.command(Command::Introduce { to: bob_did.clone(), purpose: "hello from Alice".into() }).await;
    assert_eq!(r, Response::Ok);
    until(&bob, "Bob sees the request", |s| s.messaging.requests.iter().any(|q| q.from == alice_did)).await;
    let id = bob.state().messaging.requests[0].id.clone();
    assert_eq!(bob.command(Command::AcceptRequest { id }).await, Response::Ok);
    assert!(bob.state().messaging.requests.is_empty(), "answered, the request is gone");
    let by = next(&mut a_changes, "Alice's grant", |c| match c {
        Change::Granted { by } => Some(by.clone()),
        _ => None,
    })
    .await;
    assert_eq!(by, bob_did);

    // Alice messages Bob: the direct conversation is made on the way
    let Response::Conversation { conversation } = alice.command(Command::Message { to: bob_did.clone(), text: "found you".into() }).await else {
        panic!("not sent")
    };
    let m = next(&mut b_changes, "Bob gets the message", |c| match c {
        Change::Message { message } if !message.mine => Some(message.clone()),
        _ => None,
    })
    .await;
    assert_eq!((m.from.as_str(), m.text.as_deref(), m.conversation.as_str()), (alice_did.as_str(), Some("found you"), conversation.as_str()));
    until(&bob, "Bob's conversation", |s| s.messaging.conversations.iter().any(|c| c.group == conversation && c.peer.as_deref() == Some(&alice_did))).await;

    // and answers in it
    let r = bob.command(Command::Message { to: alice_did.clone(), text: "hi Alice".into() }).await;
    assert_eq!(r, Response::Conversation { conversation: conversation.clone() }, "the same conversation, by its peer");
    let m = next(&mut a_changes, "Alice gets the answer", |c| match c {
        Change::Message { message } if !message.mine => Some(message.clone()),
        _ => None,
    })
    .await;
    assert_eq!(m.text.as_deref(), Some("hi Alice"));

    let Response::Thread { messages } = alice.command(Command::Thread { conversation }).await else { panic!("no thread") };
    let texts: Vec<_> = messages.iter().map(|m| (m.mine, m.text.clone().unwrap_or_default())).collect();
    assert_eq!(texts, vec![(true, "found you".to_string()), (false, "hi Alice".to_string())]);
    alice.stop().await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
