//! What the app is asked to do ([`Command`]) and what it answers ([`Response`]): the same values from a screen, from
//! the CLI over the control socket, and from a test.

use serde::{Deserialize, Serialize};

use crate::state::State;

/// A command. On the control socket, one JSON object per line: `{"command":"call","to":"did:key:…"}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "command")]
pub enum Command {
    /// The whole state.
    State,
    /// Call an identity (every device it has bound rings) or one device.
    Call {
        /// The DID called.
        to: String,
    },
    /// Answer a call ringing here; without `call`, the one ringing longest.
    Answer {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
    },
    /// Decline a call ringing here; without `call`, the one ringing longest.
    Decline {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
    },
    /// End a call: cancel it before the answer, hang up after (§12.11); without `call`, the latest one not ended.
    Hangup {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
    },
    /// Stop sending the microphone on a call; without `call`, the latest one not ended.
    Mute {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
    },
    /// Send the microphone again.
    Unmute {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
    },
    /// Ask an identity for permission to message it (M§14.1); it sees a request, and its `accept_request` is the
    /// grant.
    Introduce {
        /// The identity.
        to: String,
        /// Why: shown to it, sealed to it on the wire.
        purpose: String,
    },
    /// Grant a request's sender permission to message (M§14.1).
    AcceptRequest {
        /// The request's id ([`RequestView::id`](crate::RequestView)).
        id: String,
    },
    /// Forget a request, unanswered.
    DeclineRequest {
        /// The request's id.
        id: String,
    },
    /// Send a text: to a conversation (its group id), or to an identity, in your direct conversation with it, made
    /// when there is none yet (it must have granted you permission, or be in a conversation with you).
    Message {
        /// A group id or an identity DID.
        to: String,
        /// The text.
        text: String,
    },
    /// Make a group conversation with these identities (M§7.3): each must have granted you permission to message
    /// (accepting your introduction does). Answers with its group id.
    CreateGroup {
        /// The other members' identities.
        members: Vec<String>,
    },
    /// Add an identity to a group conversation (it must have granted you; any member may add, M§7.3).
    AddMember {
        /// The group id.
        conversation: String,
        /// The identity.
        identity: String,
    },
    /// Remove a member identity, every device of it, from a group conversation (any member may, M§7.3).
    RemoveMember {
        /// The group id.
        conversation: String,
        /// The identity.
        identity: String,
    },
    /// Leave a conversation: the removal of your devices is proposed, another member commits it, and it is no longer
    /// listed (M§7.3).
    Leave {
        /// The group id.
        conversation: String,
    },
    /// Publish this device's presence: `available`, `busy`, `away`, `dnd`, or `offline` (invisible); without `state`,
    /// automatic (no record: the relay says available while bound). Spec: P§3, P§5.
    SetPresence {
        /// The state.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        state: Option<String>,
    },
    /// Follow an identity's presence. It shows once its relay admits us: it must have granted us (accepting our
    /// introduction does). Spec: §9.3, P§6.
    WatchPresence {
        /// The identity.
        identity: String,
    },
    /// Stop following an identity's presence.
    UnwatchPresence {
        /// The identity.
        identity: String,
    },
    /// Withdraw every grant we issued to an identity: what they admitted at our relay, calls and following our
    /// presence, ends (P§7), and the presence keys rotate (P§12.5), sent to every other grantee. Spec: §19.4, P§7,
    /// P§12.5.
    RevokeGrants {
        /// The grantee.
        identity: String,
    },
    /// Use these audio devices (their [`AudioDevice::id`](crate::AudioDevice)s; without one, the system's default of
    /// its kind) for calls from now on, and the call that has the devices moves to them. The platform's host only.
    ChooseAudio {
        /// The microphone.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        input: Option<String>,
        /// The speaker.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        output: Option<String>,
    },
    /// Look at the audio devices again (one plugged in or out); answers with [`Response::Ok`] after a
    /// [`Change::Audio`](crate::Change).
    AudioDevices,
    /// A conversation's messages, oldest first.
    Thread {
        /// Its group id.
        conversation: String,
    },
    /// After the answer, every [`Change`](crate::Change), one per line, until the client goes (control socket only).
    Subscribe,
    /// Stop the app.
    Quit,
}

/// The answer to a [`Command`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "response")]
pub enum Response {
    /// Done.
    Ok,
    /// The state, for [`Command::State`].
    State {
        /// The state.
        state: Box<State>,
    },
    /// The call placed or acted on.
    Call {
        /// The app's call id.
        call: u64,
    },
    /// The conversation a message went to.
    Conversation {
        /// Its group id.
        conversation: String,
    },
    /// How many grants [`Command::RevokeGrants`] withdrew.
    Revoked {
        /// How many.
        count: usize,
    },
    /// A conversation's messages, for [`Command::Thread`].
    Thread {
        /// Oldest first.
        messages: Vec<crate::MessageView>,
    },
    /// Not done, and why.
    Error {
        /// Why.
        message: String,
    },
}

impl Response {
    /// An error response.
    pub fn error(message: impl Into<String>) -> Response {
        Response::Error { message: message.into() }
    }
}
