"""drop_email_verification_codes_table

Revision ID: 238c239f5e10
Revises: gg33_themes
Create Date: 2026-02-09 00:38:46.858195
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '238c239f5e10'
down_revision = 'gg33_themes'
branch_labels = None
depends_on = None


def upgrade() -> None:
	"""
	Удаляем таблицу email_verification_codes.
	Mobile использует Supabase OTP напрямую, backend OTP endpoints удалены.
	"""
	op.execute("DROP TABLE IF EXISTS email_verification_codes CASCADE;")


def downgrade() -> None:
	"""
	Восстановление таблицы email_verification_codes.
	Схема взята из миграции ii44jj55kk66_create_email_verification_codes_table.
	"""
	op.execute("""
		CREATE TABLE IF NOT EXISTS email_verification_codes (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			email VARCHAR(255) NOT NULL,
			code_hash VARCHAR(255) NOT NULL,
			purpose VARCHAR(50) NOT NULL,
			expires_at TIMESTAMPTZ NOT NULL,
			attempts INTEGER NOT NULL DEFAULT 0,
			consumed_at TIMESTAMPTZ,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);

		CREATE INDEX IF NOT EXISTS idx_email_verification_codes_email_purpose
		ON email_verification_codes(email, purpose);

		CREATE INDEX IF NOT EXISTS idx_email_verification_codes_expires_at
		ON email_verification_codes(expires_at);
	""")
