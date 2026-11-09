//! Another device of an identity, without the identity key (app plan A6, decision 5 (a)): the new device holds its own
//! key, the identity's delegation of it (§7.4), and the identity's key agreement key (§7.3), and nothing that signs as
//! the identity. Two codes carry them between the devices, by hand (typed, pasted, or a QR), or the second over the
//! local network (the handoff, below), through no server:
//!
//! 1. [`start`], on the new device: its device key and a one-time X25519 key, kept in `pairing.json` until it is
//!    done, and a **join code**, `DSIPJ1-` and base32 of the device's public key, the one-time public key and a
//!    checksum, short enough to type.
//! 2. [`welcome`], on a device holding the identity key: the identity's delegation of that device, and the key
//!    agreement secret sealed to the one-time key (HPKE, as M§6.9's suite), as a **welcome code**, `DSIPW2-` and
//!    base64url of a JSON object compressed with DEFLATE (RFC 1951): about half the length of `DSIPW1-` (the same JSON
//!    uncompressed), so that as a QR code a phone's camera reads it off another screen. [`finish`] reads both.
//! 3. [`finish`], on the new device: the secret opened, the delegation checked, and the device joined
//!    (`Identity::join`), its keys moved into the store.
//!
//! [`check_code`] is the same on both screens: the new device's key, shortened, for the person to compare, so a join
//! code swapped on its way is seen.
//!
//! **The handoff.** A desktop has no camera to scan a welcome code with, and the code is too long to type. So the new
//! device also listens on the local network while it shows its join code ([`Handoff`]), and the join code's QR form
//! carries where: `DSIPJ1-…/192.168.1.20:40123`, the addresses after the code, each after a `/` (still QR's
//! alphanumeric mode). A device that scans it [`send`]s the welcome code there: one TCP connection, the code and a
//! newline, answered `OK` or `NO` and why. Nothing here needs to be secret or trusted: the welcome code is sealed to
//! the one-time key, and what it delegates is checked ([`check`]) as when it is typed. A code from someone else's
//! identity is shown as theirs before anything joins. Typing and pasting the codes still work everywhere.
//!
//! Spec: none (infrastructure). §7.3–§7.4 say what the device ends holding; how it receives it is the identity's own.

use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use dsip_core::envelope::Envelope;
use dsip_core::keys::KeyPair;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::Error;

const JOIN: &str = "DSIPJ1";
/// The welcome code's prefix: its JSON compressed.
const WELCOME: &str = "DSIPW2-";
/// The first welcome codes' (v0.2.0): the JSON as it is.
const WELCOME_V1: &str = "DSIPW1-";
/// The most a welcome code's JSON may decompress to: it is under 2 KiB; more is not a welcome code.
const WELCOME_MAX: usize = 16 * 1024;
const INFO: &[u8] = b"dsip pairing v1";
/// The most a welcome code sent over the handoff may be: the code is under 2 KiB.
const SENT_MAX: usize = 32 * 1024;
/// The most addresses a join code's QR form carries.
const ADDRESSES_MAX: usize = 4;
/// How long a handoff connection may take, at each step.
const STEP: std::time::Duration = std::time::Duration::from_secs(5);
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

/// The device and the one-time key a join code names (in its QR form too: the addresses after it are not read here).
fn read_join(code: &str) -> Result<(String, [u8; 32]), Error> {
    let text = normal(code.split('/').next().unwrap_or_default());
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
    let packed = miniz_oxide::deflate::compress_to_vec(w.to_string().as_bytes(), 10);
    Ok((format!("{WELCOME}{}", dsip_core::b64::encode(&packed)), check_code(&device)))
}

/// A welcome code read on the new device: everything [`finish`] joins with, checked.
struct Opened {
    identity: String,
    name: String,
    device: KeyPair,
    delegation: Envelope,
    ka: dsip_transport::identity::KeyAgreement,
}

/// The new device's last step: the welcome code read, the key agreement secret opened with its one-time key, the
/// delegation and the key agreement delegation checked against it, and the device joined in `dir`. The identity's DID.
pub fn finish(dir: &Path, welcome_code: &str) -> Result<String, Error> {
    let o = open(dir, welcome_code)?;
    let id = dsip_phone::Identity::join(dir, &o.identity, &o.name, o.device, o.delegation, o.ka)?;
    let _ = std::fs::remove_file(dir.join(PENDING));
    crate::keys::ready_identity(dir);
    Ok(id.meta.identity)
}

