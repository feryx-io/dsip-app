//! An identity moved onto a domain of its own (app plan A6d): the document prepared, checked against what an HTTPS
//! server on localhost serves (wrong, then right), and the identity moved, its keys staying in the store.
#![cfg(target_os = "linux")]

use std::sync::{Arc, Mutex};

use dsip_app::web;
use serde_json::Value;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// An HTTPS server answering every request with `doc` (as JSON), under a test certificate in `dir`.
async fn serve(dir: &std::path::Path, doc: Arc<Mutex<Value>>) -> u16 {
    let (cert, key) = dsip_transport::tls::ensure_self_signed(dir, &["localhost".into(), "127.0.0.1".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    tokio::spawn(async move {
        loop {
            let Ok((sock, _)) = tcp.accept().await else { return };
            let (tls, doc) = (tls.clone(), doc.clone());
            tokio::spawn(async move {
                let Ok(mut s) = tls.accept(sock).await else { return };
                let mut buf = [0u8; 4096];
                let _ = s.read(&mut buf).await;
                let body = doc.lock().unwrap().to_string();
                let head = format!("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n", body.len());
                let _ = s.write_all(head.as_bytes()).await;
                let _ = s.write_all(body.as_bytes()).await;
                let _ = s.shutdown().await;
            });
        }
    });
    port
}

#[tokio::test(flavor = "multi_thread")]
async fn an_identity_moves_to_its_own_domain_once_the_domain_serves_its_document() {
    let base = std::env::temp_dir().join(format!("dsip-app-web-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(&base).unwrap();
    let dir = base.join("identity");
    keyring_core::set_default_store(keyring_core::mock::Store::new().unwrap());
    let old = dsip_app::init_identity(&dir, "Ann").unwrap();
    assert!(!dir.join("controller.key").exists(), "its keys in the store");

    let served = Arc::new(Mutex::new(serde_json::json!({"id": "did:web:elsewhere"})));
    let port = serve(&base, served.clone()).await;
    let did = format!("did:web:localhost%3A{port}");
    let plan = web::prepare(&dir, &did, "wss://relay.example.com/dsip", Some(("did:web:mbx.example.com", "wss://mbx.example.com/dsip"))).unwrap();
    assert_eq!(plan.url, format!("https://localhost:{port}/.well-known/did.json"));
    assert_eq!(dsip_app::keys::load_identity(&dir).unwrap().meta.identity, old, "nothing changed yet");

    // the domain serves the document of another identity under that DID: each difference said
    let other = base.join("other");
    dsip_app::init_identity(&other, "Mallory").unwrap();
    *served.lock().unwrap() = web::prepare(&other, &did, "wss://relay.example.com/dsip", None).unwrap().document;
    let ca = base.join("cert.pem");
    let differs = web::check(&plan, Some(&ca)).await.unwrap();
    assert!(differs.iter().any(|d| d.contains("#key-1")), "{differs:?}");
    assert!(differs.iter().any(|d| d.contains("keyAgreement")), "{differs:?}");
    assert!(differs.iter().any(|d| d.contains("DSIPMailbox")), "{differs:?}");

    // then the one prepared: nothing differs, and the identity moves
    *served.lock().unwrap() = plan.document.clone();
    assert_eq!(web::check(&plan, Some(&ca)).await.unwrap(), Vec::<String>::new());
    let ka_before = dsip_app::keys::load_identity(&dir).unwrap().key_agreement.unwrap();
    assert_eq!(web::move_to(&dir, &plan).unwrap(), did);
    let moved = dsip_app::keys::load_identity(&dir).unwrap();
    assert_eq!(moved.meta.identity, did);
    assert!(!dir.join("key-agreement.json").exists(), "its key agreement delegation, signed again, in the store");
    let ka = moved.key_agreement.unwrap();
    assert_eq!(ka.secret, ka_before.secret, "the same key agreement key");
    let payload: Value = serde_json::from_slice(&dsip_core::b64::decode(&ka.delegation.payload).unwrap()).unwrap();
    assert_eq!(payload["subject"], did.as_str(), "the delegation names the new identity");
    let delegation: Value = serde_json::from_slice(&dsip_core::b64::decode(&moved.delegation.payload).unwrap()).unwrap();
    assert_eq!(delegation["subject"], did.as_str());
    assert_eq!(serde_json::from_str::<Value>(&std::fs::read_to_string(dir.join("did.json")).unwrap()).unwrap(), plan.document);
    keyring_core::unset_default_store();
    let _ = std::fs::remove_dir_all(base);
}
