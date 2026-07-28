"""add global_state_version for announcements etag

Revision ID: ee66ff77gg88
Revises: dd44ee55ff66
Create Date: 2026-02-14 01:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "ee66ff77gg88"
down_revision = "dd44ee55ff66"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Singleton row table for global counters used in sync ETag.
    op.create_table(
        "global_state_version",
        sa.Column("id", sa.SmallInteger(), primary_key=True),
        sa.Column(
            "announcements_version",
            sa.BigInteger(),
            nullable=False,
            server_default="0",
        ),
        sa.CheckConstraint("id = 1", name="ck_global_state_version_single_row"),
    )

    op.execute("INSERT INTO global_state_version (id, announcements_version) VALUES (1, 0)")

    # Reuse existing trigger name/function, but increment singleton counter instead
    # of updating every user row.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION increment_announcements_global_version()
        RETURNS TRIGGER AS $$
        BEGIN
            INSERT INTO global_state_version (id, announcements_version)
            VALUES (1, 1)
            ON CONFLICT (id)
            DO UPDATE SET announcements_version = global_state_version.announcements_version + 1;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
        """
    )


def downgrade() -> None:
    # Restore previous behavior from bb11cc22dd33 migration.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION increment_announcements_global_version()
        RETURNS TRIGGER AS $$
        BEGIN
            UPDATE user_state_version
            SET announcements_version = announcements_version + 1;

            RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;
        """
    )

    op.drop_table("global_state_version")
