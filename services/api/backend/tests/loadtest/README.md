# Локальное нагрузочное тестирование AI SSE

Сценарий проверяет `/api/v1/agent/chat.stream` без обращения к реальному LLM.
Локальный mock-сервер имитирует поток фрагментов ответа и позволяет наблюдать
JWT verification, построение snapshot и работу database pool, SSE, mock LLM и
event loop.

Тест не входит в обычный CI и не является опубликованным бенчмарком:
результат зависит от машины, конфигурации backend и набора тестовых
пользователей.

## Требования

- запущенный PostgreSQL;
- установленный backend;
- `aiohttp` для load generator;
- отдельное dev/test окружение;
- валидная тестовая Supabase session.

Не используйте production credentials и не копируйте JWT из логов реального
приложения.

## 1. Макет LLM

Из `services/api`:

```bash
python -m backend.tests.loadtest.mock_llm_server
```

По умолчанию сервер слушает `localhost:9999`.

| Переменная | Default | Назначение |
|---|---:|---|
| `MOCK_RESPONSE_TOKENS` | `10` | Количество token chunks |
| `MOCK_CHUNK_DELAY_MS` | `200` | Задержка между chunks |
| `MOCK_TOOL_CALL_RATE` | `0.2` | Доля ответов с tool call |
| `MOCK_PORT` | `9999` | Порт mock server |

## 2. Запуск backend

В локальном test env направьте agent base URL на mock server:

```text
ENV=dev
BASE_URL=http://localhost:9999/v1
LOADTEST_MODE=true
```

При сочетании `LOADTEST_MODE=true` и `ENV=dev` endpoint отключает user rate
limit и Redis agent semaphore. Ограничение одного параллельного job на
пользователя в этом режиме не действует. В других окружениях
`LOADTEST_MODE` не обходит защитные механизмы.

```bash
uvicorn backend.apps.api.main:app --host 0.0.0.0 --port 8001
```

## 3. Тестовый пользователь

Передайте JWT специально созданного тестового пользователя через локальную
переменную `LOADTEST_TOKEN`. Не сохраняйте значение в shell history,
скриншотах или Git.

В load-test режиме один тестовый пользователь может создавать параллельные
запросы, поскольку semaphore отключён. Несколько test identities нужны только
для сценария, который отдельно моделирует поведение разных пользователей.

## 4. Запуск

```bash
python -m backend.tests.loadtest.load_test --tiers 5,20,50
```

Дополнительные параметры:

- `--base-url http://localhost:8001`;
- `--requests-per-tier 100`;
- `--token` — поддерживается утилитой, но переменная окружения безопаснее для
  локальной работы.

Начинайте с небольшого tier и увеличивайте конкурентность только в
изолированном окружении.

## Метрики

- **TTFT** — время до первого `token` SSE event;
- **total duration** — длительность полного stream;
- **success rate** — доля ответов, завершившихся без ошибки;
- **error breakdown** — HTTP, timeout и connection errors.

Load test затрагивает JWT verification, сбор `FocusSnapshot` через БД,
database pool, mock LLM, asyncio event loop и долгоживущие SSE connections.
Endpoint не выполняет subscription accounting, а rate limit и Redis semaphore
в описанном dev-режиме отключены. Интерпретировать результаты нужно вместе с
Prometheus metrics и структурированными логами.

Общая схема AI flow:
[docs/architecture.md](../../../../../docs/architecture.md).
