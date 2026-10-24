"""Bounded metadata-only account administration receipts."""

import sqlalchemy as sa
from alembic import op

revision = "0042"
down_revision = "0041"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "admin_user_versions",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
    )
    op.create_table(
        "admin_user_operations",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("actor_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("target_id", sa.String(32), nullable=False),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("action", sa.String(24), nullable=False),
        sa.Column("request_digest", sa.String(64), nullable=False),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("expires", sa.Integer(), nullable=False),
        sa.UniqueConstraint("actor_id", "request_key", name="uq_admin_user_operation_key"),
    )
    op.create_index("ix_admin_user_operations_expires", "admin_user_operations", ["expires"])


def downgrade():
    op.drop_table("admin_user_operations")
    op.drop_table("admin_user_versions")
