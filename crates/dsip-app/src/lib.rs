//! `dsip-app` — the running DSIP client (app plan stage A2): one long-lived [`App`] that owns the identity and a
//! [`dsip_phone::Phone`], keeps the [`State`] a screen shows, publishes every change to it as one [`Change`], and
//! carries out [`Command`]s. A screen, the CLI (through the [`control`] socket) and a test drive the same `App`, so
//! they cannot behave differently.
//!
//! ```no_run
//! # async fn demo() -> Result<(), dsip_app::Error> {
//! use dsip_app::{App, Command, Config};
//!
//! let identity = dsip_phone::Identity::load(std::path::Path::new("alice"))?;
//! let app = App::start(Config::new(identity, "wss://relay.example:8443/dsip")).await?;
//! let mut changes = app.subscribe();
//! app.command(Command::Call { to: "did:key:z6Mk…".into(), video: false }).await;
//! while let Ok(change) = changes.recv().await {
//!     println!("{change:?}");
//! }
//! # Ok(()) }
//! ```
//!
//! Every protocol decision stays in dsip-rs: the phone's endpoint core and call glue choose what is sent and when
//! media starts. This crate adds the state, the commands, the devices ([`audio`]) and the control socket.

#![deny(missing_docs)]

pub mod audio;
pub mod backup;
mod command;
pub mod control;
pub mod keys;
pub mod messaging;
pub mod pairing;
pub mod servers;
pub mod video;
mod settings;
mod state;
#[cfg(windows)]
mod user_only;
pub mod wake;
pub mod web;

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::{broadcast, mpsc};

pub use audio::HostKind;
pub use command::{Command, Response};
pub use messaging::MessagingConfig;
pub use settings::{init_identity, Mailbox, Settings};
pub use wake::WakeConfig;
pub use state::{
    Audio as AudioState, AudioDevice, CallRecord, CallSound, CallState, CallView, Change, ConversationView, Direction, Introduced, Me, MessageView,
    Messaging, PresenceState, PresenceView, Push, RecordingView, Registration, RequestView, State, Voice,
};

/// This build's version: the release's (a tag `vX.Y.Z` is this crate's version, `.github/workflows/release.yml`).
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Where the identities followed are kept, in the identity directory beside the phone's `contacts.json`.
pub const FOLLOWING_FILE: &str = "following.json";

/// The names this device's user gave identities, kept in the identity directory: the app's own address book, never
/// sent anywhere.
pub const NAMES_FILE: &str = "names.json";

/// The call history ([`State::history`]), kept in the identity directory.
pub const HISTORY_FILE: &str = "calls.json";

/// Where recordings are made, in the identity's folder: each is moved to the media folder when sent, deleted when
/// dropped.
pub const RECORDINGS_DIR: &str = "recordings";

/// Calls kept in the history, the most recent.
pub const HISTORY_MAX: usize = 200;

/// The introductions sent ([`Messaging::introduced`]), kept in the identity directory.
pub const INTRODUCED_FILE: &str = "introductions.json";

/// The direct conversations deleted and not listed until a message comes or goes in them again, by group id, kept in
/// the identity directory.
pub const HIDDEN_FILE: &str = "hidden.json";

/// The longest name the user may give an identity, in characters.
pub const NAME_MAX: usize = 64;

/// The presence states a device may publish (the `dsip-presence-state` registry, P§5).
pub const PRESENCE_STATES: &[&str] = &["available", "busy", "away", "dnd", "offline"];

/// Ended calls kept in [`State::calls`], the most recent.
pub const ENDED_KEPT: usize = 20;

