"""Artificial notebook selections, normal reservations and no provider dispatch."""

from copy import deepcopy

import pytest
from conftest import create_child
from schulpilot.db import DB, Attempt, Family, Job, LearningUnit, Material, ProviderConfig, Usage, uid
from schulpilot.model_routing import choose_tier, features_for, job_config
from schulpilot.notebook_routing import LENGTH_MESSAGE, length_failed
from schulpilot.providers import Result, reserve, settle
from sqlalchemy import func, select
from sqlalchemy.orm.attributes import flag_modified
from test_model_routing import setup_policy
from test_notebook_practice import notebook as notebook
from test_notebook_practice import post


@pytest.fixture
def retry(notebook):
    family_id = notebook.parent["families"][0]["id"]
    setup_policy(family_id)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.reserve_micros, config.max_output_tokens = 500000, 8000
        config.routing_policy = {**config.routing_policy, "economy_mode": True, "routes": {
            tier: {**route, "reserve_micros": 150000 if tier == "luna" else 250000,
                   "max_output_tokens": 4000 if tier == "luna" else 8000}
            for tier, route in config.routing_policy["routes"].items()}}
    response = post(notebook, key="notebook-length-initial")
    assert response.status_code == 202, response.text
    old_id = response.json()["id"]
    with DB.begin() as db:
        old = db.get(Job, old_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == old.id))
        assert usage.route_snapshot["tier"] == "luna"
        settle(db, usage, Result({}, 9693, 952, 3870), failed=True)
        old.status, old.error_code, old.error = "failed", "invalid_output", LENGTH_MESSAGE
        candidate = Job(child_id=notebook.child["id"], kind="unit", payload=deepcopy(old.payload),
                        idempotency=uid())
        db.add(candidate)
        db.flush()
        return {"book": notebook, "family": family_id, "old": old_id,
                "candidate": candidate.id, "usage": usage.id}


def test_recorded_notebook_need_is_read_only_and_normal_reservation_preserves_history(retry, monkeypatch):
    monkeypatch.setattr("schulpilot.providers.request_provider", lambda *_a, **_kw: pytest.fail("No provider"))
    book = retry["book"]
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        policy = deepcopy(config.routing_policy)
        old = db.get(Job, retry["old"])
        previous_payload = deepcopy(old.payload)
        previous_usage = db.get(Usage, retry["usage"])
        old_money = (previous_usage.cost_micros, previous_usage.settlement_version,
                     previous_usage.status, deepcopy(previous_usage.route_snapshot))
        old_answers = list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome)))
        old_units = db.scalar(select(func.count()).select_from(LearningUnit))
        facts = features_for(db, book.child["id"], retry["candidate"])
        assert facts["notebook_length_failed"] and not facts["study_length_failed"]
        assert choose_tier("unit", facts, economy=True) == ("sol", "recorded_notebook_output_length")
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        usage = reserve(db, db.get(Family, retry["family"]), book.child["id"], retry["candidate"], "unit")
        bound = job_config(db, db.get(Job, retry["candidate"]), "unit")
        assert usage.route_snapshot["tier"] == "sol"
        assert usage.route_snapshot["reason"] == "recorded_notebook_output_length"
        assert usage.reserved_micros == bound.reserve_micros == 250000
        assert bound.max_output_tokens == 8000 and bound.reasoning_effort == "medium"
        assert config.routing_policy == policy and old.payload == previous_payload and old.status == "failed"
        assert (previous_usage.cost_micros, previous_usage.settlement_version,
                previous_usage.status, previous_usage.route_snapshot) == old_money
        assert list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome))) == old_answers
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == old_units
        # A later source change does not silently re-route an existing reservation.
        db.get(Material, book.refs[0]["id"]).revision += 1
        assert not features_for(db, book.child["id"], retry["candidate"])["notebook_length_failed"]
        assert job_config(db, db.get(Job, retry["candidate"]), "unit").model == usage.model


def test_explicit_new_api_request_uses_recorded_route_and_idempotent_replay_never_reserves_twice(retry):
    with DB.begin() as db:
        db.delete(db.get(Job, retry["candidate"]))  # Only this unreserved synthetic candidate.
    first = post(retry["book"], key="notebook-length-conscious-repeat")
    second = post(retry["book"], key="notebook-length-conscious-repeat")
    assert first.status_code == second.status_code == 202 and first.json() == second.json()
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == first.json()["id"]))
        assert usage.route_snapshot["reason"] == "recorded_notebook_output_length"
        assert usage.reserved_micros == 250000
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
        assert db.get(Job, retry["old"]).status == "failed"


