//! Messages: the app's [`dsip_messenger::Messenger`], bound to the identity's mailbox, on a thread of its own (a
//! messenger's host is driven on one task, and its store is a SQLite connection). Commands reach it as requests on a channel; what it
//! hears becomes [`Change`]s of the app's state.
//!
//! On every binding it uploads fresh KeyPackages, syncs live, and publishes the device's reachability hint naming its
//! relay and its mailbox, as the browser client does (M§4.2, DHT Hints Profile §10): that is how a `did:key` identity's
//! mailbox is found. Another identity's mailbox is found in §8.1's order, its document first, then its hint
//! (`dsip_messenger::Messenger::discover_mailbox`).
//!
//! A conversation starts with first contact (M§14.1): `introduce` asks an identity for permission to message, it
//! answers with `accept_request`, and the grant it sends lets `message` create the direct conversation (M§7.2,
//! M§14.2). A group conversation (M§7.3) is made with identities that granted us, each one's KeyPackages fetched
//! from its mailbox with that grant; any member adds or removes another, and this identity leaves one. Every protocol
//! decision is the messenger's, or the phone's.
//!
//! The grant is the phone's: one §19.4 grant lets the requester call, message and follow presence ([`GRANT_SCOPE`],
//! P§6), issued by the phone's engine so it can be withdrawn later, and deposited at the requester's mailbox. The
//! requester's app hands the grant it reads there to its phone, which presents it to follow the granter's presence,
//! and follows it. A grant the phone issues later, carrying new presence keys when a grant was withdrawn (P§12.5),
//! is deposited at its grantee's mailbox the same way: there it is an unsolicited grant (M§14.1).
//!
//! Impl: the hint is re-signed every [`HINT_REFRESH_S`], two thirds of its life; `seq` is the issue time, never at or
//! below the last one published.

use std::path::PathBuf;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::{mpsc, oneshot};

use dsip_messaging_device::{Event, Ui};
use dsip_messenger::{Engine, Host, Messenger, Output};
use dsip_mls::sqlite::SqliteProvider;

use crate::state::{ConversationView, MessageView, RequestView};
use crate::{App, Change, Response};

/// The hint's life, seconds: the profile's maximum (§12.9).
pub const HINT_TTL_S: i64 = dsip_core::HINT_MAX_VALIDITY_S;
/// Seconds between re-signing the hint.
pub const HINT_REFRESH_S: u64 = (HINT_TTL_S as u64) * 2 / 3;
/// What accepting a request grants: calls (§19.4), messages (M§14.2) and presence (P§6), as the browser client's
/// grant does.
pub const GRANT_SCOPE: &[&str] = &["dsip.invite", "dsip.message", "dsip.subscribe"];
/// How long a grant lasts: 30 days, as the messenger's own.
pub const GRANT_VALID_S: i64 = 30 * 86_400;
/// What the introduction sent back on accepting one says (the app takes accepting to mean both ways).
pub const INTRODUCED_BACK: &str = "Accepted your introduction";

/// KeyPackages uploaded on every binding (M§5.5), as the browser client does.
pub const KEY_PACKAGES_PER_BIND: usize = 2;

/// Where the identity's messages go.
#[derive(Debug, Clone)]
pub struct MessagingConfig {
    /// The identity's mailbox, `(DID, wss URI)`: one that serves it (an operator's, which enrols identities that bind,
    /// spec-gap 115).
    pub mailbox: (String, String),
    /// Hints nodes (`https://host:port`): where this device publishes its hint and looks up others'.
    pub hints_nodes: Vec<String>,
    /// A PEM certificate to trust for mailboxes and hints nodes, besides the platform's roots.
    pub ca: Option<PathBuf>,
    /// Where the device's messaging state lives (`device.sqlite`, fetched media).
    pub state_dir: PathBuf,
    /// Fetch `did:web` documents to find those identities' mailboxes (§7.2).
    pub fetch_did_web: bool,
}

