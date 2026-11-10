//! Where this device's keys are kept (app plan A6a): the identity key and the device key under the platform's
//! protection, not in files: the Keychain on macOS and iOS, the Android Keystore, Windows' Credential Manager, the
//! Secret Service on Linux. One item per install, named by the device's DID, holds both seeds; the identity folder
//! keeps what is public (`identity.json`, `delegation.json`).
//!
//! The store is chosen once per process ([`use_system_store`]: the app and the CLI do, at their start); a process
//! that chooses none (a test, a tool reading an identity folder) reads and writes files as before. An identity whose
//! keys are still in files is moved into the store by [`secure_identity`], read back from the store before the files
//! go. A Linux desktop with no Secret Service keeps the files, which its owner alone reads.
//!
//! On iOS the item is readable after the phone's first unlock, so a push wakes a locked phone (A5d), and stays on
//! this device: no backup or sync carries it (decision 5; A6d offers a synced copy).
//!
//! Spec: none (infrastructure). §7.3 names the keys; where a device keeps them is its own.

use std::path::Path;
use std::sync::Arc;

use dsip_core::envelope::Envelope;
use dsip_core::keys::KeyPair;
use dsip_transport::identity::IdentityMeta;
use serde::{Deserialize, Serialize};

use crate::Error;

/// The store's service name for this app's items.
pub const SERVICE: &str = "com.feryx.dsip";

/// The name items were kept under before the app's id was `com.feryx.dsip`: an item found only there is moved.
const OLD_SERVICE: &str = "com.thevoiceguy.dsip";

/// The files that hold the keys of an identity not (yet) in a store.
const KEY_FILES: [&str; 2] = ["controller.key", "device.key"];

/// The file dsip-rs keeps an identity's key agreement key in (its secret and the delegation naming it).
const KEY_AGREEMENT_FILE: &str = "key-agreement.json";

/// What an item holds: both seeds, hex; and the identity's key agreement key (§7.3, spec-gap 179), its secret hex and
/// the delegation naming it, when it has one.
#[derive(Serialize, Deserialize, PartialEq)]
struct Seeds {
    /// The identity key; none on a device that joined without it (A6, pairing).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    controller: Option<String>,
    device: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    key_agreement: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    key_agreement_delegation: Option<String>,
}

impl Seeds {
    fn of(id: &dsip_phone::Identity) -> Seeds {
        Seeds {
            controller: id.controller.as_ref().map(|c| hex(&c.seed())),
            device: hex(&id.device.seed()),
            key_agreement: id.key_agreement.as_ref().map(|k| hex(&k.secret)),
            key_agreement_delegation: id.key_agreement.as_ref().map(|k| k.delegation.frame()),
        }
    }
}

/// Use the platform's store from now on, in this process; `false` where there is none (a Linux desktop without a
/// Secret Service), and the keys stay in files. Called once, at the start; later calls change nothing.
pub fn use_system_store() -> bool {
    static CHOSEN: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *CHOSEN.get_or_init(|| match system_store() {
        Ok(store) => {
            keyring_core::set_default_store(store);
            true
        }
        Err(e) => {
            tracing::info!("keys: no system store ({e}); identity keys stay in files their owner alone reads");
            false
        }
    })
}

#[cfg(target_os = "macos")]
fn system_store() -> keyring_core::Result<Arc<keyring_core::CredentialStore>> {
    // The login keychain: the data protection keychain needs a signed app's entitlements (A4c).
    Ok(apple_native_keyring_store::keychain::Store::new()?)
}

#[cfg(target_os = "ios")]
fn system_store() -> keyring_core::Result<Arc<keyring_core::CredentialStore>> {
    Ok(apple_native_keyring_store::protected::Store::new()?)
}

#[cfg(windows)]
fn system_store() -> keyring_core::Result<Arc<keyring_core::CredentialStore>> {
    Ok(windows_native_keyring_store::Store::new()?)
}

#[cfg(target_os = "android")]
fn system_store() -> keyring_core::Result<Arc<keyring_core::CredentialStore>> {
    // The Keystore wraps a SharedPreferences file's values; ndk_context is set up by the app's JNI init.
    Ok(android_native_keyring_store::Store::new()?)
}

