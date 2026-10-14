"""Optional parent Google identities and short-lived, one-use login flows."""

import sqlalchemy as sa
from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "google_identities",
        sa.Column("subject", sa.String(255), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_table(
        "google_flows",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("request_digest", sa.String(64), unique=True, nullable=False),
        sa.Column("state_digest", sa.String(64), unique=True),
        sa.Column("browser_digest", sa.String(64)),
        sa.Column("nonce_digest", sa.String(64)),
        sa.Column("encrypted_verifier", sa.Text()),
        sa.Column("client_challenge", sa.String(43)),
        sa.Column("ticket_digest", sa.String(64)),
        sa.Column("platform", sa.String(8), nullable=False),
        sa.Column("intent", sa.String(8), nullable=False),
        sa.Column("previous_session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="CASCADE")),
        sa.Column("phase", sa.String(16), nullable=False),
        sa.Column("subject", sa.String(255)),
        sa.Column("email", sa.String(254)),
        sa.Column("failure", sa.String(32)),
        sa.Column("email_authoritative", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("expires", sa.Integer(), nullable=False),
    )
    op.create_index("ix_google_flows_expires", "google_flows", ["expires"])


def downgrade():
    op.drop_table("google_flows")
    op.drop_table("google_identities")
