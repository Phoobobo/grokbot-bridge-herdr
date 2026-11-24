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

- On hc launch, and on handover of a terminal that has no `herdr.space` yet, set `herdr.space`. Also pass `--keep` on `hc run`. The hc `--name` stays `gb-<task>` (`a-z`, `0-9`, `-`, `_` only).
- Set `herdr.tab` to an id gbb minted (`tb` + 32 hex). An id the app does not know becomes a new tab, so this does not split an existing one. When the window answers, `tab.rename` titles that tab `gbb · <task>`. A handover whose terminal already has `herdr.tab` keeps that tab and is not renamed. gbb does not rename a space or tab it did not mint.
- Choose the space from `herdr-app ls` when the window answers: local spaces only (`machine` null). The space `folder` field is ignored; Herdr leaves it stale. A terminal launched in the main checkout ranks above one launched in a gbb worktree of that repo (`$WORKTREE_ROOT/<dirname>-<task>`), which ranks above a space whose display name is the repo directory. The same rank prefers that name, then the space the app is showing. Another worktree of the same repo (a Herdr worktree, a `.worktrees/` checkout) does not match.
- If the window does not answer, `hc get` a terminal launched in the main checkout or a gbb worktree and read `labels["herdr.space"]`. A different worktree is skipped.
- Otherwise mint `sp` + 32 hex. The app creates the space on its next reconcile. When the window did answer, `herdr-app do space.rename` names it after the repo directory (best-effort, a few retries). Launch does not call `space.select`; adoption does not steal focus.
- Registry and launch JSON record `herdr_space` and `created_herdr_space`. `workspace_id` stays null on hc, and webhook fields do not change.
- `gbb stop` still only kills and removes terminals this launch created. It does not call `space.close` or `tab.close`. The app removes the pane when the terminal ends, and drops a space when that was its last tab. Handover never kills, and a terminal that already had `herdr.space` is left in that space. Reclaim removes `grokbot` / `gbb_task` only.

## Alternatives rejected

- `herdr-app do space.new` / `tab.new --argv` to start the agent. The app wraps it in an interactive shell and appends `task` as an argv word. gbb delivers the prompt with `hc send` after the composer is up, and a shell tab created only to obtain an id races `tab.close` (closing the last tab closes the space).
- Copy `herdr.tab` from an existing tab. That splits into the user's current tab.
- Write the layout with `doc.set` (`name` `herdr-app`). That call is not an `hc` subcommand, and it races the open window.

## Consequences

- A launch is visible in the Herdr app without `hc attach`, in the repo's space, on its own tab titled `gbb · <task>`. The next launch for that repo reuses the space, including when the agent cwd is a gbb worktree. The hc name stays `gb-<task>`.
- With the window closed, a brand-new space keeps Herdr's automatic name (the folder the terminal started in) until the app is open for the rename. The id is already on the terminal, so opening the app adopts it.
- Two spaces can share a launch directory. The one named after the repo directory wins that tie; with neither named, the space the app is showing wins. A space whose only signal is a stale `folder`, or a terminal in a different worktree, is not used. If nothing matches, a new space is created.
- Not run against a live Herdr.app in this change. The offline test stubs `hc` and `herdr-app`.
