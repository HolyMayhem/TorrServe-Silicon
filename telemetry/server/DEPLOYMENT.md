# Production-развёртывание TorrServe Silicon Telemetry

Выполнено 30 октября 2026 (Asia/Yekaterinburg), после подтверждения владельца продолжить работу. Сервер развёрнут; публичный релиз macOS-приложения не выполнялся.

## Текущее состояние

- Worker: **torrserve-telemetry**, без создания второго Worker.
- Аккаунт: `11fb0018827f06abfb9d651295753029`.
- D1: **torrserve-analytics**, ID `8d44e16c-fa2a-46ed-9032-4c7690a4c30b`, существующий binding `DB`.
- URL: `https://torrserve-telemetry.strayuglydog.workers.dev`.
- Панель: `https://torrserve-telemetry.strayuglydog.workers.dev/admin/`.
- Активная версия Worker: `cd5e53e2-e84a-46a4-b361-e0af83d61c76`.
- Применены `0001_telemetry.sql`, `0002_country.sql`, `0003_admin_password.sql`.
- Cron очистки: `17 3 * * *` (03:17 UTC, 08:17 Asia/Yekaterinburg).
- `ADMIN_AUTH_MODE=key`. Zero Trust / Access не активировался: владелец отказался от карты и платёжных условий.
- Вход: случайный 256-битный ключ в macOS Keychain. На Worker — только `ADMIN_KEY_SHA256` и отдельный `ADMIN_SESSION_SECRET` через Wrangler Secrets.
- Observability, invocation logs и Logpush выключены, tail consumers отсутствуют.
- Workers.dev включён; preview URL выключены. Custom domains не добавлялись.
- Последняя проверка: installations / DAU / WAU / MAU = 0; записей активности = 0. Тестовые установки в production не отправлялись.

## Что проверено после развёртывания

`node scripts/verify-production.mjs` через настоящий HTTPS:

- `/health`: 200.
- `/admin/` без сессии: 303 на форму входа.
- Приватные HTML/CSS/JS/API без сессии: 401.
- Публичные файлы формы входа: 200; данных статистики в них нет.
- Вход настоящим ключом из Keychain: 204, cookie Secure / HttpOnly / SameSite=Strict на 8 часов.
- Приватные файлы и статистика с cookie: 200, `Cache-Control: no-store`.
- Статистика прочитана через Worker из production D1, поле `countries` присутствует.
- Выход: 204 и истечение cookie; без cookie API снова закрыт.

Через Wrangler/API дополнительно проверены DB binding, обе миграции, cron, наличие двух secrets (без чтения их значений), выключенное журналирование и отсутствие дубликата Worker.

## Резервная копия и предыдущее состояние

До изменений текущий Worker был стандартным Hello World с единственным binding DB, без cron и пользовательских таблиц. Ранее активная версия: `069df4b0-a1d6-4d8f-a962-1a7eada5545a`. Observability была включена.

До миграции получен SQL export пустой пользовательской схемы:

- игнорируемый `remote-inspection/pre-telemetry-20261030.sql`;
- размер 32 байта;
- SHA-256 `309d1516f5d4f4f792b17106f7b761312f848c634e3028d70e6eb8ed39df7398`.

Исходник старого Worker и настройки: игнорируемый `remote-inspection/before-production/`. Текущие снимки — `remote-inspection/`. Они не входят в Git. До публикации проверены namespaces rate limiter; конфликтующих bindings в аккаунте не было.

## Вход владельца

Ключ в Keychain: service `com.holymayhem.torrserve.telemetry.admin`, account `owner`.
Выполнить самостоятельно для копирования ключа в буфер:

```bash
security find-generic-password -s com.holymayhem.torrserve.telemetry.admin -a owner -w | pbcopy
```

Вставить в форму входа. Не передавать ключ через чат или URL. Полная схема авторизации, сроки сессии и её отзыва — в [README.md](README.md).

## Дальнейшее обслуживание

Из `telemetry/server/`, только для согласованных production-обновлений:

