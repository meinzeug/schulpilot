"""Explicit free routing; preserve the stricter policy on existing installs."""

import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = depends_on = None


def upgrade():
    op.add_column(
        "provider_config", sa.Column("openrouter_free_only", sa.Boolean(), server_default=sa.true(), nullable=False)
    )
    op.add_column(
        "provider_config", sa.Column("openrouter_require_zdr", sa.Boolean(), server_default=sa.true(), nullable=False)
    )


def downgrade():
    op.drop_column("provider_config", "openrouter_require_zdr")
    op.drop_column("provider_config", "openrouter_free_only")
