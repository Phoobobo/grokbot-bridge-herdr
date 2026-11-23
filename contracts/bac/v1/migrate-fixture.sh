#!/bin/sh
# Offline gbb registry fixture -> bac.registry.v1.
# Refuses live config/state directories. Does not read config, tokens, or secrets.
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
src_real=$(cd "$src" && pwd -P)
if [ -e "$dst" ]; then
  [ -d "$dst" ] || { echo "refuse: dst exists and is not a directory" >&2; exit 2; }
  dst_real=$(cd "$dst" && pwd -P)
else
  dst_parent=$(dirname "$dst")
  [ -d "$dst_parent" ] || { echo "refuse: dst parent missing" >&2; exit 2; }
  dst_real=$(cd "$dst_parent" && pwd -P)/$(basename "$dst")
fi

refuse_live() {
  p=$1
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
    case "$p" in
      "$live"|"$live"/*)
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
mkdir -p "$dst_real"
out="$dst_real/managed.json"
mv "$tmp" "$out"
chmod 600 "$out"
trap 'rm -f "$err"' EXIT
echo "ok $out"
