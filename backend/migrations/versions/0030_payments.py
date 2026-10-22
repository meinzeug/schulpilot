"""Immutable PayPal attempts and verified event/refund metadata."""

import sqlalchemy as sa
from alembic import op

revision = "0030"
down_revision = "0029"
branch_labels = depends_on = None


def upgrade():
    op.add_column(
        "bank_orders", sa.Column("payment_method", sa.String(24), nullable=False, server_default="bank_transfer")
    )
    op.add_column("bank_orders", sa.Column("currency", sa.String(3), nullable=False, server_default="EUR"))
    op.add_column("bank_orders", sa.Column("request_digest", sa.String(64)))
    op.create_table(
        "payment_configuration",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("encrypted_config", sa.Text(), nullable=False),
    )
    op.create_table(
        "payment_configuration_revisions",
        sa.Column("revision", sa.Integer(), primary_key=True),
        sa.Column("encrypted_config", sa.Text(), nullable=False),
    )
    op.create_table(
        "payment_attempts",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "order_id", sa.String(32), sa.ForeignKey("bank_orders.id", ondelete="CASCADE"), nullable=False, unique=True
        ),
        sa.Column("environment", sa.String(8), nullable=False),
        sa.Column("merchant_id", sa.String(64), nullable=False),
        sa.Column("config_revision", sa.Integer(), nullable=False),
        sa.Column("method", sa.String(24), nullable=False),
        sa.Column("amount_cents", sa.Integer(), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("provider_order_id", sa.String(64)),
        sa.Column("capture_id", sa.String(64)),
        sa.Column("capture_started", sa.Integer()),
        sa.Column("create_request_id", sa.String(36), nullable=False, unique=True),
        sa.Column("capture_request_id", sa.String(36), nullable=False, unique=True),
        sa.Column("refunded_cents", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.Column("error_code", sa.String(40)),
        sa.UniqueConstraint("environment", "merchant_id", "provider_order_id", name="uq_payment_provider_order"),
        sa.UniqueConstraint("environment", "merchant_id", "capture_id", name="uq_payment_capture"),
        sa.CheckConstraint(
            "amount_cents > 0 AND refunded_cents >= 0 AND refunded_cents <= amount_cents", name="ck_payment_amounts"
        ),
        sa.CheckConstraint("currency = 'EUR'", name="ck_payment_currency"),
        sa.CheckConstraint("environment IN ('sandbox', 'live')", name="ck_payment_environment"),
    )
    op.create_table(
        "payment_events",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("environment", sa.String(8), nullable=False),
        sa.Column("merchant_id", sa.String(64), nullable=False),
        sa.Column("event_id", sa.String(160), nullable=False),
        sa.Column("event_type", sa.String(80), nullable=False),
        sa.Column("body_sha256", sa.String(64), nullable=False),
        sa.Column("payment_id", sa.String(32), sa.ForeignKey("payment_attempts.id", ondelete="SET NULL")),
        sa.Column("result", sa.String(32), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("environment", "merchant_id", "event_id", name="uq_payment_webhook_event"),
    )
    op.create_table(
        "payment_refunds",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "payment_id", sa.String(32), sa.ForeignKey("payment_attempts.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("provider_refund_id", sa.String(64), nullable=False),
        sa.Column("amount_cents", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("payment_id", "provider_refund_id", name="uq_payment_refund"),
        sa.CheckConstraint("amount_cents > 0", name="ck_payment_refund_amount"),
    )


def downgrade():
    op.drop_table("payment_refunds")
    op.drop_table("payment_events")
    op.drop_table("payment_attempts")
    op.drop_table("payment_configuration_revisions")
    op.drop_table("payment_configuration")
    with op.batch_alter_table("bank_orders") as batch:
        batch.drop_column("request_digest")
        batch.drop_column("currency")
        batch.drop_column("payment_method")
