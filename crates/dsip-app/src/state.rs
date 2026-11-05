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
    /// Messages: the mailbox, the conversations, the requests to answer.
    pub messaging: Messaging,
    /// This device's presence, and the identities it follows.
    #[serde(default)]
    pub presence: PresenceState,
    /// Waking this device while it sleeps (A5d), once the phone has given its push token; `None`: not woken.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub push: Option<Push>,
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
    /// `registered`, `not-offered` (the waker wakes no one, W§4.4), `refused` (its `wake.*` reason), `failed` (no
    /// answer; tried again), or `pending` (not tried yet).
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
            Change::Message { .. } | Change::Granted { .. } | Change::Removed { .. } | Change::Stopped => {}
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
        };
        state.apply(&Change::CallAdded { call });
        let r = Response::State { state: Box::new(state) };
        let wire = serde_json::to_string(&r).unwrap();
        assert!(wire.contains(r#""calls":[{"id":7"#), "{wire}");
        assert_eq!(serde_json::from_str::<Response>(&wire).unwrap(), r);
    }
}
