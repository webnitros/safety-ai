#!/bin/bash
# Claude Code hook. While ~/.claude/isolation exists, Claude does not commit or push in any repository.
# Enable: touch ~/.claude/isolation   Disable: rm ~/.claude/isolation
flag=~/.claude/isolation
in=$(cat)
[ -f "$flag" ] || exit 0

if [ "$1" = prompt ]; then
  echo "ISOLATION MODE IS ON: do not run git commit/push/merge/rebase/tag or create MRs/PRs, and do not offer or ask about committing. Leave changes in the working tree."
  exit 0
fi

tool=$(jq -r '.tool_name // ""' <<<"$in")
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")

if [ "$tool" = Bash ]; then
  grep -q 'claude/isolation' <<<"$cmd" && { echo "Only the user can turn isolation mode off" >&2; exit 2; }
  grep -qE '(^|[^[:alnum:]_/-])git( +-[cC] +[^ ]+)* +(commit|push|merge|rebase|cherry-pick|am|tag)([^[:alnum:]-]|$)' <<<"$cmd" || exit 0
fi

echo "Isolation mode: commits and pushes are blocked. Leave changes in the working tree and do not ask about committing." >&2
exit 2
