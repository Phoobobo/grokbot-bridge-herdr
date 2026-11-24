#!/bin/sh
# Unlink the plugin and remove the bac symlink. Keeps config, registry, logs and worktrees.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
herdr plugin unlink phoobobo.bot-as-collie || true
[ -L "$HOME/.local/bin/bac" ] && rm "$HOME/.local/bin/bac"
echo "kept: ~/.config/bot-as-collie ~/.local/state/bot-as-collie ~/.local/share/bot-as-collie"
