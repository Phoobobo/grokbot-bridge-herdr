#!/bin/sh
# One serial simulated launch. Backend stubs never start an agent or server.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/bin" "$T/repo" "$T/state" "$T/data"
export HOME="$T/home" BAC_STATE_DIR="$T/state" BAC_DATA_DIR="$T/data"
export BAC_CONFIG="$T/config.toml" BAC_ISOLATED_SCOPE=serial-fixture
export BAC_HC_WATCH_ONCE=1 SCOPE_CALLS="$T/calls"
unset BAC_ALLOW_CODEX_CONFIG BAC_WEBHOOK_URL BAC_WEBHOOK_HEADER_NAME BAC_WEBHOOK_HEADER_VALUE
cat >"$BAC_CONFIG" <<'TOML'
startup_settle_sec = 0
startup_ready_timeout_sec = 5
[modules.dots]
enabled = false
TOML
cat >"$T/bin/hc" <<'SH'
#!/bin/sh
jq -cn --args '$ARGS.positional' -- "$@" >>"$SCOPE_CALLS"
case "$1" in
  run) printf '{"address":"t-scope"}\n' ;;
  get) printf '{"address":"t-scope","state":"live","status":{"state":"idle","app":"grok"},"labels":{"bac_scope":"serial-fixture"}}\n' ;;
  send) printf '{"started":true}\n' ;;
  label|events) : ;;
  *) echo "unexpected backend call: $*" >&2; exit 1 ;;
esac
SH
cat >"$T/bin/forbidden" <<'SH'
#!/bin/sh
printf 'FOREIGN_DISCOVERY\n' >>"$SCOPE_CALLS"
exit 1
SH
chmod +x "$T/bin/hc" "$T/bin/forbidden"
export HC_BIN_PATH="$T/bin/hc" HERDR_BIN_PATH="$T/bin/forbidden" HERDR_APP_BIN_PATH="$T/bin/forbidden"
git init -q "$T/repo"
git -C "$T/repo" -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null commit -qm initial --allow-empty
out=$("$ROOT/bin/bac" launch --repo "$T/repo" --kind grok --task scope-check --owner grok-bot --no-worktree --prompt fixture)
printf '%s' "$out" | jq -e '.ok == true and .pane_id == "t-scope" and .backend == "hc"' >/dev/null
# The once-only event stub exits on its own. No signal or liveness probe.
i=0
while ! jq -s -e 'any(.[]; .[0] == "events")' "$SCOPE_CALLS" >/dev/null; do
  i=$((i + 1)); [ "$i" -lt 30 ] || exit 1
  sleep 0.1
done
jq -s -e '
  all(.[]; .[0] != "ls" and .[0] != "server")
  and any(.[]; .[0] == "run" and index("bac_scope=serial-fixture") != null)
  and any(.[]; . == ["events","--json","--label","bac_scope=serial-fixture"])
' "$SCOPE_CALLS" >/dev/null
echo PASS
