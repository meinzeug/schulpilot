"""Officially sourced topics and explicit, CAS-protected child school profiles."""
import sqlalchemy as sa
from alembic import op

revision = "0041"
down_revision = "0040"
branch_labels = depends_on = None


def upgrade():
    op.create_table("curriculum_documents",
        sa.Column("id", sa.String(120), primary_key=True),
        sa.Column("state_code", sa.String(5), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False))
    op.create_index("ix_curriculum_documents_state_code", "curriculum_documents", ["state_code"])
    op.create_table("curriculum_topics",
        sa.Column("id", sa.String(140), primary_key=True),
        sa.Column("document_id", sa.String(120), sa.ForeignKey("curriculum_documents.id", ondelete="CASCADE"), nullable=False),
        sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False),
        sa.Column("state_code", sa.String(5), nullable=False),
        sa.Column("school_form_id", sa.String(120), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False))
    for field in ("document_id", "subject_id"):
        op.create_index("ix_curriculum_topics_" + field, "curriculum_topics", [field])
    op.create_index("ix_curriculum_topics_scope", "curriculum_topics", ["state_code", "school_form_id", "subject_id", "id"])
    op.create_table("child_curriculum_profiles",
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("state_code", sa.String(5), nullable=False),
        sa.Column("school_form_id", sa.String(120)),
        sa.Column("legacy_binding", sa.JSON(), nullable=False),
        sa.Column("updated", sa.Integer(), nullable=False))
    op.create_table("child_curriculum_changes",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("actor_id", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("request_key", sa.String(80), nullable=False),
        sa.Column("digest", sa.String(64), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.UniqueConstraint("child_id", "request_key", name="uq_curriculum_profile_request"))
    op.create_index("ix_child_curriculum_changes_child_id", "child_curriculum_changes", ["child_id"])
    # The same reviewed immutable public package is installed by normal init_db.
    # A Session bound to the migration transaction never commits independently.
    from schulpilot.curriculum import seed
    from sqlalchemy.orm import Session

    with Session(bind=op.get_bind()) as db:
        seed(db)
        db.flush()


def downgrade():
    op.drop_table("child_curriculum_changes")
    op.drop_table("child_curriculum_profiles")
    op.drop_table("curriculum_topics")
    op.drop_table("curriculum_documents")
