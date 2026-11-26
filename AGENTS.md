# AGENTS.md — grokbot-bridge-herdr

Herdr plugin + `bac` CLI (BotAsCollie) that let a caller drive and watch coding agents (grok, codex) in Herdr panes on the user's machine. ChatGPT dots still reach this through [dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge) (fork of uezo/dots-bridge, exposed via OpenAI Secure MCP Tunnel). That bridge's current `gbb_*` tools and `source` check are not updated in this repository; see `docs/bac/v1/MIGRATION.md`. Do not describe both ends as working until that cutover and a ChatGPT tool refresh.

## BotAsCollie

The running CLI is `bac` (`bin/bac`). Webhook `source` is `bot-as-collie`, callback `version` is the integer 1. There is no `gbb` command. Contract: `docs/bac/v1/CONTRACT.md`. Dots still has to be updated before both ends work; do not describe this tree as already accepted by the bridge. Do not add a tool that drives `hc` except through `bac`.

## Change context (required)

Every commit and pull request must leave enough context that later work can trace why the change was made.

- Commit messages use an imperative subject. The body explains why, the alternatives or trade-offs considered, and how the change was verified. When an agent makes the commit, add the trailer `Agent-Session: <conversation URL or session id>`.
- Pull request descriptions follow `.github/pull_request_template.md`, including the link to the agent conversation that produced the change.
- Non-obvious design decisions go in `docs/decisions/NNNN-title.md`. Keep the note short: context, decision, and consequences.
- Whoever installs a new version on a machine notes the machine, the commit, the time in UTC+8, and the end-to-end check result in the PR (or commit) comment.

## Layout

- `herdr-plugin.toml` — Herdr plugin manifest v1 (`phoobobo.bot-as-collie`): event hooks and pane actions. All entrypoints run `bin/bac`.
- `bin/bac` — the whole implementation, POSIX sh + jq + git + curl. Generation exclusion is `bin/bac-lock` (python3, fcntl). User-facing subcommands print one JSON document.
- `config.example.toml` — webhook config template. Real config lives in `~/.config/bot-as-collie/config.toml` (mode 600) and is never committed.
- `install.sh` / `uninstall.sh` — symlink `bac` into `~/.local/bin` and link/unlink the plugin. `flock` is not required. `python3` is required for the lock helper. `sha256sum` or macOS `shasum` is.
- `tests/hook-test.sh` — offline hook/debounce test with a stubbed `herdr`.
- `tests/prompt-test.sh` — offline prompt delivery/retry test with a stubbed `herdr` (~45 s).
- `tests/webhook-test.sh` — offline primary + `[[extra_webhooks]]` delivery test against a local HTTP sink.
- `tests/owner-test.sh` — offline owner routing / fallback / extra dedupe test against a local HTTP sink (~25 s).
- `tests/screen-test.sh` — offline Codex screen handling (hooks review, queued question, fresh session, `bac answer`, pending launch prompt) with a stubbed `herdr` that draws Codex 0.166 screens.
- `tests/hc-backend-test.sh` — offline herdr-core backend (command construction, `hc events` → callbacks, backend selection, legacy registry rows).
- `tests/place-test.sh` — offline Herdr-app placement for hc launches and handover (stubbed `hc` and `herdr-app`).
- `tests/bac-contract-test.sh` — offline contract and fixture-migration check.
- `tests/bac-callers-test.sh` — stub `hc` plus a loopback sink. Not a live Herdr, hc, or Dots run.
- `tests/run.sh` — fail-fast runner for `tests/*.sh` except itself.
- `docs/bac/v1/` — BotAsCollie v1 contract and migration checklist. `contracts/bac/v1/` — machine-readable fixtures.
- `docs/decisions/` — ADRs.

## Guardrails (do not weaken without an ADR)

- Hooks must never block Herdr: exit fast, background the webhook POST with a short `--max-time`.
- Only managed panes (in `managed.json`) produce webhooks. Ignore `working`; send `done`, `idle`, `blocked`, plus `handover`, `reclaim`, `stopped`, `pane_closed`.
- Webhook payloads carry ids and status only: no terminal output, no prompts, no environment, no secrets.
- The auth header is passed to curl via stdin config so it never appears in `ps`. Logs record the host, never the URL path or header.
- `bac stop` closes only workspaces bac created (and only when they still hold just the managed pane). Handover panes are unregistered, never closed.
- Never run `herdr server stop` or `hc server stop`. Never touch panes or hc terminals that are not managed. `bac stop` on the hc backend kills and removes only terminals bac created. Handover terminals are unregistered, never killed; reclaim removes the `bac` / `bac_task` labels and also the legacy `grokbot` / `gbb_task` labels, and leaves `herdr.space` in place. Do not `space.close` or `tab.close`: the app drops the pane when that terminal ends, and closes a space only when its last tab goes.
- Never answer the Grok "Help improve Grok" banner with Opt in.
- Never type a prompt into a Codex dialog (digits / letters pick options). Never choose a dialog option (e.g. trust hooks) without an explicit `bac answer` / `bac keys` from the caller.
- Callbacks follow the task owner (docs/decisions/0004): owner target first, the primary webhook as fallback, extras unchanged except URL dedupe. A failed owner delivery must still reach the primary.

## Verify

- The Mac handoff prohibits `tests/run.sh`, lock/kill/concurrency and equivalent capacity/fault probes on every machine. Do not invoke `tests/bac-callers-test.sh` or `tests/lock-fcntl-test.sh`; do not recreate their prohibited cases under another name.
- Use shellcheck and syntax checks without executing the helper. The reviewed serial checks are `sh tests/bac-contract-test.sh`, `sh tests/dots-disabled-test.sh`, `sh tests/scoped-routing-test.sh`, and `sh tests/status-mapping-test.sh`. They are not live E2E evidence.
- Real acceptance uses new state/data/config, a new `BAC_ISOLATED_SCOPE`, and disabled Dots. Do not install, change default CLIs, inspect other sessions, or use the old publication directory. Verify actual completion through a loopback SuperBot receiver, persisted callback, and matching task/pane/owner/assignment read/result. See ADR 0009. Never treat doctor output or a watcher PID alone as E2E success.
