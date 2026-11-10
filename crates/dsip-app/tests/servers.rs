//! A domain's servers, from its `/.well-known/dsip`: fetched over HTTPS from a server on localhost, then turned into
//! the settings a device runs with; a domain listing none, or a list this app cannot use, said so.
#![cfg(target_os = "linux")]

use std::sync::{Arc, Mutex};

use dsip_app::servers;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// An HTTPS server answering every request with `answer` (status, body), under a test certificate in `dir`; and what
/// it was asked for.
async fn serve(dir: &std::path::Path, answer: Arc<Mutex<(u16, String)>>) -> (u16, Arc<Mutex<Vec<String>>>) {
    let (cert, key) = dsip_transport::tls::ensure_self_signed(dir, &["localhost".into(), "127.0.0.1".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    let asked = Arc::new(Mutex::new(vec![]));
    let seen = asked.clone();
    tokio::spawn(async move {
        loop {
            let Ok((sock, _)) = tcp.accept().await else { return };
            let (tls, answer, seen) = (tls.clone(), answer.clone(), seen.clone());
            tokio::spawn(async move {
                let Ok(mut s) = tls.accept(sock).await else { return };
                let mut buf = [0u8; 4096];
                let n = s.read(&mut buf).await.unwrap_or(0);
                let line = String::from_utf8_lossy(&buf[..n]).lines().next().unwrap_or_default().to_string();
                seen.lock().unwrap().push(line);
                let (status, body) = answer.lock().unwrap().clone();
                let head = format!(
                    "HTTP/1.1 {status} X\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n",
                    body.len()
                );
                let _ = s.write_all(head.as_bytes()).await;
                let _ = s.write_all(body.as_bytes()).await;
                let _ = s.shutdown().await;
            });
        }
    });
    (port, asked)
}

#[tokio::test(flavor = "multi_thread")]
async fn a_domain_lists_its_servers_and_a_device_takes_one_of_each() {
    let base = std::env::temp_dir().join(format!("dsip-app-servers-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(&base).unwrap();
    let list = serde_json::json!({
        "version": 1,
        "relays": ["wss://relay1.example.com/dsip", "wss://relay2.example.com/dsip"],
        "mailboxes": [{"uri": "wss://mailbox1.example.com/dsip", "did": "did:web:mailbox1.example.com"}],
        "hints_nodes": ["https://hints.example.com"],
        "stun": ["stun:turn.example.com:3478"]
    });
    let answer = Arc::new(Mutex::new((200, list.to_string())));
    let (port, asked) = serve(&base, answer.clone()).await;
    let pem = std::fs::read(base.join("cert.pem")).unwrap();
    let domain = format!("localhost:{port}");

    let found = servers::fetch(&domain, Some(&pem)).await.unwrap();
    assert_eq!(asked.lock().unwrap().last().unwrap(), "GET /.well-known/dsip HTTP/1.1");
    let s = found.settings("/id".into(), &domain, 1);
    assert_eq!(s.relay, "wss://relay2.example.com/dsip");
    assert_eq!(s.mailbox.unwrap().uri, "wss://mailbox1.example.com/dsip");
    assert_eq!((s.hints_nodes.len(), s.stun.len()), (1, 1));
    assert_eq!(s.server.as_deref(), Some(domain.as_str()));
    assert_eq!(servers::pick_for("did:key:z6MkAnn"), servers::pick_for("did:key:z6MkAnn"), "the same each start");

    // a domain with no list, and lists this app cannot use: each said
    *answer.lock().unwrap() = (404, String::new());
    let e = servers::fetch(&domain, Some(&pem)).await.unwrap_err().to_string();
    assert!(e.contains("lists no DSIP servers"), "{e}");
    *answer.lock().unwrap() = (200, serde_json::json!({"version": 2, "relays": ["wss://r/dsip"]}).to_string());
    let e = servers::fetch(&domain, Some(&pem)).await.unwrap_err().to_string();
    assert!(e.contains("this app reads version 1"), "{e}");
    *answer.lock().unwrap() = (200, "<html>".into());
    let e = servers::fetch(&domain, Some(&pem)).await.unwrap_err().to_string();
    assert!(e.contains("not a list of servers"), "{e}");
    *answer.lock().unwrap() = (200, "x".repeat(70 * 1024));
    let e = servers::fetch(&domain, Some(&pem)).await.unwrap_err().to_string();
    assert!(e.contains("larger than"), "{e}");

    // and a server whose certificate is not trusted is not believed
    *answer.lock().unwrap() = (200, list.to_string());
    assert!(servers::fetch(&domain, None).await.is_err());
    let _ = std::fs::remove_dir_all(base);
}
