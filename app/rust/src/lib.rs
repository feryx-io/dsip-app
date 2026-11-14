//! The desktop app's way into `dsip-app`: the functions in [`api`] are what `flutter_rust_bridge` turns into Dart
//! (`lib/src/rust`). The app's state, commands and changes are `dsip-app`'s own values, carried as JSON, the same ones
//! the control socket carries, so the app and the CLI cannot behave differently.

#![deny(missing_docs)]

pub mod api;
#[cfg(target_os = "android")]
mod android;
#[cfg(target_os = "android")]
mod android_video;
#[allow(missing_docs)] // generated
mod frb_generated;
#[cfg(any(target_os = "ios", test))]
mod ios;
mod system;
