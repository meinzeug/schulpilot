"""Synthetic persistent part coordination; every provider boundary is mocked."""
import copy
import uuid
from unittest.mock import patch

import pytest
from schulpilot import package_partitions
from schulpilot import school_preparation as prep
from schulpilot.db import (
    DB,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Material,
    Message,
    ProviderConfig,
    SchoolDay,
    Session,
    Usage,
)
from schulpilot.provider_attempts import counts
from schulpilot.providers import Result, settle
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_model_routing import setup_policy
from test_package_output_transport import fixture

LENGTH_ERROR = ("Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
                "kein automatischer Wiederholungsversuch.")


def make_day(household, count=4):
    owner, child_data = household
    setup_policy(owner["families"][0]["id"])
    data, context, _ = fixture()
    with DB.begin() as db:
        child = db.get(Child, child_data["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 40, "weekly_minutes": 240, "session_minutes": 10}
        day = SchoolDay(child_id=child.id, school_date="2026-10-25", stage="review", revision=1)
        db.add(day)
        db.flush()
        db.add_all([Material(child_id=child.id, school_day_id=day.id, page_number=i + 1,
            subject=data["units"][0]["subject"], topic="Künstliches Thema", title="Künstliche Seite",
            content=context["visual_context"]["sources"][0]["content"], confirmed=True,
            status="confirmed", purpose="notebook", synthetic=False) for i in range(count)])
        return day.id


def submit(api, day_id, key=None):
    response = api.post(f"/api/school-days/{day_id}/prepare", headers={"Idempotency-Key": key or uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    return response.json()["preparation"]


def count_jobs():
    with DB() as db:
        return db.scalar(select(func.count()).select_from(Job))


def complete_part(day_id):
    """Stand in for an already domain-validated worker output, not a real AI call."""
    data, _, _ = fixture()
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        state = prep._state(day)
        job = db.get(Job, state["job_id"])
        part = state["package_plan"]["parts"][job.payload["package_partition"]]
        unit = copy.deepcopy(data["units"][0])
        unit.update(group_id=part["group"]["id"], subject=part["group"]["subject"])
        unit["questions"] = unit["questions"][:2]
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        state = package_partitions.store_validated_part(state, state["package_plan"], part["index"], {"units": [unit]},
            job_id=job.id, provider=usage.provider, model=usage.model, config_revision=usage.config_revision)
        prep._write(day, state)
        settle(db, usage, Result({}, 10, 20, 1, cost_source="reported"))
        job.status, job.result = "completed", {"completed_parts": len(state["package_outputs"])}
        return job.id


def fail_part(day_id):
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        job = db.get(Job, day.preparation["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        settle(db, usage, Result({}, 10, 20, 1, cost_source="reported"), failed=True)
        job.status, job.error, job.error_code = "failed", LENGTH_ERROR, "invalid_output"
        return job.id


def test_small_new_singleton_uses_source_bound_part_and_reserves_once(api, household):
    day_id = make_day(household, 3)
    value = submit(api, day_id)
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        job = db.get(Job, state["job_id"])
        assert state["package_parts_version"] == 1 and state["single_part_contract"] is True
        assert job.payload.get("package_partition") == 0
        assert len(job.payload["groups"][0]["material_ids"]) == 3
    assert value["total_parts"] == 1 and value["active_part"] == 0 and count_jobs() == 1
    assert submit(api, day_id)["job"]["id"] == value["job"]["id"]
    assert count_jobs() == 1


def test_multi_part_submit_reserves_one_normal_job_replays_and_gets_never_advance(api, household):
    day_id = make_day(household, 7)
    value = submit(api, day_id, "one-conscious-submit")
    assert value["total_parts"] == 3 and value["completed_parts"] == 0 and value["active_part"] == 0
    for _ in range(3):
        assert api.get(f"/api/school-days/{day_id}").status_code == 200
    assert submit(api, day_id, "one-conscious-submit") == value
    assert submit(api, day_id)["job"]["id"] == value["job"]["id"]
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        job = db.get(Job, day.preparation["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        assert usage.status == "reserved" and usage.function == "package"
        assert job.payload["sources"] == prep._sources(db, day)
        assert len(job.payload["package_partition_sources"]) == 3
        assert job.payload["groups"] == [day.preparation["package_plan"]["parts"][0]["group"]]
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
    assert count_jobs() == 1


def test_completed_part_resumes_in_next_transaction_without_early_unit(api, household):
    day_id = make_day(household, 7)
    submit(api, day_id)
    first = complete_part(day_id)
    assert count_jobs() == 1
    before = api.get(f"/api/school-days/{day_id}").json()["preparation"]
    assert before["completed_parts"] == 1 and count_jobs() == 1
    prep.advance(day_id)
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        job = db.get(Job, day.preparation["job_id"])
        assert job.id != first and job.payload["package_partition"] == 1
        assert len(day.preparation["package_outputs"]) == 1
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
    assert count_jobs() == 2


def test_failed_part_stops_and_conscious_retry_reuses_completed_part_with_two_attempt_limit(api, household):
    day_id = make_day(household)
    submit(api, day_id)
    first = complete_part(day_id)
    prep.advance(day_id)
    failed = fail_part(day_id)
    prep.advance(day_id)
    for _ in range(2):
        prep.advance(day_id)
    assert count_jobs() == 2
    value = submit(api, day_id)
    assert value["active_part"] == 1 and value["completed_parts"] == 1 and count_jobs() == 3
    fail_part(day_id)
    prep.advance(day_id)
    value = api.get(f"/api/school-days/{day_id}").json()["preparation"]
    assert value["can_retry"] is False
    submit(api, day_id)  # A fresh request key cannot gain a third paid attempt.
    assert count_jobs() == 3
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["package_outputs"]["0"]["job_id"] == first
        assert db.get(Job, failed).status == "failed"
        assert len(list(db.scalars(select(Usage)))) == 3


@pytest.mark.parametrize("fault", ["source", "safe_content", "config", "planning", "session", "family"])
def test_changed_context_never_queues_next_part(api, household, fault):
    day_id = make_day(household)
    submit(api, day_id)
    complete_part(day_id)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        state = prep._state(day)
        child = db.get(Child, day.child_id)
        material = db.get(Material, state["sources"][0]["id"])
        if fault == "source":
            material.revision += 1
        elif fault == "safe_content":
            material.content += " Neue ungeprüfte Fassung."
        elif fault == "config":
            db.get(ProviderConfig, 1).revision += 1
        elif fault == "planning":
            child.preferences = {**child.preferences, "session_minutes": 20}
        elif fault == "session":
            db.get(Session, state["session_id"]).revoked = True
        else:
            state["family_id"] = "f" * 32
            prep._write(day, state)
    prep.advance(day_id)
    assert count_jobs() == 1
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["status"] == "blocked"
        if fault in ("source", "safe_content", "config", "planning"):
            assert "package_outputs" not in state and "package_plan" not in state


def test_context_change_conscious_submit_discards_old_private_outputs_and_binds_new_plan(api, household):
    day_id = make_day(household)
    submit(api, day_id)
    complete_part(day_id)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        old_digest = day.preparation["package_plan"]["digest"]
        db.get(ProviderConfig, 1).revision += 1
    prep.advance(day_id)
    value = submit(api, day_id)
    assert value["completed_parts"] == 0 and count_jobs() == 2
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["package_plan"]["digest"] != old_digest and state["package_outputs"] == {}


def test_source_delete_scrubs_private_outputs_public_projection_has_only_progress(api, household):
    day_id = make_day(household)
    submit(api, day_id)
    complete_part(day_id)
    value = api.get(f"/api/school-days/{day_id}").json()["preparation"]
    assert value["completed_parts"] == 1
    assert not {"package_outputs", "package_plan", "output", "context", "sources", "session_id"} & value.keys()
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        db.delete(db.get(Material, day.preparation["sources"][0]["id"]))
        day.revision += 1
        db.flush()
        prep.sources_removed(db, day)
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert not set(prep._PART_KEYS) & state.keys()
        assert state["package_part_attempts"] and state["package_parts_version"] == 1
    assert count_jobs() == 1


def test_missing_completed_receipt_does_not_auto_repeat_paid_part(api, household):
    day_id = make_day(household)
    submit(api, day_id)
    with DB.begin() as db:
        job = db.get(Job, db.get(SchoolDay, day_id).preparation["job_id"])
        job.status = "completed"
    prep.advance(day_id)
    with DB() as db:
        assert db.get(SchoolDay, day_id).preparation["status"] == "blocked"
    assert count_jobs() == 1


def seed_legacy_failure(api, household, *, stamp=False, error=LENGTH_ERROR):
    day_id = make_day(household, 1)
    # Model a job created by a deployed legacy version, before singleton
    # contracts existed. Its attempts must not disappear after an upgrade.
    with patch.object(prep, "_prepare_parts", return_value={}):
        submit(api, day_id)
    fail_part(day_id)
    prep.advance(day_id)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        state = prep._state(day)
        state.pop("single_part_contract", None)
        if not stamp:
            state.pop("package_parts_version")
        state["package_attempts"][prep._fingerprint(state["sources"])] = 3
        prep._write(day, state)
        db.get(Job, state["job_id"]).error = error
    return day_id


def test_old_billed_length_failure_migrates_once_even_singleton_without_erasing_history(api, household):
    day_id = seed_legacy_failure(api, household)
    value = api.get(f"/api/school-days/{day_id}").json()["preparation"]
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        assert prep._legacy_part_migration(db, day, prep._state(day)), value
    assert value["can_retry"] is True, value
    value = submit(api, day_id, "migrate-old-once")
    assert value["total_parts"] == 1 and value["active_part"] == 0
    assert submit(api, day_id, "migrate-old-once") == value
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["package_parts_version"] == 1 and max(state["package_attempts"].values()) == 3
        assert len(list(db.scalars(select(Usage)))) == 2
    assert count_jobs() == 2


@pytest.mark.parametrize("stamp,error", [(True, LENGTH_ERROR), (False, "Ein anderer Fehler.")])
def test_fresh_contract_or_nonlength_legacy_cannot_unlock_extra_singleton_attempt(api, household, stamp, error):
    day_id = seed_legacy_failure(api, household, stamp=stamp, error=error)
    value = api.get(f"/api/school-days/{day_id}").json()["preparation"]
    assert value["can_retry"] is False
    submit(api, day_id)
    assert count_jobs() == 1
    with DB() as db:
        assert "package_plan" not in db.get(SchoolDay, day_id).preparation


def test_singleton_flag_cannot_hide_existing_legacy_attempts(api, household):
    day_id = seed_legacy_failure(api, household, stamp=True, error="Ein anderer Fehler.")
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        state = prep._state(day)
        state["single_part_contract"] = True
        # A lost counter must not hide the persisted provider job.
        state["package_attempts"] = {}
        prep._write(day, state)
        child = db.get(Child, day.child_id)
        assert prep._prepare_parts(db, day, child, state, prep._pages(db, day)) == {}
    assert count_jobs() == 1


def test_new_source_snapshot_after_legacy_failure_gets_new_plan_but_retains_attempts(api, household):
    day_id = seed_legacy_failure(api, household, stamp=True, error="Ein anderer Fehler.")
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        old_attempts = copy.deepcopy(day.preparation["package_attempts"])
        first = db.scalar(select(Material).where(Material.school_day_id == day_id))
        db.add(Material(child_id=day.child_id, school_day_id=day_id, page_number=2,
            subject=first.subject, topic=first.topic, title="Weitere künstliche Seite",
            content=first.content + " Neuer belegter Stoff.", confirmed=True, status="confirmed",
            purpose="notebook", synthetic=False))
        day.revision += 1
    value = submit(api, day_id, "new-source-new-singleton")
    assert value["active_part"] == 0 and count_jobs() == 2
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["package_attempts"] == old_attempts
        assert len(state["sources"]) == 2


def test_final_merge_only_once_fresh_state_scrub_and_previous_units_attempts_preserved(api, household, monkeypatch):
    day_id = make_day(household)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        old = LearningUnit(child_id=day.child_id, subject="Englisch", topic="Alte begonnene Runde",
            explanation="Unveränderter alter Text", questions=[], provider="synthetic", status="paused")
        db.add(old)
        db.flush()
        answer = Attempt(unit_id=old.id, question_id="old", answer="Künstliche Antwort", outcome="incorrect")
        db.add(answer)
        db.flush()
        old_id, answer_id = old.id, answer.id
    submit(api, day_id)
    complete_part(day_id)
    prep.advance(day_id)
    complete_part(day_id)
    merged = []

    def save(db, job, outputs, plan):
        day = db.get(SchoolDay, day_id)
        assert len(outputs) == len(plan["parts"]) == 2
        assert len(day.preparation["package_outputs"]) == 2
        merged.append(job.id)
        state = prep._state(day)
        state["aggregate_marker"] = "fresh-saver-state"
        prep._write(day, state)
        day.stage, day.package_version = "ready", day.package_version + 1
        job.result = {"unit_ids": ["synthetic-final-id"]}

    monkeypatch.setattr("schulpilot.school_day.save_package_parts", save)
    prep.advance(day_id)
    prep.advance(day_id)
    assert len(merged) == 1 and count_jobs() == 2
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        assert day.preparation["status"] == "ready" and day.preparation["package_completed_parts"] == 2
        assert "package_outputs" not in day.preparation and day.preparation["aggregate_marker"] == "fresh-saver-state"
        assert db.get(LearningUnit, old_id).status == "paused" and db.get(Attempt, answer_id).answer == "Künstliche Antwort"
        assert db.scalar(select(func.count()).select_from(Message).where(Message.kind == "preparation")) == 1


def test_normal_worker_parts_publish_one_version_after_all_calls_only(api, household, monkeypatch):
    day_id = make_day(household)
    data, _, _ = fixture()
    calls = []

    def provider(config, function, payload, *args, **kwargs):
        assert function == "package" and payload["package_partition"] in (0, 1)
        assert len(payload["selected_groups"]) == 1
        assert len(payload["materials"]) == (3 if payload["package_partition"] == 0 else 1)
        unit = copy.deepcopy(data["units"][0])
        unit["group_id"] = payload["selected_groups"][0]["id"]
        unit["questions"] = unit["questions"][:2]
        for item in [unit, *unit["questions"]]:
            for block in item["explanation_steps"][0]["presentation"]["blocks"]:
                block["scene"]["steps"] = block["scene"]["steps"][:2]
        calls.append(payload["package_partition"])
        return Result({"units": [unit]}, 10, 20, 1, cost_source="reported")

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    submit(api, day_id)
    for index in range(2):
        with DB() as db:
            job_id = claim(db)
        assert job_id
        process(job_id)
        with DB() as db:
            assert db.get(Job, job_id).status == "completed", db.get(Job, job_id).error
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        prep.advance(day_id)
    assert calls == [0, 1]
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        units = list(db.scalars(select(LearningUnit)))
        assert day.preparation["status"] == "ready" and "package_outputs" not in day.preparation
        assert len(units) == 2 and {unit.package_version for unit in units} == {1}
        assert all(len(unit.questions) == 2 for unit in units)
        assert len(list(db.scalars(select(Usage)))) == 2


def test_part_attempts_are_isolated_by_plan_and_index_preserving_known_zero_cost(api, household):
    day_id = make_day(household)
    submit(api, day_id)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        state, sources = day.preparation, prep._sources(db, day)
        digest = state["package_plan"]["digest"]
        assert counts(db, day.child_id, "package", sources, 0, partition=(digest, 0)) == (1, 1)
        assert counts(db, day.child_id, "package", sources, 0, partition=(digest, 1)) == (0, 0)
        assert counts(db, day.child_id, "package", sources, 0) == (0, 0)
        job = db.get(Job, state["job_id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        job.status, job.error_code = "failed", "cost_preflight"
        usage.status, usage.cost_source = "failed_not_sent", "cancelled"
        usage.cost_micros = usage.input_tokens = usage.output_tokens = 0
        usage.telemetry = {"pre_dispatch": True}
        assert counts(db, day.child_id, "package", sources, 1, partition=(digest, 0)) == (1, 0)
        usage.cost_source = "unknown"
        assert counts(db, day.child_id, "package", sources, 1, partition=(digest, 0)) == (1, 1)


def test_any_fixed_synthetic_source_stays_out_of_partition_contract():
    class Page:
        confirmed, synthetic = True, False
    first, second = Page(), Page()
    assert prep._parts_enabled([first, second])
    second.synthetic = True
    assert not prep._parts_enabled([first, second])
    assert not prep._parts_enabled([])
