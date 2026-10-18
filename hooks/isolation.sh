#!/bin/bash
# Режим изоляции: пока есть ~/.claude/isolation, Claude не коммитит и не пушит ни в один репозиторий.
# Включить: touch ~/.claude/isolation   Выключить: rm ~/.claude/isolation
flag=~/.claude/isolation
in=$(cat)
[ -f "$flag" ] || exit 0

if [ "$1" = prompt ]; then
  echo "РЕЖИМ ИЗОЛЯЦИИ ВКЛЮЧЁН: не делай git commit/push/merge/rebase/tag и MR, не предлагай и не спрашивай про коммит. Изменения оставляй в рабочем дереве."
  exit 0
fi

tool=$(jq -r '.tool_name // ""' <<<"$in")
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")

if [ "$tool" = Bash ]; then
  grep -q 'claude/isolation' <<<"$cmd" && { echo "Режим изоляции выключает только Alex" >&2; exit 2; }
  grep -qE '(^|[^[:alnum:]_/-])git( +-[cC] +[^ ]+)* +(commit|push|merge|rebase|cherry-pick|am|tag)([^[:alnum:]-]|$)' <<<"$cmd" || exit 0
fi

echo "Режим изоляции: коммиты и пуши запрещены. Оставь изменения в рабочем дереве и не спрашивай про коммит." >&2
exit 2
