"""Artificial saved-help regressions; no provider or real household data."""

import copy

import pytest
from schulpilot import controller_jobs
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Job,
    LearningEvent,
    LearningMemory,
    LearningUnit,
    Material,
    Usage,
    VocabularyItem,
)
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit
from test_learning_controller import endpoint, start
from test_vocabulary import CAPS, correct_answer, import_words


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def snapshot(unit_id):
    with DB() as db:
        unit = db.get(LearningUnit, unit_id)
        memory = db.get(LearningMemory, unit_id)
        return {
            "unit": (unit.status, unit.active_seconds, copy.deepcopy(unit.questions)),
            "memory": (memory.revision, copy.deepcopy(memory.working)),
            "counts": {
                model.__tablename__: db.scalar(select(func.count()).select_from(model))
                for model in (Activity, Attempt, LearningEvent, Job, Usage)
            },
        }


def reject_transport(*args, **kwargs):
    raise AssertionError("A saved-help capability check must not call a provider")


def test_unmapped_language_help_is_not_offered_as_a_new_support_round(normal_unit, monkeypatch):
    client, unit_id, material_id, *_ = normal_unit
    monkeypatch.setattr(controller_jobs, "request_provider", reject_transport)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        material = db.get(Material, material_id)
        unit.subject, unit.topic = material.subject, material.topic = "Englisch", "Eigene Schulwörter"
        material.content = "tree = Baum. leaf = Blatt."
        unit.questions = [{
            "id": "word", "type": "short", "prompt": "Was bedeutet tree auf Deutsch?",
            "options": [], "answer": "Baum", "accepted": [],
            "hints": ["Denke an einen Baum."], "explanation": "tree bedeutet Baum.",
        }]
        unit.introduction_seen = True
    start(client, unit_id)
    assert client.post(f"/api/units/{unit_id}/explanation", json={"question_id": "word"}).status_code == 200
    state = client.get(endpoint(unit_id)).json()
    assert client.put(endpoint(unit_id) + "/draft", json={
        "question_id": "word", "answer": "Bau", "revision": state["draft_revision"],
        "request_key": "language-help-draft-101",
    }).status_code == 200
    before = snapshot(unit_id)
    for _ in range(2):
        session = client.get(endpoint(unit_id)).json()
        assert session["source_valid"] and not session["can_request_support_check"]
        unit = client.get(f"/api/units/{unit_id}").json()
        assert not unit["learning_session"]["can_request_support_check"]
        denied = client.post(endpoint(unit_id) + "/check", json={
            "kind": "check_understanding", "revision": session["revision"],
            "request_key": "language-help-no-goal-101",
        })
        assert denied.status_code == 409
        assert "Beende zuerst" in denied.json()["detail"]
    assert snapshot(unit_id) == before
    assert before["counts"]["jobs"] == before["counts"]["usage"] == 0


@pytest.mark.parametrize("source_change", ["revision", "oversized"])
def test_support_capability_rechecks_source_context_without_reserving(normal_unit, monkeypatch, source_change):
    client, unit_id, material_id, *_ = normal_unit
    monkeypatch.setattr(controller_jobs, "request_provider", reject_transport)
    start(client, unit_id)
    assert client.post(f"/api/units/{unit_id}/explanation", json={"question_id": "sum"}).status_code == 200
    assert client.get(endpoint(unit_id)).json()["can_request_support_check"]
    with DB.begin() as db:
        material = db.get(Material, material_id)
        if source_change == "revision":
            material.revision += 1
        else:
            material.content += " " * 60001
    before = snapshot(unit_id)
    session = client.get(endpoint(unit_id)).json()
    assert not session["can_request_support_check"]
    denied = client.post(endpoint(unit_id) + "/check", json={
        "kind": "check_understanding", "revision": session["revision"],
        "request_key": "changed-help-source-101",
    })
    assert denied.status_code == 409
    assert snapshot(unit_id) == before


