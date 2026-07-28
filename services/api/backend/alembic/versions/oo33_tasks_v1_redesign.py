"""Tasks v1 redesign: plan_day, start_time, sort_order, checklist_items

Revision ID: oo33
Revises: nn23_stopped_cancel
Create Date: 2026-03-03
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "oo33"
down_revision = "nn23_stopped_cancel"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("tasks", sa.Column("plan_day", sa.Date(), nullable=True))
    op.add_column("tasks", sa.Column("start_time", sa.Time(), nullable=True))
    op.add_column(
        "tasks",
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_tasks_plan_day", "tasks", ["plan_day"])

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
        sa.Column("is_done", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
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


def downgrade() -> None:
    op.drop_index("ix_checklist_items_task_id", table_name="checklist_items")
    op.drop_table("checklist_items")
    op.drop_index("ix_tasks_plan_day", table_name="tasks")
    op.drop_column("tasks", "sort_order")
    op.drop_column("tasks", "start_time")
    op.drop_column("tasks", "plan_day")
