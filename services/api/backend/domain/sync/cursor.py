from __future__ import annotations

import base64
import hmac
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from backend.infrastructure.config import settings
from backend.infrastructure.logging import get_logger

logger = get_logger("sync.cursor")

_EPOCH = datetime.min.replace(tzinfo=timezone.utc)
_ZERO_UUID = uuid.UUID("00000000-0000-0000-0000-000000000000")

_DOMAINS = ("notifications", "messages", "focus")


@dataclass
class DomainCursor:
    updated_at: datetime
    last_id: uuid.UUID


@dataclass
class SyncCursor:
    notifications: DomainCursor
    messages: DomainCursor
    focus: DomainCursor

    @classmethod
    def initial(cls) -> SyncCursor:
        """Initial cursor — fetches everything from epoch."""
        return cls(
            notifications=DomainCursor(_EPOCH, _ZERO_UUID),
            messages=DomainCursor(_EPOCH, _ZERO_UUID),
            focus=DomainCursor(_EPOCH, _ZERO_UUID),
        )

    def encode(self) -> str:
        """Encode cursor to base64 string with HMAC signature."""
        data = {}
        for domain in _DOMAINS:
            dc: DomainCursor = getattr(self, domain)
            data[domain] = {
                "t": dc.updated_at.isoformat(),
                "id": str(dc.last_id),
            }

        json_str = json.dumps(data, separators=(",", ":"))
        cursor_b64 = base64.urlsafe_b64encode(json_str.encode()).decode()

        sig = _sign(cursor_b64)
        return f"{cursor_b64}.{sig}"

    @classmethod
    def decode(cls, raw: str) -> SyncCursor:
        """Decode cursor string. Falls back to initial() on any error."""
        try:
            parts = raw.rsplit(".", 1)
            if len(parts) != 2:
                logger.warning("cursor_missing_signature")
                return cls.initial()

            cursor_b64, sig = parts

            # Verify HMAC
            expected = _sign(cursor_b64)
            if not hmac.compare_digest(sig, expected):
                logger.warning("cursor_signature_mismatch")
                return cls.initial()

            # Decode JSON
            json_str = base64.urlsafe_b64decode(cursor_b64).decode()
            data = json.loads(json_str)

            # Build cursor (backward-compatible: missing domains get epoch)
            cursors = {}
            for domain in _DOMAINS:
                d = data.get(domain)
                if d is None:
                    cursors[domain] = DomainCursor(_EPOCH, _ZERO_UUID)
                else:
                    cursors[domain] = DomainCursor(
                        updated_at=datetime.fromisoformat(d["t"]),
                        last_id=uuid.UUID(d["id"]),
                    )

            cursor = cls(**cursors)

            # Clamp to present (protect against future timestamps)
            return _clamp_to_present(cursor)

        except Exception as e:
            logger.warning("cursor_decode_failed", error=str(e))
            return cls.initial()


def _sign(payload: str) -> str:
    """HMAC-SHA256 signature, truncated to 16 hex chars."""
    return hmac.new(
        settings.CURSOR_SECRET.encode(),
        payload.encode(),
        digestmod="sha256",
    ).hexdigest()[:16]


def _clamp_to_present(cursor: SyncCursor) -> SyncCursor:
    """Clamp all timestamps to now (protection against crafted future cursors)."""
    now = datetime.now(timezone.utc)
    for domain in _DOMAINS:
        dc: DomainCursor = getattr(cursor, domain)
        if dc.updated_at > now:
            dc.updated_at = now
    return cursor
