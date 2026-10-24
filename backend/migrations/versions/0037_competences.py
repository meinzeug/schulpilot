"""Stable reviewed competence identities and source/question bindings."""

import json
from pathlib import Path

import sqlalchemy as sa
from alembic import op

revision = "0037"
down_revision = "0036"
branch_labels = depends_on = None


def upgrade():
    op.create_table("competence_definitions",
        sa.Column("id", sa.String(120), primary_key=True),
        sa.Column("version", sa.String(40), primary_key=True),
        sa.Column("subject_key", sa.String(80), nullable=False),
        sa.Column("label", sa.String(180), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False))
    op.create_table("competence_sources",
        sa.Column("material_id", sa.String(32), sa.ForeignKey("materials.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("source_revision", sa.Integer(), primary_key=True),
        sa.Column("competence_id", sa.String(120), primary_key=True),
        sa.Column("catalog_version", sa.String(40), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("excerpt", sa.String(500), nullable=False),
        sa.ForeignKeyConstraint(["competence_id", "catalog_version"],
                                ["competence_definitions.id", "competence_definitions.version"]))
    op.create_index("ix_competence_sources_child", "competence_sources", ["child_id", "competence_id"])
    op.create_table("question_competences",
        sa.Column("unit_id", sa.String(32), sa.ForeignKey("learning_units.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("question_id", sa.String(60), primary_key=True),
        sa.Column("child_id", sa.String(32), sa.ForeignKey("children.id", ondelete="CASCADE"), nullable=False),
        sa.Column("competence_id", sa.String(120), nullable=False),
        sa.Column("catalog_version", sa.String(40), nullable=False),
        sa.Column("role", sa.String(24), nullable=False),
        sa.Column("question_digest", sa.String(64), nullable=False),
        sa.Column("source_refs", sa.JSON(), nullable=False),
        sa.Column("reference_ids", sa.JSON(), nullable=False),
        sa.ForeignKeyConstraint(["competence_id", "catalog_version"],
                                ["competence_definitions.id", "competence_definitions.version"]))
    op.create_index("ix_question_competences_child", "question_competences", ["child_id", "competence_id", "catalog_version"])
    # Immutable versioned seed: never import a future ORM shape in a migration.
    seed = json.loads((Path(__file__).parents[2] / "schulpilot/reference/competencies-v1.json").read_text())
    table = sa.table("competence_definitions", sa.column("id", sa.String()), sa.column("version", sa.String()),
        sa.column("subject_key", sa.String()), sa.column("label", sa.String()), sa.column("data", sa.JSON()))
    op.bulk_insert(table, [{"id": row["id"], "version": seed["version"], "subject_key": row["subject_key"],
        "label": row["label"], "data": row} for row in seed["competences"]])


def downgrade():
    op.drop_table("question_competences")
    op.drop_table("competence_sources")
    op.drop_table("competence_definitions")
