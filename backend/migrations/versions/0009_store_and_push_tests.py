"""Manual bank-transfer orders and narrowly scoped synthetic push tests."""

import sqlalchemy as sa
from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = depends_on = None


def upgrade():
    op.add_column("families", sa.Column("commerce_required", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.create_table(
        "store_configuration",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("encrypted_config", sa.Text(), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("ever_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_table(
        "bank_orders",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="SET NULL")),
        sa.Column("buyer_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("idempotency", sa.String(100), unique=True, nullable=False),
        sa.Column("payment_reference", sa.String(24), unique=True, nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("pending_slot", sa.String(32), unique=True),
        sa.Column("amount_cents", sa.Integer(), nullable=False),
        sa.Column("offer", sa.JSON(), nullable=False),
        sa.Column("seller", sa.JSON(), nullable=False),
        sa.Column("bank", sa.JSON(), nullable=False),
        sa.Column("terms", sa.Text(), nullable=False),
        sa.Column("terms_version", sa.String(32), nullable=False),
        sa.Column("early_start", sa.Boolean(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("starts", sa.Integer()),
        sa.Column("ends", sa.Integer()),
        sa.Column("checked_at", sa.Integer()),
        sa.Column("checked_by", sa.String(32)),
        sa.Column("booking_digest", sa.String(64), unique=True),
        sa.Column("booking_date", sa.String(10)),
        sa.Column("revoked_at", sa.Integer()),
        sa.Column("refund_digest", sa.String(64), unique=True),
        sa.Column("refund_date", sa.String(10)),
        sa.Column("mail_status", sa.String(16), nullable=False),
    )
    op.create_index("ix_bank_orders_family_id", "bank_orders", ["family_id"])
    op.create_table(
        "push_test_grants",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("expires", sa.Integer(), nullable=False),
    )


def downgrade():
    op.drop_table("push_test_grants")
    op.drop_table("bank_orders")
    op.drop_table("store_configuration")
    op.drop_column("families", "commerce_required")
