//! The app's calls for the system's call screen, and the phone's push token, without Dart (app plan A5d-2 and A5d-3,
//! as Anvil's A2 and A3; the Wake Profile's W§5.4).
//!
//! A push starts the app in a process where Flutter may never run: the calls Android's Telecom and iOS's CallKit show
//! then come from here, as events native code reads one at a time ([`next_event`]), and what the user does there comes
//! back as a command ([`act`]). The push token is a file in the app's folder (`push.json`), written by native code
//! when the platform hands it a token and given to the app whenever it starts, whoever starts it.
//!
//! Android's native code reaches it through JNI (`android.rs`), iOS's through a C ABI (`ios.rs`). Kept to plain Rust
//! so the host's tests run it.
#![cfg_attr(not(any(target_os = "android", target_os = "ios")), allow(dead_code))]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{mpsc, Mutex, OnceLock};
use std::time::Duration;

use dsip_app::{App, CallState, CallView, Change, Command, Direction, Settings, State};
use serde::{Deserialize, Serialize};

use crate::api::app::{current, running, runtime};

/// What native code says of this install at its start: the app's folder (Dart's application support directory, where
/// `settings.json` is) and the publisher's push gateway, when the build has one.
struct Install {
    dir: PathBuf,
    gateway: Option<String>,
}

static INSTALL: OnceLock<Install> = OnceLock::new();

/// Native code's start: once per process.
pub(crate) fn install(dir: PathBuf, gateway: Option<String>) {
    let _ = INSTALL.set(Install { dir, gateway });
}

/// Where the platform wakes this install (the `Command::Push` it is given at every start): FCM's one token, or an
/// iPhone's two (A5d-4; the Wake Profile, spec-gap 178), PushKit's for calls and APNs' alert token for messages, which
/// the system hands over apart.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct PushToken {
    /// `fcm` or `apns`.
    pub provider: String,
    /// The FCM project or PushKit's APNs topic; empty with no such token yet.
    #[serde(default)]
    pub app: String,
    /// The platform's token (FCM's, or PushKit's); empty: none yet.
    #[serde(default)]
    pub token: String,
    /// APNs only: `sandbox` for a build signed for development; none is `production` (W§3).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub environment: Option<String>,
    /// APNs: the alert token's topic (the bundle ID).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_app: Option<String>,
    /// APNs: the alert token.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_token: Option<String>,
}

impl PushToken {
    fn command(&self) -> Command {
        let calls = !self.token.is_empty();
        Command::Push {
            provider: Some(self.provider.clone()),
            app: calls.then(|| self.app.clone()),
            token: calls.then(|| self.token.clone()),
            environment: self.environment.clone(),
            message_app: self.message_token.as_ref().and(self.message_app.clone()),
            message_token: self.message_token.clone(),
        }
    }

    /// No token at all.
    fn is_empty(&self) -> bool {
        self.token.is_empty() && self.message_token.is_none()
    }
}

/// The push token kept in the app's folder `dir`.
pub(crate) fn push_path(dir: &Path) -> PathBuf {
    dir.join("push.json")
}

/// The push token saved for this install, if there is one.
pub(crate) fn load_push(dir: &Path) -> Option<PushToken> {
    let text = std::fs::read_to_string(push_path(dir)).ok()?;
    match serde_json::from_str(&text) {
        Ok(token) => Some(token),
        Err(e) => {
            tracing::warn!(%e, "the saved push token is unreadable; starting without");
            None
        }
    }
}

/// Keep the push token for the next start, or forget it.
pub(crate) fn save_push(dir: &Path, token: Option<&PushToken>) -> anyhow::Result<()> {
    let path = push_path(dir);
    match token {
        Some(token) => {
            // The platform may hand over a token before the app has been set up, when its folder is not there yet.
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir)?;
            }
            std::fs::write(path, serde_json::to_vec(token)?)?
        }
        None => match std::fs::remove_file(path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e.into()),
            _ => {}
        },
    }
    Ok(())
}

/// The system's call screen following the running app (Android, iOS).
static FOLLOWER: Mutex<Option<tokio::task::JoinHandle<()>>> = Mutex::new(None);

