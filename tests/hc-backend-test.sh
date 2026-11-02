#!/bin/sh
# Offline tests for the herdr-core (hc) backend:
#   command construction (hc run / send / keys, no --force),
#   backend selection (auto stays on herdr when both exist; config and --backend override;
#   auto uses hc when herdr is absent),
#   a pre-0.3.0 registry row still talks to herdr even if config says hc,
#   hc events -> the same webhook payload (owner route, no OSC message text),
#   working suppressed, done->idle debounced, error mapped to blocked,
#   finished drops the row, and an unreported Codex screen still yields blocked.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
SINK=""
cleanup() {
  if [ -n "${GBB_STATE_DIR:-}" ] && [ -f "$GBB_STATE_DIR/hc-watch.pid" ]; then
    kill "$(cat "$GBB_STATE_DIR/hc-watch.pid")" 2>/dev/null || true
  fi
  [ -n "$SINK" ] && kill "$SINK" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT
mkdir -p "$T/bin" "$T/state" "$T/data" "$T/hc-calls" "$T/herdr-calls" "$T/hits" "$T/repo"
cat >"$T/bin/hc" <<'H'
#!/bin/sh
d=$(mktemp "$STUB_DIR/call.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
case "$1" in
  run) printf '%s\n' '{"address":"t9","name":"n","state":"live","turn":0}' ;;
  get) printf '%s\n' '{"address":"t9","name":"gb","state":"live","status":{"state":"idle","app":"grok"},"reported":true,"cwd":"/tmp","turn":0,"title":"","labels":{}}' ;;
  send) printf '%s\n' '{"started":true,"status":"working","turn":1}' ;;
  read) cat "$STUB_DIR/screen" ;;
  events) [ -f "$STUB_DIR/events.jsonl" ] && cat "$STUB_DIR/events.jsonl" ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
H
cat >"$T/bin/herdr" <<'H'
#!/bin/sh
d=$(mktemp "$HERDR_STUB/call.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
case "$1 $2" in
  "workspace create") printf '%s\n' '{"result":{"root_pane":{"pane_id":"w1:p1"},"workspace":{"workspace_id":"w1"}}}' ;;
  "agent start") printf '%s\n' '{"result":{"agent":{"agent_status":"idle","name":"gb"}}}' ;;
  "agent get") printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent prompt") printf '%s\n' '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "pane read") printf '%s\n' 'ready' ;;
  *) printf '%s\n' '{"result":{"type":"ok"}}' ;;
esac
H
chmod +x "$T/bin/hc" "$T/bin/herdr"
printf '%s\n' '› Ask Codex to do anything' 'GPT-6.1-Sol xhigh · ~/x · Context 7% used · 12k in · 2k out' >"$T/screen"
export HERDR_BIN_PATH="$T/bin/herdr" HC_BIN_PATH="$T/bin/hc" STUB_DIR="$T" HERDR_STUB="$T/herdr-calls"
export GBB_STATE_DIR="$T/state" GBB_DATA_DIR="$T/data" GBB_CONFIG="$T/config.toml" GBB_HC_WATCH_ONCE=1
unset GBB_WEBHOOK_URL GBB_WEBHOOK_HEADER_NAME GBB_WEBHOOK_HEADER_VALUE GBB_OWNER GBB_BACKEND 2>/dev/null || true
git -C "$T/repo" init -q
git -C "$T/repo" config user.email t@example.com
git -C "$T/repo" config user.name t
echo x >"$T/repo/f" && git -C "$T/repo" add f && git -C "$T/repo" commit -qm init
fail() { echo "FAIL: $*"; echo "--- hc calls ---"; cat "$T"/call.* 2>/dev/null || true; echo "--- herdr calls ---"; cat "$T/herdr-calls"/call.* 2>/dev/null || true; echo "--- log ---"; cat "$T/state/bridge.log" 2>/dev/null || true; exit 1; }
reset_calls() { rm -f "$T"/call.* "$T/herdr-calls"/call.*; }
hc_runs() { cat "$T"/call.* 2>/dev/null | jq -s 'map(select(.[0]=="run"))'; }
herdr_cmds() { cat "$T/herdr-calls"/call.* 2>/dev/null | jq -s 'map(.[0] + " " + (.[1] // ""))'; }

