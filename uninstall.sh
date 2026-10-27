#!/bin/sh
# Unlink the plugin and remove the gbb symlink. Keeps config, registry, logs and worktrees.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
herdr plugin unlink phoobobo.grokbot-bridge || true
[ -L "$HOME/.local/bin/gbb" ] && rm "$HOME/.local/bin/gbb"
echo "kept: ~/.config/grokbot-bridge-herdr ~/.local/state/grokbot-bridge-herdr ~/.local/share/grokbot-bridge-herdr"
