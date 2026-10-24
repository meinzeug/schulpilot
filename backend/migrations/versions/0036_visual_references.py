"""Versioned own visual recipes and private source-bound explanation snapshots."""
import sqlalchemy as sa
from alembic import op

revision = "0036"
down_revision = "0035"
branch_labels = depends_on = None


def upgrade():
    op.create_table("visual_reference_versions",
        sa.Column("id", sa.String(100), primary_key=True),
        sa.Column("version", sa.Integer(), primary_key=True),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("recipe", sa.JSON(), nullable=False))
    op.create_table("unit_visual_snapshots",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("source_signature", sa.String(64), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("reason", sa.String(48)),
        sa.Column("steps", sa.JSON(), nullable=False),
        sa.Column("question_steps", sa.JSON(), nullable=False),
        sa.Column("receipts", sa.JSON(), nullable=False),
        sa.Column("source_bindings", sa.JSON(), nullable=False),
        sa.Column("notice", sa.Text(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False))

    op.create_table("unit_visual_positions",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("source_signature", sa.String(64), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("position", sa.JSON(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False))


def downgrade():
    op.drop_table("unit_visual_positions")
    op.drop_table("unit_visual_snapshots")
    op.drop_table("visual_reference_versions")
