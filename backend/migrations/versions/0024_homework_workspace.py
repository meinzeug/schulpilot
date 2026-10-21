"""Homework workspace on existing private materials and durable tutor turns."""

import sqlalchemy as sa
from alembic import op

revision = "0024"
down_revision = "0023"
branch_labels = depends_on = None


def upgrade():
    op.add_column("materials", sa.Column("purpose", sa.String(16), server_default="notebook", nullable=False))
    op.add_column("materials", sa.Column("homework_state", sa.JSON(), server_default="{}", nullable=False))
    op.add_column("tutor_turns", sa.Column("homework_context", sa.JSON()))
    op.create_index("ix_materials_child_purpose", "materials", ["child_id", "purpose", "created", "id"])


def downgrade():
    op.drop_index("ix_materials_child_purpose", table_name="materials")
    op.drop_column("tutor_turns", "homework_context")
    op.drop_column("materials", "homework_state")
    op.drop_column("materials", "purpose")
