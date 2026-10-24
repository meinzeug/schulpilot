"""Public sourced topics and an explicit private school-profile selection."""

from sqlalchemy import JSON, Column, ForeignKey, Index, Integer, String, UniqueConstraint

from .db import Base, now, uid


class CurriculumDocument(Base):
    __tablename__ = "curriculum_documents"
    id = Column(String(120), primary_key=True)
    state_code = Column(String(5), nullable=False, index=True)
    digest = Column(String(64), nullable=False)
    data = Column(JSON, nullable=False)


class CurriculumTopic(Base):
    __tablename__ = "curriculum_topics"
    id = Column(String(140), primary_key=True)
    document_id = Column(ForeignKey("curriculum_documents.id", ondelete="CASCADE"), nullable=False, index=True)
    subject_id = Column(ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True)
    state_code = Column(String(5), nullable=False)
    school_form_id = Column(String(120), nullable=False)
    title = Column(String(200), nullable=False)
    digest = Column(String(64), nullable=False)
    data = Column(JSON, nullable=False)
    __table_args__ = (Index("ix_curriculum_topics_scope", "state_code", "school_form_id", "subject_id", "id"),)


class ChildCurriculumProfile(Base):
    __tablename__ = "child_curriculum_profiles"
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), primary_key=True)
    revision = Column(Integer, nullable=False)
    state_code = Column(String(5), nullable=False)
    school_form_id = Column(String(120))
    legacy_binding = Column(JSON, nullable=False)
    updated = Column(Integer, nullable=False, default=lambda: int(now()))


class ChildCurriculumChange(Base):
    __tablename__ = "child_curriculum_changes"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    actor_id = Column(ForeignKey("users.id", ondelete="SET NULL"))
    request_key = Column(String(80), nullable=False)
    digest = Column(String(64), nullable=False)
    revision = Column(Integer, nullable=False)
    data = Column(JSON, nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("child_id", "request_key", name="uq_curriculum_profile_request"),)
