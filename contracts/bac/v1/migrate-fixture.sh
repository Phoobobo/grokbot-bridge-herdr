#!/bin/sh
# Offline fixture migration of a gbb registry (and an optional allowlisted config) into bac.registry.v1.
# This is not a production cutover tool: it refuses live directories and refuses to overwrite
# an existing destination. A failed run leaves the source byte-for-byte unchanged.
# Exit 0 written, 1 validation (source untouched, dest not written), 2 refused.
set -eu
ROOT=$(cd "$(dirname "$0")" && pwd -P)
FILTER="$ROOT/migrate.jq"

if [ "$#" -ne 2 ]; then
  echo "usage: migrate-fixture.sh <src-dir> <dst-dir>" >&2
  exit 2
fi

src=$1
dst=$2
[ -d "$src" ] || { echo "refuse: src is not a directory" >&2; exit 2; }

# Physical path, following directory symlinks. A missing tail keeps the
# physical ancestor plus that tail, so a not-yet-created dest compares
# the same way as an existing one. This is not a production migrator.
canon_path() {
  cn_in=$1
  [ -n "$cn_in" ] || { printf '\n'; return 0; }
  if [ -d "$cn_in" ]; then
    (cd "$cn_in" && pwd -P)
    return 0
  fi
  cn_rest=
  cn_cur=$cn_in
  while [ ! -d "$cn_cur" ]; do
    case "$cn_cur" in
      /|.|"") break ;;
    esac
    cn_rest="/$(basename "$cn_cur")$cn_rest"
    cn_next=$(dirname "$cn_cur")
    [ "$cn_next" = "$cn_cur" ] && break
    cn_cur=$cn_next
  done
  if [ -d "$cn_cur" ]; then
    cn_base=$(cd "$cn_cur" && pwd -P) || { printf '%s\n' "$cn_in"; return 0; }
    printf '%s%s\n' "$cn_base" "$cn_rest"
    return 0
  fi
  printf '%s\n' "$cn_in"
}

src_real=$(canon_path "$src")
if [ -e "$dst" ]; then
  [ -d "$dst" ] || { echo "refuse: dst exists and is not a directory" >&2; exit 2; }
else
  dst_parent=$(dirname "$dst")
  [ -d "$dst_parent" ] || { echo "refuse: dst parent missing" >&2; exit 2; }
fi
dst_real=$(canon_path "$dst")

refuse_live() {
  p=$(canon_path "$1")
  home=${HOME:-}
  config_home=${XDG_CONFIG_HOME:-$home/.config}
  state_home=${XDG_STATE_HOME:-$home/.local/state}
  data_home=${XDG_DATA_HOME:-$home/.local/share}
  for live in \
    "$config_home/grokbot-bridge-herdr" \
    "$config_home/bot-as-collie" \
    "$state_home/grokbot-bridge-herdr" \
    "$state_home/bot-as-collie" \
    "$data_home/grokbot-bridge-herdr" \
    "$data_home/bot-as-collie"
  do
    live_real=$(canon_path "$live")
    [ -n "$live_real" ] || continue
    case "$p" in
      "$live_real"|"$live_real"/*)
        echo "refuse: live path $p" >&2
        exit 2
        ;;
    esac
  done
}

refuse_live "$src_real"
refuse_live "$dst_real"
[ "$src_real" != "$dst_real" ] || { echo "refuse: src and dst are the same" >&2; exit 2; }

marker="$src_real/FIXTURE_OK"
[ -f "$marker" ] || { echo "refuse: missing FIXTURE_OK" >&2; exit 2; }
grep -q '^bac-migrate-fixture$' "$marker" || { echo "refuse: bad FIXTURE_OK" >&2; exit 2; }

reg="$src_real/managed.json"
[ -f "$reg" ] || { echo "refuse: missing managed.json" >&2; exit 2; }
[ ! -L "$reg" ] || { echo "refuse: managed.json is a symlink" >&2; exit 2; }
reg_real=$(cd "$(dirname "$reg")" && pwd -P)/$(basename "$reg")
case "$reg_real" in
  "$src_real"/*) ;;
  *) echo "refuse: managed.json is outside the fixture" >&2; exit 2 ;;
esac

tmp=$(mktemp)
err=$(mktemp)
trap 'rm -f "$tmp" "$err"' EXIT
if ! jq -e -f "$FILTER" "$reg" >"$tmp" 2>"$err"; then
  echo "migrate_failed" >&2
  cat "$err" >&2
  exit 1
fi
cfg_tmp=""
if [ -f "$src_real/config.toml" ]; then
  cfg_tmp=$(mktemp)
  # Allowlisted keys and the owner/extra/module tables only. Unknown top-level keys fail the run.
  if ! awk '
    function flush() { }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
    /^[[:space:]]*\[\[(owners|extra_webhooks)\]\]/ { in_t=1; print; next }
    /^[[:space:]]*\[(owners\.|modules\.)/ { in_t=1; print; next }
    /^[[:space:]]*\[/ { print "bad table " $0 > "/dev/stderr"; exit 1 }
    in_t && /^[[:space:]]*(name|url|header_name|header_value|enabled)[[:space:]]*=/ { print; next }
    in_t { print "bad table key " $0 > "/dev/stderr"; exit 1 }
    /^[[:space:]]*(webhook_url|webhook_header_name|webhook_header_value|webhook_timeout_sec|debounce_sec|backend|startup_settle_sec|startup_ready_timeout_sec|allowed_repos|codex_args|grok_args)[[:space:]]*=/ { print; next }
    { print "bad key " $0 > "/dev/stderr"; exit 1 }
  ' "$src_real/config.toml" >"$cfg_tmp"; then
    echo "migrate_failed" >&2
    rm -f "$cfg_tmp"
    exit 1
  fi
fi
if [ -e "$dst_real/managed.json" ] || [ -e "$dst_real/config.toml" ]; then
  echo "refuse: destination already exists" >&2
  rm -f "$cfg_tmp"
  exit 2
fi
mkdir -p "$dst_real"
out="$dst_real/managed.json"
mv "$tmp" "$out"
chmod 600 "$out"
if [ -n "$cfg_tmp" ]; then
  mv "$cfg_tmp" "$dst_real/config.toml"
  chmod 600 "$dst_real/config.toml"
fi
trap 'rm -f "$err"' EXIT
echo "ok $out"
