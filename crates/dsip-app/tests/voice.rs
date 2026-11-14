//! Voice messages and voicemail between two apps, each with its own mailbox, found through hints (M§8.2, M§13): Alice
//! records on the tone host's microphone and sends it, and Bob's app has it as an `audio` content with its purpose and
//! length, its file fetched and decrypted, and plays it. After a call Bob declined, Alice's app offers a voicemail: his
//! hint says his mailbox takes them, up to its limit; an outcome M§13.2 does not list offers none. The voicemail
//! carries the call's session.
#![cfg(target_os = "linux")]

use std::path::Path;
use std::time::Duration;

use dsip_app::{App, Change, Command, Config, HostKind, MessagingConfig, Response};
use dsip_mailbox::{MailboxConfig, MailboxServer};
use dsip_testkit::Network;

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
    cfg.audio = Some(HostKind::Tone);
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
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().voice));
}

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
    .unwrap_or_else(|_| panic!("{what}"))
}

async fn hints_published(hints: &str, apps: &[&App]) {
    let client = dsip_transport::hints::HintsClient::new(vec![hints.to_string()], None).expect("a hints client");
    for app in apps {
        let did = app.state().me.identity;
        tokio::time::timeout(Duration::from_secs(20), async {
            while client.lookup(&did, &dsip_core::did::StaticResolver::default(), dsip_transport::now_s()).await.is_none() {
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("{did}'s hint never reached the hints node"));
    }
}

/// Record about `ms`, stop, and answer with the file and its length.
async fn recorded(app: &App, ms: u64) -> (String, u64) {
    assert_eq!(app.command(Command::Record { max_s: None }).await, Response::Ok);
    until(app, "recording", |s| s.voice.recording.as_ref().is_some_and(|r| r.running)).await;
    tokio::time::sleep(Duration::from_millis(ms)).await;
    match app.command(Command::StopRecording).await {
        Response::Recorded { path, duration_ms } => (path, duration_ms),
        other => panic!("not a recording: {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_voice_message_and_a_voicemail_after_a_declined_call() {
    let dir = std::env::temp_dir().join(format!("dsip-app-voice-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let hints = dsip_testkit::hints_node().await;
    let net = Network::new();
    let alice = app(&net, &dir, "Alice", mailbox(&dir, "mailbox-a", &tls, &hints).await, &hints).await;
    let bob = app(&net, &dir, "Bob", mailbox(&dir, "mailbox-b", &tls, &hints).await, &hints).await;
    let bob_did = bob.state().me.identity;
    for a in [&alice, &bob] {
        until(a, "bound to the mailbox", |s| s.messaging.connected).await;
    }
    hints_published(&hints, &[&alice, &bob]).await;

    // M§13.2: nothing to offer before Alice may message Bob
    let r = alice.command(Command::VoicemailOffer { to: bob_did.clone(), reason: "user.declined".into() }).await;
    assert_eq!(r, Response::Voicemail { offer: false, max_duration_s: None });
    let mut a_changes = alice.subscribe();
    assert_eq!(alice.command(Command::Introduce { to: bob_did.clone(), purpose: "hello".into(), name: None }).await, Response::Ok);
    until(&bob, "Bob sees the request", |s| !s.messaging.requests.is_empty()).await;
    let id = bob.state().messaging.requests[0].id.clone();
    assert_eq!(bob.command(Command::AcceptRequest { id }).await, Response::Ok);
    next(&mut a_changes, "Alice's grant", |c| matches!(c, Change::Granted { by } if *by == bob_did).then_some(())).await;

    // a voice message: recorded, sent, and at Bob an `audio` of about that length, its file there, and played
    let (path, ms) = recorded(&alice, 1_500).await;
    assert!((1_000..3_000).contains(&ms), "{ms} ms");
    assert!(alice.state().voice.recording.is_none(), "taken");
    let mut b_changes = bob.subscribe();
    let sent = alice.command(Command::SendAudio { to: bob_did.clone(), path: path.clone(), purpose: None, session: None }).await;
    assert!(matches!(sent, Response::Conversation { .. }), "{sent:?}");
    assert!(!Path::new(&path).exists(), "the recording moved to the media folder");
    let m = next(&mut b_changes, "Bob gets it", |c| match c {
        Change::Message { message } if !message.mine && message.kind == "audio" => Some(message.clone()),
        _ => None,
    })
    .await;
    assert_eq!((m.purpose.as_deref(), m.duration_ms, m.content_type.as_deref()), (Some("voice-message"), Some(ms), Some("audio/ogg; codecs=opus")));
    let file = next(&mut b_changes, "Bob's copy", |c| match c {
        Change::MessageFile { id, path, .. } if *id == m.id => Some(path.clone()),
        _ => None,
    })
    .await;
    assert_eq!(dsip_app::audio::duration_ms(Path::new(&file)), Some(ms), "an Ogg Opus file, whole");
    assert_eq!(bob.command(Command::Play { path: file.clone() }).await, Response::Ok);
    assert_eq!(bob.state().voice.playing.as_deref(), Some(file.as_str()));
    until(&bob, "played out", |s| s.voice.playing.is_none()).await;

    // a recording dropped leaves nothing behind; one with a limit stops by itself and waits to be sent
    assert_eq!(alice.command(Command::Record { max_s: None }).await, Response::Ok);
    assert_eq!(alice.command(Command::CancelRecording).await, Response::Ok);
    assert!(alice.state().voice.recording.is_none());
    assert_eq!(alice.command(Command::Record { max_s: Some(1) }).await, Response::Ok);
    until(&alice, "stopped at its limit", |s| s.voice.recording.as_ref().is_some_and(|r| !r.running && r.duration_ms == Some(1_000))).await;
    assert!(matches!(alice.command(Command::StopRecording).await, Response::Recorded { duration_ms: 1_000, .. }));

    // M§13.2: a declined call offers a voicemail, Bob's limit with it; a blocked one does not
    let r = alice.command(Command::VoicemailOffer { to: bob_did.clone(), reason: "user.declined".into() }).await;
    assert_eq!(r, Response::Voicemail { offer: true, max_duration_s: Some(180) });
    let r = alice.command(Command::VoicemailOffer { to: bob_did.clone(), reason: "session.timeout".into() }).await;
    assert!(matches!(r, Response::Voicemail { offer: true, .. }), "unanswered: {r:?}");
    let r = alice.command(Command::VoicemailOffer { to: bob_did.clone(), reason: "user.blocked".into() }).await;
    assert_eq!(r, Response::Voicemail { offer: false, max_duration_s: None });

    let (path, _) = recorded(&alice, 800).await;
    let r = alice.command(Command::SendAudio { to: bob_did.clone(), path: path.clone(), purpose: Some("voicemail".into()), session: None }).await;
    assert!(matches!(r, Response::Error { .. }), "a voicemail names its call");
    let r = alice.command(Command::SendAudio { to: bob_did.clone(), path, purpose: Some("voicemail".into()),
                                               session: Some("01M6EKRTVG3C55DFMQ401G3MC0".into()) }).await;
    assert!(matches!(r, Response::Conversation { .. }), "{r:?}");
    let vm = next(&mut b_changes, "Bob's voicemail", |c| match c {
        Change::Message { message } if message.purpose.as_deref() == Some("voicemail") => Some(message.clone()),
        _ => None,
    })
    .await;
    assert_eq!(vm.session.as_deref(), Some("01M6EKRTVG3C55DFMQ401G3MC0"));
    alice.stop().await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
