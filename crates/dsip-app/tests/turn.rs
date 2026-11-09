//! Calls get TURN from the app's own relay: its `/turn`, beside its `wss` URL, where the relay mints short-lived
//! credentials for the TURN server its operator runs. A phone on a mobile network and a desktop behind a home NAT need
//! it when no direct path opens.

use dsip_app::Settings;
use dsip_testkit::Network;

#[tokio::test]
async fn the_app_asks_its_relay_for_turn() {
    let net = Network::new();
    let ann = net.identity("Ann");
    let settings =
        Settings { identity: ann.dir.clone(), relay: "wss://relay.example:8443/dsip".into(), ..Settings::default() };
    let cfg = settings.config().unwrap();
    assert_eq!(cfg.turn.as_ref().map(|t| t.url()), Some("https://relay.example:8443/turn"));
}
