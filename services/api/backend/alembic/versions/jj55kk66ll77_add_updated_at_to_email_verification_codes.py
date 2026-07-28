"""add updated_at to email verification codes

Revision ID: jj55kk66ll77
Revises: ii44jj55kk66
Create Date: 2025-01-27 12:15:00.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'jj55kk66ll77'
down_revision = 'ii44jj55kk66'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Добавляем поле updated_at (идемпотентно)
	op.execute(
		"""
		ALTER TABLE email_verification_codes
		ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
		"""
	)


def downgrade() -> None:
	op.execute("ALTER TABLE email_verification_codes DROP COLUMN IF EXISTS updated_at")

