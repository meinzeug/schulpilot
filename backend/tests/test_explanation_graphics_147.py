"""Explicit explanations open their own hint graphic, never another answer."""
import copy
import json

import pytest
from schulpilot.db import DB, Activity, Attempt, Child, LearningUnit, Material, UnitSource, Usage
from schulpilot.visual_references import remember, with_visual_context
from test_visual_references import SOURCE, question, step


@pytest.fixture
def staged(api, household, request):
    _, child = household
    stage = request.param
    first = question()
    first["explanation_steps"] = [step(stage)]
    second = {**copy.deepcopy(question()), "id": "q2"}
    data = {"subject": "Mathematik", "topic": "Brüche", "explanation": SOURCE,
        "explanation_steps": [step()], "questions": [first, second]}
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstliche geprüfte Quelle", subject="Mathematik",
            topic="Brüche", content=SOURCE, confirmed=True, status="confirmed", uncertainties=[], homework=[])
        db.add(material)
        db.flush()
        unit = LearningUnit(child_id=child["id"], material_id=material.id, subject="Mathematik", topic="Brüche",
            explanation=SOURCE, questions=data["questions"], status="paused", provider="own-fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        db.flush()
        payload = with_visual_context(db, db.get(Child, child["id"]), {"material": {"subject": "Mathematik",
            "topic": "Brüche", "content": SOURCE}}, [material])
        remember(db, unit, data, payload)
        identifiers = unit.id, material.id
    login = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200
    api.headers["Authorization"] = "Bearer " + login.json()["token"]
    assert api.post(f"/api/units/{identifiers[0]}/start").status_code == 200
    return identifiers, stage


@pytest.mark.parametrize("staged", ["hint1", "hint2", "hint3", "solution"], indirect=True)
def test_explicit_api_explanation_returns_full_graphic_after_no_hint_and_records_only_help(api, staged):
    (uid, _), stage = staged
    before = api.get(f"/api/units/{uid}").json()
    assert all(q["explanation_steps"] == [] for q in before["questions"])
    with DB() as db:
        original = copy.deepcopy(db.get(LearningUnit, uid).questions)
        usage_before = db.query(Usage).count()
    response = api.post(f"/api/units/{uid}/explanation", json={"question_id": "q1"})
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["question_id"] == "q1"
    assert len(value["explanation_steps"]) == 1
    saved = value["explanation_steps"][0]
    assert saved["disclosure"] == stage
    assert len(saved["presentation"]["blocks"]) == 1
    assert saved["presentation"]["blocks"][0]["disclosure"] == stage
    assert "source_excerpt" not in json.dumps(value)
    assert api.get(f"/api/units/{uid}").json()["questions"][1]["explanation_steps"] == []
    with DB() as db:
        assert db.query(Attempt).count() == 0 and db.query(Usage).count() == usage_before
        assert db.get(LearningUnit, uid).questions == original
        events = db.query(Activity).filter_by(unit_id=uid, kind="explanation").all()
        assert len(events) == 1 and events[0].detail["question_id"] == "q1"
    answer = api.post(f"/api/units/{uid}/questions/q1/answer", json={"answer": "1/2"})
    assert answer.status_code == 200, answer.text
    assert answer.json()["outcome"] == "correct"
    with DB() as db:
        attempt = db.query(Attempt).filter_by(unit_id=uid, question_id="q1").one()
        assert attempt.assisted and db.query(Usage).count() == usage_before


@pytest.mark.parametrize("staged", ["hint2"], indirect=True)
def test_explicit_explanation_does_not_override_source_revision_protection(api, staged):
    (uid, mid), _ = staged
    with DB.begin() as db:
        db.get(Material, mid).revision += 1
    response = api.post(f"/api/units/{uid}/explanation", json={"question_id": "q1"})
    assert response.status_code == 200
    assert response.json()["explanation_steps"] == []
    assert response.json()["explanation_visual_status"] == "incomplete"
