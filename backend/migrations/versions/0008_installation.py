"""Password-only admin login and one-time, operator-owned installation."""

import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "installation",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("completed", sa.Boolean(), nullable=False),
        sa.Column("bootstrap_digest", sa.String(64)),
        sa.Column("bootstrap_expires", sa.Integer()),
        sa.Column("encrypted_settings", sa.Text()),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("completed_at", sa.Integer()),
    )
    op.create_table(
        "operator_jobs",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("actor", sa.String(32), nullable=False),
        sa.Column("config_revision", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("report", sa.JSON(), nullable=False),
        sa.Column("error", sa.String(500)),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("started", sa.Integer()),
        sa.Column("finished", sa.Integer()),
    )
    # Existing families/accounts must never reopen public first-run setup.
    op.execute(
        "INSERT INTO installation(id,completed,revision) SELECT 1, EXISTS(SELECT 1 FROM users) OR EXISTS(SELECT 1 FROM families), 1"
    )
    op.execute("UPDATE sessions SET revoked=true WHERE user_id IN (SELECT id FROM users WHERE role='admin')")
    op.drop_column("users", "totp_secret")
    op.drop_column("users", "totp_last_step")


def downgrade():
    op.drop_table("operator_jobs")
    op.add_column("users", sa.Column("totp_secret", sa.Text()))
    op.add_column("users", sa.Column("totp_last_step", sa.Integer(), server_default="0", nullable=False))
    op.drop_table("installation")
