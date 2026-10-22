"""Encrypted withdrawal declarations and bounded public intake; no backfill."""

import sqlalchemy as sa
from alembic import op

revision = "0031"
down_revision = "0030"
branch_labels = depends_on = None


def upgrade():
    op.create_table("order_withdrawals",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("order_id", sa.String(32), sa.ForeignKey("bank_orders.id", ondelete="CASCADE"), nullable=False),
        sa.Column("owner_user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("received", sa.Integer(), nullable=False),
        sa.Column("effective_received", sa.Integer(), nullable=False),
        sa.Column("verified", sa.Boolean(), nullable=False),
        sa.Column("hold_payment", sa.Boolean(), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("encrypted_declaration", sa.Text(), nullable=False),
        sa.Column("request_digest", sa.String(64), nullable=False),
        sa.Column("idempotency", sa.String(100), nullable=False),
        sa.Column("mail_status", sa.String(16), nullable=False),
        sa.Column("public_declaration_id", sa.String(32)),
        sa.UniqueConstraint("order_id", name="uq_order_withdrawal_order"),
        sa.UniqueConstraint("idempotency", name="uq_order_withdrawal_request"),
        sa.UniqueConstraint("public_declaration_id", name="uq_order_withdrawal_public"))
    op.create_table("public_withdrawals",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("received", sa.Integer(), nullable=False),
        sa.Column("reference_digest", sa.String(64), nullable=False),
        sa.Column("email_digest", sa.String(64), nullable=False),
        sa.Column("encrypted_declaration", sa.Text(), nullable=False),
        sa.Column("request_digest", sa.String(64), nullable=False),
        sa.Column("idempotency", sa.String(80), nullable=False),
        sa.Column("mail_status", sa.String(16), nullable=False),
        sa.Column("status", sa.String(24), nullable=False),
        sa.Column("identity_verified", sa.Boolean(), nullable=False),
        sa.Column("reviewed", sa.Integer()),
        sa.Column("reviewed_by", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("linked_order_id", sa.String(32), sa.ForeignKey("bank_orders.id", ondelete="SET NULL")),
        sa.UniqueConstraint("idempotency", name="uq_public_withdrawal_request"))
    for column in ("received", "reference_digest", "email_digest", "linked_order_id"):
        op.create_index("ix_public_withdrawals_" + column, "public_withdrawals", [column])


def downgrade():
    for column in ("received", "reference_digest", "email_digest", "linked_order_id"):
        op.drop_index("ix_public_withdrawals_" + column, table_name="public_withdrawals")
    op.drop_table("public_withdrawals")
    op.drop_table("order_withdrawals")
