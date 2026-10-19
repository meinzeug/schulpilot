"""Explicit homework decisions and stable source/confirmation provenance."""

import sqlalchemy as sa
from alembic import op

revision = "0021"
down_revision = "0020"
branch_labels = depends_on = None


def upgrade():
    op.add_column("messages", sa.Column("context", sa.JSON()))
    op.add_column("materials", sa.Column("confirmation_digest", sa.String(64)))
    op.add_column("materials", sa.Column("task_decisions", sa.JSON(), server_default="[]", nullable=False))
    op.add_column("assignments", sa.Column("origin_kind", sa.String(24)))
    op.add_column("assignments", sa.Column("source_key", sa.String(64)))
    op.add_column("assignments", sa.Column("source_revisions", sa.JSON(), server_default="[]", nullable=False))
    op.add_column("assignments", sa.Column("source_status", sa.String(20), server_default="confirmed", nullable=False))
    op.create_index("uq_assignment_source_key", "assignments", ["source_key"], unique=True)


def downgrade():
    op.drop_column("messages", "context")
    op.drop_index("uq_assignment_source_key", table_name="assignments")
    for name in ("source_status", "source_revisions", "source_key", "origin_kind"):
        op.drop_column("assignments", name)
    op.drop_column("materials", "confirmation_digest")
    op.drop_column("materials", "task_decisions")
