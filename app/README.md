# The DSIP desktop app

Flutter over [`dsip-app`](../crates/dsip-app) through `flutter_rust_bridge` (app plan stage A3), on Linux, Windows and
macOS. The bridge (`rust/src/api/app.rs`) is five functions: `init_identity`, `start` (with `dsip-app`'s `Settings`),
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
