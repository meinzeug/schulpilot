"""Real API + worker, isolated artificial family and canonical mocked provider."""
import copy
from threading import Barrier

import pytest
from schulpilot import school_preparation, worker
from schulpilot.db import DB, Attempt, Job, LearningUnit, Material, ProviderConfig, SchoolDay, Usage
from schulpilot.providers import Result
from sqlalchemy import func, select
from test_package_parts_worker import artificial_day, bounded_output, preparation, run_one, snapshot


def staged(api, household, monkeypatch):
    day_id, child, old = artificial_day(api, household)
    calls = []
    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        calls.append(copy.deepcopy(payload))
        return Result(bounded_output(payload), 20, 40, 101, cost_source="reported")
    monkeypatch.setattr(worker, "request_provider", provider)
    preparation(api, day_id, "prefix-initial-prepare")
    run_one()
    return day_id, child, old, calls


def publish(api, household, day_id, *, key="prefix-explicit-publish", digest=None, actor=None):
    state = snapshot(day_id)
    return api.post(f"/api/school-days/{day_id}/publish-ready-parts",
        headers={"Idempotency-Key": key, "X-Schulpilot-Account": actor or household[0]["id"]},
        json={"plan_digest": digest or state["package_plan"]["digest"]})


def test_one_of_three_prefix_is_usable_without_provider_or_claiming_complete(api, household, monkeypatch):
    day_id, child, old, calls = staged(api, household, monkeypatch)
    before = api.get(f"/api/school-days/{day_id}").json()
    assert before["preparation"]["can_publish_parts"] is True
    assert before["preparation"]["ready_prefix_parts"] == 1 and before["units"] == []
    state_before = snapshot(day_id)
    with DB() as db:
        counts = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt)]
    result = publish(api, household, day_id)
    assert result.status_code == 200, result.text
    data = result.json()
    assert data["published_parts"] == 1 and data["total_parts"] == 3 and not data["complete"]
    assert len(data["unit_ids"]) == 1 and len(calls) == 1
    after = api.get(f"/api/school-days/{day_id}").json()
    assert after["stage"] == "review" and after["preparation"]["status"] == "processing"
    assert after["preparation"]["completed_parts"] == 1 and after["preparation"]["published_parts"] == 1
    assert after["preparation"]["published_unit_ids"] == data["unit_ids"]
    assert len(after["units"]) == 1 and after["units"][0]["id"] == data["unit_ids"][0]
    state = snapshot(day_id)
    assert state["package_plan"] == state_before["package_plan"]
    assert state["package_part_attempts"] == state_before["package_part_attempts"]
    assert state["package_outputs"] == {} and "output" not in state["package_publications"]["0"]
    assert "context" not in state["package_publications"]["0"]
    assert "package_outputs" not in after["preparation"] and "output_sha256" not in str(after["preparation"])
    with DB() as db:
        assert [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt)] == counts
        day = db.get(SchoolDay, day_id)
        assert school_preparation._current_plan(db, day, db.get(__import__("schulpilot.db", fromlist=["Child"]).Child, child["id"]), day.preparation)
        assert data["unit_ids"][0] in [block.get("unit_id") for block in day.learning_plan["blocks"]]


def test_replay_then_finalization_reuses_started_unit_and_preserves_answer(api, household, monkeypatch):
    day_id, child, old, calls = staged(api, household, monkeypatch)
    first = publish(api, household, day_id)
    assert first.status_code == 200, first.text
    uid = first.json()["unit_ids"][0]
    with DB.begin() as db:
        unit = db.get(LearningUnit, uid)
        original = copy.deepcopy(unit.questions)
        unit.status, unit.active_seconds = "active", 23
        attempt = Attempt(unit_id=uid, question_id=unit.questions[0]["id"], answer="Künstliche Antwort",
            outcome="incorrect", assisted=True, request_key="prefix-artificial-answer")
        db.add(attempt)
        db.flush()
        attempt_id = attempt.id
    replay = publish(api, household, day_id)
    assert replay.status_code == 200 and replay.json()["unit_ids"] == [uid]
    assert publish(api, household, day_id, key="prefix-other-no-new-part").status_code == 409
    run_one()
    run_one()
    ready = api.get(f"/api/school-days/{day_id}").json()
    assert ready["stage"] == "ready" and ready["preparation"]["status"] == "ready"
    assert ready["preparation"]["completed_parts"] == ready["preparation"]["published_parts"] == 3
    assert len(ready["units"]) == 3 and uid in [unit["id"] for unit in ready["units"]]
    assert ready["package_version"] == 1 and len(calls) == 3
    with DB() as db:
        unit, attempt = db.get(LearningUnit, uid), db.get(Attempt, attempt_id)
        assert unit.status == "active" and unit.active_seconds == 23 and unit.questions == original
        assert attempt.answer == "Künstliche Antwort" and attempt.outcome == "incorrect" and attempt.assisted
        assert db.scalar(select(func.count()).select_from(Attempt)) == 2
        assert "package_outputs" not in db.get(SchoolDay, day_id).preparation
    replay = publish(api, household, day_id)
    assert replay.status_code == 200 and replay.json()["unit_ids"] == [uid]
    assert run_one() is None


