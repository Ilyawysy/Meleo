"""unify user ids to uuid and add user foreign keys

Revision ID: bc23de45fg67
Revises: ab12cd34ef56
Create Date: 2026-01-21 23:00:00.000000
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "bc23de45fg67"
down_revision = "ab12cd34ef56"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Drop existing FK on rhythm_templates if present (string type)
	op.execute("ALTER TABLE rhythm_templates DROP CONSTRAINT IF EXISTS fk_rhythm_templates_user_id_users;")

	# Convert users.id and users.supabase_user_id to UUID
	op.execute(
		"""
		ALTER TABLE users
		ALTER COLUMN id TYPE uuid
		USING id::uuid;
		"""
	)
	op.execute(
		"""
		ALTER TABLE users
		ALTER COLUMN supabase_user_id TYPE uuid
		USING NULLIF(supabase_user_id, '')::uuid;
		"""
	)

	# Convert rhythm_templates.user_id to UUID
	op.execute(
		"""
		ALTER TABLE rhythm_templates
		ALTER COLUMN user_id TYPE uuid
		USING user_id::uuid;
		"""
	)

	# Delete orphaned domain rows (old users are not important)
	op.execute("DELETE FROM tasks WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM notes WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM notifications WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM chat_threads WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM user_shop_items WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM user_balance WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM focus_sessions WHERE user_id NOT IN (SELECT id FROM users);")
	op.execute("DELETE FROM rhythm_templates WHERE user_id NOT IN (SELECT id FROM users);")

	# Re-create FK for rhythm_templates -> users
	op.create_foreign_key(
		"fk_rhythm_templates_user_id_users",
		"rhythm_templates",
		"users",
		["user_id"],
		["id"],
	)

	# Add missing user_id foreign keys for domain tables
	_constraints = [
		("fk_tasks_user_id_users", "tasks", "user_id"),
		("fk_notes_user_id_users", "notes", "user_id"),
		("fk_notifications_user_id_users", "notifications", "user_id"),
		("fk_chat_threads_user_id_users", "chat_threads", "user_id"),
		("fk_user_shop_items_user_id_users", "user_shop_items", "user_id"),
		("fk_user_balance_user_id_users", "user_balance", "user_id"),
		("fk_focus_sessions_user_id_users", "focus_sessions", "user_id"),
	]
	for name, table, column in _constraints:
		op.execute(
			f"""
			DO $$
			BEGIN
				IF NOT EXISTS (
					SELECT 1 FROM pg_constraint WHERE conname = '{name}'
				) THEN
					ALTER TABLE {table}
					ADD CONSTRAINT {name} FOREIGN KEY ({column}) REFERENCES users(id);
				END IF;
			END$$;
			"""
		)


def downgrade() -> None:
	# Drop user_id foreign keys
	op.execute("ALTER TABLE tasks DROP CONSTRAINT IF EXISTS fk_tasks_user_id_users;")
	op.execute("ALTER TABLE notes DROP CONSTRAINT IF EXISTS fk_notes_user_id_users;")
	op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS fk_notifications_user_id_users;")
	op.execute("ALTER TABLE chat_threads DROP CONSTRAINT IF EXISTS fk_chat_threads_user_id_users;")
	op.execute("ALTER TABLE user_shop_items DROP CONSTRAINT IF EXISTS fk_user_shop_items_user_id_users;")
	op.execute("ALTER TABLE user_balance DROP CONSTRAINT IF EXISTS fk_user_balance_user_id_users;")
	op.execute("ALTER TABLE focus_sessions DROP CONSTRAINT IF EXISTS fk_focus_sessions_user_id_users;")
	op.execute("ALTER TABLE rhythm_templates DROP CONSTRAINT IF EXISTS fk_rhythm_templates_user_id_users;")

	# Revert rhythm_templates.user_id to varchar
	op.execute(
		"""
		ALTER TABLE rhythm_templates
		ALTER COLUMN user_id TYPE varchar(36)
		USING user_id::text;
		"""
	)

	# Revert users.supabase_user_id and users.id to varchar
	op.execute(
		"""
		ALTER TABLE users
		ALTER COLUMN supabase_user_id TYPE varchar(36)
		USING supabase_user_id::text;
		"""
	)
	op.execute(
		"""
		ALTER TABLE users
		ALTER COLUMN id TYPE varchar(36)
		USING id::text;
		"""
	)