/// Whether `welcome_code` is for the device starting to join in `dir`, checked as [`finish`] checks it, with nothing
/// joined: the identity it is from, and that identity's name.
pub fn check(dir: &Path, welcome_code: &str) -> Result<(String, String), Error> {
    let o = open(dir, welcome_code)?;
    Ok((o.identity, o.name))
}

fn open(dir: &Path, welcome_code: &str) -> Result<Opened, Error> {
    let pending: Pending = std::fs::read(dir.join(PENDING))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .ok_or_else(|| bad("this device has not started joining (no join code was made here)"))?;
    let (device, once) = match (unhex(&pending.device), unhex(&pending.once)) {
        (Some(d), Some(o)) => (KeyPair::from_seed(d), o),
        _ => return Err(bad(format!("{PENDING} is damaged: start again"))),
    };
    let text = welcome_code.trim();
    let json = if let Some(text) = text.strip_prefix(WELCOME) {
        dsip_core::b64::decode(text).and_then(|b| miniz_oxide::inflate::decompress_to_vec_with_limit(&b, WELCOME_MAX).ok())
    } else if let Some(text) = text.strip_prefix(WELCOME_V1) {
        dsip_core::b64::decode(text)
    } else {
        return Err(bad("not a welcome code (it starts DSIPW2-)"));
    };
    let w: Value = json.and_then(|b| serde_json::from_slice(&b).ok()).ok_or_else(|| bad("the welcome code is incomplete"))?;
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
    Ok(Opened { identity, name: s("name"), device, delegation, ka })
}

/// The addresses a join code's QR form carries (none for a code as typed).
pub fn join_addresses(code: &str) -> Vec<SocketAddr> {
    code.trim().split('/').skip(1).filter_map(|a| a.trim().parse().ok()).take(ADDRESSES_MAX).collect()
}

/// A welcome code received by the [`Handoff`]: checked for this device, not joined yet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Received {
    /// The code, for [`finish`].
    pub welcome: String,
    /// The identity it is from.
    pub identity: String,
    /// That identity's name.
    pub name: String,
}

/// The new device listening on the local network for its welcome code, while it shows its join code: see the module's
/// "handoff". Dropped, it stops.
pub struct Handoff {
    dir: PathBuf,
    listener: TcpListener,
    addresses: Vec<SocketAddr>,
}

impl Handoff {
    /// Listen for the welcome code of the device starting to join in `dir`, on every interface, on a port the system
    /// chooses.
    pub fn listen(dir: &Path) -> Result<Handoff, Error> {
        let listener = TcpListener::bind((Ipv4Addr::UNSPECIFIED, 0)).map_err(|e| bad(format!("listening: {e}")))?;
        let port = listener.local_addr().map_err(|e| bad(e.to_string()))?.port();
        listener.set_nonblocking(true).map_err(|e| bad(e.to_string()))?;
        Ok(Handoff { dir: dir.to_path_buf(), listener, addresses: local_addresses(port) })
    }

    /// Where another device on this network reaches it: this device's IPv4 addresses with the port (none when it has
    /// none but the loopback's).
    pub fn addresses(&self) -> &[SocketAddr] {
        &self.addresses
    }

    /// The port it listens on.
    pub fn port(&self) -> u16 {
        self.listener.local_addr().map(|a| a.port()).unwrap_or_default()
    }

    /// `join_code` in its QR form: the code, then each address after a `/`. The code alone when there are none.
    pub fn qr(&self, join_code: &str) -> String {
        let mut qr = join_code.to_string();
        for a in &self.addresses {
            qr.push('/');
            qr.push_str(&a.to_string());
        }
        qr
    }

    /// A welcome code for this device, when one comes within `wait`: each connection read and answered in turn, one
    /// that is not answered `NO` and the next one read.
    pub fn receive(&self, wait: Duration) -> Result<Option<Received>, Error> {
        let until = Instant::now() + wait;
        loop {
            match self.listener.accept() {
                Ok((stream, from)) => match self.answer(stream) {
                    Ok(r) => return Ok(Some(r)),
                    Err(e) => tracing::info!("a welcome code from {from} was not taken: {e}"),
                },
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    if Instant::now() >= until {
                        return Ok(None);
                    }
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(e) => return Err(bad(format!("listening: {e}"))),
            }
        }
    }

