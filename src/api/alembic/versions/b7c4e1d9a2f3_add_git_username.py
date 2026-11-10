"""add git_username

Revision ID: b7c4e1d9a2f3
Revises: aff9e778b2c3
Create Date: 2026-11-10 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7c4e1d9a2f3'
down_revision: Union[str, None] = 'aff9e778b2c3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Idempotente: si la columna ya existe (p. ej. tablas creadas desde el ORM), no hace nada.
    columns = [c['name'] for c in sa.inspect(op.get_bind()).get_columns('mapeos')]
    if 'git_username' not in columns:
        op.add_column('mapeos', sa.Column('git_username', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('mapeos', 'git_username')