/// A request to the messaging thread.
pub(crate) enum Req {
    Introduce { to: String, purpose: String, reply: oneshot::Sender<Response> },
    AcceptRequest { id: String, reply: oneshot::Sender<Response> },
    DeclineRequest { id: String, reply: oneshot::Sender<Response> },
    Message { to: String, text: String, reply: oneshot::Sender<Response> },
    SendFile { to: String, path: String, name: Option<String>, reply: oneshot::Sender<Response> },
    Thread { conversation: String, reply: oneshot::Sender<Response> },
    CreateGroup { members: Vec<String>, reply: oneshot::Sender<Response> },
    AddMember { conversation: String, identity: String, reply: oneshot::Sender<Response> },
    RemoveMember { conversation: String, identity: String, reply: oneshot::Sender<Response> },
    Leave { conversation: String, reply: oneshot::Sender<Response> },
    /// Delete message `id` of a conversation on this device, or with no `id`, the conversation (its messages; a group
    /// is left, a direct one hidden).
    Forget { conversation: String, id: Option<String>, reply: oneshot::Sender<Response> },
    /// Deposit a grant the phone issued at its grantee's mailbox.
    Deliver { to: String, grant: String },
    /// Register with the mailbox to be woken (A5d), or end the registration (`None`).
    Wake { ask: Option<crate::wake::MailboxAsk>, reply: oneshot::Sender<(crate::Registration, Option<crate::wake::Registered>)> },
    Stop,
}

/// The messenger's host: what it hears goes to the app's state.
struct AppHost {
    app: App,
    me: String,
    /// A binding happened: sync live and publish the hint (the messenger's own redial syncs once, not live).
    bound: bool,
    /// Requests accepted by themselves ([`auto_accept`]), tried once each.
    auto_tried: std::collections::BTreeSet<String>,
    /// Where attachments are kept, fetched or sent (the messenger's `media_dir`).
    media: PathBuf,
}

impl Host<SqliteProvider> for AppHost {
    async fn output(&mut self, engine: &Engine<SqliteProvider>, out: Output) {
        match out {
            Output::Event(Event::Ui(Ui::Message { group, object, .. })) => {
                let message = MessageView::of(&group, &object, &self.me, &self.media);
                // a deleted direct conversation is listed again when a message comes in it
                self.app.hide(&message.conversation, false);
                self.app.publish(Change::Message { message });
            }
            Output::Event(Event::Ui(Ui::Granted { by, .. })) => {
                // the phone holds it too, to present when following their presence (P§6)
                if let Some(g) = engine.grant_held(&by) {
                    match self.app.inner.phone.hold_grant(g).await {
                        Ok(true) => self.app.follow(&by).await,
                        Ok(false) => tracing::info!("the grant from {by} does not admit presence here"),
                        Err(e) => tracing::warn!("holding the grant from {by}: {e}"),
                    }
                }
                self.app.introduction_accepted(&by);
                self.app.publish(Change::Granted { by });
            }
            Output::Event(Event::Ui(Ui::Removed { group, by, left: false, .. })) => {
                self.app.publish(Change::Removed { conversation: group, by });
            }
            Output::Blob { object, path, .. } => {
                // an attachment fetched and decrypted (M§8.4 rule 7): its conversation's group, for the screen
                let now = dsip_transport::now_s() as f64;
                let group = engine.conversations(now).into_iter().find(|c| object["conversation"] == c.conversation.as_str()).map(|c| c.group);
                if let Some(conversation) = group {
                    let id = object["id"].as_str().unwrap_or("").to_string();
                    self.app.publish(Change::MessageFile { conversation, id, path: path.to_string_lossy().into_owned() });
                }
            }
            Output::Connected { mailbox, .. } => {
                tracing::info!("messaging: bound to mailbox {mailbox}");
                self.bound = true;
                self.app.set_messaging(|m| m.connected = true);
            }
            Output::Disconnected | Output::ConnectionError(_) => {
                self.app.set_messaging(|m| m.connected = false);
            }
            Output::ReconnectFailed { error, wait_s } => tracing::info!("messaging: redial failed ({error}); again in {wait_s} s"),
            Output::Error(e) => tracing::warn!("messaging: {e}"),
            _ => {}
        }
        refresh(&self.app, engine);
    }

    fn saved(&self) -> Value {
        json!({})
    }
}

