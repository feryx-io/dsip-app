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
        /// A video call (B§3.4), where the app has video; else audio only.
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        video: bool,
    },
    /// Turn the camera on or off in a video call (B§3.4); without `call`, the one whose video is shown.
    Camera {
        /// The app's call id.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        call: Option<u64>,
        /// On or off.
        on: bool,
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
        /// What to call it here: its contact's name once it accepts ([`Command::SetName`]); never sent.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
    },
    /// Delete an introduction from the list of those sent (it is not withdrawn: they may still accept it).
    ForgetIntroduction {
        /// To whom it went.
        to: String,
    },
    /// Grant a request's sender permission to message (M§14.1). The sender becomes a contact: named as it names
    /// itself, unless it has a name here already.
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
    /// Send a file: to a conversation or an identity, as [`Command::Message`] sends a text. Sealed and uploaded to
    /// this identity's mailbox, and sent as an `image` (by its media type) or a `file` (M§8.2, M§8.4).
    SendFile {
        /// A group id or an identity DID.
        to: String,
        /// The file on this device.
        path: String,
        /// The name it is sent under; without one, the file's own.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
    },
    /// Record a voice message, or a voicemail, from the microphone (M§8.2, M§13): to an Ogg/Opus file, until
    /// [`Command::StopRecording`] or `max_s` (a voicemail's limit, M§13.2). Not while a call has the microphone.
    Record {
        /// Stop by itself after this many seconds.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max_s: Option<u32>,
    },
    /// Stop the recording and answer with it ([`Response::Recorded`]), to send with [`Command::SendAudio`].
    StopRecording,
    /// Stop the recording and drop it.
    CancelRecording,
    /// Send a recording ([`Response::Recorded`]'s file): to a conversation or an identity, sealed and uploaded as
    /// [`Command::SendFile`] does, as an `audio` content (M§8.2).
    SendAudio {
        /// A group id or an identity DID.
        to: String,
        /// The Ogg/Opus file.
        path: String,
        /// `voice-message` (the default) or `voicemail` (M§13): M§8.2's purposes. `voice`, which earlier versions
        /// sent, is taken as `voice-message`.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        purpose: Option<String>,
        /// A voicemail's call: the session of the attempt that went unanswered (M§13.2).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        session: Option<String>,
    },
    /// Play an Ogg/Opus file (a voice message, a voicemail) to the speaker; one playing before stops.
    Play {
        /// The file.
        path: String,
    },
    /// Stop playing.
    StopPlaying,
    /// After a call to `to` ended with `reason`, whether to offer to leave a voicemail (M§13.2): `to`'s mailbox
    /// entry takes voicemail, this identity can message them, and the outcome is one that offers. Answers
    /// [`Response::Voicemail`].
    VoicemailOffer {
        /// The callee.
        to: String,
        /// How the attempt ended (§15): `user.declined`, `session.timeout`, …
        reason: String,
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
    /// Give an identity a name on this device, or with no `name` (or a blank one), take its name away. The app's own
    /// address book: kept in [`crate::NAMES_FILE`], shown in place of the identity, never sent. At most
    /// [`crate::NAME_MAX`] characters, no control characters.
    SetName {
        /// The identity.
        identity: String,
        /// Its name.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
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
    /// Be woken while asleep (A5d): `token` is the phone's platform push token (`provider` `apns` or `fcm`, `app` the
    /// APNs topic or FCM project, `environment` APNs's `production` or `sandbox`), enrolled at the push gateway and
    /// registered with the relay and the mailbox; without a token, stop being woken. Answers at once; the state's
    /// `push` follows ([`Change::Push`](crate::Change)). Needs a push gateway in the settings.
    Push {
        /// `apns` or `fcm`.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        provider: Option<String>,
        /// The APNs topic or FCM project.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        app: Option<String>,
        /// The token; none: stop being woken.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        token: Option<String>,
        /// APNs only.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        environment: Option<String>,
        /// APNs' alert token's topic (the bundle ID), when `token` is PushKit's: messages wake through it, as APNs takes
        /// each token for its own topic only (the Wake Profile, spec-gap 178). FCM's one token serves both.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message_app: Option<String>,
        /// The alert token.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message_token: Option<String>,
    },
    /// Read a push that woke this app ([`Response::Wake`]): `data` is its `dsip-wake` data as the system delivered it.
    OpenWake {
        /// The push's data.
        data: serde_json::Value,
    },
    /// Delete one message of a conversation, on this device only (the others keep theirs).
    DeleteMessage {
        /// The conversation's group id.
        conversation: String,
        /// The message's id ([`MessageView::id`](crate::MessageView)).
        id: String,
    },
    /// Delete a conversation's messages on this device. A direct conversation is no longer listed until a message
    /// comes or goes in it again; a group conversation is left too ([`Command::Leave`]).
    DeleteConversation {
        /// The group id.
        conversation: String,
    },
    /// Delete one call from the call history.
    ForgetCall {
        /// The call's session id ([`CallRecord::session`](crate::CallRecord)).
        session: String,
    },
    /// Delete the whole call history.
    ClearHistory,
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
    /// What a push said, for [`Command::OpenWake`] (W§5.3, W§6): its `kind` (`call`, `call-ended`, `message`), the
    /// `waker` to bind to, the call's `session`, and for a call the caller as the relay's sealed hint names them: a
    /// claim, to show until the invite arrives and verifies.
    Wake {
        /// `call`, `call-ended`, `message`.
        kind: String,
        /// The relay or mailbox that woke it.
        waker: String,
        /// The call's session.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        session: Option<String>,
        /// The caller's device, from the hint.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        from: Option<String>,
        /// The identity the caller's device acts for, from the hint.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        on_behalf_of: Option<String>,
    },
    /// A recording, stopped ([`Command::StopRecording`]).
    Recorded {
        /// Its Ogg/Opus file.
        path: String,
        /// Its length, milliseconds.
        duration_ms: u64,
    },
    /// Whether to offer a voicemail ([`Command::VoicemailOffer`]), and its limit.
    Voicemail {
        /// Offer it.
        offer: bool,
        /// The callee's limit, seconds (M§4.2 `voicemail.max_duration_s`).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max_duration_s: Option<u32>,
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
