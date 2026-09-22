# Lumea — плагин для Claude Code

Публичный маркетплейс плагина `lumea` (Lumea — CRM поддержки; адрес сервера и ключ выдаёт администратор). Версия плагина совпадает с версией сервера; репозиторий обновляется автоматически с каждым релизом.

```
/plugin marketplace add mollybyte/lumea-plugin
/plugin install lumea@lumea
```

Адрес сервера Lumea сообщает администратор и задаётся переменной `LUMEA_URL`; ключ доступа выпускается в Lumea (Настройки → «Ключи доступа») и задаётся переменной `LUMEA_ACCESS_KEY` — обе обязательны. Подробности, список скиллов и проверка — [plugins/lumea/README.md](plugins/lumea/README.md).

Обновление: `/plugin marketplace update lumea`, затем `/plugin update lumea`.

Текущая версия: **0.39.1**.
