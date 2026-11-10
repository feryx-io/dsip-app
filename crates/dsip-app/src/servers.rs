//! The servers a domain offers new users, from `https://<domain>/.well-known/dsip`: its relays, mailboxes, hints nodes
//! and STUN servers. The first run asks for one domain (`feryx.io`) rather than four addresses, and the domain's
//! operator adds or retires servers without an app release.
//!
//! ```json
//! {"version": 1,
//!  "relays": ["wss://relay1.feryx.io/dsip", "wss://relay2.feryx.io/dsip"],
//!  "mailboxes": [{"uri": "wss://mailbox1.feryx.io/dsip", "did": "did:web:mailbox1.feryx.io"}],
//!  "hints_nodes": ["https://hints.feryx.io"],
//!  "stun": ["stun:turn.feryx.io:3478"]}
//! ```
//!
//! Relays and mailboxes are pools: a device picks one of each ([`Servers::settings`]) and keeps it, since its hint
//! names the relay and mailbox that hold it, and a contact looks for it there. Hints nodes and STUN servers are taken
//! whole. TURN comes, as before, from the chosen relay's `/turn`.
//!
//! Spec: none (infrastructure). Impl: the file is this app's, not DSIP's, as the relay's `/config.json` is the browser
//! client's: server addresses reach a client from where it is set up, not from the protocol (spec-gap 114).

use std::path::PathBuf;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::{Error, Mailbox, Settings};

/// Where on a domain the file is.
pub const PATH: &str = "/.well-known/dsip";

/// The version of the file this app reads.
pub const VERSION: u32 = 1;

/// The largest file read: a list of addresses, not a download.
const MAX_BYTES: usize = 64 * 1024;

/// Seconds the fetch may take.
const TIMEOUT_S: u64 = 10;

fn bad(what: String) -> Error {
    Error::Settings(what)
}

/// What a domain's `/.well-known/dsip` lists.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Servers {
    /// The file's version: [`VERSION`].
    pub version: u32,
    /// Relays (`wss://…/dsip`), one of which a device binds to.
    pub relays: Vec<String>,
    /// Mailboxes, one of which a device's identity is enrolled at; none: calls only.
    #[serde(default)]
    pub mailboxes: Vec<Mailbox>,
    /// Hints nodes (`https://…`): all of them.
    #[serde(default)]
    pub hints_nodes: Vec<String>,
    /// STUN servers (`stun:host:port`): all of them.
    #[serde(default)]
    pub stun: Vec<String>,
}

/// The URL of `domain`'s file: `feryx.io`, `https://feryx.io/` and `localhost:8443` are domains; a path is not.
pub fn url(domain: &str) -> Result<String, Error> {
    let d = domain.trim();
    let d = d.strip_prefix("https://").unwrap_or(d).trim_end_matches('/');
    let ok = !d.is_empty()
        && !d.starts_with(['.', '-', ':'])
        && d.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | ':' | '[' | ']'));
    if !ok {
        return Err(bad(format!("{domain:?} is not a domain (such as feryx.io)")));
    }
    Ok(format!("https://{}{PATH}", d.to_ascii_lowercase()))
}

/// Fetch and check `domain`'s list, trusting `ca_pem` besides the web's roots.
pub async fn fetch(domain: &str, ca_pem: Option<&[u8]>) -> Result<Servers, Error> {
    let url = url(domain)?;
    let at = |e: String| bad(format!("{url}: {e}"));
    let mut b = reqwest::Client::builder().use_rustls_tls().timeout(Duration::from_secs(TIMEOUT_S));
    if let Some(pem) = ca_pem {
        for cert in reqwest::Certificate::from_pem_bundle(pem).map_err(|e| bad(format!("CA: {e}")))? {
            b = b.add_root_certificate(cert);
        }
    }
    let http = b.build().map_err(|e| at(e.to_string()))?;
    let resp = http.get(&url).send().await.map_err(|e| at(e.to_string()))?;
    let status = resp.status();
    if status == reqwest::StatusCode::NOT_FOUND {
        return Err(bad(format!("{} lists no DSIP servers (nothing at {url})", domain.trim())));
    }
    if !status.is_success() {
        return Err(at(format!("answered {status}")));
    }
    if resp.content_length().is_some_and(|n| n > MAX_BYTES as u64) {
        return Err(at(format!("larger than {MAX_BYTES} bytes")));
    }
    let body = resp.bytes().await.map_err(|e| at(e.to_string()))?;
    if body.len() > MAX_BYTES {
        return Err(at(format!("larger than {MAX_BYTES} bytes")));
    }
    let servers: Servers = serde_json::from_slice(&body).map_err(|e| at(format!("not a list of servers: {e}")))?;
    servers.check().map_err(|e| at(e.to_string()))?;
    Ok(servers)
}

