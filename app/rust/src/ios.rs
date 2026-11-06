//! iOS: what the app's Swift asks of the core when Dart may not be running (app plan A5d-3, as Anvil's A3): a VoIP push
//! that woke the app, the token PushKit gave, CallKit's call screen (`system.rs`; the Wake Profile's W§5.4), as a C ABI
//! declared in `ios/Runner/Runner-Bridging-Header.h`.
//!
//! Each call but [`dsip_init`] blocks until done and answers null, or what went wrong as a string the caller frees with
//! [`dsip_string_free`]; none is called on the main thread. Built for the host's tests too.

use std::ffi::{c_char, CStr, CString};

fn text(s: *const c_char) -> String {
    if s.is_null() {
        return String::new();
    }
    // SAFETY: Swift passes a NUL-terminated string that outlives the call.
    unsafe { CStr::from_ptr(s) }.to_string_lossy().into_owned()
}

fn owned(s: String) -> *mut c_char {
    // A NUL inside is not expected; dropped rather than failing the answer.
    CString::new(s.replace('\0', "")).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Null, or the error.
fn outcome(result: anyhow::Result<()>) -> *mut c_char {
    match result {
        Ok(()) => std::ptr::null_mut(),
        Err(e) => owned(format!("{e:#}")),
    }
}

/// The app's launch, before Dart starts or a push is handled: `dir` is the app's folder (Dart's application support
/// directory, where `settings.json` is); `gateway` the build's push gateway, empty without one. Once per process.
#[no_mangle]
pub extern "C" fn dsip_init(dir: *const c_char, gateway: *const c_char) {
    let gateway = Some(text(gateway)).filter(|g| !g.is_empty());
    crate::system::install(text(dir).into(), gateway);
}

/// A push came: start the app from its settings, unless it runs.
#[no_mangle]
pub extern "C" fn dsip_wake() -> *mut c_char {
    outcome(crate::api::app::runtime().block_on(crate::system::wake()))
}

fn set_push(which: crate::system::Tokens, provider: *const c_char, app: *const c_char, token: *const c_char, environment: *const c_char) -> *mut c_char {
    let (provider, app, token, environment) = (text(provider), text(app), text(token), text(environment));
    let set = crate::system::set_push(which, &provider, &app, &token, Some(environment.as_str()));
    outcome(crate::api::app::runtime().block_on(set))
}

/// Where this install is woken for calls: PushKit's token; an empty one is none. `environment` is APNs' (`sandbox`;
/// empty is production).
#[no_mangle]
pub extern "C" fn dsip_set_push(
    provider: *const c_char,
    app: *const c_char,
    token: *const c_char,
    environment: *const c_char,
) -> *mut c_char {
    set_push(crate::system::Tokens::Calls, provider, app, token, environment)
}

/// Where this install is woken for messages: APNs' alert token, on the bundle ID's topic (spec-gap 178); an empty one
/// is none.
#[no_mangle]
pub extern "C" fn dsip_set_message_push(
    provider: *const c_char,
    app: *const c_char,
    token: *const c_char,
    environment: *const c_char,
) -> *mut c_char {
    set_push(crate::system::Tokens::Messages, provider, app, token, environment)
}

/// The next event for the system's call screen as JSON, or null when none came within `timeout_ms`.
#[no_mangle]
pub extern "C" fn dsip_next_call_event(timeout_ms: i64) -> *mut c_char {
    let within = std::time::Duration::from_millis(timeout_ms.max(0) as u64);
    crate::system::next_event(within).map(owned).unwrap_or(std::ptr::null_mut())
}

/// What the user did at the system's call screen, as JSON.
#[no_mangle]
pub extern "C" fn dsip_act(json: *const c_char) -> *mut c_char {
    let json = text(json);
    outcome(crate::api::app::runtime().block_on(crate::system::act(&json)))
}

/// Free a string this library answered with.
#[no_mangle]
pub extern "C" fn dsip_string_free(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: made by `CString::into_raw` here, and freed once.
        drop(unsafe { CString::from_raw(s) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    /// The answer as Swift reads it, freed.
    fn answer(s: *mut c_char) -> Option<String> {
        if s.is_null() {
            return None;
        }
        let text = unsafe { CStr::from_ptr(s) }.to_string_lossy().into_owned();
        dsip_string_free(s);
        Some(text)
    }

    // One test: the install is once per process.
    #[test]
    fn swift_reaches_the_core_through_the_abi() {
        // A folder not made yet: PushKit may answer before the app is set up.
        let dir = std::env::temp_dir().join(format!("dsip-app-ios-{}", std::process::id())).join("support");
        let dir_c = c(dir.to_str().unwrap());
        dsip_init(dir_c.as_ptr(), c("did:web:push.example").as_ptr());

        let (apns, topic) = (c("apns"), c("com.thevoiceguy.dsip.voip"));
        let set = |token: &str, environment: &str| {
            answer(dsip_set_push(apns.as_ptr(), topic.as_ptr(), c(token).as_ptr(), c(environment).as_ptr()))
        };
        assert_eq!(set("8f2c00a91b", "sandbox"), None);
        let saved = crate::system::load_push(&dir).expect("kept");
        assert_eq!(
            (saved.provider.as_str(), saved.app.as_str(), saved.token.as_str(), saved.environment.as_deref()),
            ("apns", "com.thevoiceguy.dsip.voip", "8f2c00a91b", Some("sandbox"))
        );
        assert_eq!(set("8f2c00a91b", ""), None);
        assert_eq!(crate::system::load_push(&dir).unwrap().environment, None, "empty is production");

        // the alert token, apart, kept beside PushKit's
        let bundle = c("com.thevoiceguy.dsip");
        assert_eq!(answer(dsip_set_message_push(apns.as_ptr(), bundle.as_ptr(), c("c0de").as_ptr(), c("").as_ptr())), None);
        let saved = crate::system::load_push(&dir).unwrap();
        assert_eq!((saved.token.as_str(), saved.message_app.as_deref(), saved.message_token.as_deref()), ("8f2c00a91b", Some("com.thevoiceguy.dsip"), Some("c0de")));
        assert_eq!(set("", ""), None, "PushKit's token gone: messages still wake");
        assert!(crate::system::load_push(&dir).unwrap().message_token.is_some());
        assert_eq!(answer(dsip_set_message_push(apns.as_ptr(), bundle.as_ptr(), c("").as_ptr(), c("").as_ptr())), None);
        assert_eq!(crate::system::load_push(&dir), None, "no token is nowhere");

        // no settings in the folder: nothing to start; no app: nothing to act on, and no events
        assert!(answer(dsip_wake()).unwrap().contains("no settings"));
        assert!(answer(dsip_act(c(r#"{"action":"answer","id":1}"#).as_ptr())).is_some());
        assert_eq!(answer(dsip_next_call_event(0)), None);
        dsip_string_free(std::ptr::null_mut());
        std::fs::remove_dir_all(dir.parent().unwrap()).unwrap();
    }
}
