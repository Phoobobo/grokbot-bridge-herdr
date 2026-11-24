# 0006 — Modules that turn on from a probe, and `gbb report`

Date: 2026-11-03 · Status: accepted

## Context

gbb's dots-tunnel-bridge path (owner `dot`, `[[extra_webhooks]]` to `127.0.0.1:8765/herdr/webhook`, token file `~/.config/dots-bridge/herdr_webhook_token`) lived in the same config and the same notify loop as the Herdr TUI and hc backends. On a machine with no dots-bridge, those targets were still copied into `config.toml`, and every status event tried a localhost URL that was not there. The Herdr TUI plugin, the herdr CLI, and `gbb hc-watch` are the same kind of optional piece: each should run only where that machine actually has it.

A Grok Bot status page needs the same facts in one JSON document: which modules are on, why, which webhook hosts are live, and each task's backend and liveness. `gbb doctor` was close but not a task list, and it was not shaped for a page.

## Decision

Four modules. `core` is always on. The others follow a probe unless `[modules.<id>] enabled = true|false` overrides it:

| module | probe |
|---|---|
| `herdr_tui` | `herdr` on PATH and `herdr status server --json` has `running: true` (herdr 0.9.5; this command does not start the server) |
| `hc` | `hc server status` JSON has a numeric `pid` (starts the core if needed; same check as `auto`) |
| `dots` | token file exists, is non-empty, mode 600 or 400, and `http://127.0.0.1:8765/` accepts a connection |

`enabled = false` forces the module off. `enabled = true` forces it on even when the probe fails. Unset follows the probe.

Only webhook targets whose host:port equals the dots probe (`127.0.0.1:8765` by default) are dots targets. When the dots module is off they are not contacted; the log says `dots module off` and the reason. An owner target skipped this way still falls back to the primary webhook with `fallback_reason=dots_unavailable`. Other `[[extra_webhooks]]` are unchanged. The primary webhook is never treated as a dots target.

`gbb report` prints one JSON object: host, version, `backend_default`, `backend_effective`, `modules` (id, probe_ok, enabled, config, reason), `webhooks` (name and host only), `hc_watch.running`, and `tasks` (task_id, kind, backend, owner, pane_id, status, alive, stale, repo, worktree). `gbb doctor` includes the same `modules` array. Neither prints header values, token file contents, or full webhook URLs.

Existing registry rows are unchanged: no `backend` field still means the TUI, and those commands still call `herdr`. The plugin hook and `hc events` watcher still run side by side.

## Alternatives rejected

- Skip every `[[extra_webhooks]]` whose header is `X-Dots-Herdr-Token`. The offline tests, and any non-dots receiver that reused that header name on another port, would stop getting events. Gating the dots endpoint (host:port) leaves other extras alone.
- Delete dots keys from config when the probe fails. That would rewrite the MBP's config from the Mac mini and drop the dot the next time dots-bridge is up.
- A separate daemon for the status page. `gbb report` is one shot, like `gbb doctor`, and does not add a process.

## Consequences

- A config copied from the MBP onto a machine with no dots-bridge keeps the dot tables and stops calling them until port 8765 and the token file are both present. No hand edit.
- While dots-bridge is down on a machine that does use it, dot-owned events go to the primary webhook with `dots_unavailable` instead of waiting on a refused connection. When it is back, the next event uses the owner target again.
- `auto` will not fall back to herdr when `herdr status server` is not running. `herdr workspace create` would have failed in that case anyway. `--backend herdr` still tries the CLI.
