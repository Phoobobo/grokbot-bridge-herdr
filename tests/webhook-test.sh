#!/bin/sh
# Offline test: primary webhook + [[extra_webhooks]] get the same payload (except the route tag) and their own header.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
trap 'kill $SINK 2>/dev/null || true; wait $SINK 2>/dev/null || true; rm -rf "$T"' EXIT
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"type\":\"ok\"}}'" >"$T/herdr"; chmod +x "$T/herdr"
export HERDR_BIN_PATH="$T/herdr" GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/config.toml"
unset GBB_WEBHOOK_URL GBB_WEBHOOK_HEADER_NAME GBB_WEBHOOK_HEADER_VALUE 2>/dev/null || true
mkdir -p "$T/state" "$T/hits"
cat >"$T/sink.py" <<'PY'
import http.server, json, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        rec = {"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body.decode()}
        with open(os.path.join(out, self.path.strip("/") + ".json"), "w") as f:
            json.dump(rec, f)
        self.send_response(202); self.end_headers()
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

[[extra_webhooks]]
url = "ftp://nope/x"

[other]
url = "http://127.0.0.1:$P/not-a-webhook"
TOML
chmod 600 "$T/config.toml"
fail() { echo "FAIL: $*"; cat "$T/state/bridge.log" 2>/dev/null; exit 1; }

doc=$("$ROOT/bin/gbb" doctor)
[ "$(printf '%s' "$doc" | jq -c .config.extra_webhooks)" = '{"count":2,"hosts":["127.0.0.1:'"$P"'","nope"]}' ] || fail "doctor: $doc"
printf '%s' "$doc" | grep -q secret && fail "doctor leaked a secret"

"$ROOT/bin/gbb" test-webhook >"$T/tw.json"
grep -q secret "$T/tw.json" "$T/state/bridge.log" && fail "secret in output/log"
[ -f "$T/hits/primary.json" ] && [ -f "$T/hits/dots.json" ] || fail "missing deliveries: $(ls "$T/hits")"
[ ! -f "$T/hits/not-a-webhook.json" ] || fail "[other] table treated as webhook"
[ "$(jq -r .body "$T/hits/primary.json" | jq -c 'del(.route)')" = "$(jq -r .body "$T/hits/dots.json" | jq -c 'del(.route)')" ] || fail "payloads differ"
[ "$(jq -r .body "$T/hits/primary.json" | jq -r .route)" = primary ] || fail "primary route tag"
[ "$(jq -r .body "$T/hits/dots.json" | jq -r .route)" = extra ] || fail "extra route tag"
[ "$(jq -r '.headers["x-primary"]' "$T/hits/primary.json")" = primary-secret ] || fail "primary header"
[ "$(jq -r '.headers["x-dots-herdr-token"] // "none"' "$T/hits/primary.json")" = none ] || fail "dots header leaked to primary"
[ "$(jq -r '.headers["x-dots-herdr-token"]' "$T/hits/dots.json")" = dots-secret ] || fail "extra header"
[ "$(jq -r '.headers["x-primary"] // "none"' "$T/hits/dots.json")" = none ] || fail "primary header leaked to extra"
[ "$(jq -r .body "$T/hits/dots.json" | jq -r .source)" = grokbot-bridge-herdr ] || fail "payload source"
grep -q 'webhook\[x2\] skipped' "$T/state/bridge.log" || fail "bad url not skipped"
[ "$(jq '.recent_webhook_logs|length' "$T/tw.json")" -ge 2 ] || fail "test-webhook logs"

# Insecure config mode: nothing is sent to either target.
rm -f "$T/hits"/*; chmod 644 "$T/config.toml"
"$ROOT/bin/gbb" test-webhook >/dev/null
[ -z "$(ls "$T/hits")" ] || fail "sent with mode 644"
echo PASS
