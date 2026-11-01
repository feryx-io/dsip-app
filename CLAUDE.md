# CLAUDE.md — dsip-app

The DSIP client app over [dsip-rs](https://github.com/thevoiceguy/dsip-rs). Plan: dsip-rs `docs/dsip-app-plan.md`
(stages A1–A7). The model is Anvil's `anvil-app` (one state, one change stream, commands, a control socket and CLI).

## Rules

- **No protocol here.** What is sent, when, and what is accepted is dsip-rs's (and DSIP's vectors). A behaviour the
  app needs that dsip-rs lacks is a change to dsip-rs, released, then used here by tag.
- **dsip-rs by one tag.** Every `dsip-*` dependency in `[workspace.dependencies]` names the same tag; different refs
  of one repository duplicate crates (dsip-rs `RELEASING.md`, "Downstream").
- **Anvil by tag.** `anvil-audio` (and later `anvil-update`) come from Anvil's release tags (app plan decision 4).
- **The CLI and the app are one.** Everything a screen can do is a `Command`, and everything it shows is in `State` or
  a `Change`; the CLI drives the same `App` through the control socket. CI tests it with the tone host.
- `#![deny(missing_docs)]`; clippy and rustdoc with `-D warnings` in CI.
