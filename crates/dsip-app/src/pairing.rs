//! Another device of an identity, without the identity key (app plan A6, decision 5 (a)): the new device holds its own
//! key, the identity's delegation of it (§7.4), and the identity's key agreement key (§7.3), and nothing that signs as
//! the identity. Two codes carry them between the devices, by hand (typed, pasted, or a QR), with nothing on the
//! network:
//!
//! 1. [`start`], on the new device: its device key and a one-time X25519 key, kept in `pairing.json` until it is
//!    done, and a **join code**, `DSIPJ1-` and base32 of the device's public key, the one-time public key and a
//!    checksum, short enough to type.
//! 2. [`welcome`], on a device holding the identity key: the identity's delegation of that device, and the key
//!    agreement secret sealed to the one-time key (HPKE, as M§6.9's suite), as a **welcome code**, `DSIPW1-` and
//!    base64url of a small JSON object.
//! 3. [`finish`], on the new device: the secret opened, the delegation checked, and the device joined
//!    (`Identity::join`), its keys moved into the store.
//!
//! [`check_code`] is the same on both screens: the new device's key, shortened, for the person to compare, so a join
//! code swapped on its way is seen.
//!
//! Spec: none (infrastructure). §7.3–§7.4 say what the device ends holding; how it receives it is the identity's own.

use std::path::Path;

use dsip_core::envelope::Envelope;
use dsip_core::keys::KeyPair;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::Error;

const JOIN: &str = "DSIPJ1";
const WELCOME: &str = "DSIPW1-";
const INFO: &[u8] = b"dsip pairing v1";
const PENDING: &str = "pairing.json";

fn bad(why: impl Into<String>) -> Error {
    Error::Keys(why.into())
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn unhex(s: &str) -> Option<[u8; 32]> {
    let bytes: Option<Vec<u8>> = (0..s.len()).step_by(2).map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok()).collect();
    bytes?.try_into().ok()
}

fn checksum(body: &[u8]) -> [u8; 2] {
    use sha2::Digest;
    let d = sha2::Sha256::digest(body);
    [d[0], d[1]]
}

/// What the new device keeps until it is done: its device key and its one-time X25519 key.
#[derive(Serialize, Deserialize)]
struct Pending {
    device: String,
    once: String,
}

/// A code as typed, in capitals, without the spaces and dashes between groups.
fn normal(code: &str) -> String {
    code.to_ascii_uppercase().chars().filter(|c| !c.is_whitespace() && *c != '-').collect()
}

/// The device's key, shortened for the person to compare on both screens: its `did:key`'s last eight characters.
pub fn check_code(device_did: &str) -> String {
    let tail: String = device_did.chars().rev().take(8).collect::<Vec<_>>().into_iter().rev().collect();
    format!("{}-{}", &tail[..4], &tail[4..])
}

/// The new device's first step: its device key and a one-time key, kept in `dir` (the identity folder it will join
/// into, which must not hold an identity yet), and the join code to give the other device. Its check code too.
pub fn start(dir: &Path) -> Result<(String, String), Error> {
    if dir.join("identity.json").exists() {
        return Err(bad(format!("{} holds an identity already", dir.display())));
    }
    std::fs::create_dir_all(dir).map_err(|e| bad(format!("{}: {e}", dir.display())))?;
    let (device, once) = (KeyPair::generate(), KeyPair::generate().seed());
    let pending = Pending { device: hex(&device.seed()), once: hex(&once) };
    let path = dir.join(PENDING);
    std::fs::write(&path, serde_json::to_vec(&pending).expect("JSON")).map_err(|e| bad(format!("{PENDING}: {e}")))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).map_err(|e| bad(format!("{PENDING}: {e}")))?;
    }
    let body = [&[1u8][..], &device.public(), &dsip_core::hpke::x25519_public(&once)].concat();
    let mut bytes = body.clone();
    bytes.extend_from_slice(&checksum(&body));
    let text = data_encoding::BASE32_NOPAD.encode(&bytes);
    let groups: Vec<&str> = text.as_bytes().chunks(5).map(|c| std::str::from_utf8(c).expect("base32")).collect();
    Ok((format!("{JOIN}-{}", groups.join("-")), check_code(&device.did())))
}