def test_local_five_word_round_can_finish_after_help_without_new_goals(api, household, normal_unit, monkeypatch):
    client, _, _, _, child = normal_unit
    monkeypatch.setattr(controller_jobs, "request_provider", reject_transport)
    pairs = [
        {"word": "tree", "meaning": "Baum"},
        {"word": "leaf", "meaning": "Blatt"},
        {"word": "sun", "meaning": "Sonne"},
        {"word": "rain", "meaning": "Regen"},
        {"word": "cloud", "meaning": "Wolke"},
    ]
    import_words(api, child, key="own-word-import-101", pairs=pairs)
    # Seed the confirmed artificial source binding, without an OCR/provider
    # job, so the real round builder exercises the same valid-source/no-goals
    # shape as an ordinary source-backed vocabulary round.
    with DB.begin() as db:
        source = Material(child_id=child["id"], title="Eigene künstliche Wörter", subject="Englisch",
                          topic="Schulwörter", status="confirmed", confirmed=True, synthetic=False,
                          content="\n".join(f"{pair['word']} = {pair['meaning']}" for pair in pairs))
        db.add(source)
        db.flush()
        for item in db.scalars(select(VocabularyItem).where(VocabularyItem.child_id == child["id"])):
            item.source_revisions = [{"id": source.id, "revision": source.revision}]
            item.origin = "material"
    client.headers.update(CAPS)
    created = client.post(f"/api/children/{child['id']}/vocabulary/rounds", json={
        "target_locale": "en-GB", "count": 5, "skill": "spelling", "direction": "de_to_target",
    }, headers={"Idempotency-Key": "own-five-word-round-101"})
    assert created.status_code == 201, created.text
    unit_id = created.json()["unit_id"]
    unit = client.post(f"/api/units/{unit_id}/start").json()
    for question in unit["questions"][:4]:
        response = client.post(f"/api/units/{unit_id}/questions/{question['id']}/answer", json={
            "answer": correct_answer(unit_id, question["id"]),
            "request_id": "word-answer-101-" + question["id"], "guided_feedback": True,
        })
        assert response.status_code == 200, response.text
        feedback = response.json()["unit"]["pending_feedback"]
        assert client.post(f"/api/units/{unit_id}/feedback/acknowledge", json={
            "attempt_id": feedback["attempt_id"],
        }).status_code == 200
    last = unit["questions"][-1]
    wrong = client.post(f"/api/units/{unit_id}/questions/{last['id']}/answer", json={
        "answer": "own-deliberately-wrong-word", "request_id": "wrong-word-answer-101", "guided_feedback": True,
    })
    assert wrong.status_code == 200 and wrong.json()["outcome"] == "incorrect"
    assert client.post(f"/api/units/{unit_id}/feedback/acknowledge", json={
        "attempt_id": wrong.json()["unit"]["pending_feedback"]["attempt_id"],
    }).status_code == 200
    assert client.post(f"/api/units/{unit_id}/questions/{last['id']}/hint").status_code == 200
    assert client.post(f"/api/units/{unit_id}/explanation", json={"question_id": last["id"]}).status_code == 200
    before = snapshot(unit_id)
    state = client.get(endpoint(unit_id)).json()
    assert state["action"]["reason_code"] == "change_explanation"
    assert state["source_valid"]
    with DB() as db:
        from schulpilot.coaching import context

        assert context(db, db.get(LearningUnit, unit_id))[1]["learning_goals"] == []
    assert not state["can_request_support_check"]
    denied = client.post(endpoint(unit_id) + "/check", json={
        "kind": "check_understanding", "revision": state["revision"],
        "request_key": "word-no-extra-check-101",
    })
    assert denied.status_code == 409
    assert denied.json()["detail"] == (
        "Für diese Wortschatzrunde gibt es keine zusätzliche Lernprobe. "
        "Kehre zur offenen Aufgabe zurück und übe dort weiter."
    )
    assert "Rückblick" not in denied.json()["detail"]
    assert snapshot(unit_id) == before
    assert before["unit"][0] == "active"
    answer = {"answer": correct_answer(unit_id, last["id"]),
              "request_id": "retry-word-answer-101", "guided_feedback": True}
    finished = client.post(f"/api/units/{unit_id}/questions/{last['id']}/answer", json=answer)
    assert finished.status_code == 200, finished.text
    assert finished.json()["outcome"] == "correct" and finished.json()["assisted"]
    assert finished.json()["unit"]["status"] == "completed"
    assert finished.json()["unit"]["coaching"]["status"] == "not_needed"
    replay = client.post(f"/api/units/{unit_id}/questions/{last['id']}/answer", json=answer)
    assert replay.status_code == 200
    assert replay.json()["attempt_id"] == finished.json()["attempt_id"]
    after = snapshot(unit_id)
    assert after["counts"]["attempts"] == before["counts"]["attempts"] + 1
    assert after["counts"]["jobs"] == after["counts"]["usage"] == 0
    assert after["unit"][1] == before["unit"][1]
