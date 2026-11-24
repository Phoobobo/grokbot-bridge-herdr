#!/bin/sh
# Modules: probes, config overrides, dots endpoint skipped when the module is off,
# and `gbb report` JSON (no secrets). Other extra webhooks are not gated.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
SINK=""; DOTS=""
cleanup() {
  [ -n "$SINK" ] && kill "$SINK" 2>/dev/null || true
  [ -n "$DOTS" ] && kill "$DOTS" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT
mkdir -p "$T/state" "$T/hits" "$T/bin"
cat >"$T/bin/herdr" <<'H'
#!/bin/sh
case "$1 $2" in
  "status server")
    if [ -f "$HERDR_DOWN" ]; then printf '%s\n' '{"running":false,"status":"not_running"}'; exit 0; fi
    printf '%s\n' '{"running":true,"status":"running"}' ;;
  "agent get") printf '%s\n' '{"result":{"agent":{"agent_status":"done","name":"gb-old"}}}' ;;
  *) printf '%s\n' '{"result":{"type":"ok"}}' ;;
esac
H
cat >"$T/bin/hc" <<'H'
#!/bin/sh
case "$1" in
  server)
    if [ -f "$HC_DOWN" ]; then printf '%s\n' '{"error":"down"}'; exit 1; fi
    printf '%s\n' '{"pid":7,"version":"0.1.16"}' ;;
  get) printf '%s\n' '{"address":"t1","state":"live","status":{"state":"idle","app":"grok"},"reported":true}' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
H
chmod +x "$T/bin/herdr" "$T/bin/hc"
export HERDR_BIN_PATH="$T/bin/herdr" HC_BIN_PATH="$T/bin/hc" HERDR_DOWN="$T/herdr-down" HC_DOWN="$T/hc-down"
export GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/config.toml" GBB_DOTS_TOKEN_FILE="$T/token"
unset GBB_WEBHOOK_URL GBB_WEBHOOK_HEADER_NAME GBB_WEBHOOK_HEADER_VALUE GBB_OWNER GBB_BACKEND GBB_DOTS_PROBE_URL 2>/dev/null || true
fail() { echo "FAIL: $*"; cat "$T/state/bridge.log" 2>/dev/null; exit 1; }

cat >"$T/sink.py" <<'PY'
import http.server, json, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        with open(os.path.join(out, self.path.strip("/") + ".jsonl"), "a") as f:
            f.write(body.decode() + "\n")
        self.send_response(202); self.end_headers()
    def do_GET(self):
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
PY
python3 "$T/sink.py" "$T/hits" >"$T/port" & SINK=$!
i=0; while [ ! -s "$T/port" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
P=$(cat "$T/port")

# Dedicated dots port so the probe and the skip rule use the same host:port.
python3 - <<PY &
import http.server, os
out = "$T/hits"
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("content-length", 0))
        body = self.rfile.read(n)
        with open(os.path.join(out, "dots8765.jsonl"), "a") as f:
            f.write(body.decode() + "\n")
        self.send_response(202); self.end_headers()
    def do_GET(self):
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8765), H).serve_forever()
PY
DOTS=$!
i=0; while ! curl -sS -o /dev/null --connect-timeout 1 --max-time 1 http://127.0.0.1:8765/ 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
curl -sS -o /dev/null --connect-timeout 1 --max-time 1 http://127.0.0.1:8765/ 2>/dev/null || fail "could not bind 127.0.0.1:8765"

echo '{"version":1,"panes":{"w1:p1":{"pane_id":"w1:p1","workspace_id":"w1","task_id":"old","agent_name":"gb-old","kind":"grok","origin":"launched","repo":"/repo","worktree":"/wt","last_status":"idle"},"t1":{"pane_id":"t1","task_id":"new","agent_name":"gb-new","kind":"codex","origin":"launched","backend":"hc","owner":"dot","repo":"/repo","worktree":"/wt-hc","last_status":"working"}}}' >"$T/state/managed.json"

# --- probes off: no token, herdr server down, hc server down ---
printf 'down\n' >"$T/herdr-down"
printf 'down\n' >"$T/hc-down"
cat >"$T/config.toml" <<TOML
webhook_url = "http://127.0.0.1:$P/primary"
webhook_header_name = "X-Primary"
webhook_header_value = "SUPERSECRETTOKEN"
webhook_timeout_sec = 1

