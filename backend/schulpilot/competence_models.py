"""Versioned public teaching identities and private bindings, never copied answers."""

from sqlalchemy import JSON, Column, ForeignKey, ForeignKeyConstraint, Index, Integer, String

from .db import Base


class CompetenceDefinition(Base):
    __tablename__ = "competence_definitions"
    id = Column(String(120), primary_key=True)
    version = Column(String(40), primary_key=True)
    subject_key = Column(String(80), nullable=False)
    label = Column(String(180), nullable=False)
    data = Column(JSON, nullable=False)


class CompetenceSource(Base):
    __tablename__ = "competence_sources"
    material_id = Column(String(32), ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True)
    source_revision = Column(Integer, primary_key=True)
    competence_id = Column(String(120), primary_key=True)
    catalog_version = Column(String(40), primary_key=True)
    child_id = Column(String(32), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    excerpt = Column(String(500), nullable=False)
    __table_args__ = (
        ForeignKeyConstraint(["competence_id", "catalog_version"],
                             ["competence_definitions.id", "competence_definitions.version"]),
        Index("ix_competence_sources_child", "child_id", "competence_id"),
    )


class QuestionCompetence(Base):
    __tablename__ = "question_competences"
    unit_id = Column(String(32), ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    question_id = Column(String(60), primary_key=True)
    child_id = Column(String(32), ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    competence_id = Column(String(120), nullable=False)
    catalog_version = Column(String(40), nullable=False)
    role = Column(String(24), nullable=False)
    question_digest = Column(String(64), nullable=False)
    source_refs = Column(JSON, nullable=False)
    reference_ids = Column(JSON, nullable=False)
    __table_args__ = (
        ForeignKeyConstraint(["competence_id", "catalog_version"],
                             ["competence_definitions.id", "competence_definitions.version"]),
        Index("ix_question_competences_child", "child_id", "competence_id", "catalog_version"),
    )
