#!/usr/bin/env bash
# SessionStart: без адреса или ключа сервер lumea всё равно загрузится, но
# каждый вызов упадёт (без LUMEA_URL в url остаётся литерал `${LUMEA_URL}`,
# без ключа — 401) — подсказываем один раз, одним сообщением на обе
# переменные. Сетевых вызовов здесь нет намеренно.
set -euo pipefail
# stdin не читаем: он не нужен, а без jq в PATH может не быть и cat.
if ! command -v jq >/dev/null; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Lumea: не установлен jq — хуки плагина lumea не смогут разобрать вызовы и будут просить подтверждение на каждый пишущий инструмент. Предложить пользователю brew install jq."}}'
  exit 0
fi
missing=()
[ -n "${LUMEA_URL:-}" ] || missing+=(LUMEA_URL)
[ -n "${LUMEA_ACCESS_KEY:-}" ] || missing+=(LUMEA_ACCESS_KEY)
[ "${#missing[@]}" -gt 0 ] || exit 0
if [ "${#missing[@]}" -eq 1 ]; then
  names="переменная ${missing[0]} не задана"
else
  names="переменные ${missing[0]} и ${missing[1]} не заданы"
fi
jq -n --arg names "$names" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Lumea: " + $names + " — инструменты lumea не ответят. Подсказать пользователю /lumea:setup, если он заговорит о тикетах.")}}'