/// The device and the one-time key a join code names.
fn read_join(code: &str) -> Result<(String, [u8; 32]), Error> {
    let text = normal(code);
    let text = text.strip_prefix(JOIN).ok_or_else(|| bad("not a join code (it starts DSIPJ1-)"))?;
    let bytes = data_encoding::BASE32_NOPAD.decode(text.as_bytes()).map_err(|_| bad("the join code has a character that is not in it"))?;
    if bytes.len() != 67 || bytes[0] != 1 || checksum(&bytes[..65]) != bytes[65..] {
        return Err(bad("the join code is mistyped or incomplete"));
    }
    let device: [u8; 32] = bytes[1..33].try_into().expect("32");
    let once: [u8; 32] = bytes[33..65].try_into().expect("32");
    Ok((dsip_core::did::did_key_from_public(&device), once))
}

/// The other device's step, on one holding the identity key (the identity in `dir`): the identity's delegation of
/// the device `join_code` names, and the key agreement secret sealed to it, as the welcome code. The device's check
/// code too, to compare with the one the new device shows.
pub fn welcome(dir: &Path, join_code: &str) -> Result<(String, String), Error> {
    let (device, once) = read_join(join_code)?;
    crate::keys::ensure_key_agreement(dir)?;
    let id = crate::keys::load_identity(dir)?;
    let ka = id.key_agreement.as_ref().ok_or_else(|| bad("no key agreement key to hand over"))?;
    let delegation = id.delegate_device(&device, dsip_transport::now_s())?;
    let mut sk_e = [0u8; 32];
    getrandom::getrandom(&mut sk_e).map_err(|e| bad(e.to_string()))?;
    let (enc, ct) = dsip_core::hpke::hpke_seal(&once, INFO, device.as_bytes(), &ka.secret, &sk_e);
    let w = json!({
        "identity": id.meta.identity,
        "name": id.meta.display_name,
        "delegation": delegation.frame(),
        "key_agreement": ka.delegation.frame(),
        "enc": dsip_core::b64::encode(&enc),
        "ct": dsip_core::b64::encode(&ct),
    });
    Ok((format!("{WELCOME}{}", dsip_core::b64::encode(w.to_string().as_bytes())), check_code(&device)))
}

