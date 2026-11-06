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
