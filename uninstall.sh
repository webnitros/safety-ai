#!/bin/bash
# Убирает приложение, автозапуск, хук и флаг. settings.json чистится от записей isolation.sh.
set -euo pipefail
pkill -x SafetyAI 2>/dev/null || true
rm -rf ~/Applications/"Safety AI.app" ~/Library/LaunchAgents/local.safety-ai.plist ~/.claude/hooks/isolation.sh ~/.claude/isolation
settings=~/.claude/settings.json
if [ -f "$settings" ] && grep -q 'hooks/isolation.sh' "$settings"; then
  cp "$settings" "$settings.bak-uninstall"
  jq '(.hooks.PreToolUse, .hooks.UserPromptSubmit) |= map(select(all(.hooks[]; (.command | contains("hooks/isolation.sh")) | not)))' \
    "$settings.bak-uninstall" > "$settings"
fi
echo "Удалено."
