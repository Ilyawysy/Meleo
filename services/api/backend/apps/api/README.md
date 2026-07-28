# HTTP API

`backend/apps/api` — транспортный слой FastAPI. Он принимает REST/SSE-запросы,
проверяет контракты и авторизацию, собирает доменные сервисы и нормализует
ошибки. Бизнес-правила должны оставаться в `backend/domain`, а доступ к
хранилищам — в `backend/infrastructure`.

## Точки входа

- `main.py` экспортирует ASGI application:
  `app = create_app()`.
- `factory.py` создаёт FastAPI, подключает CORS, middleware, error handlers,
  роутеры, `/health` и `/metrics`.
- `middleware.py` управляет `request_id` и базовым rate limiting.
- `routers/admin.py` определяет dependency `admin_required` для проверки
  административной роли на admin endpoints.
- `errors.py` приводит application, validation, HTTP и unexpected exceptions к
  согласованному JSON-ответу.

Локальный запуск из `services/api`:

```bash
uvicorn backend.apps.api.main:app --host 0.0.0.0 --port 8001 --reload
```

OpenAPI UI доступен в dev-окружении по `/docs`.

## Роутеры

| Файл | Prefix | Назначение |
|---|---|---|
| `auth.py` | `/api/v1/auth` | Регистрация, сессия и logout |
| `users.py` | `/api/v1/users` | Профиль и onboarding |
| `focus_rooms.py` | `/api/v1` | Комнаты, задачи и checklist items |
| `focus.py` | `/api/v1` | Фокус-сессии, task segments, undo и магазин |
| `gamification.py` | `/api/v1/gamification` | XP, монеты, серии и награды |
| `plan.py` | `/api/v1/plan` | План фокуса и адаптивный план |
| `sync.py` | `/api/v1` | Агрегированный cursor-based sync |
| `chat.py` | `/api/v1/chat` | Треды и история сообщений |
| `agent.py` | `/api/v1/agent` | SSE focus statistics agent |
| `help.py` | `/api/v1/help` | JITAI question/card flow |
| `notifications.py` | `/api/v1/notifications` | Уведомления |
| `announcements.py` | `/api/v1/announcements` | Анонсы разработчика |
| `profile_stats.py` | `/api/v1/profile` | Статистика профиля |
| `mascot_skins.py` | `/api/v1/mascot-skins` | Скины маскота |
| `admin.py` | `/api/v1/admin` | Admin analytics и PostHog proxy |

## Жизненный цикл запроса

```text
request
  → CORS / request_id / rate limit
  → Pydantic validation
  → Supabase JWT
  → admin_required для административных endpoints
  → domain service
  → repository + transaction
  → response / unified error handler
```

AI-чат отличается длинным SSE lifecycle. Его конкурентность ограничивается
rate limiter и Redis semaphore; ошибки после открытия stream передаются как
типизированное SSE-событие.

## Правила слоя

- Не размещать SQL в роутерах.
- Не доверять `user_id` из тела запроса: пользователь определяется из JWT.
- Не логировать токены, пароли и значения внешних API keys.
- Сохранять совместимость response contracts или явно версионировать API.
- Для изменённого endpoint добавлять целевой тест и проверять ошибочный flow.

Общая схема: [docs/architecture.md](../../../../../docs/architecture.md).
