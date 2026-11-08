//! The names this device's user gives identities: set, shown in the state, kept across a restart, taken away; a name
//! too long, or with a control character, refused.

use dsip_app::{App, Command, Config, Response};
use dsip_testkit::Network;

async fn start(net: &Network, id: dsip_phone::Identity) -> App {
    let mut cfg = Config::new(id, "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    App::start(cfg).await.unwrap()
}

fn set(identity: &str, name: Option<&str>) -> Command {
    Command::SetName { identity: identity.into(), name: name.map(String::from) }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_name_given_is_shown_kept_and_taken_away() {
    let net = Network::new();
    let ann = net.identity("Ann");
    let dir = ann.dir.clone();
    let _ = std::fs::remove_file(dir.join(dsip_app::NAMES_FILE));
    let app = start(&net, ann).await;
    assert!(app.state().names.is_empty());

    assert_eq!(app.command(set("did:web:priya.example", Some("  Priya  "))).await, Response::Ok);
    assert_eq!(app.command(set("did:web:jonas.example", Some("Jonas"))).await, Response::Ok);
    assert_eq!(app.state().names.get("did:web:priya.example").map(String::as_str), Some("Priya"), "trimmed");

    let too_long = "x".repeat(dsip_app::NAME_MAX + 1);
    assert!(matches!(app.command(set("did:web:priya.example", Some(&too_long))).await, Response::Error { .. }));
    assert!(matches!(app.command(set("did:web:priya.example", Some("Pri\nya"))).await, Response::Error { .. }));
    assert!(matches!(app.command(set(" ", Some("Nobody"))).await, Response::Error { .. }));
    assert_eq!(app.state().names.len(), 2, "a refused name changes nothing");

    // a blank name takes it away, as no name does
    assert_eq!(app.command(set("did:web:jonas.example", Some("   "))).await, Response::Ok);
    assert_eq!(app.state().names.keys().collect::<Vec<_>>(), ["did:web:priya.example"]);
    app.stop().await;

    // kept across a restart
    let again = start(&net, dsip_app::keys::load_identity(&dir).unwrap()).await;
    assert_eq!(again.state().names.get("did:web:priya.example").map(String::as_str), Some("Priya"));
    assert_eq!(again.command(set("did:web:priya.example", None)).await, Response::Ok);
    assert!(again.state().names.is_empty());
    let saved: std::collections::BTreeMap<String, String> =
        serde_json::from_slice(&std::fs::read(dir.join(dsip_app::NAMES_FILE)).unwrap()).unwrap();
    assert!(saved.is_empty());
}
