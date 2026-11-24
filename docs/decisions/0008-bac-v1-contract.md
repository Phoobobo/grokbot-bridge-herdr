# 0008 — Freeze a BotAsCollie v1 contract before implementing it

Date: 2026-11-23 · Status: accepted. The runtime in this tree is `bac` 1.0.0 (`runtime_implemented: true`). The paragraphs below that say the contract was not implemented describe the `ae859908` decision, not the current tree.

## Context

Callers (Grok Bot via the primary webhook, ChatGPT Dot via dots-tunnel-bridge, and a coordinating super-bot) need one breaking identity, CLI `bac`, instead of a permanent `gbb` compatibility shim. The installed baseline is `bbdfc4bbaece3ddafa3a9363b1d0f43b230aa5a6` (`gbb` 0.3.3, PR #2 head). `main` is behind that commit. Dots, at `a4b8e597060da1f3a714bc3b608278c3a2f219b0`, invokes `gbb` by argv and rejects any webhook whose `source` is not `grokbot-bridge-herdr`.

A full rename in the same turn would change the running identity before the bridge and super-bot can move. The contract has to be consumable first.

## Decision

- Freeze BotAsCollie v1 in `docs/bac/v1/CONTRACT.md` and `contracts/bac/v1/`. CLI name `bac` is closed. Other mechanical names are closed in `identity.json`: source `bot-as-collie`, integer callback `version` 1, plugin `phoobobo.bot-as-collie`, config/state/data directory `bot-as-collie`, env prefix `BAC_`, new hc labels `bac=managed` / `bac_task`, agent name `bac-<task>`, tab title `bac · <task>`, new worktree branch `bac/<task>`, MCP tools `bac_*`.
- Do not implement `bac` in this commit. `runtime_implemented` stays false. Do not alias `bac` to `gbb`.
- Do not add a tool surface that drives `hc` except through the future `bac` commands. `hc-watch` stays internal.
- `pane_id` is only the backend id (`hc` `address`, or herdr `root_pane.pane_id`). Missing id is an error with no `pane_id` field. Placement ids `sp…` / `tb…` are not pane ids.
- Kinds verified in `bin/gbb` at the baseline: `codex` and `grok` are supported. `pi` and `antigravity` are explicit rejects. Any other kind is `kind_unsupported` and is never stored as `codex`. Omitted `--kind` is `kind_required` (the baseline defaulted it to `grok`; Dots defaults the Python argument to `codex`).
- Callbacks gain `event_id` (SHA-256 of domain, pane, event, status, generation), `generation`, and `attempt` 1. They still carry no terminal body, and they do not carry model or quota. Owner routing from ADR 0004 stays, including one primary fallback and the extra-webhook mirror. Extras are documented as not an isolation boundary. HTTP 202 is success, matching the Dots no-subscription response.
- Model and quota on CLI status use `observed` / `config` / `unknown` with `observed_at` and freshness. v1 quota is always `unknown`. The Codex footer is an observation, not a guess, and `Context N%` is not a quota.
- Only `bac handover` adopts an existing pane. A different caller owner gets `owner_mismatch` and the registry is not modified. The baseline returned the existing row to any caller.
- An offline fixture migrator may mention `gbb`. It refuses live state directories, preserves owner and pane id, and leaves the source untouched on failure.
- The git repository is not renamed and nothing is published.

## Revision after ae859908

The implementation kept the event_id inputs. Generation is now stored in `event-seq.json` and is not cleared by reclaim or process exit, so a reused pane id does not collide. Delivery is one attempt per target (`attempt` stays 1); owner failure also posts the same `event_id` to the primary, so one logical consumer of both can see two copies and must dedupe. Restart still does not replay an unstamped event. `--owner` is documented as a local label, not authentication. Extras and the primary fallback stay trusted metadata receivers. The Codex `model` key is read only when `BAC_ALLOW_CODEX_CONFIG=1`.

## Consequences

- `install.sh` on this branch installs `bac` and removes a `~/.local/bin/gbb` symlink. It does not install a `gbb` compatibility command. `runtime_implemented` is true.
- Draft PR #3 exists. Its remote head at the time of this note is `2b8d03475b6ef893fc9cdd16d712fe062f41c3ef`. Later local commits are not on that remote until a push. This session does not push.
- Dots must change source check, tool names, argv, the handover pane check, and dedupe in the same cutover, then the operator refreshes tools in ChatGPT. Until both sides are deployed, neither side should be described as working with the other.
- Generation is committed by `bin/bac-lock` while that process holds an fcntl lock. The lock file is not removed or renamed after a pid check. A dead helper or a killed shell releases the lock through process exit, not through pid reclaim. If the lock times out, the helper dies, or the next generation would not be a distinct JSON integer, the command exits non-zero with `ok: false`. It does not send a webhook and does not append a success history row. `flock` is not required. `python3` is required for this isolated candidate. `bac doctor` reports `generation_lock: fcntl`. This is not a production install.
- `bac migrate` still refuses live directories and an existing destination. It does not relabel live hc terminals. That production cutover is still a human step, not something this tool has finished.
- Super-bot's owner name and webhook were not found in a public repository. The coordinator fills those in. Super-bot does not get a private hc client.
- ADR 0004 fallback to the primary webhook remains. That is a trusted-operator path, not a second product identity.

## Alternatives considered

- Keep emitting `source=grokbot-bridge-herdr` so today's bridge keeps working. Rejected: the target is a breaking identity, and a shim would become the compatibility layer this change is not allowed to keep.
- Default omitted kind to grok (baseline) or codex (Dots). Rejected: an omitted kind would be presented as a real agent.
- Put model and quota on the callback. Rejected: extras mirror every callback, and v1 has no quota observation to send.
- Replay webhooks after restart. Rejected: there is no queue. A later revision states the actual guarantee: one attempt per target, a possible second copy on the primary after owner failure, and loss if the process exits before the stamp. Consumers dedupe on `event_id`. That is not an end-to-end at-most-once promise.
- Migrate by rewriting live hc labels inside the fixture tool. Rejected: that touches real sessions. Legacy labels stay on the row so a later watcher can still find them.
