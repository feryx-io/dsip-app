//! `dsip-app`: run the client, or drive the one running. `dsip-app run` binds an identity to its relay (and, with
//! `--mailbox`, to its mailbox) and serves the control socket; `call`, `answer`, `decline`, `hangup`, `mute`, `unmute`,
//! `introduce`, `accept`, `decline-request`, `message`, `thread`, `presence`, `follow`, `unfollow`, `state` and `watch`
//! talk to it.

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use dsip_app::{control, App, Command, Config, HostKind, Response};

#[derive(Parser)]
#[command(name = "dsip-app", version, about = "The DSIP client: run it, or drive the one running")]
struct Args {
    /// The control socket. Default: `$XDG_RUNTIME_DIR/dsip-app/control.sock`; on Windows a named pipe,
    /// `\\.\pipe\dsip-app-<user>`.
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
        /// The identity's mailbox (`wss://host:9443/dsip`), for messages: one that serves it, or enrols identities that
        /// bind. Without it, calls only.
        #[arg(long, requires = "mailbox_did")]
        mailbox: Option<String>,
        /// The mailbox's DID (its `service.did`).
        #[arg(long, requires = "mailbox")]
        mailbox_did: Option<String>,
        /// A hints node (`https://host:port`, repeatable): this device publishes its hint there, naming its relay (and
        /// mailbox), and finds there the relays and mailboxes of other `did:key` identities: a call to one bound to
        /// another relay goes through that relay.
        #[arg(long = "hints-node")]
        hints_nodes: Vec<String>,
        /// Where the messaging state lives. Default: `<identity>/messaging`.
        #[arg(long)]
        messaging_state: Option<PathBuf>,
        /// Fetch `did:web` documents to find those identities' mailboxes.
        #[arg(long)]
        fetch_did_web: bool,
    },
    /// Ask an identity for permission to message it.
    Introduce {
        /// The identity.
        to: String,
        /// Why (shown to it).
        purpose: String,
    },
    /// Grant a request (`state` lists them under messaging.requests).
    Accept {
        /// The request id.
        id: String,
    },
    /// Forget a request, unanswered.
    DeclineRequest {
        /// The request id.
        id: String,
    },
    /// Send a text to an identity (your direct conversation with it) or a conversation (its group id).
    Message {
        /// The identity DID or group id.
        to: String,
        /// The text.
        #[arg(num_args = 1.., required = true)]
        text: Vec<String>,
    },
    /// Make a group conversation with these identities (each must have granted you); prints its group id.
    Group {
        /// The other members' identity DIDs.
        #[arg(num_args = 1.., required = true)]
        members: Vec<String>,
    },
    /// Add an identity to a group conversation.
    Add {
        /// The group id.
        conversation: String,
        /// The identity DID.
        identity: String,
    },
    /// Remove a member, every device of it, from a group conversation.
    Remove {
        /// The group id.
        conversation: String,
        /// The identity DID.
        identity: String,
    },
    /// Leave a conversation.
    Leave {
        /// The group id.
        conversation: String,
    },
    /// A conversation's messages.
    Thread {
        /// Its group id.
        conversation: String,
    },
    /// Publish this device's presence: available, busy, away, dnd, offline (invisible), or auto (no record).
    Presence {
        /// The state.
        state: String,
    },
    /// Follow an identity's presence (it must have granted you; accepting your introduction does).
    Follow {
        /// The identity.
        identity: String,
    },
    /// Stop following an identity's presence.
    Unfollow {
        /// The identity.
        identity: String,
    },
    /// Withdraw what you granted an identity (calls, presence); the others you granted get new presence keys.
    Revoke {
        /// The identity.
        identity: String,
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
        Cmd::Run { identity, relay, ca, audio, stun, mailbox, mailbox_did, hints_nodes, messaging_state, fetch_did_web } => {
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
            if !hints_nodes.is_empty() {
                let pem = match &ca {
                    Some(p) => Some(std::fs::read(p).with_context(|| format!("reading {}", p.display()))?),
                    None => None,
                };
                cfg.hints = Some(dsip_transport::hints::HintsClient::new(hints_nodes.clone(), pem.as_deref())?);
            }
            if let (Some(uri), Some(did)) = (mailbox, mailbox_did) {
                cfg.messaging = Some(dsip_app::MessagingConfig {
                    mailbox: (did, uri),
                    hints_nodes,
                    ca: ca.clone(),
                    state_dir: messaging_state.unwrap_or_else(|| identity.join("messaging")),
                    fetch_did_web,
                });
            }
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
        Cmd::Introduce { to, purpose } => Command::Introduce { to, purpose },
        Cmd::Accept { id } => Command::AcceptRequest { id },
        Cmd::DeclineRequest { id } => Command::DeclineRequest { id },
        Cmd::Message { to, text } => Command::Message { to, text: text.join(" ") },
        Cmd::Thread { conversation } => Command::Thread { conversation },
        Cmd::Group { members } => Command::CreateGroup { members },
        Cmd::Add { conversation, identity } => Command::AddMember { conversation, identity },
        Cmd::Remove { conversation, identity } => Command::RemoveMember { conversation, identity },
        Cmd::Leave { conversation } => Command::Leave { conversation },
        Cmd::Presence { state } => Command::SetPresence { state: (state != "auto").then_some(state) },
        Cmd::Follow { identity } => Command::WatchPresence { identity },
        Cmd::Unfollow { identity } => Command::UnwatchPresence { identity },
        Cmd::Revoke { identity } => Command::RevokeGrants { identity },
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