/// Publish the conversations and requests if they changed.
fn refresh(app: &App, engine: &Engine<SqliteProvider>) {
    let now = dsip_transport::now_s() as f64;
    let conversations: Vec<ConversationView> = engine
        .conversations(now)
        .into_iter()
        .filter(|c| c.kind != "personal" && !app.hidden(&c.group))
        .map(|c| ConversationView { group: c.group, conversation: c.conversation, kind: c.kind, peer: c.peer, members: c.members, pending: c.pending })
        .collect();
    let requests: Vec<RequestView> = engine
        .requests()
        .iter()
        .map(|(id, p)| RequestView {
            id: id.clone(),
            from: p["from"].as_str().unwrap_or("").to_string(),
            name: p["identity"]["display_name"].as_str().map(String::from),
            purpose: p["purpose"].as_str().map(String::from),
        })
        .collect();
    let (convs_changed, reqs_changed) = {
        let s = app.inner.state.lock().unwrap_or_else(|e| e.into_inner());
        (s.messaging.conversations != conversations, s.messaging.requests != requests)
    };
    if convs_changed {
        app.publish(Change::Conversations { conversations });
    }
    if reqs_changed {
        app.publish(Change::Requests { requests });
    }
}

/// Start the messaging thread for the identity in `identity_dir`, whose relay is `relay`.
pub(crate) fn spawn(app: App, cfg: MessagingConfig, identity_dir: PathBuf, relay: String) -> Result<mpsc::UnboundedSender<Req>, String> {
    let id = crate::keys::load_identity(&identity_dir).map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&cfg.state_dir).map_err(|e| format!("{}: {e}", cfg.state_dir.display()))?;
    let (tx, rx) = mpsc::unbounded_channel();
    // the store is a SQLite connection, which stays on the thread that opened it: opened there, its failure sent back
    let (opened, open_result) = std::sync::mpsc::channel::<Result<(), String>>();
    std::thread::Builder::new()
        .name("dsip-app messaging".into())
        .spawn(move || {
            let store = match SqliteProvider::open(&cfg.state_dir.join("device.sqlite")) {
                Ok(s) => s,
                Err(e) => return drop(opened.send(Err(format!("messaging state: {e:?}")))),
            };
            let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
                Ok(rt) => rt,
                Err(e) => return drop(opened.send(Err(format!("messaging: no runtime: {e}")))),
            };
            let _ = opened.send(Ok(()));
            let local = tokio::task::LocalSet::new();
            if let Err(e) = local.block_on(&rt, run(app, cfg, id, relay, store, rx)) {
                tracing::warn!("messaging stopped: {e}");
            }
        })
        .map_err(|e| e.to_string())?;
    open_result.recv().map_err(|_| "messaging thread ended".to_string())??;
    Ok(tx)
}

