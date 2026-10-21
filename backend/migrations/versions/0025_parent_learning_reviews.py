"""Parent evidence reviews and explicit topic provenance."""
import sqlalchemy as sa
from alembic import op

revision = "0025"
down_revision = "0024"
branch_labels = depends_on = None


def upgrade():
    op.add_column("children", sa.Column("parent_review_settings", sa.JSON(), server_default="{}", nullable=False))
    op.add_column("assignments", sa.Column("request_digest", sa.String(64)))
    if op.get_bind().dialect.name == "sqlite":
        # A batch copy would SET NULL existing LearningUnit.assignment_id
        # references when dropping the old assignments table. SQLite supports
        # an inline nullable reference without copying or touching old rows.
        op.execute(
            "ALTER TABLE assignments ADD COLUMN source_unit_id VARCHAR(32) REFERENCES learning_units(id) ON DELETE SET NULL"
        )
    else:
        op.add_column("assignments", sa.Column("source_unit_id", sa.String(32)))
        op.create_foreign_key("fk_assignment_source_unit", "assignments", "learning_units", ["source_unit_id"], ["id"], ondelete="SET NULL")
    op.create_table("parent_learning_reviews",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE"), nullable=False),
        sa.Column("requested_by", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL")),
        sa.Column("signature", sa.String(64), nullable=False),
        sa.Column("observations", sa.JSON(), nullable=False),
        sa.Column("report", sa.JSON()), sa.Column("status", sa.String(20), nullable=False),
        sa.Column("error", sa.String(500)), sa.Column("created", sa.Integer(), nullable=False), sa.Column("finished", sa.Integer()))
    op.create_index("ix_parent_learning_reviews_child_id", "parent_learning_reviews", ["child_id"])


def downgrade():
    op.drop_table("parent_learning_reviews")
    if op.get_bind().dialect.name != "sqlite":
        op.drop_constraint("fk_assignment_source_unit", "assignments", type_="foreignkey")
    op.drop_column("assignments", "source_unit_id")
    op.drop_column("assignments", "request_digest")
    op.drop_column("children", "parent_review_settings")
