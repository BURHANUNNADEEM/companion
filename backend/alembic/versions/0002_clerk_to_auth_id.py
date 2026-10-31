"""PRD §7 auth migration: users.clerk_id -> users.auth_id (+ role/language/email/display_name).

* Fresh databases (created by 0001): no-op.
* Legacy databases that still have `users.clerk_id`:
      alembic stamp 0001_initial && alembic upgrade head
  renames the column and adds the missing columns, keeping all existing rows.

Revision ID: 0002_clerk_to_auth_id
Revises: 0001_initial
Create Date: 2026-10-31
"""
import sqlalchemy as sa
from alembic import op

revision = "0002_clerk_to_auth_id"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def _columns() -> set[str]:
    return {c["name"] for c in sa.inspect(op.get_bind()).get_columns("users")}


def upgrade() -> None:
    cols = _columns()
    if "clerk_id" not in cols:
        return
    with op.batch_alter_table("users") as batch:
        batch.alter_column("clerk_id", new_column_name="auth_id", existing_type=sa.String(128))
        if "role" not in cols:
            batch.add_column(sa.Column("role", sa.String(16), nullable=True))
        if "language" not in cols:
            batch.add_column(sa.Column("language", sa.String(8), nullable=False, server_default="ur"))
        if "email" not in cols:
            batch.add_column(sa.Column("email", sa.String(320), nullable=True))
        if "display_name" not in cols:
            batch.add_column(sa.Column("display_name", sa.String(60), nullable=True))


def downgrade() -> None:
    # Intentionally a no-op: auth_id is the provider-neutral column going forward.
    pass
