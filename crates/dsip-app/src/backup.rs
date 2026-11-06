//! A backup of the identity a person can keep (app plan A6b, decision 5 (a)): the identity key sealed under a
//! passphrase, as a recovery code to print or a small text file holding it; and a new install restored from it.
//!
//! The code is `DSIP1-` and base32 in groups of five, of 91 bytes:
//!
//! | bytes | what |
//! |---|---|
//! | 1 | the version, 1 |
//! | 16 | the salt |
//! | 24 | the nonce |
//! | 48 | the identity key's seed, sealed with XChaCha20-Poly1305 under a key Argon2id makes from the passphrase (64 MiB, 3 passes); the version and salt are its associated data |
//! | 2 | the first two bytes of the SHA-256 of what comes before, so a mistyped code is told apart from a wrong passphrase before the slow KDF |
//!
//! Only the identity key is in it: the identity's DID is the key's (`did:key`), and a restored install makes its own
//! device key and delegation. Restoring makes that install the one holding the identity key, as the first device does
//! (decision 5 (a)); adding a device that holds only its own key is A6c.
//!
//! Spec: none (infrastructure). §7.3–§7.4 name the keys and the delegation a restored install signs.

use std::path::Path;

use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use dsip_core::keys::KeyPair;
use sha2::{Digest, Sha256};

use crate::Error;

/// The code's prefix and version.
const PREFIX: &str = "DSIP1-";
const VERSION: u8 = 1;
const SALT: usize = 16;
const NONCE: usize = 24;
const SEALED: usize = 32 + 16;
const BODY: usize = 1 + SALT + NONCE + SEALED;
const LEN: usize = BODY + 2;

/// The shortest passphrase taken: the code is only as strong as it.
pub const MIN_PASSPHRASE: usize = 10;

/// A backup: the recovery code, and the text of a file that holds it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Backup {
    /// The identity it is of.
    pub identity: String,
    /// `DSIP1-XXXXX-…`.
    pub code: String,
    /// A few lines saying what it is, and the code.
    pub file: String,
}

fn bad(why: impl Into<String>) -> Error {
    Error::Keys(why.into())
}

fn key_from(passphrase: &str, salt: &[u8]) -> Result<[u8; 32], Error> {
    let params = Params::new(64 * 1024, 3, 1, Some(32)).map_err(|e| bad(e.to_string()))?;
    let mut key = [0u8; 32];
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(passphrase.as_bytes(), salt, &mut key)
        .map_err(|e| bad(e.to_string()))?;
    Ok(key)
}

fn checksum(body: &[u8]) -> [u8; 2] {
    let d = Sha256::digest(body);
    [d[0], d[1]]
}

/// `seed` sealed under `passphrase`, as a code.
fn seal(seed: &[u8; 32], passphrase: &str) -> Result<String, Error> {
    if passphrase.chars().count() < MIN_PASSPHRASE {
        return Err(bad(format!("the passphrase needs at least {MIN_PASSPHRASE} characters")));
    }
    let mut salt = [0u8; SALT];
    let mut nonce = [0u8; NONCE];
    getrandom::getrandom(&mut salt).and_then(|_| getrandom::getrandom(&mut nonce)).map_err(|e| bad(e.to_string()))?;
    let key = key_from(passphrase, &salt)?;
    let aad = [&[VERSION][..], &salt].concat();
    let sealed = XChaCha20Poly1305::new((&key).into())
        .encrypt(XNonce::from_slice(&nonce), Payload { msg: seed, aad: &aad })
        .map_err(|_| bad("sealing the backup"))?;
    let mut bytes = [aad, nonce.to_vec(), sealed].concat();
    let sum = checksum(&bytes);
    bytes.extend_from_slice(&sum);
    let text = data_encoding::BASE32_NOPAD.encode(&bytes);
    let groups: Vec<&str> = text.as_bytes().chunks(5).map(|c| std::str::from_utf8(c).expect("base32")).collect();
    Ok(format!("{PREFIX}{}", groups.join("-")))
}

/// The seed in `code`, opened with `passphrase`.
fn open(code: &str, passphrase: &str) -> Result<[u8; 32], Error> {
    let text = normal(code);
    let text = text.strip_prefix(&PREFIX[..PREFIX.len() - 1]).ok_or_else(|| bad("not a DSIP recovery code (it starts DSIP1-)"))?;
    let bytes = data_encoding::BASE32_NOPAD.decode(text.as_bytes()).map_err(|_| bad("the recovery code has a character that is not in it"))?;
    if bytes.len() != LEN || bytes[0] != VERSION || checksum(&bytes[..BODY]) != bytes[BODY..] {
        return Err(bad("the recovery code is mistyped or incomplete"));
    }
    let (aad, rest) = bytes[..BODY].split_at(1 + SALT);
    let (nonce, sealed) = rest.split_at(NONCE);
    let key = key_from(passphrase, &aad[1..])?;
    let seed = XChaCha20Poly1305::new((&key).into())
        .decrypt(XNonce::from_slice(nonce), Payload { msg: sealed, aad })
        .map_err(|_| bad("the passphrase does not open this recovery code"))?;
    seed.try_into().map_err(|_| bad("the recovery code holds no key"))
}

