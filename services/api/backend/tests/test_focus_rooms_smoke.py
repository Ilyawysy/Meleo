"""Smoke tests for the focus_rooms router.

Tests verify routing, authentication, and basic request validation
without real DB connections.
"""

from __future__ import annotations

import os
import uuid
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

os.environ.setdefault("DB_SSL_DISABLE", "1")

from fastapi import FastAPI
from starlette.testclient import TestClient

from backend.apps.api.routers import focus_rooms as focus_rooms_router
from backend.domain.focus_rooms.entities import FocusRoom, FocusRoomType
from backend.domain.focus_rooms.task_entities import Task, TaskStatus
from backend.infrastructure.database.session import get_session
from backend.infrastructure.security.auth import get_current_user_id

_USER_ID = uuid.uuid4()


def _make_app(authed: bool = True) -> FastAPI:
    app = FastAPI()
    app.include_router(focus_rooms_router.router)

    async def _fake_session():
        session = AsyncMock()
        session.commit = AsyncMock()
        session.refresh = AsyncMock()
        session.flush = AsyncMock()
        yield session

    async def _fake_user_id():
        return _USER_ID

    app.dependency_overrides[get_session] = _fake_session
    if authed:
        app.dependency_overrides[get_current_user_id] = _fake_user_id
    return app


def _fake_room(room_id: uuid.UUID | None = None, archived: bool = False) -> Any:
    room = MagicMock(spec=FocusRoom)
    room.id = room_id or uuid.uuid4()
    room.user_id = _USER_ID
    room.title = "Test Room"
    room.color = "#FF0000"
    room.type = FocusRoomType.REGULAR
    room.archived = archived
    room.archived_at = None
    room.sort_order = 0
    room.sprint_goal = None
    room.sprint_deadline = None
    room.sprint_total_hours = None
    room.deleted = False
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    room.created_at = now
    room.updated_at = now
    return room


def _fake_task(task_id: uuid.UUID | None = None, room_id: uuid.UUID | None = None) -> Any:
    task = MagicMock(spec=Task)
    task.id = task_id or uuid.uuid4()
    task.room_id = room_id or uuid.uuid4()
    task.user_id = _USER_ID
    task.title = "Test Task"
    task.description = None
    task.status = TaskStatus.NOT_DONE
    task.sort_order = 0
    task.completed_at = None
    task.deleted = False
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    task.created_at = now
    task.updated_at = now
    return task


# --- Tests ---


def test_requires_auth_rooms_list() -> None:
    """GET /api/v1/rooms without auth returns 401."""
    app = _make_app(authed=False)
    client = TestClient(app, raise_server_exceptions=False)
    response = client.get("/api/v1/rooms")
    assert response.status_code == 401


def test_requires_auth_rooms_create() -> None:
    """POST /api/v1/rooms without auth returns 401."""
    app = _make_app(authed=False)
    client = TestClient(app, raise_server_exceptions=False)
    response = client.post("/api/v1/rooms", json={"title": "X", "color": "#FF"})
    assert response.status_code == 401


def test_list_rooms(monkeypatch: pytest.MonkeyPatch) -> None:
    """GET /api/v1/rooms returns 200 with room list."""
    room = _fake_room()

    execute_result = MagicMock()
    execute_result.all.return_value = [(room, 0, 0)]

    async def _fake_execute(stmt: Any) -> Any:
        return execute_result

    app = _make_app()

    async def _fake_session_with_execute():
        session = AsyncMock()
        session.commit = AsyncMock()
        session.refresh = AsyncMock()
        session.flush = AsyncMock()
        session.execute = _fake_execute
        yield session

    app.dependency_overrides[focus_rooms_router.get_session] = _fake_session_with_execute

    client = TestClient(app)
    response = client.get("/api/v1/rooms")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["title"] == "Test Room"


