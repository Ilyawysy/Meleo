"""add pg_trgm extension and GIN indexes for search

Revision ID: xxxx_add_pg_trgm_search
Revises: qq11rr22ss33
Create Date: 2025-01-XX XX:XX:XX.XXXXXX
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text

# revision identifiers, used by Alembic.
revision = "xxxx_add_pg_trgm_search"
down_revision = "qq11rr22ss33"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create pg_trgm extension
	op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
	
	# Create normalization function
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
	
	# Add generated columns to tasks table
	op.execute(text("""
		ALTER TABLE tasks 
		ADD COLUMN norm_title TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(title, ''))
		) STORED NOT NULL,
		ADD COLUMN norm_description TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(description, ''))
		) STORED NOT NULL;
	"""))
	
	# Add generated columns to notes table
	op.execute(text("""
		ALTER TABLE notes 
		ADD COLUMN norm_title TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(title, ''))
		) STORED NOT NULL,
		ADD COLUMN norm_text TEXT GENERATED ALWAYS AS (
			normalize_text_for_search(coalesce(text, ''))
		) STORED NOT NULL;
	"""))
	
	# Create GIN indexes on generated columns
	op.execute(text("""
		CREATE INDEX idx_tasks_norm_title_gin ON tasks USING gin(norm_title gin_trgm_ops);
	"""))
	op.execute(text("""
		CREATE INDEX idx_tasks_norm_description_gin ON tasks USING gin(norm_description gin_trgm_ops);
	"""))
	op.execute(text("""
		CREATE INDEX idx_notes_norm_title_gin ON notes USING gin(norm_title gin_trgm_ops);
	"""))
	op.execute(text("""
		CREATE INDEX idx_notes_norm_text_gin ON notes USING gin(norm_text gin_trgm_ops);
	"""))


def downgrade() -> None:
	# Drop indexes
	op.execute(text("DROP INDEX IF EXISTS idx_tasks_norm_title_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_tasks_norm_description_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_notes_norm_title_gin"))
	op.execute(text("DROP INDEX IF EXISTS idx_notes_norm_text_gin"))
	
	# Drop generated columns
	op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS norm_title"))
	op.execute(text("ALTER TABLE tasks DROP COLUMN IF EXISTS norm_description"))
	op.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS norm_title"))
	op.execute(text("ALTER TABLE notes DROP COLUMN IF EXISTS norm_text"))
	
	# Drop function
	op.execute(text("DROP FUNCTION IF EXISTS normalize_text_for_search(TEXT)"))
	
	# (Optional) Drop extension if not used elsewhere
	# op.execute("DROP EXTENSION IF EXISTS pg_trgm")
