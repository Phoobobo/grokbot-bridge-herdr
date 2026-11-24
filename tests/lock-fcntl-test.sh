#!/bin/sh
# Real bin/bac fcntl lock. The old 542c8bd binary is attacked at its mv.
# The new helper must not rename or remove the lock file.
# Linux only for /proc cloexec. Not a macOS or live Herdr run.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
PIDS=""
cleanup() {
  for p in $PIDS; do
    kill -9 "$p" 2>/dev/null || true
  done
  for p in $PIDS; do
    wait "$p" 2>/dev/null || true
  done
  rm -rf "$T"
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v python3 >/dev/null || fail "python3 missing"
mkdir -p "$T/home" "$T/state" "$T/data" "$T/oldstate"
export HOME="$T/home"
printf '%s\n' 'webhook_url = "http://127.0.0.1:9/none"' 'webhook_timeout_sec = 1' >"$T/config.toml"
chmod 600 "$T/config.toml"
NEW="$ROOT/bin/bac"
seq_of() {
  if [ -s "$1" ]; then jq -r '.panes.__none__ // 0' "$1"; else printf 0; fi
}
inode_of() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$1"; }
wait_file() {
  i=0
  while [ ! -e "$1" ]; do
    i=$((i + 1))
    [ "$i" -gt 200 ] && return 1
    sleep 0.05
  done
}
wait_held() {
  dir=$1
  i=0
  while :; do
    for f in "$dir"/held.*; do
      [ -f "$f" ] || continue
      case "$f" in
        *.go|*.skip) continue ;;
      esac
      printf '%s\n' "$f"
      return 0
    done
    i=$((i + 1))
    [ "$i" -gt 200 ] && return 1
    sleep 0.05
  done
}

# --- old 542c8bd bin/bac: pause its real mv, then a new lock is published, then that mv runs ---
if git -C "$ROOT" cat-file -e 542c8bd440f293159616ddd2910bb700aaeecc33:bin/bac 2>/dev/null; then
  git -C "$ROOT" show 542c8bd440f293159616ddd2910bb700aaeecc33:bin/bac >"$T/old-bac"
  chmod +x "$T/old-bac"
  mkdir -p "$T/wrap"
  cat >"$T/wrap/mv" <<EOF
#!/bin/sh
real=\$(command -v -p mv 2>/dev/null || echo /bin/mv)
src=\${1:-}
dst=\${2:-}
case "\$src" in
  */.lock)
    case "\$dst" in
      */.lock.grave*)
        printf 1 >"$T/old-paused"
        while [ ! -f "$T/old-go" ]; do sleep 0.01; done
        "\$real" "\$@"
        rc=\$?
        if [ -L "\$dst" ]; then readlink "\$dst" >"$T/old-grave-pid"; else printf absent >"$T/old-grave-pid"; fi
        if [ -L "\$src" ]; then readlink "\$src" >"$T/old-live"; else printf absent >"$T/old-live"; fi
        exit \$rc
        ;;
    esac
    ;;
esac
exec "\$real" "\$@"
EOF
  chmod +x "$T/wrap/mv"
  ln -s 300001 "$T/oldstate/.lock"
  PATH="$T/wrap:$PATH" HOME="$T/home" BAC_STATE_DIR="$T/oldstate" BAC_DATA_DIR="$T/data" BAC_CONFIG="$T/config.toml" \
    "$T/old-bac" test-webhook >/dev/null 2>"$T/old.err" &
  old=$!
  PIDS="$old"
  wait_file "$T/old-paused" || fail "old bac did not reach mv of .lock"
  mv "$T/oldstate/.lock" "$T/oldstate/grave-b"
  ln -s "$$" "$T/oldstate/.lock"
  printf 1 >"$T/old-go"
  wait_file "$T/old-grave-pid" || fail "old mv did not finish"
  [ "$(cat "$T/old-grave-pid")" = "$$" ] || fail "old mv did not take the new lock (grave $(cat "$T/old-grave-pid"))"
  [ "$(cat "$T/old-live")" = absent ] || fail "old mv left the new lock in place ($(cat "$T/old-live"))"
  echo "OLD_STEAL_CONFIRMED grave=$(cat "$T/old-grave-pid") live=$(cat "$T/old-live")"
  kill -9 "$old" 2>/dev/null || true
  wait "$old" 2>/dev/null || true
  PIDS=""
else
  echo "OLD_ABA_SKIP missing 542c8bd object"
fi

