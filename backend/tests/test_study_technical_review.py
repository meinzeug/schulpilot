"""Reload-safe technical cap projection is read-only, not a retry override."""
import copy

import pytest
from schulpilot import study_path
from schulpilot.db import DB, Activity, Job, LearningUnit, SchoolDay, Usage, uid
from schulpilot.providers import ProviderError, Result
from sqlalchemy import func, select
from test_study_path import create, finish, generate, path
from test_study_path import study as _study

study = _study


def capped(study, monkeypatch):
    plan = create(study)
    block = plan["next_block_id"]
    calls = []
    def failure(*args, **kwargs):
        calls.append(True)
        raise ProviderError("Künstliche unvollständige Ausgabe.", code="invalid_output",
            billing_result=Result({}, 0, 0, 0, cost_source="cancelled"))
    monkeypatch.setattr(study_path, "request_provider", failure)
    for _ in range(3):
        response = generate(study, block)
        assert response.status_code == 202, response.text
        finish()
    assert len(calls) == 3
    return block, calls


def test_three_actual_failed_jobs_project_technical_review_on_repeated_readonly_get(study, monkeypatch):
    block, calls = capped(study, monkeypatch)
    with DB() as db:
        before = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)]
        plan = copy.deepcopy(db.get(SchoolDay, study["day_id"]).learning_plan)
    for _ in range(3):
        result = study["client"].get(path(study)).json()
        assert result["technical_review_required"] and not result["can_continue"]
        assert result["block_reason"] == study_path.TECHNICAL_REVIEW_MESSAGE
        assert "Eltern" not in result["block_reason"]
    assert generate(study, block).status_code == 409
    with DB() as db:
        assert [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)] == before
        assert db.get(SchoolDay, study["day_id"]).learning_plan == plan
    assert len(calls) == 3


@pytest.mark.parametrize("status", ["queued", "running"])
def test_real_bound_operator_job_after_cap_is_pending_not_a_deadend(study, monkeypatch, status):
    block, calls = capped(study, monkeypatch)
    with DB.begin() as db:
        old = db.scalar(select(Job).where(Job.child_id == study["child"]["id"]).order_by(Job.created.desc()).limit(1))
        repair = Job(id=uid(), child_id=old.child_id, kind="study_block", status=status,
            idempotency="artificial-explicit-operator-once", payload=copy.deepcopy(old.payload))
        db.add(repair)
        day = db.get(SchoolDay, study["day_id"])
        plan = copy.deepcopy(day.learning_plan)
        next(value for value in plan["blocks"] if value["id"] == block)["job_id"] = repair.id
        day.learning_plan = plan
    value = study["client"].get(path(study)).json()
    assert not value["technical_review_required"]
    assert value["blocks"][0]["status"] == "generating"
    assert value["blocks"][0]["error"] is None and len(calls) == 3


def test_existing_saved_round_is_startable_even_with_historical_failed_attempts(study, monkeypatch):
    block, calls = capped(study, monkeypatch)
    with DB.begin() as db:
        unit = LearningUnit(child_id=study["child"]["id"], school_day_id=study["day_id"],
            subject="Sachunterricht", topic="Künstliche gespeicherte Runde", explanation="Die Sonne ist ein Stern.",
            questions=[{"id":"q1","type":"short","prompt":"Was ist die Sonne?","answer":"Stern", "options":[],"accepted":[],"hints":["Lies die Quelle."],"explanation":"Die Sonne ist ein Stern."}],
            provider="synthetic", synthetic=False)
        db.add(unit)
        db.flush()
        day = db.get(SchoolDay, study["day_id"])
        plan = copy.deepcopy(day.learning_plan)
        next(value for value in plan["blocks"] if value["id"] == block)["unit_id"] = unit.id
        day.learning_plan = plan
    value = study["client"].get(path(study)).json()
    assert not value["technical_review_required"] and value["can_continue"]
    assert value["blocks"][0]["status"] == "ready" and len(calls) == 3
