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
