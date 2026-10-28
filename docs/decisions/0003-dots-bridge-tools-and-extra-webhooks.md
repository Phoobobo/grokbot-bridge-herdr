# 0003 — dots-tunnel-bridge MCP tools and `[[extra_webhooks]]`

Date: 2026-10-28 · Status: accepted

## Context

- The user runs a self-hosted [dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge) MCP server on the Mac (a fork of
  [uezo/dots-bridge](https://github.com/uezo/dots-bridge); loopback `127.0.0.1:8765`, published through OpenAI Secure MCP Tunnel) so a ChatGPT "dot" can reach local tools. They want
  the dot to drive the same coding agents Grok Bot drives through `gbb`.
- The dot can call MCP tools, and it can receive bridge events (`app.message.created`, subscribed per
  channel). It cannot run a shell, so it needs `gbb` wrapped as tools, and it needs status changes pushed to it.
- `gbb` already had one webhook target (the Grok Bot routine). That one must keep working unchanged.

## Decision

- **Tools live in dots-tunnel-bridge**, not here: a separate module `src/dots_bridge/herdr_tools.py`, registered only when
  `DOTS_BRIDGE_HERDR_TOOLS=1`. Each tool runs `gbb <subcommand>` with an argv list (no shell), an explicit
  PATH, stdin closed, a timeout, and validated inputs (`gbb_wait` max 120 s). Tools that send input or stop a
  pane re-check `gbb list` and refuse unmanaged panes and the user's protected workspaces (default `wAS`,
  `wAT`) unless the pane was explicitly handed over. `gbb_launch` appends a draft-PR-only policy to the prompt.
  `gbb` stays the single place that talks to Herdr, so its guardrails (managed panes only, never
  `herdr server stop`) apply to the dot too.
- **`[[extra_webhooks]]`** (array of tables: `url`, `header_name`, `header_value`, max 5) gets the identical
  payload as the primary webhook, each as its own background curl with the header on stdin. Same mode-600
  rule; logs show `webhook[xN]` and the host only; `gbb doctor` shows the count and hosts only. Primary webhook
  code path, keys and env overrides are unchanged; extras are read from the config file only.
- **The dots receiver** is `POST /herdr/webhook` on the dots-tunnel-bridge app: loopback clients only, a token header
  (`X-Dots-Herdr-Token`, compared in constant time, token file mode 600), `source` must be
  `grokbot-bridge-herdr`, and only the known id/status fields are kept. It turns the event into an
  `app.message.created` message on the first subscribed channel (`herdr`, then `default`), with
  `metadata.source = "herdr"`.

## Alternatives considered

- A dedicated `herdr.agent_status_changed` dots event type: cleaner for the dot, but needs changes to
  the bridge's subscription identity, store schema and delivery worker (upstream uezo/dots-bridge code). Reusing
  `app.message.created` needs none of that; the dot tells herdr messages apart by `metadata.source`.
- Polling only (`gbb_wait`): works without events, but ties up a tool call for up to two minutes per check.
- Shelling out from the dot through a generic "run command" tool: rejected, too broad.

## Consequences

- After adding or changing tools, the dot's tool list must be rescanned in ChatGPT.
- If no channel is subscribed, the receiver answers 202 `delivered:false`; nothing is queued for later.
- A slow or down dots-tunnel-bridge cannot delay the Grok Bot webhook: every target posts in its own background job.

Note (2026-10-28): the bridge was published as [Phoobobo/dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge); its
[docs/HERDR.md](https://github.com/Phoobobo/dots-tunnel-bridge/blob/main/docs/HERDR.md) documents the tools and setup. Paths such as
`~/.config/dots-bridge/` and the `dots_bridge` package name are kept from upstream.
