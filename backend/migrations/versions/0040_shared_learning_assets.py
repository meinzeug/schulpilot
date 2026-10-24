"""Atomic public build claims, private idempotency and exploration instances."""
import sqlalchemy as sa
from alembic import op

revision = "0040"
down_revision = "0039"
branch_labels = depends_on = None


def upgrade():
    op.create_table("learning_asset_builds",
        sa.Column("build_key", sa.String(64), primary_key=True),
        sa.Column("specification", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL")),
        sa.Column("reference_id", sa.String(100)),
        sa.Column("reference_version", sa.Integer()),
        sa.Column("reference_digest", sa.String(64)),
        sa.Column("technical_status", sa.String(24), nullable=False),
        sa.Column("factual_status", sa.String(32), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False))
    op.create_table("learning_asset_instances",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("build_key", sa.String(64), sa.ForeignKey("learning_asset_builds.build_key"), nullable=False),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("request_digest", sa.String(64), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "request_key", name="uq_learning_asset_request"))
    op.create_index("ix_learning_asset_instance_child_created", "learning_asset_instances", ["child_id", "created"])


def downgrade():
    op.drop_table("learning_asset_instances")
    op.drop_table("learning_asset_builds")
