//! What a screen shows: [`State`], and the [`Change`]s that move it on. Every change the app makes to its state is
//! published as one `Change`, so a screen (or `dsip-app watch`) that starts from a [`State`] and applies the changes
//! after it is always where the app is.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

/// The app's state.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct State {
    /// Who this app is.
    pub me: Me,
    /// The relay this device is bound to.
    pub relay: String,
    /// Calls up or ringing, by the app's call id, and those that ended since the app started (most recent last). On
    /// the wire, a list of the calls in id order (each carries its id).
    #[serde(with = "calls_list")]
    pub calls: BTreeMap<u64, CallView>,
    /// The audio devices.
    pub audio: Audio,
    /// The app makes and takes video calls here (B§3.4): it has a camera and H.264 ([`crate::video`]).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub video: bool,
    /// Messages: the mailbox, the conversations, the requests to answer.
    pub messaging: Messaging,
    /// This device's presence, and the identities it follows.
    #[serde(default)]
    pub presence: PresenceState,
    /// Waking this device while it sleeps (A5d), once the phone has given its push token; `None`: not woken.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub push: Option<Push>,
    /// The names this device's user gave identities (`SetName`), by identity: shown before a caller's own name.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub names: BTreeMap<String, String>,
    /// The calls that ended, oldest first, kept across restarts ([`crate::HISTORY_FILE`]); at most
    /// [`crate::HISTORY_MAX`].
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub history: Vec<CallRecord>,
    /// A voice message or voicemail being recorded, and what plays.
    #[serde(default)]
    pub voice: Voice,
}

/// Recording and playing voice messages (M§8.2) and voicemail (M§13).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Voice {
    /// The recording, under way or ended (at its limit) and not yet sent or dropped.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording: Option<RecordingView>,
    /// The file playing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub playing: Option<String>,
}

/// A recording ([`Voice::recording`]).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecordingView {
    /// Under way; `false`: it stopped (at its limit, or for a call) and waits to be sent or dropped.
    pub running: bool,
    /// When it started, Unix seconds.
    pub started_at: i64,
    /// Where it stops by itself, milliseconds (a voicemail's `max_duration_s`, M§13.2).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_ms: Option<u64>,
    /// How long it is, once it stopped.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
}

/// A call that ended, as the call history keeps it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CallRecord {
    /// The call's DSIP session id: what `forget_call` names.
    pub session: String,
    /// The other side.
    pub peer: String,
    /// The caller's display name, for an incoming call (a claim, not verified).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer_name: Option<String>,
    /// Placed here, or coming in.
    pub direction: Direction,
    /// Whether it was answered.
    pub answered: bool,
    /// Why it ended (§15 reason token).
    pub reason: String,
    /// When it ended, unix seconds.
    pub ended_at: i64,
}

/// Waking this device while it sleeps (app plan A5d; the Wake Profile): enrolled at the publisher's push gateway with
/// the phone's token, and registered with the relay (calls) and the mailbox (messages).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Push {
    /// The gateway's DID.
    pub gateway: String,
    /// The token's provider: `apns` or `fcm`.
    pub provider: String,
    /// The gateway took the token (W§3).
    pub enrolled: bool,
    /// The relay: calls wake this device.
    pub relay: Registration,
    /// The mailbox: messages wake it; `None` without one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mailbox: Option<Registration>,
    /// Why the last attempt stopped short (the gateway unreachable, …).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Where a registration with a waker stands.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Registration {
    /// `registered`, `not-offered` (the waker wakes no one, W§4.4), `no-token` (no token for its kinds: an iPhone
    /// without PushKit's token for the relay, or without the alert token for the mailbox), `refused` (its `wake.*`
    /// reason), `failed` (no answer; tried again), or `pending` (not tried yet).
    pub status: String,
    /// The refusal's reason, or the failure.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    /// When a registration given ends (it is renewed before, W§4.3).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<i64>,
}

impl Registration {
    pub(crate) fn status(status: &str) -> Registration {
        Registration { status: status.into(), ..Registration::default() }
    }

    pub(crate) fn registered(expires_at: i64) -> Registration {
        Registration { status: "registered".into(), reason: None, expires_at: Some(expires_at) }
    }

    pub(crate) fn refused(reason: &str) -> Registration {
        Registration { status: "refused".into(), reason: Some(reason.into()), expires_at: None }
    }

