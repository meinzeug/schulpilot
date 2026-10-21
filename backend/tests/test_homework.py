"""Artificial homework, real API/queue, mocked transport only."""

import copy
import json
import uuid

import pytest
from schulpilot import homework
from schulpilot.db import DB, Activity, Attempt, Job, Material, TutorTurn, Usage
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_tutor import notebook as _notebook
from test_tutor import transport as _transport

TEXT = "Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in cm²?"


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


@pytest.fixture
def transport(monkeypatch):
    return _transport.__wrapped__(monkeypatch)


def output(*, analyze=False, **changes):
    return {"phase": "analyzed" if analyze else "scaffold",
            "tasks": [{"title": "Rechteckfläche", "source_quote": TEXT}] if analyze else [],
            "more_tasks": False, "explanation": "Die Fläche beschreibt die Größe der ganzen Innenfläche.",
            "next_step": "Notiere Länge und Breite.", "understanding_question": "Welche Größen sind gegeben?",
            "steps": [], "source_quote": TEXT, "example": None, **changes}


def prepare(book):
    with DB.begin() as db:
        material = db.get(Material, book["material_id"])
        material.purpose, material.subject, material.topic, material.content = "homework", "Mathematik", "Flächen", TEXT


def ask(book, action, *, analysis=None, key=None, draft="", **changes):
    body = {"material_id": book["material_id"], "question": "Hilf mir beim Verstehen.",
            "homework": {"action": action, "draft": draft,
                         **({"analysis_id": analysis, "task_id": "t1"} if analysis else {})}, **changes}
    return book["client"].post(f"/api/children/{book['child']['id']}/tutor/questions", json=body,
                               headers={"Idempotency-Key": key or uuid.uuid4().hex})


def finish():
    with DB() as db:
        jid = claim(db)
    assert jid
    process(jid)


def detail(book, client=None):
    r = (client or book["client"]).get(f"/api/materials/{book['material_id']}/homework")
    assert r.status_code == 200, r.text
    return r.json()


def analyze(book, transport):
    prepare(book)
    transport["output"] = output(analyze=True)
    response = ask(book, "analyze")
    assert response.status_code == 202, response.text
    finish()
    turn = detail(book)["turns"][-1]
    assert turn["status"] == "ready", turn
    return turn["id"]


def test_complete_source_scaffold_draft_resume_and_explicit_check_without_mastery(api, book, transport):
    aid = analyze(book, transport)
    transport["output"] = output()
    key = uuid.uuid4().hex
    first = ask(book, "explain", analysis=aid, key=key)
    assert first.status_code == 202, first.text
    assert ask(book, "explain", analysis=aid, key=key).json()["id"] == first.json()["id"]
    finish()
    body = {"revision": 0, "source_revision": detail(book)["material"]["revision"], "request_key": uuid.uuid4().hex,
            "analysis_id": aid, "task_id": "t1", "draft": "Ich multipliziere beide Seiten.",
            "drafts": {"t1": "Ich multipliziere beide Seiten."}, "question": "Wie kann ich meinen Weg erklären?", "done": ["t1"]}
    route = f"/api/materials/{book['material_id']}/homework"
    saved = book["client"].put(route, json=body)
    assert saved.status_code == 200, saved.text
    assert book["client"].put(route, json=body).json()["revision"] == 1
    assert book["client"].put(route, json={**body, "request_key": uuid.uuid4().hex}).status_code == 409
    assert detail(book)["state"]["draft"] == body["draft"]
    parent = detail(book, api)
    assert "draft" not in parent["state"] and "drafts" not in parent["state"]
    assert "question" not in parent["state"]
    assert parent["state"]["done"] == ["t1"]
    assert api.put(route, json=body).status_code == 403
    assert ask(book, "check", analysis=aid).status_code == 422
    # A repeated successful analysis is reused without reserving again.
    assert ask(book, "analyze").json()["id"] == aid
    for _ in range(3):
        assert detail(book)["turns"][-1]["reply"]["next_question"]
        overview = book["client"].get(f"/api/children/{book['child']['id']}/homework").json()
        assert len(overview["photos"]) == 1
        assert "content" not in overview["photos"][0]
    assert len(transport["calls"]) == 2
    payload = transport["calls"][-1]
    assert payload["homework"]["task"]["source_quote"] == TEXT
    assert aid not in json.dumps(payload) and book["child"]["id"] not in json.dumps(payload)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 2
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert not list(db.scalars(select(Activity).where(Activity.kind.in_(["answer", "heartbeat", "unit_completed"]))))
    assert book["client"].post("/api/auth/logout").status_code == 200
    with DB() as db:
        assert not db.get(Material, book["material_id"]).homework_state["drafts"]
        assert not db.get(Material, book["material_id"]).homework_state["question"]


@pytest.mark.parametrize("action", ["explain", "hint", "plan", "example", "check", "question"])
def test_help_is_explicit_bounded_and_uses_existing_accounting(book, transport, action):
    aid = analyze(book, transport)
    transport["output"] = output(phase="feedback" if action == "check" else "scaffold",
        example={"task": "Ein Rechteck ist 3 cm lang und 2 cm breit.", "first_step": "Notiere die beiden Seiten."} if action == "example" else None)
    response = ask(book, action, analysis=aid, draft="Ich habe die Länge und Breite notiert.")
    assert response.status_code == 202, response.text
    finish()
    result = detail(book)["turns"][-1]
    assert result["status"] == "ready", result
    assert result["reply"]["action"] == action
    assert "28" not in result["reply"]["answer"]


