"""make refresh_tokens.moodle_user_id nullable and add moodle_username

Revision ID: c3f1a2b4d5e6
Revises: bf999a9c4337
Create Date: 2026-09-15 17:41:00.000000

Contexto: un usuario puede estar registrado en Moodle pero no tener ningún
mapeo de curso en mapeo-api todavía. En ese caso moodle_user_id es None y el
INSERT fallaba con NOT NULL violation. Se hace nullable y se añade
moodle_username como identificador alternativo de sesión.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'c3f1a2b4d5e6'
down_revision: Union[str, Sequence[str], None] = 'bf999a9c4337'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Hacer nullable la columna moodle_user_id en refresh_tokens
    op.alter_column(
        'refresh_tokens',
        'moodle_user_id',
        existing_type=sa.Integer(),
        nullable=True,
        schema='metrics'
    )

    # Añadir columna moodle_username para identificar la sesión cuando no hay user_id
    op.add_column(
        'refresh_tokens',
        sa.Column('moodle_username', sa.String(), nullable=True),
        schema='metrics'
    )
    op.create_index(
        op.f('ix_metrics_refresh_tokens_moodle_username'),
        'refresh_tokens',
        ['moodle_username'],
        unique=False,
        schema='metrics'
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(
        op.f('ix_metrics_refresh_tokens_moodle_username'),
        table_name='refresh_tokens',
        schema='metrics'
    )
    op.drop_column('refresh_tokens', 'moodle_username', schema='metrics')

    # Restaurar NOT NULL (puede fallar si hay filas con NULL; limpiar antes si es necesario)
    op.alter_column(
        'refresh_tokens',
        'moodle_user_id',
        existing_type=sa.Integer(),
        nullable=False,
        schema='metrics'
    )
