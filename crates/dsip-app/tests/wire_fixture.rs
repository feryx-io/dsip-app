//! The desktop app reads the app's state as JSON (`app/lib/src/client/models.dart`). This makes that JSON from a
//! state with every part filled, and holds it to `app/test/fixtures/state.json`, which the app's own tests read: a
//! change here that the Dart readers do not follow fails one side or the other. `UPDATE_FIXTURES=1` writes the file
//! again.

use dsip_app::{
    AudioDevice, AudioState, CallState, CallView, Change, ConversationView, Direction, Me, PresenceView, RequestView, State,
};

fn state() -> State {
    let mut s = State {
        me: Me { identity: "did:key:z6MkAlice".into(), device: "did:key:z6MkAliceLaptop".into(), display_name: "Alice".into() },
        relay: "wss://relay.example.com:8443/dsip".into(),
        audio: AudioState {
            host: "system".into(),
            devices: vec![AudioDevice { id: "mic-1".into(), name: "Built-in microphone".into(), kind: "input".into(), default: true }],
        },
        ..State::default()
    };
    let call = |id, state, direction, peer_name: Option<&str>| CallView {
        id,
        session: format!("01M6BTTMQ9QMKY9SYTY8415VZ{id}"),
        peer: "did:key:z6MkBob".into(),
        peer_name: peer_name.map(String::from),
        direction,
        state,
        muted: id == 2,
        media: id == 2,
        via: (id == 2).then(|| "wss://relay.bob.example:8443/dsip".into()),
        error: None,
    };
    for c in [
        call(1, CallState::Ended { reason: "user.hangup".into() }, Direction::Outgoing, None),
        call(2, CallState::Answered { answered_by: "user".into() }, Direction::Outgoing, None),
        call(3, CallState::Ringing, Direction::Incoming, Some("Bob")),
    ] {
        s.apply(&Change::CallAdded { call: c });
    }
    s.apply(&Change::Messaging { mailbox: Some("did:key:z6MkMailbox".into()), connected: true });
    s.apply(&Change::Conversations {
        conversations: vec![ConversationView {
            group: "MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk".into(),
            conversation: "01M6EKRTVG3C55DFMQ401G3MA9".into(),
            kind: "direct".into(),
            peer: Some("did:key:z6MkBob".into()),
            members: vec!["did:key:z6MkAlice".into(), "did:key:z6MkBob".into()],
            pending: 1,
        }],
    });
    s.apply(&Change::Requests { requests: vec![RequestView { id: "01M6EKRTVG3C55DFMQ401G3MB0".into(), from: "did:key:z6MkCarol".into(), name: Some("Carol".into()) }] });
    s.apply(&Change::MyPresence { state: Some("busy".into()) });
    s.apply(&Change::Presence {
        presence: PresenceView { identity: "did:key:z6MkBob".into(), state: Some("away".into()), token: None, source: Some("record".into()), unreadable: 1 },
    });
    s
}

#[test]
fn the_state_the_desktop_app_reads() {
    let update = serde_json::json!({"state": state(), "change": Change::CallChanged { call: state().calls[&3].clone() }});
    let made = serde_json::to_string_pretty(&update).unwrap() + "\n";
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/test/fixtures/state.json");
    if std::env::var_os("UPDATE_FIXTURES").is_some() {
        std::fs::write(&path, &made).unwrap();
    }
    let held = std::fs::read_to_string(&path).unwrap_or_default().replace("\r\n", "\n");
    assert_eq!(held, made, "app/test/fixtures/state.json is not what the app sends: UPDATE_FIXTURES=1 cargo test --test wire_fixture");
}
