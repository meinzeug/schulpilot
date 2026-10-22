"""Neutral incident metadata and explicit review-only code repair requests."""

import sqlalchemy as sa
from alembic import op

revision = "0028"
down_revision = "0027"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "operator_incidents",
        sa.Column("id", sa.String(34), primary_key=True),
        sa.Column("code", sa.String(32), nullable=False),
        sa.Column("kind", sa.String(24), nullable=False),
        sa.Column("function", sa.String(120), nullable=False),
        sa.Column("exception_category", sa.String(32), nullable=False),
        sa.Column("source_commit", sa.String(64)),
        sa.Column("release", sa.String(64), nullable=False),
        sa.Column("first_seen", sa.Integer(), nullable=False),
        sa.Column("last_seen", sa.Integer(), nullable=False),
        sa.Column("occurrences", sa.Integer(), nullable=False),
        sa.Column("trace_id", sa.String(32), nullable=False),
    )
    op.create_index("ix_operator_incidents_last_seen", "operator_incidents", ["last_seen"])
    op.create_table(
        "operator_repair_requests",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("source_incident_key", sa.String(34), nullable=False),
        sa.Column("incident_snapshot", sa.JSON(), nullable=False),
        sa.Column("incident_snapshot_digest", sa.String(64), nullable=False),
        sa.Column("source_commit", sa.String(64), nullable=False),
        sa.Column("requested_by", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("requested_session_id", sa.String(32), sa.ForeignKey("sessions.id", ondelete="SET NULL")),
        sa.Column("idempotency", sa.String(64), nullable=False, unique=True),
        sa.Column("request_digest", sa.String(64), nullable=False),
        sa.Column("active_slot", sa.String(64), unique=True),
        sa.Column("execution_slot", sa.String(8), unique=True),
        sa.Column("model", sa.String(160), nullable=False),
        sa.Column("effort", sa.String(16), nullable=False),
        sa.Column("catalog_binding", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("created", sa.Integer(), nullable=False),
        sa.Column("started", sa.Integer()),
        sa.Column("finished", sa.Integer()),
        sa.Column("artifact_path", sa.Text()),
        sa.Column("artifact_sha256", sa.String(64)),
        sa.Column("artifact_size", sa.Integer()),
        sa.Column("review_status", sa.String(16), nullable=False),
        sa.Column("reviewed_by", sa.String(32), sa.ForeignKey("users.id", ondelete="SET NULL")),
        sa.Column("reviewed_at", sa.Integer()),
        sa.Column("error_code", sa.String(32)),
        sa.Column("test_summary", sa.JSON()),
        sa.Column("reserved_micros", sa.Integer()),
        sa.Column("budget_bucket_ids", sa.JSON()),
        sa.Column("cost_micros", sa.Integer()),
        sa.Column("cost_source", sa.String(24), nullable=False, server_default="unknown"),
        sa.Column("settlement_version", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index(
        "ix_operator_repair_requests_source_incident_key", "operator_repair_requests", ["source_incident_key"]
    )
    op.create_index("ix_operator_repair_requests_created", "operator_repair_requests", ["created"])

    op.create_table(
        "operator_repair_keys",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "request_id",
            sa.String(32),
            sa.ForeignKey("operator_repair_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("request_digest", sa.String(64), nullable=False),
    )
    op.create_index("ix_operator_repair_keys_request_id", "operator_repair_keys", ["request_id"])


def downgrade():
    op.drop_table("operator_repair_keys")
    op.drop_table("operator_repair_requests")
    op.drop_table("operator_incidents")
