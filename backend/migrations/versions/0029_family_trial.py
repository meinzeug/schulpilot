"""One immutable, email-verified free trial per new eligible family."""

import sqlalchemy as sa
from alembic import op

revision = "0029"
down_revision = "0028"
branch_labels = depends_on = None


def upgrade():
    op.add_column("store_configuration", sa.Column("ever_trial_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_table("family_trials",
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("owner_user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("starts", sa.Integer()), sa.Column("ends", sa.Integer()),
        sa.Column("child_limit", sa.Integer(), nullable=False),
        sa.Column("call_limit", sa.Integer(), nullable=False),
        sa.Column("budget_micros", sa.Integer(), nullable=False),
        sa.Column("version", sa.String(40), nullable=False),
        sa.CheckConstraint("child_limit >= 1 AND call_limit >= 0 AND budget_micros >= 0", name="ck_trial_limits"),
        sa.CheckConstraint("(starts IS NULL AND ends IS NULL) OR (starts IS NOT NULL AND ends IS NOT NULL AND ends = starts + 2592000)", name="ck_trial_period"))
    op.create_index("ix_family_trials_owner_user_id", "family_trials", ["owner_user_id"])


def downgrade():
    op.drop_index("ix_family_trials_owner_user_id", table_name="family_trials")
    op.drop_table("family_trials")
    with op.batch_alter_table("store_configuration") as batch:
        batch.drop_column("ever_trial_enabled")
