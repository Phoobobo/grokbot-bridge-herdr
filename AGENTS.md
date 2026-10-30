# AGENTS.md — grokbot-bridge-herdr

Herdr plugin + `gbb` CLI that let Grok Bot drive and watch coding agents (grok, codex) in Herdr panes on the user's machine. ChatGPT dots use the same `gbb` through the companion MCP server [dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge) (fork of uezo/dots-bridge, exposed via OpenAI Secure MCP Tunnel), whose `gbb_*` tools call these subcommands and whose `/herdr/webhook` receives `[[extra_webhooks]]` and the `dot` owner target — keep `gbb`'s JSON output, subcommand flags and webhook payload compatible with it (see `docs/decisions/0003`).

## Change context (required)

Every commit and pull request must leave enough context that later work can trace why the change was made.

- Commit messages use an imperative subject. The body explains why, the alternatives or trade-offs considered, and how the change was verified. When an agent makes the commit, add the trailer `Agent-Session: <conversation URL or session id>`.
- Pull request descriptions follow `.github/pull_request_template.md`, including the link to the agent conversation that produced the change.
- Non-obvious design decisions go in `docs/decisions/NNNN-title.md`. Keep the note short: context, decision, and consequences.
- Whoever installs a new version on a machine notes the machine, the commit, the time in UTC+8, and the end-to-end check result in the PR (or commit) comment.

## Layout

- `herdr-plugin.toml` — Herdr plugin manifest v1 (`phoobobo.grokbot-bridge`): event hooks and pane actions. All entrypoints run `bin/gbb`.
- `bin/gbb` — the whole implementation, POSIX sh + jq + git + curl. User-facing subcommands print one JSON document.
- `config.example.toml` — webhook config template. Real config lives in `~/.config/grokbot-bridge-herdr/config.toml` (mode 600) and is never committed.
- `install.sh` / `uninstall.sh` — symlink `gbb` into `~/.local/bin` and link/unlink the plugin.
- `tests/hook-test.sh` — offline hook/debounce test with a stubbed `herdr`.
- `tests/prompt-test.sh` — offline prompt delivery/retry test with a stubbed `herdr` (~45 s).
- `tests/webhook-test.sh` — offline primary + `[[extra_webhooks]]` delivery test against a local HTTP sink.
- `tests/owner-test.sh` — offline owner routing / fallback / extra dedupe test against a local HTTP sink (~25 s).
- `tests/screen-test.sh` — offline Codex screen handling (hooks review, queued question, fresh session, `gbb answer`, pending launch prompt) with a stubbed `herdr` that draws Codex 0.166 screens.
- `docs/decisions/` — ADRs.

## Guardrails (do not weaken without an ADR)

- Hooks must never block Herdr: exit fast, background the webhook POST with a short `--max-time`.
- Only managed panes (in `managed.json`) produce webhooks. Ignore `working`; send `done`, `idle`, `blocked`, plus `handover`, `reclaim`, `stopped`, `pane_closed`.
- Webhook payloads carry ids and status only: no terminal output, no prompts, no environment, no secrets.
- The auth header is passed to curl via stdin config so it never appears in `ps`. Logs record the host, never the URL path or header.
- `gbb stop` closes only workspaces gbb created (and only when they still hold just the managed pane). Handover panes are unregistered, never closed.
- Never run `herdr server stop`. Never touch panes that are not managed.
- Never answer the Grok "Help improve Grok" banner with Opt in.
- Never type a prompt into a Codex dialog (digits / letters pick options). Never choose a dialog option (e.g. trust hooks) without an explicit `gbb answer` / `gbb keys` from the caller.
- Callbacks follow the task owner (docs/decisions/0004): owner target first, the primary webhook as fallback, extras unchanged except URL dedupe. A failed owner delivery must still reach the primary.

## Verify

- `for t in tests/*.sh; do sh "$t" || break; done` (offline, ~2 min) and `shellcheck -s sh -S warning bin/gbb` (only the known SC2088/SC1010 false positives).
- On a machine with Herdr: `gbb doctor`, then a launch in a scratch repo (see README "End-to-end check").
