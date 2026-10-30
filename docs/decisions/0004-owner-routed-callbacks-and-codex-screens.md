# 0004 — Owner-routed callbacks, and reading Codex screens

Date: 2026-10-30 · Status: accepted

## Context

1. Several agents now launch tasks through the same `gbb` on one machine: the user's Grok Bot, a second Grok Bot
   (参谋长), and a ChatGPT dot through dots-tunnel-bridge. Every status callback went to the single primary
   webhook (plus every `[[extra_webhooks]]` target), so whoever launched a task was not necessarily the one woken
   when it finished, and the others got noise.
2. Codex 0.166 under Herdr 0.9.5 produced wrong signals:
   - its startup "Hooks need review" dialog is reported `idle`, and a session that never ran a turn
     ("Context 0% used · 0 in · 0 out") is reported `done`, so callers got a false `done`;
   - `gbb launch --prompt` treated the dialog's `› 1. Review hooks` line as the composer and typed the prompt
     into the dialog (where digits / letters can pick an option), so the prompt was never submitted;
   - with a queued question ("⇧← to answer") `gbb send` only returned Herdr's error, with no way forward.
3. Launched Codex panes ran "GPT-6.1-Sol medium" although the intent was xhigh: with `codex_args = []` gbb defers
   to `~/.codex/config.toml`, whose top level says `model_reasoning_effort = "medium"`.

## Decision

**Owners.** A task may carry an `owner` (`gbb launch --owner <name>`, else `$GBB_OWNER`; `gbb handover --owner`;
`gbb owner <task> <name>|--clear` to reassign). It is stored in the registry, shown by `list`/`status`, and put in
every payload. Config gains named targets — `[[owners]]` with `name`/`url`/`header_name`/`header_value`
(or `[owners.<name>]`), same parsing rules and mode-600 requirement as `[[extra_webhooks]]`.

Routing per event (payload gains `route` and, when relevant, `fallback_reason`):

| situation | delivered to | route |
|---|---|---|
| no owner | primary | `primary` |
| owner with a target | owner target only | `owner` |
| owner POST fails (curl error or non-2xx) | then primary | `fallback` / `owner_delivery_failed` |
| owner not in config / bad URL / insecure config | primary | `fallback` / `owner_not_configured` … |
| every event | each `[[extra_webhooks]]`, except one whose URL equals the owner target already used | `extra` |

The owner POST and its fallback run in one background job, so hooks still never wait.

*Extras stay as they were* (every event), to keep existing installs unchanged. The only change is dedupe against
the owner target, so the deployed config (extra = dots-bridge **and** owner `dot` = dots-bridge) delivers a
dot-owned task once. Users who want the dot to see only its own tasks remove the extra and keep the owner.
Alternative rejected: turning extras into owner-only targets — that silently changes what an existing dots
setup receives.

dots-tunnel-bridge's `gbb_launch`/`gbb_handover` pass `--owner dot` (`DOTS_BRIDGE_GBB_OWNER`), so Grok Bot no
longer gets the dot's callbacks unless the dot target fails. A second Grok Bot needs its own webhook routine;
its URL/header go into an `[[owners]]` entry and it launches with `--owner <its name>`.

**Codex screens.** For codex panes gbb reads the bottom of the visible screen (`classify_text`):
`hooks_review`, `question` (open or queued), other numbered `dialog`, `fresh` composer (0 in · 0 out) or `ready`.
- The hook turns herdr `idle`/`done` into `blocked` with `blocked_reason` for dialogs, and for a `fresh` launched
  pane (`prompt_not_submitted`). Handover panes in `fresh` are `idle`. During launch (`launching_until`) a fresh
  `done` is ignored.
- Launch waits for the real composer (`›` line that is not a numbered option, plus the `Context N% used` footer)
  and a stable screen (longer when `.codex/hooks.json` exists); if a dialog appears it does **not** type: it saves
  the prompt (`$STATE_DIR/pending/<pane>`, mode 600), arms the pane, sends a `blocked` event
  (`blocked_reason`, `prompt_pending: true`) and returns `state: startup_blocked` with the screen.
- After Herdr accepts a prompt, gbb confirms the turn started (working indicator or the text echoed above the
  composer); if the text is still in the composer it presses Enter once; if a dialog opened it reports
  `agent_blocked`.
- `gbb answer <task> <n|label>` opens a queued question (shift+left), moves the `›` selection with up/down until
  it is on the wanted option (verified from the screen), presses Enter and checks the dialog closed. Then, if a
  launch prompt is pending and the composer is ready, it submits it (`gbb send <task> --pending` does that by hand).
  It never picks an option on its own; "trust hooks" is always an explicit caller choice.
- `gbb send` refuses to type into a dialog and returns `error.hint` explaining `gbb answer` / the manual keys.
- `launch` records the Codex footer's model line (`agent_model`, e.g. "GPT-6.1-Sol xhigh"); `status` shows
  `screen_state`, `agent_model`, `prompt_pending`; `doctor` shows `codex_user_defaults` and `codex_args`.

**Model.** No code default is forced; the fix is configuration: pin `codex_args` in gbb's config
(documented in config.example.toml). `doctor` makes the `~/.codex/config.toml` fallback visible.

## Consequences

- Payload adds `owner`, `route`, optional `fallback_reason`, `blocked_reason`, `herdr_status`, `prompt_pending`.
  Old receivers ignore them; dots-tunnel-bridge keeps them.
- Screen matching depends on Codex TUI wording (0.166). If Codex changes it, classification degrades to Herdr's
  raw status (old behaviour); tests/screen-test.sh pins the expected screens.
- A failed owner delivery costs up to two timeouts before the fallback lands (background, never blocking).
