"""create rhythm tables

Revision ID: qq11rr22ss33
Revises: 8381d10c5af6
Create Date: 2025-01-15 12:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "qq11rr22ss33"
down_revision = "8381d10c5af6"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create rhythm_block_type enum
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rhythm_block_type') THEN
			CREATE TYPE rhythm_block_type AS ENUM ('sleep', 'work', 'rest');
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rhythm_assignment_kind') THEN
			CREATE TYPE rhythm_assignment_kind AS ENUM ('one_off', 'weekly', 'date_set');
		END IF;
	END$$;
	""")

	# Create rhythm_templates table (idempotent)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rhythm_templates') THEN
			CREATE TABLE rhythm_templates (
				id UUID NOT NULL PRIMARY KEY,
				user_id VARCHAR(36) NOT NULL,
				name VARCHAR(255) NOT NULL,
				version INTEGER DEFAULT 1 NOT NULL,
				created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
				updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
				deleted BOOLEAN DEFAULT false NOT NULL,
				deleted_at TIMESTAMP WITH TIME ZONE,
				CONSTRAINT fk_rhythm_templates_user_id_users FOREIGN KEY(user_id) REFERENCES users (id)
			);
		END IF;
	END$$;
	""")

	# Create rhythm_segments table (idempotent)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rhythm_segments') THEN
			CREATE TABLE rhythm_segments (
				id UUID NOT NULL PRIMARY KEY,
				template_id UUID NOT NULL,
				type rhythm_block_type NOT NULL,
				start_min INTEGER NOT NULL,
				end_min INTEGER NOT NULL,
				sort_order INTEGER,
				day_offset INTEGER DEFAULT 0 NOT NULL,
				CONSTRAINT fk_rhythm_segments_template_id_rhythm_templates FOREIGN KEY(template_id) REFERENCES rhythm_templates (id) ON DELETE CASCADE
			);
		END IF;
	END$$;
	""")

	# Create rhythm_assignments table (idempotent)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rhythm_assignments') THEN
			CREATE TABLE rhythm_assignments (
				id UUID NOT NULL PRIMARY KEY,
				template_id UUID NOT NULL,
				kind rhythm_assignment_kind NOT NULL,
				one_date DATE,
				start_date DATE,
				end_date DATE,
				weekdays_mask INTEGER,
				created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
				updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
				CONSTRAINT fk_rhythm_assignments_template_id_rhythm_templates FOREIGN KEY(template_id) REFERENCES rhythm_templates (id) ON DELETE CASCADE
			);
		END IF;
	END$$;
	""")

	# Create rhythm_assignment_dates table (idempotent)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rhythm_assignment_dates') THEN
			CREATE TABLE rhythm_assignment_dates (
				assignment_id UUID NOT NULL,
				date DATE NOT NULL,
				PRIMARY KEY (assignment_id, date),
				CONSTRAINT fk_rhythm_assignment_dates_assignment_id_rhythm_assignments FOREIGN KEY(assignment_id) REFERENCES rhythm_assignments (id) ON DELETE CASCADE
			);
		END IF;
	END$$;
	""")

	# Create indexes (idempotent)
	op.execute("""
	DO $$
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_templates_user_id') THEN
			CREATE INDEX ix_rhythm_templates_user_id ON rhythm_templates (user_id);
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_templates_user_updated_id') THEN
			CREATE INDEX ix_rhythm_templates_user_updated_id ON rhythm_templates (user_id, updated_at, id);
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_segments_template_id') THEN
			CREATE INDEX ix_rhythm_segments_template_id ON rhythm_segments (template_id);
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_assignments_template_id') THEN
			CREATE INDEX ix_rhythm_assignments_template_id ON rhythm_assignments (template_id);
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_assignment_dates_assignment_id') THEN
			CREATE INDEX ix_rhythm_assignment_dates_assignment_id ON rhythm_assignment_dates (assignment_id);
		END IF;
		IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_rhythm_assignment_dates_date') THEN
			CREATE INDEX ix_rhythm_assignment_dates_date ON rhythm_assignment_dates (date);
		END IF;
	END$$;
	""")


def downgrade() -> None:
	# Drop indexes
	op.drop_index('ix_rhythm_assignment_dates_date', table_name='rhythm_assignment_dates')
	op.drop_index('ix_rhythm_assignment_dates_assignment_id', table_name='rhythm_assignment_dates')
	op.drop_index('ix_rhythm_assignments_template_id', table_name='rhythm_assignments')
	op.drop_index('ix_rhythm_segments_template_id', table_name='rhythm_segments')
	op.drop_index('ix_rhythm_templates_user_updated_id', table_name='rhythm_templates')
	op.drop_index('ix_rhythm_templates_user_id', table_name='rhythm_templates')

	# Drop tables (order matters due to foreign keys)
	op.drop_table('rhythm_assignment_dates')
	op.drop_table('rhythm_assignments')
	op.drop_table('rhythm_segments')
	op.drop_table('rhythm_templates')

	# Drop enums
	op.execute("DROP TYPE IF EXISTS rhythm_assignment_kind")
	op.execute("DROP TYPE IF EXISTS rhythm_block_type")