    pub(crate) fn failed(why: &str) -> Registration {
        Registration { status: "failed".into(), reason: Some(why.into()), expires_at: None }
    }
}

/// Presence's part of the state (Presence Profile, draft).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct PresenceState {
    /// The state this device publishes: `available`, `busy`, `away`, `dnd`, `offline` (invisible); `None`: automatic,
    /// no record (its relay says available while it is bound).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mine: Option<String>,
    /// The identities followed, in DID order.
    pub following: Vec<PresenceView>,
}

/// A followed identity's presence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PresenceView {
    /// The identity.
    pub identity: String,
    /// Its state as P§4 combines its devices' records: `available`, `busy`, `away`, `dnd`, `offline`. `None` until its
    /// relay admits us (it needs a grant of theirs, P§6), and while it refuses.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    /// The token that won, when it is not `state` (an unregistered token, shown raw beside its fallback, P§5).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
    /// `record` (a device of theirs signed it), `assertion` (their relay's claim that they are bound, §9.3), `none`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    /// How many of their devices' records are sealed under keys we do not hold (P§12.3): left out of `state`.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub unreadable: usize,
}

fn is_zero(n: &usize) -> bool {
    *n == 0
}

/// Messaging's part of the state.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Messaging {
    /// The identity's mailbox DID, when messaging is on.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mailbox: Option<String>,
    /// Bound to it now.
    pub connected: bool,
    /// The conversations this device is in (its identity's personal group left out).
    pub conversations: Vec<ConversationView>,
    /// Introductions waiting for an answer (M§14.1).
    pub requests: Vec<RequestView>,
    /// The introductions this identity sent, oldest first, one per identity, kept across restarts
    /// ([`crate::INTRODUCED_FILE`]).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub introduced: Vec<Introduced>,
}

/// An introduction this identity sent (M§14.1).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Introduced {
    /// To whom.
    pub to: String,
    /// The name the user gave them when introducing, kept as the contact's once they accept.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// What it said.
    pub purpose: String,
    /// When it was sent, unix seconds.
    pub sent_at: i64,
    /// They granted permission to message ([`Change::Granted`]).
    pub accepted: bool,
}

/// A conversation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConversationView {
    /// Its group id: what `message` and `thread` name.
    pub group: String,
    /// Its conversation id.
    pub conversation: String,
    /// `direct` or `group`.
    pub kind: String,
    /// The other identity of a direct conversation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer: Option<String>,
    /// Its members' identities.
    pub members: Vec<String>,
    /// Messages sent here not yet accepted by its hub.
    pub pending: usize,
}

/// A message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageView {
    /// The conversation's group id.
    pub conversation: String,
    /// The content id.
    pub id: String,
    /// The sender's identity.
    pub from: String,
    /// Sent from this identity.
    pub mine: bool,
    /// `text`, `audio`, …
    pub kind: String,
    /// Its text, for a text message.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// When it was sent (the sender's clock).
    pub sent_at: i64,
    /// An `image` or `file`'s name (a file's own, M§8.2).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// An attachment's media type.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_type: Option<String>,
    /// An attachment's size in bytes (sealed: a little more than the file's).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    /// An attachment's file on this device, once fetched and decrypted ([`Change::MessageFile`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    /// Why it was sent (M§8.2): an `audio`'s `voice` (a voice message) or `voicemail` (after an unanswered call,
    /// M§13), an attachment's `attachment`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    /// An `audio`'s length, milliseconds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    /// A voicemail's call: the invite's id (M§13.2).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
}

impl MessageView {
    /// The message content object `o` in conversation `group`, as this identity (`me`) sees it; an attachment's file
    /// looked for in `media`.
    pub(crate) fn of(group: &str, o: &serde_json::Value, me: &str, media: &std::path::Path) -> MessageView {
        let from = o["sender"].as_str().unwrap_or("").to_string();
        let has_blob = o.get("blob").is_some_and(|b| b.is_object());
        let path = has_blob
            .then(|| media.join(dsip_messaging_device::blob::file_name(o)))
            .filter(|p| p.is_file())
            .map(|p| p.to_string_lossy().into_owned());
        MessageView {
            conversation: group.to_string(),
            id: o["id"].as_str().unwrap_or("").to_string(),
            mine: from == me,
            from,
            kind: o["kind"].as_str().unwrap_or("").to_string(),
            text: o["text"].as_str().map(String::from),
            sent_at: o["sent_at"].as_i64().unwrap_or(0),
            name: o["name"].as_str().map(String::from),
            content_type: o["blob"]["content_type"].as_str().map(String::from),
            size: o["blob"]["size"].as_u64(),
            path,
            purpose: o["purpose"].as_str().map(String::from),
            duration_ms: o["duration_ms"].as_u64(),
            session: o["session"].as_str().map(String::from),
        }
    }
}

