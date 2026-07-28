"""ensure search normalization columns exist

Revision ID: dd11ee22ff33
Revises: cc11dd22ee33
Create Date: 2026-01-23 12:20:00.000000
"""
from __future__ import annotations

from alembic import op
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision = "dd11ee22ff33"
down_revision = "cc11dd22ee33"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Ensure pg_trgm extension and normalization function exist
	op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
	op.execute(text("""
		CREATE OR REPLACE FUNCTION normalize_text_for_search(input_text TEXT)
		RETURNS TEXT AS $$
		BEGIN
			RETURN trim(
				regexp_replace(
					regexp_replace(
						replace(
							lower(coalesce(input_text, '')),
							'ё', 'е'
						),
						'[^a-z0-9а-я]', ' ', 'g'
					),
					'\\s+', ' ', 'g'
				)
			);
		END;
		$$ LANGUAGE plpgsql IMMUTABLE STRICT;
	"""))

	# Add generated columns if missing
	op.execute(text("""
		ALTER TABLE tasks 
		ADD COLUMN IF NOT EXISTS norm_title TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(title, ''))
		) STORED,
		ADD COLUMN IF NOT EXISTS norm_description TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(description, ''))
		) STORED;
	"""))

	op.execute(text("""
		ALTER TABLE notes 
		ADD COLUMN IF NOT EXISTS norm_title TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(title, ''))
		) STORED,
		ADD COLUMN IF NOT EXISTS norm_text TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(text, ''))
		) STORED;
	"""))

	# Create GIN indexes if missing
	op.execute(text("CREATE INDEX IF NOT EXISTS idx_tasks_norm_title_gin ON tasks USING gin(norm_title gin_trgm_ops)"))
	op.execute(text("CREATE INDEX IF NOT EXISTS idx_tasks_norm_description_gin ON tasks USING gin(norm_description gin_trgm_ops)"))
	op.execute(text("CREATE INDEX IF NOT EXISTS idx_notes_norm_title_gin ON notes USING gin(norm_title gin_trgm_ops)"))
	op.execute(text("CREATE INDEX IF NOT EXISTS idx_notes_norm_text_gin ON notes USING gin(norm_text gin_trgm_ops)"))


def downgrade() -> None:
	# Conservative rollback
	op.execute(text("DROP INDEX IF EXISTS idx_notes_norm_text_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_notes_norm_title_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_tasks_norm_description_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_tasks_norm_title_gin"))
	op.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS norm_text"))
	op.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS norm_title"))
	op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS norm_description"))
	op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS norm_title"))
