//! Android: the JVM and the application context that cpal's Android backend (oboe) reaches through `ndk_context`. A
//! NativeActivity sets that up; a Flutter app does not, and Dart's FFI opens this library with `dlopen`, which runs no
//! `JNI_OnLoad`. So the app's Kotlin loads the library itself and hands both over here (as Anvil's U4a), with the app's
//! folder; and native code reaches the app here when Dart may not run (A5d-2, as Anvil's A2).

use jni::objects::{JClass, JObject, JString};
use jni::sys::{jlong, jstring};
use jni::JNIEnv;

/// `DsipNative.init(context, dir, gateway)` in the app's Kotlin: once per process, before Dart starts or a push wakes
/// the app. `dir` is the app's folder (where Dart keeps `settings.json`); `gateway` the build's push gateway, empty
/// without one.
#[no_mangle]
pub extern "system" fn Java_com_thevoiceguy_dsip_DsipNative_init(
    mut env: JNIEnv,
    _class: JClass,
    context: JObject,
    dir: JString,
    gateway: JString,
) {
    let dir = text(&mut env, &dir);
    let gateway = Some(text(&mut env, &gateway)).filter(|g| !g.is_empty());
    crate::system::install(dir.into(), gateway);
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let Ok(vm) = env.get_java_vm() else { return };
        let Ok(context) = env.new_global_ref(context) else { return };
        // SAFETY: the VM outlives the process's use of it, and the global reference is leaked so the context stays
        // valid for good.
        unsafe {
            ndk_context::initialize_android_context(vm.get_java_vm_pointer().cast(), context.as_obj().as_raw().cast());
        }
        std::mem::forget(context);
    });
}

// What native code asks of the app when Dart may not be running: a push that woke it, the token the platform gave, the
// system's call screen (`system.rs`). Each blocks its Java thread until done and answers `null` or what went wrong;
// none is called on the main thread.

fn text(env: &mut JNIEnv, s: &JString) -> String {
    env.get_string(s).map(Into::into).unwrap_or_default()
}

/// `null`, or the error as a Java string.
fn outcome(env: &mut JNIEnv, result: anyhow::Result<()>) -> jstring {
    match result {
        Ok(()) => std::ptr::null_mut(),
        Err(e) => env.new_string(format!("{e:#}")).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
    }
}

/// `DsipNative.wake()`: a push came; start the app from its settings, unless it runs.
#[no_mangle]
pub extern "system" fn Java_com_thevoiceguy_dsip_DsipNative_wake(mut env: JNIEnv, _class: JClass) -> jstring {
    let result = crate::api::app::runtime().block_on(crate::system::wake());
    outcome(&mut env, result)
}

/// `DsipNative.setPush(provider, app, token)`: where this install is woken; an empty token is nowhere.
#[no_mangle]
pub extern "system" fn Java_com_thevoiceguy_dsip_DsipNative_setPush(
    mut env: JNIEnv,
    _class: JClass,
    provider: JString,
    app: JString,
    token: JString,
) -> jstring {
    let (provider, app, token) = (text(&mut env, &provider), text(&mut env, &app), text(&mut env, &token));
    let result = crate::api::app::runtime().block_on(crate::system::set_push(crate::system::Tokens::Calls, &provider, &app, &token, None));
    outcome(&mut env, result)
}

/// `DsipNative.nextCallEvent(timeoutMs)`: the next event for the system's call screen as JSON, or `null` when none
/// came in time.
#[no_mangle]
pub extern "system" fn Java_com_thevoiceguy_dsip_DsipNative_nextCallEvent(env: JNIEnv, _class: JClass, timeout_ms: jlong) -> jstring {
    let within = std::time::Duration::from_millis(timeout_ms.max(0) as u64);
    match crate::system::next_event(within) {
        Some(json) => env.new_string(json).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
        None => std::ptr::null_mut(),
    }
}

/// `DsipNative.act(json)`: what the user did at the system's call screen.
#[no_mangle]
pub extern "system" fn Java_com_thevoiceguy_dsip_DsipNative_act(mut env: JNIEnv, _class: JClass, json: JString) -> jstring {
    let json = text(&mut env, &json);
    let result = crate::api::app::runtime().block_on(crate::system::act(&json));
    outcome(&mut env, result)
}