/// `code` as typed, in capitals, without the spaces and dashes between groups.
fn normal(code: &str) -> String {
    code.to_ascii_uppercase().chars().filter(|c| !c.is_whitespace() && *c != '-').collect()
}

/// The code found in `text`: the code itself, or a backup file holding it among other lines.
fn code_in(text: &str) -> &str {
    let prefix = &PREFIX[..PREFIX.len() - 1];
    text.lines().find(|l| normal(l).starts_with(prefix)).unwrap_or(text)
}

/// A backup of the identity in `dir`, its key sealed under `passphrase`.
pub fn export_identity(dir: &Path, passphrase: &str) -> Result<Backup, Error> {
    let id = crate::keys::load_identity(dir)?;
    let code = seal(&id.controller.seed(), passphrase)?;
    let identity = id.meta.identity.clone();
    let file = format!(
        "DSIP identity backup\n\
         Identity: {identity}\n\
         Name: {}\n\
         Restore it with this code and its passphrase. Anyone with both is this identity: keep it safe.\n\
         \n\
         {code}\n",
        id.meta.display_name
    );
    Ok(Backup { identity, code, file })
}

/// Make the identity in `code` (or a backup file's text) this install's, in `dir`, under `display_name`: its key
/// opened with `passphrase`, a new device key, and the delegation between them; the keys moved into the platform's
/// store when this process uses one. Its DID.
pub fn restore_identity(dir: &Path, code: &str, passphrase: &str, display_name: &str) -> Result<String, Error> {
    let controller = KeyPair::from_seed(open(code_in(code), passphrase)?);
    if dir.join("identity.json").exists() {
        return Err(bad(format!("{} holds an identity already", dir.display())));
    }
    let src = dir.with_extension("restoring");
    let _ = std::fs::remove_dir_all(&src);
    // dsip-phone makes a second device of the identity in a folder: here, one holding only its key
    let seed_only = src.join("identity");
    let made = (|| -> Result<String, Error> {
        dsip_phone::Identity::init(&seed_only, display_name, None, None)?;
        std::fs::write(seed_only.join("controller.key"), hex(&controller.seed())).map_err(|e| bad(e.to_string()))?;
        let id = dsip_phone::Identity::init(dir, display_name, None, Some(&seed_only))?;
        Ok(id.meta.identity)
    })();
    let _ = std::fs::remove_dir_all(&src);
    let did = made?;
    if did != controller.did() {
        return Err(bad("the restored identity is not the code's"));
    }
    crate::keys::secure_or_keep(dir);
    Ok(did)
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("dsip-app-backup-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn an_identity_is_restored_from_its_code_on_a_new_install() {
        // the keys test sets a process-wide store: not while this one makes and loads identities
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (a, b) = (temp("a"), temp("b"));
        let did = crate::init_identity(&a, "Ann").unwrap();
        let backup = export_identity(&a, "correct horse battery").unwrap();
        assert_eq!(backup.identity, did);
        assert!(backup.code.starts_with("DSIP1-") && backup.file.contains(&backup.code) && backup.file.contains(&did));
        assert_eq!(backup.code.len(), PREFIX.len() + 146 + 29, "91 bytes: 146 base32 characters, in groups of five");

        // from the file's text, typed in lower case with spaces: the same identity, a new device
        let restored = restore_identity(&b, &backup.file.to_lowercase().replace('-', " - "), "correct horse battery", "Ann").unwrap();
        assert_eq!(restored, did);
        let (old, new) = (crate::keys::load_identity(&a).unwrap(), crate::keys::load_identity(&b).unwrap());
        assert_eq!(new.controller.did(), old.controller.did());
        assert_ne!(new.device.did(), old.device.did(), "its own device key");
        assert!(matches!(restore_identity(&b, &backup.code, "correct horse battery", "Ann"), Err(Error::Keys(m)) if m.contains("already")));
        for d in [a, b] {
            std::fs::remove_dir_all(d).unwrap();
        }
    }

    #[test]
    fn a_wrong_passphrase_and_a_mistyped_code_are_told_apart() {
        let code = seal(&[9u8; 32], "a long passphrase").unwrap();
        assert_eq!(open(&code, "a long passphrase").unwrap(), [9u8; 32]);
        assert!(matches!(open(&code, "another passphrase"), Err(Error::Keys(m)) if m.contains("does not open")));
        // one character changed: the checksum says so, before the KDF
        let i = code.len() - 3;
        let other = if &code[i..i + 1] == "A" { "B" } else { "A" };
        let typo = format!("{}{other}{}", &code[..i], &code[i + 1..]);
        assert!(matches!(open(&typo, "a long passphrase"), Err(Error::Keys(m)) if m.contains("mistyped")));
        assert!(matches!(open("hello", "a long passphrase"), Err(Error::Keys(m)) if m.contains("not a DSIP")));
        assert!(matches!(seal(&[9u8; 32], "short"), Err(Error::Keys(m)) if m.contains("at least")));
    }
}
