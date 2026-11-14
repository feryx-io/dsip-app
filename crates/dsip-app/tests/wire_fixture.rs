//! The desktop app reads the app's state as JSON (`app/lib/src/client/models.dart`). This makes that JSON from a
//! state with every part filled, and holds it to `app/test/fixtures/state.json`, which the app's own tests read: a
//! change here that the Dart readers do not follow fails one side or the other. `UPDATE_FIXTURES=1` writes the file
//! again.

use dsip_app::{
    AudioDevice, AudioState, CallRecord, CallSound, CallState, CallView, Change, ConversationView, Direction, Introduced, Me, MessageView,
    PresenceView, RequestView, Mailbox, Response, Settings, State,
};

fn state() -> State {
    let mut s = State {
        me: Me { identity: "did:key:z6MkAlice".into(), device: "did:key:z6MkAliceLaptop".into(), display_name: "Alice".into() },
        relay: "wss://relay.example.com:8443/dsip".into(),
        audio: AudioState {
            host: "system".into(),
            devices: vec![AudioDevice { id: "mic-1".into(), name: "Built-in microphone".into(), kind: "input".into(), default: true }],
            ..AudioState::default()
        },
        video: true,
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
        sound: (id == 2).then(|| CallSound {
            mic: 250,
            sent: 250,
            heard: 248,
            decoded: 248,
            played: 0,
            ringback: 100,
            mic_error: None,
            speaker_error: Some("speaker: stream disconnected".into()),
            stalled: Some("played".into()),
        }),
        video: id == 2,
        camera: id == 2,
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
    s.apply(&Change::Requests { requests: vec![RequestView { id: "01M6EKRTVG3C55DFMQ401G3MB0".into(), from: "did:key:z6MkCarol".into(), name: Some("Carol".into()),
                                                                 purpose: Some("We met at the conference".into()) }] });
    s.apply(&Change::Introduced {
        introduced: vec![Introduced { to: "did:key:z6MkDave".into(), name: Some("Dave".into()), purpose: "Lunch on Friday?".into(),
                                      sent_at: 1_794_200_000, accepted: false }],
    });
    s.apply(&Change::History {
        history: vec![
            CallRecord { session: "01M6BTTMQ9QMKY9SYTY8415VZ0".into(), peer: "did:key:z6MkBob".into(), peer_name: None,
                         direction: Direction::Outgoing, answered: true, reason: "user.hangup".into(), ended_at: 1_794_200_100 },
            CallRecord { session: "01M6BTTMQ9QMKY9SYTY8415VZ9".into(), peer: "did:key:z6MkCarol".into(), peer_name: Some("Carol".into()),
                         direction: Direction::Incoming, answered: false, reason: "user.cancelled".into(), ended_at: 1_794_200_200 },
        ],
    });
    s.apply(&Change::Names { names: [("did:key:z6MkCarol".to_string(), "Carol Jones".to_string())].into() });
    s.apply(&Change::MyPresence { state: Some("busy".into()) });
    s.apply(&Change::Presence {
        presence: PresenceView { identity: "did:key:z6MkBob".into(), state: Some("away".into()), token: None, source: Some("record".into()), unreadable: 1 },
    });
    s
}

/// `value` as `app/test/fixtures/<name>`, held to the file (or written to it with `UPDATE_FIXTURES=1`).
fn holds(name: &str, value: serde_json::Value) {
    let made = serde_json::to_string_pretty(&value).unwrap() + "\n";
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/test/fixtures").join(name);
    if std::env::var_os("UPDATE_FIXTURES").is_some() {
        std::fs::write(&path, &made).unwrap();
    }
    let held = std::fs::read_to_string(&path).unwrap_or_default().replace("\r\n", "\n");
    assert_eq!(held, made, "app/test/fixtures/{name} is not what the app sends: UPDATE_FIXTURES=1 cargo test --test wire_fixture");
}

#[test]
fn the_state_the_desktop_app_reads() {
    holds("state.json", serde_json::json!({"state": state(), "change": Change::CallChanged { call: state().calls[&3].clone() }}));
}

#[test]
fn the_messages_the_desktop_app_reads() {
    let message = |id: &str, from: &str, mine, text: Option<&str>, kind: &str, sent_at| MessageView {
        conversation: "MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk".into(),
        id: id.into(),
        from: from.into(),
        mine,
        kind: kind.into(),
        text: text.map(String::from),
        sent_at,
        name: None,
        content_type: None,
        size: None,
        path: None,
        purpose: None,
        duration_ms: None,
        session: None,
    };
    let file = MessageView {
        name: Some("plan.pdf".into()),
        content_type: Some("application/pdf".into()),
        size: Some(48_213),
        path: Some("/home/alice/.local/share/dsip/media/01M6EKRTVG3C55DFMQ401G3MC4-plan.pdf".into()),
        ..message("01M6EKRTVG3C55DFMQ401G3MC4", "did:key:z6MkBob", false, None, "file", 1_793_600_180)
    };
    let thread = Response::Thread {
        messages: vec![
            message("01M6EKRTVG3C55DFMQ401G3MC1", "did:key:z6MkAlice", true, Some("hello Bob"), "text", 1_793_600_000),
            MessageView {
                content_type: Some("audio/ogg; codecs=opus".into()),
                size: Some(9_421),
                path: Some("/home/alice/.local/share/dsip/media/01M6EKRTVG3C55DFMQ401G3MC2.ogg".into()),
                purpose: Some("voice-message".into()),
                duration_ms: Some(4_200),
                ..message("01M6EKRTVG3C55DFMQ401G3MC2", "did:key:z6MkBob", false, None, "audio", 1_793_600_060)
            },
            MessageView {
                content_type: Some("audio/ogg; codecs=opus".into()),
                size: Some(21_870),
                purpose: Some("voicemail".into()),
                duration_ms: Some(12_640),
                session: Some("01M6EKRTVG3C55DFMQ401G3MC0".into()),
                ..message("01M6EKRTVG3C55DFMQ401G3MC5", "did:key:z6MkBob", false, None, "audio", 1_793_600_070)
            },
            file,
        ],
    };
    let arrived = Change::Message { message: message("01M6EKRTVG3C55DFMQ401G3MC3", "did:key:z6MkBob", false, Some("hi Alice"), "text", 1_793_600_120) };
    holds("messages.json", serde_json::json!({
        "thread": thread,
        "message": arrived,
        "conversation": Response::Conversation { conversation: "MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk".into() },
        "granted": Change::Granted { by: "did:key:z6MkBob".into() },
        "message_file": Change::MessageFile { conversation: "MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk".into(), id: "01M6EKRTVG3C55DFMQ401G3MC4".into(),
                                              path: "/home/alice/.local/share/dsip/media/01M6EKRTVG3C55DFMQ401G3MC4-plan.pdf".into() },
        "removed": Change::Removed { conversation: "MDFNNkVLUlRWRzNDNTVERk1RNDAxRzNNQTk".into(), by: "did:key:z6MkCarol".into() },
    }));
}

#[test]
fn the_presence_the_desktop_app_reads() {
    let view = |identity: &str, state: Option<&str>, token: Option<&str>, source: Option<&str>, unreadable| PresenceView {
        identity: identity.into(),
        state: state.map(String::from),
        token: token.map(String::from),
        source: source.map(String::from),
        unreadable,
    };
    holds("presence.json", serde_json::json!({
        "following": [
            view("did:key:z6MkBob", Some("away"), None, Some("record"), 1),
            view("did:key:z6MkCarol", Some("available"), None, Some("assertion"), 0),
            view("did:key:z6MkDave", Some("busy"), Some("in-a-meeting"), Some("record"), 0),
            view("did:key:z6MkErin", None, None, None, 0),
        ],
        "revoked": Response::Revoked { count: 2 },
    }));
}

#[test]
fn the_settings_the_desktop_app_reads_and_writes() {
    let device = |id: &str, name: &str, kind: &str, default| AudioDevice { id: id.into(), name: name.into(), kind: kind.into(), default };
    let audio = AudioState {
        host: "system".into(),
        devices: vec![
            device("mic-1", "Built-in microphone", "input", true),
            device("mic-2", "USB headset", "input", false),
            device("spk-1", "Built-in speakers", "output", true),
            device("spk-2", "USB headset", "output", false),
        ],
        input: None,
        output: Some("spk-2".into()),
    };
    // what the settings screen saves: `Settings` with every field it edits
    let settings = Settings {
        identity: "/home/alice/.local/share/dsip/identity".into(),
        relay: "wss://relay.example.com:8443/dsip".into(),
        audio_input: Some("mic-2".into()),
        audio_output: Some("spk-2".into()),
        stun: vec!["stun:stun.example.com:3478".into()],
        mailbox: Some(Mailbox { uri: "wss://mailbox.example.com:9443/dsip".into(), did: "did:key:z6MkMailbox".into() }),
        hints_nodes: vec!["https://hints.example.com:8090".into()],
        ..Settings::default()
    };
    let value = serde_json::json!({"audio": Change::Audio { audio }, "settings": settings});
    holds("settings.json", value.clone());
    // and what the app saves, the app reads
    assert_eq!(serde_json::from_value::<Settings>(value["settings"].clone()).unwrap(), settings);
}
