#!/bin/sh
# Install: put gbb on PATH and link the Herdr plugin. Idempotent; touches nothing else.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
ROOT=$(cd "$(dirname "$0")" && pwd -P)
for d in herdr jq git curl; do command -v "$d" >/dev/null || { echo "missing dependency: $d" >&2; exit 1; }; done
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/gbb" "$HOME/.local/bin/gbb"
chmod +x "$ROOT/bin/gbb"
herdr plugin link "$ROOT"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/grokbot-bridge-herdr"
mkdir -p "$CFG"; chmod 700 "$CFG"
[ -f "$CFG/config.toml" ] || echo "next: cp $ROOT/config.example.toml $CFG/config.toml && chmod 600 $CFG/config.toml, then fill webhook_url + header"