async fn run(app: App, cfg: MessagingConfig, id: dsip_phone::Identity, relay: String, store: SqliteProvider,
             mut rx: mpsc::UnboundedReceiver<Req>) -> Result<(), String> {
    let identity = id.meta.identity.clone();
    let now = dsip_transport::now_s();
    let err = |e: &dyn std::fmt::Display| e.to_string();
    let mut saved = dsip_messaging_device::Store::get(&store, "messenger").map_err(|e| format!("{e:?}"))?.unwrap_or(Value::Null);
    if let (Some(resume), true) = (dsip_messaging_device::Store::get(&store, "resume").map_err(|e| format!("{e:?}"))?, saved.is_object()) {
        saved["resume"] = resume; // spec-gap 44: the item transactions keep the delivery state under its own key
    }
    // the identity's key agreement key opens sealed introductions first (§7.3, spec-gap 179)
    let ka_secret = id.key_agreement.as_ref().map(|k| k.secret);
    let engine_identity = dsip_messenger::engine_identity_with(&identity, &id.device, id.controller.as_ref(), &id.delegation, &id.meta.display_name, ka_secret.as_ref());
    let engine = Engine::open(&engine_identity, &cfg.mailbox.0, &cfg.mailbox.1, store, &saved, now as f64).map_err(|e| err(&e.0))?;
    let mcfg = dsip_messenger::Config {
        identity: identity.clone(),
        device: id.device.clone(),
        delegation: id.delegation.clone(),
        mailbox: cfg.mailbox.clone(),
        resolver_files: vec![],
        ca: cfg.ca.clone(),
        media_dir: cfg.state_dir.join("media"),
        host_key: "dsip-app".into(),
    };
    let pem = match &cfg.ca {
        Some(p) => Some(std::fs::read(p).map_err(|e| format!("{}: {e}", p.display()))?),
        None => None,
    };
    let hints = dsip_transport::hints::HintsClient::new(cfg.hints_nodes.clone(), pem.as_deref()).map_err(|e| err(&e))?;
    let mut mx = Messenger::new(engine, mcfg, vec![]).map_err(|e| err(&e))?.with_hints(hints.clone());
    if cfg.fetch_did_web {
        if let Some(web) = dsip_transport::resolver::web_documents(true, dsip_transport::DidWebResolver::TTL_S, cfg.ca.as_deref()).map_err(|e| err(&e))? {
            mx = mx.with_did_web(web);
        }
    }
    let mut host = AppHost { app: app.clone(), me: identity.clone(), bound: false, auto_tried: Default::default(),
                             media: cfg.state_dir.join("media") };
    app.set_messaging(|m| m.mailbox = Some(cfg.mailbox.0.clone()));
    if let Err(e) = mx.connect(&mut host).await {
        tracing::warn!("messaging: mailbox {}: {e}; redialling", cfg.mailbox.1);
        mx.lost_connection();
    }
    refresh(&app, mx.engine());
    let mut clock = tokio::time::interval(Duration::from_secs(1));
    let mut last_seq = 0i64;
    let mut hint_due = tokio::time::Instant::now();
    loop {
        if host.bound {
            host.bound = false;
            on_bind(&mut mx, &mut host).await;
            // a mailbox that was not bound when waking was looked at gets its registration now (W§4.3)
            if let Some(w) = host.app.inner.wake.get() {
                let _ = w.send(crate::wake::Kick::Check);
            }
            hint_due = tokio::time::Instant::now();
        }
        if tokio::time::Instant::now() >= hint_due && mx.connection().is_some() && !cfg.hints_nodes.is_empty() {
            let seq = dsip_transport::now_s().max(last_seq + 1);
            last_seq = seq;
            let endpoints = dsip_transport::hints::endpoints(Some(&relay), Some((&cfg.mailbox.0, &cfg.mailbox.1)));
            let ka = id.key_agreement.as_ref().map(|k| &k.delegation);
            let hint = dsip_transport::hints::reachability_with(&identity, &id.device, &id.delegation, &endpoints, seq, dsip_transport::now_s(), HINT_TTL_S, ka);
            for (node, r) in hints.publish(&hint).await {
                tracing::info!("hint seq {seq} → {node}: {r:?}");
            }
            hint_due = tokio::time::Instant::now() + Duration::from_secs(HINT_REFRESH_S);
        }
        tokio::select! {
            req = rx.recv() => match req {
                Some(Req::Stop) | None => break,
                Some(r) => request(&mut mx, &mut host, r).await,
            },
            Some(frame) = mx.recv() => mx.received(&mut host, frame).await,
            _ = clock.tick() => {
                mx.tick(&mut host).await;
                if let Err(e) = mx.check_reconnect(&mut host).await {
                    tracing::warn!("messaging: {e}");
                }
                if let Err(e) = mx.retry_blobs(&host) {
                    tracing::warn!("messaging: {e}");
                }
            }
        }
        mx.settle(&mut host).await;
        auto_accept(&mut mx, &mut host).await;
        if let Err(e) = mx.save(&host) {
            tracing::warn!("messaging: saving: {e}");
        }
    }
    let _ = mx.save(&host);
    Ok(())
}

/// What every binding does: fresh KeyPackages (M§5.5), and a live sync (M§5.4).
async fn on_bind(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost) {
    let now = dsip_transport::now_s() as f64;
    match mx.engine_mut().key_packages_frame(KEY_PACKAGES_PER_BIND, now) {
        Ok(frame) => {
            if let Err(e) = mx.send_frame(host, &frame).await {
                tracing::warn!("messaging: KeyPackages: {e}");
            }
        }
        Err(e) => tracing::warn!("messaging: KeyPackages: {}", e.0),
    }
    mx.settle(host).await;
    if let Err(e) = mx.sync(host, true).await {
        tracing::warn!("messaging: sync: {e}");
    }
}

