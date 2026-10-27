#!/bin/sh
# Offline test of hook filtering/debounce and webhook POST shape (stubbed herdr, local HTTP sink).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"type\":\"ok\"}}'" >"$T/herdr"; chmod +x "$T/herdr"
export HERDR_BIN_PATH="$T/herdr" GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/none.toml"
mkdir -p "$T/state"
echo '{"version":1,"panes":{"w1:p1":{"pane_id":"w1:p1","workspace_id":"w1","task_id":"t1","agent_name":"gb-t1","kind":"grok","origin":"launched"}}}' >"$T/state/managed.json"
ev() { HERDR_PLUGIN_EVENT=pane.agent_status_changed HERDR_PLUGIN_EVENT_JSON="{\"data\":{\"pane_id\":\"$1\",\"workspace_id\":\"w1\",\"agent_status\":\"$2\",\"agent\":\"grok\"}}" "$ROOT/bin/gbb" hook; }
for s in working done idle working blocked blocked done; do ev w1:p1 $s; done
ev w9:p9 done
sleep 1
n=$(grep -c 'webhook skipped' "$T/state/bridge.log"); d=$(grep -c debounced "$T/state/bridge.log")
echo "notifications=$n (expect 3: done, blocked, done) debounced=$d (expect 2)"
[ "$n" = 3 ] && [ "$d" = 2 ] && echo PASS || { echo FAIL; cat "$T/state/bridge.log"; exit 1; }
rm -rf "$T"
