# 0005 — herdr-core (`hc`) as a second backend

Date: 2026-11-02 · Status: accepted

## Context

Herdr shipped a native app (herdrdev/herdr-app, 2026-10-29) on a new runtime, herdr-core, driven by `hc`. Agent status there is OSC 7501 (the Program Status Protocol), delivered on `hc events` / `events.subscribe`. The Herdr TUI (0.9.x) is still updated and still has live tasks. gbb 0.2.0 only speaks the TUI: `herdr` CLI plus the `pane.agent_status_changed` plugin hook.

Checked against hc 0.1.16 on Linux (the release the user's machine runs):

- `hc` answers `OSC 7501 ; ?` with `states=idle,working,done,blocked,error` and `kinds=permission,question,auth`. A program that never reports stays `status: null`, `reported: false`. hc does not infer status from the screen. Templates do not install reporters.
- `hc events` (piped) prints one JSON line per fact: first a snapshot `{seq, terminals}`, then JSON-RPC `event` notifications. A status event is `{type:"status", terminal, data:{status, records, reported}}` where `status` is `{state, app, kind, msg, ...}` or null. `hc get` returns the same object; `hc ls` shortens `status` to the state word.
- `terminal.send` / `hc send` pastes text and submits it, and refuses a blocked program unless `--force` (which can answer the dialog).
- Codex emits OSC 7501 itself (`app=codex`, including from multiplexers; later builds add `done`/`error` and `kind=permission|question|auth`). Grok Build 1.0.52 added OSC 7501. Both ask the terminal before they report, and hc answers.

## Decision

- New tasks can launch on `hc`. Config `backend = "auto"|"herdr"|"hc"`, else `GBB_BACKEND`, else `--backend` on that launch. `auto` uses the TUI when `herdr` is on PATH and `hc` only when `herdr` is not. A machine that has both (live TUI tasks plus the app) does not move until someone sets `hc`.
- The registry records `backend`. A missing field means the TUI, so rows written before 0.3.0 keep working. Later commands follow the row, not the config.
- Launch is `hc run --bg --no-parent --no-notify` of `grok` or `codex` plus the same `grok_args` / `codex_args`, then `hc send` for the prompt. No `--force`. Labels `grokbot=managed` and `gbb_task=<id>` are the marker. `gbb stop` kills and removes only terminals this launch created. Handover labels an existing terminal and never kills it. gbb never runs `hc server stop`.
- Status callbacks come from one background `hc events --label grokbot=managed` watcher (restarted from launch, handover, and when it dies). The payload stays the 0.2 shape plus `backend`. `working` is not sent. `error` is delivered as `blocked` with `blocked_reason=error` and `herdr_status=error`, so existing consumers still wake. `kind` becomes `blocked_reason` when it is `permission`, `question`, or `auth`. The OSC `msg` is never copied (it can be prompt text). Codex still gets the existing screen correction, including when it has not reported yet (`foreground` events, throttled). Grok is not screen-guessed: current Grok Build reports natively, and a wrapper that also wrote OSC 7501 would replace that root record.
- `gbb send` / `answer` / `keys` / `read` / `status` / `wait` / `result` use the matching `hc` command. `wait --until` polls the reported word (`error` counts as `blocked`).

## Alternatives rejected

- Prefer `hc` whenever its server is up. That would move new launches off the TUI on a machine that still has live TUI tasks, with no config change.
- Wrap grok and codex so gbb emits OSC 7501. Current Codex and Grok Build already emit it, and a second writer on the root record would clobber theirs. hc has no inference API to call instead.
- One `hc events` process per task. A single watcher filtered by `grokbot=managed` covers launch and handover and survives the `gbb` command that started it.

## Consequences

- The Herdr app shows the terminal (attach with `hc attach <name>`). The TUI plugin is not involved, so handover in the app is `gbb handover --pane <t>` (an id without `:` is tried as an hc address).
- Dots-tunnel-bridge does not need a new tool. Set `backend` on the machine; the dot's `gbb_launch` is unchanged. Payloads gain `backend`. Receivers that keep a field allow-list ignore it; `status` is still `done`, `idle`, or `blocked`.
- A Grok Build older than 1.0.52, or a Codex that does not speak 7501 and is not showing a screen gbb already classifies, runs visibly but does not invent `working`/`done`. `gbb status` shows `reported` via the raw word (`agent.agent_status` null until it speaks).