/// Start the app from `settings`, or leave the one running (a push may have started it before the screen did, or the
/// other way round): the build's push gateway when the settings name none, the push token saved, and on a phone the
/// system's call screen following its calls.
pub(crate) async fn start(mut settings: Settings) -> anyhow::Result<()> {
    // One start at a time: a push and the screen may both ask.
    static STARTING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _one = STARTING.lock().await;
    if current().is_some() {
        return Ok(());
    }
    // The keys in the system's store (A6a): an identity made before they were is moved in now.
    dsip_app::keys::use_system_store();
    let identity = settings.identity.clone();
    runtime().spawn_blocking(move || dsip_app::keys::ready_identity(&identity)).await?;
    let install = INSTALL.get();
    if settings.push_gateway.is_none() {
        settings.push_gateway = install.and_then(|i| i.gateway.clone());
    }
    let push = install.and_then(|i| load_push(&i.dir));
    let cfg = settings.config()?;
    let app = runtime().spawn(App::start(cfg)).await??;
    if cfg!(any(target_os = "android", target_os = "ios")) {
        let _guard = runtime().enter();
        *FOLLOWER.lock().unwrap_or_else(|e| e.into_inner()) = Some(follow(app.clone()));
    }
    if let (Some(push), true) = (push, settings.push_gateway.is_some()) {
        let app = app.clone();
        runtime().spawn(async move {
            if let dsip_app::Response::Error { message } = app.command(push.command()).await {
                tracing::warn!(%message, "the push token was not taken");
            }
        });
    }
    *running().lock().unwrap_or_else(|e| e.into_inner()) = Some(app);
    Ok(())
}

/// The app stopped: the system's call screen ends every call it was showing.
pub(crate) fn stopped() {
    if let Some(follower) = FOLLOWER.lock().unwrap_or_else(|e| e.into_inner()).take() {
        follower.abort();
        say(vec![SystemEvent::Reset]);
    }
}

/// Native code's way to the app, woken by a push: start it from the settings saved, unless it runs (its binding
/// comes back by itself, W§5.4).
pub(crate) async fn wake() -> anyhow::Result<()> {
    if current().is_some() {
        return Ok(());
    }
    let install = INSTALL.get().ok_or_else(|| anyhow::anyhow!("not installed"))?;
    let text = std::fs::read_to_string(install.dir.join("settings.json"))
        .map_err(|e| anyhow::anyhow!("no settings to start from: {e}"))?;
    start(serde_json::from_str(&text)?).await
}

/// Which of an install's tokens native code gives.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Tokens {
    /// FCM's one token, or PushKit's.
    Calls,
    /// APNs' alert token (spec-gap 178).
    Messages,
}

/// The tokens kept in `saved`, with `which` now `token` (empty: none) on `app`, and for APNs its `environment`. A
/// token from another provider replaces everything kept.
pub(crate) fn with_token(saved: Option<PushToken>, which: Tokens, provider: &str, app: &str, token: &str, environment: Option<&str>) -> Option<PushToken> {
    let mut t = saved.filter(|t| t.provider == provider).unwrap_or_else(|| PushToken { provider: provider.into(), ..Default::default() });
    t.environment = environment.filter(|e| !e.is_empty()).map(str::to_string);
    match which {
        Tokens::Calls => (t.app, t.token) = (app.into(), token.into()),
        Tokens::Messages => {
            let given = !token.is_empty();
            (t.message_app, t.message_token) = (given.then(|| app.to_string()), given.then(|| token.to_string()))
        }
    }
    (!t.is_empty()).then_some(t)
}

/// Native code's way to the app: one of the platform's push tokens (empty: none), and for APNs its `environment`,
/// kept for every start and given to the app now if it runs.
pub(crate) async fn set_push(which: Tokens, provider: &str, app: &str, token: &str, environment: Option<&str>) -> anyhow::Result<()> {
    let install = INSTALL.get().ok_or_else(|| anyhow::anyhow!("not installed"))?;
    let token = with_token(load_push(&install.dir), which, provider, app, token, environment);
    save_push(&install.dir, token.as_ref())?;
    if let Some(running) = current() {
        let command = token.as_ref().map(PushToken::command).unwrap_or(Command::Push {
            provider: None,
            app: None,
            token: None,
            environment: None,
            message_app: None,
            message_token: None,
        });
        if let dsip_app::Response::Error { message } = runtime().spawn(async move { running.command(command).await }).await? {
            anyhow::bail!(message);
        }
    }
    Ok(())
}

