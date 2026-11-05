//! How to run the app, as data: what `dsip-app run`'s flags say, and what the desktop app keeps in its settings file
//! and hands its bridge as JSON. One [`Settings::config`] turns either into the [`Config`] the app starts with.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::{Config, Error, HostKind, MessagingConfig};

/// How to run the app.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Settings {
    /// The identity directory (`dsip-app init`, [`init_identity`]).
    pub identity: PathBuf,
    /// The relay (`wss://host:8443/dsip`).
    pub relay: String,
    /// A PEM certificate to trust for the relay, mailbox and hints nodes, besides the platform's roots.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ca: Option<PathBuf>,
    /// `system` (the microphone and speaker), `tone` (a test tone), `none` (calls without sound). Default: `system`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio: Option<String>,
    /// The microphone to use (an [`AudioDevice::id`](crate::AudioDevice)); without it, the system's default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_input: Option<String>,
    /// The speaker to use; without it, the system's default.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_output: Option<String>,
    /// STUN servers for the calls' media.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stun: Vec<String>,
    /// The identity's mailbox, for messages; without it, calls only.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mailbox: Option<Mailbox>,
    /// Hints nodes (`https://host:port`): where this device publishes its hint and finds others'.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub hints_nodes: Vec<String>,
    /// Where the messaging state lives. Default: `<identity>/messaging`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub messaging_state: Option<PathBuf>,
    /// Fetch `did:web` documents to find those identities' mailboxes.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub fetch_did_web: bool,
    /// The publisher's push gateway (a `did:web`, W§2), for waking this device while it sleeps (A5d): a phone's app
    /// sets it; without it, never woken.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub push_gateway: Option<String>,
}

/// A mailbox: where it is and who it is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Mailbox {
    /// `wss://host:9443/dsip`.
    pub uri: String,
    /// Its DID (its `service.did`).
    pub did: String,
}

impl Settings {
    /// The [`Config`] these settings describe, the identity loaded from its directory.
    pub fn config(&self) -> Result<Config, Error> {
        let bad = |what: String| Error::Settings(what);
        let id = dsip_phone::Identity::load(&self.identity)?;
        let mut cfg = Config::new(id, &self.relay);
        cfg.tls = dsip_transport::tls::client_config(self.ca.as_deref())?;
        cfg.audio = match self.audio.as_deref().unwrap_or("system") {
            "system" => Some(HostKind::System),
            "tone" => Some(HostKind::Tone),
            "none" => None,
            other => return Err(bad(format!("audio {other}: system, tone or none"))),
        };
        cfg.audio_devices = (self.audio_input.clone(), self.audio_output.clone());
        cfg.stun = self.stun.clone();
        if !self.hints_nodes.is_empty() {
            let pem = match &self.ca {
                Some(p) => Some(std::fs::read(p).map_err(|e| bad(format!("{}: {e}", p.display())))?),
                None => None,
            };
            cfg.hints = Some(dsip_transport::hints::HintsClient::new(self.hints_nodes.clone(), pem.as_deref())?);
        }
        if let Some(g) = &self.push_gateway {
            let mut w = crate::WakeConfig::new(g);
            // a gateway under the settings' own CA (a test's, a private deployment's) is trusted as the relay is
            if let Some(p) = &self.ca {
                let pem = std::fs::read(p).map_err(|e| bad(format!("{}: {e}", p.display())))?;
                let docs = dsip_transport::resolver::DidWebResolver::new().with_ca(&pem)?;
                w.client = Some(dsip_transport::wake::WakeClient::new(std::sync::Arc::new(docs)).with_ca(&pem).map_err(|e| bad(e.to_string()))?);
            }
            cfg.wake = Some(w);
        }
        if let Some(m) = &self.mailbox {
            cfg.messaging = Some(MessagingConfig {
                mailbox: (m.did.clone(), m.uri.clone()),
                hints_nodes: self.hints_nodes.clone(),
                ca: self.ca.clone(),
                state_dir: self.messaging_state.clone().unwrap_or_else(|| self.identity.join("messaging")),
                fetch_did_web: self.fetch_did_web,
            });
        }
        Ok(cfg)
    }
}

/// Make an identity in `dir`: a controller key, a device key and the delegation between them (a `did:key`). Returns
/// its DID.
pub fn init_identity(dir: &std::path::Path, display_name: &str) -> Result<String, Error> {
    Ok(dsip_phone::Identity::init(dir, display_name, None, None)?.meta.identity)
}
