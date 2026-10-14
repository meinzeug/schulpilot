"""Bounded answer review, follow-up rounds and source-bound learning paths."""

import sqlalchemy as sa
from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = depends_on = None


def upgrade():
    if op.get_bind().dialect.name == "sqlite":
        # A batch table-copy would cascade-delete existing attempts with
        # foreign_keys=ON. Add nullable inline references without a table copy.
        op.execute(
            "ALTER TABLE learning_units ADD COLUMN learning_root_id VARCHAR(32) REFERENCES learning_units(id) ON DELETE SET NULL"
        )
        op.execute(
            "ALTER TABLE learning_units ADD COLUMN followup_of VARCHAR(32) REFERENCES learning_units(id) ON DELETE SET NULL"
        )
    else:
        op.add_column("learning_units", sa.Column("learning_root_id", sa.String(32)))
        op.add_column("learning_units", sa.Column("followup_of", sa.String(32)))
        op.create_foreign_key(
            "fk_unit_learning_root",
            "learning_units",
            "learning_units",
            ["learning_root_id"],
            ["id"],
            ondelete="SET NULL",
        )
        op.create_foreign_key(
            "fk_unit_followup", "learning_units", "learning_units", ["followup_of"], ["id"], ondelete="SET NULL"
        )
    op.add_column("learning_units", sa.Column("round_kind", sa.String(20), server_default="learning", nullable=False))
    op.add_column("learning_units", sa.Column("not_before", sa.String(10)))
    op.add_column("learning_units", sa.Column("goal_revision", sa.Integer()))
    op.create_index("ix_learning_units_learning_root_id", "learning_units", ["learning_root_id"])
    op.create_table(
        "unit_coaching",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL")),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("decision", sa.String(24), nullable=False),
        sa.Column("reason", sa.String(500), nullable=False),
        sa.Column("report", sa.JSON(), nullable=False),
        sa.Column("next_unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="SET NULL")),
        sa.Column("next_review", sa.String(10)),
        sa.Column("request_count", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(20), nullable=False),
        sa.Column("model", sa.String(160), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )


def downgrade():
    op.drop_table("unit_coaching")
    op.drop_index("ix_learning_units_learning_root_id", table_name="learning_units")
    if op.get_bind().dialect.name != "sqlite":
        op.drop_constraint("fk_unit_followup", "learning_units", type_="foreignkey")
        op.drop_constraint("fk_unit_learning_root", "learning_units", type_="foreignkey")
    for name in ("round_kind", "not_before", "goal_revision", "followup_of", "learning_root_id"):
        op.drop_column("learning_units", name)