/// An introduction waiting for an answer (M§14.1).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RequestView {
    /// Its id: what `accept_request` and `decline_request` name.
    pub id: String,
    /// Who asks.
    pub from: String,
    /// The name it gives (a claim, not verified).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// What it says: why it asks (opened with this identity's key when it came sealed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
}

/// The identity and this device.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Me {
    /// The identity DID: what others call.
    pub identity: String,
    /// This device's DID.
    pub device: String,
    /// The display name others are shown (a claim, §18.2).
    pub display_name: String,
}

/// One call.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CallView {
    /// The app's id for the call: what commands name.
    pub id: u64,
    /// The DSIP session id.
    pub session: String,
    /// The other side: the identity called, or the caller's verified identity.
    pub peer: String,
    /// The caller's display name, for an incoming call (a claim, not verified).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub peer_name: Option<String>,
    /// Placed here, or coming in.
    pub direction: Direction,
    /// Where it is.
    pub state: CallState,
    /// The microphone is muted for this call.
    pub muted: bool,
    /// Audio from the other side has arrived.
    pub media: bool,
    /// The relay the call goes through when it is not this app's own: the one the callee's hint named (§8.1).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub via: Option<String>,
    /// The reason of a signed `error` about the call, when one came (a relay that could not route it).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// What its sound did on this device, counted, while it rings back or has the devices: where a call's sound
    /// stops on a real device shows here.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sound: Option<CallSound>,
    /// It carries video: offered with it, and the answer took it (B§3.4).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub video: bool,
    /// This side's camera sends to it ([`crate::Command::Camera`]).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub camera: bool,
}

/// A call's sound on this device, counted from when it took the devices ([`CallView::sound`]). Each stage feeds the
/// next, so the first that stays at 0 (or an error) is where the sound stops.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CallSound {
    /// 20 ms frames the microphone gave.
    pub mic: u64,
    /// Of those, Opus frames handed to the call's media to send.
    pub sent: u64,
    /// Opus packets from the other side, as the media received them.
    pub heard: u64,
    /// Of those, packets that decoded to sound.
    pub decoded: u64,
    /// 20 ms frames the speaker took.
    pub played: u64,
    /// 20 ms frames of the ringback tone the speaker took.
    pub ringback: u64,
    /// Why the microphone stopped giving frames, if it did.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mic_error: Option<String>,
    /// Why the speaker refused a frame (the call's, or the ringback's), if it did.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub speaker_error: Option<String>,
    /// The stage that stopped counting while the call went on ([`CallSound::stall`]): `mic`, `sent`, `heard`,
    /// `decoded`, `played` or `ringback`. Where the sound stops, when it does.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stalled: Option<String>,
}

impl CallSound {
    /// The first stage that did not count on since `before`: the ringback while it rings back (`call` false), else
    /// each stage of the call's sound in order, the microphone to the speaker. The far end's stages only once its
    /// media has come (`media`): before, the call says it has no sound.
    pub fn stall(&self, before: &CallSound, call: bool, media: bool) -> Option<&'static str> {
        if !call {
            return (self.ringback <= before.ringback).then_some("ringback");
        }
        let stages = [
            ("mic", self.mic, before.mic),
            ("sent", self.sent, before.sent),
            ("heard", self.heard, before.heard),
            ("decoded", self.decoded, before.decoded),
            ("played", self.played, before.played),
        ];
        let ours = if media { stages.len() } else { 2 };
        stages[..ours].iter().find(|(_, now, then)| now <= then).map(|(stage, _, _)| *stage)
    }
}

/// Which way a call goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Direction {
    /// Placed by this app.
    Outgoing,
    /// Coming in.
    Incoming,
}