def test_create_room(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST /api/v1/rooms creates a room and returns 201."""
    room = _fake_room()

    async def _fake_create(self, r: Any) -> Any:
        return room

    async def _fake_task_count(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    async def _fake_focus_sec(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    monkeypatch.setattr(focus_rooms_router.SqlAlchemyFocusRoomRepository, "create", _fake_create)
    monkeypatch.setattr(focus_rooms_router, "_get_room_task_count", _fake_task_count)
    monkeypatch.setattr(focus_rooms_router, "_get_room_focus_seconds", _fake_focus_sec)

    app = _make_app()
    client = TestClient(app)
    response = client.post("/api/v1/rooms", json={"title": "My Room", "color": "#AABBCC"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test Room"


def test_archive_room(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST /api/v1/rooms/{room_id}/archive returns 200 with archived=true."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id, archived=True)

    async def _fake_archive_room(self, rid: uuid.UUID, user_id: uuid.UUID) -> Any:
        return room

    async def _fake_task_count(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    async def _fake_focus_sec(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    from backend.domain.focus_rooms.service import FocusRoomService

    monkeypatch.setattr(FocusRoomService, "archive_room", _fake_archive_room)
    monkeypatch.setattr(focus_rooms_router, "_get_room_task_count", _fake_task_count)
    monkeypatch.setattr(focus_rooms_router, "_get_room_focus_seconds", _fake_focus_sec)

    app = _make_app()
    client = TestClient(app)
    response = client.post(f"/api/v1/rooms/{room_id}/archive")
    assert response.status_code == 200
    assert response.json()["archived"] is True


def test_archive_room_not_found(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST /api/v1/rooms/{room_id}/archive returns 404 for missing room."""

    async def _fake_archive_room(self, rid: uuid.UUID, user_id: uuid.UUID) -> None:
        return None

    from backend.domain.focus_rooms.service import FocusRoomService

    monkeypatch.setattr(FocusRoomService, "archive_room", _fake_archive_room)

    app = _make_app()
    client = TestClient(app)
    response = client.post(f"/api/v1/rooms/{uuid.uuid4()}/archive")
    assert response.status_code == 404


def test_list_tasks(monkeypatch: pytest.MonkeyPatch) -> None:
    """GET /api/v1/rooms/{room_id}/tasks returns 200 with task list."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id)
    task = _fake_task(room_id=room_id)

    async def _fake_get_room(self, rid: uuid.UUID) -> Any:
        return room

    async def _fake_list_tasks(self, rid: uuid.UUID) -> list:
        return [task]

    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyFocusRoomRepository, "get_by_id", _fake_get_room
    )
    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyRoomTaskRepository, "list_for_room", _fake_list_tasks
    )

    app = _make_app()
    client = TestClient(app)
    response = client.get(f"/api/v1/rooms/{room_id}/tasks")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["title"] == "Test Task"


def test_create_task(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST /api/v1/rooms/{room_id}/tasks creates a task and returns 201."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id)
    task = _fake_task(room_id=room_id)

    async def _fake_get_room(self, rid: uuid.UUID) -> Any:
        return room

    async def _fake_create_task(self, t: Any) -> Any:
        return task

    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyFocusRoomRepository, "get_by_id", _fake_get_room
    )
    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyRoomTaskRepository, "create", _fake_create_task
    )

    app = _make_app()
    client = TestClient(app)
    response = client.post(f"/api/v1/rooms/{room_id}/tasks", json={"title": "My Task"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test Task"


def test_create_task_archived_room_returns_409(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST to archived room returns 409."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id, archived=True)

    async def _fake_get_room(self, rid: uuid.UUID) -> Any:
        return room

    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyFocusRoomRepository, "get_by_id", _fake_get_room
    )

    app = _make_app()
    client = TestClient(app)
    response = client.post(f"/api/v1/rooms/{room_id}/tasks", json={"title": "Bad"})
    assert response.status_code == 409


def test_delete_task(monkeypatch: pytest.MonkeyPatch) -> None:
    """DELETE /api/v1/tasks/{task_id} returns 204."""
    task_id = uuid.uuid4()

    async def _fake_soft_delete(self, tid: uuid.UUID) -> bool:
        return True

    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyRoomTaskRepository, "soft_delete", _fake_soft_delete
    )

    app = _make_app()
    client = TestClient(app)
    response = client.delete(f"/api/v1/tasks/{task_id}")
    assert response.status_code == 204


def test_delete_task_not_found(monkeypatch: pytest.MonkeyPatch) -> None:
    """DELETE /api/v1/tasks/{task_id} returns 404 for missing task."""

    async def _fake_soft_delete(self, tid: uuid.UUID) -> bool:
        return False

    monkeypatch.setattr(
        focus_rooms_router.SqlAlchemyRoomTaskRepository, "soft_delete", _fake_soft_delete
    )

    app = _make_app()
    client = TestClient(app)
    response = client.delete(f"/api/v1/tasks/{uuid.uuid4()}")
    assert response.status_code == 404


def test_create_room_sprint_fields_rejected_for_regular() -> None:
    """POST /api/v1/rooms with sprint fields and type=regular returns 422."""
    app = _make_app()
    client = TestClient(app, raise_server_exceptions=False)
    response = client.post(
        "/api/v1/rooms",
        json={"title": "Bad Room", "color": "#AABBCC", "type": "regular", "sprint_goal": "Win"},
    )
    assert response.status_code == 422


def test_create_room_invalid_hex_color() -> None:
    """POST /api/v1/rooms with invalid hex color returns 422."""
    app = _make_app()
    client = TestClient(app, raise_server_exceptions=False)
    response = client.post(
        "/api/v1/rooms",
        json={"title": "My Room", "color": "not-a-color"},
    )
    assert response.status_code == 422


def test_set_active_room(monkeypatch: pytest.MonkeyPatch) -> None:
    """PUT /api/v1/rooms/active with a valid room sets active and returns 200."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id)

    async def _fake_execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = room
        return result

    async def _fake_get_active(self):
        return None

    async def _fake_set_active(self, rid):
        return None

    async def _fake_bump(self, user_id):
        return None

    from backend.infrastructure.repositories.gamification_repository import (
        SqlAlchemyGamificationRepository,
    )
    from backend.domain.focus_rooms.service import FocusRoomService

    monkeypatch.setattr(
        SqlAlchemyGamificationRepository, "get_active_focus_room_id", _fake_get_active
    )
    monkeypatch.setattr(
        SqlAlchemyGamificationRepository, "set_active_focus_room_id", _fake_set_active
    )
    monkeypatch.setattr(FocusRoomService, "bump_focus_version", _fake_bump)

    app = _make_app()

    async def _fake_session_with_execute():
        session = AsyncMock()
        session.commit = AsyncMock()
        session.refresh = AsyncMock()
        session.flush = AsyncMock()
        session.execute = _fake_execute
        yield session

    app.dependency_overrides[focus_rooms_router.get_session] = _fake_session_with_execute

    client = TestClient(app)
    response = client.put("/api/v1/rooms/active", json={"room_id": str(room_id)})
    assert response.status_code == 200
    assert response.json()["active_focus_room_id"] == str(room_id)


def test_set_active_room_archived_returns_400(monkeypatch: pytest.MonkeyPatch) -> None:
    """PUT /api/v1/rooms/active with archived room returns 400."""
    room_id = uuid.uuid4()
    room = _fake_room(room_id, archived=True)

    async def _fake_execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = room
        return result

    async def _fake_get_active(self):
        return None

    async def _fake_set_active(self, rid):
        return None

    from backend.infrastructure.repositories.gamification_repository import (
        SqlAlchemyGamificationRepository,
    )

    monkeypatch.setattr(
        SqlAlchemyGamificationRepository, "get_active_focus_room_id", _fake_get_active
    )
    monkeypatch.setattr(
        SqlAlchemyGamificationRepository, "set_active_focus_room_id", _fake_set_active
    )

    app = _make_app()

    async def _fake_session_with_execute():
        session = AsyncMock()
        session.commit = AsyncMock()
        session.refresh = AsyncMock()
        session.flush = AsyncMock()
        session.execute = _fake_execute
        yield session

    app.dependency_overrides[focus_rooms_router.get_session] = _fake_session_with_execute

    client = TestClient(app, raise_server_exceptions=False)
    response = client.put("/api/v1/rooms/active", json={"room_id": str(room_id)})
    assert response.status_code == 400


def test_set_active_room_not_found_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    """PUT /api/v1/rooms/active with missing room returns 404."""

    async def _fake_execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        return result

    async def _fake_get_active(self):
        return None

    from backend.infrastructure.repositories.gamification_repository import (
        SqlAlchemyGamificationRepository,
    )

    monkeypatch.setattr(
        SqlAlchemyGamificationRepository, "get_active_focus_room_id", _fake_get_active
    )

    app = _make_app()

    async def _fake_session_with_execute():
        session = AsyncMock()
        session.commit = AsyncMock()
        session.refresh = AsyncMock()
        session.flush = AsyncMock()
        session.execute = _fake_execute
        yield session

    app.dependency_overrides[focus_rooms_router.get_session] = _fake_session_with_execute

    client = TestClient(app, raise_server_exceptions=False)
    response = client.put("/api/v1/rooms/active", json={"room_id": str(uuid.uuid4())})
    assert response.status_code == 404


def test_create_room_sprint_fields_allowed_for_sprint(monkeypatch: pytest.MonkeyPatch) -> None:
    """POST /api/v1/rooms with sprint fields and type=sprint returns 201."""
    room = _fake_room()
    room.type = focus_rooms_router.FocusRoomType.SPRINT
    room.sprint_goal = "Finish feature"
    room.sprint_total_hours = 40

    async def _fake_create(self, r: Any) -> Any:
        return room

    async def _fake_task_count(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    async def _fake_focus_sec(session: Any, room_id: Any, user_id: Any) -> int:
        return 0

    monkeypatch.setattr(focus_rooms_router.SqlAlchemyFocusRoomRepository, "create", _fake_create)
    monkeypatch.setattr(focus_rooms_router, "_get_room_task_count", _fake_task_count)
    monkeypatch.setattr(focus_rooms_router, "_get_room_focus_seconds", _fake_focus_sec)

    app = _make_app()
    client = TestClient(app)
    response = client.post(
        "/api/v1/rooms",
        json={
            "title": "Sprint Room",
            "color": "#AABBCC",
            "type": "sprint",
            "sprint_goal": "Finish feature",
            "sprint_total_hours": 40,
        },
    )
    assert response.status_code == 201
