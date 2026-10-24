"""Own-account private profile image revisions; no existing records rewritten."""

import sqlalchemy as sa
from alembic import op

revision = "0032"
down_revision = "0031"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "user_avatars",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.String(32), nullable=False),
        sa.Column("image_digest", sa.String(64)),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.Column("request_key", sa.String(100), nullable=False),
        sa.Column("request_digest", sa.String(64), nullable=False),
    )


def downgrade():
    op.drop_table("user_avatars")
