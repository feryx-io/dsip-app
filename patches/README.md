# Patched crates

## nix 0.26.4 (`nix-0.26.4/`)

`webrtc-util` (under `webrtc`, under dsip-rs's `dsip-media`) uses nix 0.26, whose socket code names macOS's kernel
control sockets (`sockaddr_ctl`, `AF_SYS_CONTROL`, `SYSPROTO_*`) on iOS too. libc 0.2.190 declares those for macOS
only, so nix 0.26.4 stops compiling for iOS, and libc cannot be held back: `parking_lot_core` 0.10 (under
`forge-webrtc`) needs libc 0.2.191. Anvil met the same libc change through `backtrace` and holds libc back instead.

This copy is nix 0.26.4 from crates.io with:

- every guard on the kernel-control items (`SysControlAddr`, `sys_control`, `SockProtocol::KextEvent` and
  `KextControl`, the `sctl` field and its match arms, the `RawFd` import only they use) narrowed from iOS and macOS to
  macOS; nothing else in the source changed (`diff -r` against `~/.cargo/registry/src/*/nix-0.26.4/src`);
- its tests and benches left out (`[[test]]` and `[[bench]]` dropped from `Cargo.toml`);
- `#![allow(warnings)]` in place of its `deny` lints: a path patch is linted as this workspace's code, where a
  crates.io dependency's lints are capped.

The root `Cargo.toml` applies it with `[patch.crates-io]`. Remove both once `webrtc-util` moves to a nix that builds
for iOS (nix 0.27 and later gate these to macOS), or libc declares them for iOS again.
