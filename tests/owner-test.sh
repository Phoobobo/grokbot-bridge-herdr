#!/bin/sh
# Offline test of owner-routed callbacks (docs/decisions/0004) with a local HTTP sink:
#  owner with a target -> only that target (+ extras), owner target == an extra URL -> delivered once,
#  owner delivery fails -> primary with route "fallback", unknown owner / no owner -> primary,
#  hook events carry the registry owner, gbb owner reassigns, doctor never prints secrets.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
trap 'kill $SINK 2>/dev/null || true; wait $SINK 2>/dev/null || true; rm -rf "$T"' EXIT
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"type\":\"ok\"}}'" >"$T/herdr"; chmod +x "$T/herdr"
export HERDR_BIN_PATH="$T/herdr" GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/config.toml"
unset GBB_WEBHOOK_URL GBB_WEBHOOK_HEADER_NAME GBB_WEBHOOK_HEADER_VALUE GBB_OWNER 2>/dev/null || true
mkdir -p "$T/state" "$T/hits"
cat >"$T/sink.py" <<'PY'
import http.server, json, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        rec = {"headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(body)}
        with open(os.path.join(out, self.path.strip("/") + ".jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
        self.send_response(500 if self.path == "/broken" else 202); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
PY
python3 "$T/sink.py" "$T/hits" >"$T/port" & SINK=$!
i=0; while [ ! -s "$T/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
P=$(cat "$T/port")
cat >"$T/config.toml" <<TOML
webhook_url = "http://127.0.0.1:$P/primary"
webhook_header_name = "X-Primary"
webhook_header_value = "primary-secret"
webhook_timeout_sec = 1

[[extra_webhooks]]
url = "http://127.0.0.1:$P/dots"
header_name = "X-Dots-Herdr-Token"
header_value = "dots-secret"

[[owners]]
name = "dot"
url = "http://127.0.0.1:$P/dots"
header_name = "X-Dots-Herdr-Token"
header_value = "dots-secret"

[[owners]]
name = "boss"
url = "http://127.0.0.1:$P/boss"
header_name = "X-Boss"
header_value = "boss-secret"

[owners.broken]
url = "http://127.0.0.1:$P/broken"
header_name = "X-Broken"
header_value = "broken-secret"
TOML
chmod 600 "$T/config.toml"
fail() { echo "FAIL: $*"; ls -l "$T/hits"; cat "$T/state/bridge.log" 2>/dev/null; exit 1; }
hits() { [ -f "$T/hits/$1.jsonl" ] && grep -c . "$T/hits/$1.jsonl" || echo 0; }
body() { tail -n 1 "$T/hits/$1.jsonl" | jq -c .body; }
clear_hits() { rm -f "$T/hits"/*; }
tw() { "$ROOT/bin/gbb" test-webhook "$@" >"$T/tw.json"; }

doc=$("$ROOT/bin/gbb" doctor)
[ "$(printf '%s' "$doc" | jq -c '[.config.owners[].name]')" = '["dot","boss","broken"]' ] || fail "doctor owners: $doc"
printf '%s' "$doc" | jq -e '.config.owners | all(.header_value_set)' >/dev/null || fail "doctor header_value_set"
printf '%s' "$doc" | grep -q secret && fail "doctor leaked a secret"

# 1. owner with its own target: owner target + extra, not primary.
tw --owner boss
[ "$(hits boss)" = 1 ] && [ "$(hits primary)" = 0 ] && [ "$(hits dots)" = 1 ] || fail "boss routing"
[ "$(body boss | jq -r '.owner + "/" + .route')" = boss/owner ] || fail "boss payload $(body boss)"
[ "$(tail -n 1 "$T/hits/boss.jsonl" | jq -r '.headers["x-boss"]')" = boss-secret ] || fail "boss header"
[ "$(tail -n 1 "$T/hits/boss.jsonl" | jq -r '.headers["x-primary"] // "none"')" = none ] || fail "primary header leaked to owner"
clear_hits

# 2. owner target is also an extra: delivered once (route owner), primary untouched.
tw --owner dot
[ "$(hits dots)" = 1 ] && [ "$(hits primary)" = 0 ] || fail "dot dedupe: dots=$(hits dots) primary=$(hits primary)"
[ "$(body dots | jq -r .route)" = owner ] || fail "dot route"
grep -q 'same target as the owner route' "$T/state/bridge.log" || fail "dedupe log"
clear_hits

# 3. owner delivery fails (HTTP 500) -> primary gets it with route fallback.
tw --owner broken
[ "$(hits broken)" = 1 ] && [ "$(hits primary)" = 1 ] || fail "fallback on failure"
[ "$(body primary | jq -r '.route + "/" + .fallback_reason + "/" + .owner')" = fallback/owner_delivery_failed/broken ] || fail "fallback payload $(body primary)"
clear_hits

# 4. unknown owner -> primary (fallback, owner_not_configured); 5. no owner -> primary (route primary).
tw --owner nobody
[ "$(body primary | jq -r '.route + "/" + .fallback_reason')" = fallback/owner_not_configured ] || fail "unknown owner"
clear_hits
tw
[ "$(hits primary)" = 1 ] && [ "$(body primary | jq -r '.route + "/" + (.owner // "null")')" = primary/null ] || fail "no owner"
clear_hits
"$ROOT/bin/gbb" test-webhook --owner 'bad name!' >/dev/null 2>&1 && fail "invalid owner accepted"

# 6. hook events carry the registry owner; gbb owner reassigns / clears it.
echo '{"version":1,"panes":{"w1:p1":{"pane_id":"w1:p1","workspace_id":"w1","task_id":"t1","agent_name":"gb-t1","kind":"grok","origin":"launched","armed":true,"owner":"boss"}}}' >"$T/state/managed.json"
ev() { HERDR_PLUGIN_EVENT=pane.agent_status_changed HERDR_PLUGIN_EVENT_JSON="{\"data\":{\"pane_id\":\"w1:p1\",\"agent_status\":\"$1\"}}" "$ROOT/bin/gbb" hook; }
ev "done"; sleep 2
[ "$(hits boss)" = 1 ] && [ "$(hits primary)" = 0 ] && [ "$(body boss | jq -r '.status + "/" + .owner')" = done/boss ] || fail "hook owner route"
o=$("$ROOT/bin/gbb" owner t1 nobody)
[ "$(printf '%s' "$o" | jq -r '.route + "/" + .fallback_reason')" = fallback/owner_not_configured ] || fail "gbb owner: $o"
o=$("$ROOT/bin/gbb" owner t1 --clear)
[ "$(printf '%s' "$o" | jq -r '.route + "/" + (.owner // "null")')" = primary/null ] || fail "gbb owner --clear: $o"
[ "$("$ROOT/bin/gbb" list | jq -r '.managed[0].owner // "null"')" = null ] || fail "list owner"
grep -q secret "$T/state/bridge.log" && fail "secret in log"
echo PASS