```bash
npm ci
npm run check
npm test
npm run inspect:remote
npx wrangler deploy --dry-run -c wrangler.production.json --outdir .test-output/production
npx wrangler d1 migrations apply DB --remote -c wrangler.production.json
npx wrangler deploy -c wrangler.production.json
node scripts/verify-production.mjs
```

Локальный `wrangler.production.json` игнорируется Git; исходный шаблон `wrangler.production.example.json` не содержит секретов. Никогда не разворачивать local config и не создавать заново Worker/D1.

При новом публичном выпуске явно обновить `LATEST_APP_VERSION` в production config. Проверять D1 Metrics (rows read/written, storage), Worker requests и backlog очистки. На Free бюджет ограничен; установлен дополнительный серверный предел 5000 принятых дневных heartbeat. Первые нулевые данные ещё не доказывают стоимость настоящей нагрузки.

Read-only проверка D1:

```bash
npx wrangler d1 execute DB --remote -c wrangler.production.json --command "SELECT * FROM telemetry_totals"
npx wrangler d1 execute DB --remote -c wrangler.production.json --command "SELECT * FROM telemetry_daily ORDER BY day DESC LIMIT 7"
npx wrangler d1 execute DB --remote -c wrangler.production.json --command "SELECT MIN(day) oldest_day, COUNT(*) rows FROM telemetry_activity"
```

Для немедленного отзыва всех сессий выполнить согласованно `node scripts/bootstrap-admin.mjs --upload`. Он повторно использует существующий ключ Keychain и меняет signing secret. Не запускать без необходимости: все открытые сессии завершатся.

## Откат

Любой откат production — отдельное согласованное действие.

- Вернуть Worker на записанную исправную версию. Для полного отключения телеметрии возможен возврат к исходному Hello World: `npx wrangler rollback 069df4b0-a1d6-4d8f-a962-1a7eada5545a --name torrserve-telemetry`.
- Базу автоматически не откатывать и не выполнять DROP. Добавленные таблицы не мешают старому Worker; уже принятые данные нужно сохранить.
- Cron и настройки проверить отдельно: rollback версии не считать гарантией возврата всех внешних параметров.
- Восстановление export/Time Travel затронет всю D1 и требует отдельного решения.

До публичного релиза приложения остаётся проверка нового пункта настроек в живом UI и по возможности smoke на физическом Intel Mac. Проверка входа браузером владельца также нужна: CLI подтвердил протокол авторизации, но не ввод ключа пользователем и визуальный вид новой формы.


## Обновление: смена пароля в панели

Опубликовано после отдельного подтверждения владельца 30 октября 2026. Версия до обновления — `36b733fe-27c1-4ff8-9de4-7d3417b6805f`. Выполнено:

1. Сохранён D1 export `remote-inspection/pre-password-20261030.sql` (2943 bytes, SHA256 `a7ec59526e3dbf7e6d6b9ea352f8f245252d51fe3aaebbd08c19d3b74d09b5c4`) и снимки `before-password/`.
2. Добавлена в существующую D1 одна пустая таблица `telemetry_admin_auth` миграцией `0003_admin_password.sql`. Аналитические таблицы и счётчики не изменяются.
3. Создан `ADMIN_PASSWORD_PEPPER` через Wrangler Secrets; начальный ключ и секрет подписи сессий сохранены.
4. Обновлён тот же Worker и assets: форма смены пароля, browser PBKDF2, проверка версии сессий, API смены.
5. Проверены текущий вход, защищённые файлы, публичные параметры PBKDF2 и browser module, наличие кнопки смены и отказ cross-origin API через настоящий HTTPS. Пользовательский пароль в production не задавался: таблица авторизации пуста, владелец выберет пароль в панели. Начальный ключ и прежние сессии работают до его первой смены.

Предыдущее внедрение использовало только случайный ключ. После первой пользовательской смены нельзя откатывать код на версию без поддержки новой таблицы, иначе начальный ключ снова даст вход. Таблицу авторизации автоматически не удалять, pepper не ротировать. Согласованное восстановление доступа описано в README.
