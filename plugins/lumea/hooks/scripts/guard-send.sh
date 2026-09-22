#!/usr/bin/env bash
# PreToolUse: пишущие инструменты Lumea всегда идут через подтверждение —
# даже в auto-режиме и даже если инструмент в allow-списке. Печатает
# permissionDecision "ask" с человеческим описанием того, что произойдёт;
# заведомо неверный вызов (пустая рассылка, незаполненный плейсхолдер) — "deny".
# Список инструментов в case обязан совпадать с матчером в hooks.json.
set -euo pipefail

# Отказоустойчивость: ненулевой код (кроме 2) с пустым stdout Claude Code не
# блокирует, и в auto-режиме отправка ушла бы без диалога. Поэтому без jq и
# при любой ошибке разбора (битый stdin, items не массив) печатаем
# статический ask — подтверждение остаётся за человеком.
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
tool=$(jq -r '.tool_name // ""' <<<"$input" | sed -E 's/^mcp__(plugin_lumea_lumea|lumea)__//')

# Первые 200 символов текста одной строкой, с многоточием при обрезке.
preview() { jq -rn --arg t "$1" '$t | gsub("\n"; " ") | if length > 200 then .[0:200] + "…" else . end'; }
# Тот же формат, что у ticketRef в lib/utils/ticket-ref.ts: «#» и первая
# группа uuid (8 символов) — оператор сверяет ref в вопросе с шапкой тикета.
short_ref() { printf '#%s' "$(printf '%s' "$1" | cut -c1-8)"; }

decide() { # $1 = allow|ask|deny, $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  decided=1
}