async fn request(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, req: Req) {
    match req {
        Req::Introduce { to, purpose, reply } => {
            let _ = reply.send(introduce(mx, host, &to, &purpose).await.unwrap_or_else(Response::error));
        }
        Req::AcceptRequest { id, reply } => {
            let _ = reply.send(accept_request(mx, host, &id, true).await.unwrap_or_else(Response::error));
        }
        Req::DeclineRequest { id, reply } => {
            let r = if mx.engine_mut().forget_request(&id) { Response::Ok } else { Response::error(format!("no request {id}")) };
            refresh(&host.app, mx.engine());
            let _ = reply.send(r);
        }
        Req::Message { to, text, reply } => {
            let _ = reply.send(message(mx, host, &to, &text).await.unwrap_or_else(Response::error));
        }
        Req::SendFile { to, path, name, reply } => {
            let _ = reply.send(send_file(mx, host, &to, &path, name).await.unwrap_or_else(Response::error));
        }
        Req::Thread { conversation, reply } => {
            let messages = mx
                .engine()
                .thread(&conversation)
                .iter()
                .map(|m| MessageView::of(&conversation, &m["object"], &host.me, &host.media))
                .collect();
            let _ = reply.send(Response::Thread { messages });
        }
        Req::CreateGroup { members, reply } => {
            let _ = reply.send(create_group(mx, host, &members).await.unwrap_or_else(Response::error));
        }
        Req::AddMember { conversation, identity, reply } => {
            let _ = reply.send(add_member(mx, host, &conversation, &identity).await.unwrap_or_else(Response::error));
        }
        Req::RemoveMember { conversation, identity, reply } => {
            let now = dsip_transport::now_s() as f64;
            let r = match mx.engine_mut().remove_member(&conversation, &identity, now) {
                Ok(frame) => commit(mx, host, &frame).await,
                Err(e) => Err(e.0),
            };
            let _ = reply.send(r.map(|()| Response::Ok).unwrap_or_else(Response::error));
        }
        Req::Leave { conversation, reply } => {
            let now = dsip_transport::now_s() as f64;
            let r = match mx.engine_mut().leave(&conversation, now) {
                Ok(out) => mx.handle(host, out).await.map_err(|e| e.to_string()),
                Err(e) => Err(e.0),
            };
            refresh(&host.app, mx.engine());
            let _ = reply.send(r.map(|()| Response::Ok).unwrap_or_else(Response::error));
        }
        Req::Forget { conversation, id: Some(id), reply } => {
            let r = if mx.engine_mut().forget_message(&conversation, &id) {
                Response::Ok
            } else {
                Response::error(format!("no message {id} in {conversation}"))
            };
            let _ = reply.send(r);
        }
        Req::Forget { conversation, id: None, reply } => {
            let now = dsip_transport::now_s() as f64;
            let kind = mx.engine().conversations(now).into_iter().find(|c| c.group == conversation).map(|c| c.kind);
            let r = match kind.as_deref() {
                None => Err(format!("no conversation {conversation}")),
                Some("group") => match mx.engine_mut().leave(&conversation, now) {
                    Ok(out) => mx.handle(host, out).await.map_err(|e| e.to_string()),
                    Err(e) => Err(e.0),
                },
                Some(_) => {
                    host.app.hide(&conversation, true);
                    Ok(())
                }
            };
            if r.is_ok() {
                mx.engine_mut().forget_thread(&conversation);
            }
            refresh(&host.app, mx.engine());
            let _ = reply.send(r.map(|()| Response::Ok).unwrap_or_else(Response::error));
        }
        Req::Deliver { to, grant } => {
            if let Err(e) = deliver(mx, &to, &grant).await {
                tracing::warn!("the grant to {to} not deposited at its mailbox: {e}");
            }
        }
        Req::Wake { ask, reply } => {
            let r = match ask {
                Some(a) => crate::wake::at_mailbox(mx, host, a).await,
                None => {
                    if let Err(e) = mx.wake_remove(host).await {
                        tracing::info!("waking: ending the mailbox's registration: {e}");
                    }
                    (crate::Registration::status("removed"), None)
                }
            };
            let _ = reply.send(r);
        }
        Req::Stop => {}
    }
}

/// M§14.1: ask `to` for permission to message, the purpose sealed to its key agreement key.
async fn introduce(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, to: &str, purpose: &str) -> Result<Response, String> {
    let now = dsip_transport::now_s() as f64;
    let r = mx.engine_mut().introduce(to, purpose, false, now).map_err(|e| e.0)?;
    // spec-gap 81: tell our own mailbox first, so the grant that answers is not rate-limited there (best effort)
    if let Err(e) = mx.send_frame(host, &r.send).await {
        tracing::warn!("introduction {} not announced to our own mailbox: {e}", r.id);
    }
    let mut conn = mx.peer_connect(to).await.map_err(|e| e.to_string())?;
    let did = conn.relay.did.clone();
    let frame = mx.engine_mut().first_contact_frame(&did, "introduction", to, &r.envelope, now);
    let answer = dsip_messenger::peer_exchange(&mut conn, &frame).await.map_err(|e| e.to_string())?;
    match answer["type"].as_str() {
        Some("accepted") => Ok(Response::Ok),
        _ => Err(format!("introduction refused: {} (retry after {})", answer["reason"], answer["retry_after"])),
    }
}