/// The new device's last step: the welcome code read, the key agreement secret opened with its one-time key, the
/// delegation and the key agreement delegation checked against it, and the device joined in `dir`. The identity's DID.
pub fn finish(dir: &Path, welcome_code: &str) -> Result<String, Error> {
    let pending: Pending = std::fs::read(dir.join(PENDING))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .ok_or_else(|| bad("this device has not started joining (no join code was made here)"))?;
    let (device, once) = match (unhex(&pending.device), unhex(&pending.once)) {
        (Some(d), Some(o)) => (KeyPair::from_seed(d), o),
        _ => return Err(bad(format!("{PENDING} is damaged: start again"))),
    };
    let text = welcome_code.trim();
    let text = text.strip_prefix(WELCOME).ok_or_else(|| bad("not a welcome code (it starts DSIPW1-)"))?;
    let w: Value = dsip_core::b64::decode(text)
        .and_then(|b| serde_json::from_slice(&b).ok())
        .ok_or_else(|| bad("the welcome code is incomplete"))?;
    let s = |k: &str| w[k].as_str().unwrap_or_default().to_string();
    let bytes = |k: &str| dsip_core::b64::decode(&s(k)).unwrap_or_default();
    let secret: [u8; 32] = dsip_core::hpke::hpke_open(&bytes("enc"), &once, INFO, device.did().as_bytes(), &bytes("ct"))
        .and_then(|pt| pt.try_into().ok())
        .ok_or_else(|| bad("the welcome code is not for this device"))?;
    let identity = s("identity");
    let delegation = Envelope::from_frame(&s("delegation")).map_err(|e| bad(format!("the delegation: {e:?}")))?;
    let ka_delegation = Envelope::from_frame(&s("key_agreement")).map_err(|e| bad(format!("the key agreement delegation: {e:?}")))?;
    // Both are the identity's (§7.3, §7.4). A did:key identity's verify here, by their signatures; a did:web identity's
    // need its document, which relays and peers fetch: here their fields are checked, and the signatures where they
    // are used.
    let payload = |e: &Envelope| -> Value { dsip_core::b64::decode(&e.payload).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default() };
    let ka_payload = payload(&ka_delegation);
    if ka_payload["subject"] != identity.as_str()
        || ka_payload["key"] != dsip_core::did::multibase_x25519(&dsip_core::hpke::x25519_public(&secret)).as_str()
    {
        return Err(bad("the key agreement key handed over is not the one the identity's delegation names"));
    }
    if identity.starts_with("did:key:") {
        let resolver = dsip_core::did::StaticResolver::default();
        let ctx = dsip_core::envelope::Context::new(dsip_transport::now_s(), &resolver);
        let ka_value: Value = serde_json::from_str(&ka_delegation.frame()).expect("a frame is JSON");
        dsip_schema::key_agreement::verify(&ka_value, &ctx, Some(&identity))
            .map_err(|why| bad(format!("the key agreement delegation does not verify: {why}")))?;
        let ver = dsip_core::envelope::verify_raw(&delegation, &ctx, false).map_err(|_| bad("the delegation does not verify"))?;
        if ver.signer_did != identity {
            return Err(bad("the delegation is not the identity's"));
        }
    }
    let ka = dsip_transport::identity::KeyAgreement { secret, delegation: ka_delegation };
    let id = dsip_phone::Identity::join(dir, &identity, &s("name"), device, delegation, ka)?;
    let _ = std::fs::remove_file(dir.join(PENDING));
    crate::keys::ready_identity(dir);
    Ok(id.meta.identity)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_second_device_joins_by_two_codes_and_holds_no_identity_key() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let base = std::env::temp_dir().join(format!("dsip-app-pairing-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let (first, second) = (base.join("first"), base.join("second"));
        let did = crate::init_identity(&first, "Ann").unwrap();

        // the new device: a join code, typed on the first in lower case with spaces
        let (join, check) = start(&second).unwrap();
        assert!(join.starts_with("DSIPJ1-") && join.len() <= 136, "67 bytes: {join}");
        let (welcome_code, check_there) = welcome(&first, &join.to_lowercase().replace('-', " ")).unwrap();
        assert_eq!(check_there, check, "the same check code on both screens");

        assert_eq!(finish(&second, &welcome_code).unwrap(), did);
        let (a, b) = (crate::keys::load_identity(&first).unwrap(), crate::keys::load_identity(&second).unwrap());
        assert!(b.controller.is_none(), "no identity key on the new device");
        assert_eq!(b.meta.identity, did);
        assert_ne!(b.device.did(), a.device.did());
        assert_eq!(b.key_agreement.as_ref().map(|k| k.secret), a.key_agreement.as_ref().map(|k| k.secret), "the same key agreement key");
        assert!(!second.join(PENDING).exists(), "the one-time key is gone");
        // what needs the identity key, the new device cannot do
        assert!(crate::backup::export_identity(&second, "a long passphrase").is_err());

        // a welcome code for another device does not open here; a mistyped join code is said so
        let (other_join, _) = start(&base.join("third")).unwrap();
        let (other_welcome, _) = welcome(&first, &other_join).unwrap();
        assert!(matches!(finish(&base.join("fourth"), &other_welcome), Err(Error::Keys(m)) if m.contains("not started")));
        let (_, _) = start(&base.join("fourth")).unwrap();
        assert!(matches!(finish(&base.join("fourth"), &other_welcome), Err(Error::Keys(m)) if m.contains("not for this device")));
        let i = join.len() - 2;
        let typo = format!("{}{}{}", &join[..i], if &join[i..i + 1] == "A" { "B" } else { "A" }, &join[i + 1..]);
        assert!(matches!(welcome(&first, &typo), Err(Error::Keys(m)) if m.contains("mistyped")));
        std::fs::remove_dir_all(base).unwrap();
    }
}
