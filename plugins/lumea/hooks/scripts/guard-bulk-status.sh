#!/usr/bin/env bash
# PreToolUse для bulk_update_tickets: смена статуса многим тикетам — через
# подтверждение; теги и приоритет дёшевы и обратимы, их пропускаем молча
# (пустой вывод, код 0 — решает обычный поток разрешений Claude Code).
set -euo pipefail

# Без jq не разобрать, есть ли status, а ошибка разбора с пустым stdout не
# блокирует вызов — в обоих случаях статический ask (см. guard-send.sh).
static_ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Lumea: %s — подтвердите вручную"}}\n' "$1"
}
decided=0
on_exit() {
  local code=$?
  if [ "$code" -ne 0 ] && [ "$decided" -eq 0 ]; then
    static_ask "не удалось разобрать вход хука"
    exit 0
  fi
}
trap on_exit EXIT

if ! command -v jq >/dev/null; then
  decided=1
  static_ask "jq не установлен (brew install jq)"
  exit 0
fi

input=$(cat)
status=$(jq -r '.tool_input.status // ""' <<<"$input")
[ -n "$status" ] || exit 0
count=$(jq -r '.tool_input.ticketIds | if type == "array" then length else 0 end' <<<"$input")
jq -n --arg r "Lumea: сменить статус $count тикет(ов) на $status" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
decided=1
