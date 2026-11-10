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
//! Only the identity key is in the code: the identity's DID is the key's (`did:key`), and a restored install makes its
//! own device key and delegation.
//!
//! The file holds a second line, `DSIPC1-` and base32 in groups of five: the names the user gave identities and the
//! identities followed ([`crate::NAMES_FILE`], [`crate::FOLLOWING_FILE`]) as they were when it was made, as JSON,
//! sealed with XChaCha20-Poly1305 under SHA-256("dsip backup contacts v1" ‖ the code's key), so one Argon2id opens
//! both; `DSIPC1` and the code's salt are its associated data, binding it to that code. 1 byte of version, 24 of
//! nonce, the sealed JSON. Restored from the file, they come back; from the code alone, only the identity does. The
//! same JSON holds the servers the device used ([`Connection`]: relay, mailbox, hints nodes, STUN), so an install
//! restored from the file starts with them, nothing typed ([`connection_in`]); a file made before they were kept has
//! none, and is read as before. Restoring makes that install the one holding the identity key, as the first device does
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
/// The contacts line's prefix (the file only).
const CONTACTS_PREFIX: &str = "DSIPC1-";
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
#[cfg(test)]
fn seal(seed: &[u8; 32], passphrase: &str) -> Result<String, Error> {
    seal_keyed(seed, passphrase).map(|(code, _)| code)
}

/// The key a code's passphrase makes, and its salt: what seals the contacts line beside it.
struct CodeKey {
    key: [u8; 32],
    salt: [u8; SALT],
}

/// `seed` sealed under `passphrase`, as a code, and the key that sealed it.
fn seal_keyed(seed: &[u8; 32], passphrase: &str) -> Result<(String, CodeKey), Error> {
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
    Ok((format!("{PREFIX}{}", grouped(&text)), CodeKey { key, salt }))
}

/// `text` in groups of five, between dashes.
fn grouped(text: &str) -> String {
    let groups: Vec<&str> = text.as_bytes().chunks(5).map(|c| std::str::from_utf8(c).expect("base32")).collect();
    groups.join("-")
}

/// The seed in `code`, opened with `passphrase`.
#[cfg(test)]
fn open(code: &str, passphrase: &str) -> Result<[u8; 32], Error> {
    open_keyed(code, passphrase).map(|(seed, _)| seed)
}

/// The seed in `code`, opened with `passphrase`, and the key that opened it.
fn open_keyed(code: &str, passphrase: &str) -> Result<([u8; 32], CodeKey), Error> {
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
    let seed = seed.try_into().map_err(|_| bad("the recovery code holds no key"))?;
    Ok((seed, CodeKey { key, salt: aad[1..].try_into().expect("the salt") }))
}

/// The names given identities, and the identities followed, and the servers used: what the file keeps beside the code.
#[derive(Debug, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct Contacts {
    #[serde(default)]
    names: std::collections::BTreeMap<String, String>,
    #[serde(default)]
    following: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    servers: Option<Connection>,
}

/// The servers a device used, kept in a backup file so a restored install starts with them: the part of its
/// [`Settings`](crate::Settings) that says where it connects, not what is the device's own (identity folder, sound).
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Connection {
    /// The relay.
    pub relay: String,
    /// The mailbox, if it had one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mailbox: Option<crate::Mailbox>,
    /// The hints nodes.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub hints_nodes: Vec<String>,
    /// The STUN servers.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stun: Vec<String>,
    /// The domain they were found at, if they were ([`crate::servers`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub server: Option<String>,
}

impl From<&crate::Settings> for Connection {
    fn from(s: &crate::Settings) -> Connection {
        Connection {
            relay: s.relay.clone(),
            mailbox: s.mailbox.clone(),
            hints_nodes: s.hints_nodes.clone(),
            stun: s.stun.clone(),
            server: s.server.clone(),
        }
    }
}