# --- new bac: paused after fcntl acquire and before event-seq replace ---
STEP=$T/step
mkdir -p "$STEP"
printf 1 >"$STEP/enable"
export BAC_LOCK_STEP=$STEP BAC_TEST_DRAIN_SEC=0
export BAC_STATE_DIR=$T/state BAC_DATA_DIR=$T/data BAC_CONFIG=$T/config.toml
before=$(seq_of "$T/state/event-seq.json")
"$NEW" test-webhook >/dev/null 2>"$T/new1.err" &
n1=$!
PIDS="$n1"
held_path=$(wait_held "$STEP") || fail "new bac did not pause after acquire"
helper=$(basename "$held_path")
helper=${helper#held.}
lock_inode=$(inode_of "$T/state/generation.lock")
"$NEW" test-webhook >/dev/null 2>"$T/new2.err" &
n2=$!
PIDS="$n1 $n2"
sleep 0.4
kill -0 "$n2" 2>/dev/null || fail "second bac entered or exited while the first still holds fcntl"
[ "$(seq_of "$T/state/event-seq.json")" = "$before" ] || fail "generation changed while the first had not committed"
[ "$(inode_of "$T/state/generation.lock")" = "$lock_inode" ] || fail "lock file was renamed or replaced"
printf 1 >"$STEP/held.go"
wait "$n1" || fail "first bac failed"
wait "$n2" || fail "second bac failed"
PIDS=""
after=$(seq_of "$T/state/event-seq.json")
[ "$after" -eq $((before + 2)) ] || fail "serialized generation $before -> $after"
[ "$(inode_of "$T/state/generation.lock")" = "$lock_inode" ] || fail "lock inode changed after commit"
echo "NEW_HOLD_OK inode=$lock_inode seq=$before->$after helper_was=$helper"

# --- helper dies before commit: this shell must not publish; the next one adds one ---
STEP=$T/step-die
mkdir -p "$STEP"
printf 1 >"$STEP/enable"
export BAC_LOCK_STEP=$STEP
mid=$(seq_of "$T/state/event-seq.json")
"$NEW" test-webhook >/dev/null 2>"$T/die.err" &
d1=$!
PIDS="$d1"
held_path=$(wait_held "$STEP") || fail "die case did not pause"
hpid=$(basename "$held_path")
hpid=${hpid#held.}
kill -9 "$hpid" 2>/dev/null || true
wait "$d1" || true
PIDS=""
[ "$(seq_of "$T/state/event-seq.json")" = "$mid" ] || fail "dead helper still published a generation"
unset BAC_LOCK_STEP
"$NEW" test-webhook >/dev/null
[ "$(seq_of "$T/state/event-seq.json")" -eq $((mid + 1)) ] || fail "recovery after dead helper did not add exactly one"
[ "$(inode_of "$T/state/generation.lock")" = "$lock_inode" ] || fail "lock inode changed after helper death"
echo "HELPER_DIE_OK"

# --- shell SIGKILL, with a child that outlives it: lock releases, child is not the lock ---
STEP=$T/step-kill
mkdir -p "$STEP"
printf 1 >"$STEP/enable"
export BAC_LOCK_STEP=$STEP BAC_LOCK_SPAWN_SLEEP=30
kbefore=$(seq_of "$T/state/event-seq.json")
"$NEW" test-webhook >/dev/null 2>"$T/kill.err" &
shellpid=$!
PIDS="$shellpid"
held_path=$(wait_held "$STEP") || fail "sigkill case did not pause"
wait_file "$T/state/orphan.pid" || fail "bac did not spawn the inherited child"
orphan=$(cat "$T/state/orphan.pid")
PIDS="$shellpid $orphan"
hpid=$(basename "$held_path")
hpid=${hpid#held.}
flags=$(awk '/^flags:/ {print $2}' /proc/"$hpid"/fdinfo/* 2>/dev/null | head -n 1 || true)
kill -9 "$shellpid" 2>/dev/null || true
i=0
while kill -0 "$hpid" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && fail "helper kept the lock after the shell was killed"
  sleep 0.05
done
kill -0 "$orphan" 2>/dev/null || fail "orphan child died with the shell"
unset BAC_LOCK_STEP BAC_LOCK_SPAWN_SLEEP
"$NEW" test-webhook >/dev/null
[ "$(seq_of "$T/state/event-seq.json")" -eq $((kbefore + 1)) ] || fail "generation after SIGKILL was not exactly one new commit"
kill -9 "$orphan" 2>/dev/null || true
wait "$orphan" 2>/dev/null || true
PIDS=""
echo "SIGKILL_OK cloexec_flags=${flags:-unknown} orphan=$orphan"

# --- timeout does not steal ---
STEP=$T/step-wait
mkdir -p "$STEP"
printf 1 >"$STEP/enable"
export BAC_LOCK_STEP=$STEP
tbefore=$(seq_of "$T/state/event-seq.json")
"$NEW" test-webhook >/dev/null 2>"$T/hold.err" &
holder=$!
PIDS="$holder"
wait_held "$STEP" >/dev/null || fail "timeout holder did not pause"
BAC_LOCK_TIMEOUT_SEC=1 "$NEW" test-webhook >/dev/null 2>"$T/timeout.err" || true
[ "$(seq_of "$T/state/event-seq.json")" = "$tbefore" ] || fail "timed-out waiter changed generation"
[ "$(inode_of "$T/state/generation.lock")" = "$lock_inode" ] || fail "timeout replaced the lock file"
printf 1 >"$STEP/held.go"
wait "$holder" || fail "holder failed after timeout test"
PIDS=""
[ "$(seq_of "$T/state/event-seq.json")" -eq $((tbefore + 1)) ] || fail "holder did not commit after release"
unset BAC_LOCK_STEP
echo "TIMEOUT_OK"

# --- jq failure does not replace event-seq; registry failure leaves managed.json ---
unset BAC_LOCK_STEP
printf '%s\n' '{"version":1,"panes":{"t1":{"pane_id":"t1","owner":"dot"}}}' >"$T/state/managed.json"
chmod 600 "$T/state/managed.json"
seq_hash=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/state/event-seq.json")
reg_hash=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/state/managed.json")
bad=$T/badjq
mkdir -p "$bad"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$bad/jq"
chmod +x "$bad/jq"
if PATH="$bad:$PATH" "$NEW" test-webhook >/dev/null 2>"$T/jq.err"; then
  :
fi
now=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/state/event-seq.json")
[ "$now" = "$seq_hash" ] || fail "broken jq replaced event-seq"
if PATH="$bad:$PATH" "$NEW" owner t1 --owner dot othername >/dev/null 2>"$T/own.err"; then
  fail "broken jq owner update exited 0"
fi
now=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$T/state/managed.json")
[ "$now" = "$reg_hash" ] || fail "broken jq replaced managed.json"
echo "JQ_FAIL_OK"
echo PASS
