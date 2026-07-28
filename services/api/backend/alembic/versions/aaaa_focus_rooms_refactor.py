"""focus_rooms refactor: drop+recreate tasks domain, add focus_rooms

Revision ID: aaaa_focus_rooms_refactor
Revises: zz11_add_user_onboarding
Create Date: 2026-04-21 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "aaaa_focus_rooms_refactor"
down_revision = "zz11_add_user_onboarding"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. Drop pg_trgm GIN indexes on tasks (may fail gracefully) ──────────
    op.execute("DROP INDEX IF EXISTS ix_tasks_norm_title_gin;")
    op.execute("DROP INDEX IF EXISTS ix_tasks_norm_description_gin;")
    op.execute("DROP INDEX IF EXISTS ix_tasks_trgm_title;")
    op.execute("DROP INDEX IF EXISTS ix_tasks_trgm_description;")

    # ── 2. Drop old triggers on tasks/checklist_items ────────────────────────
    op.execute("DROP TRIGGER IF EXISTS trg_tasks_version ON tasks;")

    # ── 3. Drop old focus_sessions trigger (will recreate below) ────────────
    op.execute("DROP TRIGGER IF EXISTS trg_focus_sessions_version ON focus_sessions;")

    # ── 4. Drop dependent tables (CASCADE handles FK children) ───────────────
    op.execute("DROP TABLE IF EXISTS focus_task_segments CASCADE;")
    op.execute("DROP TABLE IF EXISTS checklist_items CASCADE;")
    op.execute("DROP TABLE IF EXISTS focus_sessions CASCADE;")
    op.execute("DROP TABLE IF EXISTS tasks CASCADE;")

    # ── 5. Drop old enums ────────────────────────────────────────────────────
    op.execute("DROP TYPE IF EXISTS task_priority CASCADE;")
    op.execute("DROP TYPE IF EXISTS task_recurrence CASCADE;")
    op.execute("DROP TYPE IF EXISTS task_status CASCADE;")
    op.execute("DROP TYPE IF EXISTS focus_session_status CASCADE;")

    # ── 6. Create new enums ──────────────────────────────────────────────────
    op.execute("CREATE TYPE focus_room_type AS ENUM ('regular', 'sprint');")
    op.execute("CREATE TYPE task_status AS ENUM ('not_done', 'done');")
    op.execute(
        "CREATE TYPE focus_session_status AS ENUM ('created', 'running', 'finished', 'cancelled');"
    )

    # ── 7. Create focus_rooms ────────────────────────────────────────────────
    op.create_table(
        "focus_rooms",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("color", sa.String(16), nullable=False),
        sa.Column(
            "type",
            postgresql.ENUM("regular", "sprint", name="focus_room_type", create_type=False),
            nullable=False,
            server_default="regular",
        ),
        sa.Column("archived", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default="0"),
        sa.Column("sprint_goal", sa.String(255), nullable=True),
        sa.Column("sprint_deadline", sa.DateTime(timezone=True), nullable=True),
        sa.Column("sprint_total_hours", sa.Integer, nullable=True),
        sa.Column("deleted", sa.Boolean, nullable=False, server_default="false"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_focus_rooms_user_id", "focus_rooms", ["user_id"])
    op.create_index(
        "ix_focus_rooms_user_active", "focus_rooms", ["user_id", "archived", "sort_order"]
    )
    op.create_index("ix_focus_rooms_user_updated", "focus_rooms", ["user_id", "updated_at", "id"])

    # ── 8. Recreate tasks (simplified) ───────────────────────────────────────
    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "room_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("focus_rooms.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column(
            "status",
            postgresql.ENUM("not_done", "done", name="task_status", create_type=False),
            nullable=False,
            server_default="not_done",
        ),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default="0"),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted", sa.Boolean, nullable=False, server_default="false"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_tasks_room_id", "tasks", ["room_id"])
    op.create_index("ix_tasks_user_id", "tasks", ["user_id"])
    op.create_index("ix_tasks_room_sort", "tasks", ["room_id", "sort_order"])
    op.create_index("ix_tasks_user_updated", "tasks", ["user_id", "updated_at", "id"])

    # ── 9. Recreate checklist_items ───────────────────────────────────────────
    op.create_table(
        "checklist_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "task_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("is_done", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("sort_order", sa.Integer, nullable=False, server_default="0"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_checklist_items_task_id", "checklist_items", ["task_id"])

    # ── 10. Recreate focus_sessions (with room_id) ────────────────────────────
    op.create_table(
        "focus_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "room_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("focus_rooms.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("planned_duration_sec", sa.Integer, nullable=False),
        sa.Column(
            "status",
            postgresql.ENUM(
                "created",
                "running",
                "finished",
                "cancelled",
                name="focus_session_status",
                create_type=False,
            ),
            nullable=False,
            server_default="created",
        ),
        sa.Column("active_elapsed_sec", sa.Integer, nullable=False, server_default="0"),
        sa.Column("last_state_change_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "task_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tasks.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("earned_coins", sa.Integer, nullable=False, server_default="0"),
        sa.Column("credited_minutes", sa.Integer, nullable=True),
        sa.Column("earned_xp", sa.Integer, nullable=False, server_default="0"),
        sa.Column("session_day", sa.Date, nullable=True),
        sa.Column("undo_deadline_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_focus_sessions_user_id", "focus_sessions", ["user_id"])
    op.create_index("ix_focus_sessions_room_id", "focus_sessions", ["room_id"])

    # ── 11. Recreate focus_task_segments ─────────────────────────────────────
    op.create_table(
        "focus_task_segments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "session_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("focus_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("tasks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index("ix_focus_task_segments_session_id", "focus_task_segments", ["session_id"])
    op.create_index("ix_focus_task_segments_task_id", "focus_task_segments", ["task_id"])
    op.create_index("ix_focus_task_segments_user_id", "focus_task_segments", ["user_id"])

    # ── 12. Drop tasks_version from user_state_version ────────────────────────
    op.execute("ALTER TABLE user_state_version DROP COLUMN IF EXISTS tasks_version;")

    # ── 13. Update version triggers ───────────────────────────────────────────
    # Add focus_rooms trigger (bumps focus_version)
    op.execute("""
        CREATE TRIGGER trg_focus_rooms_version
        AFTER INSERT OR UPDATE OR DELETE ON focus_rooms
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    # Restore focus_sessions trigger
    op.execute("""
        CREATE TRIGGER trg_focus_sessions_version
        AFTER INSERT OR UPDATE OR DELETE ON focus_sessions
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)

    # tasks trigger now bumps focus_version (tasks are children of focus_rooms)
    op.execute("""
        CREATE TRIGGER trg_tasks_version
        AFTER INSERT OR UPDATE OR DELETE ON tasks
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('focus_version');
    """)


def downgrade() -> None:
    # No live users — downgrade is intentionally a no-op.
    pass