impl Contacts {
    /// Those kept in `dir` now.
    fn read(dir: &Path) -> Contacts {
        let json = |f: &str| std::fs::read(dir.join(f)).ok();
        Contacts {
            names: json(crate::NAMES_FILE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default(),
            following: json(crate::FOLLOWING_FILE).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default(),
            servers: None,
        }
    }

    /// Keep them in `dir`, where the app reads them at its start; a file there already is kept.
    fn write(&self, dir: &Path) -> Result<(), Error> {
        for (file, json) in [
            (crate::NAMES_FILE, (!self.names.is_empty()).then(|| serde_json::to_vec_pretty(&self.names))),
            (crate::FOLLOWING_FILE, (!self.following.is_empty()).then(|| serde_json::to_vec(&self.following))),
        ] {
            let path = dir.join(file);
            if let (Some(json), false) = (json, path.exists()) {
                std::fs::write(&path, json.map_err(|e| bad(e.to_string()))?).map_err(|e| bad(e.to_string()))?;
            }
        }
        Ok(())
    }
}

/// The key that seals the contacts line, from the code's.
fn contacts_key(k: &CodeKey) -> [u8; 32] {
    Sha256::digest([&b"dsip backup contacts v1"[..], &k.key].concat()).into()
}

fn contacts_aad(k: &CodeKey) -> Vec<u8> {
    [&b"DSIPC1"[..], &k.salt].concat()
}

/// `contacts` sealed beside the code `k` made, as the file's line; none when there are none.
fn seal_contacts(contacts: &Contacts, k: &CodeKey) -> Result<Option<String>, Error> {
    if contacts == &Contacts::default() {
        return Ok(None);
    }
    let mut nonce = [0u8; NONCE];
    getrandom::getrandom(&mut nonce).map_err(|e| bad(e.to_string()))?;
    let json = serde_json::to_vec(contacts).map_err(|e| bad(e.to_string()))?;
    let sealed = XChaCha20Poly1305::new((&contacts_key(k)).into())
        .encrypt(XNonce::from_slice(&nonce), Payload { msg: &json, aad: &contacts_aad(k) })
        .map_err(|_| bad("sealing the contacts"))?;
    let bytes = [&[VERSION][..], &nonce, &sealed].concat();
    Ok(Some(format!("{CONTACTS_PREFIX}{}", grouped(&data_encoding::BASE32_NOPAD.encode(&bytes)))))
}

/// The contacts in the file's line, opened with the code's key.
fn open_contacts(line: &str, k: &CodeKey) -> Result<Contacts, Error> {
    let text = normal(line);
    let text = text.strip_prefix(&CONTACTS_PREFIX[..CONTACTS_PREFIX.len() - 1]).ok_or_else(|| bad("no contacts line"))?;
    let bytes = data_encoding::BASE32_NOPAD.decode(text.as_bytes()).map_err(|_| bad("the contacts line is damaged"))?;
    if bytes.len() < 1 + NONCE || bytes[0] != VERSION {
        return Err(bad("the contacts line is damaged"));
    }
    let (nonce, sealed) = bytes[1..].split_at(NONCE);
    let json = XChaCha20Poly1305::new((&contacts_key(k)).into())
        .decrypt(XNonce::from_slice(nonce), Payload { msg: sealed, aad: &contacts_aad(k) })
        .map_err(|_| bad("the contacts line is damaged, or not this code's"))?;
    serde_json::from_slice(&json).map_err(|e| bad(e.to_string()))
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

/// The contacts line in a backup file's `text`, if it has one.
fn contacts_in(text: &str) -> Option<&str> {
    let prefix = &CONTACTS_PREFIX[..CONTACTS_PREFIX.len() - 1];
    text.lines().find(|l| normal(l).starts_with(prefix))
}

/// A backup of the identity in `dir`, its key sealed under `passphrase`; the file keeps `servers` too, when given.
pub fn export_identity(dir: &Path, passphrase: &str, servers: Option<&Connection>) -> Result<Backup, Error> {
    let id = crate::keys::load_identity(dir)?;
    // only a device holding the identity key backs it up; one that joined holds none (A6, pairing)
    let (code, key) = seal_keyed(&id.identity_key()?.seed(), passphrase)?;
    let identity = id.meta.identity.clone();
    let contacts = Contacts { servers: servers.filter(|c| !c.relay.is_empty()).cloned(), ..Contacts::read(dir) };
    let mut file = format!(
        "DSIP identity backup\n\
         Identity: {identity}\n\
         Name: {}\n\
         Restore it with this code and its passphrase. Anyone with both is this identity: keep it safe.\n\
         \n\
         {code}\n",
        id.meta.display_name
    );
    if let Some(line) = seal_contacts(&contacts, &key)? {
        file.push_str(&format!(
            "\nThe names you gave {} identities, and the {} you follow, as they are today{}, sealed under the same \
             passphrase.\n\
             Restoring from this file brings them back; the code alone does not.\n\
             \n\
             {line}\n",
            contacts.names.len(),
            contacts.following.len(),
            if contacts.servers.is_some() { ", and the servers this device uses" } else { "" },
        ));
    }
    Ok(Backup { identity, code, file })
}

/// Make the identity in `code` (or a backup file's text) this install's, in `dir`, under `display_name`: its key
/// opened with `passphrase`, a new device key, and the delegation between them; the keys moved into the platform's
/// store when this process uses one. Its DID.
pub fn restore_identity(dir: &Path, code: &str, passphrase: &str, display_name: &str) -> Result<String, Error> {
    let (seed, key) = open_keyed(code_in(code), passphrase)?;
    let controller = KeyPair::from_seed(seed);
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
    // the same key agreement key as the identity's other devices: derived from the identity key restored (A6c)
    crate::keys::ready_identity(dir);
    // the names and identities followed, when the file has them: the identity is restored whatever comes of these
    if let Some(line) = contacts_in(code) {
        match open_contacts(line, &key).and_then(|c| c.write(dir)) {
            Ok(()) => {}
            Err(e) => tracing::warn!("restoring the contacts: {e}"),
        }
    }
    Ok(did)
}

/// The servers kept in a backup file's `text`, opened with `passphrase`: none from a code alone, from a file made
/// before they were kept, or from a line that does not open (the identity is restored without them, as the contacts).
pub fn connection_in(text: &str, passphrase: &str) -> Result<Option<Connection>, Error> {
    let Some(line) = contacts_in(text) else { return Ok(None) };
    let (_, key) = open_keyed(code_in(text), passphrase)?;
    Ok(open_contacts(line, &key).ok().and_then(|c| c.servers))
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
        let backup = export_identity(&a, "correct horse battery", None).unwrap();
        assert_eq!(backup.identity, did);
        assert!(backup.code.starts_with("DSIP1-") && backup.file.contains(&backup.code) && backup.file.contains(&did));
        assert_eq!(backup.code.len(), PREFIX.len() + 146 + 29, "91 bytes: 146 base32 characters, in groups of five");

        // from the file's text, typed in lower case with spaces: the same identity, a new device
        let restored = restore_identity(&b, &backup.file.to_lowercase().replace('-', " - "), "correct horse battery", "Ann").unwrap();
        assert_eq!(restored, did);
        let (old, new) = (crate::keys::load_identity(&a).unwrap(), crate::keys::load_identity(&b).unwrap());
        assert_eq!(new.identity_key().unwrap().did(), old.identity_key().unwrap().did());
        assert_ne!(new.device.did(), old.device.did(), "its own device key");
        // the same key agreement key: what is sealed to the identity opens on both devices (A6c; core §7.3)
        let secret = |id: &dsip_phone::Identity| id.key_agreement.as_ref().map(|k| k.secret);
        assert!(secret(&old).is_some());
        assert_eq!(secret(&new), secret(&old));
        assert!(matches!(restore_identity(&b, &backup.code, "correct horse battery", "Ann"), Err(Error::Keys(m)) if m.contains("already")));
        for d in [a, b] {
            std::fs::remove_dir_all(d).unwrap();
        }
    }

    #[test]
    fn names_and_following_come_back_from_the_file_not_from_the_code() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (a, b, c, d) = (temp("ca"), temp("cb"), temp("cc"), temp("cd"));
        crate::init_identity(&a, "Ann").unwrap();
        let names = r#"{"did:web:priya.example": "Priya Patel", "did:key:z6MkBob": "Bob"}"#;
        std::fs::write(a.join(crate::NAMES_FILE), names).unwrap();
        std::fs::write(a.join(crate::FOLLOWING_FILE), r#"["did:web:priya.example"]"#).unwrap();
        let backup = export_identity(&a, "correct horse battery", None).unwrap();
        let line = contacts_in(&backup.file).expect("a contacts line");
        assert!(line.starts_with(CONTACTS_PREFIX) && !backup.code.contains("DSIPC1"), "in the file, not the code");
        assert!(!backup.file.contains("Priya"), "sealed");

        // from the file (typed in lower case, as the code may be): both come back
        restore_identity(&b, &backup.file.to_lowercase(), "correct horse battery", "Ann").unwrap();
        let read = Contacts::read(&b);
        assert_eq!(read.names.get("did:web:priya.example").map(String::as_str), Some("Priya Patel"));
        assert_eq!(read.names.len(), 2);
        assert_eq!(read.following, ["did:web:priya.example"]);

        // from the code alone: the identity, not them
        restore_identity(&c, &backup.code, "correct horse battery", "Ann").unwrap();
        assert_eq!(Contacts::read(&c), Contacts::default());

        // a damaged contacts line: the identity is restored all the same, without them
        let i = backup.file.find(line).unwrap() + line.len() - 3;
        let flip = if &backup.file[i..i + 1] == "A" { "B" } else { "A" };
        let damaged = format!("{}{flip}{}", &backup.file[..i], &backup.file[i + 1..]);
        restore_identity(&d, &damaged, "correct horse battery", "Ann").unwrap();
        assert_eq!(Contacts::read(&d), Contacts::default());

        // nothing to keep: no line
        let e = temp("ce");
        crate::init_identity(&e, "Eve").unwrap();
        assert!(contacts_in(&export_identity(&e, "correct horse battery", None).unwrap().file).is_none());
        for x in [a, b, c, d, e] {
            std::fs::remove_dir_all(x).unwrap();
        }
    }

    #[test]
    fn the_servers_come_back_from_the_file() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (a, b) = (temp("sa"), temp("sb"));
        crate::init_identity(&a, "Ann").unwrap();
        let servers = Connection {
            relay: "wss://relay.example.com:8443/dsip".into(),
            mailbox: Some(crate::Mailbox { uri: "wss://mailbox.example.com:9443/dsip".into(), did: "did:key:z6MkMb".into() }),
            hints_nodes: vec!["http://hints.example.com:8090".into()],
            stun: vec!["stun:stun.example.com:3478".into()],
            server: None,
        };
        // no names, no following: the line is there for the servers alone
        let backup = export_identity(&a, "correct horse battery", Some(&servers)).unwrap();
        assert!(backup.file.contains("the servers this device uses") && !backup.file.contains("relay.example.com"), "sealed");
        assert_eq!(connection_in(&backup.file, "correct horse battery").unwrap(), Some(servers.clone()));
        assert!(connection_in(&backup.file, "another passphrase").is_err());
        assert_eq!(connection_in(&backup.code, "correct horse battery").unwrap(), None, "the code alone holds none");
        restore_identity(&b, &backup.file, "correct horse battery", "Ann").unwrap();
        assert_eq!(Contacts::read(&b), Contacts::default(), "only names and following are written to the folder");

        // a file made before servers were kept (names only): none, and no error
        std::fs::write(a.join(crate::NAMES_FILE), r#"{"did:key:z6MkBob": "Bob"}"#).unwrap();
        let old = export_identity(&a, "correct horse battery", None).unwrap();
        assert_eq!(connection_in(&old.file, "correct horse battery").unwrap(), None);
        for x in [a, b] {
            std::fs::remove_dir_all(x).unwrap();
        }
    }

    #[test]
    fn a_contacts_line_opens_only_beside_its_own_code() {
        let (_, mine) = seal_keyed(&[1u8; 32], "a long passphrase").unwrap();
        let (_, other) = seal_keyed(&[1u8; 32], "a long passphrase").unwrap();
        let c = Contacts { names: [("did:key:z6MkBob".into(), "Bob".into())].into(), ..Contacts::default() };
        let line = seal_contacts(&c, &mine).unwrap().unwrap();
        assert_eq!(open_contacts(&line, &mine).unwrap(), c);
        // same passphrase, another code (another salt): refused
        assert!(open_contacts(&line, &other).is_err());
    }

    #[test]
    fn restored_contacts_do_not_replace_what_is_there() {
        let dir = temp("keep");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(crate::NAMES_FILE), r#"{"did:key:z6MkBob": "Robert"}"#).unwrap();
        Contacts {
            names: [("did:key:z6MkBob".into(), "Bob".into())].into(),
            following: vec!["did:key:z6MkBob".into()],
            servers: None,
        }
        .write(&dir)
            .unwrap();
        let read = Contacts::read(&dir);
        assert_eq!(read.names.get("did:key:z6MkBob").map(String::as_str), Some("Robert"));
        assert_eq!(read.following, ["did:key:z6MkBob"]);
        std::fs::remove_dir_all(dir).unwrap();
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