/// M§14.1: answer request `id` with a grant, deposited at the requester's mailbox. With `back`, and unless the
/// requester granted us already or was introduced to by us, introduce ourselves to it in turn ([`INTRODUCED_BACK`]):
/// its app accepts that by itself ([`auto_accept`]), so each side can call, message and follow the other.
///
/// A grant is one way (§19.4): the app takes accepting to mean both ways, as people expect of accepting a contact.
async fn accept_request(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, id: &str, back: bool) -> Result<Response, String> {
    let now = dsip_transport::now_s();
    let requester = mx.engine().requests().get(id).and_then(|p| p["from"].as_str()).map(String::from).ok_or_else(|| format!("no request {id}"))?;
    let request = dsip_phone::GrantRequest {
        introduction: id.to_string(),
        requester: requester.clone(),
        scope: GRANT_SCOPE.iter().map(|s| s.to_string()).collect(),
        valid_until: now + GRANT_VALID_S,
    };
    let grant = host.app.inner.phone.grant_request(request).await.map_err(|e| e.to_string())?.ok_or("the phone issued no grant")?;
    let mut conn = mx.peer_connect(&requester).await.map_err(|e| e.to_string())?;
    let did = conn.relay.did.clone();
    let frame = mx.engine_mut().first_contact_frame(&did, "grant", &requester, &grant, now as f64);
    let answer = dsip_messenger::peer_exchange(&mut conn, &frame).await.map_err(|e| e.to_string())?;
    if answer["type"] != "accepted" {
        return Err(format!("grant refused: {}", answer["reason"]));
    }
    mx.engine_mut().forget_request(id);
    refresh(&host.app, mx.engine());
    let asked_already = host.app.state().messaging.introduced.iter().any(|i| i.to == requester);
    if back && mx.engine().grant_held(&requester).is_none() && !asked_already {
        match introduce(mx, host, &requester, INTRODUCED_BACK).await {
            Ok(_) => {
                let name = host.app.state().names.get(&requester).cloned();
                host.app.record_introduced(requester, name, INTRODUCED_BACK.into());
            }
            Err(e) => tracing::warn!("introducing ourselves back to {requester}: {e}"),
        }
    }
    Ok(Response::Ok)
}

/// Accept, by itself, a request from an identity this one introduced itself to: it asked first, so it wants to hear
/// from them (the other side of [`accept_request`]'s introduction back). Each request is tried once; it becomes a
/// contact as an accepted one does.
async fn auto_accept(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost) {
    let asked: std::collections::BTreeSet<String> = host.app.state().messaging.introduced.into_iter().map(|i| i.to).collect();
    let due: Vec<(String, String, Option<String>)> = mx
        .engine()
        .requests()
        .iter()
        .filter_map(|(id, p)| {
            let from = p["from"].as_str()?;
            (asked.contains(from) && !host.auto_tried.contains(id))
                .then(|| (id.clone(), from.to_string(), p["identity"]["display_name"].as_str().map(String::from)))
        })
        .collect();
    for (id, from, name) in due {
        host.auto_tried.insert(id.clone());
        match accept_request(mx, host, &id, false).await {
            Ok(_) => {
                tracing::info!("accepted {from}'s introduction by itself: we introduced ourselves to them");
                host.app.add_contact(&from, name.as_deref());
            }
            Err(e) => tracing::warn!("accepting {from}'s introduction by itself: {e}"),
        }
    }
}

/// `identity`'s KeyPackages from its mailbox (M§5.5), fetched with the grant we hold from it (M§14.2), its devices
/// noted.
async fn key_packages(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, identity: &str, now: f64) -> Result<Value, String> {
    let answer = mx.fetch_key_packages(host, identity, None).await.map_err(|e| format!("{identity}: {e}"))?;
    mx.engine_mut().key_package_devices(identity, &answer, now).map_err(|e| e.0)?;
    Ok(answer)
}

