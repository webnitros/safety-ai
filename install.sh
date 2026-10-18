#!/bin/bash
# Installs the isolation hook into Claude Code and the menu bar toggle app. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# 1. Hook
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
  echo "Hook registered in $settings (backup: $settings.bak-isolation)"
fi

# 2. App
app=~/Applications/"Safety AI.app"
agent=~/Library/LaunchAgents/local.safety-ai.plist
pkill -x SafetyAI 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Command Line Tools may ship a Swift older than the newest SDK; prefer 26.5 when present
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$sdk" ] || sdk=$(xcrun --show-sdk-path)
swiftc -O -sdk "$sdk" app/main.swift -o "$app/Contents/MacOS/SafetyAI"
cp -R app/*.lproj "$app/Contents/Resources/"
langs=$(cd app && ls -d *.lproj | sed 's/\.lproj$//; s|.*|<string>&</string>|' | tr -d '\n')
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.safety-ai</string>
  <key>CFBundleName</key><string>Safety AI</string>
  <key>CFBundleExecutable</key><string>SafetyAI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$langs</array>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$app"

# 3. Start at login
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
echo "Done: lock icon is in the menu bar."
