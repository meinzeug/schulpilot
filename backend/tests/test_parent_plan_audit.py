"""Parent navigation uses complete data behind bounded previews."""

import uuid

import pytest
from schulpilot.db import DB, Activity, Assignment, LearningMemory, LearningUnit, Usage
from sqlalchemy import func, select
from test_tutor import notebook as _notebook


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


def create_topic(api, book):
    response = api.post(f"/api/children/{book['child']['id']}/assignments",
        json={"subject": "Mathematik", "topic": "Brüche verstehen"},
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 201, response.text
    return response.json()


def test_old_open_round_and_saved_plan_survive_short_history(api, book):
    topic = create_topic(api, book)
    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        unit.assignment_id, unit.goal_revision, unit.status, unit.created = topic["id"], 1, "paused", 1
        db.add(LearningMemory(unit_id=unit.id, child_id=unit.child_id, source_signature="synthetic",
            working={"instructional_plan": {"cursor": 0, "steps": [{"kind": "practice", "reason": "Neue eigene Anwendung.",
                "expected_result": "Eine eigene Antwort."}]}}))
        for index in range(25):
            db.add(LearningUnit(child_id=unit.child_id, assignment_id=topic["id"], goal_revision=1,
                subject=unit.subject, topic=unit.topic, explanation=unit.explanation, questions=unit.questions,
                provider=unit.provider, created=index + 2, status="completed" if index < 11 else "active",
                completed=index + 2 if index < 11 else None))
    route = f"/api/children/{book['child']['id']}/learning-plan"
    for _ in range(2):
        response = api.get(route)
        assert response.status_code == 200, response.text
        value = response.json()
        row = next(t for t in value["topics"] if t["id"] == topic["id"])
        assert len(row["recent_units"]) == 10
        assert book["unit_id"] not in {u["id"] for u in row["recent_units"]}
        assert row["available_unit"] == {"id": book["unit_id"], "status": "paused"}
        assert [p["unit_id"] for p in value["instructional_plans"]] == [book["unit_id"]]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_completing_topic_rejects_stale_revision_and_keeps_rounds(api, book):
    topic = create_topic(api, book)
    route = f"/api/children/{book['child']['id']}/assignments/{topic['id']}"
    with DB.begin() as db:
        db.get(LearningUnit, book["unit_id"]).assignment_id = topic["id"]
    body = {"subject": "Mathematik", "topic": "Geänderter Bruchauftrag", "revision": 1}
    assert api.put(route, json=body).json()["revision"] == 2
    assert api.post(route + "/complete", json={"revision": 1}).status_code == 409
    with DB() as db:
        assert not db.get(Assignment, topic["id"]).done
        assert not db.scalar(select(Activity).where(Activity.kind == "parent_goal_completed"))
    assert book["client"].post(route + "/complete", json={"revision": 2}).status_code == 403
    assert api.post(route + "/complete", json={"revision": 2}).status_code == 200
    with DB() as db:
        assignment = db.get(Assignment, topic["id"])
        assert assignment.done and assignment.revision == 3
        assert db.get(LearningUnit, book["unit_id"]).assignment_id == topic["id"]
    assert not api.get(f"/api/children/{book['child']['id']}/learning-plan").json()["topics"]
    assert api.get(f"/api/children/{book['child']['id']}/learning-plan?include_completed=true").json()["topics"][0]["done"]


def test_legacy_complete_is_compatible_and_does_not_duplicate_activity(api, book):
    topic = create_topic(api, book)
    route = f"/api/children/{book['child']['id']}/assignments/{topic['id']}/complete"
    for _ in range(2):
        assert api.post(route).status_code == 200
    with DB() as db:
        assert db.get(Assignment, topic["id"]).revision == 2
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "parent_goal_completed")) == 1
