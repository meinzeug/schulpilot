"""Private exam preparation plans and explicit, bounded learning days."""

import sqlalchemy as sa
from alembic import op

revision = "0033"
down_revision = "0032"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "exams",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column("purpose", sa.String(16), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("subject", sa.String(80), nullable=False),
        sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="SET NULL")),
        sa.Column("exam_date", sa.String(10)),
        sa.Column("timezone", sa.String(80), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("plan_revision", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("minutes", sa.Integer(), nullable=False),
        sa.Column("topics", sa.JSON(), nullable=False),
        sa.Column("schedule", sa.JSON(), nullable=False),
        sa.Column("reminders", sa.Boolean(), nullable=False),
        sa.Column("reminder_time", sa.String(5), nullable=False),
        sa.Column("archived", sa.Boolean(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.Column("create_key", sa.String(113), nullable=False, unique=True),
        sa.Column("request_digest", sa.String(64), nullable=False),
    )
    op.create_index("ix_exams_child_id", "exams", ["child_id"])
    op.create_index("ix_exams_subject_id", "exams", ["subject_id"])
    op.create_table(
        "exam_sessions",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("exam_id", sa.String(32), sa.ForeignKey("exams.id", ondelete="CASCADE"), nullable=False),
        sa.Column("exam_revision", sa.Integer(), nullable=False),
        sa.Column("date", sa.String(10), nullable=False),
        sa.Column("minutes", sa.Integer(), nullable=False),
        sa.Column("topics", sa.JSON(), nullable=False),
        sa.UniqueConstraint("exam_id", "exam_revision", "date"),
    )
    op.create_index("ix_exam_sessions_exam_id", "exam_sessions", ["exam_id"])
    op.create_table(
        "exam_rounds",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("session_id", sa.String(32), sa.ForeignKey("exam_sessions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ordinal", sa.Integer(), nullable=False),
        sa.Column("topic_id", sa.String(48), nullable=False),
        sa.Column("topic_label", sa.String(160), nullable=False),
        sa.Column("question_count", sa.Integer(), nullable=False),
        sa.Column("source_revisions", sa.JSON(), nullable=False),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL")),
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="SET NULL")),
        sa.UniqueConstraint("session_id", "ordinal"),
    )
    for name in ("session_id", "job_id", "unit_id"):
        op.create_index("ix_exam_rounds_" + name, "exam_rounds", [name])


def downgrade():
    op.drop_table("exam_rounds")
    op.drop_table("exam_sessions")
    op.drop_table("exams")
