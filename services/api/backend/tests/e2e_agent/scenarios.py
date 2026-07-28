from __future__ import annotations

import re
from typing import Any

from .assertions import (
    assert_http_error,
    assert_no_errors,
    assert_response_text_contains,
    assert_status,
    assert_tool_called,
    assert_tool_count,
    assert_touched_entity,
)

# Shared mutable context populated by extract callbacks during run
context: dict[str, Any] = {}


def _extract_task_id(result: dict[str, Any]) -> None:
    touched: list[dict[str, Any]] = result.get("touched_entities") or []
    for entity in touched:
        if entity.get("entity_type") == "task":
            entity_id = entity.get("entity_id")
            if entity_id:
                context["task_id"] = entity_id
                return
    events: list[dict[str, Any]] = result.get("events") or []
    for event in events:
        if event.get("type") == "function" and event.get("name") == "create_task":
            raw = event.get("result", "")
            match = re.search(r'"id"\s*:\s*"([^"]+)"', str(raw))
            if match:
                context["task_id"] = match.group(1)
                return


def _history_with_task_id(content_template: str) -> list[dict[str, str]]:
    task_id = context.get("task_id", "UNKNOWN_TASK_ID")
    return [{"role": "user", "content": content_template.format(task_id=task_id)}]


SCENARIOS: list[dict[str, Any]] = [
    # 1 — create_task
    {
        "name": "create_task",
        "description": "Агент создаёт новую задачу",
        "history": [
            {
                "role": "user",
                "content": "Создай задачу 'Написать отчёт за квартал' с высоким приоритетом",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "create_task"),
            lambda r: assert_no_errors(r),
            lambda r: assert_touched_entity(r, "task"),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": _extract_task_id,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 2 — get_task
    {
        "name": "get_task",
        "description": "Агент получает задачу по ID",
        "history": None,
        "history_factory": lambda: _history_with_task_id("Покажи детали задачи с id {task_id}"),
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_task"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": "create_task",
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 3 — update_task
    {
        "name": "update_task",
        "description": "Агент обновляет задачу",
        "history": None,
        "history_factory": lambda: _history_with_task_id(
            "Обнови задачу {task_id}: измени приоритет на низкий"
        ),
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "update_task"),
            lambda r: assert_no_errors(r),
            lambda r: assert_touched_entity(r, "task"),
        ],
        "depends_on": "create_task",
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 4 — list_tasks
    {
        "name": "list_tasks",
        "description": "Агент выводит список задач",
        "history": [
            {
                "role": "user",
                "content": "Покажи все мои задачи",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "list_tasks"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 5 — search_tasks
    {
        "name": "search_tasks",
        "description": "Агент ищет задачи по ключевому слову",
        "history": [
            {
                "role": "user",
                "content": "Найди задачи со словом 'отчёт'",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "search_tasks"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 6 — add_checklist_item
    {
        "name": "add_checklist_item",
        "description": "Агент добавляет пункт чеклиста",
        "history": None,
        "history_factory": lambda: _history_with_task_id(
            "Добавь пункт чеклиста 'Собрать данные' в задачу {task_id}"
        ),
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "add_checklist_item"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": "create_task",
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 7 — toggle_checklist_item
    {
        "name": "toggle_checklist_item",
        "description": "Агент отмечает пункт чеклиста выполненным",
        "history": None,
        "history_factory": lambda: _history_with_task_id(
            "Отметь первый пункт чеклиста задачи {task_id} как выполненный"
        ),
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "toggle_checklist_item"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": "add_checklist_item",
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 8 — get_user_snapshot
    {
        "name": "get_user_snapshot",
        "description": "Агент получает снапшот пользователя",
        "history": [
            {
                "role": "user",
                "content": "Покажи мой текущий статус и активность",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_user_snapshot"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 9 — get_period_stats
    {
        "name": "get_period_stats",
        "description": "Агент получает статистику за период",
        "history": [
            {
                "role": "user",
                "content": "Покажи мою статистику за последнюю неделю",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_period_stats"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 10 — get_user_settings
    {
        "name": "get_user_settings",
        "description": "Агент получает настройки пользователя",
        "history": [
            {
                "role": "user",
                "content": "Какие у меня текущие настройки?",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_user_settings"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 11 — update_user_settings
    {
        "name": "update_user_settings",
        "description": "Агент обновляет настройки пользователя",
        "history": [
            {
                "role": "user",
                "content": "Включи звуковые уведомления в настройках",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "update_user_settings"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 12 — get_guide
    {
        "name": "get_guide",
        "description": "Агент возвращает гайд по функционалу",
        "history": [
            {
                "role": "user",
                "content": "Как пользоваться фокус-сессиями? Объясни подробно",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_guide"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 13 — delete_task
    {
        "name": "delete_task",
        "description": "Агент удаляет задачу",
        "history": None,
        "history_factory": lambda: _history_with_task_id("Удали задачу с id {task_id}"),
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "delete_task"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": "create_task",
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 14 — edge: empty_history
    {
        "name": "empty_history",
        "description": "Запрос с пустой историей — ожидаем ответ агента без падения",
        "history": [{"role": "user", "content": ""}],
        "mentions": None,
        "assertions": [
            lambda r: assert_status(r, "completed"),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 15 — edge: nonexistent_task
    {
        "name": "nonexistent_task",
        "description": "Запрос задачи с несуществующим ID",
        "history": [
            {
                "role": "user",
                "content": "Покажи задачу с id 00000000-0000-0000-0000-000000000000",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "get_task"),
            lambda r: assert_status(r, "completed"),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 16 — edge: multi_tool_chain
    {
        "name": "multi_tool_chain",
        "description": "Агент вызывает несколько инструментов за один запрос",
        "history": [
            {
                "role": "user",
                "content": (
                    "Создай задачу 'Тест мультиинструмент', затем сразу покажи список всех задач"
                ),
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_tool_called(r, "create_task"),
            lambda r: assert_tool_called(r, "list_tasks"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": "Удали только что созданную задачу 'Тест мультиинструмент'",
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 17 — edge: invalid_priority
    {
        "name": "invalid_priority",
        "description": "Запрос с некорректным значением приоритета",
        "history": [
            {
                "role": "user",
                "content": "Создай задачу 'Тест приоритет' с приоритетом 'superurgent'",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_status(r, "completed"),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 18 — edge: ambiguous_request
    {
        "name": "ambiguous_request",
        "description": "Агент обрабатывает неоднозначный запрос без падения",
        "history": [
            {
                "role": "user",
                "content": "Сделай что-нибудь с задачей",
            }
        ],
        "mentions": None,
        "assertions": [
            lambda r: assert_status(r, "completed"),
            lambda r: assert_response_text_contains(r, "задач"),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 19 — edge: expired_token
    {
        "name": "expired_token",
        "description": "Запрос с просроченным токеном — ожидаем 401",
        "history": [{"role": "user", "content": "Покажи задачи"}],
        "mentions": None,
        "assertions": [
            lambda r: assert_http_error(r, 401),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": True,
        "token_override": "invalid.expired.token",
        "expect_http_error": 401,
    },
    # ──────────────────────────────────────────────
    # Multi-step scenarios: один промпт → несколько действий
    # ──────────────────────────────────────────────
    # 21 — multi: create + update + show
    {
        "name": "multi_create_update_show",
        "description": "Создать задачу, изменить приоритет, показать результат — всё за один запрос",
        "history": [
            {
                "role": "user",
                "content": (
                    "Создай задачу 'Подготовить презентацию' с приоритетом low, "
                    "затем сразу измени её приоритет на high, "
                    "и покажи итоговый результат задачи"
                ),
            }
        ],
        "assertions": [
            lambda r: assert_tool_called(r, "create_task"),
            lambda r: assert_tool_called(r, "update_task"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": "Удали задачу 'Подготовить презентацию'",
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 22 — multi: create task + add checklist items
    {
        "name": "multi_create_with_checklist",
        "description": "Создать задачу и сразу добавить несколько пунктов чеклиста",
        "history": [
            {
                "role": "user",
                "content": (
                    "Создай задачу 'Организовать встречу' и добавь в неё чеклист: "
                    "'Забронировать переговорку', 'Отправить приглашения', 'Подготовить повестку'"
                ),
            }
        ],
        "assertions": [
            lambda r: assert_tool_called(r, "create_task"),
            lambda r: assert_tool_called(r, "add_checklist_item"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": "Удали задачу 'Организовать встречу'",
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 23 — multi: check stats + create task based on analysis
    {
        "name": "multi_stats_then_create",
        "description": "Посмотреть статистику, потом создать задачу на основе анализа",
        "history": [
            {
                "role": "user",
                "content": (
                    "Покажи мою статистику за неделю и на основе неё "
                    "создай задачу 'Увеличить продуктивность' с высоким приоритетом"
                ),
            }
        ],
        "assertions": [
            lambda r: assert_tool_called(r, "get_period_stats"),
            lambda r: assert_tool_called(r, "create_task"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": "Удали задачу 'Увеличить продуктивность'",
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 24 — multi: search + delete found task
    {
        "name": "multi_search_and_delete",
        "description": "Найти задачу по названию и удалить её",
        "history_factory": lambda: [
            {
                "role": "user",
                "content": "Найди задачу со словом 'отчёт' и удали первую найденную",
            }
        ],
        "assertions": [
            lambda r: assert_tool_called(r, "search_tasks"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 25 — multi: settings + snapshot in one go
    {
        "name": "multi_settings_and_snapshot",
        "description": "Показать настройки и статус пользователя за один запрос",
        "history": [
            {
                "role": "user",
                "content": "Покажи мои текущие настройки и мой статус (streak, уровень, монеты)",
            }
        ],
        "assertions": [
            lambda r: assert_tool_called(r, "get_user_settings"),
            lambda r: assert_tool_called(r, "get_user_snapshot"),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # 26 — multi: batch create 3 tasks
    {
        "name": "multi_batch_create",
        "description": "Создать 3 задачи одним запросом",
        "history": [
            {
                "role": "user",
                "content": (
                    "Создай три задачи одним запросом:\n"
                    "1. 'Купить продукты' — приоритет low\n"
                    "2. 'Позвонить врачу' — приоритет high\n"
                    "3. 'Оплатить счета' — приоритет medium"
                ),
            }
        ],
        "assertions": [
            lambda r: assert_tool_count(r, "create_task", 3),
            lambda r: assert_no_errors(r),
        ],
        "depends_on": None,
        "cleanup": "Удали задачи 'Купить продукты', 'Позвонить врачу' и 'Оплатить счета'",
        "extract": None,
        "skip_poll": False,
        "token_override": None,
        "expect_http_error": None,
    },
    # ──────────────────────────────────────────────
    # Edge cases (continued)
    # ──────────────────────────────────────────────
    # 27 — edge: rate_limit
    {
        "name": "rate_limit",
        "description": "Повторный запрос подряд — ожидаем 429 при превышении лимита",
        "history": [{"role": "user", "content": "Покажи задачи"}],
        "mentions": None,
        "assertions": [
            lambda r: assert_http_error(r, 429),
        ],
        "depends_on": None,
        "cleanup": None,
        "extract": None,
        "skip_poll": True,
        "token_override": None,
        "expect_http_error": 429,
        "_rate_limit_probe": True,
    },
]
