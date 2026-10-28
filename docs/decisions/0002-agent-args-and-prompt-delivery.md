# 0002 — Per-kind agent args and verified first-prompt delivery

Date: 2026-10-28 · Status: accepted

## Context

- The user wants agents launched by Grok Bot to run with a chosen model/effort (codex: `gpt-6.1-sol`,
  reasoning effort `xhigh`) without depending on, or changing, what their own Codex app uses.
  `gbb launch -- <args>` existed but joined the args into one string and re-split it, so an arg such as
  `model_reasoning_effort="xhigh"` or one containing spaces could not be passed reliably.
- `gbb launch --kind codex` failed with `PROMPT_RESULT: unbound variable` and `prompt_error: Expected JSON
  value (while parsing '')`. Root cause: `prompt_with_retry` only set `PROMPT_RESULT` on some paths; after four
  `agent_prompt_stalled` attempts it returned 1 with it unset (`set -u`). The stalls themselves came from
  typing into codex too early: `herdr agent start` reports ready while codex (cold start, ~20 s on first run)
  is still drawing its splash and drops the input, and herdr's status briefly reads `working` during startup.
  The old "text still in input box" check also cut the snippet with `cut -c`, which slices bytes on macOS
  and never matches CJK prompts.

## Decision

- Config keys `codex_args` / `grok_args` (single-line array of double-quoted strings, parsed as JSON) are
  the default agent args when launch has no `--`. Args travel as `"$@"`, one argv word each; herdr quotes them
  when it types the command (verified with a value containing spaces). Applied args are recorded in the
  registry entry and launch output (`agent_args`).
- Before the first prompt, wait for status idle/done, the codex `›` composer, and a screen unchanged across
  two 1 s polls (bounded by `startup_ready_timeout_sec`, default 90).
- On stall/timeout: poll status and screen (`esc to interrupt`) for ~6 s; if the text is on screen, press Enter
  once if it is in the composer and never re-type; re-type only when nothing reached the screen.
  `PROMPT_RESULT` is always a JSON document (`prompt_not_delivered`, `prompt_unconfirmed` on failure).

## Consequences

- Launch takes a few seconds longer (stability polls). A codex TUI redesign that drops the `›` composer marker
  would make launch wait the full timeout, then still try to prompt (logged as "input not confirmed ready").
- A prompt is never submitted twice by gbb, at the cost of reporting `prompt_unconfirmed` for Grok Bot to
  inspect with `gbb read` in rare ambiguous cases.
- When neither `--` nor `<kind>_args` is given, the agent's own config applies (codex: `~/.codex/config.toml`).
