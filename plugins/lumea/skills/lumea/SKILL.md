---
name: lumea
description: Справочник по Lumea (CRM поддержки Sota и Faygo) для любого разговора о тикетах, клиентах, очереди поддержки, кейсах, issue, сменах, логах и жалобах клиентов — модель данных, форматы id, какой MCP-инструмент для чего, лимиты и правила безопасности. Загружается при первой реплике по теме, до вызова любого инструмента lumea. Триггеры — «Lumea», «тикет», «что там с тикетом», «кто жаловался», «напиши клиентам», «очередь», «открой кейс», «сводка за смену», «кто на смене», «логи клиента», «подписка клиента», «ticket», «customer», «support queue», «shift», «complaint», «open a case», «who's on shift», «what's in the queue», «group the tickets», «notify the customers», «customer logs».
user-invocable: false
---

# Lumea из Claude Code

Lumea — CRM поддержки проектов Sota и Faygo. MCP-сервер `lumea` даёт ровно те права, что у владельца ключа в браузере; каждый вызов попадает в аудит с пометкой `via: mcp`. Слэш-скиллы плагина — горячие клавиши: пять процессных (`/lumea:case`, `/lumea:collect`, `/lumea:resolve`, `/lumea:sweep`, `/lumea:issue`) описаны в `reference/workflows.md`; остальные — по описанию скилла: `/lumea:setup` (ключ, роль, права), `/lumea:groups` (открытые тикеты по проблемам), `/lumea:investigate` (переписка и логи против кода репозитория), `/lumea:digest` (сводка периода), `/lumea:client` (карточка клиента), `/lumea:watch` (фоновые уведомления). То же самое можно сделать из свободного разговора по правилам ниже.

## Модель данных

- **Проект** (`list_projects`): `id`, `name` (`Sota`, `Faygo`), `type` (`sotavpn` / `faygovpn`). Фильтры тикетов берут `projectName` — как в справочнике; внешние сервисы (`get_client_external`, `run_external_action`) — `projectType`; `find_similar_tickets`, `list_quick_replies`, `staff_metrics` — `projectId`.
- **Тикет** — диалог с одним клиентом в одном проекте и канале (`telegram` / `web` / `email`). Статусы: `unanswered` (последним писал клиент, ждёт) → `in_progress` → `closed`. Приоритеты `low` / `normal` / `high` / `urgent`. Теги — свободные строки; `issue#<iid>` ставит система при привязке issue (руками и через `bulk_update_tickets` не ставится), `case:<slug>` — кейс. В ответах: `lastMessageAt` (по нему сортировка), `aiEnabled`, `project`, `client { id, name, username }`.
- **Сообщения** — `author.kind`: `client`, `staff`, `ai`, `template` (бот-шаблон). `isInternal: true` — внутренняя заметка, клиент её не видит. Вложение — `media { messageId, fileName, size }`; содержимое — `get_message_media { messageId }`.
- **Клиент** — один на все проекты (`telegramId`, `email`, `externalId`, `isBlocked`, заметки сотрудников). Подписка, срок, оплата — только во внешнем сервисе: `get_client_external { clientId, projectType }`.
- **Issue** — связь тикета с issue GitLab репозитория проекта: `list_ticket_issues { ticketId }` (`id` связи нужен для `unlink_issue`), `list_issue_tickets { projectName, iid }` — все тикеты одного issue.
- **Кейс** — набор тикетов с одной проблемой: тег `case:<slug>` на каждом плюс внутренняя заметка при открытии; файлы клиентов — в `.lumea/cases/<slug>/`. Подробно — `reference/workflows.md`.

## Как называют тикет

`#1d2155` — `#` и первые 6 символов uuid (так в шапке тикета и в `ticketRef` ответов); полный uuid; ссылка `…/dashboard/tickets/<uuid>`. Инструменты принимают только полный uuid:

- из ссылки и полного uuid брать id прямо из строки, искать не нужно;
- короткий id разрешать через `search { query: '#1d2155' }` → `tickets[0].id`; нашлось больше одного — показать варианты и спросить; ничего — спросить полный id или ссылку, не перебирать.

## Какой инструмент для чего

