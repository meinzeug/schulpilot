"""Private source-bound written-work reviews, turns and bounded drafts."""

import sqlalchemy as sa
from alembic import op

revision = "0034"
down_revision = "0033"
branch_labels = depends_on = None


def fk(name, target, *, nullable=False, ondelete="CASCADE", primary_key=False):
    return sa.Column(
        name, sa.String(32), sa.ForeignKey(target, ondelete=ondelete), nullable=nullable, primary_key=primary_key
    )


def upgrade():
    op.create_table(
        "exam_review_pages",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("material_id", "materials.id"),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("upload_revision", sa.Integer(), nullable=False),
        sa.UniqueConstraint("material_id"),
        sa.UniqueConstraint("exam_id", "position"),
    )
    op.create_table(
        "exam_reviews",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("child_id", "children.id"),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("context_revision", sa.String(64), nullable=False),
        sa.Column("source_revisions", sa.JSON(), nullable=False),
        sa.Column("report", sa.JSON(), nullable=False),
        sa.Column("error", sa.String(500)),
        fk("job_id", "jobs.id", nullable=True, ondelete="SET NULL"),
        fk("user_id", "users.id", nullable=True, ondelete="SET NULL"),
        fk("session_id", "sessions.id", nullable=True, ondelete="SET NULL"),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.UniqueConstraint("exam_id"),
    )
    op.create_table(
        "exam_review_turns",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("review_id", "exam_reviews.id"),
        fk("child_id", "children.id"),
        fk("user_id", "users.id"),
        fk("session_id", "sessions.id", nullable=True, ondelete="SET NULL"),
        sa.Column("task_id", sa.String(48), nullable=False),
        sa.Column("context_revision", sa.String(64), nullable=False),
        sa.Column("source_revisions", sa.JSON(), nullable=False),
        sa.Column("action", sa.String(16), nullable=False),
        sa.Column("draft", sa.Text(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("reply", sa.JSON()),
        sa.Column("error", sa.String(500)),
        fk("job_id", "jobs.id", nullable=True, ondelete="SET NULL"),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_table(
        "exam_review_drafts",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("child_id", "children.id"),
        fk("user_id", "users.id"),
        fk("session_id", "sessions.id"),
        sa.Column("task_id", sa.String(48), nullable=False),
        sa.Column("context_revision", sa.String(64), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "session_id", "exam_id", "task_id"),
    )
    op.create_table(
        "exam_review_practices",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("review_id", "exam_reviews.id"),
        fk("child_id", "children.id"),
        sa.Column("task_id", sa.String(48), nullable=False),
        sa.Column("context_revision", sa.String(64), nullable=False),
        fk("job_id", "jobs.id", nullable=True, ondelete="SET NULL"),
        fk("unit_id", "learning_units.id"),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("job_id"),
        sa.UniqueConstraint("unit_id"),
    )
    op.create_table(
        "exam_scan_batches",
        sa.Column("id", sa.String(32), primary_key=True),
        fk("exam_id", "exams.id"),
        fk("child_id", "children.id"),
        sa.Column("state", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.UniqueConstraint("exam_id"),
    )
    for table, fields in {
        "exam_scan_batches": ["child_id"],
        "exam_review_practices": ["exam_id", "child_id"],
        "exam_review_pages": ["exam_id"],
        "exam_reviews": ["child_id", "job_id"],
        "exam_review_turns": ["exam_id", "child_id", "job_id"],
        "exam_review_drafts": ["exam_id", "child_id"],
    }.items():
        for field in fields:
            op.create_index(f"ix_{table}_{field}", table, [field])


def downgrade():
    for table in [
        "exam_scan_batches",
        "exam_review_practices",
        "exam_review_drafts",
        "exam_review_turns",
        "exam_reviews",
        "exam_review_pages",
    ]:
        op.drop_table(table)
