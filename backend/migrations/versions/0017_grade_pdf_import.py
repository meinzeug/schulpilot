"""Private repeatable grade PDF imports; unknown assessment dates stay unknown."""

import sqlalchemy as sa
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = depends_on = None


def upgrade():
    with op.batch_alter_table("school_grades") as table:
        table.alter_column("assessed_on", existing_type=sa.String(10), nullable=True)
        table.add_column(sa.Column("school_year_start", sa.Integer()))
        table.add_column(sa.Column("semester", sa.Integer()))
        table.create_check_constraint(
            "ck_grade_known_period",
            "assessed_on IS NOT NULL OR (school_year_start IS NOT NULL AND semester IS NOT NULL AND semester IN (1,2))",
        )
    op.create_table(
        "grade_imports",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("file_digest", sa.String(64), nullable=False),
        sa.Column("school_year_start", sa.Integer(), nullable=False),
        sa.Column("entries", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("confirmation_digest", sa.String(64)),
        sa.Column("result", sa.JSON()),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "request_key", name="uq_grade_import_request"),
    )
    op.create_index("ix_grade_imports_child_id", "grade_imports", ["child_id"])
    op.create_index("ix_grade_imports_created", "grade_imports", ["created"])
    op.create_table(
        "grade_source_slots",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("grade_id", sa.String(32), sa.ForeignKey("school_grades.id", ondelete="SET NULL"), unique=True),
        sa.Column("slot_key", sa.String(64), nullable=False),
        sa.Column("school_year_start", sa.Integer(), nullable=False),
        sa.Column("last_value", sa.String(20), nullable=False),
        sa.Column("ignored", sa.Boolean(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "slot_key", name="uq_grade_source_slot"),
    )
    op.create_index("ix_grade_source_slots_child_id", "grade_source_slots", ["child_id"])


def downgrade():
    if op.get_bind().scalar(sa.text("SELECT count(*) FROM school_grades WHERE assessed_on IS NULL")):
        raise RuntimeError("Undated grades exist; preserve schema and use a forward correction.")
    op.drop_table("grade_source_slots")
    op.drop_table("grade_imports")
    with op.batch_alter_table("school_grades") as table:
        table.drop_constraint("ck_grade_known_period", type_="check")
        table.drop_column("school_year_start")
        table.drop_column("semester")
        table.alter_column("assessed_on", existing_type=sa.String(10), nullable=False)
