//! A second device that joined by the pairing codes, holding no identity key (app plan A6, decision 5 (a)), runs as
//! the identity: it binds to the relay with its own key and delegation, and a call to the identity rings on it. Its
//! key agreement key is the identity's, so what is sealed to the identity opens there too.

use std::time::Duration;

use dsip_app::{App, CallState, Command, Config, Direction, Response};
use dsip_testkit::Network;

#[tokio::test(flavor = "multi_thread")]
async fn a_device_that_joined_by_codes_rings_for_its_identity() {
    let net = Network::new();
    let ann = net.identity("Ann");
    let ann_dir = ann.dir.clone();
    let second = ann_dir.with_extension("second");
    let _ = std::fs::remove_dir_all(&second);

    // the two codes, as a person carries them between the devices
    let (join, _) = dsip_app::pairing::start(&second).unwrap();
    let (welcome, _) = dsip_app::pairing::welcome(&ann_dir, &join).unwrap();
    assert_eq!(dsip_app::pairing::finish(&second, &welcome).unwrap(), ann.meta.identity);
    let joined = dsip_app::keys::load_identity(&second).unwrap();
    assert!(joined.controller.is_none());

    let mut cfg = Config::new(joined, "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    let device = App::start(cfg).await.expect("the joined device binds as the identity");
    assert_eq!(device.state().me.identity, ann.meta.identity);

    let mut cfg = Config::new(net.identity("Bob"), "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = None;
    let bob = App::start(cfg).await.unwrap();
    assert!(matches!(bob.command(Command::Call { to: ann.meta.identity.clone(), video: false }).await, Response::Call { .. }));
    tokio::time::timeout(Duration::from_secs(15), async {
        while !device.state().calls.values().any(|c| c.direction == Direction::Incoming && c.state == CallState::Ringing) {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("it never rang: {:#?}", device.state().calls));
    let _ = std::fs::remove_dir_all(second);
}
