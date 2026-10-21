"""Session-bound family calls and explicit device call opt-in."""
import sqlalchemy as sa
from alembic import op

revision = "0026"
down_revision = "0025"
branch_labels = depends_on = None


def upgrade():
    op.add_column("push_devices", sa.Column("family_calls", sa.Boolean(), server_default=sa.false(), nullable=False))
    op.add_column("push_devices", sa.Column("call_binding", sa.String(64)))
    op.create_table("family_calls",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caller_session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("parent_session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="SET NULL")),
        sa.Column("parent_user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("active_slot", sa.String(32), unique=True),
        sa.Column("parent_active_slot", sa.String(32), unique=True),
        sa.Column("idempotency", sa.String(64), unique=True, nullable=False),
        sa.Column("instance", sa.String(32), nullable=False),
        sa.Column("context_kind", sa.String(16), nullable=False),
        sa.Column("context_id", sa.String(32)),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("reason", sa.String(32)),
        sa.Column("declined_users", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("ring_expires", sa.Integer(), nullable=False),
        sa.Column("expires", sa.Integer(), nullable=False),
        sa.Column("caller_seen", sa.Integer(), nullable=False),
        sa.Column("parent_seen", sa.Integer()),
        sa.Column("accepted_at", sa.Integer()),
        sa.Column("ended_at", sa.Integer()))
    op.create_index("ix_family_calls_family_id", "family_calls", ["family_id"])
    op.create_index("ix_family_calls_child_id", "family_calls", ["child_id"])


def downgrade():
    op.drop_table("family_calls")
    op.drop_column("push_devices", "call_binding")
    op.drop_column("push_devices", "family_calls")
