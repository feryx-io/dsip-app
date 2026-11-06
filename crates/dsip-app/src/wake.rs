//! Waking this device when it sleeps (app plan A5d; the Wake Profile, `wake/0.1`): the phone's platform push token
//! ([`crate::Command::Push`]) enrolled at the publisher's push gateway, and the registration that results given to the
//! relay (calls) and the mailbox (messages), each when it says it wakes devices; renewed once half its life is gone,
//! and at once when the token changes. An iPhone has two tokens, as APNs takes each for its own topic only (spec-gap
//! 178): PushKit's for calls, given to the relay, and the alert token for messages, given to the mailbox, each
//! enrolled apart. FCM's one token serves both. A woken app opens what the push carried ([`open`]).
//!
//! What it keeps is `wake.json` beside the identity: the tokens, each enrolment's key (made for it and nothing else,
//! so the gateway never learns the device's DID), the gateway's handles, the seal secret the relay seals a call's
//! caller to, and each registration's waker and expiry. The protocol is dsip-rs's (`dsip_transport::wake::enrol`,
//! `Phone::wake_register`, `Messenger::wake_register`); this decides when.
//!
//! Spec: W§3 (enrolment), W§4.1–W§4.4 (registration, renewal, advertising), W§5.4 and W§6 (what a woken device reads).

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use dsip_core::b64;
use dsip_core::keys::KeyPair;
use dsip_transport::wake::{Answer, WakeClient};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::mpsc;

use crate::state::{Push, Registration};
use crate::{App, Change};

/// The file, in the identity's folder.
pub const FILE: &str = "wake.json";

/// How often registrations are looked at when nothing asks sooner.
const CHECK_S: u64 = 3600;

/// How soon a step that failed (the gateway or a waker unreachable) is tried again.
const RETRY_S: u64 = 300;

/// Where the app's pushes come from: the publisher's gateway.
#[derive(Clone)]
pub struct WakeConfig {
    /// The gateway's DID (a `did:web` naming its `DSIPWake` endpoint, W§2).
    pub gateway: String,
    /// How to reach gateways; `None`: over the web, documents fetched as `did:web` (tests give their own).
    pub client: Option<WakeClient>,
}

impl WakeConfig {
    /// The publisher's gateway at `gateway`, reached over the web.
    pub fn new(gateway: &str) -> WakeConfig {
        WakeConfig { gateway: gateway.into(), client: None }
    }

    fn client(&self) -> WakeClient {
        self.client.clone().unwrap_or_else(|| WakeClient::new(Arc::new(dsip_transport::resolver::DidWebResolver::new())))
    }
}

/// The platform's push token, as the phone's system gave it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Token {
    /// `apns` or `fcm` (registry `dsip-wake-provider`).
    pub provider: String,
    /// The APNs topic (the bundle ID with `.voip` for PushKit's token, the bundle ID for the alert token) or the FCM
    /// project.
    pub app: String,
    /// The token.
    pub token: String,
    /// APNs only: `production` or `sandbox`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub environment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Enrolment {
    gateway: String,
    token: Token,
    /// The wake key's seed (base64url).
    key: String,
    handle: String,
}

/// A registration given to a waker.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct Registered {
    waker: String,
    handle: String,
    expires_at: i64,
}

/// What `wake.json` holds.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Saved {
    /// The token for calls, or for everything when there is no `message_token`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    token: Option<Token>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    enrolment: Option<Enrolment>,
    /// APNs' alert token, for messages (spec-gap 178).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    message_token: Option<Token>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    message_enrolment: Option<Enrolment>,
    /// The seal secret (base64url), made once per device.
    #[serde(default)]
    seal: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    relay: Option<Registered>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    mailbox: Option<Registered>,
}

impl Saved {
    fn load(path: &Path) -> Saved {
        let mut s: Saved = std::fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        if seed(&s.seal).is_none() {
            s.seal = b64::encode(&dsip_wake::seal_keys().0);
        }
        s
    }

    fn save(&self, path: &Path) {
        let text = serde_json::to_vec_pretty(self).expect("JSON");
        let written = std::fs::write(path, text).and_then(|_| restrict(path));
        if let Err(e) = written {
            tracing::warn!("waking: saving {}: {e}", path.display());
        }
    }

    fn seal_secret(&self) -> [u8; 32] {
        seed(&self.seal).expect("made at load")
    }
}

fn seed(text: &str) -> Option<[u8; 32]> {
    b64::decode(text)?.try_into().ok()
}

