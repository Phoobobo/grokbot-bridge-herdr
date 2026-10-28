#!/bin/sh
# Offline test of prompt_with_retry (gbb send) with a stubbed herdr:
#  1. herdr always reports agent_prompt_stalled and the text never reaches the screen
#     -> ok:false, error.code prompt_not_delivered, no "unbound variable" (regression for PROMPT_RESULT).
#  2. stalled, but the text sits in the composer -> gbb presses Enter once, agent starts working -> ok:true,
#     and the prompt is not typed a second time.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
cat >"$T/herdr" <<'H'
#!/bin/sh
S="$STUB_DIR"
case "$1 $2" in
  "agent prompt") echo prompt >>"$S/calls"
    [ "$(cat "$S/mode")" = composer ] && printf '› %s\n' "$4" >"$S/screen"
    echo '{"error":{"code":"agent_prompt_stalled","message":"stalled"}}' >&2; exit 1 ;;
  "agent send-keys") echo "keys $4" >>"$S/calls"; echo working >"$S/status"; echo '{"result":{"type":"ok"}}' ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(cat "$S/status")" ;;
  "pane read") cat "$S/screen" ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
H
chmod +x "$T/herdr"
export HERDR_BIN_PATH="$T/herdr" GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/c.toml" STUB_DIR="$T"
printf 'startup_ready_timeout_sec = 3\n' >"$T/c.toml"
mkdir -p "$T/state"
reset() {
  echo '{"version":1,"panes":{"w1:p1":{"pane_id":"w1:p1","workspace_id":"w1","task_id":"t1","agent_name":"gb-t1","kind":"codex","origin":"launched"}}}' >"$T/state/managed.json"
  echo idle >"$T/status"; printf '› Ask Codex to do anything\n' >"$T/screen"; : >"$T/calls"; echo "$1" >"$T/mode"
}
fail=0
reset dropped
out=$("$ROOT/bin/gbb" send t1 "hello there" 2>"$T/err")
echo "dropped:  $out"
printf '%s' "$out" | jq -e '.ok == false and .error.code == "prompt_not_delivered"' >/dev/null || fail=1
grep -q unbound "$T/err" && { echo "stderr: $(cat "$T/err")"; fail=1; }
reset composer
out=$("$ROOT/bin/gbb" send t1 "hello there" 2>"$T/err")
echo "composer: $out  calls: $(tr '\n' ' ' <"$T/calls")"
printf '%s' "$out" | jq -e '.ok == true' >/dev/null || fail=1
[ "$(grep -c prompt "$T/calls")" = 1 ] && grep -q 'keys enter' "$T/calls" || fail=1
[ "$fail" = 0 ] && echo PASS || { echo FAIL; cat "$T/state/bridge.log"; exit 1; }
rm -rf "$T"
