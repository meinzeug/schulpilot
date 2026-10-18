"""Fixed subject registry before OCR; preserve all private content snapshots."""

import sqlalchemy as sa
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = depends_on = None
PRIVATE = ("materials", "assignments", "learning_units", "school_grades", "mastery")


def upgrade():
    op.create_table(
        "subjects",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("key", sa.String(100), nullable=False, unique=True),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("owner_family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE")),
        sa.Column("cover_key", sa.String(100), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
    )
    op.create_index("ix_subjects_owner_family_id", "subjects", ["owner_family_id"])
    op.create_table(
        "subject_aliases",
        sa.Column("key", sa.String(64), primary_key=True),
        sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False),
        sa.Column("family_id", sa.String(32), sa.ForeignKey("families.id", ondelete="CASCADE")),
        sa.Column("normalized", sa.String(160), nullable=False),
    )
    op.create_index("ix_subject_aliases_subject_id", "subject_aliases", ["subject_id"])
    op.create_index("ix_subject_aliases_family_id", "subject_aliases", ["family_id"])
    op.create_table(
        "subject_providers",
        sa.Column("provider", sa.String(24), primary_key=True),
        sa.Column("external_id", sa.String(100), primary_key=True),
        sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
    )
    op.create_index("ix_subject_providers_subject_id", "subject_providers", ["subject_id"])
    op.create_table(
        "child_subjects",
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("level_type", sa.String(16)),
        sa.Column("level_number", sa.Integer()),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.CheckConstraint(
            "(level_type IS NULL AND level_number IS NULL) OR (level_type IS NOT NULL AND level_type IN ('klasse','lernjahr','vorschule') AND level_number IS NOT NULL AND level_number >= 0 AND level_number <= 20)",
            name="ck_child_subject_level",
        ),
    )
    for name in PRIVATE:
        if op.get_bind().dialect.name == "sqlite":
            # A table rebuild would cascade-delete attempts/source references.
            # SQLite supports this additive nullable REFERENCES column inline.
            op.execute(
                f'ALTER TABLE "{name}" ADD COLUMN subject_id VARCHAR(32) REFERENCES subjects(id) ON DELETE SET NULL'
            )
        else:
            op.add_column(
                name, sa.Column("subject_id", sa.String(32), sa.ForeignKey("subjects.id", ondelete="SET NULL"))
            )
        op.create_index(f"ix_{name}_subject_id", name, ["subject_id"])
    from schulpilot.subject_registry import backfill_connection, seed_connection

    seed_connection(op.get_bind())
    # Only the historical migration may preserve formerly dynamic names.
    # Ordinary rematching must never create subjects from untrusted AI labels.
    backfill_connection(op.get_bind(), preserve_legacy_extras=True)


def downgrade():
    for name in PRIVATE:
        op.drop_index(f"ix_{name}_subject_id", table_name=name)
        op.drop_column(name, "subject_id")
    for name in ("child_subjects", "subject_providers", "subject_aliases", "subjects"):
        op.drop_table(name)
