# The DSIP app

Flutter over [`dsip-app`](../crates/dsip-app) through `flutter_rust_bridge` (app plan stage A3), on Linux, Windows and
macOS, and on Android and iOS (A5). The bridge (`rust/src/api/app.rs`) is five functions: `init_identity`, `start` (with `dsip-app`'s `Settings`),
`command` and `updates`, each carrying `dsip-app`'s own `Command`, `Response`, `State` and `Change` as JSON, the
values the control socket carries, so the app and the CLI cannot behave differently, and `stop`. Each update holds
the whole state after a change, so Dart never applies a change itself.

The screens are in `lib/src/screens`, what they drive is `lib/src/controller.dart` over a `Client`
(`lib/src/client`; the real one is `RustClient`), and every string is in `lib/l10n/app_en.arb`. The Dart readers of
the state (`lib/src/client/models.dart`) are held to `test/fixtures/state.json`, `messages.json`, `presence.json` and `settings.json`, which `dsip-app`'s own test makes
(`crates/dsip-app/tests/wire_fixture.rs`): when the Rust types change, `UPDATE_FIXTURES=1 cargo test --test
wire_fixture` writes it again and the Dart test says what to follow.

So far: the first run (make an identity, or use an identity folder; the relay, a mailbox, a hints node), calls (place,
answer, decline, hang up, mute), messages (first contact: introduce yourself, answer the requests that come; direct
and group conversations, their threads kept up as messages arrive; add, remove, leave), presence (the state you publish,
automatic or picked; following others, and what is known of each: their state, whether it is their relay's word or a
record of theirs, how many of their devices are sealed to you; stop following, stop sharing), who you are, and the
settings: the microphone and speaker (chosen at once, kept for the next start) and the connection (relay, mailbox,
hints node, STUN server; saved, then the app starts again with them). Joining as another device of an identity on
another machine comes later.

`test/goldens` holds a screenshot of every screen, light and dark, drawn from the fixtures with the app's own font
(Inter, `assets/fonts`, SIL Open Font License) and Material Icons. One set, made on Linux, is compared on Linux
(exactly) and on Windows and macOS, where text's edges rasterise a few shades apart: there a screen matches while under
0.3% of its pixels differ by more than 96 of 255 (`test/goldens/tolerant_comparator.dart`, Anvil's; each run prints the
figures). A screen changed on purpose needs them made again, on Linux:

```bash
flutter test test/goldens --update-goldens
```

A failed comparison leaves the images and their difference in `test/goldens/failures` (CI keeps them as the run's
artifact).

```bash
flutter pub get
flutter test                                              # the screens against a fake client, and the goldens
flutter run -d linux                                      # or windows, macos
flutter test integration_test/app_test.dart -d linux      # the app as built, its Rust core loaded
```

Building needs what `dsip-app` needs (`../README.md`), and on Linux Flutter's desktop tools: `clang cmake ninja-build
pkg-config libgtk-3-dev`. On Windows, cargo builds the Rust core in `build\windows\x64\ck`, short of MSVC's
260-character paths; from a deep checkout, set `CARGOKIT_TEMP_DIR` to a short folder such as `C:\ck`. After changing `rust/src/api`, make the bindings again:

```bash
flutter_rust_bridge_codegen generate   # 2.13.0
```

## On a phone

The same app on Android (8.0 and later) and iOS, with the same id as the desktop's, `com.thevoiceguy.dsip` (A5a, as
Anvil's U4a). Cargokit cross-builds the Rust core for each Android ABI and for iOS devices and simulators.
`MainActivity` loads the core and hands it the JVM and the application context, which cpal's Android audio needs and a
Flutter app does not set up (`rust/src/android.rs`); `rust/build.rs` links the NDK's C++ ABI for oboe. Before the app
starts it asks for the microphone (refused, it still starts and says why) and, on iOS, sets the audio session to play
and record for voice chat (`lib/src/mobile/platform.dart`, the `dsip/mobile` channel). Below 600 points wide the tabs
run along the bottom and a conversation opens over the list; the goldens hold each screen at a phone's size too
(`phone-*.png`). A phone does not update itself: its store does (A7).

The app's calls are the system's calls (A5b, as Anvil's U4b): CallKit on iOS, a self-managed `ConnectionService` with
Telecom on Android, kept in step by `lib/src/mobile/calls.dart`. A call ringing in rings there (the lock screen too), a
call placed shows as dialling, answered and over follow `dsip-app`; answering, declining, hanging up and muting there
are the same commands the app's buttons send. A call the system filters (Do Not Disturb, a blocked caller) is
declined; one it cannot show still rings in the app. DSIP's calls have no hold and no keys, so the system offers
neither. On Android a foreground service runs while there is a call, so it keeps the microphone when the user leaves
the app, with a call-style notification (Answer and Decline, then Hang up), and the app comes over the lock screen only
then; the system's Recents on iOS leave the app's calls out. Where a call's audio goes is the system's (A5c, as Anvil's U4c): Telecom's call endpoints (Android 14 on; the call
audio state before) and the audio session's route on iOS: the earpiece, the speaker, Bluetooth (by the device's name
where the system gives it), a wired headset. A call shows a speaker switch when the earpiece and the speaker are all
there is, and with Bluetooth or a headset too, the route in use, opening the list to choose from; on a phone Settings
has no microphone and speaker lists. The screen goes off at the ear while a call is answered or being placed on the
earpiece (not ringing, not on the speaker or a headset): a proximity wake lock on Android, released once the phone has
left the ear, proximity monitoring on iOS.

A sleeping phone rings (A5d, DSIP's Wake Profile). On Android (A5d-2, as Anvil's A2) the publisher's push gateway and
Firebase project are given at build time, so none is kept here: `DSIP_PUSH_GATEWAY` (its DID) and `DSIP_FCM_APP_ID`,
`DSIP_FCM_SENDER_ID`, `DSIP_FCM_API_KEY`, `DSIP_FCM_PROJECT_ID`, from the environment or `-P`; without them the app
builds and is never woken. The FCM token goes to the core (`push.json` in the app's folder, given to `dsip-app`'s
`push` at every start), which enrols it at the gateway and registers with the relay and the mailbox. Telecom follows the
core itself on Android, Dart or not (`rust/src/system.rs`, read by `CoreLink.kt`): a push starts the app with no
Flutter running. A `call` wake rings at once, as from an unknown caller (the wake's hint is the relay's claim), while
the core starts and binds; the call's invite, flushed then, takes its place by session and says who calls; answered
before it came, it is answered then; declined, it is declined. A `call-ended` wake, the core not starting, or a minute
with no invite ends it. A `message` wake starts the core so the mailbox delivers.

On iOS (A5d-3, as Anvil's A3) the gateway is given the same way (`DSIP_PUSH_GATEWAY` in the environment of
`flutter build ios`, read through Info.plist); PushKit's VoIP token goes to the core with the topic, the bundle ID with
`.voip`, and APNs' environment (`sandbox` when the build's provisioning profile is a development one). CallKit follows
the core as Telecom does (`rust/src/ios.rs`, a C ABI read by `CoreLink.swift`), and calls ring and end as on Android.
Apple's rule is that every VoIP push reports a call: a `call-ended` wake reports the call it names, or one ended at
once, as does a wake for an app not set up. An unsigned build gets no tokens, so it is never woken until A4c signs it.

The identity's keys are kept in the platform's store, not in the identity folder (A6a, `dsip_app::keys`):
- **iOS:** the Keychain, readable after the phone's first unlock so a push wakes a locked phone, and kept on this
  device only.
- **Android:** the Android Keystore.
- **macOS:** the login keychain.
- **Windows:** Credential Manager.
- **Linux:** the Secret Service, or the files, their owner's alone.

An identity made before this is moved in at the next start. A store that refuses them (a build without the
entitlements a keychain wants) leaves them in those files, and says why in the log.

Messages wake an iPhone through a second token (A5d-4): APNs takes PushKit's token for the `.voip` topic only, so the
app also registers for remote notifications and gives the core its alert token, on the bundle ID's topic, which the
core enrols apart and gives to the mailbox (spec-gap 178; both kept in `push.json`). The user is asked once, at a
launch after setup, to allow notifications. A message wake is an alert the system shows by itself, "New message"
(`DSIP_NEW_MESSAGE` in `ios/Runner/en.lproj/Localizable.strings`), with none of the app's code run; tapped, the app
opens and its mailbox delivers. Showing who wrote, and what, before then needs a notification service extension
that syncs the mailbox (the profile's "may sync"): a later step.

```bash
flutter build apk --release                                   # debug-signed until there is an upload key (A7)
flutter build ios --release --no-codesign                     # unsigned until there is an Apple account
flutter test integration_test/mobile_test.dart -d <device>    # an emulator or a simulator: the core, the audio, wakes
DSIP_PUSH_GATEWAY=did:web:push.example DSIP_FCM_APP_ID=… DSIP_FCM_SENDER_ID=… DSIP_FCM_API_KEY=… DSIP_FCM_PROJECT_ID=… \
  flutter build apk --release                                 # woken through the publisher's gateway and Firebase project
DSIP_PUSH_GATEWAY=did:web:push.example flutter build ios --release   # woken through the gateway by PushKit (signed builds)
```

Accessibility (A7), checked by `test/accessibility_test.dart` on every screen, at a desktop's size and a phone's:
- tap targets of at least 48 dp (Android) and 44 (iOS), and a label on everything tappable;
- text contrast of WCAG AA (4.5:1): measured on the screens where Flutter's sampling reads it right, and computed
  exactly for every colour pair the theme draws text in, both themes;
- every screen at twice the text size without overflowing;
- the first run done from the keyboard (Tab reaches each field and Start);
- the calls from the keyboard, from any tab: Ctrl+Enter answers, Ctrl+Backspace declines or hangs up, Ctrl+M mutes
  (Cmd on a Mac), named in the buttons' tooltips;
- a call ringing in, and each change of its state, said to a screen reader.

The launcher icons are drawn by `tool/icons.py` with the desktop's.

## Releases

A tag `vX.Y.Z` (the `dsip-app` crate's version) runs `.github/workflows/release.yml`: the installers for each desktop,
each installed, started and removed again in CI before anything is published, and the `dsip-app` CLI for each, with
`SHA256SUMS` over the release. A pull request touching the packaging runs the same without publishing.

| | Package | Made by |
|---|---|---|
| Windows | a setup for this user, no administrator needed, in `%LOCALAPPDATA%\Programs\DSIP` | `packaging/windows.iss` (Inno Setup 6) |
| macOS | a disk image, the app universal (Apple Silicon and Intel) | `packaging/macos.sh` |
| Linux | a `.deb` (`/opt/dsip`, `dsip` on the path) and an AppImage | `packaging/linux.sh` |

Uninstalling keeps the app's folder, which holds the identity's keys, unless the user says to delete it (Windows
asks; a silent uninstall keeps it): a `did:key` identity cannot be rotated, so its keys gone is the identity gone.
The app updates itself (`rust/src/api/update.rs`, Anvil's `anvil-update` with DSIP's description). Each release
carries `latest.json` (`packaging/manifest.py`: the version, the release's page, each installer with its size and
SHA-256) and `latest.json.sig`, an Ed25519 signature made in the release workflow with the `DSIP_UPDATE_KEY` secret and
checked there against `packaging/update-key.pub.pem`, the public half the app carries (a test holds them together).
The app looks half a minute after it starts and every hour, and Settings has a check by hand. A banner offers "Update
and restart" (not during a call; it looks again first, then fetches the file, checks its size and SHA-256, stops the
app and runs the installer, which starts it again) to the Windows setup and an AppImage, and "Download" to a .deb or a
Mac app its user cannot replace (the sandbox allows no write to Applications). The key's private half is the secret and
one offline copy the owner keeps: lost, installed copies take no updates until reinstalled by hand with a build that
carries a new key.

Nothing is code-signed yet, as Anvil's builds: A4c (Windows Authenticode, macOS Developer ID and notarization) waits
for the certificates. Until then the first run warns: SmartScreen's "More info" → "Run anyway" on Windows; on macOS,
System Settings → Privacy & Security → "Open Anyway" after the first try (right-click → Open before macOS 15). The icon is drawn by `tool/icons.py` (no dependencies):
`python3 tool/icons.py`.
