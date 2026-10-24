"""Private exam plans; planned work is never evidence of learning."""

from sqlalchemy import JSON, Boolean, Column, ForeignKey, Integer, String, UniqueConstraint

from .db import Base, now, uid


class Exam(Base):
    __tablename__ = "exams"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(160), nullable=False)
    purpose = Column(String(16), nullable=False)
    kind = Column(String(16), nullable=False)
    subject = Column(String(80), nullable=False)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"), index=True)
    exam_date = Column(String(10))
    timezone = Column(String(80), nullable=False)
    revision = Column(Integer, nullable=False, default=1)
    plan_revision = Column(Integer, nullable=False, default=1, server_default="1")
    minutes = Column(Integer, nullable=False)
    topics = Column(JSON, nullable=False, default=list)
    schedule = Column(JSON, nullable=False, default=dict)
    reminders = Column(Boolean, nullable=False, default=False)
    reminder_time = Column(String(5), nullable=False, default="16:00")
    archived = Column(Boolean, nullable=False, default=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
    create_key = Column(String(113), nullable=False, unique=True)
    request_digest = Column(String(64), nullable=False)


class ExamSession(Base):
    __tablename__ = "exam_sessions"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True)
    exam_revision = Column(Integer, nullable=False)
    date = Column(String(10), nullable=False)
    minutes = Column(Integer, nullable=False)
    topics = Column(JSON, nullable=False, default=list)
    __table_args__ = (UniqueConstraint("exam_id", "exam_revision", "date"),)


class ExamRound(Base):
    __tablename__ = "exam_rounds"
    id = Column(String(32), primary_key=True, default=uid)
    session_id = Column(ForeignKey("exam_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    ordinal = Column(Integer, nullable=False)
    topic_id = Column(String(48), nullable=False)
    topic_label = Column(String(160), nullable=False)
    question_count = Column(Integer, nullable=False)
    source_revisions = Column(JSON, nullable=False)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), index=True)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="SET NULL"), index=True)
    __table_args__ = (UniqueConstraint("session_id", "ordinal"),)