@pytest.mark.parametrize("fault", ["actor", "plan", "revision", "safe_text", "config", "receipt", "job", "usage"])
def test_stale_or_unbound_prefix_is_refused_atomically(api, household, monkeypatch, fault):
    day_id, child, old, calls = staged(api, household, monkeypatch)
    kwargs = {}
    with DB.begin() as db:
        state = copy.deepcopy(db.get(SchoolDay, day_id).preparation)
        if fault == "actor":
            kwargs["actor"] = "0" * 32
        elif fault == "plan":
            kwargs["digest"] = "0" * 64
        elif fault in ("revision", "safe_text"):
            material = db.get(Material, old["sources"][0]["id"])
            if fault == "revision":
                material.revision += 1
            else:
                material.content += "\nEine andere sichere Quellenfassung."
        elif fault == "config":
            db.get(ProviderConfig, 1).revision += 1
        elif fault == "receipt":
            state["package_outputs"]["0"]["output_sha256"] = "0" * 64
            db.get(SchoolDay, day_id).preparation = state
        elif fault == "job":
            db.get(Job, state["package_outputs"]["0"]["job_id"]).status = "failed"
        else:
            db.scalar(select(Usage).where(Usage.job_id == state["package_outputs"]["0"]["job_id"])).config_revision += 1
    response = publish(api, household, day_id, **kwargs)
    assert response.status_code == 409, response.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit).where(LearningUnit.school_day_id == day_id)) == 0
        assert db.get(SchoolDay, day_id).package_version == 0
        assert len(db.get(SchoolDay, day_id).preparation.get("package_outputs", {})) == 1
    assert len(calls) == 1


def test_published_unit_is_not_recreated_after_explicit_erasure(api, household, monkeypatch):
    from schulpilot.db import Child
    from schulpilot.package_publication import publication_records
    from schulpilot.unit_erasure import remove

    day_id, child, old, calls = staged(api, household, monkeypatch)
    response = publish(api, household, day_id)
    assert response.status_code == 200, response.text
    uid = response.json()["unit_ids"][0]
    with DB.begin() as db:
        remove(db, db.get(Child, child["id"]), [uid])
        db.flush()
        day = db.get(SchoolDay, day_id)
        rows = publication_records(day.preparation, day.preparation["package_plan"])
        assert rows["0"]["deleted"] and "0" not in day.preparation.get("package_outputs", {})
    assert publish(api, household, day_id, key="prefix-after-erasure").status_code == 409
    with DB() as db:
        assert db.get(LearningUnit, uid) is None
    assert len(calls) == 1


def test_failed_later_part_stays_failed_while_validated_prefix_can_be_used(api, household, monkeypatch):
    from schulpilot.providers import ProviderError

    day_id, child, old, calls = staged(api, household, monkeypatch)
    def failure(*args, **kwargs):
        raise ProviderError("Künstlicher gebundener Folgefehler.", code="invalid_output",
            billing_result=Result({}, 10, 20, 137, cost_source="reported"))
    monkeypatch.setattr(worker, "request_provider", failure)
    run_one()
    response = publish(api, household, day_id)
    assert response.status_code == 200, response.text
    assert response.json()["preparation"]["status"] == "failed"
    assert response.json()["published_parts"] == 1 and not response.json()["complete"]
    assert run_one() is None


def test_two_parallel_requests_publish_exactly_once_under_real_child_row_lock(api, household, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor

    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.db import engine
    from schulpilot.main import app

    if engine.dialect.name != "postgresql":
        pytest.skip("Requires PostgreSQL row locks")
    day_id, child, old, calls = staged(api, household, monkeypatch)
    digest = snapshot(day_id)["package_plan"]["digest"]
    headers = {**HEADERS, "Authorization": api.headers["Authorization"], "X-Schulpilot-Account": household[0]["id"]}
    barrier = Barrier(2)
    def request(index):
        with TestClient(app, headers=headers) as client:
            barrier.wait(timeout=10)
            result = client.post(f"/api/school-days/{day_id}/publish-ready-parts",
                json={"plan_digest": digest}, headers={"Idempotency-Key": "prefix-concurrent-same-key"})
            assert result.status_code == 200, result.text
            return result.json()["unit_ids"]
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(request, range(2)))
    assert results[0] == results[1] and len(results[0]) == 1 and len(calls) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit).where(LearningUnit.school_day_id == day_id)) == 1
        assert db.get(SchoolDay, day_id).package_version == 1
