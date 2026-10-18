"""Shared source catalog; private versioned tips in the existing DB worker."""

import sqlalchemy as sa
from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "catalog_snapshots",
        sa.Column("id", sa.String(length=64), primary_key=True, nullable=False),
        sa.Column("provider", sa.String(length=24), nullable=False),
        sa.Column("schema_version", sa.String(length=20), nullable=False),
        sa.Column("metadata_json", sa.JSON(), nullable=False),
        sa.Column("report", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("last_import", sa.Integer(), nullable=False),
    )
    op.create_table(
        "catalog_contents",
        sa.Column("id", sa.String(length=100), primary_key=True, nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("content_type", sa.String(length=24), nullable=False),
        sa.Column("title_verified", sa.Boolean(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_contents_content_type", "catalog_contents", ["content_type"])
    op.create_index("ix_catalog_contents_snapshot_id", "catalog_contents", ["snapshot_id"])
    op.create_table(
        "catalog_provenance",
        sa.Column("kind", sa.String(length=32), primary_key=True, nullable=False),
        sa.Column("key", sa.String(length=240), primary_key=True, nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_provenance_snapshot_id", "catalog_provenance", ["snapshot_id"])
    op.create_table(
        "catalog_refreshes",
        sa.Column("id", sa.String(length=64), primary_key=True, nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
        sa.Column("child_id", sa.String(length=32), sa.ForeignKey("children.id", ondelete="CASCADE")),
        sa.Column("resource_kind", sa.String(length=20)),
        sa.Column("resource_id", sa.String(length=32)),
        sa.Column("annotation", sa.JSON()),
        sa.Column("lease", sa.String(length=32)),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("phase", sa.Integer(), nullable=False),
        sa.Column("cursor", sa.String(length=32), nullable=False),
        sa.Column("processed", sa.Integer(), nullable=False),
        sa.Column("error", sa.String(length=160)),
        sa.Column("updated", sa.Integer(), nullable=False),
    )
    op.create_index("ix_catalog_refreshes_child_id", "catalog_refreshes", ["child_id"])
    op.create_index("ix_catalog_refresh_queue", "catalog_refreshes", ["status", "updated"])
    op.create_table(
        "catalog_state",
        sa.Column("provider", sa.String(length=24), primary_key=True, nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_table(
        "catalog_levels",
        sa.Column("id", sa.String(length=100), primary_key=True, nullable=False),
        sa.Column("subject_id", sa.String(length=32), sa.ForeignKey("subjects.id"), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("level_type", sa.String(length=16), nullable=False),
        sa.Column("level_number", sa.Integer()),
        sa.Column("has_topics", sa.Boolean(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_level_lookup", "catalog_levels", ["subject_id", "level_type", "level_number"])
    op.create_index("ix_catalog_levels_snapshot_id", "catalog_levels", ["snapshot_id"])
    op.create_index("ix_catalog_levels_subject_id", "catalog_levels", ["subject_id"])
    op.create_table(
        "catalog_topics",
        sa.Column("id", sa.String(length=100), primary_key=True, nullable=False),
        sa.Column("subject_id", sa.String(length=32), sa.ForeignKey("subjects.id"), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("entry_url", sa.Text(), nullable=False),
        sa.Column("search_text", sa.Text(), nullable=False),
        sa.Column("empty_curated", sa.Boolean(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_topics_snapshot_id", "catalog_topics", ["snapshot_id"])
    op.create_index("ix_catalog_topics_subject_id", "catalog_topics", ["subject_id"])
    op.create_table(
        "catalog_memberships",
        sa.Column(
            "topic_id", sa.String(length=100), sa.ForeignKey("catalog_topics.id"), primary_key=True, nullable=False
        ),
        sa.Column(
            "content_id", sa.String(length=100), sa.ForeignKey("catalog_contents.id"), primary_key=True, nullable=False
        ),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("curated", sa.Boolean(), nullable=False),
        sa.Column("general_verified", sa.Boolean(), nullable=False),
        sa.Column("general_url", sa.Text()),
        sa.Column("position", sa.Integer()),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_membership_scope", "catalog_memberships", ["topic_id", "curated"])
    op.create_index("ix_catalog_memberships_snapshot_id", "catalog_memberships", ["snapshot_id"])
    op.create_table(
        "catalog_placements",
        sa.Column("id", sa.String(length=64), primary_key=True, nullable=False),
        sa.Column("topic_id", sa.String(length=100), sa.ForeignKey("catalog_topics.id"), nullable=False),
        sa.Column("level_id", sa.String(length=100), sa.ForeignKey("catalog_levels.id"), nullable=False),
        sa.Column("area", sa.Text(), nullable=False),
        sa.Column("entry_url", sa.Text(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id"), nullable=False),
    )
    op.create_index("ix_catalog_placements_level_id", "catalog_placements", ["level_id"])
    op.create_index("ix_catalog_placements_snapshot_id", "catalog_placements", ["snapshot_id"])
    op.create_index("ix_catalog_placements_topic_id", "catalog_placements", ["topic_id"])
    op.create_table(
        "learning_tip_contexts",
        sa.Column("id", sa.String(length=32), primary_key=True, nullable=False),
        sa.Column("child_id", sa.String(length=32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("context_ref", sa.String(length=100), nullable=False),
        sa.Column("material_id", sa.String(length=32), sa.ForeignKey("materials.id", ondelete="CASCADE")),
        sa.Column("unit_id", sa.String(length=32), sa.ForeignKey("learning_units.id", ondelete="CASCADE")),
        sa.Column("assignment_id", sa.String(length=32), sa.ForeignKey("assignments.id", ondelete="CASCADE")),
        sa.Column("tutor_id", sa.String(length=32), sa.ForeignKey("tutor_turns.id", ondelete="CASCADE")),
        sa.Column("subject_id", sa.String(length=32), sa.ForeignKey("subjects.id", ondelete="SET NULL")),
        sa.Column("source_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("fingerprint", sa.String(length=64), nullable=False),
        sa.Column("snapshot_id", sa.String(length=64), sa.ForeignKey("catalog_snapshots.id")),
        sa.Column("matcher_version", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("matches", sa.JSON(), nullable=False),
        sa.Column("confirmed_topic_ids", sa.JSON(), nullable=False),
        sa.Column("confirmation_fingerprint", sa.String(length=64)),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False),
        sa.UniqueConstraint("context_ref"),
        sa.CheckConstraint(
            "(CASE WHEN material_id IS NULL THEN 0 ELSE 1 END + CASE WHEN unit_id IS NULL THEN 0 ELSE 1 END + CASE WHEN assignment_id IS NULL THEN 0 ELSE 1 END + CASE WHEN tutor_id IS NULL THEN 0 ELSE 1 END) = 1",
            name="ck_tip_one_context",
        ),
    )
    op.create_index("ix_learning_tip_contexts_assignment_id", "learning_tip_contexts", ["assignment_id"])
    op.create_index("ix_learning_tip_contexts_child_id", "learning_tip_contexts", ["child_id"])
    op.create_index("ix_learning_tip_contexts_material_id", "learning_tip_contexts", ["material_id"])
    op.create_index("ix_learning_tip_contexts_tutor_id", "learning_tip_contexts", ["tutor_id"])
    op.create_index("ix_learning_tip_contexts_unit_id", "learning_tip_contexts", ["unit_id"])
    op.create_table(
        "learning_tip_interactions",
        sa.Column("id", sa.String(length=32), primary_key=True, nullable=False),
        sa.Column("child_id", sa.String(length=32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.String(length=32), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("context_id", sa.String(length=32), sa.ForeignKey("learning_tip_contexts.id", ondelete="CASCADE")),
        sa.Column("content_id", sa.String(length=100), sa.ForeignKey("catalog_contents.id")),
        sa.Column("kind", sa.String(length=24), nullable=False),
        sa.Column("request_key", sa.String(length=80), nullable=False),
        sa.Column("request_digest", sa.String(length=64), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("user_id", "request_key", name="uq_tip_interaction_request"),
    )
    op.create_index("ix_learning_tip_interactions_child_id", "learning_tip_interactions", ["child_id"])
    op.create_index("ix_learning_tip_interactions_context_id", "learning_tip_interactions", ["context_id"])
    op.create_index("ix_learning_tip_interactions_user_id", "learning_tip_interactions", ["user_id"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute(
            "CREATE INDEX ix_catalog_topic_search ON catalog_topics USING gin(to_tsvector('german', search_text))"
        )


def downgrade():
    if op.get_bind().scalar(sa.text("SELECT count(*) FROM learning_tip_contexts")):
        raise RuntimeError("Private learning tips exist; preserve additive schema and use a forward correction.")
    op.drop_table("learning_tip_interactions")
    op.drop_table("learning_tip_contexts")
    op.drop_table("catalog_placements")
    op.drop_table("catalog_memberships")
    op.drop_table("catalog_topics")
    op.drop_table("catalog_levels")
    op.drop_table("catalog_state")
    op.drop_table("catalog_refreshes")
    op.drop_table("catalog_provenance")
    op.drop_table("catalog_contents")
    op.drop_table("catalog_snapshots")
