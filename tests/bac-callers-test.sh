#!/bin/sh
# Isolated stub harness for bac. Not a live Herdr, hc, Dots, or ChatGPT check.
# HOME is a temp directory. Header values are fixtures. The Codex file is read only
# when BAC_ALLOW_CODEX_CONFIG=1, and only its top-level model key.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
SINK=""
cleanup() {
  if [ -f "$T/state/hc-watch.pid" ]; then kill "$(cat "$T/state/hc-watch.pid")" 2>/dev/null || true; fi
  [ -n "$SINK" ] && kill "$SINK" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; echo "--- log ---"; cat "$T/state/bridge.log" 2>/dev/null || true; exit 1; }
mkdir -p "$T/bin" "$T/state" "$T/data" "$T/hits" "$T/repo" "$T/home/.codex" "$T/screen"
export HOME="$T/home"
unset BAC_ALLOW_CODEX_CONFIG BAC_CODEX_CONFIG BAC_OWNER BAC_WEBHOOK_URL BAC_BACKEND 2>/dev/null || true
cat >"$HOME/.codex/config.toml" <<'TOML'
model = "fixture-model"
api_key = "SHOULD-NOT-BE-READ"
TOML
printf '%s\n' '› ready' 'GPT-6.1-Sol xhigh · Context 7% used' >"$T/screen/codex"
cat >"$T/bin/hc" <<'H'
#!/bin/sh
d=$(mktemp "$STUB_DIR/call.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
case "$1" in
  run)
    if [ -f "$STUB_DIR/no-address" ]; then printf '%s\n' '{}'; exit 0; fi
    n=$(cat "$STUB_DIR/addr" 2>/dev/null || echo 0)
    n=$((n + 1)); printf '%s\n' "$n" >"$STUB_DIR/addr"
    printf '{"address":"t%s","name":"n","state":"live"}\n' "$n"
    ;;
  get)
    addr=$3; [ -n "${addr:-}" ] || addr=$2
    printf '{"address":"%s","name":"n","state":"live","status":{"state":"idle","app":"grok"},"reported":true,"cwd":"%s","labels":{}}\n' "$addr" "$STUB_DIR/repo"
    ;;
  send) printf '%s\n' '{"started":true,"status":"working"}' ;;
  read) cat "$STUB_DIR/screen/codex" ;;
  events)
    [ -f "$STUB_DIR/events.jsonl" ] && cat "$STUB_DIR/events.jsonl"
    ;;
  server) printf '%s\n' '{"pid":1,"version":"stub"}' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
