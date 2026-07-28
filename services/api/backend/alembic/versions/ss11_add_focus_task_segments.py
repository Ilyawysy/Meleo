"""Add focus_task_segments table

Revision ID: ss11
Revises: rr11
Create Date: 2026-03-07
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "ss11"
down_revision = "rr11"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "focus_task_segments",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "session_id",
            UUID(as_uuid=True),
            sa.ForeignKey("focus_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "task_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tasks.id"),
            nullable=False,
        ),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_focus_task_segments_session_id", "focus_task_segments", ["session_id"])
    op.create_index("ix_focus_task_segments_task_id", "focus_task_segments", ["task_id"])
    op.create_index("ix_focus_task_segments_user_id", "focus_task_segments", ["user_id"])
    op.create_index(
        "ix_focus_task_segments_user_task",
        "focus_task_segments",
        ["user_id", "task_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_focus_task_segments_user_task", table_name="focus_task_segments")
    op.drop_index("ix_focus_task_segments_user_id", table_name="focus_task_segments")
    op.drop_index("ix_focus_task_segments_task_id", table_name="focus_task_segments")
    op.drop_index("ix_focus_task_segments_session_id", table_name="focus_task_segments")
    op.drop_table("focus_task_segments")