    fn answer(&self, mut stream: TcpStream) -> Result<Received, Error> {
        let io = |e: std::io::Error| bad(e.to_string());
        stream.set_nonblocking(false).map_err(io)?;
        stream.set_read_timeout(Some(STEP)).map_err(io)?;
        stream.set_write_timeout(Some(STEP)).map_err(io)?;
        let line = read_line(&mut stream, SENT_MAX)?;
        match check(&self.dir, &line) {
            Ok((identity, name)) => {
                stream.write_all(b"OK\n").map_err(io)?;
                Ok(Received { welcome: line.trim().to_string(), identity, name })
            }
            Err(e) => {
                let _ = stream.write_all(format!("NO {e}\n").as_bytes());
                Err(e)
            }
        }
    }
}

/// Send `welcome_code` to the new device at the addresses its join code's QR form carries (`join_code`): the address
/// that took it. None when the code carries none (it was typed): then the welcome code is shown, to scan or type.
pub fn send(join_code: &str, welcome_code: &str) -> Result<Option<SocketAddr>, Error> {
    let addresses = join_addresses(join_code);
    if addresses.is_empty() {
        return Ok(None);
    }
    send_to(&addresses, welcome_code).map(Some)
}

/// Send `welcome_code` to the first of `addresses` that takes it; why the last did not, when none did.
pub fn send_to(addresses: &[SocketAddr], welcome_code: &str) -> Result<SocketAddr, Error> {
    let mut why = bad("no address to send it to");
    for &a in addresses {
        let sent = (|| -> Result<(), Error> {
            let io = |e: std::io::Error| bad(format!("{a}: {e}"));
            let mut stream = TcpStream::connect_timeout(&a, STEP).map_err(io)?;
            stream.set_read_timeout(Some(STEP)).map_err(io)?;
            stream.set_write_timeout(Some(STEP)).map_err(io)?;
            stream.write_all(format!("{}\n", welcome_code.trim()).as_bytes()).map_err(io)?;
            let reply = read_line(&mut stream, 1024)?;
            match reply.strip_prefix("NO") {
                None if reply.trim() == "OK" => Ok(()),
                Some(no) => Err(bad(format!("the new device did not take it: {}", no.trim()))),
                None => Err(bad(format!("{a} is not a device joining"))),
            }
        })();
        match sent {
            Ok(()) => return Ok(a),
            Err(e) => why = e,
        }
    }
    Err(why)
}

/// A line from `stream`, of at most `max` bytes, without its newline: the end of the stream ends it too.
fn read_line(stream: &mut TcpStream, max: usize) -> Result<String, Error> {
    let mut got = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        let n = stream.read(&mut buf).map_err(|e| bad(format!("reading: {e}")))?;
        if n == 0 {
            break;
        }
        got.extend_from_slice(&buf[..n]);
        if let Some(end) = got.iter().position(|&b| b == b'\n') {
            got.truncate(end);
            break;
        }
        if got.len() > max {
            return Err(bad("more than a welcome code"));
        }
    }
    String::from_utf8(got).map_err(|_| bad("not text"))
}

