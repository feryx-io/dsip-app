//! Profile cards (core §19.4, the extension `profile-card/1.0`): the name and small picture this identity asks to be
//! shown as, and those others sent it. What a card is, when one may be sent and how one is sealed are dsip-rs's
//! (`dsip_core::profile_card`, `dsip_messaging::first_contact::profile_card_send`); this module keeps the user's
//! choices and picture, and the cards received, in the identity's folder.
//!
//! A card leaves this device only by the user's standing choice, off until turned on, one choice for introductions
//! sent and one for requests accepted (§19.4 "Consent"). A card received is its sender's own claim: the state says
//! nothing of it is verified, and a screen shows it so.
//!
//! A card that came on a grant is no longer shown once that grant's `valid_until` has passed, or once the grant is
//! revoked (§19.4 "Keeping it", a SHOULD). A grantee is sent no revocation: the phone says when following the
//! grantor's presence was ended by policy while the grant still ran (`dsip_phone::ShareEnded`, spec-gap 190), and
//! the card goes then. Not following them, the app learns nothing and the card stays until `valid_until`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::state::{Card, Profile};
use crate::{App, Change};

/// The user's choices and picture ([`Profile`]), kept in the identity directory.
pub const PROFILE_FILE: &str = "profile.json";

/// The cards contacts sent, by identity, kept in the identity directory.
pub const CARDS_FILE: &str = "cards.json";

/// Where the pictures of cards received are kept, in the identity directory: one file a picture, named by its hash.
pub const CARDS_DIR: &str = "cards";

/// A card kept for a contact: the card as taken, and when the grant that carried it ends (none: it came on an
/// introduction).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct Kept {
    card: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    until: Option<i64>,
}

/// What [`PROFILE_FILE`] holds: the choices, and the picture's file name in the identity directory.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct Saved {
    #[serde(default)]
    with_introductions: bool,
    #[serde(default)]
    with_grants: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    picture: Option<String>,
}

/// The media type of a picture a card may carry, by how its bytes begin: JPEG or PNG (§19.4).
pub fn picture_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        Some("image/jpeg")
    } else if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
        Some("image/png")
    } else {
        None
    }
}

fn extension(content_type: &str) -> &'static str {
    if content_type == "image/png" { "png" } else { "jpg" }
}

