"""Literal source roles; task presentation v1 lives in existing immutable question JSON."""

import sqlalchemy as sa
from alembic import op

revision = "0022"
down_revision = "0021"
branch_labels = depends_on = None


def upgrade():
    op.add_column("jobs", sa.Column("error_code", sa.String(24)))
    op.add_column("materials", sa.Column("source_blocks", sa.JSON(), server_default="[]", nullable=False))


def downgrade():
    op.drop_column("jobs", "error_code")
    op.drop_column("materials", "source_blocks")
