# Документация Meleo

Этот раздел объясняет устройство showcase-репозитория и помогает быстро
перейти от обзорной презентации к проверяемым техническим деталям.

## Основные материалы

| Документ | Содержание |
|---|---|
| [Главная презентация](../README.md) | Назначение продукта, ключевые решения, стек и ограничения |
| [Архитектура](architecture.md) | Компоненты, границы ответственности и основные data flows |
| [Инженерный разбор](presentation.md) | Проблема, продуктовая гипотеза, реализация и результаты |
| [Процесс разработки](development-process.md) | Организация репозитория, CI, тестирование и работа с секретами |
| [Мобильное приложение](../apps/mobile/README.md) | Flutter-архитектура, запуск и основные модули |

## Служебные документы

- [CONTRIBUTING.md](../CONTRIBUTING.md) — правила изменений и quality gates.
- [SECURITY.md](../SECURITY.md) — границы публичного showcase и отправка
  security reports.
- [Load testing](../services/api/backend/tests/loadtest/README.md) — сценарий
  локальной проверки SSE без обращений к реальному LLM.

## Карта исходного кода

- `apps/mobile/` — Flutter, Riverpod, SQLite, native Android bridge.
- `apps/admin/` — React, TypeScript, Vite, Tailwind.
- `services/api/` — FastAPI, SQLAlchemy, Alembic и backend-тесты.
- `infra/` — Docker Compose, Caddy и observability.

Документация описывает состояние кода в showcase. Закрытые значения окружения,
production credentials и приватная deployment-конфигурация не публикуются.
