"""Immutable literal source history, bounded provenance and stale dependencies."""

import sqlalchemy as sa
from alembic import op

revision = "0035"
down_revision = "0034"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "source_revisions",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("cause", sa.String(24), nullable=False),
        sa.Column("snapshot", sa.JSON(), nullable=False),
        sa.Column("receipt", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("material_id", "revision", "digest", name="uq_source_snapshot"),
        sa.UniqueConstraint("material_id", "sequence", name="uq_source_sequence"),
    )
    for field in ("material_id", "child_id"):
        op.create_index("ix_source_revisions_" + field, "source_revisions", [field])
    op.create_table(
        "source_invalidations",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source_revision", sa.Integer(), nullable=False),
        sa.Column("current_revision", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(64), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("unit_id", "material_id", "current_revision", name="uq_source_invalidation"),
    )
    for field in ("material_id", "child_id", "unit_id"):
        op.create_index("ix_source_invalidations_" + field, "source_invalidations", [field])

    op.create_table(
        "source_image_receipts",
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("image_digest", sa.String(64), nullable=False),
        sa.Column("geometry", sa.JSON(), nullable=False),
        sa.Column("normalization_version", sa.String(64), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_table(
        "source_evaluation_budgets",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("limit_micros", sa.Integer(), nullable=False),
    )
    op.create_table(
        "source_evaluation_grants",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("work_id", sa.String(64), sa.ForeignKey("source_evaluation_budgets.id"), nullable=False),
        sa.Column("operator_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE"), nullable=False),
        sa.Column("sources", sa.JSON(), nullable=False),
        sa.Column("config_revision", sa.Integer(), nullable=False),
        sa.Column("policy_digest", sa.String(64), nullable=False),
        sa.Column("expires", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_table(
        "source_evaluation_cases",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("work_id", sa.String(64), sa.ForeignKey("source_evaluation_budgets.id"), nullable=False),
        sa.Column("grant_id", sa.String(32), sa.ForeignKey("source_evaluation_grants.id", ondelete="SET NULL")),
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="SET NULL")),
        sa.Column("job_id", sa.String(32), sa.ForeignKey("jobs.id", ondelete="SET NULL"), unique=True),
        sa.Column("tier", sa.String(8), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("reserved_micros", sa.Integer(), nullable=False),
        sa.Column("charged_micros", sa.Integer()),
        sa.Column("created", sa.Integer(), nullable=False),
    )


def downgrade():
    for table in (
        "source_evaluation_cases",
        "source_evaluation_grants",
        "source_evaluation_budgets",
        "source_image_receipts",
    ):
        op.drop_table(table)
    op.drop_table("source_invalidations")
    op.drop_table("source_revisions")
