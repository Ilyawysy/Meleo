# Доменный слой

`backend/domain` содержит прикладные сущности, repository protocols и
бизнес-сервисы. Слой не отвечает за HTTP и не должен зависеть от конкретного
клиентского интерфейса.

## Домены

| Каталог | Назначение |
|---|---|
| `users` | Пользователь, onboarding, state versions и удаление аккаунта |
| `focus_rooms` | Комнаты, задачи, checklist items, archive и reorder |
| `focus` | Фокус-сессии, task segments, внутренняя валюта и магазин |
| `gamification` | XP, серии, recovery, награды и агрегаты |
| `chat` | История сообщений и тредов |
| `notifications` | Пользовательские уведомления |
| `announcements` | Анонсы разработчика |
| `mascot_skins` | Доступные и приобретённые скины |
| `subscriptions` | Free/Pro state и лимиты AI-сообщений |
| `sync` | Cursor и сбор агрегированного состояния |

## Паттерн

Домен обычно разделён на:

- `entities.py` — SQLAlchemy entities и enum;
- `repository.py` — Protocol, описывающий нужные операции хранения;
- `service.py` — бизнес-правила и транзакционный сценарий;
- `calculator.py` или `stats_service.py` — чистые вычисления, если они
  выделены отдельно.

Реализации repository contracts находятся в
`backend/infrastructure/repositories`.

## Основные инварианты

- Любой пользовательский запрос ограничен `user_id`.
- Задача принадлежит комнате, а checklist item — задаче.
- Изменение порядка сохраняет согласованный `sort_order`.
- Награды начисляются через завершение фокус-сессии, а списание монет и
  покупка выполняются в одной транзакции.
- Sync использует версии и курсор, а повторяемые команды защищаются
  idempotency.
- Смена статуса сессии следует разрешённому lifecycle; task segments не
  должны описывать две активные задачи одновременно.

## Изменение домена

1. Сначала сформулируйте инвариант и сценарии отказа.
2. Измените entity/service/repository contract минимально.
3. Добавьте новую Alembic revision, если меняется схема.
4. Обновите infrastructure implementation.
5. Добавьте unit или integration-shaped тест.
6. Проследите изменение до API, sync и mobile state.

Контекст компонентов: [docs/architecture.md](../../../../docs/architecture.md).
