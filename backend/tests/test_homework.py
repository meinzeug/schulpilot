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


def test_literal_formula_evidence_survives_index_transport_without_retyping():
    from schulpilot.providers import strict_schema

    text = "Erweitere beide Brüche.\n\n1) Berechne \\(\\frac{1}{3}+\\frac{1}{6}\\)."
    schema = strict_schema(homework.HomeworkOutput, preserve_limits=True)
    payload, candidates = homework.bind_sources(schema, {"sources": [{"content": text}]})
    assert candidates == payload["homework_source_candidates"]
    assert all(candidate in text for candidate in candidates)
    assert "source_quote" not in schema["properties"]
    assert "source_quote_index" in schema["$defs"]["Task"]["required"]
    original = output(analyze=True)
    original["tasks"] = [{"title": "Brüche addieren", "source_quote_index": 1, "instruction_quote_index": 0}]
    del original["source_quote"]
    original["source_quote_index"] = None
    restored = homework.decode_sources(original, candidates)
    result = homework.checked_reply(restored, {"homework": {"action": "analyze"}, "sources": [{"content": text}]},
                                    [{"id": "fake", "revision": 1, "label": "Künstlich"}])
    assert result["tasks"][0]["source_quote"] == candidates[1]
    for index in [True, -1, len(candidates), "1", None]:
        bad = {"source_quote_index": None, "tasks": [{"source_quote_index": index, "instruction_quote_index": None}]}
        with pytest.raises((ValueError, TypeError)):
            homework.decode_sources(bad, candidates)


def test_provider_adapter_decodes_bound_homework_evidence(book, monkeypatch):
    import httpx
    from schulpilot import providers
    from schulpilot.db import ProviderConfig

    calls = []
    class Client:
        def __init__(self, **kwargs):
            pass
        def __enter__(self):
            return self
        def __exit__(self, *args):
            pass
        def post(self, url, headers, json):
            calls.append(json)
            result = output(analyze=True)
            result["tasks"] = [{"title": "Rechteckfläche", "source_quote_index": 0, "instruction_quote_index": None}]
            del result["source_quote"]
            result["source_quote_index"] = 0
            return httpx.Response(200, json={"status": "completed", "output": [{"type": "message", "content": [
                {"type": "output_text", "text": __import__("json").dumps(result)}]}],
                "usage": {"input_tokens": 100, "output_tokens": 100}})
    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    result = providers.request_provider(config, "tutor", {"homework": {"action": "analyze"}, "sources": [{"content": TEXT}]})
    assert result.data["tasks"][0]["source_quote"] == TEXT
    assert result.data["source_quote"] == TEXT
    assert "source_quote_index" in calls[0]["text"]["format"]["schema"]["required"]


def test_validation_audit_is_static_and_does_not_store_model_text(book, transport):
    aid = analyze(book, transport)
    transport["output"] = output(source_quote="Private invented reference must not appear in audit")
    r = ask(book, "explain", analysis=aid)
    finish()
    with DB() as db:
        turn = db.get(TutorTurn, r.json()["id"])
        job = db.get(Job, turn.job_id)
        assert job.error_code == "invalid_output"
        assert job.result == {"validation_reason": "Unverified quotation"}
        assert "Private" not in job.error


@pytest.mark.parametrize("prefix", ["1\n", "1) ", "1. ", ""])
def test_standalone_photo_task_number_is_not_a_third_measurement(prefix):
    reply = homework.deterministic_reply({"homework": {"action": "check", "draft": "28",
        "task": {"source_quote": prefix + TEXT}}}, [{"id": "fake", "label": "Künstlich"}])
    assert reply and reply["outcome"] == "correct"
