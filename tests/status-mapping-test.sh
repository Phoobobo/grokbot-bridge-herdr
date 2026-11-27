#!/bin/sh
# Pure status mapping with stubbed observation/delivery; no locks or backend.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# Load only this production function; never run the bac CLI initializer.
sed -n '/^hc_emit_word() {/,/^hc_baseline_terminal()/p' "$ROOT/bin/bac" | sed '$d' >"$T/function.sh"
. "$T/function.sh"
export LAST_DIR=$T
now() { printf 1; }
note_seen() { printf '%s\n' "$2" >"$T/seen"; }
remember_status() { printf '%s\n' "$2" >"$1"; }
log() { :; }
deliver_status() { printf '%s\n' "$4" >"$T/delivered"; }
entry='{"kind":"grok","armed":true}'
for status in done idle blocked error; do
  hc_emit_word t-fixture "$entry" "$status" '{}'
  want=$status
  [ "$status" != error ] || want=blocked
  [ "$(cat "$T/delivered")" = "$want" ]
done
rm "$T/delivered"
for status in working unknown; do
  hc_emit_word t-fixture "$entry" "$status" '{}'
  [ ! -e "$T/delivered" ]
  [ "$(cat "$T/seen")" = "$status" ]
done
echo PASS
