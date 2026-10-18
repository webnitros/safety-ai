#!/bin/bash
# Ставит хук режима изоляции в Claude Code и приложение-тумблер в строку меню. Повторный запуск безопасен.
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "Нужен jq" >&2; exit 1; }

# 1. Хук
hook=~/.claude/hooks/isolation.sh
settings=~/.claude/settings.json
mkdir -p ~/.claude/hooks
cp hooks/isolation.sh "$hook"
chmod +x "$hook"
[ -f "$settings" ] || echo '{}' > "$settings"
if ! grep -q 'hooks/isolation.sh' "$settings"; then
  cp "$settings" "$settings.bak-isolation"
  jq --arg h "$hook" '
    .hooks.PreToolUse += [{"matcher":"Bash|mcp__.*__(add_commit|add_branch|accept_merge_request|save_merge_request)","hooks":[{"type":"command","command":$h,"timeout":10}]}]
    | .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":($h+" prompt"),"timeout":10}]}]
  ' "$settings.bak-isolation" > "$settings"
  echo "Хук подключён в $settings (копия: $settings.bak-isolation)"
fi

# 2. Приложение
app=~/Applications/"Safety AI.app"
agent=~/Library/LaunchAgents/local.safety-ai.plist
pkill -x SafetyAI 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
# CLT 6.3 не дружит с SDK 27, берём 26.5 если есть
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$sdk" ] || sdk=$(xcrun --show-sdk-path)
swiftc -O -sdk "$sdk" app/main.swift -o "$app/Contents/MacOS/SafetyAI"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.safety-ai</string>
  <key>CFBundleName</key><string>Safety AI</string>
  <key>CFBundleExecutable</key><string>SafetyAI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$app"

# 3. Автозапуск при входе
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.safety-ai</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF

open "$app"
echo "Готово: замок в строке меню."
