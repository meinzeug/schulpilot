"""Normal artificial family, persisted multi-call parts and actual worker guards.

Only request_provider is mocked. No real provider, push or child answer write.
The existing historical Attempt below is an explicitly artificial DB fixture.
"""
import copy
import json
from pathlib import Path

import pytest
from schulpilot import learning_entry, package_part_output, school_preparation, visual_references, worker
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    SchoolDay,
    UnitSource,
    Usage,
)
from schulpilot.providers import ProviderError, Result, validate_factual_package
from schulpilot.schemas import PackageOutput
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_school_day import allow_synthetic_test_transport

CASE = json.loads((Path(__file__).parents[2] / "testdata/learning_scenes_v1.json").read_text())["cases"][0]


def bounded_output(payload):
    group = payload["selected_groups"][0]
    ref = next(item["ref"] for item in payload["visual_context"]["sources"]
        if item["group_id"] == group["id"])

    def step(stage):
        presentation = copy.deepcopy(CASE["question"]["presentation"])
        for block in presentation["blocks"]:
            block["disclosure"] = stage
            block["scene"]["steps"] = block["scene"]["steps"][:2]
        return {"id": "e1", "text": CASE["source"], "competence_id": None, "disclosure": stage,
            "reference": {"id": "general.source_relation.phases", "version": 1},
            "source_refs": [ref], "presentation": presentation}

    entry = payload.get("learning_entry", {}).get("units", [])
    ids = [item["id"] for item in learning_entry._specs(entry[0], 2)] if entry else ["q1", "q2"]
    first = {**copy.deepcopy(CASE["question"]), "id": ids[0], "presentation": None,
        "explanation_steps": [step("solution")]}
    second = {**copy.deepcopy(first), "id": ids[1],
        "prompt": "Welcher Begriff folgt in der Quelle auf Kondensation?", "answer": "Niederschlag"}
    value = {"units": [{"group_id": group["id"], "subject": group["subject"],
        "topic": "Künstlicher Wasserkreislauf", "explanation": CASE["source"],
        "explanation_steps": [step("given")], "questions": [first, second]}]}
    # The mock supplies canonical output; these are the normal post-provider
    # validators, never substitute fixtures or a disabled validation gate.
    value = PackageOutput.model_validate(value).model_dump(mode="json")
    package_part_output.validate(value)
    validate_factual_package(value, payload, allow_matching=True)
    learning_entry.validate_entry_output(payload, value)
    with DB() as db:
        visual_references.validate_output(db, value, payload)
    return value


def preparation(api, day_id, key):
    response = api.post(f"/api/school-days/{day_id}/prepare", headers={
        "Idempotency-Key": key, "X-Schulpilot-Capabilities": "visual-v1,learning-entry-v1"})
    assert response.status_code == 202, response.text
    return response.json()["preparation"]


def run_one():
    school_preparation.advance_one()
    with DB() as db:
        job_id = worker.claim(db)
    if job_id:
        worker.process(job_id)
    school_preparation.advance_one()
    return job_id


def snapshot(day_id):
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        return copy.deepcopy(day.preparation)


def artificial_day(api, household):
    owner, child = household
    allow_synthetic_test_transport()
    response = api.post(f"/api/children/{child['id']}/school-day/today")
    assert response.status_code == 201, response.text
    day_id = response.json()["id"]
    with DB.begin() as db:
        assert db.get(Family, owner["families"][0]["id"]).synthetic is False
        db.get(Child, child["id"]).preferences = {"weekdays": list(range(7)), "daily_minutes": 40,
            "weekly_minutes": 240, "session_minutes": 8, "quiet_start": 0, "quiet_end": 0}
        day = db.get(SchoolDay, day_id)
        day.stage = "review"
        materials = [Material(child_id=child["id"], school_day_id=day_id, page_number=index + 1,
            title=f"Künstliche Heftseite {index + 1}", subject=CASE["subject"],
            topic="Künstlicher Wasserkreislauf", content=CASE["source"], confirmed=True,
            status="confirmed", uncertainties=[], homework=[], purpose="notebook", synthetic=False)
            for index in range(7)]
        db.add_all(materials)
        old = LearningUnit(child_id=child["id"], subject="Englisch", topic="Künstlicher Altbestand",
            explanation="Historischer künstlicher Testbestand, kein echter Lernerfolg.",
            questions=[{"id": "old", "type": "short", "prompt": "Künstliche Altfrage", "options": [],
                "answer": "Alt", "accepted": [], "hints": ["Künstlicher Hinweis"], "explanation": "Altbestand"}],
            status="active", provider="synthetic", synthetic=False, active_seconds=17)
        db.add(old)
        db.flush()
        old_attempt = Attempt(unit_id=old.id, question_id="old", answer="Künstliche Altantwort",
            outcome="uncertain", assisted=False, request_key="historical-artificial-attempt")
        db.add(old_attempt)
        db.flush()
        identities = {"unit": old.id, "attempt": old_attempt.id,
            "sources": [{"id": material.id, "revision": material.revision} for material in materials]}
    return day_id, child, identities


