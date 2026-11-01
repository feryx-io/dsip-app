# dsip-app

The official DSIP client, for Windows, macOS, Linux, Android and iOS. DSIP (Decentralized Session Initiation
Protocol) is an identity-first protocol for calls and messages: the spec and its conformance suite are in
[DSIP](https://github.com/thevoiceguy/DSIP), the Rust stack and its services in
[dsip-rs](https://github.com/thevoiceguy/dsip-rs). This repository is the app over that stack, following dsip-rs's
[app plan](https://github.com/thevoiceguy/dsip-rs/blob/main/docs/dsip-app-plan.md).

**Status: stage A2, the running client.** There is no UI yet. The `dsip-app` crate is the client the screens will
sit on:
- **Calls:** it binds an identity to its relay, rings for incoming calls, places calls, and carries their sound
  through the microphone and speaker. With `--hints-node`, it publishes its relay in its hint, and a call to
  someone bound to another relay goes through theirs, as the browser client does.
- **Messages:** first contact (introduce, accept), then direct conversations, through the identity's mailbox. A
  `did:key` identity's mailbox is found through its hint on the hints nodes, which the app publishes, as the browser
  client does.
- **Control:** a local control socket that the `dsip-app` CLI drives.

Presence comes next; the Flutter desktop app (A3) and the mobile apps (A5) after.

```
crates/dsip-app     the running client: State, Change, Command, the control socket, audio, and the CLI
```

## Try it

```sh
dsip-app init --identity ~/.dsip/alice --name Alice           # prints Alice's DID
dsip-app run --identity ~/.dsip/alice --relay wss://relay.example.com:8443/dsip &
dsip-app watch &                                               # the state, then every change, one JSON line each
dsip-app call did:key:z6Mk…                                    # Bob's DID
dsip-app hangup
dsip-app quit
```

With a mailbox, the same app messages:

```sh
dsip-app run --identity ~/.dsip/alice --relay wss://relay.example.com:8443/dsip \
    --mailbox wss://mailbox.example.com:9443/dsip --mailbox-did did:key:z6Mk… --hints-node https://hints.example.com &
dsip-app introduce did:key:z6Mk…bob "it's Alice"     # Bob's app lists the request; he runs `dsip-app accept <id>`
dsip-app message did:key:z6Mk…bob hello              # once he has: the direct conversation is made on the way
dsip-app thread <group id>                           # `state` lists the conversations
```

On Bob's side, `dsip-app answer` takes the call that rings. `--audio tone` uses a test tone instead of the
microphone (headless machines); `--audio none` signals calls with no sound. `--ca relay.pem` trusts a relay's
self-signed certificate.

## How it is built

- **One state, one stream of changes.** [`App`](crates/dsip-app/src/lib.rs) owns the identity and a
  [`dsip_phone::Phone`](https://github.com/thevoiceguy/dsip-rs/tree/main/crates/dsip-phone). It keeps the `State` a
  screen shows, and publishes each change to it as one `Change`. Commands go in; screens only read. The CLI drives
  the running app through the control socket (one JSON command per line), so the CLI and the app can't behave
  differently, and CI tests the client without a UI. The model is [Anvil](https://github.com/thevoiceguy/anvil)'s
  `anvil-app`.
- **Protocol decisions stay in dsip-rs.** The phone's endpoint core and call glue decide what is sent and when
  media starts; this crate adds no protocol of its own.
- **Sound.** Anvil's `anvil-audio` provides the devices (cpal, plus echo cancellation and noise suppression in
  Rust). The microphone is encoded to 48 kHz Opus and fed to the call's WebRTC leg (dsip-media); what the leg
  receives is decoded to the speaker.
- **Messages.** A `dsip-messenger` on a thread of its own (its store is SQLite). It uploads fresh KeyPackages and
  syncs live on every binding, publishes the device's hint, and turns what the engine hears into changes.
- **dsip-rs by one ref.** Every `dsip-*` crate is pinned to the same dsip-rs ref (dsip-rs `RELEASING.md`,
  "Downstream"): a release tag, or between releases the commit carrying what the app needs.

## Build and test

Rust as pinned in `rust-toolchain.toml`. On Linux, ALSA's headers (`libasound2-dev`).

```sh
cargo test --workspace     # two apps on an in-process relay: a call rings, is answered, carries sound both ways;
                           # on Linux, two apps on two mailboxes introduce, grant and message through hints alone
cargo clippy --workspace --all-targets -- -D warnings
```

## License

MIT or Apache-2.0, at your option.
