#!/bin/bash
# Safety AI hook for Claude Code and Codex (same hook format: tool_input.command, exit 2 = block).
# Always: agents may not touch Safety AI's own files or unregister this hook.
# While the isolation flag exists: blocks what rules.conf lists.
# rules.conf lines: built-in rules (commit, push, merge, tag, pr), "deny <regex>" for shell commands,
# and "ask" to show an Allow/Deny dialog instead of blocking outright. No file = all built-in rules on.
dir=${SAFETY_AI_DIR:-"$HOME/Library/Application Support/Safety AI"}
flag=$dir/isolation
conf=$dir/rules.conf
agent=${SAFETY_AI_AGENT:-Claude}
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in")
# Codex may call the field cmd and pass the command as an argv array
cmd=$(jq -r '.tool_input | objects | (.command // .cmd // "") | if type == "array" then join(" ") else . end' <<<"$in")

self() { echo "Safety AI settings can only be changed by the user in the Safety AI app." >&2; exit 2; }

if [ "$1" != prompt ]; then
  # what this call touches: shell command, file paths of edit tools, or the whole patch for apply_patch
  targets=$cmd$'\n'$(jq -r '.tool_input | [.file_path?, .notebook_path?, .path?] | map(select(. != null)) | .[]' <<<"$in" 2>/dev/null)
  # apply_patch, and unknown non-MCP tools with no command or path: look at all their arguments
  case $tool in
    *apply_patch*) targets+=$'\n'$(jq -c '.tool_input' <<<"$in") ;;
    mcp__*) ;;
    *) [ -z "${targets//[[:space:]]/}" ] && targets=$(jq -c '.tool_input // ""' <<<"$in") ;;
  esac
  # drop shell quoting so Safety\ AI, "Safety AI" and 'Safety'' AI' all look the same
  tr -d '\\"'"'" <<<"$targets" | grep -qiE 'safety +ai|safetyai|local\.safety-ai' && self

  # removing the hook from the agents' settings files
  if grep -qE '(settings|hooks)\.json' <<<"$targets"; then
    case $tool in
      Bash) grep -qiE 'isolation|safety' <<<"$cmd" && self ;;
      Edit) jq -e '(.tool_input.old_string | test("Safety AI")) and (.tool_input.new_string | test("Safety AI") | not)' <<<"$in" >/dev/null && self ;;
      MultiEdit) jq -e 'any(.tool_input.edits[]; (.old_string | test("Safety AI")) and (.new_string | test("Safety AI") | not))' <<<"$in" >/dev/null && self ;;
      Write)
        f=$(jq -r '.tool_input.file_path' <<<"$in")
        grep -q 'Safety AI' "$f" 2>/dev/null && ! jq -e '.tool_input.content | test("Safety AI")' <<<"$in" >/dev/null && self ;;
    esac
  fi
fi

[ -f "$flag" ] || exit 0
# the flag may hold an end time (unix seconds) when isolation was turned on for a while
until=$(tr -cd 0-9 < "$flag")
[ -n "$until" ] && [ "$(date +%s)" -ge "$until" ] && exit 0

if [ -f "$conf" ]; then rules=$(grep -vE '^[[:space:]]*(#|$)' "$conf"); else rules=$(printf 'commit\npush\nmerge\ntag\npr'); fi
on() { grep -qx "$1" <<<"$rules"; }
join() { local IFS='|'; echo "$*"; }

git=() gh=() mcp=() what=()
on commit && { git+=(commit am cherry-pick); mcp+=(add_commit); what+=(commits); }
on push   && { git+=(push); gh+=("repo +(create|sync)"); mcp+=(add_branch); what+=("push/new remote branches"); }
on merge  && { git+=(merge rebase); what+=("merge/rebase"); }
on tag    && { git+=(tag); gh+=("release +create"); what+=("tags/releases"); }
on pr     && { gh+=("pr +(create|merge)"); mcp+=(save_merge_request accept_merge_request); what+=("PR/MR"); }
deny=$(sed -n 's/^deny  *//p' <<<"$rules")

if [ "$1" = prompt ]; then
  [ ${#what[@]} -eq 0 ] && [ -z "$deny" ] && exit 0
  list=$(join "${what[@]}" | sed 's/|/, /g')
  [ -n "$deny" ] && list+="; shell commands matching: $(tr '\n' ' ' <<<"$deny")"
  if on ask; then
    echo "ISOLATION MODE IS ON (ask mode). These need the user's approval: $list. When you run one, the user gets an Allow/Deny popup, so do not ask in chat. If it is denied, leave changes in the working tree."
  else
    echo "ISOLATION MODE IS ON. Do not do: $list. Do not offer or ask to do these. Leave changes in the working tree."
  fi
  exit 0
fi

cwd=$(jq -r '.cwd // ""' <<<"$in")

# Allow/Deny dialog; prints the pressed button. Deny is the default, no answer in 90 s = deny.
# The app draws it with a countdown; plain AppleScript is the fallback when the app is not installed.
dialog() {
  [ -n "${SAFETY_AI_DIALOG:-}" ] && { "$SAFETY_AI_DIALOG" "$@"; return; }
  local app_bin="$HOME/Applications/Safety AI.app/Contents/MacOS/SafetyAI"
  [ -x "$app_bin" ] && { "$app_bin" --ask "$@" 90 2>/dev/null; return; }
  osascript - "$@" "$HOME/Applications/Safety AI.app/Contents/Resources/AppIcon.icns" <<'EOF' 2>/dev/null
on run argv
  set ic to caution
  try
    set ic to (POSIX file (item 5 of argv)) as alias
  end try
  tell me to activate
  set r to display dialog (item 2 of argv) with title (item 1 of argv) buttons {item 3 of argv, item 4 of argv} ¬
    default button (item 3 of argv) cancel button (item 3 of argv) with icon ic giving up after 90
  return button returned of r
end run
EOF
}

# returns 0 if the user allowed the action in the dialog
allowed() {
  on ask || return 1
  local what=${cmd:-$tool}
  [ ${#what} -gt 400 ] && what="${what:0:400}…"
  if defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | grep -q ru; then
    set -- "Safety AI" "$agent хочет выполнить:

$what

Папка: $cwd" "Запретить" "Разрешить"
  else
    set -- "Safety AI" "$agent wants to run:

$what

Folder: $cwd" "Deny" "Allow"
  fi
  [ "$(dialog "$@")" = "$4" ]
}

block() {
  allowed && exit 0
  echo "Isolation mode blocks this ($1). Leave changes in the working tree and do not ask about it." >&2
  exit 2
}

if [ -n "$cmd" ]; then
  [ ${#git[@]} -gt 0 ] && grep -qE "(^|[^[:alnum:]_/-])git( +-[cC] +[^ ]+)* +($(join "${git[@]}"))([^[:alnum:]-]|$)" <<<"$cmd" && block git
  [ ${#gh[@]} -gt 0 ] && grep -qE "(^|[^[:alnum:]_/-])gh +($(join "${gh[@]}"))([^[:alnum:]-]|$)" <<<"$cmd" && block gh
  while IFS= read -r re; do [ -n "$re" ] && grep -qE -- "$re" <<<"$cmd" && block "deny $re"; done <<<"$deny"
  exit 0
fi

[ ${#mcp[@]} -gt 0 ] && grep -qE "__($(join "${mcp[@]}"))$" <<<"$tool" && block "$tool"
exit 0
