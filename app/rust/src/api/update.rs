//! The app updating itself (app plan A4): Anvil's `anvil-update` (decision 4) with DSIP's description, releases and
//! key. Each release carries `latest.json` (its version, its page, each installer with its size and SHA-256) and
//! `latest.json.sig`, an Ed25519 signature over it made in the release workflow with the `DSIP_UPDATE_KEY` secret;
//! the manifest is accepted only under [`UPDATE_KEY`], the public half built in. Values cross as JSON, as the rest of
//! the bridge's do.

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use anvil_update::{App, Available, Install, Updater};

/// The app as the updater knows it: what each installer calls it, and where (`app/packaging`).
pub const DSIP: App = App { name: "DSIP", windows_dir: "DSIP", mac_bundle: "DSIP.app", deb_prefix: "/opt/dsip" };

/// Where the latest release's manifest is.
pub const FEED: &str = "https://github.com/thevoiceguy/dsip-app/releases/latest/download/";

/// The public key releases are signed with (Ed25519, raw): the same as `app/packaging/update-key.pub.pem`, which the
/// release workflow checks each signature against (a test holds them together). Its private half is the
/// repository's `DSIP_UPDATE_KEY` secret and an offline copy the owner keeps; lost, installed copies take no updates
/// until reinstalled by hand with a build carrying a new key.
pub const UPDATE_KEY: [u8; 32] = [
    0x9c, 0xe9, 0xf7, 0x96, 0xff, 0x4e, 0x6b, 0x42, 0x4d, 0x00, 0x75, 0x13, 0x2d, 0xd4, 0x2d, 0x5f, //
    0x5e, 0x80, 0x6c, 0xff, 0xed, 0x26, 0x61, 0xb4, 0x8d, 0xfd, 0x61, 0x0f, 0x18, 0xdf, 0xe0, 0xe4,
];

static AVAILABLE: Mutex<Option<Available>> = Mutex::new(None);
static DOWNLOADED: Mutex<Option<PathBuf>> = Mutex::new(None);

fn updater() -> anyhow::Result<&'static Updater> {
    static UPDATER: OnceLock<Updater> = OnceLock::new();
    if let Some(u) = UPDATER.get() {
        return Ok(u);
    }
    let u = Updater::with_app(DSIP, dsip_app::VERSION, FEED, &UPDATE_KEY, Install::detect(&DSIP))?;
    Ok(UPDATER.get_or_init(|| u))
}

/// This copy's version (the release's: the `dsip-app` crate's).
#[flutter_rust_bridge::frb(sync)]
pub fn app_version() -> String {
    dsip_app::VERSION.to_string()
}

/// The latest release when it is newer than this copy, as JSON: `{"version", "notes" (its page), "can_install",
/// "reason" (why not, when it cannot), "download" (the file to install by hand, when it cannot)}`; `null` when this
/// copy is the latest.
pub async fn check_for_update() -> anyhow::Result<String> {
    let updater = updater()?;
    let available = crate::api::app::runtime().spawn(async move { updater.check().await }).await??;
    let info = available.as_ref().map(|a| {
        let (reason, download) = match updater.install_kind() {
            Install::Manual { reason, target } => (
                Some(reason.clone()),
                target.and_then(|t| a.manifest.files.get(t)).map(|f| f.url.clone()).or_else(|| Some(a.manifest.notes.clone())),
            ),
            _ => (None, None),
        };
        serde_json::json!({
            "version": a.manifest.version,
            "notes": a.manifest.notes,
            "can_install": a.file.is_some(),
            "reason": reason,
            "download": download,
        })
    });
    *AVAILABLE.lock().unwrap_or_else(|e| e.into_inner()) = available;
    Ok(info.map(|i| i.to_string()).unwrap_or_else(|| "null".into()))
}

/// Fetch the release [`check_for_update`] found, checked against its manifest (size and SHA-256).
pub async fn download_update() -> anyhow::Result<()> {
    let updater = updater()?;
    let available = AVAILABLE.lock().unwrap_or_else(|e| e.into_inner()).clone().ok_or_else(|| anyhow::anyhow!("no update has been found"))?;
    let dir = std::env::temp_dir().join("dsip-update");
    let path = crate::api::app::runtime().spawn(async move { updater.download(&available, &dir).await }).await??;
    *DOWNLOADED.lock().unwrap_or_else(|e| e.into_inner()) = Some(path);
    Ok(())
}

/// Install the release fetched once this process has gone, and start the app again: the caller stops the app and
/// quits right after.
pub fn install_update() -> anyhow::Result<()> {
    let path = DOWNLOADED.lock().unwrap_or_else(|e| e.into_inner()).clone().ok_or_else(|| anyhow::anyhow!("no update has been fetched"))?;
    updater()?.install(&path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    /// The key built in is the one the release workflow checks signatures against.
    #[test]
    fn the_key_built_in_is_the_release_workflows() {
        let pem = include_str!("../../../packaging/update-key.pub.pem");
        let b64: String = pem.lines().filter(|l| !l.starts_with("-----")).collect();
        let der = base64(&b64);
        assert_eq!(der.len(), 44, "an Ed25519 SubjectPublicKeyInfo");
        assert_eq!(der[der.len() - 32..], super::UPDATE_KEY);
    }

    #[test]
    fn the_description_is_the_installers() {
        let iss = include_str!("../../../packaging/windows.iss");
        assert!(iss.contains(&format!(r"DefaultDirName={{localappdata}}\Programs\{}", super::DSIP.windows_dir)));
        let linux = include_str!("../../../packaging/linux.sh");
        assert!(linux.contains(&format!("\"$root{}/\"", super::DSIP.deb_prefix)), "the .deb installs elsewhere");
        let mac = include_str!("../../../packaging/macos.sh");
        assert!(mac.contains(super::DSIP.mac_bundle));
    }

    fn base64(text: &str) -> Vec<u8> {
        const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = Vec::new();
        let (mut acc, mut bits) = (0u32, 0);
        for c in text.bytes().filter(|&c| c != b'=') {
            let v = ALPHABET.iter().position(|&a| a == c).expect("base64") as u32;
            acc = (acc << 6) | v;
            bits += 6;
            if bits >= 8 {
                bits -= 8;
                out.push((acc >> bits) as u8);
            }
        }
        out
    }
}