| Задача                                    | Инструмент                                                                                                      | Не делать                                                                     |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| разобраться в одном тикете                | `get_ticket_context` — тикет, последние 200 сообщений с заметками, клиент, внешние аккаунты, диагностика, issue | три вызова `get_ticket` + `get_ticket_messages` + `get_client`                |
| много тикетов (обзор, группировка, sweep) | `export_tickets { limit: 200 }`, дальше по `nextCursor` — строки с `title`, `summary`, `tags`, `lastMessage`    | `list_tickets` страница за страницей; `limit: 1000` за раз — ответ не пройдёт |
| очередь на экран                          | `list_tickets` (`status`, `projectName`, `tags`, `priority`, `sort`; закрытые только с `includeClosed`)         |                                                                               |
| переписка по одному тикету                | `get_ticket_messages { ticketId, limit }` — окно до 200, старше — `before`                                      |                                                                               |
| похожие уже решённые проблемы             | `find_similar_tickets { ticketId }` или `{ text, projectId }` — только закрытые, по смыслу                      | поиск по словам через `search`                                                |
| клиент по имени / @username / email / id  | `search`, из ответа `clients`; затем `get_client`, `get_client_tickets`                                         |                                                                               |
| подписка, оплата, статус аккаунта         | `get_client_external { clientId, projectType }` (`includePayments: true` — только если спросили про оплату)     | отвечать по памяти или по тексту переписки                                    |
| сводка за период                          | `ticket_digest { period, projectName? }` — одним вызовом                                                        | собирать из `ticket_stats` + `list_tickets` + `staff_metrics`                 |
| что нового с момента X                    | `ticket_updates { since, tags?, projectName? }` — новые тикеты и сообщения клиентов с вложениями                | перечитывать переписку каждого тикета                                         |
| написать нескольким клиентам              | `bulk_send_messages { items: [{ ticketId, content }] }`                                                         | цикл `send_message`                                                           |
| статус / приоритет / теги у многих        | `bulk_update_tickets { ticketIds, <одно поле> }`                                                                | цикл `update_ticket`                                                          |
| тикеты по issue                           | `list_issue_tickets { projectName, iid }` — с `lastClientText`, по нему виден язык клиента                      |                                                                               |
| issue из тикета                           | `find_related_issues` (черновик и кандидаты) → `create_issue_from_ticket` или `link_issue`                      | `create_issue_from_ticket` без показа кандидатов                              |
| заметка для коллег                        | `add_internal_note`                                                                                             | `send_message` с текстом, начинающимся с `#`                                  |
| кто я, какие права                        | `whoami` — один раз за разговор                                                                                 |                                                                               |

Полный список с полями и лимитами — `reference/tools.md`.

## Лимиты

- Ответ инструмента в Claude Code ограничен примерно 25 тысячами токенов: `export_tickets` по 200 строк и не больше 5 страниц (1000 тикетов) за задачу; `get_ticket_context` — не по всем тикетам кейса, а по 3–5 самым содержательным, остальным `get_ticket_messages { limit: 30 }`.
- `ticket_updates`: `since` не старше 7 дней и не в будущем, `limit` ≤ 100; лента отстаёт от текущего момента на 2 с. Продолжать с `nextSince`, пока `truncated: true`.
- `bulk_send_messages` и `bulk_update_tickets`: до 200 за вызов; бюджет вызова ~50 с — при `nextIndex` (не `null`) повторить с `items.slice(nextIndex)` / `ticketIds.slice(nextIndex)`. `bulk_update_tickets` — ровно одно поле кроме `ticketIds`: `status`, `priority`, `addTags` или `removeTags`.
- `list_tickets` и `get_client_tickets`: `perPage` ≤ 100; `search`: `limit` ≤ 20; `get_message_media`: картинки до 5 МБ приходят изображением, текст до 200 КБ — текстом, остальное — метаданные со ссылкой в CRM.
- `ticket_digest`: произвольный период не длиннее 31 дня; `team` — `[]` без права `statistics.read`, это не ошибка.

## Правила

1. **Ничего не отправлять и не менять без явного «да».** Перед `send_message`, `send_quick_reply`, `bulk_send_messages`, `bulk_update_tickets`, `update_ticket`, `block_client`, `run_external_action`, `create_issue_from_ticket`, `link_issue`, `toggle_ai` и любым другим пишущим инструментом показать, что именно произойдёт: адресаты (число, проект, кейс) и текст целиком. Хук плагина (`hooks/hooks.json`) спросит подтверждение ещё раз на отправку, блокировку, внешнее действие, создание и привязку issue и смену статуса пачкой — это не повод пропускать показ, а страховка на случай auto-режима; `update_ticket` и `bulk_update_tickets` без `status` (приоритет, теги) хук не трогает, подтверждение там — только словами. Три разных действия — три отдельных вопроса; «да» на рассылку не значит «да» на закрытие.
2. **Клиенту — на его языке.** Язык брать из его сообщений (`lastClientText`, переписка); отчёты и интерфейс — по-русски. В тексте клиенту не оставлять плейсхолдеров `{{…}}` и не обещать сроков, которых не давали.
3. **Цитировать, а не пересказывать.** Выводы о проблеме подкреплять цитатой из сообщения клиента с `ticketRef`; факты о подписке и оплате — только из `get_client_external`.
4. **Массовые вызовы — по результату, не по счётчику.** Читать `results` / `failed` и перечислять недоставленные поштучно с причиной; `skipped` у `bulk_update_tickets` — тикеты, уже бывшие в целевом статусе, это не ошибка.
5. **Ошибки.** `Недостаточно прав: нужен ключ …` — назвать право и предложить попросить его у администратора на странице ролей, не обходить другим инструментом. Инструменты `lumea` недоступны или сервер отвечает ошибкой авторизации (401) — предложить `/lumea:setup`. `Слишком много запросов. Повторите через N с` — подождать N секунд, не повторять сразу. `Тикет не найден` — id не тот: короткий id сначала разрешить через `search`, не подбирать.
6. **Только чтение по умолчанию.** Вопросы «что там», «кто», «сколько» — без единого пишущего вызова; `whoami` вызывать один раз, не перед каждым инструментом.

## Дальше

- `reference/workflows.md` — сквозные правила процессов: кейс (`case:<slug>`), сбор логов, resolve, sweep, issue из кейса.
- `reference/tools.md` — все инструменты с полями и лимитами (сгенерирован из реестра сервера).