/// What the system's call screen is told.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum SystemEvent {
    /// A call ringing in, and its session: what a wake named it (W§5.2).
    Incoming {
        /// The app's call id.
        id: u64,
        /// Who calls, as a person reads it.
        name: String,
        /// The caller's DID.
        address: String,
        /// The DSIP session id.
        session: String,
    },
    /// A call placed, or one already up when the screen first hears of it.
    Outgoing {
        /// The app's call id.
        id: u64,
        /// Who is called.
        name: String,
        /// Their DID.
        address: String,
    },
    /// Answered.
    Connected {
        /// The app's call id.
        id: u64,
    },
    /// Over.
    Ended {
        /// The app's call id.
        id: u64,
    },
    /// The app stopped: every call it had is over.
    Reset,
}

/// The calls as the system's call screen has them, kept in step with the app's: whether each was told answered.
#[derive(Default)]
pub(crate) struct SystemCalls {
    told: BTreeMap<u64, bool>,
}

fn answered(call: &CallView) -> bool {
    matches!(call.state, CallState::Answered { .. })
}

fn ended(call: &CallView) -> bool {
    matches!(call.state, CallState::Ended { .. })
}

impl SystemCalls {
    /// What the screen needs to hear to show the app's calls as `state` has them (as Dart's `SystemCalls.sync`).
    pub(crate) fn sync(&mut self, state: &State) -> Vec<SystemEvent> {
        let mut said = Vec::new();
        let live: Vec<&CallView> = state.calls.values().filter(|c| !ended(c)).collect();
        for call in &live {
            let up = answered(call);
            match self.told.get_mut(&call.id) {
                None => {
                    let (id, name, address) = (call.id, name_for(call), call.peer.clone());
                    if call.direction == Direction::Incoming && call.state == CallState::Ringing {
                        said.push(SystemEvent::Incoming { id, name, address, session: call.session.clone() });
                    } else {
                        said.push(SystemEvent::Outgoing { id, name, address });
                        if up {
                            said.push(SystemEvent::Connected { id });
                        }
                    }
                    self.told.insert(call.id, up);
                }
                Some(told) if up && !*told => {
                    *told = true;
                    said.push(SystemEvent::Connected { id: call.id });
                }
                Some(_) => {}
            }
        }
        let gone: Vec<u64> = self.told.keys().filter(|id| !live.iter().any(|c| c.id == **id)).copied().collect();
        for id in gone {
            self.told.remove(&id);
            said.push(SystemEvent::Ended { id });
        }
        said
    }
}

/// Who a call is with, as a person reads it: the name it came with (a claim), or the DID shortened as the app shows it.
fn name_for(call: &CallView) -> String {
    call.peer_name.clone().filter(|n| !n.is_empty()).unwrap_or_else(|| short_did(&call.peer))
}

/// `did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK` → `did:key:z6MkhaXg…2doK` (Dart's `shortDid`).
fn short_did(did: &str) -> String {
    let (method, key) = match did.rfind(':') {
        Some(i) => did.split_at(i + 1),
        None => ("", did),
    };
    let chars: Vec<char> = key.chars().collect();
    if chars.len() <= 14 {
        return did.to_string();
    }
    let head: String = chars[..8].iter().collect();
    let tail: String = chars[chars.len() - 4..].iter().collect();
    format!("{method}{head}…{tail}")
}

/// The events not yet read, one JSON object each.
fn queue() -> &'static (mpsc::Sender<String>, Mutex<mpsc::Receiver<String>>) {
    static QUEUE: OnceLock<(mpsc::Sender<String>, Mutex<mpsc::Receiver<String>>)> = OnceLock::new();
    QUEUE.get_or_init(|| {
        let (tx, rx) = mpsc::channel();
        (tx, Mutex::new(rx))
    })
}

fn say(events: Vec<SystemEvent>) {
    for event in events {
        match serde_json::to_string(&event) {
            Ok(json) => {
                let _ = queue().0.send(json);
            }
            Err(e) => tracing::warn!(%e, "a call event did not serialize"),
        }
    }
}

/// The next event for the system's call screen, waiting up to `within`.
pub(crate) fn next_event(within: Duration) -> Option<String> {
    queue().1.lock().unwrap_or_else(|e| e.into_inner()).recv_timeout(within).ok()
}

/// Follow `app`'s calls for the system's call screen until aborted.
fn follow(app: App) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut changes = app.subscribe();
        let mut calls = SystemCalls::default();
        say(calls.sync(&app.state()));
        loop {
            match changes.recv().await {
                Ok(Change::Stopped) | Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
                Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => say(calls.sync(&app.state())),
            }
        }
    })
}