H
cat >"$T/bin/herdr" <<'H'
#!/bin/sh
printf '%s\n' '{"result":{"type":"ok"}}'
H
cat >"$T/bin/herdr-app" <<'H'
#!/bin/sh
echo "no window" >&2
exit 2
H
chmod +x "$T/bin/hc" "$T/bin/herdr" "$T/bin/herdr-app"
export HERDR_BIN_PATH="$T/bin/herdr" HC_BIN_PATH="$T/bin/hc" HERDR_APP_BIN_PATH="$T/bin/herdr-app"
export STUB_DIR="$T" BAC_STATE_DIR="$T/state" BAC_DATA_DIR="$T/data" BAC_CONFIG="$T/config.toml" BAC_HC_WATCH_ONCE=1
git -C "$T/repo" init -q
git -C "$T/repo" config user.email t@example.com
git -C "$T/repo" config user.name t
echo x >"$T/repo/f" && git -C "$T/repo" add f && git -C "$T/repo" commit -qm init
cat >"$T/sink.py" <<'PY'
import http.server, json, os, sys
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("content-length", 0))
        body = self.rfile.read(n)
        rec = {"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": json.loads(body)}
        with open(os.path.join(out, self.path.strip("/") + ".jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
            f.flush()
        self.send_response(500 if self.path == "/slow" else 202)
        self.end_headers()
    def log_message(self, *a):
        pass
class S(http.server.ThreadingHTTPServer):
    daemon_threads = True
s = S(("127.0.0.1", 0), H)
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
webhook_header_value = "fixture-primary"
webhook_timeout_sec = 1
debounce_sec = 0
startup_settle_sec = 0
startup_ready_timeout_sec = 3

[[owners]]
name = "dot"
url = "http://127.0.0.1:$P/dot"
header_name = "X-Dots-Herdr-Token"
header_value = "fixture-dot"

[[owners]]
name = "slow"
url = "http://127.0.0.1:$P/slow"
header_name = "X-Slow"
header_value = "fixture-slow"
TOML
chmod 600 "$T/config.toml"
BAC="$ROOT/bin/bac"
runs() {
  if ls "$T"/call.* >/dev/null 2>&1; then
    cat "$T"/call.* | jq -s 'map(select(.[0]=="run")) | length'
  else
    echo 0
  fi
}
reset() { rm -f "$T"/call.*; }

# --- missing / rejected kinds create no terminal ---
reset
before=$(runs)
for args in "" "--kind pi" "--kind antigravity" "--kind nope"; do
  # shellcheck disable=SC2086
  set -- $args
  out=$("$BAC" launch --repo "$T/repo" --task k --prompt hi --no-worktree "$@" 2>/dev/null || true)
  printf '%s' "$out" | jq -e 'has("pane_id") | not' >/dev/null || fail "kind created a pane id: $args $out"
done
printf '%s' "$("$BAC" launch --repo "$T/repo" --task k --prompt hi --no-worktree 2>/dev/null || true)" | jq -e '.error.code=="kind_required"' >/dev/null || fail "omitted kind"
printf '%s' "$("$BAC" launch --repo "$T/repo" --kind pi --task k --prompt hi --no-worktree 2>/dev/null || true)" | jq -e '.error.code=="kind_unsupported" and .error.kind=="pi" and .error.kind_support=="rejected"' >/dev/null || fail "pi"
printf '%s' "$("$BAC" launch --repo "$T/repo" --kind antigravity --task k --prompt hi --no-worktree 2>/dev/null || true)" | jq -e '.error.kind=="antigravity" and .error.kind_support=="rejected"' >/dev/null || fail "antigravity"
printf '%s' "$("$BAC" launch --repo "$T/repo" --kind nope --task k --prompt hi --no-worktree 2>/dev/null || true)" | jq -e '.error.kind=="nope" and .error.kind_support=="unknown" and .error.kind!="codex"' >/dev/null || fail "unknown kind"
[ "$(runs)" = "$before" ] || fail "rejected kind invoked hc run"

# --- no address: error, no pane id, no registry row ---
touch "$T/no-address"
out=$("$BAC" launch --repo "$T/repo" --kind grok --task none --prompt hi --no-worktree 2>/dev/null || true)
printf '%s' "$out" | jq -e '.error.code=="agent_start_failed" and (has("pane_id")|not)' >/dev/null || fail "fake pane: $out"
[ "$("$BAC" list | jq '.managed|length')" = 0 ] || fail "registry row without an address"
rm -f "$T/no-address"

# --- Grok Bot primary path: stub assigns the pane id ---
reset
out=$("$BAC" launch --repo "$T/repo" --kind grok --task g1 --prompt hi --no-worktree)
pane=$(printf '%s' "$out" | jq -r .pane_id)
[ "$pane" = t1 ] || fail "stub pane: $out"
printf '%s' "$out" | jq -e '.ok==true and .pane_id_source=="hc.address" and .backend=="hc" and .owner==null' >/dev/null || fail "launch shape: $out"
"$BAC" status g1 >/dev/null || fail "status"
"$BAC" result g1 >/dev/null || fail "result"
# launch itself may not emit done; fire one status through the watcher
rm -f "$T/state/last/$(printf '%s' "$pane" | tr ':' '_')"
cat >"$T/events.jsonl" <<JSON
{"jsonrpc":"2.0","method":"event","params":{"terminal":"$pane","type":"status","data":{"reported":true,"status":{"state":"done","app":"grok","msg":"TERMINAL BODY"}}}}
JSON
"$BAC" hc-watch
body=$(tail -n 1 "$T/hits/primary.jsonl" | jq -c .body)
printf '%s' "$body" | jq -e --arg p "$pane" '.source=="bot-as-collie" and .version==1 and .route=="primary" and .pane_id==$p and .event=="agent_status" and .status=="done" and (.attempt==1) and (.event_id|test("^[0-9a-f]{64}$"))' >/dev/null || fail "primary callback: $body"
printf '%s' "$body" | jq -e 'has("text") or has("screen") or has("prompt") or has("model") or has("header_value")' >/dev/null && fail "callback carried a forbidden field: $body"
printf '%s' "$body" | grep -q 'TERMINAL BODY' && fail "terminal body in callback"
grep -q fixture-primary "$T/state/bridge.log" && fail "header in log"
eid1=$(printf '%s' "$body" | jq -r .event_id)
gen1=$(printf '%s' "$body" | jq -r .generation)
want=$(printf 'bac.callback.v1\n%s\n%s\n%s\n%s' "$pane" agent_status "done" "$gen1" | sha256sum | awk '{print $1}')
[ "$eid1" = "$want" ] || fail "event_id mismatch"

# --- Dots owner path ---
rm -f "$T/hits"/*
out=$("$BAC" launch --repo "$T/repo" --kind codex --task d1 --prompt hi --owner dot --no-worktree)
dpane=$(printf '%s' "$out" | jq -r .pane_id)
[ -n "$dpane" ] && [ "$dpane" != "$pane" ] || fail "second stub pane: $out"
rm -f "$T/state/last/$(printf '%s' "$dpane" | tr ':' '_')"
cat >"$T/events.jsonl" <<JSON
{"jsonrpc":"2.0","method":"event","params":{"terminal":"$dpane","type":"status","data":{"reported":true,"status":{"state":"idle","app":"codex"}}}}
JSON
"$BAC" hc-watch
dbody=$(tail -n 1 "$T/hits/dot.jsonl" | jq -c .body)
printf '%s' "$dbody" | jq -e --arg p "$dpane" '.route=="owner" and .owner=="dot" and .pane_id==$p and .source=="bot-as-collie"' >/dev/null || fail "dot callback: $dbody"
[ ! -f "$T/hits/primary.jsonl" ] || fail "primary also got the dot event"
"$BAC" status "$dpane" --owner dot >/dev/null || fail "dot status"
"$BAC" result d1 --owner dot >/dev/null || fail "dot result"

# --- cross-owner does not mutate; omitted owner is not a free pass on an owned row ---
hash=$(jq -c --arg p "$dpane" '.panes[$p]' "$T/state/managed.json" | sha256sum | awk '{print $1}')
for cmd in \
  "send $dpane --owner canmouzhang nope" \
  "read $dpane --owner canmouzhang" \
  "stop $dpane --owner canmouzhang" \
  "result $dpane --owner canmouzhang" \
  "status $dpane --owner canmouzhang" \
  "send $dpane hello" \
  "read $dpane" \
  "stop $dpane" \
  "reclaim --pane $dpane" \
  "owner $dpane --owner canmouzhang other"
 do
  # shellcheck disable=SC2086
  out=$("$BAC" $cmd 2>/dev/null || true)
  code=$(printf '%s' "$out" | jq -r '.error.code // empty')
  case "$code" in
    owner_mismatch|owner_required) ;;
    *) fail "expected owner refusal for [$cmd]: $out" ;;
  esac
  printf '%s' "$out" | jq -e 'has("text")|not' >/dev/null || fail "refusal included text: $cmd"
 done
nowhash=$(jq -c --arg p "$dpane" '.panes[$p]' "$T/state/managed.json" | sha256sum | awk '{print $1}')
[ "$nowhash" = "$hash" ] || fail "cross-owner changed the row"
"$BAC" list --owner canmouzhang | jq -e --arg p "$dpane" 'any(.managed[]; .pane_id==$p)|not' >/dev/null || fail "list --owner leaked the dot row"
"$BAC" list | jq -e --arg p "$dpane" 'any(.managed[]; .pane_id==$p)' >/dev/null || fail "local operator list hid the row"
"$BAC" report --owner canmouzhang | jq -e --arg p "$dpane" 'any(.tasks[]; .pane_id==$p)|not' >/dev/null || fail "report filter"
# transfer then clear, only as the current owner
"$BAC" owner "$dpane" --owner dot canmouzhang >/dev/null || fail "transfer"
[ "$("$BAC" list | jq -r --arg p "$dpane" '.managed[] | select(.pane_id==$p) | .owner')" = canmouzhang ] || fail "transfer did not stick"
qhash=$(jq -c --arg p "$dpane" '.panes[$p]' "$T/state/managed.json" | sha256sum | awk '{print $1}')
q=$("$BAC" owner "$dpane" --owner canmouzhang)
printf '%s' "$q" | jq -e '.ok==true and .owner=="canmouzhang"' >/dev/null || fail "owner query: $q"
[ "$(jq -c --arg p "$dpane" '.panes[$p]' "$T/state/managed.json" | sha256sum | awk '{print $1}')" = "$qhash" ] || fail "owner query wrote the row"
"$BAC" owner "$dpane" --owner dot --clear >/dev/null 2>&1 && fail "old owner cleared after transfer"
"$BAC" owner "$dpane" --owner canmouzhang --clear >/dev/null || fail "clear"
[ "$("$BAC" list | jq -r --arg p "$dpane" '.managed[] | select(.pane_id==$p) | .owner')" = null ] || fail "clear did not stick"

# --- handover is the adopt path; reclaim + reuse does not reuse event_id ---
hout=$("$BAC" handover --pane t9 --owner dot)
printf '%s' "$hout" | jq -e '.ok==true and .entry.pane_id=="t9" and .entry.origin=="handover" and .entry.owner=="dot"' >/dev/null || fail "handover: $hout"
rm -f "$T/hits"/*
rm -f "$T/state/last/t9"
cat >"$T/events.jsonl" <<'JSON'
{"jsonrpc":"2.0","method":"event","params":{"terminal":"t9","type":"status","data":{"reported":true,"status":{"state":"done","app":"grok"}}}}
JSON
"$BAC" hc-watch
h1=$(tail -n 1 "$T/hits/dot.jsonl" | jq -r .body.event_id)
g1=$(tail -n 1 "$T/hits/dot.jsonl" | jq -r .body.generation)
"$BAC" reclaim --pane t9 --owner dot >/dev/null || fail "reclaim"
seq_after=$(jq -r '.panes.t9' "$T/state/event-seq.json")
[ "$seq_after" != null ] && [ "$seq_after" -ge "$g1" ] || fail "reclaim dropped generation ($seq_after vs $g1)"
"$BAC" handover --pane t9 --owner dot >/dev/null || fail "rehandover"
rm -f "$T/hits"/* "$T/state/last/t9"
"$BAC" hc-watch
h2=$(tail -n 1 "$T/hits/dot.jsonl" | jq -r .body.event_id)
g2=$(tail -n 1 "$T/hits/dot.jsonl" | jq -r .body.generation)
[ "$h2" != "$h1" ] || fail "reused pane collided event_id"
[ "$g2" -gt "$g1" ] || fail "generation did not advance ($g1 -> $g2)"

# --- non-2xx owner delivery falls back once. The sink returns 500 immediately.
# curl --max-time is the same failure branch. This harness does not sleep inside the sink,
# so a slow body cannot be mistaken for a generation race.
# --- timeout: one attempt per target, same event_id on fallback ---
rm -f "$T/hits"/*
"$BAC" test-webhook --owner slow >/dev/null
slow_n=$(grep -c . "$T/hits/slow.jsonl" || true)
prim_n=$(grep -c . "$T/hits/primary.jsonl" || true)
[ "$slow_n" = 1 ] && [ "$prim_n" = 1 ] || fail "timeout deliveries slow=$slow_n primary=$prim_n"
s_id=$(jq -r .body.event_id "$T/hits/slow.jsonl")
p_id=$(jq -r .body.event_id "$T/hits/primary.jsonl")
[ "$s_id" = "$p_id" ] || fail "fallback changed event_id"
jq -e '.body.attempt==1 and .body.route=="owner"' "$T/hits/slow.jsonl" >/dev/null || fail "slow attempt"
jq -e '.body.attempt==1 and .body.route=="fallback" and .body.fallback_reason=="owner_delivery_failed"' "$T/hits/primary.jsonl" >/dev/null || fail "fallback shape"

# --- restart keeps the counter; parallel stamps get distinct ids ---
# Owner matching above is a local label check, not authentication.
before_seq=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
rm -f "$T/hits"/*
"$BAC" test-webhook >/dev/null
"$BAC" test-webhook >/dev/null
after_seq=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
[ "$after_seq" -eq $((before_seq + 2)) ] || fail "restart did not persist generation ($before_seq -> $after_seq)"
ids=$(jq -r .body.event_id "$T/hits/primary.jsonl" | sort -u | wc -l | tr -d ' ')
[ "$ids" -eq 2 ] || fail "two processes produced one event_id"
wait_pids() { # seconds pid [pid]
  limit=$1
  a=$2
  b=${3:-}
  i=0
  while [ "$i" -lt "$limit" ]; do
    alive=0
    kill -0 "$a" 2>/dev/null && alive=1
    if [ -n "$b" ] && kill -0 "$b" 2>/dev/null; then alive=1; fi
    [ "$alive" = 0 ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  kill "$a" ${b:+"$b"} 2>/dev/null || true
  return 1
}
round=0
while [ "$round" -lt 3 ]; do
  seq_before=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
  rm -f "$T/hits"/*
  "$BAC" test-webhook >/dev/null &
  p1=$!
  "$BAC" test-webhook >/dev/null &
  p2=$!
  if ! wait_pids 40 "$p1" "$p2"; then fail "concurrent round $round exceeded 20s"; fi
  seq_after=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
  [ "$seq_after" -eq $((seq_before + 2)) ] || fail "round $round generation $seq_before -> $seq_after"
  par=$(jq -r .body.event_id "$T/hits/primary.jsonl" | sort -u | wc -l | tr -d ' ')
  [ "$par" -eq 2 ] || fail "round $round ids: $(jq -c .body.event_id "$T/hits/primary.jsonl")"
  round=$((round + 1))
done
jq -e '.panes | all(.[]; type=="number")' "$T/state/event-seq.json" >/dev/null || fail "event-seq corrupted"

# PATH without flock. macOS does not ship flock; this Linux VM hides that one name
# and keeps every other command from PATH.
nof=$(mktemp -d)
oldifs=$IFS
IFS=:
for d in $PATH; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = flock ] && continue
    [ -e "$nof/$base" ] && continue
    ln -s "$f" "$nof/$base" 2>/dev/null || true
  done
done
IFS=$oldifs
if PATH="$nof" command -v flock >/dev/null 2>&1; then fail "flock still visible"; fi
seq_before=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
rm -f "$T/hits"/*
PATH="$nof" "$BAC" test-webhook >/dev/null &
p1=$!
PATH="$nof" "$BAC" test-webhook >/dev/null &
p2=$!
if ! wait_pids 40 "$p1" "$p2"; then fail "no-flock round exceeded 20s"; fi
seq_after=$(jq -r '.panes.__none__ // 0' "$T/state/event-seq.json")
[ "$seq_after" -eq $((seq_before + 2)) ] || fail "no-flock generation $seq_before -> $seq_after"
par=$(PATH="$nof" jq -r .body.event_id "$T/hits/primary.jsonl" | sort -u | wc -l | tr -d ' ')
[ "$par" -eq 2 ] || fail "no-flock ids collided"
doc=$(PATH="$nof" "$BAC" doctor)
printf '%s' "$doc" | jq -e '.generation_lock=="mkdir" and .flock_required==false and .flock_present==false and .sha256==true' >/dev/null || fail "doctor without flock: $doc"

# A live holder is not evicted, and a failed jq does not roll the counter backwards.
mkdir -p "$T/state/.lock"
printf '%s\n' "$$" >"$T/state/.lock/pid"
held=$(jq -c . "$T/state/event-seq.json")
PATH="$nof" "$BAC" test-webhook >/dev/null &
p1=$!
if ! wait_pids 50 "$p1"; then kill "$p1" 2>/dev/null || true; fail "held-lock webhook exceeded 25s"; fi
[ "$(cat "$T/state/.lock/pid")" = "$$" ] || fail "live lock was stolen"
[ "$(jq -c . "$T/state/event-seq.json")" = "$held" ] || fail "live lock still advanced generation"
rm -rf "$T/state/.lock"
badjq=$(mktemp -d)
printf '%s\n' '#!/bin/sh' 'exit 1' >"$badjq/jq"
chmod +x "$badjq/jq"
for c in git curl python3 sha256sum sh; do
  src=$(command -v "$c" 2>/dev/null || true)
  [ -n "$src" ] && ln -s "$src" "$badjq/$c"
done
held=$(sha256sum "$T/state/event-seq.json" | awk '{print $1}')
if PATH="$badjq:$PATH" "$BAC" test-webhook >/dev/null 2>"$T/jqfail.err"; then
  fail "broken jq still stamped"
fi
[ "$(sha256sum "$T/state/event-seq.json" | awk '{print $1}')" = "$held" ] || fail "failed jq rewrote event-seq"

# --- model config is opt-in and allowlisted; a Codex footer is an observation, not a quota ---
st=$("$BAC" status g1)
printf '%s' "$st" | grep -q SHOULD-NOT-BE-READ && fail "status read a secret key"
printf '%s' "$st" | jq -e '.model.provenance=="unknown" and .quota.provenance=="unknown"' >/dev/null || fail "default model: $st"
st=$(BAC_ALLOW_CODEX_CONFIG=1 "$BAC" status g1)
printf '%s' "$st" | grep -q SHOULD-NOT-BE-READ && fail "allowlisted read still saw api_key"
printf '%s' "$st" | jq -e '.model.provenance=="config" and .model.id=="fixture-model" and .model.freshness=="not_a_session_observation" and .quota.provenance=="unknown"' >/dev/null || fail "config model: $st"
st=$("$BAC" status d1)
printf '%s' "$st" | jq -e '.model.provenance=="observed" and .model.id=="GPT-6.1-Sol xhigh" and .quota.provenance=="unknown"' >/dev/null || fail "observed model: $st"

echo PASS