[[extra_webhooks]]
url = "http://127.0.0.1:8765/herdr/webhook"
header_name = "X-Dots-Herdr-Token"
header_value = "DOTSSECRETOKEN"

[[extra_webhooks]]
url = "http://127.0.0.1:$P/other"
header_name = "X-Other"
header_value = "OTHERSECRET"
TOML
chmod 600 "$T/config.toml"
rep=$("$ROOT/bin/gbb" report)
printf '%s' "$rep" | grep -q SUPERSECRETTOKEN && fail "report leaked primary secret"
printf '%s' "$rep" | grep -q DOTSSECRETOKEN && fail "report leaked dots secret"
printf '%s' "$rep" | grep -q OTHERSECRET && fail "report leaked other secret"
printf '%s' "$rep" | grep -q '/herdr/webhook' && fail "report included a webhook path"
printf '%s' "$rep" | jq -e --arg p "$P" '
  .ok and .version == "0.3.1" and .backend_default == "auto" and .backend_effective == "none"
  and .hc_watch.running == false
  and ([.modules[] | {id, probe_ok, enabled}] | sort_by(.id)) == (
    [{"id":"core","probe_ok":true,"enabled":true},
     {"id":"dots","probe_ok":false,"enabled":false},
     {"id":"hc","probe_ok":false,"enabled":false},
     {"id":"herdr_tui","probe_ok":false,"enabled":false}] | sort_by(.id))
  and ([.modules[] | select(.id=="dots") | .reason][0] | test("token file missing"))
  and ([.webhooks[] | select(.name=="extra:1")][0].active == false)
  and ([.webhooks[] | select(.name=="extra:1")][0].host == "127.0.0.1:8765")
  and ([.webhooks[] | select(.name=="extra:2")][0].active == true)
  and ([.webhooks[] | select(.name=="extra:2")][0].host == ("127.0.0.1:" + $p))
  and ([.tasks[] | select(.task_id=="old")][0] | .backend=="herdr" and .alive==false and .stale==true and .repo=="/repo" and .worktree=="/wt")
  and ([.tasks[] | select(.task_id=="new")][0] | .backend=="hc" and .owner=="dot" and .pane_id=="t1" and .alive==false and .stale==true)
' >/dev/null || fail "report shape off: $rep"
doc=$("$ROOT/bin/gbb" doctor)
printf '%s' "$doc" | grep -q SUPERSECRETTOKEN && fail "doctor leaked a secret"
printf '%s' "$doc" | jq -e '[.modules[].id] | sort == ["core","dots","hc","herdr_tui"]' >/dev/null || fail "doctor modules: $doc"
printf '%s' "$doc" | jq -e '.modules[] | select(.id=="herdr_tui") | .enabled==false and (.reason|test("not running"))' >/dev/null || fail "doctor herdr reason"

