"""Immutable public graphic recipes and private, source-bound unit snapshots."""
from sqlalchemy import JSON, Column, ForeignKey, Integer, String, Text

from .db import Base, now


class VisualReference(Base):
    __tablename__ = "visual_reference_versions"
    id = Column(String(100), primary_key=True)
    version = Column(Integer, primary_key=True)
    digest = Column(String(64), nullable=False)
    recipe = Column(JSON, nullable=False)


class UnitVisualSnapshot(Base):
    __tablename__ = "unit_visual_snapshots"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    source_signature = Column(String(64), nullable=False)
    status = Column(String(20), nullable=False)
    reason = Column(String(48))
    steps = Column(JSON, nullable=False, default=list)
    question_steps = Column(JSON, nullable=False, default=dict)
    receipts = Column(JSON, nullable=False, default=list)
    source_bindings = Column(JSON, nullable=False, default=list)
    notice = Column(Text, nullable=False, default="")
    created = Column(Integer, nullable=False, default=lambda: int(now()))


class UnitVisualPosition(Base):
    """Private technical reading position, never a competence or activity."""
    __tablename__ = "unit_visual_positions"
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    source_signature = Column(String(64), nullable=False)
    revision = Column(Integer, nullable=False, default=1)
    position = Column(JSON, nullable=False)
    updated = Column(Integer, nullable=False, default=lambda: int(now()))