#[cfg(all(target_os = "linux", not(target_os = "android")))]
fn system_store() -> keyring_core::Result<Arc<keyring_core::CredentialStore>> {
    let store = zbus_secret_service_keyring_store::Store::new()?;
    // A session bus with no Secret Service answers only when asked: ask now.
    use keyring_core::api::CredentialStoreApi;
    match store.build(SERVICE, "probe", None)?.get_secret() {
        Ok(_) | Err(keyring_core::Error::NoEntry) => Ok(store),
        Err(e) => Err(e),
    }
}

/// The item for the install whose device is `device`.
fn entry(device: &str) -> keyring_core::Result<keyring_core::Entry> {
    entry_in(SERVICE, device)
}

fn entry_in(service: &str, device: &str) -> keyring_core::Result<keyring_core::Entry> {
    // iOS: readable once the phone has been unlocked since it started (a push may wake it locked), this device only.
    if cfg!(target_os = "ios") {
        let mods: std::collections::HashMap<&str, &str> = [("access-policy", "after-first-unlock-this-device-only")].into();
        return keyring_core::Entry::new_with_modifiers(service, device, &mods);
    }
    keyring_core::Entry::new(service, device)
}

/// The secret of `device`'s item; one kept under the old name ([`OLD_SERVICE`]) is moved to [`SERVICE`] first:
/// written, read back, then the old one deleted.
fn secret_of(device: &str) -> keyring_core::Result<Vec<u8>> {
    match entry(device)?.get_secret() {
        Err(keyring_core::Error::NoEntry) => {}
        found => return found,
    }
    let old = entry_in(OLD_SERVICE, device)?;
    let secret = old.get_secret()?;
    let new = entry(device)?;
    new.set_secret(&secret)?;
    if new.get_secret()? == secret {
        let _ = old.delete_credential();
        tracing::info!("keys: {device} moved from {OLD_SERVICE} to {SERVICE}");
    }
    Ok(secret)
}

fn store_error(e: keyring_core::Error) -> Error {
    Error::Keys(e.to_string())
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn unhex(s: &str) -> Option<[u8; 32]> {
    let s = s.trim();
    let bytes: Option<Vec<u8>> = (0..s.len()).step_by(2).map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok()).collect();
    bytes?.try_into().ok()
}

fn read(dir: &Path, name: &str) -> Result<String, Error> {
    std::fs::read_to_string(dir.join(name)).map_err(|e| Error::Keys(format!("{}: {e}", dir.join(name).display())))
}

/// Whether the identity in `dir` still keeps its keys in files.
fn in_files(dir: &Path) -> bool {
    KEY_FILES.iter().any(|f| dir.join(f).exists())
}

/// The identity in `dir`: its keys from the files there, or from the store.
pub fn load_identity(dir: &Path) -> Result<dsip_phone::Identity, Error> {
    if in_files(dir) || keyring_core::get_default_store().is_none() {
        return Ok(dsip_phone::Identity::load(dir)?);
    }
    let meta: IdentityMeta = serde_json::from_str(&read(dir, "identity.json")?).map_err(|e| Error::Keys(format!("identity.json: {e}")))?;
    let delegation = Envelope::from_frame(&read(dir, "delegation.json")?).map_err(|e| Error::Keys(format!("delegation.json: {e:?}")))?;
    let secret = secret_of(&meta.device).map_err(|e| match e {
        keyring_core::Error::NoEntry => Error::Keys(format!("the keys of {} are not in this device's store", meta.device)),
        e => store_error(e),
    })?;
    let seeds: Seeds = serde_json::from_slice(&secret).map_err(|e| Error::Keys(format!("the stored keys: {e}")))?;
    let key = |s: &str| unhex(s).map(KeyPair::from_seed).ok_or_else(|| Error::Keys("the stored keys are not keys".into()));
    let controller = seeds.controller.as_deref().map(key).transpose()?;
    let device = key(&seeds.device)?;
    if device.did() != meta.device {
        return Err(Error::Keys(format!("the stored device key is not {}'s", meta.device)));
    }
    let key_agreement = match (&seeds.key_agreement, &seeds.key_agreement_delegation) {
        (Some(secret), Some(frame)) => Some(dsip_transport::identity::KeyAgreement {
            secret: unhex(secret).ok_or_else(|| Error::Keys("the stored key agreement key is not a key".into()))?,
            delegation: Envelope::from_frame(frame).map_err(|e| Error::Keys(format!("the stored key agreement delegation: {e:?}")))?,
        }),
        _ => None,
    };
    Ok(dsip_phone::Identity { dir: dir.to_path_buf(), controller, device, delegation, meta, key_agreement })
}