case "$tool" in
  send_message)
    ticket=$(jq -r '.tool_input.ticketId // ""' <<<"$input")
    text=$(jq -r '.tool_input.content // "" | sub("^\\s+"; "")' <<<"$input") # zod trim() до проверки «#»
    # Текст с «#» в начале сервер сохраняет как внутреннюю заметку (schema
    # send_message в modules/mcp/tools/messages.ts) — клиент его не увидит.
    case "$text" in
      '#'*) decide ask "Lumea: внутренняя заметка (клиент не увидит) в тикет $(short_ref "$ticket"): «$(preview "$text")»" ;;
      *) decide ask "Lumea: отправить клиенту в тикет $(short_ref "$ticket"): «$(preview "$text")»" ;;
    esac
    ;;
  send_quick_reply)
    ticket=$(jq -r '.tool_input.ticketId // ""' <<<"$input")
    shortcut=$(jq -r '.tool_input.shortcut // ""' <<<"$input")
    decide ask "Lumea: отправить быстрый ответ «${shortcut}» клиенту в тикет $(short_ref "$ticket")"
    ;;
  bulk_send_messages)
    count=$(jq -r '.tool_input.items // [] | length' <<<"$input")
    if [ "$count" = "0" ]; then
      decide deny "Lumea: bulk_send_messages без items — некому отправлять"
      exit 0
    fi
    if jq -e '[.tool_input.items[] | (.content // "") | test("\\{\\{")] | any' <<<"$input" >/dev/null; then
      decide deny "Lumea: в тексте остался незаполненный плейсхолдер {{…}} — подставьте значения перед отправкой"
      exit 0
    fi
    first=$(jq -r '.tool_input.items[0].content // ""' <<<"$input")
    decide ask "Lumea: отправить сообщения в $count тикет(ов). Первый текст: «$(preview "$first")»"
    ;;
  block_client)
    client=$(jq -r '.tool_input.clientId // ""' <<<"$input")
    duration=$(jq -r '.tool_input.duration // "permanent"' <<<"$input")
    decide ask "Lumea: заблокировать клиента $client на $duration — бот перестанет ему отвечать"
    ;;
  run_external_action)
    action=$(jq -r '.tool_input.actionId // ""' <<<"$input")
    client=$(jq -r '.tool_input.clientId // ""' <<<"$input")
    project=$(jq -r '.tool_input.projectType // ""' <<<"$input")
    decide ask "Lumea: выполнить действие «${action}» во внешнем сервисе ($project) для клиента $client"
    ;;
  create_issue_from_ticket)
    ticket=$(jq -r '.tool_input.ticketId // ""' <<<"$input")
    force=$(jq -r '.tool_input.force // false' <<<"$input")
    title=$(jq -r '.tool_input.title // "черновик сервера"' <<<"$input")
    decide ask "Lumea: создать issue в GitLab из тикета $(short_ref "$ticket") (заголовок: $title, force=$force)"
    ;;
  link_issue)
    ticket=$(jq -r '.tool_input.ticketId // ""' <<<"$input")
    iid=$(jq -r '.tool_input.iid // ""' <<<"$input")
    decide ask "Lumea: привязать тикет $(short_ref "$ticket") к issue #$iid и оставить в нём комментарий"
    ;;
  toggle_ai)
    ticket=$(jq -r '.tool_input.ticketId // ""' <<<"$input")
    # `//` в jq считает false пустым — enable=false потерялся бы.
    enable=$(jq -r '.tool_input.enable | if . == null then "" else tostring end' <<<"$input")
    decide ask "Lumea: AI на тикете $(short_ref "$ticket") → enable=$enable"
    ;;
  create_quick_reply|update_quick_reply)
    # Общий для create и update: у create shortcut обязателен, у update — любое
    # подмножество полей; чего нет во входе, того нет и в тексте вопроса.
    shortcut=$(jq -r '.tool_input.shortcut // ""' <<<"$input")
    text=$(jq -r '.tool_input.text // ""' <<<"$input")
    id=$(jq -r '.tool_input.id // ""' <<<"$input")
    if [ "$tool" = "create_quick_reply" ]; then
      verb="создать быстрый ответ «${shortcut}»"
    else
      fields=$(jq -r '[.tool_input | to_entries[] | select(.key != "id") | .key] | join(", ")' <<<"$input")
      verb="изменить быстрый ответ ${id} (поля: ${fields})"
      [ -n "$shortcut" ] && verb="$verb → shortcut «${shortcut}»"
    fi
    [ -n "$text" ] && verb="$verb: «$(preview "$text")»"
    decide ask "Lumea: $verb"
    ;;
  delete_quick_reply)
    # shortcut во входе — только для подтверждения (сервер сверяет его с
    # строкой); без него показываем id.
    shortcut=$(jq -r '.tool_input.shortcut // ""' <<<"$input")
    id=$(jq -r '.tool_input.id // ""' <<<"$input")
    if [ -n "$shortcut" ]; then
      decide ask "Lumea: удалить быстрый ответ «${shortcut}» ($id) вместе с файлами — необратимо"
    else
      decide ask "Lumea: удалить быстрый ответ $id вместе с файлами — необратимо"
    fi
    ;;
  create_broadcast)
    # Создание само ничего не шлёт, но замораживает выборку и заводит джоб на
    # каждый тикет — человек должен увидеть потолок и фильтры до этого.
    name=$(jq -r '.tool_input.name // ""' <<<"$input")
    max=$(jq -r '.tool_input.maxRecipients // ""' <<<"$input")
    statuses=$(jq -r '.tool_input.statuses // [] | join(", ")' <<<"$input")
    project=$(jq -r '.tool_input.projectName // "все проекты"' <<<"$input")
    if [ -z "$max" ]; then
      decide deny "Lumea: create_broadcast без maxRecipients — потолок получателей обязателен"
      exit 0
    fi
    decide ask "Lumea: создать рассылку «${name}» (${project}, статусы: ${statuses}, потолок ${max} получателей). Отправка начнётся отдельно, по start_broadcast"
    ;;
  start_broadcast|resume_broadcast)
    id=$(jq -r '.tool_input.broadcastId // ""' <<<"$input")
    if [ "$tool" = "start_broadcast" ]; then
      decide ask "Lumea: ЗАПУСТИТЬ рассылку $id — сообщения уйдут клиентам по всей очереди"
    else
      decide ask "Lumea: возобновить остановленную рассылку $id — отправка продолжится клиентам"
    fi
    ;;
  retry_broadcast)
    id=$(jq -r '.tool_input.broadcastId // ""' <<<"$input")
    decide ask "Lumea: повторить упавшие джобы рассылки $id — сообщения уйдут клиентам заново"
    ;;
  cancel_broadcast)
    # Остановка ничего не шлёт, но обрывает идущую кампанию на середине —
    # часть клиентов получит сообщение, часть нет.
    id=$(jq -r '.tool_input.broadcastId // ""' <<<"$input")
    decide ask "Lumea: остановить рассылку $id — оставшиеся получатели не получат сообщение"
    ;;
  *)
    exit 0
    ;;
esac
