# Процесс разработки и качество

## Цель showcase

Репозиторий объединяет исходный код мобильной и backend-платформы в структуру,
удобную для технической оценки. Рабочая история разработки остаётся в закрытых
исходных репозиториях; демонстрационный снимок не содержит учётных данных и
внутренних временных файлов.

## Организация работы

Изменение проходит последовательность:

1. формулировка цели и acceptance criteria;
2. проверка полного data flow;
3. минимальная реализация;
4. автоматические проверки;
5. проверка изменений с отдельным вниманием к границам безопасности;
6. атомарный commit.

Для cross-stack функции data flow прослеживается от API и доменного сервиса до
sync/data layer, Riverpod state и UI. Это снижает риск исправить только один
симптом в распределённом сценарии.

## Стратегия репозитория

```text
apps/mobile      мобильное приложение
apps/admin       административная панель
services/api     backend-приложение и история схемы БД
infra            развёртывание и наблюдаемость
docs             техническая презентация решений
```

Такая структура сохраняет автономность компонентов, но позволяет проверять
архитектуру и CI из одной точки.

## Проверки качества

### Мобильный клиент

```bash
cd apps/mobile
flutter analyze
flutter test
```

Тесты охватывают session scope, logout boundary, operation queue, sync races,
focus providers, локальную БД, statistics и onboarding.

### Backend

```bash
cd services/api
ruff check backend/ --select E9,F63,F7,F82
pytest backend/ -v
alembic heads
```

Наиболее важны тесты доменных расчётов, focus rooms, plan/profile API, cursor
sync, idempotency и agent hardening. Для изменения схемы создаётся новая
Alembic revision; существующая история не переписывается.

CI использует критический набор правил Ruff, выявляющий синтаксические ошибки,
неопределённые имена и некорректные конструкции. Расширенный стилевой аудит
остаётся отдельной задачей и не заявляется как пройденный quality gate.

### Административная панель

```bash
cd apps/admin
npm run build
```

Команда включает TypeScript compilation и production build Vite.

## CI

`.github/workflows/ci.yml` выполняется для pull request и push в `main`.
`dorny/paths-filter` определяет затронутые компоненты:

- `apps/mobile/**` → Flutter analyze и tests;
- `services/api/**` или `infra/**` → Python setup, Ruff и pytest;
- `apps/admin/**` или `infra/**` → Node setup и admin build.

Mobile и admin jobs используют `pubspec.lock` и `package-lock.json`.
Backend-зависимости устанавливаются по диапазонам версий из `pyproject.toml`;
отдельного Python lockfile в showcase нет. Jobs используют минимальные
test-only значения окружения, production secrets в workflow не требуются.

## Работа с миграциями

- `services/api/alembic.ini` задаёт `backend/alembic` как каталог миграций.
- Перед применением проверяется единственный head.
- Новое изменение схемы добавляется новой revision.
- Destructive migration требует плана восстановления и отдельного решения по
  данным.
- Запуск `upgrade head` не является частью production startup command.

## Работа с секретами

Showcase сформирован из приватных исходников после проверки текущего дерева и
Git history. Файлы с реальными значениями окружения не импортированы. В
репозитории остаются только:

- `apps/mobile/env.mobile.example`;
- `apps/admin/.env.example`;
- `services/api/backend/.env.example`;
- `infra/docker/.env.example`;
- `infra/docker/.env.prod.example`.

Example-файлы документируют контракт конфигурации, но не дают доступ к
реальным сервисам. При случайной утечке секрет отзывается у провайдера, после
чего очищается вся затронутая история.

## Приоритеты проверки

Повышенного внимания требуют:

- JWT и Supabase Auth;
- admin authorization;
- cross-user isolation при logout;
- sync cursor, version и idempotency;
- coin/XP transactions;
- AI tool permissions и rate limits;
- Docker exposure и reverse proxy.

Для этих областей недостаточно только линтера: нужны целевые тесты и проверка
сценария отказа.

## Критерии готовности

Изменение считается завершённым, если:

- acceptance criteria выполнены;
- diff не затрагивает несвязанные модули;
- документация соответствует коду;
- применимые локальные проверки проходят;
- новые секреты и generated artifacts не попали в Git;
- ограничения и ручная проверка перечислены явно.
