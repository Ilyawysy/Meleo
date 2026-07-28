"""increment announcements version on user_announcement_reads changes

Revision ID: ff77aa88bb99
Revises: ee55ff66gg77
Create Date: 2026-02-15 01:10:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "ff77aa88bb99"
down_revision = "ee55ff66gg77"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_announcement_reads_version ON user_announcement_reads")
    op.execute(
        """
        CREATE TRIGGER trg_announcement_reads_version
        AFTER INSERT OR DELETE ON user_announcement_reads
        FOR EACH ROW
        EXECUTE FUNCTION increment_user_state_version('announcements_version')
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_announcement_reads_version ON user_announcement_reads;")
