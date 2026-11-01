//! `dsip-app`: run the client, or drive the one running. `dsip-app run` binds an identity to its relay and serves the
//! control socket; `call`, `answer`, `decline`, `hangup`, `mute`, `unmute`, `state` and `watch` talk to it.

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use dsip_app::{control, App, Command, Config, HostKind, Response};

#[derive(Parser)]
#[command(name = "dsip-app", version, about = "The DSIP client: run it, or drive the one running")]
struct Args {
    /// The control socket. Default: `$XDG_RUNTIME_DIR/dsip-app/control.sock`.
    #[arg(long, global = true)]
    control: Option<PathBuf>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Make an identity: a controller key, a device key and the delegation between them, in `dir` (a `did:key`).
    Init {
        /// Where the keys go.
        #[arg(long)]
        identity: PathBuf,
        /// The display name others are shown.
        #[arg(long)]
        name: String,
    },
    /// Run the client: bind the identity to the relay, ring for incoming calls, serve the control socket.
    Run {
        /// The identity directory (`dsip-app init`, or `dsip identity init`).
        #[arg(long)]
        identity: PathBuf,
        /// The relay (`wss://host:8443/dsip`).
        #[arg(long)]
        relay: String,
        /// A PEM certificate to trust for the relay, besides the platform's roots (a self-signed relay).
        #[arg(long)]
        ca: Option<PathBuf>,
        /// Audio: `system` (the microphone and speaker), `tone` (a test tone, headless), `none` (calls without sound).
        #[arg(long, default_value = "system")]
        audio: String,
        /// STUN server for the calls' media (repeatable): `stun:stun.example.com:3478`.
        #[arg(long)]
        stun: Vec<String>,
    },
    /// Call an identity or a device.
    Call {
        /// The DID.
        to: String,
    },
    /// Answer the call ringing here (or call `--call`).
    Answer {
        /// The app's call id.
        #[arg(long)]
        call: Option<u64>,
    },
    /// Decline the call ringing here.
    Decline {
        /// The app's call id.
        #[arg(long)]
        call: Option<u64>,
    },
    /// End a call.
    Hangup {
        /// The app's call id.
        #[arg(long)]
        call: Option<u64>,
    },
    /// Stop sending the microphone.
    Mute {
        /// The app's call id.
        #[arg(long)]
        call: Option<u64>,
    },
    /// Send the microphone again.
    Unmute {
        /// The app's call id.
        #[arg(long)]
        call: Option<u64>,
    },
    /// Print the state (JSON).
    State,
    /// Print the state, then every change, one JSON line each, until the app stops.
    Watch,
    /// Stop the running app.
    Quit,
}

#[tokio::main]
async fn main() -> Result<ExitCode> {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with_writer(std::io::stderr).init();
    let args = Args::parse();
    let path = args.control.clone().unwrap_or_else(control::default_path);
    let cmd = match args.cmd {
        Cmd::Init { identity, name } => {
            let id = dsip_phone::Identity::init(&identity, &name, None, None).context("making the identity")?;
            println!("{}", id.meta.identity);
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Run { identity, relay, ca, audio, stun } => {
            let id = dsip_phone::Identity::load(&identity).with_context(|| format!("loading {}", identity.display()))?;
            let mut cfg = Config::new(id, &relay);
            cfg.tls = dsip_transport::tls::client_config(ca.as_deref())?;
            cfg.audio = match audio.as_str() {
                "system" => Some(HostKind::System),
                "tone" => Some(HostKind::Tone),
                "none" => None,
                other => anyhow::bail!("--audio {other}: system, tone or none"),
            };
            cfg.stun = stun;
            let app = App::start(cfg).await?;
            let s = app.state();
            tracing::info!("{} ({}) bound to {} as device {}", s.me.display_name, s.me.identity, s.relay, s.me.device);
            let a = app.clone();
            tokio::spawn(async move {
                if tokio::signal::ctrl_c().await.is_ok() {
                    a.stop().await;
                }
            });
            control::serve(app, &path).await.with_context(|| format!("serving {}", path.display()))?;
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Watch => {
            control::watch(&path, |line| {
                println!("{line}");
                true
            })
            .await
            .with_context(|| format!("no app at {}", path.display()))?;
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Call { to } => Command::Call { to },
        Cmd::Answer { call } => Command::Answer { call },
        Cmd::Decline { call } => Command::Decline { call },
        Cmd::Hangup { call } => Command::Hangup { call },
        Cmd::Mute { call } => Command::Mute { call },
        Cmd::Unmute { call } => Command::Unmute { call },
        Cmd::State => Command::State,
        Cmd::Quit => Command::Quit,
    };
    let response = control::request(&path, &cmd).await.with_context(|| format!("no app at {}", path.display()))?;
    println!("{}", serde_json::to_string(&response)?);
    Ok(if matches!(response, Response::Error { .. }) { ExitCode::FAILURE } else { ExitCode::SUCCESS })
}
