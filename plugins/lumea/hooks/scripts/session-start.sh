#!/usr/bin/env bash
# SessionStart: без ключа сервер lumea всё равно загрузится, но каждый вызов
# упадёт в 401 — подсказываем один раз. Сетевых вызовов здесь нет намеренно.
set -euo pipefail
# stdin не читаем: он не нужен, а без jq в PATH может не быть и cat.
if ! command -v jq >/dev/null; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Lumea: не установлен jq — хуки плагина lumea не смогут разобрать вызовы и будут просить подтверждение на каждый пишущий инструмент. Предложить пользователю brew install jq."}}'
  exit 0
fi
[ -z "${LUMEA_ACCESS_KEY:-}" ] || exit 0
jq -n '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: "Lumea: переменная LUMEA_ACCESS_KEY не задана — инструменты lumea ответят 401. Подсказать пользователю /lumea:setup, если он заговорит о тикетах."}}'