/// Where a call is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum CallState {
    /// Placed; not yet ringing anywhere.
    Calling,
    /// Ringing: at the callee, or here, waiting on the user.
    Ringing,
    /// Answered (`answered_by`, §14.3).
    Answered {
        /// `user`, `screening`, `gateway`, …
        answered_by: String,
    },
    /// Over (§15 reason token).
    Ended {
        /// `user.hangup`, `user.busy`, `transport.no-response`, …
        reason: String,
    },
}

impl CallState {
    /// Whether the call is over.
    pub fn ended(&self) -> bool {
        matches!(self, CallState::Ended { .. })
    }
}

/// The audio devices, and which are in use.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Audio {
    /// The audio host: `system` (the platform's devices) or `tone` (a test tone, for headless use).
    pub host: String,
    /// The microphones and speakers the host offers.
    pub devices: Vec<AudioDevice>,
    /// The microphone chosen (its [`AudioDevice::id`]); `None`: the system's default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input: Option<String>,
    /// The speaker chosen; `None`: the system's default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
}

/// A microphone or speaker.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioDevice {
    /// The host's id for it.
    pub id: String,
    /// Its name.
    pub name: String,
    /// A microphone (`input`) or a speaker (`output`).
    pub kind: String,
    /// The system's default of its kind.
    pub default: bool,
}

/// One change to the [`State`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "change")]
pub enum Change {
    /// The names given identities, all of them as they are now.
    Names {
        /// Identity to name.
        names: BTreeMap<String, String>,
    },
    /// A call was placed or came in.
    CallAdded {
        /// The call.
        call: CallView,
    },
    /// A call moved on: its state, its mute, its media, its error.
    CallChanged {
        /// The call as it is now.
        call: CallView,
    },
    /// Messaging bound to its mailbox, or lost it.
    Messaging {
        /// The mailbox DID.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mailbox: Option<String>,
        /// Bound now.
        connected: bool,
    },
    /// The conversations changed (one added, its members, its pending count).
    Conversations {
        /// All of them, as they are now.
        conversations: Vec<ConversationView>,
    },
    /// A message arrived, or this app sent one.
    Message {
        /// The message.
        message: MessageView,
    },
    /// A message's attachment was fetched and decrypted: its file on this device.
    MessageFile {
        /// The conversation's group id.
        conversation: String,
        /// The message's id.
        id: String,
        /// The file.
        path: String,
    },
    /// The introductions waiting for an answer changed.
    Requests {
        /// All of them, as they are now.
        requests: Vec<RequestView>,
    },
    /// An identity this one introduced itself to granted it permission to message (M§14.1): `message` it now. The
    /// grant shares its presence too, which the app now follows.
    Granted {
        /// Who.
        by: String,
    },
    /// Another member removed this identity from a group conversation (M§7.3); it is no longer listed.
    Removed {
        /// The group id.
        conversation: String,
        /// Who removed it.
        by: String,
    },
    /// The state this device publishes changed.
    MyPresence {
        /// The state; `None`: automatic.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        state: Option<String>,
    },
    /// A followed identity's presence changed, or it was followed.
    Presence {
        /// It, as it is now.
        presence: PresenceView,
    },
    /// An identity is no longer followed.
    Unfollowed {
        /// The identity.
        identity: String,
    },
    /// The audio devices changed: those offered, or those chosen.
    Audio {
        /// The audio as it is now.
        audio: Audio,
    },
    /// Waking this device changed: enrolled, registered, refused; `None`: it is not woken (no token).
    Push {
        /// Where it stands.
        push: Option<Push>,
    },
    /// The call history changed: a call ended, or some were deleted.
    History {
        /// All of it, as it is now.
        history: Vec<CallRecord>,
    },
    /// The introductions sent changed: one sent, accepted or deleted.
    Introduced {
        /// All of them, as they are now.
        introduced: Vec<Introduced>,
    },
    /// Recording or playing changed.
    Voice {
        /// As it is now.
        voice: Voice,
    },
    /// The app stopped: its phone unbound.
    Stopped,
}

