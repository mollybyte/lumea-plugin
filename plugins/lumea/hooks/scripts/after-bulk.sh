#!/usr/bin/env bash
# PostToolUse для массовых инструментов: сводная строка "failed: N" и
# "nextIndex: N" легко теряются, и модель отчитывается «готово». Добавляем в
# контекст напоминание перечислить неудачи поштучно и продолжить с nextIndex.
set -euo pipefail
# Ошибка разбора (битый stdin) — не повод для ненулевого кода: подсказки нет,
# но и «ошибка хука» в транскрипте не нужна. Молчим с кодом 0.
trap '[ $? -eq 0 ] || exit 0' EXIT
command -v jq >/dev/null || exit 0

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input" | sed -E 's/^mcp__(plugin_lumea_lumea|lumea)__//')

# Форма tool_response для MCP-инструментов не зафиксирована документацией;
# на практике Claude Code отдаёт массив блоков [{type:"text",text:"<JSON>"}]
# без structuredContent. Берём structuredContent, если вдруг есть, иначе —
# JSON из первого текстового блока (сервер кладёт туда тот же объект,
# modules/mcp/tool.ts jsonResult), будь tool_response объектом с content,
# массивом блоков или строкой.
result=$(jq -c '
  .tool_response
  | if type == "object" and has("structuredContent") then .structuredContent
    elif type == "object" then .content[0].text?
    elif type == "array" then .[0].text?
    else . end
  | if type == "string" then (try fromjson catch null) else . end
  | if type == "object" then . else null end
' <<<"$input")
[ "$result" != "null" ] || exit 0

# bulk_send_messages: failed — число; bulk_update_tickets: failed — массив.
failed=$(jq -r '.failed // 0 | if type == "array" then length else . end' <<<"$result")
next=$(jq -r '.nextIndex // "null"' <<<"$result")

case "$tool" in
  bulk_send_messages) arg=items ;;
  *) arg=ticketIds ;;
esac

parts=()
if [ "$failed" != "0" ] && [ "$failed" != "null" ]; then
  parts+=("Lumea: $failed вызов(ов) не выполнен(о). Перечислить их поштучно (ticketId и причина из results/failed), не отчитываться «готово» по счётчику.")
fi
if [ "$next" != "null" ]; then
  parts+=("Lumea: выполнено частично — сервер исчерпал бюджет времени на элементе $next. Продолжить тем же вызовом с $arg.slice($next) и свести итог по всем частям, не отчитываться по первой.")
fi
[ "${#parts[@]}" -gt 0 ] || exit 0

printf '%s\n' "${parts[@]}" | jq -Rs \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: (rtrimstr("\n"))}}'