# --- auto with both binaries stays on the TUI (no hc run) ---
cat >"$T/config.toml" <<'TOML'
startup_settle_sec = 0
startup_ready_timeout_sec = 8
webhook_timeout_sec = 1
debounce_sec = 0
TOML
chmod 600 "$T/config.toml"
reset_calls
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task auto1 --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.ok == true and .backend == "herdr" and .pane_id == "w1:p1"' >/dev/null || fail "auto launch: $out"
[ "$(hc_runs | jq 'length')" = 0 ] || fail "auto called hc run: $(hc_runs)"
printf '%s' "$(herdr_cmds)" | jq -e 'index("workspace create") != null' >/dev/null || fail "auto did not create a herdr workspace: $(herdr_cmds)"
[ "$("$ROOT/bin/gbb" list | jq -r '.managed[0].backend')" = herdr ] || fail "auto registry backend"

# --- config backend=hc, and --backend herdr overrides it ---
cat >"$T/config.toml" <<'TOML'
backend = "hc"
startup_settle_sec = 0
startup_ready_timeout_sec = 8
webhook_timeout_sec = 1
debounce_sec = 0
codex_args = ["-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=\"xhigh\""]
TOML
chmod 600 "$T/config.toml"
reset_calls
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind codex --task pin --prompt "review it" --owner boss)
printf '%s' "$out" | jq -e '.ok == true and .backend == "hc" and .pane_id == "t9" and .owner == "boss"' >/dev/null || fail "hc launch: $out"
wt=$(printf '%s' "$out" | jq -r .worktree)
run=$(hc_runs | jq -c '.[0]')
printf '%s' "$run" | jq -e --arg wt "$wt" '
  .[0]=="run" and .[1]=="--bg" and .[2]=="--json" and index("--no-parent") and index("--no-notify")
  and index("grokbot=managed") and index("gbb_task=pin") and index("--cwd") and (.[index("--cwd")+1] == $wt)
  and (.[index("--")+1] == "codex") and index("-m") and index("gpt-6.1-sol")
  and index("model_reasoning_effort=\"xhigh\"")' >/dev/null || fail "hc run argv: $run"
printf '%s' "$(herdr_cmds)" | jq -e 'index("workspace create") == null' >/dev/null || fail "hc launch called herdr: $(herdr_cmds)"
[ "$("$ROOT/bin/gbb" list | jq -r '[.managed[] | select(.task_id=="pin")][0].backend')" = hc ] || fail "pin registry backend"
reset_calls
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task back --prompt "hi" --backend herdr --no-worktree)
printf '%s' "$out" | jq -e '.backend == "herdr"' >/dev/null || fail "--backend herdr: $out"
[ "$(hc_runs | jq 'length')" = 0 ] || fail "--backend herdr still ran hc"

# --- auto with no herdr uses hc ---
export HERDR_BIN_PATH="$T/bin/no-herdr"
reset_calls
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task onlyhc --prompt "hi" --backend auto)
printf '%s' "$out" | jq -e '.ok == true and .backend == "hc"' >/dev/null || fail "auto-only-hc: $out"
printf '%s' "$(hc_runs | jq -c '.[0]')" | jq -e '(.[index("--")+1] == "grok")' >/dev/null || fail "onlyhc argv: $(hc_runs)"
export HERDR_BIN_PATH="$T/bin/herdr"