impl State {
    /// Apply `change`, as a screen following the app does.
    pub fn apply(&mut self, change: &Change) {
        match change {
            Change::CallAdded { call } | Change::CallChanged { call } => {
                self.calls.insert(call.id, call.clone());
            }
            Change::Messaging { mailbox, connected } => {
                self.messaging.mailbox = mailbox.clone();
                self.messaging.connected = *connected;
            }
            Change::Conversations { conversations } => self.messaging.conversations = conversations.clone(),
            Change::Requests { requests } => self.messaging.requests = requests.clone(),
            Change::MyPresence { state } => self.presence.mine = state.clone(),
            Change::Presence { presence } => {
                let f = &mut self.presence.following;
                match f.binary_search_by(|p| p.identity.cmp(&presence.identity)) {
                    Ok(i) => f[i] = presence.clone(),
                    Err(i) => f.insert(i, presence.clone()),
                }
            }
            Change::Unfollowed { identity } => self.presence.following.retain(|p| &p.identity != identity),
            Change::Audio { audio } => self.audio = audio.clone(),
            Change::Push { push } => self.push = push.clone(),
            Change::Names { names } => self.names = names.clone(),
            Change::History { history } => self.history = history.clone(),
            Change::Introduced { introduced } => self.messaging.introduced = introduced.clone(),
            Change::Voice { voice } => self.voice = voice.clone(),
            Change::Message { .. } | Change::MessageFile { .. } | Change::Granted { .. } | Change::Removed { .. } | Change::Stopped => {}
        }
    }
}

/// [`State::calls`] as a JSON list: a map's keys would be strings on the wire.
mod calls_list {
    use std::collections::BTreeMap;

    use serde::{Deserialize, Deserializer, Serializer};

    use super::CallView;

    pub fn serialize<S: Serializer>(calls: &BTreeMap<u64, CallView>, s: S) -> Result<S::Ok, S::Error> {
        s.collect_seq(calls.values())
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<BTreeMap<u64, CallView>, D::Error> {
        Ok(Vec::<CallView>::deserialize(d)?.into_iter().map(|c| (c.id, c)).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Response;

    #[test]
    fn the_state_goes_over_the_wire_and_back() {
        let mut state = State { relay: "wss://relay.test/dsip".into(), ..State::default() };
        let call = CallView {
            id: 7,
            session: "01M6BTTMQ9QMKY9SYTY8415VZ7".into(),
            peer: "did:key:z6Mk".into(),
            peer_name: Some("Alice".into()),
            direction: Direction::Incoming,
            state: CallState::Answered { answered_by: "user".into() },
            muted: false,
            media: true,
            via: None,
            error: None,
            sound: None,
            video: false,
            camera: false,
        };
        state.apply(&Change::CallAdded { call });
        let r = Response::State { state: Box::new(state) };
        let wire = serde_json::to_string(&r).unwrap();
        assert!(wire.contains(r#""calls":[{"id":7"#), "{wire}");
        assert_eq!(serde_json::from_str::<Response>(&wire).unwrap(), r);
    }

    #[test]
    fn a_stage_stalled_is_the_first_that_stopped_counting() {
        let n = |mic, sent, heard, decoded, played, ringback| CallSound { mic, sent, heard, decoded, played, ringback, ..CallSound::default() };
        let before = n(100, 100, 90, 90, 90, 40);
        // every stage counting: none
        assert_eq!(n(200, 200, 190, 190, 190, 40).stall(&before, true, true), None);
        // the speaker takes no more: played; the decoder too: decoded, the one before it
        assert_eq!(n(200, 200, 190, 190, 90, 40).stall(&before, true, true), Some("played"));
        assert_eq!(n(200, 200, 190, 90, 90, 40).stall(&before, true, true), Some("decoded"));
        // nothing from the far end: heard, unless its media has not come (the call says it has no sound)
        assert_eq!(n(200, 200, 90, 90, 90, 40).stall(&before, true, true), Some("heard"));
        assert_eq!(n(200, 200, 90, 90, 90, 40).stall(&before, true, false), None);
        // the microphone stops: mic, whatever the far end does
        assert_eq!(n(100, 100, 190, 190, 190, 40).stall(&before, true, false), Some("mic"));
        assert_eq!(n(200, 100, 190, 190, 190, 40).stall(&before, true, true), Some("sent"));
        // ringing back: only the ringback counts
        assert_eq!(n(100, 100, 90, 90, 90, 90).stall(&before, false, false), None);
        assert_eq!(n(100, 100, 90, 90, 90, 40).stall(&before, false, false), Some("ringback"));
    }
}
