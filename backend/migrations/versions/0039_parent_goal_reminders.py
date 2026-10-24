"""Personal parent schedules and minimal, deduplicated check snapshots."""
import sqlalchemy as sa
from alembic import op

revision = "0039"
down_revision = "0038"
branch_labels = depends_on = None


def upgrade():
    op.create_table("parent_goal_reminders",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("weekdays", sa.JSON(), nullable=False),
        sa.Column("time", sa.String(5), nullable=False),
        sa.Column("timezone", sa.String(64), nullable=False),
        sa.Column("daily_minimum", sa.Boolean(), nullable=False),
        sa.Column("exam_sessions", sa.Boolean(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.Column("next_check", sa.Integer(), nullable=False))
    op.create_index("ix_parent_goal_reminders_due", "parent_goal_reminders", ["enabled", "next_check"])
    op.create_table("parent_goal_reminder_changes",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("projection", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "child_id", "request_key", name="uq_parent_reminder_request"))
    op.create_table("parent_goal_reminder_events",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("rule_revision", sa.Integer(), nullable=False),
        sa.Column("date", sa.String(10), nullable=False),
        sa.Column("scheduled", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("daily_remaining_seconds", sa.Integer(), nullable=False),
        sa.Column("exam_sessions", sa.JSON(), nullable=False),
        sa.UniqueConstraint("user_id", "child_id", "date", name="uq_parent_reminder_day"))
    op.create_index("ix_parent_reminder_events_owner_created", "parent_goal_reminder_events", ["user_id", "created"])


def downgrade():
    op.drop_table("parent_goal_reminder_events")
    op.drop_table("parent_goal_reminder_changes")
    op.drop_table("parent_goal_reminders")
