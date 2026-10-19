"""Exercise storage, sessions, public payload, answer replay and parent evidence."""

import copy

import pytest
from schulpilot import coaching
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, SchoolDay, UnitSource, Usage
from schulpilot.families import export_child
from schulpilot.learning_progress import read_ledger, totals
from schulpilot.school_preparation import preparation_data
from schulpilot.subject_content import open_learning_unit
from sqlalchemy import func, select
from test_learning import child_client
from test_providers import configured
from test_subject_content import CASES


@pytest.mark.parametrize("subject", sorted({c["subject"] for c in CASES}))
def test_two_sources_storage_public_graphics_answer_resume_and_parent(subject, api, household, monkeypatch):
    parent, child = household
    examples = [copy.deepcopy(c) for c in CASES if c["subject"] == subject]
    q = [c["question"] for c in examples]
    with DB.begin() as db:
        kid = db.get(Child, child["id"])
        kid.preferences = {"weekdays": list(range(7))}
        material = Material(
            child_id=child["id"],
            title="Künstliche Prüfquelle",
            subject=subject,
            topic=subject,
            content="\n".join(c["source"] for c in examples),
            confirmed=True,
            status="confirmed",
            synthetic=False,
        )
        db.add(material)
        db.flush()
        unit = LearningUnit(
            child_id=child["id"],
            material_id=material.id,
            subject=subject,
            topic=subject,
            questions=q,
            explanation=material.content,
            estimated_minutes=5,
            provider="synthetic-fixture",
            model="local-audit-regression",
            synthetic=False,
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        unit_id = unit.id
    # No external calls in this local lifecycle test.
    monkeypatch.setattr(coaching, "schedule", lambda *a, **kw: None)
    with child_client(
        {"credentials": {"child_username": "test-child", "child_password": "secure-child-pass-123"}}
    ) as child_api:
        response = child_api.post(f"/api/units/{unit_id}/start")
        assert response.status_code == 426  # Older client never starts an unusable new drawing.
        child_api.headers["X-Schulpilot-Capabilities"] = "language-v1,visual-v1"
        response = child_api.post(f"/api/units/{unit_id}/start")
        assert response.status_code == 200, response.text
        for given in response.json()["questions"]:
            assert "answer" not in given and "accepted" not in given and "hints" not in given
            assert all(b["disclosure"] == "given" for b in given["presentation"]["blocks"])
            assert all("source_excerpt" not in b for b in given["presentation"]["blocks"])
        for question in q:
            body = {"answer": question["answer"], "request_id": "synthetic-answer-" + question["id"]}
            first = child_api.post(f"/api/units/{unit_id}/questions/{question['id']}/answer", json=body)
            replay = child_api.post(f"/api/units/{unit_id}/questions/{question['id']}/answer", json=body)
            assert first.status_code == replay.status_code == 200, first.text
            assert first.json()["attempt_id"] == replay.json()["attempt_id"]
        saved = child_api.get(f"/api/units/{unit_id}").json()
        assert saved["status"] == "completed"
        assert all(len(question["attempts"]) == 1 for question in saved["questions"])
        assert all(len(question["presentation"]["blocks"]) == 1 for question in saved["questions"])
    with DB() as db:
        unit = db.get(LearningUnit, unit_id)
        assert unit.questions == q  # Private revision snapshot is not rewritten by reads/replays.
        ledger = totals(read_ledger(db, child["id"]))
        assert ledger["practiced_tasks"] == ledger["attempts"] == 2
        open_count = sum(c["question"]["presentation"]["evidence_kind"] in ("reflection", "movement") for c in examples)
        assert ledger["reflection_tasks"] == open_count
        assert ledger["uncertain_tasks"] == 0
        exported = export_child(db, db.get(Child, child["id"]))
        assert any(u["id"] == unit_id for u in exported["learning_units"])
        before = (
            db.scalar(select(func.count()).select_from(Attempt)),
            db.scalar(select(func.count()).select_from(Usage)),
        )
    for _ in range(2):
        response = api.get(f"/api/units/{unit_id}")
        assert response.status_code == 200 and response.json()["questions"][0]["answer"] == q[0]["answer"]
    with DB() as db:
        assert before == (
            db.scalar(select(func.count()).select_from(Attempt)),
            db.scalar(select(func.count()).select_from(Usage)),
        )
        if open_learning_unit(db.get(LearningUnit, unit_id)):
            assert coaching.view(db, db.get(LearningUnit, unit_id))["local_only"]


def test_quota_blocks_useless_retry_and_get_does_not_reserve(api, household):
    from schulpilot.db import Family

    parent, child = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        family = (
            db.get(Family, child["family_id"]) if "family_id" in child else db.get(Family, parent["families"][0]["id"])
        )
        family.call_limit = 0  # Isolated test DB only; never production.
        day = SchoolDay(
            child_id=child["id"],
            school_date="2026-10-19",
            stage="review",
            preparation={
                "status": "blocked",
                "phase": "package",
                "error": "Der enthaltene Lernumfang oder das Kostenlimit ist erreicht.",
            },
        )
        db.add(day)
        db.flush()
        db.add(Material(child_id=child["id"], school_day_id=day.id, title="Test", confirmed=True, status="confirmed"))
        db.flush()
        before = db.scalar(select(func.count()).select_from(Usage))
        for _ in range(3):
            data = preparation_data(db, day, db.get(Child, child["id"]))
            assert not data["can_retry"] and data["retry_blocker"]["code"] == "quota_exhausted"
        assert db.scalar(select(func.count()).select_from(Usage)) == before
        assert db.scalar(select(func.count()).select_from(Job)) == 0
