"""Versioned additions, upload replay protection and guided introductions.

Revision ID: 0005
Revises: 0004
"""

import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = depends_on = None


def upgrade():
    op.add_column("assignments", sa.Column("scheduled_for", sa.String(10)))
    op.create_table(
        "erasure_requests",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("scope", sa.String(16), nullable=False),
        sa.Column("target", sa.String(32), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("published", sa.Boolean(), server_default=sa.false(), nullable=False),
    )
    op.create_table(
        "service_state",
        sa.Column("name", sa.String(40), primary_key=True),
        sa.Column("updated", sa.Integer(), nullable=False),
    )
    op.add_column(
        "provider_config", sa.Column("production_block_reason", sa.String(500), server_default="", nullable=False)
    )
    op.add_column("school_days", sa.Column("package_version", sa.Integer(), server_default="0", nullable=False))
    with op.batch_alter_table("materials") as batch:
        batch.add_column(sa.Column("upload_key", sa.String(80)))
        batch.add_column(sa.Column("image_digest", sa.String(64)))
        batch.add_column(sa.Column("quality_warnings", sa.JSON(), server_default="[]", nullable=False))
        batch.add_column(sa.Column("legibility", sa.String(16), server_default="unknown", nullable=False))
        batch.create_unique_constraint("uq_material_upload_key", ["child_id", "upload_key"])
    op.add_column("learning_units", sa.Column("package_version", sa.Integer()))
    op.add_column(
        "learning_units", sa.Column("introduction_seen", sa.Boolean(), server_default=sa.false(), nullable=False)
    )
    op.execute("UPDATE school_days SET package_version = 1 WHERE stage = 'ready'")
    op.execute("UPDATE learning_units SET package_version = 1 WHERE school_day_id IS NOT NULL")
    # Existing started units keep their current position; no interrupted lessons.
    op.execute("UPDATE learning_units SET introduction_seen = true WHERE status != 'not_started'")


def downgrade():
    op.drop_column("assignments", "scheduled_for")
    op.drop_table("service_state")
    op.drop_table("erasure_requests")
    op.drop_column("provider_config", "production_block_reason")
    op.drop_column("learning_units", "introduction_seen")
    op.drop_column("learning_units", "package_version")
    with op.batch_alter_table("materials") as batch:
        batch.drop_constraint("uq_material_upload_key", type_="unique")
        batch.drop_column("quality_warnings")
        batch.drop_column("legibility")
        batch.drop_column("image_digest")
        batch.drop_column("upload_key")
    op.drop_column("school_days", "package_version")