# --- commands against an hc row, and a legacy row that must ignore config backend=hc ---
reset_calls
echo '{"version":1,"panes":{"t9":{"pane_id":"t9","task_id":"s1","agent_name":"gb-s1","kind":"grok","origin":"launched","backend":"hc","armed":true},"w9:p9":{"pane_id":"w9:p9","workspace_id":"w9","task_id":"old","agent_name":"gb-old","kind":"grok","origin":"launched","armed":true}}}' >"$T/state/managed.json"
send=$("$ROOT/bin/gbb" send s1 "hello there")
printf '%s' "$send" | jq -e '.ok == true and .pane_id == "t9"' >/dev/null || fail "hc send: $send"
cat "$T"/call.* | jq -s -e 'map(select(.[0]=="send")) | .[0] == ["send","--json","t9","--","hello there"]' >/dev/null || fail "send argv: $(cat "$T"/call.* | jq -s 'map(select(.[0]=="send"))')"
cat "$T"/call.* | jq -s -e 'all(.[]; index("--force") | not) and all(.[]; index("force") | not)' >/dev/null || fail "send used --force"
reset_calls
keys=$("$ROOT/bin/gbb" keys s1 enter)
printf '%s' "$keys" | jq -e '.ok == true' >/dev/null || fail "hc keys: $keys"
cat "$T"/call.* | jq -s -e 'map(select(.[0]=="keys")) | .[0] == ["keys","--json","t9","enter"]' >/dev/null || fail "keys argv"
reset_calls
"$ROOT/bin/gbb" status old >/dev/null || fail "legacy status failed"
[ -z "$(ls "$T"/call.* 2>/dev/null || true)" ] || fail "legacy status called hc: $(cat "$T"/call.*)"
printf '%s' "$(herdr_cmds)" | jq -e 'index("agent get") != null' >/dev/null || fail "legacy status did not call herdr: $(herdr_cmds)"

