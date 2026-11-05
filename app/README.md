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
(`phone-*.png`). A phone does not update itself: its store does (A7). The system's call screen (CallKit, Telecom),
the call's audio route and ringing a sleeping phone (A1's push) come next (A5b–A5d).

```bash
flutter build apk --release                                   # debug-signed until there is an upload key (A7)
flutter build ios --release --no-codesign                     # unsigned until there is an Apple account
flutter test integration_test/mobile_test.dart -d <device>    # an emulator or a simulator: the core, the audio
```

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
