"""Private parent-managed school results; never replace learning evidence."""

import sqlalchemy as sa
from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = depends_on = None


def upgrade():
    op.add_column("children", sa.Column("grade_planning_enabled", sa.Boolean(), nullable=False, server_default=sa.true()))
    op.create_table(
        "school_grades",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("subject", sa.String(80), nullable=False),
        sa.Column("topic", sa.String(160), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("scale", sa.String(12), nullable=False),
        sa.Column("value", sa.Numeric(4, 2), nullable=False),
        sa.Column("weight", sa.Integer(), nullable=False),
        sa.Column("assessed_on", sa.String(10), nullable=False),
        sa.Column("note", sa.String(500), nullable=False),
        sa.Column("assignment_id", sa.String(32), sa.ForeignKey("assignments.id", ondelete="SET NULL")),
        sa.Column("request_key", sa.String(80)),
        sa.Column("request_digest", sa.String(64)),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "request_key", name="uq_grade_request"),
    )
    op.create_index("ix_school_grades_child_id", "school_grades", ["child_id"])


def downgrade():
    op.drop_table("school_grades")
    with op.batch_alter_table("children") as table:
        table.drop_column("grade_planning_enabled")