@pytest.mark.parametrize("fail_second", [False, True], ids=["complete-path", "fail-stop-explicit-retry"])
def test_normal_parts_stage_privately_then_publish_once_with_graphics_and_preserved_history(
    api, household, monkeypatch, fail_second
):
    day_id, child, old = artificial_day(api, household)
    calls, failed_once = [], False

    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        nonlocal failed_once
        assert function == "package" and image_bytes is None and synthetic_fixture is False
        assert len(payload["selected_groups"]) == 1 and 1 <= len(payload["materials"]) <= 3
        calls.append(copy.deepcopy(payload))
        if fail_second and payload["package_partition"] == 1 and not failed_once:
            failed_once = True
            raise ProviderError("Künstlicher abgerechneter Teilfehler, kein automatischer Retry.",
                code="invalid_output", billing_result=Result({}, 10, 20, 137, cost_source="reported"))
        return Result(bounded_output(payload), 20, 40, 101, cost_source="reported")

    monkeypatch.setattr(worker, "request_provider", provider)
    initial = preparation(api, day_id, "parts-first-explicit")
    assert initial["status"] == "processing" and initial["phase"] == "package"
    assert initial["total_parts"] == 3 and initial["completed_parts"] == 0
    first_job = run_one()
    assert first_job and [call["package_partition"] for call in calls] == [0]
    staged = snapshot(day_id)
    first_receipt = copy.deepcopy(staged["package_outputs"]["0"])
    assert len(staged["package_outputs"]) == 1
    assert first_receipt["context"]["visual_context"]["required"] is True
    assert first_receipt["context"]["learning_entry"]["units"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.unit_id.is_not(None))) == 0
        assert db.get(SchoolDay, day_id).stage == "review"
        job = db.get(Job, first_job)
        assert set(job.result) == {"school_day_id", "package_partition", "completed_parts", "total_parts"}
    before_poll = len(calls)
    for _ in range(3):
        response = api.get(f"/api/school-days/{day_id}")
        assert response.status_code == 200
        public = response.json()
        assert public["units"] == [] and public["preparation"]["completed_parts"] == 1
        assert not {"package_outputs", "package_plan", "visual_context", "learning_entry"}.intersection(public["preparation"])
        assert "output_sha256" not in response.text and "context_sha256" not in response.text
    assert len(calls) == before_poll
    assert preparation(api, day_id, "parts-processing-replay")["status"] == "processing"
    assert len(calls) == before_poll

    second_job = run_one()
    assert second_job and [call["package_partition"] for call in calls] == [0, 1]
    if fail_second:
        failed_state = snapshot(day_id)
        assert failed_state["status"] == "failed"
        assert failed_state["package_outputs"]["0"] == first_receipt
        for _ in range(3):
            assert run_one() is None
            assert api.get(f"/api/school-days/{day_id}").json()["preparation"]["status"] == "failed"
        assert [call["package_partition"] for call in calls] == [0, 1]
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
            failed_usage = db.scalar(select(Usage).where(Usage.job_id == second_job))
            assert failed_usage.status == "failed_billed" and failed_usage.cost_micros == 137
        retry = preparation(api, day_id, "parts-explicit-retry-missing-only")
        assert retry["completed_parts"] == 1 and retry["status"] == "processing"
        assert snapshot(day_id)["package_outputs"]["0"] == first_receipt
        assert run_one()
        assert [call["package_partition"] for call in calls] == [0, 1, 1]
    assert run_one()
    expected = [0, 1, 1, 2] if fail_second else [0, 1, 2]
    assert [call["package_partition"] for call in calls] == expected
    assert "learning_entry" in calls[0] and all("learning_entry" not in call for call in calls[1:])
    ready = api.get(f"/api/school-days/{day_id}").json()
    assert ready["stage"] == "ready" and ready["package_version"] == 1
    assert ready["preparation"]["status"] == "ready" and ready["preparation"]["completed_parts"] == 3
    assert len(ready["units"]) == 3 and all(unit["status"] == "not_started" for unit in ready["units"])
    assert "package_outputs" not in snapshot(day_id)
    with DB() as db:
        units = list(db.scalars(select(LearningUnit).where(LearningUnit.school_day_id == day_id)))
        assert len(units) == 3 and {unit.package_version for unit in units} == {1}
        assert all(len(unit.questions) == 2 and unit.active_seconds == 0 for unit in units)
        assert all(db.get(UnitVisualSnapshot, unit.id).status == "ready" for unit in units)
        linked = list(db.scalars(select(UnitSource).where(UnitSource.unit_id.in_([unit.id for unit in units]))))
        assert sorted((item.material_id, item.revision) for item in linked) == sorted(
            (item["id"], item["revision"]) for item in old["sources"])
        assert len(linked) == 7
        previous = db.get(LearningUnit, old["unit"])
        attempt = db.get(Attempt, old["attempt"])
        assert previous.status == "active" and previous.active_seconds == 17
        assert attempt.answer == "Künstliche Altantwort" and attempt.outcome == "uncertain"
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        jobs_before = db.scalar(select(func.count()).select_from(Job))
        usages_before = db.scalar(select(func.count()).select_from(Usage))
        assert jobs_before == usages_before == len(expected)
    for key in ("parts-first-explicit", "parts-after-completion"):
        assert preparation(api, day_id, key)["status"] == "ready"
        assert run_one() is None
        assert api.get(f"/api/school-days/{day_id}").json()["package_version"] == 1
    assert len(calls) == len(expected)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == jobs_before
        assert db.scalar(select(func.count()).select_from(Usage)) == usages_before
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 4
