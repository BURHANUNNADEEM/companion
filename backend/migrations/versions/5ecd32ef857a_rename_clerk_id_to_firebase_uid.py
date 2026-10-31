"""rename clerk_id to firebase_uid

Revision ID: 5ecd32ef857a
Revises: 49c786ccbe1c
Create Date: 2026-10-31 12:47:16.095865

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '5ecd32ef857a'
down_revision: Union[str, Sequence[str], None] = '49c786ccbe1c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