/// The file holds keys: its owner's alone.
fn restrict(path: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

/// What the waking task is told.
pub(crate) enum Kick {
    /// New tokens: for calls (or everything), and APNs' alert token for messages; neither, stop being woken.
    Tokens(Option<Token>, Option<Token>),
    /// Look again now (a binding came back).
    Check,
}

/// Run the waking task for `app` until it stops: registrations kept up from `wake.json` in `dir`.
pub(crate) fn spawn(app: App, cfg: WakeConfig, dir: &Path) -> mpsc::UnboundedSender<Kick> {
    let (tx, mut rx) = mpsc::unbounded_channel();
    let path = dir.join(FILE);
    let mut stopped = app.inner.stopped.subscribe();
    tokio::spawn(async move {
        let mut w = Waking { app, client: cfg.client(), cfg, path };
        let mut wait = Duration::from_secs(0);
        loop {
            tokio::select! {
                k = rx.recv() => match k {
                    Some(Kick::Tokens(calls, messages)) => {
                        let mut s = Saved::load(&w.path);
                        s.token = calls;
                        s.message_token = messages;
                        s.save(&w.path);
                    }
                    Some(Kick::Check) => {}
                    None => return,
                },
                _ = tokio::time::sleep(wait) => {}
                _ = stopped.changed() => return,
            }
            wait = Duration::from_secs(if w.check().await { CHECK_S } else { RETRY_S });
        }
    });
    tx
}

struct Waking {
    app: App,
    cfg: WakeConfig,
    client: WakeClient,
    path: PathBuf,
}

impl Waking {
    /// Enrol and register as `wake.json` and the wakers need, then tell the state. Whether every step went through.
    async fn check(&mut self) -> bool {
        let mut s = Saved::load(&self.path);
        let mut push = Push { gateway: self.cfg.gateway.clone(), ..Push::default() };
        let done = self.steps(&mut s, &mut push).await;
        s.save(&self.path);
        let push = (s.token.is_some() || s.message_token.is_some()).then_some(push);
        self.app.publish(Change::Push { push });
        done
    }

    /// The enrolment for `token` at the gateway: the one in `current` if it is for this token and gateway, else a new
    /// one under a new wake key (W§3: a new token, or another gateway, means a new enrolment and so new registrations).
    /// `None` when the gateway did not take it, the reason in `push`.
    async fn enrolled(&self, current: &mut Option<Enrolment>, token: Option<Token>, push: &mut Push) -> Option<Enrolment> {
        let Some(token) = token else {
            *current = None;
            return None;
        };
        if let Some(e) = current.as_ref().filter(|e| e.gateway == self.cfg.gateway && e.token == token) {
            return Some(e.clone());
        }
        *current = None;
        let key = KeyPair::generate();
        let env = token.environment.as_deref();
        match dsip_transport::wake::enrol(&self.client, &self.cfg.gateway, &key, &token.provider, &token.app, &token.token, env).await {
            Ok(handle) => {
                *current = Some(Enrolment { gateway: self.cfg.gateway.clone(), token, key: b64::encode(&key.seed()), handle });
                current.clone()
            }
            Err(e) => {
                push.error = Some(format!("enrolling {} at {}: {e}", token.app, self.cfg.gateway));
                None
            }
        }
    }

    async fn steps(&mut self, s: &mut Saved, push: &mut Push) -> bool {
        let Some(provider) = s.token.as_ref().or(s.message_token.as_ref()).map(|t| t.provider.clone()) else {
            // W§4.2: no token, no waking: each registration is ended where it was given
            if s.relay.take().is_some() {
                if let Err(e) = self.app.inner.phone.wake_remove().await {
                    tracing::info!("waking: ending the relay's registration: {e}");
                }
            }
            if s.mailbox.take().is_some() {
                let _ = self.app.mailbox_wake(None).await;
            }
            s.enrolment = None;
            s.message_enrolment = None;
            return true;
        };
        push.provider = provider.clone();
        let calls = self.enrolled(&mut s.enrolment, s.token.clone(), push).await;
        let messages = self.enrolled(&mut s.message_enrolment, s.message_token.clone(), push).await;
        if (s.token.is_some() && calls.is_none()) || (s.message_token.is_some() && messages.is_none()) {
            return false;
        }
        push.enrolled = true;
        // Messages wake through the alert token's handle; FCM's one token serves both. APNs' VoIP token cannot carry
        // an alert push (spec-gap 178): without an alert token, the mailbox wakes nothing.
        let for_messages = match (messages, provider.as_str()) {
            (Some(m), _) => Some(m),
            (None, "apns") => None,
            (None, _) => calls.clone(),
        };
        let now = dsip_transport::now_s();

        // the relay: calls (W§4.4: only one that says it wakes devices)
        let phone = &self.app.inner.phone;
        let mut done = true;
        push.relay = if phone.relay_wake().is_none() {
            s.relay = None;
            Registration::status("not-offered")
        } else if let Some(e) = calls {
            if let Some(r) = s.relay.as_ref().filter(|r| !due(r, phone.relay_did(), &e.handle, now)) {
                Registration::registered(r.expires_at)
            } else {
                let key = KeyPair::from_seed(seed(&e.key).unwrap_or_default());
                let reg = dsip_wake::registration(&key, phone.relay_did(), &e.gateway, &e.handle, now);
                let seal = dsip_core::hpke::x25519_public(&s.seal_secret());
                match phone.wake_register(reg, Some(seal), None).await {
                    Ok(Answer::Accepted { .. }) => {
                        let r = Registered { waker: phone.relay_did().into(), handle: e.handle.clone(), expires_at: now + dsip_wake::W_REGISTRATION_S };
                        let view = Registration::registered(r.expires_at);
                        s.relay = Some(r);
                        view
                    }
                    Ok(Answer::Refused { reason, .. }) => Registration::refused(&reason),
                    Err(err) => {
                        done = false;
                        Registration::failed(&err.to_string())
                    }
                }
            }
        } else {
            if s.relay.take().is_some() {
                if let Err(e) = phone.wake_remove().await {
                    tracing::info!("waking: ending the relay's registration: {e}");
                }
            }
            Registration::status("no-token")
        };

        // the mailbox: messages, when there is one
        if self.app.inner.messaging.get().is_some() {
            let view = match for_messages {
                Some(e) => {
                    let key = seed(&e.key).unwrap_or_default();
                    let ask = MailboxAsk { key, gateway: e.gateway.clone(), handle: e.handle.clone(), current: s.mailbox.clone(), now };
                    let (view, kept) = self.app.mailbox_wake(Some(ask)).await;
                    s.mailbox = kept;
                    view
                }
                None => {
                    if s.mailbox.take().is_some() {
                        let _ = self.app.mailbox_wake(None).await;
                    }
                    Registration::status("no-token")
                }
            };
            done &= view.status != "failed";
            push.mailbox = Some(view);
        }
        done
    }
}

/// Whether `r` must be given again: another waker, another handle, or less than half its life left (W§4.3).
fn due(r: &Registered, waker: &str, handle: &str, now: i64) -> bool {
    r.waker != waker || r.handle != handle || r.expires_at - now < dsip_wake::W_REGISTRATION_S / 2
}

/// What the messaging thread is asked to do about waking: register with the mailbox (`None` in [`App::mailbox_wake`]:
/// end the registration).
pub(crate) struct MailboxAsk {
    pub(crate) key: [u8; 32],
    pub(crate) gateway: String,
    pub(crate) handle: String,
    pub(crate) current: Option<Registered>,
    pub(crate) now: i64,
}

/// The messaging thread's part: register (or keep) this device with its mailbox. The view, and what to keep.
pub(crate) async fn at_mailbox<S, H>(mx: &mut dsip_messenger::Messenger<S>, host: &mut H, ask: MailboxAsk) -> (Registration, Option<Registered>)
where
    S: dsip_messaging_device::Store,
    H: dsip_messenger::Host<S>,
{
    if mx.connection().is_none() {
        return (Registration::failed("the mailbox is not connected"), ask.current);
    }
    if mx.mailbox_wake().is_none() {
        return (Registration::status("not-offered"), None);
    }
    let waker = mx.config().mailbox.0.clone();
    if let Some(r) = ask.current.as_ref().filter(|r| !due(r, &waker, &ask.handle, ask.now)) {
        return (Registration::registered(r.expires_at), ask.current.clone());
    }
    let reg = dsip_wake::registration(&KeyPair::from_seed(ask.key), &waker, &ask.gateway, &ask.handle, ask.now);
    match mx.wake_register(host, reg, None).await {
        Ok(Answer::Accepted { .. }) => {
            let r = Registered { waker, handle: ask.handle, expires_at: ask.now + dsip_wake::W_REGISTRATION_S };
            (Registration::registered(r.expires_at), Some(r))
        }
        Ok(Answer::Refused { reason, .. }) => (Registration::refused(&reason), None),
        Err(e) => (Registration::failed(&e.to_string()), ask.current),
    }
}

/// What a woken app reads from its push's data (`{"dsip-wake": {kind, waker, session?, sealed?}}`, or the object
/// inside): the kind, the waker to bind to, the session, and for a call the caller's hint opened with this device's
/// seal secret. The hint is the relay's claim (W§6): the caller is known only once the invite verifies.
pub fn open(identity_dir: &Path, data: &Value) -> Result<crate::Response, String> {
    let w = data.get("dsip-wake").unwrap_or(data);
    let w = match w {
        // FCM carries it as a string (W§5.3)
        Value::String(s) => serde_json::from_str(s).map_err(|e| format!("the push's data: {e}"))?,
        other => other.clone(),
    };
    let text = |k: &str| w[k].as_str().map(String::from);
    let kind = text("kind").ok_or("the push's data names no kind")?;
    let waker = text("waker").ok_or("the push's data names no waker")?;
    let session = text("session");
    let (mut from, mut on_behalf_of) = (None, None);
    if let (Some(sealed), Some(sid)) = (w.get("sealed"), &session) {
        let secret = Saved::load(&identity_dir.join(FILE)).seal_secret();
        match dsip_wake::open_hint(sealed, sid, &secret) {
            Ok(hint) => {
                from = hint["from"].as_str().map(String::from);
                on_behalf_of = hint["on_behalf_of"].as_str().map(String::from);
            }
            Err(why) => tracing::info!("waking: the call's hint did not open: {why}"),
        }
    }
    Ok(crate::Response::Wake { kind, waker, session, from, on_behalf_of })
}
