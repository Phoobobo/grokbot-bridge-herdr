#!/bin/sh
# Install: put bac on PATH and link the Herdr plugin. Idempotent; touches nothing else.
# Does not install a gbb compatibility command.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
ROOT=$(cd "$(dirname "$0")" && pwd -P)
for d in jq git curl python3; do command -v "$d" >/dev/null || { echo "missing dependency: $d" >&2; exit 1; }; done
if ! command -v sha256sum >/dev/null && ! command -v shasum >/dev/null; then
  echo "missing dependency: sha256sum (Linux) or shasum (macOS)" >&2
  exit 1
fi
if ! command -v flock >/dev/null; then
  echo "note: flock is not on PATH. bac does not require it. The generation lock is fcntl inside bin/bac-lock (python3). Stock macOS has no flock."
fi
if ! command -v herdr >/dev/null && ! command -v hc >/dev/null; then
  echo "missing dependency: herdr (TUI) or hc (herdr-core)" >&2
  exit 1
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/bac" "$HOME/.local/bin/bac"
chmod +x "$ROOT/bin/bac"
rm -f "$HOME/.local/bin/gbb"
if command -v herdr >/dev/null; then
  herdr plugin link "$ROOT"
else
  echo "herdr is not on PATH: skipped plugin link (hc backend does not use the Herdr TUI plugin)"
fi
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/bot-as-collie"
mkdir -p "$CFG"; chmod 700 "$CFG"
[ -f "$CFG/config.toml" ] || echo "next: cp $ROOT/config.example.toml $CFG/config.toml && chmod 600 $CFG/config.toml, then fill webhook_url + header"
