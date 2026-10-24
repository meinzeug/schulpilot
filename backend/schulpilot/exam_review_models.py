"""Source-bound written-work review, never a school grade or an Attempt."""

from sqlalchemy import JSON, Column, ForeignKey, Integer, String, Text, UniqueConstraint

from .db import Base, now, uid


class ExamReviewPage(Base):
    __tablename__ = "exam_review_pages"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), nullable=False, unique=True)
    position = Column(Integer, nullable=False)
    upload_revision = Column(Integer, nullable=False)
    __table_args__ = (UniqueConstraint("exam_id", "position"),)


class ExamReview(Base):
    __tablename__ = "exam_reviews"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, unique=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    revision = Column(Integer, nullable=False, default=1)
    status = Column(String(16), nullable=False, default="queued")
    context_revision = Column(String(64), nullable=False)
    source_revisions = Column(JSON, nullable=False, default=list)
    report = Column(JSON, nullable=False, default=dict)
    error = Column(String(500))
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), index=True)
    user_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    updated = Column(Integer, nullable=False, default=lambda: int(now()))


class ExamReviewTurn(Base):
    __tablename__ = "exam_review_turns"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True)
    review_id = Column(ForeignKey("exam_reviews.id", ondelete="CASCADE"), nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="SET NULL"))
    task_id = Column(String(48), nullable=False)
    context_revision = Column(String(64), nullable=False)
    source_revisions = Column(JSON, nullable=False, default=list)
    action = Column(String(16), nullable=False)
    draft = Column(Text, nullable=False, default="")
    status = Column(String(16), nullable=False, default="queued")
    reply = Column(JSON)
    error = Column(String(500))
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), index=True)
    created = Column(Integer, nullable=False, default=lambda: int(now()))


class ExamReviewDraft(Base):
    __tablename__ = "exam_review_drafts"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    session_id = Column(ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    task_id = Column(String(48), nullable=False)
    context_revision = Column(String(64), nullable=False)
    text = Column(Text, nullable=False)
    revision = Column(Integer, nullable=False, default=1)
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("user_id", "session_id", "exam_id", "task_id"),)


class ExamReviewPractice(Base):
    __tablename__ = "exam_review_practices"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, index=True)
    review_id = Column(ForeignKey("exam_reviews.id", ondelete="CASCADE"), nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    task_id = Column(String(48), nullable=False)
    context_revision = Column(String(64), nullable=False)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), unique=True)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False, unique=True)
    created = Column(Integer, nullable=False, default=lambda: int(now()))


class ExamScanBatch(Base):
    """Explicit persistent OCR intent, separate from school-day preparation."""

    __tablename__ = "exam_scan_batches"
    id = Column(String(32), primary_key=True, default=uid)
    exam_id = Column(ForeignKey("exams.id", ondelete="CASCADE"), nullable=False, unique=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    state = Column(JSON, nullable=False, default=dict)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
