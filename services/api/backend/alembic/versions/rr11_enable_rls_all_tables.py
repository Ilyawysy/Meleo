"""Enable RLS on all public tables missing it.

Tables affected:
- user_gamification_profile
- daily_focus_aggregate
- gamification_events
- developer_announcements
- user_announcement_reads
- user_state_version
- global_state_version
- idempotency_keys
- streak_plan_history
- checklist_items

No policies added -- RLS with no policies = deny all for anon/authenticated.
Backend uses service_role key which bypasses RLS.

Revision ID: rr11
Revises: qq11
Create Date: 2026-03-06
"""

from __future__ import annotations

from alembic import op

revision = "rr11"
down_revision = "qq11"
branch_labels = None
depends_on = None

_TABLES = [
    "user_gamification_profile",
    "daily_focus_aggregate",
    "gamification_events",
    "developer_announcements",
    "user_announcement_reads",
    "user_state_version",
    "global_state_version",
    "idempotency_keys",
    "streak_plan_history",
    "checklist_items",
]


def upgrade() -> None:
    for table in _TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    for table in _TABLES:
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")
