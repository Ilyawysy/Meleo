"""add users table standalone

Revision ID: aabbccdd1122
Revises: None
Create Date: 2025-10-25 19:45:00.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "aabbccdd1122"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Создаем таблицу users
	op.create_table(
		"users",
		sa.Column("id", sa.String(36), nullable=False),  # UUID as string for SQLite compatibility
		sa.Column("email", sa.String(length=255), nullable=False),
		sa.Column("password_hash", sa.String(length=255), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("email"),
	)

	# Создаем индекс на email
	op.create_index("ix_users_email", "users", ["email"], unique=True)


def downgrade() -> None:
	op.drop_index("ix_users_email", table_name="users")
	op.drop_table("users")