/// M§7.3: a group conversation with `members`, hubbed at our mailbox, with our own other devices; every add in one
/// commit, sent once the hub holds the group.
async fn create_group(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, members: &[String]) -> Result<Response, String> {
    let now = dsip_transport::now_s() as f64;
    let me = host.me.clone();
    let mut targets = std::collections::BTreeMap::new();
    for m in members.iter().filter(|m| **m != me) {
        let answer = key_packages(mx, host, m, now).await?;
        targets.insert(m.clone(), answer);
    }
    let own = match mx.fetch_key_packages(host, &me, None).await {
        Ok(a) => Some(a),
        Err(e) => {
            tracing::info!("our own devices: none added to the group ({e})");
            None
        }
    };
    let before: std::collections::HashSet<String> = mx.engine().conversations(now).into_iter().map(|c| c.group).collect();
    let frames = mx.engine_mut().create_group(&targets, own.as_ref(), now).map_err(|e| e.0)?;
    let gid = mx.engine().conversations(now).into_iter().map(|c| c.group).find(|g| !before.contains(g)).ok_or("no group created")?;
    mx.save(host).map_err(|e| e.to_string())?;
    mx.send_frames(host, &frames).await.map_err(|e| e.to_string())?;
    mx.settle(host).await;
    refresh(&host.app, mx.engine());
    Ok(Response::Conversation { conversation: gid })
}

/// M§7.3: add `identity`'s devices to the group conversation `gid` (any member may, holding its grant, M§14.2).
async fn add_member(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, gid: &str, identity: &str) -> Result<Response, String> {
    let now = dsip_transport::now_s() as f64;
    let answer = key_packages(mx, host, identity, now).await?;
    let frame = mx.engine_mut().add_member(gid, identity, &answer, now).map_err(|e| e.0)?;
    commit(mx, host, &frame).await?;
    Ok(Response::Ok)
}

/// Send a commit to the conversation's hub, durably first (M§9.2), and take what follows.
async fn commit(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, frame: &str) -> Result<(), String> {
    mx.save(host).map_err(|e| e.to_string())?;
    mx.send_frame(host, frame).await.map_err(|e| e.to_string())?;
    mx.settle(host).await;
    refresh(&host.app, mx.engine());
    Ok(())
}

/// Deposit `grant` at `to`'s mailbox (M§14.1), as [`accept_request`] deposits the first.
async fn deliver(mx: &mut Messenger<SqliteProvider>, to: &str, grant: &str) -> Result<(), String> {
    let mut conn = mx.peer_connect(to).await.map_err(|e| e.to_string())?;
    let did = conn.relay.did.clone();
    let frame = mx.engine_mut().first_contact_frame(&did, "grant", to, grant, dsip_transport::now_s() as f64);
    let answer = dsip_messenger::peer_exchange(&mut conn, &frame).await.map_err(|e| e.to_string())?;
    match answer["type"].as_str() {
        Some("accepted") => Ok(()),
        _ => Err(format!("refused: {} (retry after {})", answer["reason"], answer["retry_after"])),
    }
}

/// Send `text` to `to`: a conversation's group id, or an identity — its direct conversation, created when there is
/// none (M§7.2, presenting the grant it sent, M§14.2).
/// The conversation `to` names (its group id, its conversation id, or the peer of a direct one), made as a direct
/// conversation with that identity when there is none yet (M§7.2); refused when a recorder in it is not accepted
/// (C§5).
async fn conversation_for(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, to: &str, now: f64)
                          -> Result<dsip_messaging_device::Conversation, String> {
    let convs = mx.engine().conversations(now);
    let group = match convs.iter().find(|c| c.group == to || c.conversation == to || (c.kind == "direct" && c.peer.as_deref() == Some(to))) {
        Some(c) => c.group.clone(),
        None => {
            let answer = mx.fetch_key_packages(host, to, None).await.map_err(|e| e.to_string())?;
            mx.engine_mut().key_package_devices(to, &answer, now).map_err(|e| e.0)?;
            let frames = mx.engine_mut().create_direct(to, &answer, None, now).map_err(|e| e.0)?;
            let gid = frames
                .first()
                .and_then(|f| dsip_core::envelope::Envelope::from_frame(f).ok())
                .and_then(|e| dsip_messaging::wire::payload_of(&e))
                .and_then(|p| p["groups"][0]["group"].as_str().map(String::from))
                .ok_or("no group created")?;
            mx.save(host).map_err(|e| e.to_string())?;
            mx.send_frames(host, &frames).await.map_err(|e| e.to_string())?;
            mx.settle(host).await;
            gid
        }
    };
    let c = mx.engine().conversations(now).into_iter().find(|c| c.group == group).ok_or("not a member of that conversation")?;
    if !c.may_send {
        return Err("a recorder in this conversation is not accepted yet (C§5)".into());
    }
    Ok(c)
}