/// Why the app could not start.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// The phone: the identity, the relay, the binding.
    #[error(transparent)]
    Phone(#[from] dsip_phone::Error),
    /// The identity directory.
    #[error(transparent)]
    Identity(#[from] dsip_transport::Error),
    /// The audio devices.
    #[error("audio: {0}")]
    Audio(String),
    /// The settings: a value they hold, or a file they name.
    #[error("settings: {0}")]
    Settings(String),
    /// The messaging state, or its thread.
    #[error("messaging: {0}")]
    Messaging(String),
    /// Where the identity's keys are kept ([`keys`]).
    #[error("keys: {0}")]
    Keys(String),
}

/// How the app runs.
pub struct Config {
    /// Who it is.
    pub identity: dsip_phone::Identity,
    /// The relay it binds to (`wss://…/dsip`).
    pub relay: String,
    /// TLS for the relay; `None`: the platform's roots.
    pub tls: Option<Arc<rustls::ClientConfig>>,
    /// How it reaches the relay; `None`: over the network. Tests bind through `dsip-testkit`'s.
    pub dialer: Option<Arc<dyn dsip_phone::Dialer>>,
    /// Calls with sound (`Some`: through this host) or signalled only (`None`).
    pub audio: Option<HostKind>,
    /// Video calls through this host ([`video`]), on a platform that has video and with sound; `None`: audio only.
    pub video: Option<HostKind>,
    /// STUN servers for the calls' media.
    pub stun: Vec<String>,
    /// Where calls get TURN credentials, for when no direct path opens between the two sides (a phone on a mobile
    /// network): the relay's `/turn`. `None`: STUN only.
    pub turn: Option<dsip_transport::turn::TurnClient>,
    /// Messages through the identity's mailbox; `None`: calls only.
    pub messaging: Option<MessagingConfig>,
    /// The hints tier (§8.1): a `did:key` callee bound to another relay is called through it. Without messaging, the
    /// app publishes its own hint here, naming its relay (with messaging, the messaging thread does, with the mailbox).
    pub hints: Option<dsip_transport::hints::HintsClient>,
    /// How to reach other relays without `wss` (tests: `dsip-testkit`'s `Network::peers`).
    pub peer_dialer: Option<Arc<dyn dsip_transport::agent::PeerDialer>>,
    /// Seal this device's presence records (P§12): only the holders of its grants read them, never a relay. On by
    /// default.
    pub seal_presence: bool,
    /// The microphone and speaker to use (their [`AudioDevice::id`]s), `None` for the system's default of the kind.
    /// One no longer there is left for the default, with a warning.
    pub audio_devices: (Option<String>, Option<String>),
    /// Waking this device while it sleeps (A5d): the publisher's push gateway; `None`: never woken.
    pub wake: Option<WakeConfig>,
}

impl Config {
    /// `identity` bound to `relay`, with the platform's audio devices and no STUN.
    pub fn new(identity: dsip_phone::Identity, relay: &str) -> Config {
        Config {
            identity,
            relay: relay.into(),
            tls: None,
            dialer: None,
            audio: Some(HostKind::System),
            video: Some(HostKind::System),
            stun: vec![],
            turn: None,
            messaging: None,
            hints: None,
            peer_dialer: None,
            seal_presence: true,
            audio_devices: (None, None),
            wake: None,
        }
    }
}

/// What a call's task is asked to do.
enum Action {
    Accept,
    Decline,
    HangUp,
}

/// The app's hold on one call.
struct CallCtl {
    actions: mpsc::UnboundedSender<Action>,
    muted: Arc<AtomicBool>,
}

pub(crate) struct Inner {
    pub(crate) phone: dsip_phone::Phone,
    pub(crate) state: std::sync::Mutex<State>,
    changes: broadcast::Sender<Change>,
    calls: std::sync::Mutex<HashMap<u64, CallCtl>>,
    next_id: AtomicU64,
    audio: Option<audio::Audio>,
    /// The calls' video, where there is one ([`Config::video`]).
    video: Option<video::Video>,
    messaging: std::sync::OnceLock<mpsc::UnboundedSender<messaging::Req>>,
    stopped: tokio::sync::watch::Sender<bool>,
    /// The identities followed, kept across restarts ([`FOLLOWING_FILE`] in the identity directory); held while
    /// writing it.
    following_file: std::sync::Mutex<std::path::PathBuf>,
    /// The names given identities ([`NAMES_FILE`] in the identity directory); held while writing it.
    names_file: std::sync::Mutex<std::path::PathBuf>,
    /// The identity's folder.
    identity_dir: std::path::PathBuf,
    /// The direct conversations deleted ([`HIDDEN_FILE`]): not listed until a message comes or goes in one again.
    pub(crate) hidden: std::sync::Mutex<std::collections::BTreeSet<String>>,
    /// The waking task, when the app has a push gateway.
    wake: std::sync::OnceLock<mpsc::UnboundedSender<wake::Kick>>,
    /// Whether `busy` is published for a call while the user's presence is automatic ([`App::auto_presence`]).
    auto_busy: AtomicBool,
}

/// The running client. Cheap to clone; clones are the same app.
#[derive(Clone)]
pub struct App {
    pub(crate) inner: Arc<Inner>,
}

impl App {
    /// Bind `cfg.identity` to its relay and start: incoming calls ring, commands are taken.
    pub async fn start(cfg: Config) -> Result<App, Error> {
        let audio = match cfg.audio {
            Some(kind) => Some(audio::Audio::new(kind).map_err(Error::Audio)?),
            None => None,
        };
        if let (Some(a), (input, output)) = (&audio, &cfg.audio_devices) {
            if input.is_some() || output.is_some() {
                // Impl: a device chosen before and gone now (unplugged) is no reason not to start: the default serves
                if let Err(e) = a.choose(input.as_deref(), output.as_deref()) {
                    tracing::warn!("audio devices {input:?}, {output:?}: {e}; the system's defaults instead");
                }
            }
        }
        let me = Me {
            identity: cfg.identity.meta.identity.clone(),
            device: cfg.identity.meta.device.clone(),
            display_name: cfg.identity.meta.display_name.clone(),
        };
        let identity_dir = cfg.identity.dir.clone();
        // the relay-only hint, when no messaging thread publishes one with the mailbox
        let relay_hint = match (&cfg.hints, cfg.messaging.is_none()) {
            (Some(h), true) => Some((
                h.clone(),
                cfg.identity.device.clone(),
                cfg.identity.delegation.clone(),
                cfg.identity.key_agreement.as_ref().map(|k| k.delegation.clone()),
            )),
            _ => None,
        };
        let mut b = dsip_phone::Phone::builder().identity(cfg.identity).relay(&cfg.relay).answer(dsip_phone::AnswerPolicy::Ring);
        if let Some(t) = cfg.tls {
            b = b.tls(t);
        }
        if let Some(d) = cfg.dialer {
            b = b.dialer(d);
        }
        // video only with sound: it rides the call's media leg next to the audio
        let video = audio.as_ref().and(cfg.video).and_then(video::Video::new);
        if let Some(a) = &audio {
            let mut media = a.media(cfg.stun);
            media.video = video.as_ref().map(video::Video::media);
            b = b.media(dsip_phone::Media::Native(media));
        }
        if let Some(h) = &cfg.hints {
            b = b.hints(h.clone());
        }
        if let Some(t) = cfg.turn {
            b = b.turn(t);
        }
        if let Some(p) = cfg.peer_dialer {
            b = b.configure(move |c| c.peer_dialer = Some(p));
        }
        if cfg.seal_presence {
            b = b.seal_presence();
        }

        let phone = b.build().await?;
        let relay = cfg.relay.clone();
        let saved = |file: &str| std::fs::read(identity_dir.join(file)).ok();
        let state = State {
            me,
            messaging: Messaging {
                introduced: saved(INTRODUCED_FILE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default(),
                ..Messaging::default()
            },
            history: saved(HISTORY_FILE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default(),
            presence: PresenceState::default(),
            push: None,
            names: std::fs::read(identity_dir.join(NAMES_FILE)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default(),
            relay: cfg.relay,
            calls: Default::default(),
            audio: audio.as_ref().map(|a| a.view()).unwrap_or_else(|| AudioState { host: "none".into(), ..Default::default() }),
            video: video.is_some(),
            voice: Default::default(),
        };
        let (changes, _) = broadcast::channel(256);
        let app = App {
            inner: Arc::new(Inner {
                phone,
                state: std::sync::Mutex::new(state),
                changes,
                calls: Default::default(),
                next_id: AtomicU64::new(1),
                audio,
                video,
                messaging: std::sync::OnceLock::new(),
                stopped: tokio::sync::watch::channel(false).0,
                following_file: std::sync::Mutex::new(identity_dir.join(FOLLOWING_FILE)),
                names_file: std::sync::Mutex::new(identity_dir.join(NAMES_FILE)),
                hidden: std::sync::Mutex::new(saved(HIDDEN_FILE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()),
                identity_dir: identity_dir.clone(),
                wake: std::sync::OnceLock::new(),
                auto_busy: AtomicBool::new(false),
            }),
        };
        if let Some(m) = cfg.messaging {
            let tx = messaging::spawn(app.clone(), m, identity_dir.clone(), relay.clone()).map_err(Error::Messaging)?;
            let _ = app.inner.messaging.set(tx);
        }
        if let Some(w) = cfg.wake {
            let _ = app.inner.wake.set(wake::spawn(app.clone(), w, &identity_dir));
        }
        if let Some((hints, device, delegation, key_agreement)) = relay_hint {
            let (identity, mut stopped) = (app.state().me.identity, app.inner.stopped.subscribe());
            tokio::spawn(async move {
                let mut last_seq = 0i64;
                loop {
                    let now = dsip_transport::now_s();
                    let seq = now.max(last_seq + 1);
                    last_seq = seq;
                    let endpoints = dsip_transport::hints::endpoints(Some(&relay), None);
                    // with the identity's key agreement delegation: senders seal to its key (§7.3, spec-gap 179)
                    let hint = dsip_transport::hints::reachability_with(&identity, &device, &delegation, &endpoints, seq, now, messaging::HINT_TTL_S,
                                                                         key_agreement.as_ref());
                    for (node, r) in hints.publish(&hint).await {
                        tracing::info!("hint seq {seq} → {node}: {r:?}");
                    }
                    tokio::select! {
                        _ = tokio::time::sleep(Duration::from_secs(messaging::HINT_REFRESH_S)) => {}
                        _ = stopped.wait_for(|s| *s) => return,
                    }
                }
            });
        }
        // the followed identities' presence, as the phone shows it, into the state
        let (a, mut shown, mut stopped) = (app.clone(), app.inner.phone.presence(), app.inner.stopped.subscribe());
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    changed = shown.changed() => if changed.is_err() { return },
                    _ = stopped.wait_for(|s| *s) => return,
                }
                let now = shown.borrow_and_update().clone();
                a.show_presence(&now);
            }
        });
        // P§12.5: a grant the phone issued with new presence keys, deposited at the grantee's mailbox as the first was
        let a = app.clone();
        tokio::spawn(async move {
            while let Some(g) = a.inner.phone.issued_grant().await {
                if let Some(m) = a.inner.messaging.get() {
                    let _ = m.send(messaging::Req::Deliver { to: g.to, grant: g.grant });
                }
            }
        });
        // follow again what was followed when the app last ran (the grants that admit us are the phone's, kept too)
        let a = app.clone();
        tokio::spawn(async move {
            for identity in a.saved_following() {
                a.follow(&identity).await;
            }
        });
        let a = app.clone();
        tokio::spawn(async move {
            while let Some(inc) = a.inner.phone.incoming().await {
                tracing::info!("incoming call from {}", inc.from);
                a.track(inc.call, Direction::Incoming, inc.from, inc.display_name);
            }
        });
        Ok(app)
    }

    /// The state now.
    pub fn state(&self) -> State {
        self.inner.state.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Every change from now on. A subscriber that falls more than 256 changes behind is told it lagged
    /// ([`broadcast::error::RecvError::Lagged`]) and should read the [`State`] again.
    pub fn subscribe(&self) -> broadcast::Receiver<Change> {
        self.inner.changes.subscribe()
    }

    /// With the tone host ([`HostKind::Tone`]): how many frames reached the speaker, and their peak level (0–1).
    pub fn tone_heard(&self) -> Option<(u64, f32)> {
        self.inner.audio.as_ref().and_then(|a| a.tone_heard())
    }

    /// The tiles calls' pictures are drawn on, for the app's textures (Android and Windows).
    #[cfg(any(target_os = "android", windows))]
    pub fn video_tiles(&self) -> Option<anvil_video::Tiles> {
        self.inner.video.as_ref().and_then(video::Video::tiles)
    }

    /// The video frames the call holding the video has sent and received, where the app has video.
    pub fn video_frames(&self) -> Option<(u64, u64)> {
        self.inner.video.as_ref().map(video::Video::frames)
    }

    /// Carry out `cmd`.
    pub async fn command(&self, cmd: Command) -> Response {
        match cmd {
            Command::State => Response::State { state: Box::new(self.state()) },
            Command::Call { to, video } => match if video && self.inner.video.is_some() {
                self.inner.phone.video_call(&to).await
            } else {
                self.inner.phone.call(&to).await
            } {
                Ok(call) => Response::Call { call: self.track(call, Direction::Outgoing, to, None) },
                Err(e) => Response::error(e.to_string()),
            },
            Command::Camera { call, on } => self.camera(call, on),
            Command::Answer { call } => self.act(call, Pick::Ringing, Action::Accept),
            Command::Decline { call } => self.act(call, Pick::Ringing, Action::Decline),
            Command::Hangup { call } => self.act(call, Pick::Latest, Action::HangUp),
            Command::Mute { call } => self.mute(call, true),
            Command::Unmute { call } => self.mute(call, false),
            Command::Introduce { to, purpose, name } => {
                let name = name.as_deref().map(str::trim).filter(|n| !n.is_empty()).map(String::from);
                if let Some(e) = name.as_deref().and_then(name_error) {
                    return Response::error(e);
                }
                let r = self.ask(|reply| messaging::Req::Introduce { to: to.clone(), purpose: purpose.clone(), reply }).await;
                if r == Response::Ok {
                    self.record_introduced(to, name, purpose);
                }
                r
            }
            Command::ForgetIntroduction { to } => {
                let mut introduced = self.state().messaging.introduced;
                let before = introduced.len();
                introduced.retain(|i| i.to != to);
                if introduced.len() == before {
                    return Response::error(format!("no introduction to {to}"));
                }
                self.set_introduced(introduced);
                Response::Ok
            }
            Command::AcceptRequest { id } => {
                let from = self.state().messaging.requests.into_iter().find(|r| r.id == id);
                let r = self.ask(|reply| messaging::Req::AcceptRequest { id, reply }).await;
                if let (Response::Ok, Some(req)) = (&r, from) {
                    self.add_contact(&req.from, req.name.as_deref());
                }
                r
            }
            Command::DeleteMessage { conversation, id } => {
                self.ask(|reply| messaging::Req::Forget { conversation, id: Some(id), reply }).await
            }
            Command::DeleteConversation { conversation } => {
                self.ask(|reply| messaging::Req::Forget { conversation, id: None, reply }).await
            }
            Command::ForgetCall { session } => {
                let mut history = self.state().history;
                let before = history.len();
                history.retain(|c| c.session != session);
                if history.len() == before {
                    return Response::error(format!("no call {session} in the history"));
                }
                self.set_history(history);
                Response::Ok
            }
            Command::ClearHistory => {
                self.set_history(vec![]);
                Response::Ok
            }
            Command::DeclineRequest { id } => self.ask(|reply| messaging::Req::DeclineRequest { id, reply }).await,
            Command::Message { to, text } => self.ask(|reply| messaging::Req::Message { to, text, reply }).await,
            Command::SendFile { to, path, name } => self.ask(|reply| messaging::Req::SendFile { to, path, name, reply }).await,
            Command::Record { max_s } => self.record(max_s).await,
            Command::StopRecording => {
                let Some(a) = &self.inner.audio else { return Response::error("no sound (audio none)") };
                let taken = a.stop_recording().await;
                self.set_voice(|v| v.recording = None);
                match taken {
                    Some((path, duration_ms)) => Response::Recorded { path: path.to_string_lossy().into_owned(), duration_ms },
                    None => Response::error("not recording"),
                }
            }
            Command::CancelRecording => {
                if let Some((path, _)) = match &self.inner.audio {
                    Some(a) => a.stop_recording().await,
                    None => None,
                } {
                    let _ = std::fs::remove_file(path);
                }
                self.set_voice(|v| v.recording = None);
                Response::Ok
            }
            Command::SendAudio { to, path, purpose, session } => {
                // M§8.2's token; `voice` is what earlier versions said
                let purpose = match purpose.as_deref() {
                    None | Some("voice") => "voice-message".to_string(),
                    Some(p) => p.to_string(),
                };
                self.ask(|reply| messaging::Req::SendAudio { to, path, purpose, session, reply }).await
            }
            Command::Play { path } => {
                let Some(a) = &self.inner.audio else { return Response::error("no sound (audio none)") };
                let app = self.clone();
                let played = path.clone();
                let ended = move || app.set_voice(|v| if v.playing.as_deref() == Some(played.as_str()) { v.playing = None });
                match a.play(std::path::Path::new(&path), ended) {
                    Ok(()) => {
                        self.set_voice(|v| v.playing = Some(path));
                        Response::Ok
                    }
                    Err(e) => Response::error(e),
                }
            }
            Command::StopPlaying => {
                if let Some(a) = &self.inner.audio {
                    a.stop_playing();
                }
                self.set_voice(|v| v.playing = None);
                Response::Ok
            }
            Command::VoicemailOffer { to, reason } => self.ask(|reply| messaging::Req::VoicemailOffer { to, reason, reply }).await,
            Command::Thread { conversation } => self.ask(|reply| messaging::Req::Thread { conversation, reply }).await,
            Command::CreateGroup { members } => self.ask(|reply| messaging::Req::CreateGroup { members, reply }).await,
            Command::AddMember { conversation, identity } => {
                self.ask(|reply| messaging::Req::AddMember { conversation, identity, reply }).await
            }
            Command::RemoveMember { conversation, identity } => {
                self.ask(|reply| messaging::Req::RemoveMember { conversation, identity, reply }).await
            }
            Command::Leave { conversation } => self.ask(|reply| messaging::Req::Leave { conversation, reply }).await,
            Command::SetPresence { state } => {
                if let Some(s) = state.as_deref().filter(|s| !PRESENCE_STATES.contains(s)) {
                    return Response::error(format!("{s}: one of {}", PRESENCE_STATES.join(", ")));
                }
                self.inner.phone.set_presence(state.as_deref());
                self.publish(Change::MyPresence { state });
                // back to automatic during a call: busy again
                self.inner.auto_busy.store(false, Ordering::SeqCst);
                self.auto_presence();
                Response::Ok
            }
            Command::WatchPresence { identity } => {
                self.follow(&identity).await;
                Response::Ok
            }
            Command::SetName { identity, name } => {
                let name = name.as_deref().map(str::trim).filter(|n| !n.is_empty());
                if let Some(e) = name.and_then(name_error) {
                    return Response::error(e);
                }
                if identity.trim().is_empty() {
                    return Response::error("no identity");
                }
                let mut names = self.state().names;
                match name {
                    Some(n) => names.insert(identity, n.to_string()),
                    None => names.remove(&identity),
                };
                self.publish(Change::Names { names });
                self.save_names();
                Response::Ok
            }
            Command::UnwatchPresence { identity } => {
                self.inner.phone.unwatch(&identity);
                self.publish(Change::Unfollowed { identity });
                self.save_following();
                Response::Ok
            }
            Command::RevokeGrants { identity } => match self.inner.phone.revoke_grants_to(&identity).await {
                Ok(count) => Response::Revoked { count },
                Err(e) => Response::error(e.to_string()),
            },
            Command::ChooseAudio { input, output } => {
                let Some(a) = &self.inner.audio else { return Response::error("calls have no sound (audio none)") };
                let r = a.choose(input.as_deref(), output.as_deref());
                self.publish(Change::Audio { audio: a.view() });
                match r {
                    Ok(()) => Response::Ok,
                    Err(e) => Response::error(e),
                }
            }
            Command::AudioDevices => {
                let Some(a) = &self.inner.audio else { return Response::error("calls have no sound (audio none)") };
                self.publish(Change::Audio { audio: a.view() });
                Response::Ok
            }
            Command::Push { provider, app, token, environment, message_app, message_token } => {
                let Some(w) = self.inner.wake.get() else { return Response::error("no push gateway: set one in the settings") };
                let given = |app: Option<String>, token: Option<String>| match (token, &provider, app) {
                    (None, ..) => Ok(None),
                    (Some(token), Some(provider), Some(app)) => {
                        Ok(Some(wake::Token { provider: provider.clone(), app, token, environment: environment.clone() }))
                    }
                    _ => Err(Response::error("a token needs its provider and app")),
                };
                let (calls, messages) = match (given(app, token), given(message_app, message_token)) {
                    (Ok(calls), Ok(messages)) => (calls, messages),
                    (Err(e), _) | (_, Err(e)) => return e,
                };
                let _ = w.send(wake::Kick::Tokens(calls, messages));
                Response::Ok
            }
            Command::OpenWake { data } => match wake::open(&self.inner.identity_dir, &data) {
                Ok(r) => r,
                Err(e) => Response::error(e),
            },
            Command::Subscribe => Response::error("subscribe is for the control socket"),
            Command::Quit => {
                self.stop().await;
                Response::Ok
            }
        }
    }

    /// Ask the messaging thread to register this device with its mailbox to be woken ([`wake::MailboxAsk`]), or with
    /// `None` to end that registration: the registration's view, and what to keep of it.
    pub(crate) async fn mailbox_wake(&self, ask: Option<wake::MailboxAsk>) -> (Registration, Option<wake::Registered>) {
        let Some(m) = self.inner.messaging.get() else { return (Registration::status("not-offered"), None) };
        let (reply, answer) = tokio::sync::oneshot::channel();
        if m.send(messaging::Req::Wake { ask, reply }).is_err() {
            return (Registration::failed("messaging has stopped"), None);
        }
        answer.await.unwrap_or_else(|_| (Registration::failed("messaging has stopped"), None))
    }

    /// Unbind and stop: calls still up end. Resolves [`App::stopped`].
    pub async fn stop(&self) {
        if let Some(m) = self.inner.messaging.get() {
            let _ = m.send(messaging::Req::Stop);
        }
        let _ = self.inner.phone.close().await;
        let _ = self.inner.changes.send(Change::Stopped);
        self.inner.stopped.send_replace(true);
    }

    /// Wait until the app is stopped ([`Command::Quit`], [`App::stop`]).
    pub async fn stopped(&self) {
        let mut rx = self.inner.stopped.subscribe();
        let _ = rx.wait_for(|s| *s).await;
    }

    /// Follow `identity`'s presence (again: a renewed grant may admit us now).
    pub(crate) async fn follow(&self, identity: &str) {
        self.inner.phone.watch(identity).await;
        let known = self.inner.state.lock().unwrap_or_else(|e| e.into_inner()).presence.following.iter().any(|p| p.identity == identity);
        if !known {
            self.publish(Change::Presence { presence: PresenceView { identity: identity.into(), state: None, token: None, source: None, unreadable: 0 } });
            self.save_following();
        }
    }

    /// The identities followed when the app last ran.
    fn saved_following(&self) -> Vec<String> {
        let path = self.inner.following_file.lock().unwrap_or_else(|e| e.into_inner());
        std::fs::read(&*path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
    }

    /// Keep the identities followed now, for the next start.
    fn save_following(&self) {
        let path = self.inner.following_file.lock().unwrap_or_else(|e| e.into_inner());
        let ids: Vec<String> = self.state().presence.following.into_iter().map(|p| p.identity).collect();
        let tmp = path.with_extension("json.tmp");
        let r = serde_json::to_vec(&ids).map_err(std::io::Error::other)
            .and_then(|b| std::fs::write(&tmp, b))
            .and_then(|()| std::fs::rename(&tmp, &*path));
        if let Err(e) = r {
            tracing::warn!("saving {}: {e}", path.display());
        }
    }

    /// Keep the names given identities, for the next start.
    fn save_names(&self) {
        let path = self.inner.names_file.lock().unwrap_or_else(|e| e.into_inner());
        save_json(&path, &self.state().names);
    }

    /// Make `did` a contact, named `offered` (else its DID, shortened), unless it has a name already; the shortened DID
    /// a contact was given for want of a name gives way to one offered later.
    pub(crate) fn add_contact(&self, did: &str, offered: Option<&str>) {
        let mut names = self.state().names;
        let offered = offered.map(str::trim).filter(|n| name_error(n).is_none() && !n.is_empty());
        let placeholder = names.get(did).is_some_and(|n| *n == short_did(did));
        if (names.contains_key(did) && !(placeholder && offered.is_some())) || did.trim().is_empty() {
            return;
        }
        names.insert(did.to_string(), offered.map_or_else(|| short_did(did), String::from));
        self.publish(Change::Names { names });
        self.save_names();
    }

    /// `by` accepted our introduction: it is marked accepted, and `by` becomes a contact under the name given when
    /// introducing it.
    pub(crate) fn introduction_accepted(&self, by: &str) {
        let mut introduced = self.state().messaging.introduced;
        let name = introduced.iter().find(|i| i.to == by).and_then(|i| i.name.clone());
        let mut changed = false;
        for i in introduced.iter_mut().filter(|i| i.to == by && !i.accepted) {
            i.accepted = true;
            changed = true;
        }
        if changed {
            self.set_introduced(introduced);
        }
        self.add_contact(by, name.as_deref());
    }

    /// Add an introduction sent to `to` to the list, in place of one sent before.
    pub(crate) fn record_introduced(&self, to: String, name: Option<String>, purpose: String) {
        let mut introduced = self.state().messaging.introduced;
        introduced.retain(|i| i.to != to);
        introduced.push(Introduced { to, name, purpose, sent_at: dsip_transport::now_s(), accepted: false });
        self.set_introduced(introduced);
    }

    fn set_introduced(&self, introduced: Vec<Introduced>) {
        save_json(&self.inner.identity_dir.join(INTRODUCED_FILE), &introduced);
        self.publish(Change::Introduced { introduced });
    }

    fn set_history(&self, history: Vec<CallRecord>) {
        save_json(&self.inner.identity_dir.join(HISTORY_FILE), &history);
        self.publish(Change::History { history });
    }

    /// Whether the direct conversation `group` was deleted and is not listed.
    pub(crate) fn hidden(&self, group: &str) -> bool {
        self.inner.hidden.lock().unwrap_or_else(|e| e.into_inner()).contains(group)
    }

    /// List the conversation `group` again (`false`), or no longer (`true`); whether that changed anything.
    pub(crate) fn hide(&self, group: &str, hide: bool) -> bool {
        let mut hidden = self.inner.hidden.lock().unwrap_or_else(|e| e.into_inner());
        let changed = if hide { hidden.insert(group.to_string()) } else { hidden.remove(group) };
        if changed {
            save_json(&self.inner.identity_dir.join(HIDDEN_FILE), &*hidden);
        }
        changed
    }

    /// While the user's presence is automatic (no state of their own), the device says `busy` for as long as a call is
    /// up, and `available` once none is. A state the user chose stays as chosen.
    ///
    /// Spec: P§3, P§5, P§8. Impl: automatic is this app's (no record: the relay says available while bound), so being
    /// on a call has to be said by a record; and since a record outlives the call by up to its lifetime, the call's end
    /// is said by another, `available`, kept fresh from then on. It shows as automatic does and is dropped at unbind
    /// like any record. Withdrawing it at once instead would lose it to P§8's publish interval after a short call,
    /// leaving `busy` shown for the lifetime.
    fn auto_presence(&self) {
        let (mine, on_call) = {
            let st = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            (st.presence.mine.is_some(), st.calls.values().any(|c| matches!(c.state, CallState::Answered { .. })))
        };
        if mine {
            self.inner.auto_busy.store(false, Ordering::SeqCst);
            return;
        }
        match (self.inner.auto_busy.swap(on_call, Ordering::SeqCst), on_call) {
            (false, true) => self.inner.phone.set_presence(Some("busy")),
            (true, false) => self.inner.phone.set_presence(Some("available")),
            _ => {}
        }
    }

    /// Start recording to a new file in [`RECORDINGS_DIR`]; a recording not taken before is dropped.
    async fn record(&self, max_s: Option<u32>) -> Response {
        let Some(a) = &self.inner.audio else { return Response::error("no sound (audio none)") };
        let dir = self.inner.identity_dir.join(RECORDINGS_DIR);
        if let Err(e) = std::fs::create_dir_all(&dir) {
            return Response::error(format!("{}: {e}", dir.display()));
        }
        if let Some((old, _)) = a.stop_recording().await {
            let _ = std::fs::remove_file(old);
        }
        let now = dsip_transport::now_s();
        let path = dir.join(format!("{now}-{}.ogg", self.inner.next_id.fetch_add(1, Ordering::Relaxed)));
        let max_ms = max_s.map(|s| u64::from(s) * 1000);
        let app = self.clone();
        // stopped by itself (its limit, a call): shown as waiting to be sent or dropped
        let ended = move |ms| {
            app.set_voice(|v| {
                if let Some(r) = v.recording.as_mut().filter(|r| r.running) {
                    r.running = false;
                    r.duration_ms = Some(ms);
                }
            })
        };
        match a.record(&path, max_ms, ended) {
            Ok(()) => {
                self.set_voice(|v| v.recording = Some(RecordingView { running: true, started_at: now, max_ms, duration_ms: None }));
                Response::Ok
            }
            Err(e) => Response::error(e),
        }
    }

    /// Change the recording and playing, and say so.
    fn set_voice(&self, f: impl FnOnce(&mut Voice)) {
        let mut voice = self.state().voice;
        let before = voice.clone();
        f(&mut voice);
        if voice != before {
            self.publish(Change::Voice { voice });
        }
    }

    /// Publish each followed identity whose presence differs from what the phone shows now.
    fn show_presence(&self, shown: &std::collections::BTreeMap<String, dsip_phone::Presence>) {
        let following: Vec<PresenceView> = self.inner.state.lock().unwrap_or_else(|e| e.into_inner()).presence.following.clone();
        for old in following {
            let p = shown.get(&old.identity);
            let view = PresenceView {
                identity: old.identity.clone(),
                state: p.map(|p| p.state.clone()),
                token: p.filter(|p| p.token != p.state).map(|p| p.token.clone()),
                source: p.map(|p| p.source.clone()),
                unreadable: p.map_or(0, |p| p.unreadable),
            };
            if view != old {
                self.publish(Change::Presence { presence: view });
            }
        }
    }

    /// Hand a request to the messaging thread and wait for its answer.
    async fn ask(&self, req: impl FnOnce(tokio::sync::oneshot::Sender<Response>) -> messaging::Req) -> Response {
        let Some(m) = self.inner.messaging.get() else { return Response::error("messaging is off: run with a mailbox") };
        let (reply, answer) = tokio::sync::oneshot::channel();
        if m.send(req(reply)).is_err() {
            return Response::error("messaging has stopped");
        }
        answer.await.unwrap_or_else(|_| Response::error("messaging has stopped"))
    }

    /// Change the messaging state with `f` and publish it.
    pub(crate) fn set_messaging(&self, f: impl FnOnce(&mut Messaging)) {
        let (mailbox, connected) = {
            let mut s = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            f(&mut s.messaging);
            (s.messaging.mailbox.clone(), s.messaging.connected)
        };
        let _ = self.inner.changes.send(Change::Messaging { mailbox, connected });
    }

    fn act(&self, call: Option<u64>, pick: Pick, action: Action) -> Response {
        let Some(id) = call.or_else(|| self.pick(pick)) else {
            return Response::error(match pick {
                Pick::Ringing => "no call is ringing here",
                Pick::Latest => "no call is up",
            });
        };
        let calls = self.inner.calls.lock().unwrap_or_else(|e| e.into_inner());
        match calls.get(&id) {
            Some(c) if c.actions.send(action).is_ok() => Response::Call { call: id },
            _ => Response::error(format!("no call {id}")),
        }
    }

    fn mute(&self, call: Option<u64>, muted: bool) -> Response {
        let Some(id) = call.or_else(|| self.pick(Pick::Latest)) else { return Response::error("no call is up") };
        let Some(flag) = self.inner.calls.lock().unwrap_or_else(|e| e.into_inner()).get(&id).map(|c| c.muted.clone()) else {
            return Response::error(format!("no call {id}"));
        };
        flag.store(muted, Ordering::Relaxed);
        self.update(id, |v| v.muted = muted);
        Response::Call { call: id }
    }

    /// The call a command without an id is for: the incoming call ringing longest, or the latest call not ended.
    fn pick(&self, pick: Pick) -> Option<u64> {
        let state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        let mut live = state.calls.values().filter(|c| !c.state.ended());
        match pick {
            Pick::Ringing => live.find(|c| c.direction == Direction::Incoming && c.state == CallState::Ringing).map(|c| c.id),
            Pick::Latest => live.next_back().map(|c| c.id),
        }
    }

    /// Follow `call`: add it to the state, then publish its every change until it ends. Returns its id.
    fn track(&self, mut call: dsip_phone::Call, direction: Direction, peer: String, peer_name: Option<String>) -> u64 {
        let id = self.inner.next_id.fetch_add(1, Ordering::Relaxed);
        let (actions, mut rx) = mpsc::unbounded_channel();
        let muted = Arc::new(AtomicBool::new(false));
        self.inner.calls.lock().unwrap_or_else(|e| e.into_inner()).insert(id, CallCtl { actions, muted: muted.clone() });
        let view = CallView {
            id,
            session: call.session().to_string(),
            peer,
            peer_name,
            direction,
            state: view_state(call.state()),
            muted: false,
            media: false,
            via: call.via().map(String::from),
            error: None,
            sound: None,
            video: false,
            camera: false,
        };
        self.publish(Change::CallAdded { call: view });
        let app = self.clone();
        tokio::spawn(async move {
            let mut poll = tokio::time::interval(Duration::from_millis(250));
            let mut ticks: u64 = 0;
            // the sound's last counts, a second apart, and whether they were the call's (not the ringback's); the stage stalled
            let mut counted: (bool, std::collections::VecDeque<CallSound>) = (false, std::collections::VecDeque::new());
            let mut stalled: Option<String> = None;
            let mut has_audio = false;
            let mut has_video = false;
            let mut was_answered = false;
            loop {
                tokio::select! {
                    changed = call.changed() => {
                        let state = changed.map(view_state).unwrap_or(CallState::Ended { reason: "transport.closed".into() });
                        let answered = matches!(state, CallState::Answered { .. });
                        was_answered |= answered;
                        let ringing_there = direction == Direction::Outgoing && state == CallState::Ringing;
                        let ended = state.ended();
                        let err = call.error();
                        app.update(id, |v| { v.state = state; v.error = err; });
                        app.auto_presence();
                        // the caller hears it ring (§12.4: the callee's `ringing` progress), until the answer or the end
                        if let Some(a) = &app.inner.audio {
                            if ringing_there && !a.ringing_back(id) {
                                if let Err(e) = a.ringback(id) {
                                    tracing::warn!("call {id}: no ringback: {e}");
                                }
                            } else if !ringing_there {
                                a.stop_ringback(id);
                            }
                        }
                        if answered && !has_audio {
                            if let Some(a) = &app.inner.audio {
                                match a.start(id, muted.clone()) {
                                    Ok(()) => has_audio = true,
                                    Err(e) => tracing::warn!("call {id}: no audio devices: {e}"),
                                }
                            }
                        }
                        if ended {
                            if let Some(a) = &app.inner.audio {
                                a.stop(id);
                            }
                            if let Some(v) = &app.inner.video {
                                v.stop(id);
                            }
                            app.remember(id, was_answered);
                            app.inner.calls.lock().unwrap_or_else(|e| e.into_inner()).remove(&id);
                            app.forget_ended();
                            return;
                        }
                    }
                    action = rx.recv() => match action {
                        Some(Action::Accept) => call.command(dsip_endpoint::CallCommand::Accept { session: call.session().to_string() }),
                        Some(Action::Decline) => call.command(dsip_endpoint::CallCommand::Decline { session: call.session().to_string() }),
                        Some(Action::HangUp) | None => call.hang_up(),
                    },
                    _ = poll.tick() => {
                        let (media, err) = (call.media_received(), call.error());
                        // a video call's camera and picture, once it has the devices (what the answer accepted is known
                        // only then, B§2.1)
                        let video = call.video();
                        if let Some(v) = &app.inner.video {
                            if has_audio && video && !has_video {
                                has_video = true;
                                if let Err(e) = v.show(id) {
                                    tracing::warn!("call {id}: its video not shown: {e}");
                                }
                                if let Err(e) = v.send(id) {
                                    tracing::warn!("call {id}: no camera: {e}");
                                }
                            }
                        }
                        // the sound's counters about once a second, while it rings back or has the devices
                        ticks += 1;
                        let mut sound = match &app.inner.audio {
                            Some(a) if ticks.is_multiple_of(4) && (has_audio || a.ringing_back(id)) => Some(a.sound()),
                            _ => None,
                        };
                        // a stage stalled: counting no more over the last two seconds, the call's or the ringback's
                        if let Some(now) = &mut sound {
                            if counted.0 != has_audio {
                                counted = (has_audio, std::collections::VecDeque::new());
                                stalled = None;
                            }
                            if counted.1.len() == 2 {
                                stalled = counted.1.pop_front().and_then(|b| now.stall(&b, has_audio, media)).map(String::from);
                            }
                            counted.1.push_back(now.clone());
                            now.stalled = stalled.clone();
                        }
                        let camera = app.inner.video.as_ref().is_some_and(|v| v.sending_to(id));
                        let differs = app.inner.state.lock().unwrap_or_else(|e| e.into_inner()).calls.get(&id)
                            .is_some_and(|v| v.media != media || v.error != err || v.video != video || v.camera != camera
                                || sound.as_ref().is_some_and(|s| v.sound.as_ref() != Some(s)));
                        if differs {
                            app.update(id, |v| {
                                v.media = media;
                                v.video = video;
                                v.camera = camera;
                                v.error = err;
                                if sound.is_some() {
                                    v.sound = sound;
                                }
                            });
                        }
                    }
                }
            }
        });
        id
    }

    /// The camera on or off in video call `call` (the one shown, without).
    fn camera(&self, call: Option<u64>, on: bool) -> Response {
        let Some(v) = &self.inner.video else { return Response::error("this app has no video") };
        let Some(id) = call.or_else(|| v.showing()) else { return Response::error("no video call") };
        if !self.state().calls.get(&id).is_some_and(|c| c.video) {
            return Response::error(format!("call {id} is not a video call"));
        }
        let r = if on { v.send(id) } else { v.stop_sending(); Ok(()) };
        match r {
            Ok(()) => {
                self.update(id, |c| c.camera = on);
                Response::Ok
            }
            Err(e) => Response::error(format!("camera: {e}")),
        }
    }

    /// Change call `id`'s view with `f` and publish it.
    fn update(&self, id: u64, f: impl FnOnce(&mut CallView)) {
        let view = {
            let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
            let Some(v) = state.calls.get_mut(&id) else { return };
            f(v);
            v.clone()
        };
        let _ = self.inner.changes.send(Change::CallChanged { call: view });
    }

    pub(crate) fn publish(&self, change: Change) {
        self.inner.state.lock().unwrap_or_else(|e| e.into_inner()).apply(&change);
        let _ = self.inner.changes.send(change);
    }

    /// Add call `id`, ended, to the history.
    fn remember(&self, id: u64, answered: bool) {
        let Some(c) = self.state().calls.get(&id).cloned() else { return };
        let reason = match &c.state {
            CallState::Ended { reason } => reason.clone(),
            _ => return,
        };
        let mut history = self.state().history;
        history.push(CallRecord {
            session: c.session,
            peer: c.peer,
            peer_name: c.peer_name,
            direction: c.direction,
            answered,
            reason,
            ended_at: dsip_transport::now_s(),
        });
        let over = history.len().saturating_sub(HISTORY_MAX);
        history.drain(..over);
        self.set_history(history);
    }

    /// Keep the [`ENDED_KEPT`] most recent ended calls.
    fn forget_ended(&self) {
        let mut state = self.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        let ended: Vec<u64> = state.calls.values().filter(|c| c.state.ended()).map(|c| c.id).collect();
        for id in ended.iter().take(ended.len().saturating_sub(ENDED_KEPT)) {
            state.calls.remove(id);
        }
    }
}

/// Why `name` cannot be a name given an identity, if it cannot.
fn name_error(name: &str) -> Option<String> {
    if name.chars().count() > NAME_MAX {
        return Some(format!("a name is at most {NAME_MAX} characters"));
    }
    if name.chars().any(char::is_control) {
        return Some("a name has no control characters".into());
    }
    None
}

/// A DID short enough for a name: its method, and the start and end of its key (the screens' `shortDid`).
pub(crate) fn short_did(did: &str) -> String {
    let (method, key) = did.rsplit_once(':').map_or(("", did), |(m, k)| (m, k));
    let chars: Vec<char> = key.chars().collect();
    if chars.len() <= 14 {
        return did.to_string();
    }
    let (head, tail): (String, String) = (chars[..8].iter().collect(), chars[chars.len() - 4..].iter().collect());
    format!("{method}:{head}…{tail}")
}

/// Write `value` to `path` whole, then rename it over the file, so a crash leaves the old one or the new one.
fn save_json(path: &std::path::Path, value: &impl serde::Serialize) {
    let tmp = path.with_extension("json.tmp");
    let r = serde_json::to_vec_pretty(value).map_err(std::io::Error::other)
        .and_then(|b| std::fs::write(&tmp, b))
        .and_then(|()| std::fs::rename(&tmp, path));
    if let Err(e) = r {
        tracing::warn!("saving {}: {e}", path.display());
    }
}

#[derive(Clone, Copy)]
enum Pick {
    Ringing,
    Latest,
}

fn view_state(s: dsip_phone::CallState) -> CallState {
    match s {
        dsip_phone::CallState::Calling => CallState::Calling,
        dsip_phone::CallState::Ringing => CallState::Ringing,
        dsip_phone::CallState::Answered { answered_by } => CallState::Answered { answered_by },
        dsip_phone::CallState::Ended { reason } => CallState::Ended { reason },
        _ => CallState::Calling,
    }
}

#[cfg(test)]
mod tests {
    use super::short_did;

    #[test]
    fn a_contact_named_by_its_did_is_named_short() {
        assert_eq!(short_did("did:key:z6MkmDofjNWY2jwMsssxw3pkEUgHQqEQEX3ZPAm3eM7ghLKk"), "did:key:z6MkmDof…hLKk");
        assert_eq!(short_did("did:web:example.com"), "did:web:example.com");
        // cut on characters, not bytes
        assert_eq!(short_did("did:key:z6Mkåäöåäöåäöåäöåäö"), "did:key:z6Mkåäöå…öåäö");
    }
}
