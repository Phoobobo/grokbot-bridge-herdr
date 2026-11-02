# Changelog

## 0.3.0 — 2026-11-02

Launch tasks in herdr-core (`hc`) terminals, which the Herdr app can show and attach, without moving tasks that already run in the Herdr TUI.

- `backend = "auto"|"herdr"|"hc"` in config.toml, or `GBB_BACKEND`, or `gbb launch --backend`. `auto` keeps the TUI when `herdr` is installed. Each registry row records its backend; a row with no field stays on the TUI.
- On `hc`, status callbacks come from `hc events` (OSC 7501) and use the same payload and owner / primary / extra routing. `error` is delivered as `blocked` with `blocked_reason=error`. The OSC message text is not sent.
- Codex and Grok Build report status themselves (Codex's OSC 7501, Grok Build ≥ 1.0.52). gbb does not wrap them. A Codex that has not reported yet still uses the existing screen classification. `hc send` is never called with `--force`.
- `gbb stop` kills and removes only hc terminals gbb created. Handover terminals are unlabeled, not killed. gbb does not run `hc server stop`.

## 0.2.0

Owner-routed callbacks, Codex screen corrections, and the dots-tunnel-bridge extra webhook. See docs/decisions/0003 and 0004.
