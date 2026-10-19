"""Add explicit deterministic rechecks without rewriting answer history."""

import sqlalchemy as sa
from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "attempt_assessments",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("attempt_id", sa.String(32), sa.ForeignKey("attempts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("rules_version", sa.String(40), nullable=False),
        sa.Column("previous_outcome", sa.String(20), nullable=False),
        sa.Column("outcome", sa.String(20), nullable=False),
        sa.Column("previous_evaluation", sa.JSON()),
        sa.Column("evaluation", sa.JSON(), nullable=False),
        sa.Column("actor_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("created", sa.Float(), nullable=False),
        sa.UniqueConstraint("attempt_id", "rules_version"),
    )
    op.create_index("ix_attempt_assessments_attempt_id", "attempt_assessments", ["attempt_id"])


def downgrade():
    op.drop_table("attempt_assessments")
