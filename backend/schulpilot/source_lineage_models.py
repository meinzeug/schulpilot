"""Private, immutable source snapshots and source-dependent invalidation receipts."""

from sqlalchemy import JSON, Column, ForeignKey, Integer, String, UniqueConstraint, event

from .db import Base, now, uid


class SourceRevision(Base):
    __tablename__ = "source_revisions"
    id = Column(String(32), primary_key=True, default=uid)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    revision = Column(Integer, nullable=False)
    sequence = Column(Integer, nullable=False)
    digest = Column(String(64), nullable=False)
    cause = Column(String(24), nullable=False)
    snapshot = Column(JSON, nullable=False)
    receipt = Column(JSON, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (
        UniqueConstraint("material_id", "revision", "digest", name="uq_source_snapshot"),
        UniqueConstraint("material_id", "sequence", name="uq_source_sequence"),
    )


class SourceInvalidation(Base):
    __tablename__ = "source_invalidations"
    id = Column(String(32), primary_key=True, default=uid)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), nullable=False, index=True)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), nullable=False, index=True)
    source_revision = Column(Integer, nullable=False)
    current_revision = Column(Integer, nullable=False)
    reason = Column(String(64), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("unit_id", "material_id", "current_revision", name="uq_source_invalidation"),)


class SourceImageReceipt(Base):
    __tablename__ = "source_image_receipts"
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True)
    image_digest = Column(String(64), nullable=False)
    geometry = Column(JSON, nullable=False)
    normalization_version = Column(String(64), nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class SourceEvaluationBudget(Base):
    __tablename__ = "source_evaluation_budgets"
    id = Column(String(64), primary_key=True)
    limit_micros = Column(Integer, nullable=False)


class SourceEvaluationGrant(Base):
    __tablename__ = "source_evaluation_grants"
    id = Column(String(32), primary_key=True, default=uid)
    work_id = Column(ForeignKey("source_evaluation_budgets.id"), nullable=False)
    operator_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    family_id = Column(ForeignKey("families.id", ondelete="CASCADE"), nullable=False)
    sources = Column(JSON, nullable=False)
    config_revision = Column(Integer, nullable=False)
    policy_digest = Column(String(64), nullable=False)
    expires = Column(Integer, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


class SourceEvaluationCase(Base):
    __tablename__ = "source_evaluation_cases"
    id = Column(String(32), primary_key=True)
    work_id = Column(ForeignKey("source_evaluation_budgets.id"), nullable=False)
    grant_id = Column(ForeignKey("source_evaluation_grants.id", ondelete="SET NULL"))
    material_id = Column(ForeignKey("materials.id", ondelete="SET NULL"))
    job_id = Column(ForeignKey("jobs.id", ondelete="SET NULL"), unique=True)
    tier = Column(String(8), nullable=False)
    status = Column(String(20), nullable=False)
    reserved_micros = Column(Integer, nullable=False, default=0)
    charged_micros = Column(Integer)
    created = Column(Integer, default=lambda: int(now()), nullable=False)


@event.listens_for(SourceRevision, "before_update")
@event.listens_for(SourceImageReceipt, "before_update")
def immutable_source_receipt(mapper, connection, target):
    raise ValueError("Gespeicherte Quellenbelege sind unveränderlich; eine neue Fassung anlegen.")