# --- events -> webhooks ---
cat >"$T/sink.py" <<'PY'
import http.server, json, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        rec = {"path": self.path, "body": json.loads(body)}
        with open(os.path.join(out, self.path.strip("/") + ".jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
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
backend = "hc"
webhook_url = "http://127.0.0.1:$P/primary"
webhook_header_name = "X-Primary"
webhook_header_value = "primary-secret"
webhook_timeout_sec = 1
debounce_sec = 0

[[owners]]
name = "boss"
url = "http://127.0.0.1:$P/boss"
header_name = "X-Boss"
header_value = "boss-secret"
TOML
chmod 600 "$T/config.toml"
echo '{"version":1,"panes":{"t1":{"pane_id":"t1","workspace_id":null,"task_id":"t1","agent_name":"gb-t1","kind":"grok","origin":"launched","backend":"hc","armed":true,"owner":"boss","repo":"/r","worktree":"/w","branch":"gbb/t1"}}}' >"$T/state/managed.json"
rm -rf "$T/state/last"; mkdir -p "$T/state/last"
cat >"$T/events.jsonl" <<'JSON'
{"seq":1,"terminals":[{"address":"t1","status":{"state":"idle","app":"grok"},"reported":true}]}
{"jsonrpc":"2.0","method":"event","params":{"seq":2,"terminal":"t1","type":"status","data":{"reported":true,"records":{},"status":{"state":"working","app":"grok"}}}}
{"jsonrpc":"2.0","method":"event","params":{"seq":3,"terminal":"t1","type":"status","data":{"reported":true,"records":{},"status":{"state":"done","app":"grok","msg":"SECRET_PROMPT_TEXT"}}}}
{"jsonrpc":"2.0","method":"event","params":{"seq":4,"terminal":"t1","type":"status","data":{"reported":true,"records":{},"status":{"state":"idle","app":"grok"}}}}
{"jsonrpc":"2.0","method":"event","params":{"seq":5,"terminal":"t7","type":"status","data":{"reported":true,"records":{},"status":{"state":"done","app":"grok"}}}}
{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":5}}
JSON
"$ROOT/bin/gbb" hc-watch
[ -f "$T/hits/boss.jsonl" ] || fail "no owner delivery"
[ ! -f "$T/hits/primary.jsonl" ] || fail "primary got an owner task"
[ "$(grep -c . "$T/hits/boss.jsonl")" = 1 ] || fail "expected 1 done callback, got $(cat "$T/hits/boss.jsonl")"
body=$(tail -n 1 "$T/hits/boss.jsonl" | jq -c .body)
printf '%s' "$body" | jq -e '.source=="grokbot-bridge-herdr" and .version=="0.3.0" and .event=="agent_status" and .status=="done" and .task_id=="t1" and .pane_id=="t1" and .backend=="hc" and .owner=="boss" and .route=="owner" and .herdr_status=="done" and .repo=="/r"' >/dev/null || fail "done payload: $body"
printf '%s' "$body" | grep -q SECRET_PROMPT_TEXT && fail "payload leaked the OSC message"
grep -q primary-secret "$T/state/bridge.log" && fail "secret in log"
rm -f "$T/hits"/*
cat >"$T/events.jsonl" <<'JSON'
{"jsonrpc":"2.0","method":"event","params":{"seq":6,"terminal":"t1","type":"status","data":{"reported":true,"records":{},"status":{"state":"blocked","kind":"question","app":"grok","msg":"SECRET2"}}}}
{"jsonrpc":"2.0","method":"event","params":{"seq":7,"terminal":"t1","type":"status","data":{"reported":true,"records":{},"status":{"state":"error","app":"grok"}}}}
{"jsonrpc":"2.0","method":"event","params":{"seq":8,"terminal":"t1","type":"finished","data":{"reason":"exited","exit_code":0,"signal":null,"finished_ms":1}}}
JSON
"$ROOT/bin/gbb" hc-watch
[ "$(grep -c . "$T/hits/boss.jsonl")" = 3 ] || fail "blocked/error/closed count: $(cat "$T/hits/boss.jsonl")"
printf '%s\n' "$(jq -c .body "$T/hits/boss.jsonl")" | grep -q SECRET2 && fail "blocked payload leaked msg"
jq -c .body "$T/hits/boss.jsonl" | jq -s -e '
  .[0].status=="blocked" and .[0].blocked_reason=="question" and .[0].herdr_status=="blocked"
  and .[1].status=="blocked" and .[1].blocked_reason=="error" and .[1].herdr_status=="error"
  and .[2].event=="pane_closed" and .[2].pane_id=="t1"' >/dev/null || fail "event map: $(jq -c .body "$T/hits/boss.jsonl")"
[ "$("$ROOT/bin/gbb" list | jq '.managed | length')" = 0 ] || fail "finished row still registered"

# --- Codex that never reports: a question screen becomes blocked ---
rm -f "$T/hits"/* "$T/state/last"/*
printf '%s\n' '• Queued follow-up inputs' '  ? 1 question' '  ⇧← to answer' '› Ask Codex to do anything' \
  '  GPT-6.1-Sol xhigh · ~/x · Context 7% used · 12k in · 2k out' >"$T/screen"
echo '{"version":1,"panes":{"t2":{"pane_id":"t2","task_id":"cx","agent_name":"gb-cx","kind":"codex","origin":"launched","backend":"hc","armed":true}}}' >"$T/state/managed.json"
cat >"$T/events.jsonl" <<'JSON'
{"jsonrpc":"2.0","method":"event","params":{"seq":1,"terminal":"t2","type":"foreground","data":{"pid":1,"name":"codex","cwd":"/w"}}}
JSON
"$ROOT/bin/gbb" hc-watch
[ -f "$T/hits/primary.jsonl" ] || fail "unreported codex produced no callback"
jq -c .body "$T/hits/primary.jsonl" | jq -s -e '.[0].status=="blocked" and .[0].blocked_reason=="question" and .[0].route=="primary" and .[0].task_id=="cx"' >/dev/null || fail "screen fallback: $(cat "$T/hits/primary.jsonl")"
echo PASS
