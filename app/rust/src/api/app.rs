//! The running app, one per process: started from [`dsip_app::Settings`], driven by [`dsip_app::Command`]s, watched
//! through [`updates`]. Every value crosses as JSON, as on the control socket.

use std::sync::{Mutex, OnceLock};

use dsip_app::{App, Command, Response, Settings};

use crate::frb_generated::StreamSink;

/// The runtime the app's tasks run on, for the life of the process.
pub(crate) fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| tokio::runtime::Builder::new_multi_thread().enable_all().thread_name("dsip-app").build().expect("a runtime"))
}

pub(crate) fn running() -> &'static Mutex<Option<App>> {
    static APP: Mutex<Option<App>> = Mutex::new(None);
    &APP
}

pub(crate) fn current() -> Option<App> {
    running().lock().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Set up logging (to stderr, `RUST_LOG` filters) once, when Dart loads the library.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    let filter = tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into());
    let _ = tracing_subscriber::fmt().with_env_filter(filter).with_writer(std::io::stderr).try_init();
}

/// Make an identity in `dir` (a controller key, a device key and the delegation between them); its DID.
pub fn init_identity(dir: String, display_name: String) -> anyhow::Result<String> {
    // its keys go to the system's store (the Keychain, the Keystore, …: A6a)
    dsip_app::keys::use_system_store();
    Ok(dsip_app::init_identity(std::path::Path::new(&dir), &display_name)?)
}

/// Back up the identity in `dir`: its key sealed under `passphrase`, as `{"identity", "code", "file"}` JSON (the DID,
/// the recovery code, a backup file's text).
pub fn export_identity(dir: String, passphrase: String) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    let b = dsip_app::backup::export_identity(std::path::Path::new(&dir), &passphrase)?;
    Ok(serde_json::json!({"identity": b.identity, "code": b.code, "file": b.file}).to_string())
}

/// Make the identity in `code` (a recovery code, or a backup file's text) this install's, in `dir`; its DID.
pub fn restore_identity(dir: String, code: String, passphrase: String, display_name: String) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    Ok(dsip_app::backup::restore_identity(std::path::Path::new(&dir), &code, &passphrase, &display_name)?)
}

/// The new device's first step in joining an identity (no identity key on it): `{"code", "check"}` JSON, the join
/// code to give a device holding the identity, and the check code both show.
pub fn pairing_start(dir: String) -> anyhow::Result<String> {
    let (code, check) = dsip_app::pairing::start(std::path::Path::new(&dir))?;
    Ok(serde_json::json!({"code": code, "check": check}).to_string())
}

/// On a device holding the identity in `dir`: the welcome code for the device whose join code is `join`, as
/// `{"code", "check"}` JSON.
pub fn pairing_welcome(dir: String, join: String) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    let (code, check) = dsip_app::pairing::welcome(std::path::Path::new(&dir), &join)?;
    Ok(serde_json::json!({"code": code, "check": check}).to_string())
}

/// The new device's handoff while it shows its join code (`dsip_app::pairing::Handoff`): one at a time, the last
/// started; stopped by [`pairing_stop`].
static HANDOFF: std::sync::Mutex<Option<std::sync::Arc<dsip_app::pairing::Handoff>>> = std::sync::Mutex::new(None);

/// The new device in `dir` listens on the local network for its welcome code: the join code `code` in its QR form,
/// with where it listens, or None when it cannot listen or has no address but the loopback's (the QR is then the code
/// alone).
pub fn pairing_listen(dir: String, code: String) -> Option<String> {
    let handoff = match dsip_app::pairing::Handoff::listen(std::path::Path::new(&dir)) {
        Ok(h) if !h.addresses().is_empty() => h,
        Ok(_) => return None,
        Err(e) => {
            tracing::info!("not listening for the welcome code: {e}");
            return None;
        }
    };
    let qr = handoff.qr(&code);
    *HANDOFF.lock().unwrap_or_else(|e| e.into_inner()) = Some(std::sync::Arc::new(handoff));
    Some(qr)
}

/// A welcome code the handoff received within `wait_ms`, checked for this device and not joined yet:
/// `{"welcome", "identity", "name"}` JSON. None when none came, or the handoff is stopped.
pub fn pairing_receive(wait_ms: u32) -> anyhow::Result<Option<String>> {
    dsip_app::keys::use_system_store();
    let Some(handoff) = HANDOFF.lock().unwrap_or_else(|e| e.into_inner()).clone() else {
        std::thread::sleep(std::time::Duration::from_millis(wait_ms.into()));
        return Ok(None);
    };
    Ok(handoff.receive(std::time::Duration::from_millis(wait_ms.into()))?.map(|r| {
        serde_json::json!({"welcome": r.welcome, "identity": r.identity, "name": r.name}).to_string()
    }))
}

