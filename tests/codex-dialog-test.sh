#!/bin/sh
# Pure screen classification using observed 0.172 folder-access text.
# No agent, backend, network, lock or failure probe is started.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
sed -n '/^classify_text() {/,/^screen_state()/p' "$ROOT/bin/bac" | sed '$d' >"$T/classify.sh"
. "$T/classify.sh"
trust='Folder access
/tmp/scratch
Trust this folder? Codex can read, edit, and run files here.
› 1. Trust and continue
  2. Back to Agent Command Center
enter continue · esc back'
[ "$(printf '%s\n' "$trust" | classify_text)" = dialog ]
continue_dialog='Choose an option
› 1. Continue
  2. Back
enter continue · esc back'
[ "$(printf '%s\n' "$continue_dialog" | classify_text)" = dialog ]
ready='› Ask Codex to do anything
GPT-6.1-Sol low · /tmp/scratch
← for agents · ? for shortcuts'
[ "$(printf '%s\n' "$ready" | classify_text)" = ready ]
hooks='Hooks need review
› 1. Review hooks
enter confirm'
[ "$(printf '%s\n' "$hooks" | classify_text)" = hooks_review ]
echo PASS
