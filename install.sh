#!/bin/sh
# Install: put gbb on PATH and link the Herdr plugin. Idempotent; touches nothing else.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
ROOT=$(cd "$(dirname "$0")" && pwd -P)
for d in jq git curl; do command -v "$d" >/dev/null || { echo "missing dependency: $d" >&2; exit 1; }; done
if ! command -v herdr >/dev/null && ! command -v hc >/dev/null; then
  echo "missing dependency: herdr (TUI) or hc (herdr-core)" >&2
  exit 1
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/gbb" "$HOME/.local/bin/gbb"
chmod +x "$ROOT/bin/gbb"
if command -v herdr >/dev/null; then
  herdr plugin link "$ROOT"
else
  echo "herdr is not on PATH: skipped plugin link (hc backend does not use the Herdr TUI plugin)"
fi
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/grokbot-bridge-herdr"
mkdir -p "$CFG"; chmod 700 "$CFG"
[ -f "$CFG/config.toml" ] || echo "next: cp $ROOT/config.example.toml $CFG/config.toml && chmod 600 $CFG/config.toml, then fill webhook_url + header"
