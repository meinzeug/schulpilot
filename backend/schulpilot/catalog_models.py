"""Shared provider metadata; private contextual matches never enter the catalog."""

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Column,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    literal_column,
)

from .db import Base, now, uid


class CatalogSnapshot(Base):
    __tablename__ = "catalog_snapshots"
    id = Column(String(64), primary_key=True)
    provider = Column(String(24), nullable=False)
    schema_version = Column(String(20), nullable=False)
    metadata_json = Column(JSON, nullable=False)
    report = Column(JSON, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    last_import = Column(Integer, default=lambda: int(now()), nullable=False)


class CatalogState(Base):
    __tablename__ = "catalog_state"
    provider = Column(String(24), primary_key=True)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False)


class CatalogLevel(Base):
    __tablename__ = "catalog_levels"
    id = Column(String(100), primary_key=True)
    subject_id = Column(ForeignKey("subjects.id"), nullable=False, index=True)
    title = Column(String(160), nullable=False)
    level_type = Column(String(16), nullable=False)
    level_number = Column(Integer)
    has_topics = Column(Boolean, nullable=False)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogTopic(Base):
    __tablename__ = "catalog_topics"
    id = Column(String(100), primary_key=True)
    subject_id = Column(ForeignKey("subjects.id"), nullable=False, index=True)
    title = Column(Text, nullable=False)
    entry_url = Column(Text, nullable=False)
    search_text = Column(Text, nullable=False)
    empty_curated = Column(Boolean, nullable=False)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogPlacement(Base):
    __tablename__ = "catalog_placements"
    id = Column(String(64), primary_key=True)
    topic_id = Column(ForeignKey("catalog_topics.id"), nullable=False, index=True)
    level_id = Column(ForeignKey("catalog_levels.id"), nullable=False, index=True)
    area = Column(Text, nullable=False)
    entry_url = Column(Text, nullable=False)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogContent(Base):
    __tablename__ = "catalog_contents"
    id = Column(String(100), primary_key=True)
    title = Column(Text, nullable=False)
    url = Column(Text, nullable=False)
    content_type = Column(String(24), nullable=False, index=True)
    title_verified = Column(Boolean, nullable=False)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogMembership(Base):
    __tablename__ = "catalog_memberships"
    topic_id = Column(ForeignKey("catalog_topics.id"), primary_key=True)
    content_id = Column(ForeignKey("catalog_contents.id"), primary_key=True)
    url = Column(Text, nullable=False)
    curated = Column(Boolean, nullable=False)
    general_verified = Column(Boolean, default=False, nullable=False)
    general_url = Column(Text)
    position = Column(Integer)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogProvenance(Base):
    __tablename__ = "catalog_provenance"
    kind = Column(String(32), primary_key=True)
    key = Column(String(240), primary_key=True)
    data = Column(JSON, nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False, index=True)


class CatalogRefresh(Base):
    """Small resumable local batches in the existing worker; no AI reservation."""

    __tablename__ = "catalog_refreshes"
    id = Column(String(64), primary_key=True)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"), nullable=False)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), index=True)
    resource_kind = Column(String(20))
    resource_id = Column(String(32))
    annotation = Column(JSON)
    lease = Column(String(32))
    status = Column(String(20), default="queued", nullable=False)
    phase = Column(Integer, default=0, nullable=False)
    cursor = Column(String(32), default="", nullable=False)
    processed = Column(Integer, default=0, nullable=False)
    error = Column(String(160))
    updated = Column(Integer, default=lambda: int(now()), nullable=False)


class LearningTipContext(Base):
    __tablename__ = "learning_tip_contexts"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    context_ref = Column(String(100), nullable=False, unique=True)
    material_id = Column(ForeignKey("materials.id", ondelete="CASCADE"), index=True)
    unit_id = Column(ForeignKey("learning_units.id", ondelete="CASCADE"), index=True)
    assignment_id = Column(ForeignKey("assignments.id", ondelete="CASCADE"), index=True)
    tutor_id = Column(ForeignKey("tutor_turns.id", ondelete="CASCADE"), index=True)
    subject_id = Column(ForeignKey("subjects.id", ondelete="SET NULL"))
    source_fingerprint = Column(String(64), nullable=False)
    fingerprint = Column(String(64), nullable=False)
    snapshot_id = Column(ForeignKey("catalog_snapshots.id"))
    matcher_version = Column(String(20), nullable=False)
    status = Column(String(20), nullable=False)
    matches = Column(JSON, default=list, nullable=False)
    confirmed_topic_ids = Column(JSON, default=list, nullable=False)
    confirmation_fingerprint = Column(String(64))
    revision = Column(Integer, default=1, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    updated = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (
        CheckConstraint(
            "(CASE WHEN material_id IS NULL THEN 0 ELSE 1 END + "
            "CASE WHEN unit_id IS NULL THEN 0 ELSE 1 END + "
            "CASE WHEN assignment_id IS NULL THEN 0 ELSE 1 END + "
            "CASE WHEN tutor_id IS NULL THEN 0 ELSE 1 END) = 1",
            name="ck_tip_one_context",
        ),
    )


class LearningTipInteraction(Base):
    __tablename__ = "learning_tip_interactions"
    id = Column(String(32), primary_key=True, default=uid)
    child_id = Column(ForeignKey("children.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    context_id = Column(ForeignKey("learning_tip_contexts.id", ondelete="CASCADE"), index=True)
    content_id = Column(ForeignKey("catalog_contents.id"))
    kind = Column(String(24), nullable=False)
    request_key = Column(String(80), nullable=False)
    request_digest = Column(String(64), nullable=False)
    data = Column(JSON, nullable=False)
    created = Column(Integer, default=lambda: int(now()), nullable=False)
    __table_args__ = (UniqueConstraint("user_id", "request_key", name="uq_tip_interaction_request"),)


Index("ix_catalog_level_lookup", CatalogLevel.subject_id, CatalogLevel.level_type, CatalogLevel.level_number)
Index("ix_catalog_membership_scope", CatalogMembership.topic_id, CatalogMembership.curated)
Index("ix_catalog_refresh_queue", CatalogRefresh.status, CatalogRefresh.updated)
Index(
    "ix_catalog_topic_search",
    func.to_tsvector(literal_column("'german'"), CatalogTopic.search_text),
    postgresql_using="gin",
).ddl_if(dialect="postgresql")