/// The key files readable by their owner alone (Unix; dsip-rs writes them under the umask).
fn restrict_files(dir: &Path) -> Result<(), Error> {
    #[cfg(unix)]
    for f in KEY_FILES {
        use std::os::unix::fs::PermissionsExt;
        let path = dir.join(f);
        if path.exists() {
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).map_err(|e| Error::Keys(format!("{f}: {e}")))?;
        }
    }
    #[cfg(not(unix))]
    let _ = dir;
    Ok(())
}

/// Move the keys of the identity in `dir` from its files into the store: written, read back, then the files removed.
/// Whether they are in the store now (`false`: no store in this process, and the files stay, their owner's alone).
pub fn secure_identity(dir: &Path) -> Result<bool, Error> {
    if keyring_core::get_default_store().is_none() {
        restrict_files(dir)?;
        return Ok(false);
    }
    if !in_files(dir) {
        // moved already: they must be there
        load_identity(dir)?;
        return Ok(true);
    }
    let id = dsip_phone::Identity::load(dir)?;
    store(&id)?;
    for f in KEY_FILES.iter().chain([&KEY_AGREEMENT_FILE]) {
        match std::fs::remove_file(dir.join(f)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(Error::Keys(format!("{f}: {e}"))),
            _ => {}
        }
    }
    tracing::info!("keys: {} moved into the system store", id.meta.device);
    Ok(true)
}

/// Write `id`'s keys to its item, and read them back.
fn store(id: &dsip_phone::Identity) -> Result<(), Error> {
    let seeds = Seeds::of(id);
    let item = entry(&id.meta.device).map_err(store_error)?;
    item.set_secret(&serde_json::to_vec(&seeds).expect("JSON")).map_err(store_error)?;
    let back: Seeds = item.get_secret().ok().and_then(|s| serde_json::from_slice(&s).ok()).ok_or_else(|| Error::Keys("the store did not give the keys back".into()))?;
    if back != seeds {
        return Err(Error::Keys("the store gave other keys back".into()));
    }
    Ok(())
}

/// After dsip-rs changed the identity in `dir` (`id`: a key agreement key issued, a move to `did:web`), keep its keys
/// where they are: where they are in the store, the store's item is written again and the key agreement file dsip-rs
/// wrote goes; where they are in files, those stay, their owner's alone.
pub(crate) fn keep(dir: &Path, id: &dsip_phone::Identity) -> Result<(), Error> {
    if !in_files(dir) && keyring_core::get_default_store().is_some() {
        store(id)?;
        match std::fs::remove_file(dir.join(KEY_AGREEMENT_FILE)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(Error::Keys(format!("{KEY_AGREEMENT_FILE}: {e}"))),
            _ => {}
        }
    }
    Ok(())
}

/// Give the identity in `dir` a key agreement key, when it has none (A6c; core §7.3, spec-gap 179): the first secret
/// derived from its identity key, so every device holding that key holds the same one, and the identity's delegation
/// naming it. What is sealed to the identity then opens with it, and its hint carries the delegation. Kept where the
/// identity's keys are: the store, or `key-agreement.json`, its owner's alone. Whether one was issued.
pub fn ensure_key_agreement(dir: &Path) -> Result<bool, Error> {
    let mut id = load_identity(dir)?;
    if id.key_agreement.is_some() {
        return Ok(false);
    }
    let secret = id.derived_key_agreement_secret(0)?;
    id.issue_key_agreement(secret, dsip_transport::now_s())?;
    keep(dir, &id)?;
    tracing::info!("keys: {} has a key agreement key", id.meta.identity);
    Ok(true)
}

/// [`secure_identity`], and where the store refuses (a build without the entitlements a keychain wants, a store that
/// fails), the keys left in their files, their owner's alone, and the reason logged.
pub fn secure_or_keep(dir: &Path) {
    if let Err(e) = secure_identity(dir) {
        tracing::warn!("keys: the identity's keys stay in files: {e}");
        if let Err(e) = restrict_files(dir) {
            tracing::warn!("keys: {e}");
        }
    }
}

