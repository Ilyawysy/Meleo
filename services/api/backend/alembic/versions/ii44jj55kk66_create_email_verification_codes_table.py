"""create email verification codes table

Revision ID: ii44jj55kk66
Revises: 045651e658f3
Create Date: 2025-01-27 12:00:00.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'ii44jj55kk66'
down_revision = '045651e658f3'
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"email_verification_codes",
		sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
		sa.Column("user_id", sa.String(36), nullable=True),  # TEXT NULL - может быть внешний auth user id
		sa.Column("email", sa.String(255), nullable=False),
		sa.Column("code_hash", sa.String(255), nullable=False),  # bcrypt hash
		sa.Column("purpose", sa.String(50), nullable=False),  # 'verify_email', 'login', 'reset_password'
		sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("last_sent_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("resend_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
	)
	
	# Index for active codes (not consumed)
	op.create_index(
		"email_verification_codes_active_idx",
		"email_verification_codes",
		["email", "purpose"],
		unique=False,
		postgresql_where=sa.text("consumed_at IS NULL")
	)


def downgrade() -> None:
	op.drop_index("email_verification_codes_active_idx", table_name="email_verification_codes")
	op.drop_table("email_verification_codes")

