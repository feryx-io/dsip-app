//! `dsip-app`: run the client, or drive the one running. `dsip-app run` binds an identity to its relay (and, with
//! `--mailbox`, to its mailbox) and serves the control socket; `call`, `answer`, `decline`, `hangup`, `mute`, `unmute`,
//! `introduce`, `accept`, `decline-request`, `message`, `group`, `add`, `remove`, `leave`, `thread`, `presence`,
//! `follow`, `unfollow`, `revoke`, `audio`, `state` and `watch` talk to it.

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use dsip_app::{control, App, Command, Mailbox, Response, Settings};

#[derive(Parser)]
#[command(name = "dsip-app", version, about = "The DSIP client: run it, or drive the one running")]
struct Args {
    /// The control socket. Default: `$XDG_RUNTIME_DIR/dsip-app/control.sock`; on Windows a named pipe,
    /// `\\.\pipe\dsip-app-<user>`.
    #[arg(long, global = true)]
    control: Option<PathBuf>,
    /// Keep the identity's keys in its folder's files, its owner's alone, not in the system's store (the Keychain,
    /// Credential Manager, the Secret Service).
    #[arg(long, global = true)]
    key_files: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
// parsed once per run: `run`'s many flags cost nothing worth a box
#[allow(clippy::large_enum_variant)]
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
    /// Move the identity in `dir` onto a domain of its own (a `did:web`): print the document the domain must serve and
    /// where; `--check` says how what it serves differs; `--move` checks, and moves the identity once nothing differs.
    /// Contacts know the new DID as a new identity.
    Web {
        /// The identity folder.
        #[arg(long)]
        identity: PathBuf,
        /// The `did:web` DID (`did:web:example.com`, or `did:web:example.com:users:ann`).
        #[arg(long)]
        did: String,
        /// The relay the document names (`wss://…/dsip`).
        #[arg(long)]
        relay: String,
        /// The mailbox the document names.
        #[arg(long, requires = "mailbox_did")]
        mailbox: Option<String>,
        /// The mailbox's DID.
        #[arg(long)]
        mailbox_did: Option<String>,
        /// A PEM certificate to trust for the domain, besides the web's.
        #[arg(long)]
        ca: Option<PathBuf>,
        /// Fetch what the domain serves and compare.
        #[arg(long)]
        check: bool,
        /// Check, then move the identity when nothing differs.
        #[arg(long = "move", conflicts_with = "check")]
        move_: bool,
    },
    /// Join an identity as another device, without its identity key: print the join code (and a check code), give it
    /// to a device that holds the identity, then type the welcome code it gives back (standard input). Meanwhile it
    /// listens on the local network: given the join code's QR form (printed too), the other device sends the welcome
    /// code itself, and it is taken once the identity it is from is said.
    Join {
        /// The new device's identity folder (without one yet).
        #[arg(long)]
        identity: PathBuf,
    },
    /// On a device holding the identity key: the welcome code for the device whose join code this is. Given the join
    /// code's QR form (with the new device's addresses), it is sent there too.
    Welcome {
        /// The identity folder.
        #[arg(long)]
        identity: PathBuf,
        /// The other device's join code.
        code: String,
    },
    /// Back up the identity in `dir`: its key sealed under a passphrase read from standard input, as a recovery code
    /// (printed) and, with `--out`, a file holding it.
    Export {
        /// The identity folder.
        #[arg(long)]
        identity: PathBuf,
        /// Write the backup file here too.
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// Restore an identity from its recovery code (or a backup file) into `dir`, as this install's: the passphrase is
    /// read from standard input.
    Restore {
        /// Where the restored identity goes (a folder without one).
        #[arg(long)]
        identity: PathBuf,
        /// The recovery code, or the backup file's path.
        code: String,
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
        #[arg(long, required_unless_present = "server")]
        relay: Option<String>,
        /// A domain listing its servers at `/.well-known/dsip` (`feryx.io`): the relay, mailbox, hints nodes and STUN
        /// servers not given here are taken from it, the relay and mailbox picked from its pools by this identity.
        #[arg(long)]
        server: Option<String>,
        /// A PEM certificate to trust for the relay, besides the platform's roots (a self-signed relay).
        #[arg(long)]
        ca: Option<PathBuf>,
        /// Audio: `system` (the microphone and speaker), `tone` (a test tone, headless), `none` (calls without sound).
        #[arg(long, default_value = "system")]
        audio: String,
        /// The microphone to use (an id `dsip-app state` lists under audio.devices); default: the system's.
        #[arg(long)]
        input: Option<String>,
        /// The speaker to use; default: the system's.
        #[arg(long)]
        output: Option<String>,
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
        /// The publisher's push gateway (a `did:web`), to be woken while asleep once `push` gives a token.
        #[arg(long)]
        push_gateway: Option<String>,
    },
    /// Ask an identity for permission to message it.
    Introduce {
        /// The identity.
        to: String,
        /// Why (shown to it).
        purpose: String,
        /// What to call it here once it accepts (its contact's name; never sent).
        #[arg(long)]
        name: Option<String>,
    },
    /// Delete one message of a conversation, on this device only.
    DeleteMessage {
        /// The conversation's group id.
        conversation: String,
        /// The message's id (`thread` lists them).
        id: String,
    },
    /// Delete a conversation's messages on this device (a group is left too).
    DeleteConversation {
        /// The group id.
        conversation: String,
    },
    /// Delete one call from the history (`state` lists it), or with `--all` all of it.
    ForgetCall {
        /// The call's session id.
        #[arg(required_unless_present = "all")]
        session: Option<String>,
        /// The whole history.
        #[arg(long, conflicts_with = "session")]
        all: bool,
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
    /// Send a file to an identity or a conversation, as `message` sends a text.
    SendFile {
        /// The identity DID or group id.
        to: String,
        /// The file.
        path: std::path::PathBuf,
        /// The name it is sent under (the file's own without one).
        #[arg(long)]
        name: Option<String>,
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
    /// Use this microphone and speaker for calls (ids from `state`'s audio.devices; one left out: the system's
    /// default). Without either, list the devices again.
    Audio {
        /// The microphone.
        #[arg(long)]
        input: Option<String>,
        /// The speaker.
        #[arg(long)]
        output: Option<String>,
    },
    /// Be woken while asleep with this platform push token (enrolled at the push gateway, registered with the relay
    /// and the mailbox); `--off` to stop.
    Push {
        /// `apns` or `fcm`.
        #[arg(long, required_unless_present = "off")]
        provider: Option<String>,
        /// The APNs topic or FCM project.
        #[arg(long, required_unless_present = "off")]
        app: Option<String>,
        /// The token.
        #[arg(long, required_unless_present = "off")]
        token: Option<String>,
        /// APNs's `production` or `sandbox`.
        #[arg(long)]
        environment: Option<String>,
        /// APNs: the alert token's topic (the bundle ID), for message wakes, when `--token` is PushKit's.
        #[arg(long, requires = "message_token")]
        message_app: Option<String>,
        /// APNs: the alert token.
        #[arg(long, requires = "message_app")]
        message_token: Option<String>,
        /// Stop being woken.
        #[arg(long, conflicts_with_all = ["provider", "app", "token", "environment", "message_app", "message_token"])]
        off: bool,
    },
    /// Read a push's `dsip-wake` data (JSON): what woke the app, and a call's caller from its sealed hint.
    OpenWake {
        /// The data.
        data: String,
    },
    /// Print the state (JSON).
    State,
    /// Print the state, then every change, one JSON line each, until the app stops.
    Watch,
    /// Stop the running app.
    Quit,
}

/// The passphrase, the first line of standard input (never an argument, which others on the machine can see).
fn passphrase() -> Result<String> {
    eprintln!("passphrase:");
    let mut line = String::new();
    std::io::stdin().read_line(&mut line).context("reading the passphrase")?;
    Ok(line.trim_end_matches(['\r', '\n']).to_string())
}

#[tokio::main]
async fn main() -> Result<ExitCode> {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with_writer(std::io::stderr).init();
    let args = Args::parse();
    let path = args.control.clone().unwrap_or_else(control::default_path);
    if !args.key_files && matches!(args.cmd, Cmd::Init { .. } | Cmd::Run { .. } | Cmd::Export { .. } | Cmd::Restore { .. } | Cmd::Web { .. } | Cmd::Join { .. } | Cmd::Welcome { .. }) {
        dsip_app::keys::use_system_store();
    }
    let cmd = match args.cmd {
        Cmd::Init { identity, name } => {
            println!("{}", dsip_app::init_identity(&identity, &name).context("making the identity")?);
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Web { identity, did, relay, mailbox, mailbox_did, ca, check, move_ } => {
            let mb = mailbox_did.as_deref().zip(mailbox.as_deref());
            let plan = dsip_app::web::prepare(&identity, &did, &relay, mb).context("preparing the document")?;
            if !check && !move_ {
                println!("serve at {}:\n{}", plan.url, serde_json::to_string_pretty(&plan.document)?);
                return Ok(ExitCode::SUCCESS);
            }
            let differs = dsip_app::web::check(&plan, ca.as_deref()).await.context("checking the domain")?;
            for d in &differs {
                println!("{}: {d}", plan.url);
            }
            if !differs.is_empty() {
                return Ok(ExitCode::FAILURE);
            }
            println!("{} serves the document", plan.url);
            if move_ {
                println!("{}", dsip_app::web::move_to(&identity, &plan).context("moving the identity")?);
            }
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Join { identity } => {
            let (code, check) = dsip_app::pairing::start(&identity).context("starting to join")?;
            println!("join code: {code}\ncheck: {check} (the other device shows the same)");
            let handoff = dsip_app::pairing::Handoff::listen(&identity)
                .map_err(|e| eprintln!("not listening for the welcome code: {e}"))
                .ok();
            if let Some(h) = handoff.as_ref().filter(|h| !h.addresses().is_empty()) {
                println!("for a QR code (the welcome code then comes back by itself): {}", h.qr(&code));
            }
            eprintln!("welcome code:");
            // typed, or sent over the local network: whichever comes first
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let mut line = String::new();
                let _ = std::io::stdin().read_line(&mut line);
                let _ = tx.send(line);
            });
            let welcome = loop {
                if let Ok(line) = rx.try_recv() {
                    break line.trim().to_string();
                }
                let wait = std::time::Duration::from_millis(500);
                if let Some(r) = handoff.as_ref().map(|h| h.receive(wait)).transpose().context("listening")?.flatten() {
                    eprintln!("received from {} ({})", r.name, r.identity);
                    break r.welcome;
                }
                if handoff.is_none() {
                    std::thread::sleep(std::time::Duration::from_millis(200));
                }
            };
            println!("{}", dsip_app::pairing::finish(&identity, &welcome).context("joining")?);
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Welcome { identity, code } => {
            let (welcome, check) = dsip_app::pairing::welcome(&identity, &code).context("welcoming the device")?;
            println!("check: {check} (the new device shows the same)\n{welcome}");
            match dsip_app::pairing::send(&code, &welcome) {
                Ok(Some(to)) => println!("sent to the new device at {to}"),
                Ok(None) => {}
                Err(e) => eprintln!("not sent ({e}): give it the welcome code"),
            }
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Export { identity, out } => {
            let backup = dsip_app::backup::export_identity(&identity, &passphrase()?, None).context("backing up the identity")?;
            if let Some(out) = out {
                std::fs::write(&out, &backup.file).with_context(|| out.display().to_string())?;
            }
            println!("{}", backup.code);
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Restore { identity, code, name } => {
            // a path to a backup file, or the code itself
            let text = std::fs::read_to_string(&code).unwrap_or(code);
            let did = dsip_app::backup::restore_identity(&identity, &text, &passphrase()?, &name).context("restoring the identity")?;
            println!("{did}");
            return Ok(ExitCode::SUCCESS);
        }
        Cmd::Run {
            identity,
            relay,
            server,
            ca,
            audio,
            input,
            output,
            stun,
            mailbox,
            mailbox_did,
            hints_nodes,
            messaging_state,
            fetch_did_web,
            push_gateway,
        } => {
            // an identity made before its keys were kept in the store: moved in now
            dsip_app::keys::ready_identity(&identity);
            let mut settings = Settings {
                identity,
                relay: relay.unwrap_or_default(),
                ca,
                audio: Some(audio),
                audio_input: input,
                audio_output: output,
                stun,
                mailbox: mailbox.zip(mailbox_did).map(|(uri, did)| Mailbox { uri, did }),
                hints_nodes,
                messaging_state,
                fetch_did_web,
                push_gateway,
                server: None,
            };
            if let Some(domain) = server {
                let pem = match &settings.ca {
                    Some(p) => Some(std::fs::read(p).with_context(|| p.display().to_string())?),
                    None => None,
                };
                let list = dsip_app::servers::fetch(&domain, pem.as_deref()).await?;
                let did = dsip_app::keys::load_identity(&settings.identity)?.meta.identity;
                let found = list.settings(settings.identity.clone(), &domain, dsip_app::servers::pick_for(&did));
                if settings.relay.is_empty() {
                    settings.relay = found.relay;
                }
                settings.mailbox = settings.mailbox.or(found.mailbox);
                if settings.hints_nodes.is_empty() {
                    settings.hints_nodes = found.hints_nodes;
                }
                if settings.stun.is_empty() {
                    settings.stun = found.stun;
                }
                settings.server = found.server;
                tracing::info!("servers from {domain}: relay {}", settings.relay);
            }
            let cfg = settings.config()?;
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
        Cmd::Call { to } => Command::Call { to, video: false },
        Cmd::Introduce { to, purpose, name } => Command::Introduce { to, purpose, name },
        Cmd::DeleteMessage { conversation, id } => Command::DeleteMessage { conversation, id },
        Cmd::DeleteConversation { conversation } => Command::DeleteConversation { conversation },
        Cmd::ForgetCall { session: Some(session), .. } => Command::ForgetCall { session },
        Cmd::ForgetCall { session: None, .. } => Command::ClearHistory,
        Cmd::Accept { id } => Command::AcceptRequest { id },
        Cmd::DeclineRequest { id } => Command::DeclineRequest { id },
        Cmd::Message { to, text } => Command::Message { to, text: text.join(" ") },
        Cmd::SendFile { to, path, name } => {
            // the app may run elsewhere than this shell's directory
            let path = std::path::absolute(&path).with_context(|| format!("{}", path.display()))?;
            Command::SendFile { to, path: path.to_string_lossy().into_owned(), name }
        }
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
        Cmd::Audio { input: None, output: None } => Command::AudioDevices,
        Cmd::Audio { input, output } => Command::ChooseAudio { input, output },
        Cmd::Push { off: true, .. } => {
            Command::Push { provider: None, app: None, token: None, environment: None, message_app: None, message_token: None }
        }
        Cmd::Push { provider, app, token, environment, message_app, message_token, .. } => {
            Command::Push { provider, app, token, environment, message_app, message_token }
        }
        Cmd::OpenWake { data } => Command::OpenWake { data: serde_json::from_str(&data).context("the data is not JSON")? },
        Cmd::State => Command::State,
        Cmd::Quit => Command::Quit,
    };
    let response = control::request(&path, &cmd).await.with_context(|| format!("no app at {}", path.display()))?;
    println!("{}", serde_json::to_string(&response)?);
    Ok(if matches!(response, Response::Error { .. }) { ExitCode::FAILURE } else { ExitCode::SUCCESS })
}