impl Servers {
    /// Whether the list is one this app can use: its version, a relay at least, and every address of its kind.
    pub fn check(&self) -> Result<(), Error> {
        if self.version != VERSION {
            return Err(bad(format!("version {}: this app reads version {VERSION}", self.version)));
        }
        if self.relays.is_empty() {
            return Err(bad("no relays".into()));
        }
        fn all<'a>(what: &str, xs: impl IntoIterator<Item = &'a String>, ok: &[&str]) -> Result<(), Error> {
            match xs.into_iter().find(|x| !ok.iter().any(|p| x.starts_with(p))) {
                Some(x) => Err(bad(format!("{what} {x:?} is not one"))),
                None => Ok(()),
            }
        }
        all("relay", &self.relays, &["wss://"])?;
        all("mailbox", self.mailboxes.iter().map(|m| &m.uri), &["wss://"])?;
        all("mailbox DID", self.mailboxes.iter().map(|m| &m.did), &["did:"])?;
        all("hints node", &self.hints_nodes, &["https://", "http://"])?;
        all("STUN server", &self.stun, &["stun:", "stuns:"])
    }

    /// Settings for an identity in `identity` using these servers: the relay and mailbox `pick` chooses from the
    /// pools (any number: a random one spreads devices across them), every hints node and STUN server, and `domain`
    /// kept as [`Settings::server`].
    pub fn settings(&self, identity: PathBuf, domain: &str, pick: u64) -> Settings {
        let one = |n: usize| (pick % n.max(1) as u64) as usize;
        Settings {
            identity,
            relay: self.relays.get(one(self.relays.len())).cloned().unwrap_or_default(),
            mailbox: self.mailboxes.get(one(self.mailboxes.len())).cloned(),
            hints_nodes: self.hints_nodes.clone(),
            stun: self.stun.clone(),
            server: Some(domain.trim().to_string()),
            ..Settings::default()
        }
    }
}

/// A random number to [`Servers::settings`] with.
pub fn random_pick() -> u64 {
    let mut b = [0u8; 8];
    // with no randomness to be had, the first of each: still a working choice
    let _ = getrandom::getrandom(&mut b);
    u64::from_le_bytes(b)
}

/// The pick for the identity `did`: the same on every start, and spread across the pools by identity (for a client
/// that keeps no settings of its own, `dsip-app run --server`).
pub fn pick_for(did: &str) -> u64 {
    use sha2::Digest as _;
    let h = sha2::Sha256::digest(did.as_bytes());
    u64::from_le_bytes(h[..8].try_into().unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list() -> Servers {
        serde_json::from_value(serde_json::json!({
            "version": 1,
            "relays": ["wss://relay1.feryx.io/dsip", "wss://relay2.feryx.io/dsip"],
            "mailboxes": [{"uri": "wss://mailbox1.feryx.io/dsip", "did": "did:web:mailbox1.feryx.io"}],
            "hints_nodes": ["https://hints.feryx.io"],
            "stun": ["stun:turn.feryx.io:3478"],
            "something_newer": true
        }))
        .unwrap()
    }

    #[test]
    fn a_domain_is_where_its_file_is() {
        for d in ["feryx.io", " https://feryx.io/ ", "Feryx.IO"] {
            assert_eq!(url(d).unwrap(), "https://feryx.io/.well-known/dsip", "{d}");
        }
        assert_eq!(url("localhost:8443").unwrap(), "https://localhost:8443/.well-known/dsip");
        for d in ["", "feryx.io/x", "http://feryx.io", "a b", ".io", "feryx.io?x"] {
            assert!(url(d).is_err(), "{d}");
        }
    }

    #[test]
    fn a_list_is_checked_and_newer_fields_ignored() {
        list().check().unwrap();
        let mut l = list();
        l.version = 2;
        assert!(l.check().unwrap_err().to_string().contains("version 2"));
        let mut l = list();
        l.relays.clear();
        assert!(l.check().is_err());
        let mut l = list();
        l.relays.push("https://relay3.feryx.io".into());
        assert!(l.check().unwrap_err().to_string().contains("relay3"));
        let mut l = list();
        l.mailboxes[0].did = "mailbox1".into();
        assert!(l.check().is_err());
        let mut l = list();
        l.stun = vec!["turn.feryx.io".into()];
        assert!(l.check().is_err());
    }

    #[test]
    fn a_device_takes_one_relay_and_mailbox_and_every_node() {
        let l = list();
        let s = l.settings("/id".into(), "feryx.io", 0);
        assert_eq!(s.relay, "wss://relay1.feryx.io/dsip");
        assert_eq!(l.settings("/id".into(), "feryx.io", 3).relay, "wss://relay2.feryx.io/dsip");
        assert_eq!(s.mailbox.as_ref().unwrap().did, "did:web:mailbox1.feryx.io");
        assert_eq!(s.hints_nodes, ["https://hints.feryx.io"]);
        assert_eq!(s.stun, ["stun:turn.feryx.io:3478"]);
        assert_eq!(s.server.as_deref(), Some("feryx.io"));
        let calls_only = Servers { mailboxes: vec![], ..l };
        assert_eq!(calls_only.settings("/id".into(), "feryx.io", 7).mailbox, None);
    }
}
