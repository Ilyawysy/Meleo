"""add supabase_user_id to users table

Revision ID: ab12cd34ef56
Revises: 8381d10c5af6
Create Date: 2026-01-21 12:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "ab12cd34ef56"
down_revision = "8381d10c5af6"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Add supabase_user_id (nullable for backfill)
	op.add_column(
		"users",
		sa.Column("supabase_user_id", sa.String(length=36), nullable=True),
	)
	op.create_index("ix_users_supabase_user_id", "users", ["supabase_user_id"], unique=True)

	# Drop keycloak_id if it exists
	op.execute(
		"""
		DO $$
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM information_schema.columns
				WHERE table_name = 'users'
				AND column_name = 'keycloak_id'
			) THEN
				ALTER TABLE users DROP COLUMN keycloak_id;
			END IF;
		END$$;
		"""
	)
	op.execute(
		"""
		DO $$
		BEGIN
			IF EXISTS (
				SELECT 1
				FROM pg_indexes
				WHERE tablename = 'users'
				AND indexname = 'ix_users_keycloak_id'
			) THEN
				DROP INDEX ix_users_keycloak_id;
			END IF;
		END$$;
		"""
	)


def downgrade() -> None:
	op.add_column(
		"users",
		sa.Column("keycloak_id", sa.String(length=36), nullable=True),
	)
	op.create_index("ix_users_keycloak_id", "users", ["keycloak_id"], unique=True)
	op.drop_index("ix_users_supabase_user_id", table_name="users")
	op.drop_column("users", "supabase_user_id")
