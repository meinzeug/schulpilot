"""Add private, account-bound notification acknowledgements."""

import sqlalchemy as sa
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "notification_reads",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("event_key", sa.String(80), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_index("ix_notification_reads_child_id", "notification_reads", ["child_id"])


def downgrade():
    op.drop_table("notification_reads")
