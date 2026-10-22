"""Private scoped Schulbuddy conversations; existing learning evidence unchanged."""

import sqlalchemy as sa
from alembic import op

revision = "0027"
down_revision = "0026"
branch_labels = depends_on = None


def upgrade():
    op.create_table("schulbuddy_turns",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("job_id", sa.String(32), nullable=False, unique=True),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("context_key", sa.String(64), nullable=False),
        sa.Column("scope", sa.JSON(), nullable=False),
        sa.Column("source_revisions", sa.JSON(), nullable=False),
        sa.Column("reply_to", sa.String(32)),
        sa.Column("question", sa.String(1200), nullable=False),
        sa.Column("reply", sa.JSON()),
        sa.Column("error", sa.String(500)),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "request_key", name="uq_schulbuddy_request"))
    for name in ("child_id", "user_id", "context_key"):
        op.create_index("ix_schulbuddy_turns_" + name, "schulbuddy_turns", [name])


def downgrade():
    op.drop_table("schulbuddy_turns")
