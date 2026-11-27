#!/bin/sh
# Serial module check with synthetic config and binaries; no agent or service.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.local/bin" "$T/bin" "$T/state" "$T/data"
export HOME="$T/home" BAC_STATE_DIR="$T/state" BAC_DATA_DIR="$T/data"
export BAC_CONFIG="$T/config.toml" BAC_DOTS_TOKEN_FILE="$T/synthetic-token"
export BAC_DOTS_PROBE_URL=http://127.0.0.1:8765/ TEST_DOTS_CALLS="$T/calls"
unset BAC_ALLOW_CODEX_CONFIG
printf 'synthetic-fixture\n' >"$BAC_DOTS_TOKEN_FILE"
chmod 600 "$BAC_DOTS_TOKEN_FILE"
cat >"$T/bin/backend" <<'SH'
#!/bin/sh
printf '{}\n'
SH
cat >"$HOME/.local/bin/curl" <<'SH'
#!/bin/sh
printf 'probe\n' >>"$TEST_DOTS_CALLS"
SH
chmod +x "$T/bin/backend" "$HOME/.local/bin/curl"
export HERDR_BIN_PATH="$T/bin/backend" HC_BIN_PATH="$T/bin/backend"
# bac prepends user-local paths, all under this synthetic HOME.
export PATH="$T/bin:$PATH"
printf '[modules.dots]\nenabled = false\n' >"$BAC_CONFIG"
out=$("$ROOT/bin/bac" report)
printf '%s' "$out" | jq -e '.modules[] | select(.id == "dots") | .enabled == false and .probe_ok == false and .config == false and (.reason | contains("probe skipped"))' >/dev/null
[ ! -e "$TEST_DOTS_CALLS" ] || { echo 'FAIL: disabled Dots called curl' >&2; exit 1; }
# Positive control: the synthetic probe is reachable when auto detection is on.
printf '# auto detection\n' >"$BAC_CONFIG"
out=$("$ROOT/bin/bac" report)
printf '%s' "$out" | jq -e '.modules[] | select(.id == "dots") | .enabled == true and .probe_ok == true' >/dev/null
[ -s "$TEST_DOTS_CALLS" ]
if grep -v '^probe$' "$TEST_DOTS_CALLS"; then
  echo 'FAIL: unexpected synthetic curl call' >&2
  exit 1
fi
echo PASS
