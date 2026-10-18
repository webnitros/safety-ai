#!/bin/bash
# Hook tests with a temporary state dir. Usage: ./test.sh hooks/isolation.sh
h=$1; d=$(mktemp -d); export SAFETY_AI_DIR=$d
F=$d/isolation C=$d/rules.conf
fails=0
check() { # want json
  "$h" >/dev/null 2>&1 <<<"$2"; got=$?
  [ "$got" = "$1" ] || { echo "FAIL want=$1 got=$got $2"; fails=$((fails+1)); }
}
run() { check "$1" "$(jq -nc --arg t "$2" --arg c "$3" '{tool_name:$t,tool_input:{command:$c}}')"; }
file() { check "$1" "$(jq -nc --arg t "$2" --arg p "$3" '{tool_name:$t,tool_input:{file_path:$p,content:"x",old_string:"a",new_string:"b"}}')"; }

echo "-- flag off: everything passes"
run 0 Bash "git push"; run 0 mcp__gitlab__add_commit ""

echo "-- settings are protected even with isolation off"
S="$HOME/Library/Application Support/Safety AI"
run 2 Bash "rm '$S/rules.conf'"; run 2 Bash "pkill SafetyAI"
run 2 Bash 'ls ~/Library/Application\ Support/Safety\ AI'; run 2 Bash "cat ~/Library/'Application Support'/\"Safety AI\"/rules.conf"
run 0 Bash "cd ~/ASTRA/safety-ai && ./test.sh hooks/isolation.sh"; run 2 Bash "defaults write local.safety-ai showInDock -bool true"
file 2 Write "$S/rules.conf"; file 2 Edit "$S/isolation.sh"; file 2 Write "$HOME/Library/LaunchAgents/local.safety-ai.plist"
check 2 '{"tool_name":"apply_patch","tool_input":{"command":["apply_patch","*** Begin Patch\n*** Delete File: /Users/x/Library/Application Support/Safety AI/rules.conf\n*** End Patch"]}}'
run 2 Bash "jq 'del(.hooks.PreToolUse[] | select(.hooks[0].command | contains(\"isolation\")))' ~/.claude/settings.json"
check 2 '{"tool_name":"Edit","tool_input":{"file_path":"/u/.claude/settings.json","old_string":"\"/u/Library/Application Support/Safety AI/isolation.sh\"","new_string":""}}'
check 0 '{"tool_name":"Edit","tool_input":{"file_path":"/u/.claude/settings.json","old_string":"\"theme\": \"dark\"","new_string":"\"theme\": \"light\""}}'
run 0 Bash "cat ~/.claude/settings.json"; file 0 Write "$d/notes.md"; run 0 Bash "ls ~/Library/Application\ Support"

touch $F
echo "-- no conf: all built-in rules"
run 2 Bash "git commit -m x"; run 2 Bash "cd a && git push origin main"; run 2 Bash "git rebase main"
run 2 Bash "git tag v1"; run 2 Bash "gh pr create --fill"; run 2 Bash "gh repo create x --push"
run 2 mcp__gitlab__add_commit ""; run 2 mcp__GitLab__save_merge_request ""
run 0 Bash "git status"; run 0 Bash "git log --grep commit"; run 0 Bash "gh pr list"; run 0 Bash "rm -rf build"

echo "-- timed isolation: end time in the flag"
echo $(( $(date +%s) + 600 )) > $F; run 2 Bash "git commit -m x"
echo $(( $(date +%s) - 1 )) > $F; run 0 Bash "git commit -m x"; run 2 Bash "rm '$S/isolation'"
: > $F

echo "-- Codex: argv-array command, cmd field"
check 2 '{"tool_name":"shell","tool_input":{"command":["bash","-lc","git push origin main"]}}'
check 0 '{"tool_name":"shell","tool_input":{"command":["bash","-lc","git status"]}}'
check 2 '{"tool_name":"exec_command","tool_input":{"cmd":"/bin/zsh -lc \"git commit -m x\"","workdir":"/tmp"}}'
check 0 '{"tool_name":"exec_command","tool_input":{"cmd":"/bin/zsh -lc \"git status\""}}'
check 2 '{"tool_name":"exec_command","tool_input":{"cmd":"ls ~/Library/Application\\ Support/Safety\\ AI"}}'
check 2 '{"tool_name":"some_new_tool","tool_input":{"target":"/Users/x/Library/Application Support/Safety AI/rules.conf"}}'
check 0 '{"tool_name":"mcp__outline__create_document","tool_input":{"title":"Safety AI notes"}}'

echo "-- conf: only commit + custom deny"
printf '# comment\ncommit\ndeny rm +-rf\ndeny docker +compose +down\n' > $C
run 2 Bash "git commit -m x"; run 2 mcp__gitlab__add_commit ""
run 0 Bash "git push"; run 0 Bash "gh pr create"; run 0 mcp__gitlab__save_merge_request ""
run 2 Bash "rm -rf build"; run 2 Bash "docker compose down -v"; run 0 Bash "docker compose up -d"

echo "-- empty conf: nothing blocked"
printf '# all off\n' > $C
run 0 Bash "git commit -m x"; run 0 Bash "git push"; run 0 mcp__gitlab__add_commit ""

echo "-- ask mode: fake dialog answers"
printf 'commit\nask\n' > $C
fake=$d/fake-dialog; printf '#!/bin/bash\necho "$2" > "%s/last-dialog"\n[ "$FAKE" = allow ] && echo "$4" || echo "$3"\n' "$d" > $fake; chmod +x $fake
export SAFETY_AI_DIALOG=$fake
FAKE=allow run 0 Bash "git commit -m x"; FAKE=deny run 2 Bash "git commit -m x"
FAKE=allow run 0 mcp__gitlab__add_commit ""; FAKE=deny run 2 mcp__gitlab__add_commit ""
FAKE=allow run 0 Bash "git push"   # push not in rules, no dialog needed
FAKE=allow run 2 Bash "rm '$S/isolation'"   # self-protection never asks
SAFETY_AI_AGENT=Codex FAKE=deny run 2 Bash "git commit -m x"
grep -q Codex $d/last-dialog || { echo "FAIL dialog does not name Codex"; fails=$((fails+1)); }
out=$(echo '{}' | "$h" prompt); grep -q "ask mode" <<<"$out" || { echo "FAIL ask reminder: $out"; fails=$((fails+1)); }
unset SAFETY_AI_DIALOG

echo "-- prompt text"
printf 'push\npr\ndeny rm +-rf\n' > $C; echo '{}' | "$h" prompt
printf '' > $C; out=$(echo '{}' | "$h" prompt); [ -z "$out" ] && echo "(empty conf -> no reminder)" || { echo "FAIL reminder: $out"; fails=$((fails+1)); }

rm -rf "$d"; echo "fails=$fails"; [ $fails = 0 ]
