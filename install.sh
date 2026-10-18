#!/bin/bash
# Installs the Safety AI hook into Claude Code (and Codex, if present) and the menu bar app. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

dir="$HOME/Library/Application Support/Safety AI"
hook="$dir/isolation.sh"
app=~/Applications/"Safety AI.app"
agent=~/Library/LaunchAgents/local.safety-ai.plist
first_install=$([ -d "$app" ] && echo no || echo yes)

# 1. Hook and state, moved out of ~/.claude by older versions
mkdir -p "$dir"
cp hooks/isolation.sh "$hook"
chmod +x "$hook"
[ -f ~/.claude/isolation.conf ] && [ ! -f "$dir/rules.conf" ] && mv ~/.claude/isolation.conf "$dir/rules.conf"
[ -f ~/.claude/isolation ] && mv ~/.claude/isolation "$dir/isolation"
rm -f ~/.claude/isolation.conf ~/.claude/hooks/isolation.sh

# register(file, agent name, PreToolUse matcher): drops our old entries, adds current ones.
# PreToolUse waits up to 120 s for the Allow/Deny dialog.
register() {
  local file=$1 cmd="SAFETY_AI_AGENT=$2 \"$hook\"" matcher=$3 tmp
  [ -f "$file" ] || echo '{}' > "$file"
  [ -f "$file.bak-isolation" ] || cp "$file" "$file.bak-isolation"
  tmp=$(mktemp)
  jq --arg c "$cmd" --arg m "$matcher" '
    (.hooks.PreToolUse, .hooks.UserPromptSubmit) |= ((. // []) | map(select(all(.hooks[]; (.command | contains("isolation.sh")) | not))))
    | .hooks.PreToolUse += [({"hooks":[{"type":"command","command":$c,"timeout":120}]} + (if $m == "" then {} else {"matcher":$m} end))]
    | .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":($c+" prompt"),"timeout":10}]}]
  ' "$file" > "$tmp"
  cat "$tmp" > "$file" && rm "$tmp"
  echo "Hook registered in $file (original backup: $file.bak-isolation)"
}
register ~/.claude/settings.json Claude 'Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__.*'
# Codex support is paused: drop the hook an earlier version registered there
if [ -f ~/.codex/hooks.json ] && grep -q 'isolation.sh' ~/.codex/hooks.json; then
  tmp=$(mktemp)
  jq '(.hooks.PreToolUse, .hooks.UserPromptSubmit) |= ((. // []) | map(select(all(.hooks[]; (.command | contains("isolation.sh")) | not))))' \
    ~/.codex/hooks.json > "$tmp"
  cat "$tmp" > ~/.codex/hooks.json && rm "$tmp"
  echo "Hook removed from ~/.codex/hooks.json"
fi

# 2. App
pkill -x SafetyAI 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Command Line Tools may ship a Swift older than the newest SDK; prefer 26.5 when present
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$sdk" ] || sdk=$(xcrun --show-sdk-path)
swiftc -O -sdk "$sdk" app/main.swift -o "$app/Contents/MacOS/SafetyAI"
cp -R app/*.lproj app/AppIcon.icns "$app/Contents/Resources/"
langs=$(cd app && ls -d *.lproj | sed 's/\.lproj$//; s|.*|<string>&</string>|' | tr -d '\n')
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.safety-ai</string>
  <key>CFBundleName</key><string>Safety AI</string>
  <key>CFBundleExecutable</key><string>SafetyAI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$langs</array>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$app"

# 3. Start at login: on for a fresh install; later the app's "Launch at login" switch owns it
if [ "$first_install" = yes ]; then
  cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.safety-ai</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>$app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
fi

open "$app"
echo "Done: lock icon is in the menu bar."
