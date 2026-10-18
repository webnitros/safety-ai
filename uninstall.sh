#!/bin/bash
# Removes the app, login item, hook, switch and rules, and the hook entries in Claude Code and Codex settings.
set -euo pipefail
pkill -x SafetyAI 2>/dev/null || true
rm -rf ~/Applications/"Safety AI.app" ~/Library/LaunchAgents/local.safety-ai.plist "$HOME/Library/Application Support/Safety AI"
rm -f ~/.claude/hooks/isolation.sh ~/.claude/isolation ~/.claude/isolation.conf   # older versions
defaults delete local.safety-ai 2>/dev/null || true
for f in ~/.claude/settings.json ~/.codex/hooks.json; do
  [ -f "$f" ] && grep -q 'isolation.sh' "$f" || continue
  cp "$f" "$f.bak-uninstall"
  jq '(.hooks.PreToolUse, .hooks.UserPromptSubmit) |= ((. // []) | map(select(all(.hooks[]; (.command | contains("isolation.sh")) | not))))' \
    "$f.bak-uninstall" > "$f"
done
echo "Removed."
