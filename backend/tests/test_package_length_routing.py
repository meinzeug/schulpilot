"""A conscious package retry may use the preapproved route after real truncation."""

from copy import deepcopy

import pytest
from conftest import create_child
from schulpilot import school_preparation
from schulpilot.db import DB, Job, Material, ProviderConfig, SchoolDay, Usage, uid
from schulpilot.model_routing import choose_tier, features_for
from sqlalchemy import select
from test_model_routing import setup_policy
from test_package_parts_worker import artificial_day, preparation

LENGTH = (
    "Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
    "kein automatischer Wiederholungsversuch."
)


@pytest.fixture
def jobs(api, household):
    day_id, child, _ = artificial_day(api, household)
    setup_policy(household[0]["families"][0]["id"])
    with DB.begin() as db:
        pages = list(
            db.scalars(select(Material).where(Material.school_day_id == day_id).order_by(Material.page_number))
        )
        for page in pages[2:]:
            db.delete(page)
        config = db.get(ProviderConfig, 1)
        config.routing_policy = {**config.routing_policy, "economy_mode": True}
    preparation(api, day_id, "package-length-route-test")
    school_preparation.advance_one()
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        old = db.get(Job, day.preparation["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == old.id))
        assert usage.route_snapshot["tier"] == "luna"
        usage.status = "failed_billed"
        usage.telemetry = {"finish_reason": "length"}
        old.status, old.error = "failed", LENGTH
        upcoming = Job(child_id=child["id"], kind="package", payload=deepcopy(old.payload), idempotency=uid())
        db.add(upcoming)
        db.flush()
        return day_id, child["id"], old.id, upcoming.id, usage.id, old.payload["sources"][0]["id"]


def test_exact_evidence_changes_only_route_before_normal_reservation(jobs):
    _, child, _, upcoming, _, _ = jobs
    with DB() as db:
        facts = features_for(db, child, upcoming)
        assert facts["package_length_failed"]
        assert choose_tier("package", facts, economy=True) == ("sol", "recorded_package_output_length")
        assert not db.new and not db.dirty


@pytest.mark.parametrize(
    "fault",
    [
        "other_error",
        "partial_error",
        "no_length_receipt",
        "other_route",
        "unbilled",
        "different_sources",
        "different_day_revision",
        "different_partition",
        "different_plan",
        "different_planning",
        "different_group",
        "source_changed",
        "unconfirmed",
        "foreign_child",
        "completed",
    ],
)
def test_no_route_change_without_same_current_part_and_evidence(jobs, fault, api, household):
    day_id, child, old_id, upcoming_id, usage_id, material_id = jobs
    sibling = create_child(api, household[0], "routing-sibling") if fault == "foreign_child" else None
    with DB.begin() as db:
        old, usage = db.get(Job, old_id), db.get(Usage, usage_id)
        if fault == "other_error":
            old.error = "Andere Ablehnung"
        elif fault == "partial_error":
            old.error = "Die KI hat die begrenzte Ausgabelänge erreicht."
        elif fault == "no_length_receipt":
            usage.telemetry = {"finish_reason": "stop"}
        elif fault == "other_route":
            usage.route_snapshot = {**usage.route_snapshot, "tier": "sol"}
        elif fault == "unbilled":
            usage.status = "failed_not_sent"
        elif fault == "source_changed":
            db.get(Material, material_id).content += " Veränderter Text."
        elif fault == "unconfirmed":
            db.get(Material, material_id).confirmed = False
        elif fault == "foreign_child":
            old.child_id = sibling["id"]
        elif fault == "completed":
            old.status = "completed"
        else:
            key = {
                "different_sources": "sources",
                "different_day_revision": "day_revision",
                "different_partition": "package_partition",
                "different_plan": "package_plan_digest",
                "different_planning": "planning_fingerprint",
                "different_group": "groups",
            }[fault]
            old.payload = {**old.payload, key: None}
    with DB() as db:
        assert not features_for(db, child, upcoming_id)["package_length_failed"]