@pytest.mark.parametrize("damage", ["leak", "quote", "task", "provider", "revision", "revoked"])
def test_rejects_unsafe_stale_or_failed_responses_and_never_retries(book, transport, damage):
    aid = analyze(book, transport)
    transport["output"] = output()
    if damage == "leak":
        transport["output"]["explanation"] = "Rechne 7 mal 4. Das ergibt 28 Quadratzentimeter."
    if damage == "quote":
        transport["output"]["source_quote"] = "Diese erfundene Aufgabe steht nicht im Foto."
    if damage == "task":
        transport["output"]["tasks"] = [{"title": "Andere Aufgabe", "source_quote": TEXT}]
    if damage in ("revision", "revoked", "provider"):
        def effect():
            if damage == "provider":
                raise RuntimeError("synthetic provider outage")
            with DB.begin() as db:
                if damage == "revision":
                    db.get(Material, book["material_id"]).revision += 1
                else:
                    from schulpilot.db import Session

                    turn = db.scalars(select(TutorTurn).order_by(TutorTurn.created.desc())).first()
                    db.get(Session, turn.session_id).revoked = True
        transport["effect"] = effect
    response = ask(book, "explain", analysis=aid)
    assert response.status_code == 202
    finish()
    with DB() as db:
        turn = db.get(TutorTurn, response.json()["id"])
        assert turn.status == "failed" and turn.reply is None
        job = db.get(Job, turn.job_id)
        assert job.status == "failed" and job.attempts == 1
    with DB() as db:
        assert claim(db) is None
    assert len(transport["calls"]) == 2


def test_three_hint_stages_are_cached_after_third_and_old_analysis_is_invalidated(book, transport):
    aid = analyze(book, transport)
    transport["output"] = output()
    for stage in range(1, 4):
        r = ask(book, "hint", analysis=aid)
        assert r.status_code == 202
        finish()
        assert transport["calls"][-1]["homework"]["hint_level"] == stage
    assert ask(book, "hint", analysis=aid).json()["status"] == "ready"
    assert len(transport["calls"]) == 4
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    assert ask(book, "explain", analysis=aid).status_code == 409


@pytest.mark.parametrize("text, task", [
    ("Das ergibt 1/2.", "Berechne 1/3 + 1/6."),
    (r"Das ergibt \(\frac{1}{2}\).", r"Berechne \(\frac{1}{3}+\frac{1}{6}\)."),
    ("Die Dichte beträgt 3 g/cm³.", "Ein Körper hat eine Masse von 120 g und ein Volumen von 40 cm³. Berechne seine Dichte."),
])
def test_known_numeric_solution_leaks_are_detected(text, task):
    assert homework.reveals_result(text, task)


def test_analysis_refuses_invented_tasks_or_answer_titles():
    revisions = [{"id": "fake", "revision": 1, "ref": "p1", "label": "Künstlich"}]
    payload = {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]}
    from schulpilot.providers import ProviderError

    for task in ({"title": "Erfundene Übung", "source_quote": "Berechne 8 + 9."},
                 {"title": "Fläche 28", "source_quote": TEXT}):
        data = copy.deepcopy(output(analyze=True))
        data["tasks"] = [task]
        with pytest.raises(ProviderError):
            homework.checked_reply(data, payload, revisions)


@pytest.mark.parametrize("answer, expected", [("28", "correct"), ("28,0", "correct"), ("11", "incorrect"), ("28 m²", "incorrect")])
def test_clear_own_answers_are_checked_without_any_model_or_new_usage(book, transport, answer, expected):
    aid = analyze(book, transport)
    response = ask(book, "check", analysis=aid, draft=answer)
    assert response.status_code == 202, response.text
    finish()
    turn = next(t for t in detail(book)["turns"] if t["id"] == response.json()["id"])
    assert turn["status"] == "ready", turn
    assert turn["reply"]["method"] == "homework_math_v1" and turn["reply"]["outcome"] == expected
    assert len(transport["calls"]) == 1  # only the analysis, no grading model
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_analysis_instruction_and_language_gap_disclosure_are_validated():
    from schulpilot.providers import ProviderError

    quote = "Yesterday, Tom ___ (play) football."
    instruction = "Setze die regelmäßigen Verben ins simple past."
    payload = {"homework": {"action": "explain", "task": {"source_quote": quote, "instruction_quote": instruction}, "draft": ""},
               "sources": [{"content": instruction + "\n" + quote}]}
    revisions = [{"id": "fake", "revision": 1, "ref": "p1", "label": "Künstlich"}]
    with pytest.raises(ProviderError):
        homework.checked_reply(output(source_quote=quote, explanation="Setze hier played ein."), payload, revisions)
    valid = homework.checked_reply(output(source_quote=quote, explanation="Das Signalwort beschreibt einen vergangenen Zeitpunkt."), payload, revisions)
    assert valid["mode"] == "homework"
    data = output(analyze=True)
    data["tasks"][0]["instruction_quote"] = "Diese erfundene Anleitung ist nicht im Foto."
    with pytest.raises(ProviderError):
        homework.checked_reply(data, {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]}, revisions)
