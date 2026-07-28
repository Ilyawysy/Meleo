# Инфраструктурный слой

`backend/infrastructure` реализует технические адаптеры для доменного и
HTTP-слоёв: PostgreSQL, Redis, Supabase Auth, idempotency, ETag, logging и
metrics.

## Состав

| Путь | Ответственность |
|---|---|
| `config.py` | `pydantic-settings`, env contract и runtime options |
| `database/` | SQLAlchemy base, async engine/session и SSL для asyncpg |
| `repositories/` | SQLAlchemy implementations доменных repository protocols |
| `security/` | Supabase JWT, Admin API wrapper и masking логов |
| `redis_client.py` | Клиенты coordination/cache Redis |
| `rate_limit.py` | User-level token bucket для AI |
| `agent_semaphore.py` | Ограничение параллельных agent jobs |
| `idempotency.py` | Защита повторяемых write-запросов |
| `etag.py` | Версионирование и conditional responses |
| `logging.py` | structlog JSON configuration |
| `metrics.py` | Prometheus middleware и application metrics |

## PostgreSQL

`database/session.py` создаёт async SQLAlchemy engine для `asyncpg`. Для
Supabase PostgreSQL настраивается SSL certificate; отключение SSL допустимо
только в изолированном test/dev окружении.

`get_session()` задаёт границу транзакции для запроса. Репозитории фильтруют
пользовательские данные по `user_id`; прямой client access к доменным таблицам
не является частью архитектуры приложения.

## Redis

Используются два разных профиля:

- `redis-coordination` с `noeviction` — rate limits и semaphore;
- `redis-cache` с `allkeys-lru` — ETag и восстанавливаемое cache state.

Это разделяет критичные координационные ключи и данные, которые допустимо
вытеснить.

## Граница безопасности

`security/auth.py` связывает claim `sub` Supabase JWT с каноническим
`supabase_user_id`. Код security-зоны изменяется только после отдельного
review. Токены, service-role keys и пароли запрещено включать в логи.

## Наблюдаемость

Каждый HTTP-запрос получает `request_id`. structlog формирует JSON-события,
Promtail отправляет их в Loki, а Prometheus middleware экспортирует latency и
status metrics на `/metrics`.

## Конфигурация

Контракт переменных приведён в
[`../.env.example`](../.env.example). Файл содержит только шаблон; реальный
`.env` хранится локально и не коммитится.

Общая схема: [docs/architecture.md](../../../../docs/architecture.md).
