"""Persist multi-page after-school wizards and package source links.

Revision ID: 0004
Revises: 0003
"""

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "school_days",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("school_date", sa.String(10), nullable=False),
        sa.Column("stage", sa.String(16), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "school_date"),
    )
    op.create_index("ix_school_days_child_id", "school_days", ["child_id"])
    # Batch mode also supports the isolated SQLite development database.
    with op.batch_alter_table("materials") as batch:
        batch.add_column(sa.Column("school_day_id", sa.String(32)))
        batch.add_column(sa.Column("page_number", sa.Integer()))
        batch.create_foreign_key(
            "fk_material_school_day", "school_days", ["school_day_id"], ["id"], ondelete="SET NULL"
        )
        batch.create_index("ix_materials_school_day_id", ["school_day_id"])
    with op.batch_alter_table("learning_units") as batch:
        batch.add_column(sa.Column("school_day_id", sa.String(32)))
        batch.add_column(sa.Column("estimated_minutes", sa.Integer()))
        batch.create_foreign_key("fk_unit_school_day", "school_days", ["school_day_id"], ["id"], ondelete="SET NULL")
        batch.create_index("ix_learning_units_school_day_id", ["school_day_id"])
    op.create_table(
        "unit_sources",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
    )


def downgrade():
    op.drop_table("unit_sources")
    with op.batch_alter_table("learning_units") as batch:
        batch.drop_constraint("fk_unit_school_day", type_="foreignkey")
        batch.drop_index("ix_learning_units_school_day_id")
        batch.drop_column("estimated_minutes")
        batch.drop_column("school_day_id")
    with op.batch_alter_table("materials") as batch:
        batch.drop_constraint("fk_material_school_day", type_="foreignkey")
        batch.drop_index("ix_materials_school_day_id")
        batch.drop_column("page_number")
        batch.drop_column("school_day_id")
    op.drop_index("ix_school_days_child_id", "school_days")
    op.drop_table("school_days")
