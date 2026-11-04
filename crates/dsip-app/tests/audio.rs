//! Choosing the audio devices, as the settings screen does: the tone host has no devices to choose and refuses, the
//! state keeps the system's defaults and every screen is told; looking at the devices again is a change too; a device
//! chosen before and gone now does not stop the app from starting. (The platform's host, which does choose, needs real
//! devices: CI's runners have none.)

use std::time::Duration;

use dsip_app::{App, Change, Command, Config, HostKind, Response};
use dsip_testkit::Network;

async fn app(net: &Network, audio: Option<HostKind>, devices: (Option<String>, Option<String>)) -> App {
    let mut cfg = Config::new(net.identity("Alice"), "wss://relay.invalid/dsip");
    cfg.dialer = Some(net.dialer());
    cfg.audio = audio;
    cfg.audio_devices = devices;
    App::start(cfg).await.expect("the app starts")
}

async fn audio_change(changes: &mut tokio::sync::broadcast::Receiver<Change>) -> dsip_app::AudioState {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Ok(Change::Audio { audio }) = changes.recv().await {
                return audio;
            }
        }
    })
    .await
    .expect("an audio change")
}

#[tokio::test(flavor = "multi_thread")]
async fn the_tone_host_refuses_a_choice_and_the_screens_are_told() {
    let net = Network::new();
    let alice = app(&net, Some(HostKind::Tone), (None, None)).await;
    let mut changes = alice.subscribe();

    let r = alice.command(Command::ChooseAudio { input: Some("mic-1".into()), output: None }).await;
    assert!(matches!(&r, Response::Error { message } if message.contains("no choice of device")), "{r:?}");
    let audio = audio_change(&mut changes).await;
    assert_eq!((audio.host.as_str(), &audio.input, &audio.output), ("tone", &None, &None));
    assert_eq!(alice.state().audio, audio);

    assert_eq!(alice.command(Command::AudioDevices).await, Response::Ok);
    assert_eq!(audio_change(&mut changes).await, alice.state().audio);
    alice.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_device_gone_since_is_no_reason_not_to_start() {
    let net = Network::new();
    let alice = app(&net, Some(HostKind::Tone), (Some("unplugged".into()), Some("unplugged".into()))).await;
    let s = alice.state();
    assert_eq!((s.audio.input, s.audio.output), (None, None));
    alice.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn without_sound_there_is_nothing_to_choose() {
    let net = Network::new();
    let alice = app(&net, None, (None, None)).await;
    assert_eq!(alice.state().audio.host, "none");
    for cmd in [Command::ChooseAudio { input: None, output: None }, Command::AudioDevices] {
        assert!(matches!(alice.command(cmd).await, Response::Error { .. }));
    }
    alice.stop().await;
}

#[test]
fn the_commands_on_the_wire() {
    let c: Command = serde_json::from_str(r#"{"command":"choose_audio","input":"mic-1"}"#).unwrap();
    assert_eq!(c, Command::ChooseAudio { input: Some("mic-1".into()), output: None });
    assert_eq!(serde_json::to_string(&Command::AudioDevices).unwrap(), r#"{"command":"audio_devices"}"#);
}
