"""populate weekly assignment dates into rhythm_assignment_dates

Data migration: for each weekly assignment, generate dates from start_date
to min(end_date, start_date + 730 days) using weekdays_mask, and insert
into rhythm_assignment_dates. This materializes weekly dates so SQL conflict
checking can use a single EXISTS query.

Revision ID: kk44ll55mm66
Revises: jj33kk44ll55
Create Date: 2026-02-17 13:00:00.000000
"""

from __future__ import annotations

from alembic import op

revision = "kk44ll55mm66"
down_revision = "jj33kk44ll55"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Use server-side PL/pgSQL to generate weekly dates and bulk-insert them.
    # Python weekday(): Monday=0..Sunday=6 matches our weekdays_mask bit layout.
    # Postgres EXTRACT(ISODOW) gives Monday=1..Sunday=7, so we use (ISODOW - 1).
    op.execute("""
    INSERT INTO rhythm_assignment_dates (assignment_id, date)
    SELECT
        a.id,
        d::date
    FROM rhythm_assignments a
    CROSS JOIN LATERAL generate_series(
        a.start_date,
        LEAST(
            COALESCE(a.end_date, a.start_date + INTERVAL '730 days'),
            a.start_date + INTERVAL '730 days'
        ),
        INTERVAL '1 day'
    ) AS d
    JOIN rhythm_templates t ON t.id = a.template_id
    WHERE a.kind = 'weekly'
      AND a.start_date IS NOT NULL
      AND a.weekdays_mask IS NOT NULL
      AND a.weekdays_mask > 0
      AND t.deleted = false
      AND (a.weekdays_mask & (1 << (EXTRACT(ISODOW FROM d)::int - 1))) > 0
    ON CONFLICT (assignment_id, date) DO NOTHING
    """)


def downgrade() -> None:
    # Remove only the backfilled weekly dates.
    # Date-set dates were already present before this migration.
    op.execute("""
    DELETE FROM rhythm_assignment_dates
    WHERE assignment_id IN (
        SELECT id FROM rhythm_assignments WHERE kind = 'weekly'
    )
    """)
