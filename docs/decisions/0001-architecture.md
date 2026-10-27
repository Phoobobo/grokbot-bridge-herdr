# 0001 — Architecture: herdr CLI over remote shell, plugin fills the gaps

Date: 2026-10-28 · Status: accepted

## Context

Grok Bot (a cloud assistant) should start, watch and steer local coding agents (grok, codex) on the user's
MacBook, and the user should be able to hand some of their own Herdr panes to Grok Bot and take them back.
Grok Bot can already run shell commands on the user's registered machines (remote shell), and it can be woken
by an HTTPS webhook on a routine.

Herdr 0.9.x already provides almost everything needed to drive agents: `workspace create --no-focus`,
`agent start --kind grok|codex`, `agent prompt --wait`, `agent read`, `agent send-keys`, `agent wait`, and
plugin event hooks. A feasibility test (2026-10-28, Herdr 0.9.3, grok 1.0.70) showed that a plugin hook on
`pane.agent_status_changed` fires within ~20–75 ms of each idle/working/done change of an agent started from
outside Herdr, with payload `{event, data:{pane_id, workspace_id, agent_status, agent}}`.

What Herdr lacks: (1) pushing a status change to an outside service, (2) knowing which panes belong to Grok Bot
(and which task), (3) a user gesture to hand a pane over / take it back, (4) guardrails so a remote driver never
closes or pokes the user's own panes.

## Decision

- **Grok Bot drives agents through the `herdr` CLI via remote shell on the user's machine**, wrapped by `gbb`
  for JSON output, retries (startup banner, `agent_prompt_stalled`), git worktrees, and the registry.
- **The plugin only adds what Herdr lacks**: a status-change webhook for managed panes (done/idle/blocked,
  debounced, backgrounded curl), a managed-pane registry (`~/.local/state/grokbot-bridge-herdr/managed.json`),
  handover/reclaim pane actions with a visible `🤖 Grok Bot` marker (`pane report-metadata`), and guardrails
  (close only what gbb created; never touch unmanaged panes; no output or secrets in webhooks).
- Implementation is one POSIX sh script with jq/git/curl so it runs on stock macOS and Linux without a build.

## Alternatives rejected

- **MCP server / tunnel into the Mac**: Grok Bot's remote MCP connectors need a public HTTPS endpoint. The MBP
  has no Tailscale (or other tunnel) and exposing a local socket publicly would be a large new attack surface.
  Remote shell already exists, is authenticated, and stays under the user's approval policy.
- **Polling from Grok Bot** (`herdr agent wait` over remote shell): works (tested as fallback) but keeps a
  remote shell open for the whole turn and cannot cover panes the user hands over while Grok Bot is asleep.
- **Long-lived `events.subscribe` daemon**: equivalent signal, but an extra process to supervise; the plugin
  hook is managed by Herdr itself and survives restarts.
- **Codex `exec` / app-server** for codex tasks: good for headless jobs, but loses the shared, visible pane the
  user can watch and take over; kept as a possible later mode.

## Consequences

- Webhook delivery is best-effort (5 s timeout, no retry queue). Grok Bot should treat a missing webhook as
  "check with `gbb status`", and can always fall back to `gbb wait`.
- The webhook URL and sender key live only in `~/.config/grokbot-bridge-herdr/config.toml` (mode 600).
- The registry is keyed by Herdr pane id; entries are removed on `pane.closed`, `gbb stop`, or reclaim.