/// This device's IPv4 addresses other than the loopback's, private ones first, with `port`.
fn local_addresses(port: u16) -> Vec<SocketAddr> {
    let mut v4: Vec<Ipv4Addr> = if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| match i.ip() {
            std::net::IpAddr::V4(a) if !a.is_loopback() && !a.is_unspecified() => Some(a),
            _ => None,
        })
        .collect();
    v4.sort_by_key(|a| (!a.is_private(), a.is_link_local()));
    v4.dedup();
    v4.into_iter().take(ADDRESSES_MAX).map(|a| SocketAddr::from((a, port))).collect()
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
        // compressed: small enough for a QR code a camera reads off another screen
        assert!(welcome_code.starts_with(WELCOME) && welcome_code.len() < 1300, "{} characters", welcome_code.len());

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

    #[test]
    fn the_welcome_code_comes_back_over_the_local_network_to_the_device_that_scanned_nothing() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let base = std::env::temp_dir().join(format!("dsip-app-pairing-handoff-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let (first, second) = (base.join("first"), base.join("second"));
        let did = crate::init_identity(&first, "Ann").unwrap();

        // the new device: its join code, and the same with where it listens, for the QR code
        let (join, _) = start(&second).unwrap();
        let handoff = Handoff::listen(&second).unwrap();
        let here = SocketAddr::from((Ipv4Addr::LOCALHOST, handoff.port()));
        let qr = format!("{join}/{here}/not-an-address");
        assert_eq!(join_addresses(&qr), vec![here], "the addresses after the code; what is not one is passed over");
        assert!(join_addresses(&join).is_empty(), "a code as typed carries none");
        let own = handoff.qr(&join);
        assert!(own.starts_with(&join) && join_addresses(&own).len() == handoff.addresses().len());
        assert!(handoff.addresses().iter().all(|a| !a.ip().is_loopback() && a.port() == handoff.port()));

        // the device holding the identity reads the QR form as the join code, and sends the welcome code back
        let (welcome_code, _) = welcome(&first, &qr).unwrap();
        // a welcome code for another device is refused, and the handoff goes on listening
        let (other_join, _) = start(&base.join("third")).unwrap();
        let (other_welcome, _) = welcome(&first, &other_join).unwrap();
        let sender = std::thread::spawn(move || {
            let refused = send_to(&[here], &other_welcome);
            (refused, send(&qr, &welcome_code), welcome_code)
        });
        let got = handoff.receive(Duration::from_secs(20)).unwrap().expect("received");
        let (refused, sent, welcome_code) = sender.join().unwrap();
        assert!(matches!(refused, Err(Error::Keys(m)) if m.contains("not for this device")), "said why");
        assert_eq!(sent.unwrap(), Some(here));
        assert_eq!(got, Received { welcome: welcome_code.clone(), identity: did.clone(), name: "Ann".into() });
        assert!(!second.join("identity.json").exists(), "checked, not joined: the person starts it");
        assert_eq!(finish(&second, &got.welcome).unwrap(), did);

        // nothing sent: nothing received; nowhere to send: the code is shown instead
        assert_eq!(handoff.receive(Duration::from_millis(200)).unwrap(), None);
        assert_eq!(send(&join, &welcome_code).unwrap(), None);
        drop(handoff);
        assert!(send_to(&[here], &welcome_code).is_err(), "a handoff dropped listens no more");
        std::fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn a_handoff_takes_no_more_than_a_welcome_code() {
        let dir = std::env::temp_dir().join(format!("dsip-app-pairing-flood-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let handoff = Handoff::listen(&dir).unwrap();
        let here = SocketAddr::from((Ipv4Addr::LOCALHOST, handoff.port()));
        let sender = std::thread::spawn(move || send_to(&[here], &"A".repeat(SENT_MAX * 2)));
        assert_eq!(handoff.receive(Duration::from_secs(3)).unwrap(), None);
        assert!(sender.join().unwrap().is_err());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_welcome_code_of_the_first_form_is_still_read() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let base = std::env::temp_dir().join(format!("dsip-app-pairing-v1-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let (first, second) = (base.join("first"), base.join("second"));
        let did = crate::init_identity(&first, "Ann").unwrap();
        let (join, _) = start(&second).unwrap();
        let (w2, _) = welcome(&first, &join).unwrap();
        // the same JSON as v0.2.0 wrote it: uncompressed, `DSIPW1-`
        let json = miniz_oxide::inflate::decompress_to_vec(&dsip_core::b64::decode(&w2[WELCOME.len()..]).unwrap()).unwrap();
        let w1 = format!("{WELCOME_V1}{}", dsip_core::b64::encode(&json));
        assert!(w1.len() > w2.len() * 3 / 2, "W2 is the shorter by far: {} against {}", w2.len(), w1.len());
        assert_eq!(finish(&second, &w1).unwrap(), did);
        std::fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn a_welcome_code_that_would_decompress_too_far_is_refused() {
        let _one = crate::keys::STORE_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = std::env::temp_dir().join(format!("dsip-app-pairing-bomb-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        start(&dir).unwrap();
        let bomb = miniz_oxide::deflate::compress_to_vec(&vec![b' '; WELCOME_MAX * 64], 10);
        let code = format!("{WELCOME}{}", dsip_core::b64::encode(&bomb));
        assert!(matches!(finish(&dir, &code), Err(Error::Keys(m)) if m.contains("incomplete")));
        assert!(matches!(finish(&dir, "DSIPX9-hello"), Err(Error::Keys(m)) if m.contains("not a welcome code")));
        std::fs::remove_dir_all(dir).unwrap();
    }
}
