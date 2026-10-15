"""Durable school preparation and nullable measured provider search counts."""

import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = depends_on = None


def upgrade():
    op.add_column("school_days", sa.Column("preparation", sa.JSON(), nullable=False, server_default="{}"))
    # Legacy requests are unknown, never an invented zero-search measurement.
    op.add_column("usage", sa.Column("search_calls", sa.Integer(), nullable=True))


def downgrade():
    with op.batch_alter_table("usage") as table:
        table.drop_column("search_calls")
    with op.batch_alter_table("school_days") as table:
        table.drop_column("preparation")
