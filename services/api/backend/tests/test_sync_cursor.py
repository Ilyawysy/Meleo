from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

from backend.domain.sync.cursor import DomainCursor, SyncCursor


def _cursor_with_timestamp(ts: datetime) -> SyncCursor:
    return SyncCursor(
        notifications=DomainCursor(ts, uuid.uuid4()),
        messages=DomainCursor(ts, uuid.uuid4()),
        focus=DomainCursor(ts, uuid.uuid4()),
    )


def test_cursor_roundtrip_preserves_values() -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    cursor = _cursor_with_timestamp(now)

    decoded = SyncCursor.decode(cursor.encode())

    assert decoded.notifications.updated_at == now
    assert decoded.notifications.last_id == cursor.notifications.last_id
    assert decoded.messages.last_id == cursor.messages.last_id
    assert decoded.focus.last_id == cursor.focus.last_id


def test_cursor_tampering_falls_back_to_initial() -> None:
    encoded = SyncCursor.initial().encode()
    payload, _sig = encoded.rsplit(".", 1)
    tampered = f"{payload}.deadbeefdeadbeef"

    assert SyncCursor.decode(tampered) == SyncCursor.initial()


def test_cursor_missing_signature_falls_back_to_initial() -> None:
    encoded = SyncCursor.initial().encode()
    payload = encoded.rsplit(".", 1)[0]

    assert SyncCursor.decode(payload) == SyncCursor.initial()


def test_future_timestamp_is_clamped() -> None:
    future = datetime.now(timezone.utc) + timedelta(days=7)
    cursor = _cursor_with_timestamp(future)

    decoded = SyncCursor.decode(cursor.encode())

    assert decoded.notifications.updated_at <= datetime.now(timezone.utc)
    assert decoded.messages.updated_at <= datetime.now(timezone.utc)
    assert decoded.focus.updated_at <= datetime.now(timezone.utc)