/// What every start, and every identity made or restored here, goes through: the keys moved into the store
/// ([`secure_or_keep`]), and a key agreement key issued when there is none ([`ensure_key_agreement`]; its failure is
/// logged, and what is sealed to the identity keeps opening with the derived key).
pub fn ready_identity(dir: &Path) {
    secure_or_keep(dir);
    if let Err(e) = ensure_key_agreement(dir) {
        tracing::warn!("keys: no key agreement key for {}: {e}", dir.display());
    }
}

/// Forget the stored keys of the install whose device is `device` (its identity removed from this device).
pub fn forget_keys(device: &str) -> Result<(), Error> {
    if keyring_core::get_default_store().is_none() {
        return Ok(());
    }
    match entry(device).and_then(|e| e.delete_credential()) {
        Ok(()) | Err(keyring_core::Error::NoEntry) => Ok(()),
        Err(e) => Err(store_error(e)),
    }
}

/// Tests that touch keyring's process-wide default store, or make identities while another may: one at a time.
#[cfg(test)]
pub(crate) static STORE_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_move_into_the_store_and_load_from_it() {
        let _one = STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = std::env::temp_dir().join(format!("dsip-app-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let made = dsip_phone::Identity::init(&dir, "Ann", None, None).unwrap();
        // no store chosen: files, as before, their owner's alone; a key agreement key issued beside them
        assert!(!secure_identity(&dir).unwrap());
        assert!(ensure_key_agreement(&dir).unwrap());
        assert!(!ensure_key_agreement(&dir).unwrap(), "once");
        let ka = load_identity(&dir).unwrap().key_agreement.expect("issued");
        assert_eq!(ka.secret, made_with(&dir).derived_key_agreement_secret(0).unwrap());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(std::fs::metadata(dir.join("controller.key")).unwrap().permissions().mode() & 0o777, 0o600);
        }
        assert_eq!(load_identity(&dir).unwrap().device.did(), made.device.did());

        keyring_core::set_default_store(keyring_core::mock::Store::new().unwrap());
        assert!(secure_identity(&dir).unwrap());
        assert!(!dir.join("controller.key").exists() && !dir.join("device.key").exists(), "the files are gone");
        let loaded = load_identity(&dir).unwrap();
        assert_eq!((loaded.identity_key().unwrap().did(), loaded.device.did()), (made.identity_key().unwrap().did(), made.device.did()));
        assert_eq!(loaded.delegation.frame(), made.delegation.frame());
        assert!(!dir.join(KEY_AGREEMENT_FILE).exists(), "the key agreement key moved too");
        assert_eq!(loaded.key_agreement.map(|k| (k.secret, k.delegation.frame())), Some((ka.secret, ka.delegation.frame())));
        assert!(secure_identity(&dir).unwrap(), "moved already");

        // an item kept under the app's old id: found there, moved to the new name, the old one gone
        let device = made.device.did();
        let secret = entry(&device).unwrap().get_secret().unwrap();
        entry(&device).unwrap().delete_credential().unwrap();
        entry_in(OLD_SERVICE, &device).unwrap().set_secret(&secret).unwrap();
        assert_eq!(load_identity(&dir).unwrap().device.did(), device);
        assert_eq!(entry(&device).unwrap().get_secret().unwrap(), secret);
        assert!(matches!(entry_in(OLD_SERVICE, &device).unwrap().get_secret(), Err(keyring_core::Error::NoEntry)));

        forget_keys(&made.device.did()).unwrap();
        assert!(matches!(load_identity(&dir), Err(Error::Keys(m)) if m.contains("not in this device's store")));
        keyring_core::unset_default_store();
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// The identity in `dir` as its files hold it (for the secret it derives).
    fn made_with(dir: &Path) -> dsip_phone::Identity {
        dsip_phone::Identity::load(dir).unwrap()
    }

    #[test]
    fn hex_round_trips() {
        let seed = [7u8; 32];
        assert_eq!(unhex(&hex(&seed)), Some(seed));
        assert_eq!(unhex("zz"), None);
    }
}