/// What the user did at the system's call screen.
#[derive(Debug, Deserialize)]
pub(crate) struct Action {
    action: String,
    id: u64,
    #[serde(default)]
    on: Option<bool>,
    #[serde(default)]
    reason: Option<String>,
}

/// The command for `action` on the app as `state` has it, if any (as Dart's `SystemCalls._act`): ending a call ringing
/// in declines it; Do Not Disturb or a blocked caller at the system declines a call it would not let ring.
pub(crate) fn command_for(action: &Action, state: &State) -> Option<Command> {
    let call = state.calls.get(&action.id).filter(|c| !ended(c))?;
    let ringing_in = call.direction == Direction::Incoming && call.state == CallState::Ringing;
    let id = Some(action.id);
    Some(match action.action.as_str() {
        "answer" if ringing_in => Command::Answer { call: id },
        "end" if ringing_in => Command::Decline { call: id },
        "end" => Command::Hangup { call: id },
        "failed" if ringing_in && action.reason.as_deref() == Some("filtered") => Command::Decline { call: id },
        "mute" => match action.on.unwrap_or(true) {
            true if !call.muted => Command::Mute { call: id },
            false if call.muted => Command::Unmute { call: id },
            _ => return None,
        },
        _ => return None,
    })
}

/// Carry out what the user did at the system's call screen (`json` an [`Action`]).
pub(crate) async fn act(json: &str) -> anyhow::Result<()> {
    let action: Action = serde_json::from_str(json)?;
    let app = current().ok_or_else(|| anyhow::anyhow!("the app is not running"))?;
    if let Some(command) = command_for(&action, &app.state()) {
        if let dsip_app::Response::Error { message } = runtime().spawn(async move { app.command(command).await }).await? {
            anyhow::bail!(message);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const ANN: &str = "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK";

    fn call(id: u64, direction: Direction, state: CallState) -> CallView {
        CallView {
            id,
            session: format!("01K8S0E8M3000000000INVITE0{id}"),
            peer: ANN.into(),
            peer_name: Some("Ann".into()),
            direction,
            state,
            muted: false,
            media: false,
            via: None,
            error: None,
            sound: None,
            video: false,
            camera: false,
        }
    }

    fn state(calls: Vec<CallView>) -> State {
        State { calls: calls.into_iter().map(|c| (c.id, c)).collect(), ..Default::default() }
    }

    fn up() -> CallState {
        CallState::Answered { answered_by: "user".into() }
    }

    #[test]
    fn a_call_is_told_as_it_goes() {
        let mut calls = SystemCalls::default();
        let mut c = call(7, Direction::Incoming, CallState::Ringing);
        assert_eq!(
            calls.sync(&state(vec![c.clone()])),
            vec![SystemEvent::Incoming {
                id: 7,
                name: "Ann".into(),
                address: ANN.into(),
                session: "01K8S0E8M3000000000INVITE07".into()
            }]
        );
        assert!(calls.sync(&state(vec![c.clone()])).is_empty(), "told once");
        c.state = up();
        assert_eq!(calls.sync(&state(vec![c.clone()])), vec![SystemEvent::Connected { id: 7 }]);
        c.state = CallState::Ended { reason: "user.hangup".into() };
        assert_eq!(calls.sync(&state(vec![c])), vec![SystemEvent::Ended { id: 7 }], "an ended call is over");
        assert!(calls.sync(&state(vec![])).is_empty());
    }

    #[test]
    fn a_call_already_up_is_told_as_placed_and_connected() {
        let mut calls = SystemCalls::default();
        let mut c = call(3, Direction::Incoming, up());
        c.peer_name = None;
        assert_eq!(
            calls.sync(&state(vec![c])),
            vec![
                SystemEvent::Outgoing { id: 3, name: "did:key:z6MkhaXg…2doK".into(), address: ANN.into() },
                SystemEvent::Connected { id: 3 },
            ]
        );
    }

    fn action(json: &str) -> Action {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn what_the_user_does_there_is_a_command() {
        let ringing = state(vec![call(7, Direction::Incoming, CallState::Ringing)]);
        let for_ringing = |json| command_for(&action(json), &ringing);
        assert!(matches!(for_ringing(r#"{"action":"answer","id":7}"#), Some(Command::Answer { call: Some(7) })));
        assert!(matches!(for_ringing(r#"{"action":"end","id":7}"#), Some(Command::Decline { call: Some(7) })));
        assert!(matches!(
            for_ringing(r#"{"action":"failed","id":7,"reason":"filtered"}"#),
            Some(Command::Decline { call: Some(7) })
        ));
        assert!(for_ringing(r#"{"action":"failed","id":7,"reason":"busy"}"#).is_none(), "rings on in the app");
        assert!(for_ringing(r#"{"action":"answer","id":8}"#).is_none(), "no such call");

        let mut on = call(7, Direction::Outgoing, up());
        let talking = state(vec![on.clone()]);
        let for_talking = |json| command_for(&action(json), &talking);
        assert!(matches!(for_talking(r#"{"action":"end","id":7}"#), Some(Command::Hangup { call: Some(7) })));
        assert!(for_talking(r#"{"action":"answer","id":7}"#).is_none());
        assert!(matches!(for_talking(r#"{"action":"mute","id":7,"on":true}"#), Some(Command::Mute { call: Some(7) })));
        assert!(for_talking(r#"{"action":"mute","id":7,"on":false}"#).is_none(), "not muted");
        on.muted = true;
        let muted = state(vec![on]);
        assert!(matches!(
            command_for(&action(r#"{"action":"mute","id":7,"on":false}"#), &muted),
            Some(Command::Unmute { call: Some(7) })
        ));
    }

    #[test]
    fn the_push_token_is_kept_in_the_apps_folder() {
        // A folder not made yet: the platform may give a token before the app is set up.
        let dir = std::env::temp_dir().join(format!("dsip-app-push-{}", std::process::id())).join("support");
        assert_eq!(load_push(&dir), None);
        let token = PushToken { provider: "fcm".into(), app: "dsip-test".into(), token: "token-1".into(), ..Default::default() };
        save_push(&dir, Some(&token)).unwrap();
        assert_eq!(load_push(&dir), Some(token.clone()));
        assert!(matches!(token.command(), Command::Push { token: Some(t), .. } if t == "token-1"));
        save_push(&dir, None).unwrap();
        save_push(&dir, None).unwrap();
        assert_eq!(load_push(&dir), None);
        std::fs::remove_dir_all(dir.parent().unwrap()).unwrap();

        // kept before APNs' environment was: read as production
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(push_path(&dir), r#"{"provider":"apns","app":"com.feryx.dsip.voip","token":"ab12"}"#).unwrap();
        assert!(matches!(load_push(&dir).unwrap().command(), Command::Push { environment: None, .. }));
        std::fs::remove_dir_all(dir.parent().unwrap()).unwrap();
    }

    #[test]
    fn an_iphones_two_tokens_are_kept_together_as_they_come() {
        let voip = |saved, token| with_token(saved, Tokens::Calls, "apns", "com.feryx.dsip.voip", token, Some("sandbox"));
        let alert = |saved, token| with_token(saved, Tokens::Messages, "apns", "com.feryx.dsip", token, Some("sandbox"));

        // the alert token may come first: messages alone
        let t = alert(None, "alert-1").unwrap();
        let Command::Push { token, message_app, message_token, .. } = t.command() else { panic!() };
        assert_eq!((token, message_app.as_deref(), message_token.as_deref()), (None, Some("com.feryx.dsip"), Some("alert-1")));

        // then PushKit's: both, in one command
        let t = voip(Some(t), "voip-1").unwrap();
        let Command::Push { app, token, environment, message_token, .. } = t.command() else { panic!() };
        assert_eq!((app.as_deref(), token.as_deref(), environment.as_deref(), message_token.as_deref()),
                   (Some("com.feryx.dsip.voip"), Some("voip-1"), Some("sandbox"), Some("alert-1")));

        // a token gone leaves the other; both gone, nothing
        let t = alert(Some(t), "").unwrap();
        assert!(matches!(t.command(), Command::Push { token: Some(_), message_token: None, message_app: None, .. }));
        assert_eq!(voip(Some(t), ""), None);

        // another provider's token replaces what was kept
        let kept = alert(None, "alert-1");
        let fcm = with_token(kept, Tokens::Calls, "fcm", "dsip-test", "fcm-1", None).unwrap();
        assert_eq!(fcm.message_token, None);
    }

    #[test]
    fn a_did_is_shortened_as_the_app_shows_it() {
        assert_eq!(short_did(ANN), "did:key:z6MkhaXg…2doK");
        assert_eq!(short_did("did:web:example.com"), "did:web:example.com");
    }
}
