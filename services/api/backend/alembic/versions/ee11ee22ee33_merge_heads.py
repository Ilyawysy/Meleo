from __future__ import annotations

from alembic import op  # noqa: F401
import sqlalchemy as sa  # noqa: F401

# revision identifiers, used by Alembic.
revision = "ee11ee22ee33"
down_revision = ("abcdef123456", "a1b2c3d4e5f7", "e0f1a2b3c4d5")
branch_labels = None
depends_on = None


def upgrade() -> None:
	# This is a merge migration; no operations are required.
	pass


def downgrade() -> None:
	# This merge has no structural changes to revert.
	pass
