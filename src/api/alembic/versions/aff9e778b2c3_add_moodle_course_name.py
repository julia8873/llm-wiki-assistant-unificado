"""add_moodle_course_name

Revision ID: aff9e778b2c3
Revises: 77cdb6236db4
Create Date: 2026-09-16 09:02:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'aff9e778b2c3'
down_revision: Union[str, None] = '77cdb6236db4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('mapeos', sa.Column('moodle_course_name', sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column('mapeos', 'moodle_course_name')
