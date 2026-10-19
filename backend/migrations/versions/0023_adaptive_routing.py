"""Bound model routes, child budgets and separate credit fees; preserve old usage."""

import sqlalchemy as sa
from alembic import op

revision = "0023"
down_revision = "0022"
branch_labels = depends_on = None


def upgrade():
    op.add_column("provider_config", sa.Column("routing_policy", sa.JSON(), server_default="{}", nullable=False))
    for column in [
        sa.Column("route_snapshot", sa.JSON(), server_default="{}", nullable=False),
        sa.Column("telemetry", sa.JSON(), server_default="{}", nullable=False),
        sa.Column("cost_source", sa.String(24), server_default="unknown", nullable=False),
        sa.Column("settlement_version", sa.Integer(), server_default="0", nullable=False),
        sa.Column("estimated_micros", sa.Integer()),
        sa.Column("child_budget_id", sa.String(80)),
        sa.Column("reserved_eur_micros", sa.Integer()),
        sa.Column("charged_eur_micros", sa.Integer()),
        sa.Column("allocated_fee_micros", sa.Integer()),
        sa.Column("reservation_key", sa.String(64)),
    ]:
        op.add_column("usage", column)
    # Old settled rows must not be settled a second time after an upgrade.
    op.execute("UPDATE usage SET settlement_version = 1 WHERE status <> 'reserved'")
    op.create_index("uq_usage_reservation", "usage", ["reservation_key"], unique=True)
    op.create_table("child_cost_buckets",
        sa.Column("id", sa.String(80), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("period", sa.String(7), nullable=False),
        sa.Column("calls", sa.Integer(), nullable=False),
        sa.Column("encumbered_eur_micros", sa.Integer(), nullable=False),
        sa.Column("known_eur_micros", sa.Integer(), nullable=False),
        sa.Column("unknown_calls", sa.Integer(), nullable=False))
    op.create_index("ix_child_cost_buckets_child_id", "child_cost_buckets", ["child_id"])
    op.create_table("credit_purchases",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("credits_micros", sa.Integer(), nullable=False),
        sa.Column("fee_micros", sa.Integer(), nullable=False),
        sa.Column("consumed_micros", sa.Integer(), nullable=False),
        sa.Column("allocated_fee_micros", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False))
    op.create_table("learning_memory",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("plan_revision", sa.Integer(), nullable=False),
        sa.Column("source_signature", sa.String(64), nullable=False),
        sa.Column("working", sa.JSON(), nullable=False),
        sa.Column("decision", sa.JSON(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False))
    op.create_index("ix_learning_memory_child_id", "learning_memory", ["child_id"])
    op.create_table("learning_controller_events",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("event_key", sa.String(100), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("evidence", sa.JSON(), nullable=False),
        sa.Column("decision", sa.JSON(), nullable=False),
        sa.Column("strategy_version", sa.String(32), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("unit_id", "event_key", name="uq_controller_event"))
    op.create_index("ix_learning_controller_events_child_id", "learning_controller_events", ["child_id"])
    op.create_index("ix_learning_controller_events_unit_id", "learning_controller_events", ["unit_id"])


def downgrade():
    op.drop_table("learning_controller_events")
    op.drop_table("learning_memory")
    op.drop_table("credit_purchases")
    op.drop_table("child_cost_buckets")
    op.drop_index("uq_usage_reservation", table_name="usage")
    for name in ["reservation_key", "route_snapshot", "telemetry", "cost_source", "settlement_version", "estimated_micros",
                 "child_budget_id", "reserved_eur_micros", "charged_eur_micros", "allocated_fee_micros"]:
        op.drop_column("usage", name)
    op.drop_column("provider_config", "routing_policy")