# Dots endpoint is not contacted; the other extra and the primary are.
rm -f "$T/hits"/*
HERDR_PLUGIN_EVENT=pane.agent_status_changed \
  HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w1:p1","agent_status":"done"}}' \
  "$ROOT/bin/gbb" hook
i=0; while { [ ! -f "$T/hits/primary.jsonl" ] || [ ! -f "$T/hits/other.jsonl" ]; } && [ "$i" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done
[ -f "$T/hits/primary.jsonl" ] || fail "primary not delivered while dots is off"
[ -f "$T/hits/other.jsonl" ] || fail "non-dots extra was gated: $(ls "$T/hits" 2>/dev/null)"
[ ! -f "$T/hits/dots8765.jsonl" ] || fail "dots endpoint was contacted while the module is off"
grep -q 'dots module off' "$T/state/bridge.log" || fail "skip not logged"

# --- probes on ---
rm -f "$T/herdr-down" "$T/hc-down"
printf 'token\n' >"$T/token"; chmod 600 "$T/token"
rep=$("$ROOT/bin/gbb" report)
printf '%s' "$rep" | jq -e '
  ([.modules[] | select(.id=="herdr_tui")][0].probe_ok == true)
  and ([.modules[] | select(.id=="hc")][0].probe_ok == true)
  and ([.modules[] | select(.id=="dots")][0].probe_ok == true)
  and ([.modules[] | select(.id=="dots")][0].enabled == true)
  and .backend_effective == "hc"
  and ([.tasks[] | select(.task_id=="old")][0] | .alive==true and .stale==false and .status=="done")
  and ([.tasks[] | select(.task_id=="new")][0] | .alive==true and .stale==false and .status=="idle")
  and ([.webhooks[] | select(.name=="extra:1")][0].active == true)
' >/dev/null || fail "probes on: $rep"
rm -f "$T/hits"/*
HERDR_PLUGIN_EVENT=pane.agent_status_changed \
  HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w1:p1","agent_status":"blocked"}}' \
  "$ROOT/bin/gbb" hook
i=0; while [ ! -f "$T/hits/dots8765.jsonl" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
[ -f "$T/hits/dots8765.jsonl" ] || fail "dots endpoint not used when the probe passes"

# --- enabled = false overrides a passing dots probe ---
cat >>"$T/config.toml" <<'TOML'

[modules.dots]
enabled = false
TOML
rm -f "$T/hits"/*
HERDR_PLUGIN_EVENT=pane.agent_status_changed \
  HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w1:p1","agent_status":"done"}}' \
  "$ROOT/bin/gbb" hook
sleep 1
[ -f "$T/hits/primary.jsonl" ] || fail "primary missing under enabled=false"
[ ! -f "$T/hits/dots8765.jsonl" ] || fail "enabled=false still delivered to dots"
"$ROOT/bin/gbb" report | jq -e '.modules[] | select(.id=="dots") | .config==false and .enabled==false and .probe_ok==true' >/dev/null || fail "override false"

# --- enabled = true forces hc on even when the server probe fails; herdr_tui forced off ---
printf 'down\n' >"$T/hc-down"
cat >"$T/config.toml" <<TOML
webhook_url = "http://127.0.0.1:$P/primary"
webhook_header_value = "SUPERSECRETTOKEN"
webhook_timeout_sec = 1

[modules.hc]
enabled = true

[modules.herdr_tui]
enabled = false
TOML
chmod 600 "$T/config.toml"
"$ROOT/bin/gbb" report | jq -e '
  ([.modules[] | select(.id=="hc")][0] | .config==true and .enabled==true and .probe_ok==false)
  and ([.modules[] | select(.id=="herdr_tui")][0] | .config==false and .enabled==false and .probe_ok==true)
  and .backend_effective == "hc"
' >/dev/null || fail "force overrides"
printf '%s' "$("$ROOT/bin/gbb" report)" | grep -q SUPERSECRETTOKEN && fail "report leaked after override"

# enabled=true forces dots delivery even when the token file (probe) is missing.
rm -f "$T/token" "$T/hits"/*
cat >"$T/config.toml" <<TOML
webhook_url = "http://127.0.0.1:$P/primary"
webhook_header_value = "SUPERSECRETTOKEN"
webhook_timeout_sec = 1

[[extra_webhooks]]
url = "http://127.0.0.1:8765/herdr/webhook"
header_name = "X-Dots-Herdr-Token"
header_value = "DOTSSECRETOKEN"

[modules.dots]
enabled = true
TOML
chmod 600 "$T/config.toml"
HERDR_PLUGIN_EVENT=pane.agent_status_changed \
  HERDR_PLUGIN_EVENT_JSON='{"data":{"pane_id":"w1:p1","agent_status":"blocked"}}' \
  "$ROOT/bin/gbb" hook
i=0; while [ ! -f "$T/hits/dots8765.jsonl" ] && [ "$i" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done
[ -f "$T/hits/dots8765.jsonl" ] || fail "enabled=true did not deliver when the probe failed"
"$ROOT/bin/gbb" report | jq -e '.modules[] | select(.id=="dots") | .config==true and .enabled==true and .probe_ok==false' >/dev/null || fail "force dots on"
printf '%s' "$("$ROOT/bin/gbb" report)" | grep -q DOTSSECRETOKEN && fail "report leaked dots secret"
echo PASS
