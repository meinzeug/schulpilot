"""Personal parent checks; snapshots never establish learning evidence."""

from sqlalchemy import JSON, Boolean, Column, ForeignKey, Index, Integer, String, UniqueConstraint

from .db import Base, now, uid


class ParentGoalReminder(Base):
    __tablename__ = "parent_goal_reminders"
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False)
    enabled = Column(Boolean, nullable=False, default=False)
    weekdays = Column(JSON, nullable=False)
    time = Column(String(5), nullable=False)
    timezone = Column(String(64), nullable=False)
    daily_minimum = Column(Boolean, nullable=False)
    exam_sessions = Column(Boolean, nullable=False)
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
    next_check = Column(Integer, nullable=False, default=0)
    __table_args__ = (Index("ix_parent_goal_reminders_due", "enabled", "next_check"),)


class ParentGoalReminderChange(Base):
    __tablename__ = "parent_goal_reminder_changes"
    id = Column(String(32), primary_key=True, default=uid)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    request_key = Column(String(80), nullable=False)
    digest = Column(String(64), nullable=False)
    projection = Column(JSON, nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("user_id", "child_id", "request_key", name="uq_parent_reminder_request"),)


class ParentGoalReminderEvent(Base):
    __tablename__ = "parent_goal_reminder_events"
    id = Column(String(32), primary_key=True, default=uid)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    rule_revision = Column(Integer, nullable=False)
    date = Column(String(10), nullable=False)
    scheduled = Column(Integer, nullable=False)
    created = Column(Integer, nullable=False)
    daily_remaining_seconds = Column(Integer, nullable=False)
    exam_sessions = Column(JSON, nullable=False)
    __table_args__ = (
        UniqueConstraint("user_id", "child_id", "date", name="uq_parent_reminder_day"),
        Index("ix_parent_reminder_events_owner_created", "user_id", "created"),
    )
