"""Preserve the previously effective Codex medium effort without reactivation."""

import sqlalchemy as sa
from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = depends_on = None


def upgrade():
    # No revision, selected model, existing approval or historical job changes.
    op.add_column(
        "provider_config", sa.Column("reasoning_effort", sa.String(32), nullable=False, server_default="medium")
    )


def downgrade():
    with op.batch_alter_table("provider_config") as table:
        table.drop_column("reasoning_effort")