async fn message(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, to: &str, text: &str) -> Result<Response, String> {
    let now = dsip_transport::now_s() as f64;
    let c = conversation_for(mx, host, to, now).await?;
    let group = c.group.clone();
    let id = mx.engine_mut().new_id(now);
    let obj = json!({"object": "content", "id": id, "conversation": c.conversation, "sender": host.me, "sent_at": now as i64,
                     "purpose": "message", "kind": "text", "content_type": "text/plain", "text": text});
    let sent = mx.engine_mut().send(&group, &obj, now).map_err(|e| e.0)?;
    mx.save(host).map_err(|e| e.to_string())?; // M§9.2: pending, durably, before it goes out
    if !sent.send.is_empty() {
        mx.send_frame(host, &sent.send).await.map_err(|e| e.to_string())?;
    }
    let message = MessageView::of(&group, &obj, &host.me, &host.media);
    host.app.hide(&group, false);
    host.app.publish(Change::Message { message });
    refresh(&host.app, mx.engine());
    Ok(Response::Conversation { conversation: group })
}

/// The largest file sent, bytes: a mailbox's own limit (`max_blob_bytes`, 16 MiB by default) is checked as it uploads.
pub const FILE_MAX: u64 = 64 * 1024 * 1024;

/// The media type of a file, from its name's extension.
fn content_type_of(name: &str) -> &'static str {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "heic" => "image/heic",
        "pdf" => "application/pdf",
        "txt" | "log" | "md" => "text/plain",
        "ogg" | "opus" => "audio/ogg",
        "mp3" => "audio/mpeg",
        "m4a" => "audio/mp4",
        "mp4" => "video/mp4",
        "webm" => "video/webm",
        "zip" => "application/zip",
        "json" => "application/json",
        "doc" | "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" | "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        _ => "application/octet-stream",
    }
}

/// Send the file at `path` to `to` (M§8.2, M§8.4): sealed and uploaded to this identity's mailbox, then sent as an
/// `image` or a `file` naming it; kept in the media folder too, so the sender's own thread shows it.
async fn send_file(mx: &mut Messenger<SqliteProvider>, host: &mut AppHost, to: &str, path: &str, name: Option<String>) -> Result<Response, String> {
    let file = std::path::Path::new(path);
    let len = std::fs::metadata(file).map_err(|e| format!("{path}: {e}"))?.len();
    if len > FILE_MAX {
        return Err(format!("{path}: {len} bytes, over {FILE_MAX}"));
    }
    let name = name.filter(|n| !n.trim().is_empty())
        .or_else(|| file.file_name().map(|n| n.to_string_lossy().into_owned()))
        .unwrap_or_else(|| "file".into());
    let plain = std::fs::read(file).map_err(|e| format!("{path}: {e}"))?;
    let content_type = content_type_of(&name);
    let kind = if content_type.starts_with("image/") { "image" } else { "file" };
    let now = dsip_transport::now_s() as f64;
    let c = conversation_for(mx, host, to, now).await?;
    let blob = mx.upload_blob(&plain, content_type).await.map_err(|e| e.to_string())?;
    let id = mx.engine_mut().new_id(now);
    let obj = dsip_messaging_device::blob::attachment_content(&id, &c.conversation, &host.me, now as i64, kind, Some(&name), &blob.uploaded(), None);
    // the sender's copy, where a fetched one would be
    let kept = host.media.join(dsip_messaging_device::blob::file_name(&obj));
    if let Err(e) = std::fs::create_dir_all(&host.media).and_then(|()| std::fs::write(&kept, &plain)) {
        tracing::warn!("keeping {}: {e}", kept.display());
    }
    let sent = mx.engine_mut().send(&c.group, &obj, now).map_err(|e| e.0)?;
    mx.save(host).map_err(|e| e.to_string())?; // M§9.2: pending, durably, before it goes out
    if !sent.send.is_empty() {
        mx.send_frame(host, &sent.send).await.map_err(|e| e.to_string())?;
    }
    host.app.hide(&c.group, false);
    host.app.publish(Change::Message { message: MessageView::of(&c.group, &obj, &host.me, &host.media) });
    refresh(&host.app, mx.engine());
    Ok(Response::Conversation { conversation: c.group })
}
