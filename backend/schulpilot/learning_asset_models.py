"""Public immutable builds and separately owned private exploration instances."""
from sqlalchemy import JSON, Column, ForeignKey, Index, Integer, String, UniqueConstraint

from .db import Base, now, uid


class LearningAssetBuild(Base):
    __tablename__ = "learning_asset_builds"
    build_key = Column(String(64), primary_key=True)
    specification = Column(JSON, nullable=False)
    status = Column(String(24), nullable=False)
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), nullable=True)
    reference_id = Column(String(100))
    reference_version = Column(Integer)
    reference_digest = Column(String(64))
    technical_status = Column(String(24), nullable=False, default="pending")
    factual_status = Column(String(32), nullable=False, default="unassessed")
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    updated = Column(Integer, nullable=False, default=lambda: int(now()))


class LearningAssetInstance(Base):
    __tablename__ = "learning_asset_instances"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    build_key = Column(ForeignKey("learning_asset_builds.build_key"), nullable=False)
    request_key = Column(String(80), nullable=False)
    request_digest = Column(String(64), nullable=False)
    created = Column(Integer, nullable=False, default=lambda: int(now()))
    __table_args__ = (UniqueConstraint("user_id", "request_key", name="uq_learning_asset_request"),
                     Index("ix_learning_asset_instance_child_created", "child_id", "created"))
