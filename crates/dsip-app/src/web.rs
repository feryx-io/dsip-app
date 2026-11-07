//! An identity on a domain of the person's own (app plan A6d, decision 5 (c)): a `did:web` DID in place of the
//! `did:key` this app makes, which the person can rotate (§7.5) and keep however the device is lost, because they hold
//! the domain. In three steps, so the identity is never unreachable:
//!
//! 1. [`prepare`]: the DID document the domain must serve, and where. Nothing changes yet.
//! 2. [`check`]: fetch what the domain serves, and say how it differs from what it must be.
//! 3. [`move_to`]: the identity becomes the `did:web`. Its keys stay where they are; its delegation and its key
//!    agreement delegation are signed again for the new DID. The app then starts again as it.
//!
//! The DID is a new identity to everyone who knew the `did:key`: contacts and grants are under the old one, and are
//! asked for again. What the document says is dsip-rs's (`Identity::did_web_document`): the identity key, the key
//! agreement key (the delegated one, §7.3), the relay (`DSIPSignaling`) and the mailbox (`DSIPMailbox`), since a
//! `did:web` is reached by its document alone (§8.1).
//!
//! Spec: none (infrastructure). §7.2, §7.3, §8.1 name what the document carries.

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use serde_json::Value;

use crate::Error;

/// What the domain must serve: the document, at its URL.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Plan {
    /// The `did:web` DID.
    pub did: String,
    /// Where the document is fetched from (`https://<host>/.well-known/did.json`, or `…/<path>/did.json`).
    pub url: String,
    /// The document.
    pub document: Value,
}

fn bad(why: impl Into<String>) -> Error {
    Error::Keys(why.into())
}

/// The document the identity in `dir` would serve as `did` (a `did:web`), naming `relay` and `mailbox` (`(DID, URI)`),
/// and where it goes. The identity is not changed.
pub fn prepare(dir: &Path, did: &str, relay: &str, mailbox: Option<(&str, &str)>) -> Result<Plan, Error> {
    let url = dsip_transport::resolver::did_web_url(did).map_err(|e| bad(format!("{did}: {e}")))?;
    let mut id = crate::keys::load_identity(dir)?;
    id.meta.identity = did.to_string();
    Ok(Plan { did: did.to_string(), url, document: id.did_web_document(Some(relay), mailbox, &[])? })
}

/// Fetch what `plan`'s URL serves (trusting `ca`, PEM, besides the web PKI) and compare it with `plan.document`: what
/// differs, each in a sentence; empty when the domain serves what it must.
pub async fn check(plan: &Plan, ca: Option<&Path>) -> Result<Vec<String>, Error> {
    let mut web = dsip_transport::resolver::DidWebResolver::with(Duration::from_secs(60), Duration::from_secs(10));
    if let Some(ca) = ca {
        let pem = std::fs::read(ca).map_err(|e| bad(format!("{}: {e}", ca.display())))?;
        web = web.with_ca(&pem).map_err(|e| bad(e.to_string()))?;
    }
    let docs = Arc::new(dsip_transport::resolver::WebDocuments::new(web));
    docs.fetch(std::slice::from_ref(&plan.did)).await;
    let Some(served) = docs.held(&plan.did) else {
        return Ok(vec![format!("nothing that reads as a DID document at {}", plan.url)]);
    };
    let want: dsip_core::did::DidDocument =
        serde_json::from_value(plan.document.clone()).map_err(|e| bad(format!("the document: {e}")))?;
    let kid = format!("{}#key-1", plan.did);
    let mut differs = vec![];
    if served.id != plan.did {
        differs.push(format!("its id is {}, not {}", served.id, plan.did));
    }
    if served.ed25519_key(&kid, "key-1") != want.ed25519_key(&kid, "key-1") {
        differs.push("its #key-1 is not this identity's key".into());
    }
    if served.x25519_key_agreement() != want.x25519_key_agreement() {
        differs.push("its keyAgreement is not this identity's key agreement key".into());
    }
    if served.signaling_uri() != want.signaling_uri() {
        differs.push(format!("its DSIPSignaling service is not {}", want.signaling_uri().unwrap_or_default()));
    }
    let mailbox = |d: &dsip_core::did::DidDocument| {
        d.service.iter().find(|s| s.service_type == "DSIPMailbox").map(|s| s.service_endpoint.clone())
    };
    if mailbox(&served) != mailbox(&want) {
        differs.push("its DSIPMailbox service is not this identity's mailbox".into());
    }
    Ok(differs)
}

/// Make the identity in `dir` the `did:web` of `plan`: its delegation and key agreement delegation signed again for
/// it, `did.json` written beside it, and its keys kept where they were (the store, or files). Its new DID.
pub fn move_to(dir: &Path, plan: &Plan) -> Result<String, Error> {
    let mut id = crate::keys::load_identity(dir)?;
    if id.meta.identity == plan.did {
        return Ok(plan.did.clone());
    }
    id.rehome_did_web(&plan.did, &[])?;
    std::fs::write(dir.join("did.json"), serde_json::to_string_pretty(&plan.document).expect("JSON"))
        .map_err(|e| bad(format!("did.json: {e}")))?;
    crate::keys::keep(dir, &id)?;
    Ok(id.meta.identity)
}
