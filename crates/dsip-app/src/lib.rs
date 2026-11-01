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
//! app.command(Command::Call { to: "did:key:z6Mk…".into() }).await;
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
mod command;
#[cfg(unix)]
pub mod control;
mod state;

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::{broadcast, mpsc};

pub use audio::HostKind;
pub use command::{Command, Response};
pub use state::{Audio as AudioState, AudioDevice, CallState, CallView, Change, Direction, Me, State};

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
    /// STUN servers for the calls' media.
    pub stun: Vec<String>,
}

impl Config {
    /// `identity` bound to `relay`, with the platform's audio devices and no STUN.
    pub fn new(identity: dsip_phone::Identity, relay: &str) -> Config {
        Config { identity, relay: relay.into(), tls: None, dialer: None, audio: Some(HostKind::System), stun: vec![] }
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

struct Inner {
    phone: dsip_phone::Phone,
    state: std::sync::Mutex<State>,
    changes: broadcast::Sender<Change>,
    calls: std::sync::Mutex<HashMap<u64, CallCtl>>,
    next_id: AtomicU64,
    audio: Option<audio::Audio>,
    stopped: tokio::sync::watch::Sender<bool>,
}

/// The running client. Cheap to clone; clones are the same app.
#[derive(Clone)]
pub struct App {
    inner: Arc<Inner>,
}

impl App {
    /// Bind `cfg.identity` to its relay and start: incoming calls ring, commands are taken.
    pub async fn start(cfg: Config) -> Result<App, Error> {
        let audio = match cfg.audio {
            Some(kind) => Some(audio::Audio::new(kind).map_err(Error::Audio)?),
            None => None,
        };
        let me = Me {
            identity: cfg.identity.meta.identity.clone(),
            device: cfg.identity.meta.device.clone(),
            display_name: cfg.identity.meta.display_name.clone(),
        };
        let mut b = dsip_phone::Phone::builder().identity(cfg.identity).relay(&cfg.relay).answer(dsip_phone::AnswerPolicy::Ring);
        if let Some(t) = cfg.tls {
            b = b.tls(t);
        }
        if let Some(d) = cfg.dialer {
            b = b.dialer(d);
        }
        if let Some(a) = &audio {
            b = b.media(dsip_phone::Media::Native(a.media(cfg.stun)));
        }
        let phone = b.build().await?;
        let state = State {
            me,
            relay: cfg.relay,
            calls: Default::default(),
            audio: AudioState {
                host: audio.as_ref().map_or("none", |a| a.kind().name()).into(),
                devices: audio.as_ref().map(|a| a.devices()).unwrap_or_default(),
            },
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
                stopped: tokio::sync::watch::channel(false).0,
            }),
        };
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

    /// Carry out `cmd`.
    pub async fn command(&self, cmd: Command) -> Response {
        match cmd {
            Command::State => Response::State { state: Box::new(self.state()) },
            Command::Call { to } => match self.inner.phone.call(&to).await {
                Ok(call) => Response::Call { call: self.track(call, Direction::Outgoing, to, None) },
                Err(e) => Response::error(e.to_string()),
            },
            Command::Answer { call } => self.act(call, Pick::Ringing, Action::Accept),
            Command::Decline { call } => self.act(call, Pick::Ringing, Action::Decline),
            Command::Hangup { call } => self.act(call, Pick::Latest, Action::HangUp),
            Command::Mute { call } => self.mute(call, true),
            Command::Unmute { call } => self.mute(call, false),
            Command::Subscribe => Response::error("subscribe is for the control socket"),
            Command::Quit => {
                self.stop().await;
                Response::Ok
            }
        }
    }

    /// Unbind and stop: calls still up end. Resolves [`App::stopped`].
    pub async fn stop(&self) {
        let _ = self.inner.phone.close().await;
        let _ = self.inner.changes.send(Change::Stopped);
        self.inner.stopped.send_replace(true);
    }

    /// Wait until the app is stopped ([`Command::Quit`], [`App::stop`]).
    pub async fn stopped(&self) {
        let mut rx = self.inner.stopped.subscribe();
        let _ = rx.wait_for(|s| *s).await;
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
            error: None,
        };
        self.publish(Change::CallAdded { call: view });
        let app = self.clone();
        tokio::spawn(async move {
            let mut poll = tokio::time::interval(Duration::from_millis(250));
            let mut has_audio = false;
            loop {
                tokio::select! {
                    changed = call.changed() => {
                        let state = changed.map(view_state).unwrap_or(CallState::Ended { reason: "transport.closed".into() });
                        let answered = matches!(state, CallState::Answered { .. });
                        let ended = state.ended();
                        let err = call.error();
                        app.update(id, |v| { v.state = state; v.error = err; });
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
                        let differs = app.inner.state.lock().unwrap_or_else(|e| e.into_inner()).calls.get(&id)
                            .is_some_and(|v| v.media != media || v.error != err);
                        if differs {
                            app.update(id, |v| { v.media = media; v.error = err; });
                        }
                    }
                }
            }
        });
        id
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

    fn publish(&self, change: Change) {
        self.inner.state.lock().unwrap_or_else(|e| e.into_inner()).apply(&change);
        let _ = self.inner.changes.send(change);
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
