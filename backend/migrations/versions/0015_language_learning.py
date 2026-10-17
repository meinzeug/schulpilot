"""Add revision-bound vocabulary and idempotent language evidence."""

import sqlalchemy as sa
from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = depends_on = None


def key(name, target, *, primary=False, nullable=False, ondelete="CASCADE"):
    return sa.Column(
        name, sa.String(32), sa.ForeignKey(target, ondelete=ondelete), primary_key=primary, nullable=nullable
    )


def col(name, kind, **kwargs):
    return sa.Column(name, kind, nullable=False, **kwargs)


def upgrade():
    op.add_column("attempts", sa.Column("request_key", sa.String(80)))
    op.add_column("attempts", sa.Column("request_digest", sa.String(64)))
    op.add_column("attempts", sa.Column("evaluation", sa.JSON()))
    op.add_column("attempts", col("input_method", sa.String(12), server_default="typed"))
    # A unique index is equivalent here and avoids rebuilding SQLite's live
    # attempts table (which can cascade-delete dependent evidence).
    op.create_index("uq_attempt_request", "attempts", ["unit_id", "request_key"], unique=True)

    def common():
        return [sa.Column("id", sa.String(32), primary_key=True), key("child_id", "children.id")]

    op.create_table(
        "vocabulary_collections",
        *common(),
        col("title", sa.String(160)),
        col("target_locale", sa.String(12)),
        col("created", sa.Integer()),
    )
    op.create_table(
        "vocabulary_items",
        *common(),
        col("identity", sa.String(64)),
        col("target_locale", sa.String(12)),
        col("word", sa.String(200)),
        col("meaning", sa.String(200)),
        col("context", sa.String(500)),
        col("part_of_speech", sa.String(40)),
        col("variants", sa.JSON()),
        col("meaning_variants", sa.JSON()),
        col("source_revisions", sa.JSON()),
        col("origin", sa.String(16)),
        col("revision", sa.Integer()),
        col("confirmed", sa.Boolean()),
        col("history", sa.JSON()),
        col("created", sa.Integer()),
        sa.UniqueConstraint("child_id", "identity", name="uq_vocabulary_identity"),
    )
    op.create_table(
        "vocabulary_memberships",
        key("collection_id", "vocabulary_collections.id", primary=True),
        key("item_id", "vocabulary_items.id", primary=True),
    )
    op.create_table(
        "vocabulary_reviews",
        *common(),
        key("item_id", "vocabulary_items.id"),
        col("revision", sa.Integer()),
        col("direction", sa.String(16)),
        col("skill", sa.String(24)),
        col("stage", sa.Integer()),
        col("due", sa.String(10)),
        sa.Column("last_promoted", sa.String(10)),
        col("needs_clarification", sa.Boolean()),
        sa.UniqueConstraint("item_id", "revision", "direction", "skill", name="uq_vocabulary_review"),
    )
    op.create_table(
        "vocabulary_review_events",
        key("attempt_id", "attempts.id", primary=True),
        key("review_id", "vocabulary_reviews.id"),
        col("day", sa.String(10)),
        col("advanced", sa.Boolean()),
        col("stage", sa.Integer()),
        col("due", sa.String(10)),
    )
    op.create_table(
        "vocabulary_imports",
        *common(),
        key("user_id", "users.id"),
        key("session_id", "sessions.id", nullable=True, ondelete="SET NULL"),
        col("request_key", sa.String(80)),
        col("request_digest", sa.String(64)),
        col("target_locale", sa.String(12)),
        col("title", sa.String(160)),
        col("text", sa.Text()),
        col("source_revisions", sa.JSON()),
        col("pairs", sa.JSON()),
        col("status", sa.String(16)),
        key("job_id", "jobs.id", nullable=True, ondelete="SET NULL"),
        key("collection_id", "vocabulary_collections.id", nullable=True, ondelete="SET NULL"),
        sa.Column("error", sa.String(500)),
        col("created", sa.Integer()),
        sa.UniqueConstraint("child_id", "request_key", name="uq_vocabulary_import_request"),
    )
    op.create_table(
        "vocabulary_actions",
        *common(),
        col("request_key", sa.String(80)),
        col("request_digest", sa.String(64)),
        key("unit_id", "learning_units.id"),
        sa.UniqueConstraint("child_id", "request_key", name="uq_vocabulary_action_request"),
    )
    op.create_table(
        "language_projects",
        *common(),
        key("user_id", "users.id"),
        key("session_id", "sessions.id", nullable=True, ondelete="SET NULL"),
        col("request_key", sa.String(80)),
        col("request_digest", sa.String(64)),
        col("target_locale", sa.String(12)),
        col("mode", sa.String(32)),
        col("inputs", sa.JSON()),
        col("source_revisions", sa.JSON()),
        col("item_revisions", sa.JSON()),
        key("previous_id", "language_projects.id", nullable=True),
        col("step", sa.Integer()),
        col("status", sa.String(16)),
        sa.Column("result", sa.JSON()),
        sa.Column("error", sa.String(500)),
        key("job_id", "jobs.id", nullable=True, ondelete="SET NULL"),
        key("unit_id", "learning_units.id", nullable=True, ondelete="SET NULL"),
        col("created", sa.Integer()),
        sa.UniqueConstraint("child_id", "request_key", name="uq_language_project_request"),
    )
    for table in (
        "vocabulary_collections",
        "vocabulary_items",
        "vocabulary_reviews",
        "vocabulary_imports",
        "vocabulary_actions",
        "language_projects",
    ):
        op.create_index("ix_" + table + "_child_id", table, ["child_id"])
    op.create_index("ix_vocabulary_review_events_review_id", "vocabulary_review_events", ["review_id"])


def downgrade():
    for table in (
        "language_projects",
        "vocabulary_actions",
        "vocabulary_imports",
        "vocabulary_review_events",
        "vocabulary_reviews",
        "vocabulary_memberships",
        "vocabulary_items",
        "vocabulary_collections",
    ):
        op.drop_table(table)
    with op.batch_alter_table("attempts") as table:
        table.drop_index("uq_attempt_request")
        for name in ("request_key", "request_digest", "evaluation", "input_method"):
            table.drop_column(name)
