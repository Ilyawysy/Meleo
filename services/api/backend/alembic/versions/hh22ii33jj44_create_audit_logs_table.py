"""create audit_logs table

Revision ID: hh22ii33jj44
Revises: b4d7d01582e7
Create Date: 2025-11-11 23:45:00.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "hh22ii33jj44"
down_revision = "b4d7d01582e7"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Создаем таблицу audit_logs
	op.create_table(
		"audit_logs",
		sa.Column("id", sa.String(36), nullable=False, primary_key=True),
		sa.Column("admin_user_id", sa.String(36), nullable=False),
		sa.Column("action", sa.String(100), nullable=False),
		sa.Column("target_user_id", sa.String(36), nullable=True),
		sa.Column("details", postgresql.JSONB, nullable=True),
		sa.Column("ip_address", sa.String(45), nullable=True),  # IPv6 support
		sa.Column("user_agent", sa.String(500), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.PrimaryKeyConstraint("id"),
	)
	
	# Создаем индексы
	op.create_index("ix_audit_logs_admin_user_id", "audit_logs", ["admin_user_id"])
	op.create_index("ix_audit_logs_target_user_id", "audit_logs", ["target_user_id"])
	op.create_index("ix_audit_logs_action", "audit_logs", ["action"])
	op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"])


def downgrade() -> None:
	# Удаляем индексы
	op.drop_index("ix_audit_logs_created_at", table_name="audit_logs")
	op.drop_index("ix_audit_logs_action", table_name="audit_logs")
	op.drop_index("ix_audit_logs_target_user_id", table_name="audit_logs")
	op.drop_index("ix_audit_logs_admin_user_id", table_name="audit_logs")
	
	# Удаляем таблицу
	op.drop_table("audit_logs")