/// The profile as a screen sees it, from [`PROFILE_FILE`] in `dir`.
pub(crate) fn load_profile(dir: &Path) -> Profile {
    let saved: Saved = std::fs::read(dir.join(PROFILE_FILE)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let picture = saved.picture.map(|f| dir.join(f)).filter(|p| p.is_file()).map(|p| p.to_string_lossy().into_owned());
    Profile { picture, with_introductions: saved.with_introductions, with_grants: saved.with_grants }
}

fn save_profile(dir: &Path, profile: &Profile) {
    let picture = profile.picture.as_deref().and_then(|p| Path::new(p).file_name()).map(|f| f.to_string_lossy().into_owned());
    crate::save_json(&dir.join(PROFILE_FILE), &Saved { with_introductions: profile.with_introductions, with_grants: profile.with_grants, picture });
}

/// The cards kept in `dir`.
pub(crate) fn load_cards(dir: &Path) -> BTreeMap<String, Kept> {
    std::fs::read(dir.join(CARDS_FILE)).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

/// `card`, as taken from a message, for a screen: its name, and its picture as a file in `dir`'s [`CARDS_DIR`],
/// written when it is not there yet. The file is named by the picture's hash, so a changed picture is a new file.
pub(crate) fn view(dir: &Path, card: &Value) -> Card {
    let picture = card["picture"]["data"].as_str().and_then(dsip_core::b64::decode).and_then(|bytes| {
        let ext = extension(card["picture"]["content_type"].as_str().unwrap_or_default());
        let hash: String = Sha256::digest(&bytes).iter().take(12).map(|b| format!("{b:02x}")).collect();
        let path = dir.join(CARDS_DIR).join(format!("{hash}.{ext}"));
        if !path.is_file() {
            let tmp = path.with_extension("tmp");
            let r = std::fs::create_dir_all(dir.join(CARDS_DIR)).and_then(|()| std::fs::write(&tmp, &bytes)).and_then(|()| std::fs::rename(&tmp, &path));
            if let Err(e) = r {
                tracing::warn!("keeping a card's picture in {}: {e}", path.display());
                return None;
            }
        }
        Some(path.to_string_lossy().into_owned())
    });
    Card { name: card["display_name"].as_str().map(String::from), picture }
}

/// The cards of `kept` still shown at `now`, for a screen.
pub(crate) fn views(dir: &Path, kept: &BTreeMap<String, Kept>, now: i64) -> BTreeMap<String, Card> {
    kept.iter().filter(|(_, k)| k.until.is_none_or(|u| u > now)).map(|(id, k)| (id.clone(), view(dir, &k.card))).collect()
}

/// When the compact grant `grant` ends (its `valid_until`).
pub(crate) fn grant_until(grant: &str) -> Option<i64> {
    let payload = dsip_core::b64::decode(grant.split('.').nth(1)?)?;
    serde_json::from_slice::<Value>(&payload).ok()?["valid_until"].as_i64()
}

impl App {
    fn dir(&self) -> &Path {
        &self.inner.identity_dir
    }

    /// This identity's card: its display name, and its picture when it has one. `None` when dsip-rs would not take
    /// it (the picture's file changed under the app).
    pub(crate) fn my_card(&self) -> Option<Value> {
        let s = self.state();
        let mut card = json!({});
        if !s.me.display_name.is_empty() {
            card["display_name"] = json!(s.me.display_name);
        }
        if let Some(bytes) = s.profile.picture.as_deref().and_then(|p| std::fs::read(p).ok()) {
            if let Some(t) = picture_type(&bytes) {
                card["picture"] = json!({"content_type": t, "data": dsip_core::b64::encode(&bytes)});
            }
        }
        dsip_core::profile_card::take_card(&card).filter(|c| c.as_object().is_some_and(|o| !o.is_empty()))
    }

    /// `SetPicture`: make the image file at `path` this identity's picture (copied into the identity's folder), or
    /// with none, have no picture. An error says why a file is not one a card may carry.
    pub(crate) fn set_picture(&self, path: Option<&str>) -> Result<(), String> {
        let mut profile = self.state().profile;
        let old = profile.picture.take().map(PathBuf::from);
        if let Some(path) = path {
            let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
            let t = picture_type(&bytes).ok_or("the picture must be a JPEG or a PNG")?;
            let max = dsip_core::profile_card::CARD_PICTURE_MAX_BYTES;
            if bytes.len() > max {
                return Err(format!("the picture is {} bytes: a card carries at most {max}", bytes.len()));
            }
            // a new name each time: a screen that cached the last one shows this one
            let hash: String = Sha256::digest(&bytes).iter().take(6).map(|b| format!("{b:02x}")).collect();
            let kept = self.dir().join(format!("profile-picture-{hash}.{}", extension(t)));
            std::fs::write(&kept, &bytes).map_err(|e| format!("{}: {e}", kept.display()))?;
            profile.picture = Some(kept.to_string_lossy().into_owned());
        }
        if let Some(old) = old.filter(|o| Some(o.to_string_lossy().as_ref()) != profile.picture.as_deref()) {
            let _ = std::fs::remove_file(old);
        }
        self.set_profile(profile);
        self.send_cards();
        Ok(())
    }

    /// The card changed, or is shared from now on: send it to those this identity granted (§19.4 "A changed card").
    fn send_cards(&self) {
        if let Some(m) = self.inner.messaging.get() {
            let _ = m.send(crate::messaging::Req::SendCards);
        }
    }

    /// `ShareProfile`: the standing choices, each left as it is when not given.
    pub(crate) fn share_profile(&self, introductions: Option<bool>, grants: Option<bool>) {
        let mut profile = self.state().profile;
        profile.with_introductions = introductions.unwrap_or(profile.with_introductions);
        let turned_on = !profile.with_grants && grants == Some(true);
        profile.with_grants = grants.unwrap_or(profile.with_grants);
        self.set_profile(profile);
        if turned_on {
            self.send_cards();
        }
    }

    fn set_profile(&self, profile: Profile) {
        save_profile(self.dir(), &profile);
        self.publish(Change::Profile { profile });
    }

    /// Keep `card` as `identity`'s, in place of the one held (§19.4 "Keeping it": a later card replaces the earlier
    /// whole, so one without a picture removes the picture). `until` is when the grant that carried it ends.
    pub(crate) fn keep_card(&self, identity: &str, card: &Value, until: Option<i64>) {
        let mut kept = self.inner.cards.lock().unwrap_or_else(|e| e.into_inner());
        kept.insert(identity.to_string(), Kept { card: card.clone(), until });
        self.publish_cards(&kept);
    }

    /// Forget the card `identity` sent on a grant: that grant was revoked, as far as a grantee can tell (§19.4
    /// "Keeping it", spec-gap 190). A card that came on their introduction is ours to keep with the contact: it rode
    /// no grant of theirs.
    pub(crate) fn drop_granted_card(&self, identity: &str) {
        let mut kept = self.inner.cards.lock().unwrap_or_else(|e| e.into_inner());
        if kept.get(identity).is_some_and(|k| k.until.is_some()) {
            kept.remove(identity);
            self.publish_cards(&kept);
        }
    }

    /// Stop showing the cards whose grant has ended, and forget them.
    pub(crate) fn expire_cards(&self) {
        let now = dsip_transport::now_s();
        let mut kept = self.inner.cards.lock().unwrap_or_else(|e| e.into_inner());
        let before = kept.len();
        kept.retain(|_, k| k.until.is_none_or(|u| u > now));
        if kept.len() != before {
            self.publish_cards(&kept);
        }
    }

    fn publish_cards(&self, kept: &BTreeMap<String, Kept>) {
        crate::save_json(&self.dir().join(CARDS_FILE), kept);
        let cards = views(self.dir(), kept, dsip_transport::now_s());
        // pictures no card shows any more
        let shown: std::collections::BTreeSet<&str> = cards.values().filter_map(|c| c.picture.as_deref()).collect();
        let requests = self.state().messaging.requests;
        let asked: std::collections::BTreeSet<&str> = requests.iter().filter_map(|r| r.card.as_ref()?.picture.as_deref()).collect();
        if let Ok(files) = std::fs::read_dir(self.dir().join(CARDS_DIR)) {
            for f in files.flatten() {
                let p = f.path().to_string_lossy().into_owned();
                if !shown.contains(p.as_str()) && !asked.contains(p.as_str()) {
                    let _ = std::fs::remove_file(f.path());
                }
            }
        }
        self.publish(Change::Cards { cards });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_picture_is_a_jpeg_or_a_png_by_its_bytes() {
        assert_eq!(picture_type(&[0xff, 0xd8, 0xff, 0xe0, 0]), Some("image/jpeg"));
        assert_eq!(picture_type(b"\x89PNG\r\n\x1a\n...."), Some("image/png"));
        assert_eq!(picture_type(b"GIF89a"), None);
        assert_eq!(picture_type(b""), None);
    }

    #[test]
    fn a_card_is_viewed_with_its_picture_as_a_file_named_by_its_hash() {
        let dir = std::env::temp_dir().join(format!("dsip-app-cards-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let bytes = [0xff, 0xd8, 0xff, 1, 2, 3];
        let card = json!({"display_name": "Carol", "picture": {"content_type": "image/jpeg", "data": dsip_core::b64::encode(&bytes)}});
        let v = view(&dir, &card);
        assert_eq!(v.name.as_deref(), Some("Carol"));
        let path = v.picture.expect("a picture");
        assert!(path.ends_with(".jpg"));
        assert_eq!(std::fs::read(&path).unwrap(), bytes);
        // the same picture: the same file; a card without one: none
        assert_eq!(view(&dir, &card).picture.as_deref(), Some(path.as_str()));
        assert_eq!(view(&dir, &json!({"display_name": "Carol"})), Card { name: Some("Carol".into()), picture: None });
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_card_that_came_on_a_grant_is_shown_until_the_grant_ends() {
        let dir = std::env::temp_dir().join(format!("dsip-app-cards-until-{}", std::process::id()));
        let mut kept = BTreeMap::new();
        kept.insert("did:key:a".to_string(), Kept { card: json!({"display_name": "A"}), until: Some(100) });
        kept.insert("did:key:b".to_string(), Kept { card: json!({"display_name": "B"}), until: None });
        assert_eq!(views(&dir, &kept, 99).len(), 2);
        assert_eq!(views(&dir, &kept, 100).keys().collect::<Vec<_>>(), ["did:key:b"]);
    }

    #[test]
    fn a_grant_says_when_it_ends() {
        let payload = dsip_core::b64::encode(br#"{"type":"grant","valid_until":1790000000}"#);
        assert_eq!(grant_until(&format!("h.{payload}.s")), Some(1_790_000_000));
        assert_eq!(grant_until("nonsense"), None);
    }
}
