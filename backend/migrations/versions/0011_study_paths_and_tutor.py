"""Persistent source-sized study paths and private, session-bound tutor turns."""

import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = depends_on = None


def upgrade():
    op.add_column("school_days", sa.Column("learning_plan", sa.JSON(), nullable=False, server_default="{}"))
    op.create_table(
        "tutor_turns",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="SET NULL")),
        sa.Column("school_day_id", sa.String(32), sa.ForeignKey("school_days.id", ondelete="CASCADE")),
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE")),
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE")),
        sa.Column("reply_to", sa.String(32), sa.ForeignKey("tutor_turns.id", ondelete="CASCADE")),
        sa.Column("question", sa.Text(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("reply", sa.JSON()),
        sa.Column("error", sa.String(500)),
        sa.Column("source_revisions", sa.JSON(), nullable=False),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL")),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_index("ix_tutor_turns_child_id", "tutor_turns", ["child_id"])
    op.create_index("ix_tutor_turns_created", "tutor_turns", ["created"])


def downgrade():
    op.drop_table("tutor_turns")
    with op.batch_alter_table("school_days") as table:
        table.drop_column("learning_plan")