def test_complete_recorded_message_allows_only_whitespace_normalization(retry):
    with DB.begin() as db:
        old = db.get(Job, retry["old"])
        old.error = "\n" + old.error.replace(" ", "  ") + "\n"
    with DB() as db:
        assert length_failed(db, retry["book"].child["id"], db.get(Job, retry["candidate"]))


@pytest.mark.parametrize("fault", [
    "source_revision", "safe_content_same_revision", "unconfirmed", "foreign_source",
    "different_image_anchor_revision", "source_order", "different_count", "different_signature",
    "different_subject", "missing_notebook_contract", "partial_error", "different_error_code",
    "not_failed", "foreign_job", "old_other_kind", "target_other_kind", "target_running",
    "old_boolean_revision", "target_boolean_revision", "fixture_source", "exam_source",
])
def test_recorded_need_cannot_cross_selection_revision_count_owner_contract_or_complete_error(retry, api, fault):
    book = retry["book"]
    sibling = create_child(api, book.parent, "notebook-route-sibling") if fault.startswith("foreign") else None
    with DB.begin() as db:
        old, candidate = db.get(Job, retry["old"]), db.get(Job, retry["candidate"])
        material = db.get(Material, book.refs[0]["id"])
        payload = deepcopy(old.payload)
        if fault == "source_revision":
            material.revision += 1
        elif fault == "safe_content_same_revision":
            material.content += " Neuer bestätigter künstlicher Satz."
        elif fault == "unconfirmed":
            material.confirmed = False
        elif fault == "foreign_source":
            material.child_id = sibling["id"]
        elif fault == "different_image_anchor_revision":
            payload["material_revision"] += 1
        elif fault == "source_order":
            payload["sources"] = list(reversed(payload["sources"]))
        elif fault == "different_count":
            payload["notebook_practice"]["question_count"] = 3
        elif fault == "different_signature":
            payload["notebook_practice"]["source_signature"] = "e" * 64
        elif fault == "different_subject":
            payload["notebook_practice"]["subject_id"] = "e" * 32
        elif fault == "missing_notebook_contract":
            payload.pop("notebook_practice")
        elif fault == "partial_error":
            old.error = "Die KI hat die begrenzte Ausgabelänge erreicht."
        elif fault == "different_error_code":
            old.error_code = "provider_error"
        elif fault == "not_failed":
            old.status = "completed"
        elif fault == "foreign_job":
            old.child_id = sibling["id"]
        elif fault == "old_other_kind":
            old.kind = "study_block"
        elif fault == "target_other_kind":
            candidate.kind = "coach_practice"
        elif fault == "target_running":
            candidate.status = "running"
        elif fault == "old_boolean_revision":
            payload["material_revision"] = True
        elif fault == "target_boolean_revision":
            candidate.payload = {**candidate.payload, "material_revision": True}
            flag_modified(candidate, "payload")  # Python True == 1 must not suppress this corrupt JSON fixture.
        elif fault == "fixture_source":
            material.fixture_id = "synthetic-fixture"
        else:
            material.purpose = "exam"
        old.payload = payload
        if fault == "old_boolean_revision":
            flag_modified(old, "payload")
    with DB() as db:
        if fault in ("old_boolean_revision", "target_boolean_revision"):
            identifier = retry["old"] if fault == "old_boolean_revision" else retry["candidate"]
            assert type(db.get(Job, identifier).payload["material_revision"]) is bool
        assert not length_failed(db, book.child["id"], db.get(Job, retry["candidate"]))
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_no_recorded_failure_retains_small_scope_economy_route(retry):
    with DB.begin() as db:
        db.get(Job, retry["old"]).error = "Anderer geschlossener künstlicher Fehler."
    with DB() as db:
        facts = features_for(db, retry["book"].child["id"], retry["candidate"])
        assert not facts["notebook_length_failed"]
        assert choose_tier("unit", facts, economy=True) == ("luna", "focused_source_practice")
