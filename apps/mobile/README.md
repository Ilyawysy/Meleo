# Мобильное приложение Meleo

Flutter-клиент для iOS и Android. Приложение объединяет фокус-комнаты, задачи,
таймер, статистику, геймификацию, уведомления и AI-помощь. Основные данные
читаются из локальной SQLite-базы и синхронизируются с FastAPI.

## Архитектура

```text
lib/
├── core/                  # env, network, database, session, sync
└── features/
    ├── auth/              # Supabase Auth, OTP, secure tokens
    ├── focus/             # rooms, tasks, sessions, plan, gamification
    ├── chat/              # threads and SSE agent
    ├── notifications/
    ├── statistics/
    ├── profile/
    ├── search/
    ├── subscription/
    └── shell/
```

### Границы сессии Riverpod

- Внешний `ProviderScope` хранит `sessionScopeProvider`,
  `appScopeControllerProvider` и logout orchestration.
- Внутренний scope содержит доменные провайдеры и пересоздаётся при logout.
- Read providers отдают реактивное состояние из SQLite.
- Доменные команды записывают изменения локально. `DomainOperationQueue`
  сериализует операции чата и уведомлений; active-room provider использует
  отдельную очередь.

### Offline-first синхронизация

Локальные изменения сохраняются с pending/dirty state. Конкретный доменный
sync-сервис читает это состояние и самостоятельно выполняет push.
`SyncOrchestrator` управляет lifecycle сервисов и агрегированным pull для
rooms, tasks, focus sessions, chat и notifications. API использует
cursor/version, а `AdaptiveSyncController` регулирует повторные pull-циклы и
backoff.

## Основные сценарии

- авторизация и OTP через Supabase;
- создание, архивирование и переупорядочивание фокус-комнат;
- задачи и checklist items внутри комнаты;
- фокус-сессии с переключением активной задачи;
- план, дневной прогресс и статистика;
- XP, монеты, магазин и анимированный Rive-маскот;
- SSE-чат со статистическим AI-агентом;
- JITAI-flow «Не могу начать»;
- локальные уведомления и поиск;
- Android-native прототип блокировки выбранных приложений.

App blocking использует `MethodChannel` и Android service. Эквивалентный
iOS-механизм в текущем прототипе отсутствует.

## Конфигурация

Создайте локальный `.env.mobile` на основе
[`env.mobile.example`](env.mobile.example). Реальные значения не коммитятся.

Основные параметры:

- `API_BASE_URL`;
- `SUPABASE_URL`;
- `SUPABASE_ANON_KEY`;
- `SENTRY_DSN_DEV`, `SENTRY_DSN_PROD` и `ENVIRONMENT`;
- `POSTHOG_API_KEY` и `POSTHOG_HOST`.

`SUPABASE_REDIRECT_URL` также поддерживается через `dart-define`, но имеет
app-specific default в `lib/core/env.dart`. URL агента строится из
`API_BASE_URL`.

## Запуск

Требуются Flutter SDK с совместимым Dart `^3.9.2` и настроенный
эмулятор/устройство.

```bash
flutter pub get
flutter run --dart-define-from-file=.env.mobile
```

Без настроенных API, Supabase и внешних интеграций доступны только те экраны и
локальные сценарии, которые не требуют сетевого состояния.

## Проверки

```bash
flutter analyze
flutter test
```

Тесты охватывают session lifecycle, operation queue, sync races, focus
providers, локальную БД, statistics, onboarding и auth gate.

## Ключевые точки входа

- `lib/main.dart` — инициализация и auth gate;
- `lib/core/providers/logout_controller.dart` — завершение сессии;
- `lib/core/sync/sync_orchestrator.dart` — lifecycle синхронизации;
- `lib/features/focus/ui/start_tab.dart` — главный START screen;
- `lib/features/chat/agent_service.dart` — SSE client;
- `lib/features/focus/data/app_blocker_channel.dart` — Android bridge.

Общая схема системы находится в
[`../../docs/architecture.md`](../../docs/architecture.md).