/// Stop the handoff: it listens no more.
pub fn pairing_stop() {
    *HANDOFF.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

/// Send the `welcome` code to the new device at the addresses its join code's QR form (`join`) carries: the address
/// that took it, or None when `join` carries none (it was typed).
pub fn pairing_send(join: String, welcome: String) -> anyhow::Result<Option<String>> {
    Ok(dsip_app::pairing::send(&join, &welcome)?.map(|a| a.to_string()))
}

/// The new device's last step: joined with the `welcome` code, in `dir`; the identity's DID.
pub fn pairing_finish(dir: String, welcome: String) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    Ok(dsip_app::pairing::finish(std::path::Path::new(&dir), &welcome)?)
}

/// The document the identity in `dir` would serve on a domain of its own, as `did` (a `did:web`), naming `relay` and
/// the mailbox (`mailbox_did`, `mailbox_uri`) when given: `{"did", "url", "document"}` JSON. Nothing changes yet.
pub fn web_prepare(dir: String, did: String, relay: String, mailbox_did: Option<String>, mailbox_uri: Option<String>) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    let mb = mailbox_did.as_deref().zip(mailbox_uri.as_deref());
    Ok(serde_json::to_string(&dsip_app::web::prepare(std::path::Path::new(&dir), &did, &relay, mb)?)?)
}

/// What the domain of `plan` (from [`web_prepare`]) serves, compared with what it must: each difference, as a JSON list
/// of sentences; empty when it serves the document.
pub async fn web_check(plan: String, ca: Option<String>) -> anyhow::Result<String> {
    let plan: dsip_app::web::Plan = serde_json::from_str(&plan)?;
    let differs = runtime().spawn(async move { dsip_app::web::check(&plan, ca.as_deref().map(std::path::Path::new)).await }).await??;
    Ok(serde_json::to_string(&differs)?)
}

/// Make the identity in `dir` the `did:web` of `plan` (once [`web_check`] finds nothing differs); its new DID. The app
/// is stopped first, and started again after.
pub fn web_move(dir: String, plan: String) -> anyhow::Result<String> {
    dsip_app::keys::use_system_store();
    let plan: dsip_app::web::Plan = serde_json::from_str(&plan)?;
    Ok(dsip_app::web::move_to(std::path::Path::new(&dir), &plan)?)
}

/// The system's microphones and speakers, as `dsip-app` lists them (`{"host", "devices": [{"id", "name", "kind",
/// "default"}]}`), without the app running: what the phone's own test checks Rust reaches (on Android, through the
/// JVM `MainActivity` hands over).
pub fn system_audio() -> anyhow::Result<String> {
    let audio = dsip_app::audio::Audio::new(dsip_app::HostKind::System).map_err(anyhow::Error::msg)?;
    Ok(serde_json::to_string(&audio.view())?)
}

/// Start the app from `settings` ([`dsip_app::Settings`] as JSON): the identity bound to its relay, its mailbox when
/// it has one. One running already is left running: on a phone, a push may have started it before the screen did
/// (`system.rs`).
pub async fn start(settings: String) -> anyhow::Result<()> {
    let settings: Settings = serde_json::from_str(&settings)?;
    crate::system::start(settings).await
}

/// Do `command` ([`dsip_app::Command`] as JSON); the [`dsip_app::Response`] as JSON.
pub async fn command(command: String) -> String {
    let response = match (current(), serde_json::from_str::<Command>(&command)) {
        (None, _) => Response::error("the app is not running"),
        (_, Err(e)) => Response::error(format!("not a command: {e}")),
        (Some(app), Ok(cmd)) => match runtime().spawn(async move { app.command(cmd).await }).await {
            Ok(r) => r,
            Err(e) => Response::error(e.to_string()),
        },
    };
    serde_json::to_string(&response).unwrap_or_default()
}

/// Every change, until the app stops: one JSON object per change, `{"state": …, "change": …}`, the whole
/// [`dsip_app::State`] after the [`dsip_app::Change`] (so Dart never applies a change itself), the first with no
/// change.
pub fn updates(sink: StreamSink<String>) -> anyhow::Result<()> {
    let app = current().ok_or_else(|| anyhow::anyhow!("the app is not running"))?;
    runtime().spawn(async move {
        let mut changes = app.subscribe();
        let send = |change: Option<&dsip_app::Change>| {
            let update = serde_json::json!({"state": app.state(), "change": change});
            sink.add(update.to_string()).is_ok()
        };
        if !send(None) {
            return;
        }
        loop {
            match changes.recv().await {
                Ok(c) => {
                    let stopped = matches!(c, dsip_app::Change::Stopped);
                    if !send(Some(&c)) || stopped {
                        return;
                    }
                }
                // too far behind: the state as it is now
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                    if !send(None) {
                        return;
                    }
                }
                Err(_) => return,
            }
        }
    });
    Ok(())
}

/// Stop the app: calls still up end, its relay and mailbox are left.
pub async fn stop() {
    crate::system::stopped();
    let app = running().lock().unwrap_or_else(|e| e.into_inner()).take();
    if let Some(app) = app {
        let _ = runtime().spawn(async move { app.stop().await }).await;
    }
}
