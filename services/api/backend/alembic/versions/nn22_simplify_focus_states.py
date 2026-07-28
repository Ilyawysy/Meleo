"""simplify focus states: 9 → 5 (finished, stopped replace old states)

Revision ID: nn22_simplify
Revises: mm11_gam_v102
Create Date: 2026-03-01 12:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "nn22_simplify"
down_revision = "mm11_gam_v102"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. Add new enum values (requires COMMIT for ALTER TYPE) ──
    op.execute("COMMIT")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'finished'")
    op.execute("ALTER TYPE focus_session_status ADD VALUE IF NOT EXISTS 'stopped'")

    # ── 2. Map old statuses to new ones ──
    op.execute("""
        UPDATE focus_sessions SET status = 'finished'
        WHERE status IN ('stopped_pending_credit', 'credited_undoable', 'credited_final')
    """)
    op.execute("""
        UPDATE focus_sessions SET status = 'cancelled'
        WHERE status IN ('paused', 'awaiting_confirm', 'completed')
    """)

    # ── 3. Clear undo_deadline_at (no longer used) ──
    op.execute("""
        UPDATE focus_sessions SET undo_deadline_at = NULL
        WHERE undo_deadline_at IS NOT NULL
    """)


def downgrade() -> None:
    # Old enum values remain in Postgres (cannot remove from enum).
    # Map back: finished → credited_final, stopped → cancelled
    op.execute("""
        UPDATE focus_sessions SET status = 'credited_final'
        WHERE status = 'finished'
    """)
    op.execute("""
        UPDATE focus_sessions SET status = 'cancelled'
        WHERE status = 'stopped'
    """)
