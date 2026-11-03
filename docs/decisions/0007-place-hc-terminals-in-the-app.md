# 0007 — put hc terminals in the Herdr app

Date: 2026-11-03 · Status: accepted

## Context

`gbb launch` on hc ran `hc run` with only `grokbot=managed` and `gbb_task`. Those terminals stay out of the Herdr app. The app shows a core terminal when it carries `herdr.space` (and, if set, `herdr.tab`). Checked in herdr-app's agent guide (`herdr-app --skill` / `defaults/AGENTS.md`) and in `adopt()` (`src/window.rs`):

- `herdr.space=<id>` opts the terminal into that space. An id the app does not know becomes a new space.
- `herdr.tab` omitted, or an id the app does not know, becomes a new tab. An id of a tab that already exists splits a pane into that tab.
- Adoption also turns on core `keep`. `hc kill` / a normal exit still end the program (`keep` only replaces a lost one).
- `herdr-app ls` is the window's list of spaces (id, name, folder, machine, tabs, terminal addresses). `hc ls --json` has launch `cwd` but not labels; `hc get` has `labels`.
- A space's repo is the git common dir of its folder or of a terminal launched there. A linked worktree shares that dir with the main checkout. An unnamed space is displayed as the directory of its first terminal's checkout.

The user's Herdr.app 0.9.5 / hc 0.1.17 already behaved this way for a hand-applied label (`hc ls` gained `where`). This note is the app's documented mechanism, not a guessed label.

## Decision

- On hc launch, and on handover of a terminal that has no `herdr.space` yet, set `herdr.space` and do not set `herdr.tab`. Also pass `--keep` on `hc run`.
- Choose the space from `herdr-app ls` when the window answers: local spaces only (`machine` null). Prefer one whose folder, or a terminal's launch cwd, is the same git repo; otherwise the one display name that equals the repo directory. Ties prefer the space the app is showing.
- If the window does not answer, `hc get` a terminal whose launch cwd is that repo and read `labels["herdr.space"]`.
- Otherwise mint `sp` + 32 hex. The app creates the space on its next reconcile. When the window did answer, `herdr-app do space.rename` names it after the repo directory (best-effort, a few retries). Launch does not call `space.select`; adoption does not steal focus.
- Registry and launch JSON record `herdr_space` and `created_herdr_space`. `workspace_id` stays null on hc, and webhook fields do not change.
- `gbb stop` still only kills and removes terminals this launch created. It does not call `space.close` or `tab.close`. The app removes the pane when the terminal ends, and drops a space when that was its last tab. Handover never kills, and a terminal that already had `herdr.space` is left in that space. Reclaim removes `grokbot` / `gbb_task` only.

## Alternatives rejected

- `herdr-app do space.new` / `tab.new --argv` to start the agent. The app wraps it in an interactive shell and appends `task` as an argv word. gbb delivers the prompt with `hc send` after the composer is up, and a shell tab created only to obtain an id races `tab.close` (closing the last tab closes the space).
- Copy `herdr.tab` from an existing tab. That splits into the user's current tab.
- Write the layout with `doc.set` (`name` `herdr-app`). That call is not an `hc` subcommand, and it races the open window.

## Consequences

- A launch is visible in the Herdr app without `hc attach`, in the repo's space, on its own tab. The next launch for that repo reuses the space, including when the agent cwd is a worktree.
- With the window closed, a brand-new space keeps Herdr's automatic name (the folder the terminal started in) until the app is open for the rename. The id is already on the terminal, so opening the app adopts it.
- Two spaces can share a display name. A folder or cwd match wins over the name. If only the name matches, that space is used.
- Not run against a live Herdr.app in this change. The offline test stubs `hc` and `herdr-app`.
