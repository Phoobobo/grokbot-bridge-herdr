# Changelog

## 0.3.2 — 2026-11-03

An hc launch shows up in the Herdr app, in the space for that repo, on its own tab.

- `gbb launch` on hc labels the terminal `herdr.space` (and `--keep`). It does not set `herdr.tab`, so the app opens a new tab instead of splitting one that is already there. The space is the local one whose folder or a terminal was started in that git repo (a worktree counts as the main checkout); if none match, the display name equal to the repo directory. With no Herdr window, the same id is read from a terminal already labeled `herdr.space`. Otherwise gbb mints an id and the app creates the space when it next looks; if the window is open, gbb renames that space to the repo directory.
- Handover of an hc terminal that is not already in a space gets the same label. One that already has `herdr.space` stays where it is.
- `gbb stop` still only kills and removes terminals gbb created. It does not close Herdr spaces or tabs. Launch JSON gains `herdr_space` and `created_herdr_space`. Webhook fields are unchanged.

## 0.3.1 — 2026-11-03

Split gbb into modules that turn on from a probe, so a machine without dots-bridge does not dial `127.0.0.1:8765` on every event. Config files stay the same; this is 0.3.1 rather than 0.4.0 because the webhook payload, subcommands, and config keys are unchanged. `gbb report` is additive.

- Modules: `core` (always on), `herdr_tui` (`herdr` on PATH and `herdr status server` running), `hc` (`hc server status` returns a pid), `dots` (token file `~/.config/dots-bridge/herdr_webhook_token` mode 600 and `127.0.0.1:8765` accepting connections). `[modules.<id>] enabled = true|false` overrides the probe.
- Owner and `[[extra_webhooks]]` targets whose host:port is the dots endpoint are skipped, and logged, when the dots module is off. An owner skip still falls back to the primary webhook (`fallback_reason=dots_unavailable`). Other extra webhooks are not gated.
- `gbb doctor` lists each module with probe result, effective enabled, and reason. `gbb report` prints host, version, modules, webhook targets by name and host only, whether `hc-watch` is running, and each task (id, kind, backend, owner, pane id, status, alive, stale, repo, worktree). No header values or token contents.

## 0.3.0 — 2026-11-02

Launch tasks in herdr-core (`hc`) terminals, which the Herdr app can show and attach, without moving tasks that already run in the Herdr TUI.

- `backend = "auto"|"herdr"|"hc"` in config.toml, or `GBB_BACKEND`, or `gbb launch --backend`. `auto` (the default) launches new tasks on hc when `hc server status` can reach or start the core, and uses the Herdr TUI only when hc is missing or that call fails. `backend = "herdr"` and `--backend herdr` still force the TUI. Each registry row records its backend; a row with no field, or `backend = "herdr"`, keeps using the TUI session server for status, send, read, stop, and handover while the hc watcher runs for hc rows.
- On `hc`, status callbacks come from `hc events` (OSC 7501) and use the same payload and owner / primary / extra routing. `error` is delivered as `blocked` with `blocked_reason=error`. The OSC message text is not sent.
- Codex and Grok Build report status themselves (Codex's OSC 7501, Grok Build ≥ 1.0.52). gbb does not wrap them. A Codex that has not reported yet still uses the existing screen classification. `hc send` is never called with `--force`.
- `gbb stop` kills and removes only hc terminals gbb created. Handover terminals are unlabeled, not killed. gbb does not run `hc server stop`.

## 0.2.0

Owner-routed callbacks, Codex screen corrections, and the dots-tunnel-bridge extra webhook. See docs/decisions/0003 and 0004.
