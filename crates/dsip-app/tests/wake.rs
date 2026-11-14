//! Waking the app while it sleeps (app plan A5d; the Wake Profile), against dsip-rs's in-process relay and a push
//! gateway with a recording provider: the phone's token enrolled and the registration given to the relay and the
//! mailbox, kept across a restart, given again for a new token, ended when the token goes; a call to the sleeping app
//! wakes it with a hint `open-wake` reads; a relay that wakes no one; no gateway.
#![cfg(target_os = "linux")]

use std::path::Path;
use std::time::Duration;

use dsip_app::{App, Command, Config, MessagingConfig, Response, State, WakeConfig};
use dsip_mailbox::{MailboxConfig, MailboxServer};
use dsip_testkit::{push, Network, PushGateway};
use dsip_transport::wake::WakeClient;
use serde_json::Value;

fn push_token(token: &str) -> Command {
    Command::Push { provider: Some("fcm".into()), app: Some(push::APP.into()), token: Some(token.into()), environment: None, message_app: None, message_token: None }
}

fn config(net: &Network, id: dsip_phone::Identity, gw: Option<&PushGateway>) -> Config {
    let mut cfg = Config::new(id, "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    cfg.wake = gw.map(|g| WakeConfig { gateway: g.did.clone(), client: Some(g.client.clone()) });
    cfg
}

async fn until(app: &App, what: &str, want: impl Fn(&State) -> bool) {
    tokio::time::timeout(Duration::from_secs(20), async {
        while !want(&app.state()) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{what}: {:#?}", app.state().push));
}

fn relay_registered(s: &State) -> bool {
    s.push.as_ref().is_some_and(|p| p.enrolled && p.relay.status == "registered")
}

/// The pushes, once there are `n`.
async fn pushes(gw: &PushGateway, n: usize) -> Vec<Value> {
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let p = gw.recorder.pushes();
            if p.len() >= n {
                return p;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("{n} pushes never came: {:?}", gw.recorder.pushes()))
}

#[tokio::test]
async fn the_token_is_enrolled_and_registered_with_the_relay_and_kept_across_a_restart() {
    let gw = PushGateway::start().await;
    let net = Network::waking(&gw);
    let id = net.identity("Bob");
    let dir = id.dir.clone();
    let bob = App::start(config(&net, id, Some(&gw))).await.unwrap();
    assert_eq!(bob.state().push, None, "no token yet");
    assert_eq!(bob.command(push_token("fcm-token-1")).await, Response::Ok);
    until(&bob, "registered with the relay", relay_registered).await;
    let first = bob.state().push.unwrap();
    assert_eq!((first.gateway.as_str(), first.provider.as_str(), first.mailbox.as_ref()), (gw.did.as_str(), "fcm", None));

    // wake.json holds keys: its owner's alone
    use std::os::unix::fs::PermissionsExt;
    let mode = std::fs::metadata(dir.join(dsip_app::wake::FILE)).unwrap().permissions().mode();
    assert_eq!(mode & 0o777, 0o600);

    // started again, the registration is the one given: not given again
    bob.stop().await;
    let bob = App::start(config(&net, dsip_phone::Identity::load(&dir).unwrap(), Some(&gw))).await.unwrap();
    until(&bob, "registered after the restart", relay_registered).await;
    assert_eq!(bob.state().push.unwrap().relay.expires_at, first.relay.expires_at);

    // a new token is enrolled again and registered again
    tokio::time::sleep(Duration::from_millis(1100)).await;
    assert_eq!(bob.command(push_token("fcm-token-2")).await, Response::Ok);
    until(&bob, "registered for the new token", |s| relay_registered(s) && s.push.as_ref().unwrap().relay.expires_at > first.relay.expires_at).await;
}

#[tokio::test]
async fn a_call_to_the_sleeping_app_wakes_it_and_open_wake_reads_who_calls() {
    let gw = PushGateway::start().await;
    let net = Network::waking(&gw);
    let id = net.identity("Bob");
    let dir = id.dir.clone();
    let bob = App::start(config(&net, id, Some(&gw))).await.unwrap();
    let bob_did = bob.state().me.identity;
    bob.command(push_token("fcm-token-bob")).await;
    until(&bob, "registered", relay_registered).await;
    bob.stop().await;
    tokio::time::sleep(Duration::from_millis(300)).await;

    let alice = App::start(config(&net, net.identity("Alice"), None)).await.unwrap();
    let me = alice.state().me;
    assert!(matches!(alice.command(Command::Call { to: bob_did, video: false }).await, Response::Call { .. }));
    let p = pushes(&gw, 1).await;
    assert_eq!(p[0]["token"], "fcm-token-bob");

    // what the woken app reads: the data as FCM delivers it, one string field (W§5.3)
    let data = serde_json::json!({"dsip-wake": p[0]["data"]["dsip-wake"].to_string()});
    let Response::Wake { kind, waker, session, from, on_behalf_of } = dsip_app::wake::open(&dir, &data).unwrap() else { panic!() };
    assert_eq!((kind.as_str(), waker.as_str()), ("call", net.relay().did()));
    assert_eq!(session.as_deref(), p[0]["data"]["dsip-wake"]["session"].as_str());
    assert_eq!((from.as_deref(), on_behalf_of.as_deref()), (Some(me.device.as_str()), Some(me.identity.as_str())));
}

#[tokio::test]
async fn with_the_token_gone_the_registration_ends_and_a_call_wakes_nothing() {
    let gw = PushGateway::start().await;
    let net = Network::waking(&gw);
    let bob = App::start(config(&net, net.identity("Bob"), Some(&gw))).await.unwrap();
    let bob_did = bob.state().me.identity;
    bob.command(push_token("fcm-token-bob")).await;
    until(&bob, "registered", relay_registered).await;
    let off = Command::Push { provider: None, app: None, token: None, environment: None, message_app: None, message_token: None };
    assert_eq!(bob.command(off).await, Response::Ok);
    until(&bob, "not woken", |s| s.push.is_none()).await;
    bob.stop().await;
    tokio::time::sleep(Duration::from_millis(300)).await;

    let alice = App::start(config(&net, net.identity("Alice"), None)).await.unwrap();
    alice.command(Command::Call { to: bob_did, video: false }).await;
    tokio::time::sleep(Duration::from_millis(1000)).await;
    assert!(gw.recorder.pushes().is_empty(), "{:?}", gw.recorder.pushes());
}

#[tokio::test]
async fn a_relay_that_wakes_no_one_is_not_registered_with() {
    let gw = PushGateway::start().await;
    let net = Network::new();
    let bob = App::start(config(&net, net.identity("Bob"), Some(&gw))).await.unwrap();
    bob.command(push_token("fcm-token-bob")).await;
    until(&bob, "enrolled", |s| s.push.as_ref().is_some_and(|p| p.enrolled && p.relay.status == "not-offered")).await;
}

#[tokio::test]
async fn without_a_push_gateway_a_token_is_refused() {
    let net = Network::new();
    let bob = App::start(config(&net, net.identity("Bob"), None)).await.unwrap();
    assert!(matches!(bob.command(push_token("t")).await, Response::Error { .. }));
}

/// A mailbox enrolling identities that bind and waking them through `gw`, on 127.0.0.1 under a test certificate.
async fn mailbox(dir: &Path, gw: &PushGateway) -> (String, String) {
    let (cert, key) = dsip_transport::tls::ensure_self_signed(dir, &["127.0.0.1".into(), "localhost".into()]).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    let mut cfg = MailboxConfig::new(dir.join("mailbox"), format!("https://127.0.0.1:{port}/blobs"));
    cfg.serve_any = Some(4);
    cfg.wake = Some(gw.waker());
    let server = MailboxServer::open(cfg).unwrap();
    server.spawn_tasks();
    let did = server.did().to_string();
    tokio::spawn(async move { server.serve_tls(tcp, tls).await });
    (did, format!("wss://127.0.0.1:{port}/dsip"))
}

#[tokio::test(flavor = "multi_thread")]
async fn with_a_mailbox_that_wakes_both_are_registered_with() {
    let gw = PushGateway::start().await;
    let net = Network::waking(&gw);
    let dir = std::env::temp_dir().join(format!("dsip-app-wake-mailbox-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let mut cfg = config(&net, net.identity("Bob"), Some(&gw));
    cfg.messaging = Some(MessagingConfig {
        mailbox: mailbox(&dir, &gw).await,
        hints_nodes: vec![],
        ca: Some(dir.join("cert.pem")),
        state_dir: dir.join("bob-messaging"),
        fetch_did_web: false,
    });
    let bob = App::start(cfg).await.unwrap();
    bob.command(push_token("fcm-token-bob")).await;
    until(&bob, "registered with both", |s| {
        relay_registered(s) && s.push.as_ref().and_then(|p| p.mailbox.as_ref()).is_some_and(|m| m.status == "registered")
    })
    .await;
    bob.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

/// The bundle ID of the iPhone app the APNs gateway below pushes for.
const BUNDLE: &str = "org.dsip.test";

/// A gateway pushing for an iPhone app's two APNs topics (spec-gap 178): PushKit's `<bundle>.voip` and the alert
/// token's `<bundle>`, through a recorder; and the waker configuration that reaches it.
async fn apns_gateway(dir: &Path) -> (String, WakeClient, dsip_push::providers::Recorder, dsip_transport::waker::WakeConfig) {
    use std::collections::HashMap;
    use std::sync::Arc;
    let (cert, key) = dsip_transport::tls::ensure_self_signed(dir, &["localhost".into(), "127.0.0.1".into()]).unwrap();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    let did = format!("did:web:localhost%3A{port}");
    let endpoint = format!("https://localhost:{port}/wake");
    let recorder = dsip_push::providers::Recorder::default();
    let providers: HashMap<String, Arc<dyn dsip_push::Provider>> = [("apns".to_string(), Arc::new(recorder.clone()) as Arc<dyn dsip_push::Provider>)].into();
    let gateway = Arc::new(dsip_push::Gateway::new(dsip_push::GatewayConfig {
        key: dsip_core::keys::KeyPair::generate(),
        did: did.clone(),
        handle_key: dsip_core::keys::KeyPair::generate().seed(),
        apps: vec![("apns".into(), format!("{BUNDLE}.voip")), ("apns".into(), BUNDLE.into())],
        providers,
        resolver: Default::default(),
        web: None,
        limits: dsip_push::Limits::default(),
    }));
    let mut docs = dsip_core::did::StaticResolver::default();
    docs.insert(gateway.document(&endpoint));
    let acceptor = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    tokio::spawn(async move { dsip_push::server::serve(gateway, &endpoint, tcp, acceptor).await });
    let client = WakeClient::new(Arc::new(docs)).with_ca(&std::fs::read(&cert).unwrap()).unwrap();
    let waker = dsip_transport::waker::WakeConfig { client: client.clone(), gateways: Some(vec![did.clone()]), store: None };
    (did, client, recorder, waker)
}

fn iphone_tokens(voip: Option<&str>, alert: Option<&str>) -> Command {
    Command::Push {
        provider: Some("apns".into()),
        app: voip.map(|_| format!("{BUNDLE}.voip")),
        token: voip.map(String::from),
        environment: Some("sandbox".into()),
        message_app: alert.map(|_| BUNDLE.into()),
        message_token: alert.map(String::from),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn an_iphone_enrols_its_two_tokens_apart_calls_at_the_relay_and_messages_at_the_mailbox() {
    let dir = std::env::temp_dir().join(format!("dsip-app-wake-iphone-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let (gateway, client, recorder, waker) = apns_gateway(&dir).await;
    let net = Network::with(dsip_relay::RelayConfig { wake: Some(waker.clone()), ..dsip_relay::RelayConfig::default() });
    let id = net.identity("Bob");
    let id_dir = id.dir.clone();
    let mut cfg = config(&net, id, None);
    cfg.wake = Some(WakeConfig { gateway: gateway.clone(), client: Some(client) });
    cfg.messaging = Some(MessagingConfig {
        mailbox: mailbox_waking(&dir, waker).await,
        hints_nodes: vec![],
        ca: Some(dir.join("mailbox-cert.pem")),
        state_dir: dir.join("bob-messaging"),
        fetch_did_web: false,
    });
    let bob = App::start(cfg).await.unwrap();
    let bob_did = bob.state().me.identity;
    let mailbox_registered = |s: &State| s.push.as_ref().and_then(|p| p.mailbox.as_ref()).is_some_and(|m| m.status == "registered");

    // PushKit's token alone: calls wake, messages cannot (APNs takes no alert push on a VoIP token)
    assert_eq!(bob.command(iphone_tokens(Some("voip-token"), None)).await, Response::Ok);
    until(&bob, "the relay alone", |s| {
        relay_registered(s) && s.push.as_ref().and_then(|p| p.mailbox.as_ref()).is_some_and(|m| m.status == "no-token")
    })
    .await;

    // the alert token too: enrolled apart, under its own key, and given to the mailbox
    assert_eq!(bob.command(iphone_tokens(Some("voip-token"), Some("alert-token"))).await, Response::Ok);
    until(&bob, "both", |s| relay_registered(s) && mailbox_registered(s)).await;
    let saved: Value = serde_json::from_slice(&std::fs::read(id_dir.join(dsip_app::wake::FILE)).unwrap()).unwrap();
    let (calls, messages) = (&saved["enrolment"], &saved["message_enrolment"]);
    assert_eq!((calls["token"]["app"].as_str(), messages["token"]["app"].as_str()), (Some("org.dsip.test.voip"), Some(BUNDLE)));
    assert_ne!(calls["key"], messages["key"], "each enrolment its own wake key (W§3)");
    assert_eq!(saved["relay"]["handle"], calls["handle"], "the relay wakes through PushKit's token");
    assert_eq!(saved["mailbox"]["handle"], messages["handle"], "the mailbox through the alert token");

    // a call to the sleeping phone is a VoIP push on PushKit's token
    bob.stop().await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    let alice = App::start(config(&net, net.identity("Alice"), None)).await.unwrap();
    alice.command(Command::Call { to: bob_did, video: false }).await;
    let pushed = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if let Some(p) = recorder.pushes().into_iter().next() {
                return p;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .expect("a push");
    assert_eq!((pushed["app"].as_str(), pushed["token"].as_str(), pushed["class"].as_str()), (Some("org.dsip.test.voip"), Some("voip-token"), Some("call")));
    let _ = std::fs::remove_dir_all(dir);
}

/// [`mailbox`], waking through `waker`.
async fn mailbox_waking(dir: &Path, waker: dsip_transport::waker::WakeConfig) -> (String, String) {
    let (cert, key) = dsip_transport::tls::ensure_self_signed(&dir.join("mailbox-tls"), &["127.0.0.1".into(), "localhost".into()]).unwrap();
    std::fs::copy(&cert, dir.join("mailbox-cert.pem")).unwrap();
    let tls = dsip_transport::tls::acceptor(&cert, &key).unwrap();
    let tcp = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = tcp.local_addr().unwrap().port();
    let mut cfg = MailboxConfig::new(dir.join("mailbox"), format!("https://127.0.0.1:{port}/blobs"));
    cfg.serve_any = Some(4);
    cfg.wake = Some(waker);
    let server = MailboxServer::open(cfg).unwrap();
    server.spawn_tasks();
    let did = server.did().to_string();
    tokio::spawn(async move { server.serve_tls(tcp, tls).await });
    (did, format!("wss://127.0.0.1:{port}/dsip"))
}
