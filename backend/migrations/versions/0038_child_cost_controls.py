"""Explicit child day/month cost policy and immutable conversion balances."""
import sqlalchemy as sa
from alembic import op

revision = "0038"
down_revision = "0037"
branch_labels = depends_on = None


def upgrade():
    op.create_table("child_cost_controls",
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("timezone", sa.String(64), nullable=False),
        sa.Column("daily_limit_eur_micros", sa.BigInteger()),
        sa.Column("monthly_limit_eur_micros", sa.BigInteger()),
        sa.Column("updated", sa.Integer(), nullable=False))
    op.create_table("child_cost_control_changes",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("actor_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("policy", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "request_key", name="uq_child_cost_control_request"))
    op.create_table("usage_cost_balances",
        sa.Column("usage_id", sa.String(32), sa.ForeignKey("usage.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("provider_eur_micros", sa.BigInteger()),
        sa.Column("fee_known_eur_micros", sa.BigInteger()),
        sa.Column("fee_reserved_eur_micros", sa.BigInteger(), nullable=False),
        sa.Column("held_eur_micros", sa.BigInteger(), nullable=False),
        sa.Column("accounted_eur_micros", sa.BigInteger(), nullable=False),
        sa.Column("fee_state", sa.String(32), nullable=False),
        sa.Column("fx_snapshot", sa.JSON(), nullable=False),
        sa.Column("fee_basis_usd_micros", sa.BigInteger()))
    op.create_index("ix_cost_balances_child_created", "usage_cost_balances", ["child_id", "created"])
    op.create_index("ix_usage_child_created", "usage", ["child_id", "created"])


def downgrade():
    op.drop_index("ix_usage_child_created", table_name="usage")
    op.drop_table("usage_cost_balances")
    op.drop_table("child_cost_control_changes")
    op.drop_table("child_cost_controls")
