"""Archived saved explanations; artificial fixtures and the mocked Buddy adapter."""

import copy
import json

import httpx
import pytest
from schulpilot import providers
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Job,
    LearningUnit,
    Mastery,
    Material,
    SchulbuddyTurn,
    UnitSource,
    Usage,
    now,
)
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import delete, func, select
from test_schulbuddy import book as book_fixture
from test_schulbuddy import finish
from test_schulbuddy import transport as transport_fixture
from test_schulbuddy_graphics import ask, response, scope
from test_schulbuddy_graphics import graphic_book as graphic_book_fixture


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return transport_fixture.__wrapped__(monkeypatch)


@pytest.fixture
def graphic_book(book, household):
    return graphic_book_fixture.__wrapped__(book, household)


@pytest.fixture
def archived(graphic_book):
    with DB.begin() as db:
        unit = db.get(LearningUnit, graphic_book["unit_id"])
        unit.status = "completed"
        unit.completed = int(now())
        unit.active_seconds = 37
        db.add(Attempt(unit_id=unit.id, question_id="q1", answer="1/2", outcome="correct",
                       evaluation={"attempt_number": 1}))
        db.add(Mastery(child_id=unit.child_id, subject=unit.subject, topic=unit.topic,
                       independent=1, assisted=2, difficulties=3, uncertain_units=1,
                       next_review="2026-10-26", last_practiced="2026-10-25"))
    return graphic_book


def archived_scope(book, **extra):
    return scope(book, explanation_kind="question", question_id="q1", **extra)


def ask_scope(book, selected):
    # The shared graphics helper defaults to intro/e1. Explicitly remove those
    # defaults for a bare ordinary question context.
    return ask(book, **{"explanation_kind": None, "explanation_step_id": None,
                        "graphic_index": None, "graphic_phase": None, **selected})


def evidence():
    """Preserve complete saved learning records, including answer/time fields."""
    with DB() as db:
        return {
            model.__tablename__: [
                {column.name: copy.deepcopy(getattr(row, column.name)) for column in model.__table__.columns}
                for row in db.scalars(select(model).order_by(model.id))
            ]
            for model in (LearningUnit, Attempt, Activity, Mastery)
        }


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model))
                     for model in (Job, Usage, Attempt, Activity, Mastery))


def test_completed_answered_saved_graphic_context_get_has_no_writes(archived, transport):
    before_counts, before_evidence = counts(), evidence()
    result = archived["client"].get("/api/schulbuddy/context", params=archived_scope(archived))
    assert result.status_code == 200, result.text
    assert result.json()["starters"][0] == "Erkläre mir diese Grafik."
    assert counts() == before_counts and evidence() == before_evidence
    assert transport["calls"] == []


def test_archived_worker_keeps_answers_mastery_time_and_other_active_source_unit_unchanged(archived, transport):
    with DB.begin() as db:
        saved = db.get(LearningUnit, archived["unit_id"])
        active = LearningUnit(child_id=saved.child_id, material_id=archived["material_id"],
                              subject=saved.subject, topic=saved.topic, explanation=saved.explanation,
                              questions=copy.deepcopy(saved.questions), provider="synthetic", model="own-fixture",
                              status="active", active_seconds=19)
        db.add(active)
        db.flush()
        db.add(UnitSource(unit_id=active.id, material_id=archived["material_id"], revision=1))
    response(transport)
    before = evidence()
    sent = ask_scope(archived, archived_scope(archived))
    assert sent.status_code == 202, sent.text
    finish()
    result = archived["client"].get("/api/schulbuddy/questions/" + sent.json()["id"])
    assert result.status_code == 200 and result.json()["status"] == "ready", result.text
    assert len(transport["calls"]) == 1
    payload = transport["calls"][0]
    assert "current_question" not in payload
    assert payload["archived_question"] == {
        "id": "q1", "type": "short", "prompt": "Welcher Bruch beschreibt 1 von 2 Teilen?",
        "options": [], "own_work_attempted": True, "read_only": True,
    }
    explanation = payload["current_explanation"]
    assert (explanation["kind"], explanation["step_id"], explanation["disclosure"]) == ("question", "e1", "solution")
    assert len(explanation["saved_step_digest"]) == 64
    assert explanation["graphic_state"] == {
        "phase": "fraction-circle-denominator", "representation": "circle", "focus": "denominator",
        "numerator": 1, "denominator": 2,
    }
    assert "source_excerpt" not in json.dumps(explanation)
    assert evidence() == before


def test_actual_codex_wire_explains_archive_without_weakening_open_question_rules(archived, monkeypatch):
    calls = []

    class Client:
        def __init__(self, **kwargs):
            assert kwargs["follow_redirects"] is False

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def post(self, url, json):
            assert url == "http://localhost/generate"
            calls.append(copy.deepcopy(json))
            return httpx.Response(200, json={"data": {
                "answer": "Die gezeigten Teile sind gleich groß.", "sources": [],
                "next_question": None, "starters": []},
                "usage": {"input_tokens": 40, "output_tokens": 25}, "search_calls": 0})

    monkeypatch.setattr(providers.httpx, "Client", Client)
    before = evidence()
    sent = ask_scope(archived, archived_scope(archived))
    assert sent.status_code == 202, sent.text
    finish()
    result = archived["client"].get("/api/schulbuddy/questions/" + sent.json()["id"])
    assert result.status_code == 200 and result.json()["status"] == "ready", result.text
    assert len(calls) == 1
    wire = calls[0]
    assert wire["web_search"] is False and wire["reasoning_effort"] == "high"
    assert "archived_question.read_only=true" in wire["system"]
    assert "verlange dafür keinen neuen Antwortversuch" in wire["system"]
    assert "Der historische Versuch beweist kein Verständnis" in wire["system"]
    assert "keine neue Bewertung, Hilfemarkierung, Fortschritts- oder Zeitgutschrift" in wire["system"]
    assert "Der Lösungsschutz für offene current_question und andere ungesehene Aufgaben bleibt bestehen." in wire["system"]
    assert "Verrate vor einem eigenen Versuch weder das Endergebnis noch die richtige Auswahl oder eine vollständige Musterlösung." in wire["system"]
    assert "current_question.own_work_attempted bezeichnet nur einen gespeicherten Versuch, kein bewiesenes Verständnis." in wire["system"]
    assert wire["payload"]["archived_question"]["read_only"] is True
    assert wire["payload"]["archived_question"]["own_work_attempted"] is True
    assert "answer" not in wire["payload"]["archived_question"]
    assert "current_question" not in wire["payload"]
    assert wire["payload"]["current_explanation"]["step_id"] == "e1"
    assert wire["payload"]["current_explanation"]["disclosure"] == "solution"
    assert len(wire["payload"]["current_explanation"]["saved_step_digest"]) == 64
    assert evidence() == before


@pytest.mark.parametrize("with_saved_step", [False, True])
def test_completed_latest_unread_feedback_keeps_ordinary_question_context(archived, transport, with_saved_step):
    with DB.begin() as db:
        attempt = db.scalar(select(Attempt).where(Attempt.unit_id == archived["unit_id"]))
        db.add(Activity(child_id=archived["child"]["id"], unit_id=archived["unit_id"],
                        kind="feedback_pending", detail={"attempt_id": attempt.id, "question_id": "q1"}))
    selected = (archived_scope(archived) if with_saved_step else
                {"page_kind": "learn", "unit_id": archived["unit_id"], "question_id": "q1"})
    before_counts, before_evidence = counts(), evidence()
    context = archived["client"].get("/api/schulbuddy/context", params=selected)
    assert context.status_code == 200, context.text
    assert counts() == before_counts and evidence() == before_evidence
    response(transport)
    sent = ask_scope(archived, selected)
    assert sent.status_code == 202, sent.text
    finish()
    result = archived["client"].get("/api/schulbuddy/questions/" + sent.json()["id"])
    assert result.status_code == 200 and result.json()["status"] == "ready", result.text
    assert len(transport["calls"]) == 1
    payload = transport["calls"][0]
    assert "archived_question" not in payload
    assert payload["current_question"]["id"] == "q1"
    assert payload["current_question"]["feedback_pending"] is True
    assert payload["current_question"]["own_work_attempted"] is True
    if with_saved_step:
        assert "saved_step_digest" not in payload["current_explanation"]
    else:
        assert "current_explanation" not in payload
    assert evidence() == before_evidence


@pytest.mark.parametrize("change", ["bare_question", "wrong_step", "wrong_question", "no_attempt", "active", "no_completed_at"])
def test_archive_exception_requires_exact_saved_step_answer_and_completed_unit(archived, transport, change):
    selected = archived_scope(archived)
    if change == "bare_question":
        selected = {key: value for key, value in selected.items()
                    if key not in {"explanation_kind", "explanation_step_id", "graphic_index", "graphic_phase"}}
    elif change == "wrong_step":
        selected["explanation_step_id"] = "not_saved"
    elif change == "wrong_question":
        selected["question_id"] = "not_saved"
    else:
        with DB.begin() as db:
            unit = db.get(LearningUnit, archived["unit_id"])
            if change == "no_attempt":
                db.execute(delete(Attempt).where(Attempt.unit_id == unit.id))
            elif change == "active":
                unit.status, unit.completed = "active", None
            else:
                unit.completed = None
    before_counts, before_evidence = counts(), evidence()
    result = archived["client"].get("/api/schulbuddy/context", params=selected)
    assert result.status_code == 409, result.text
    posted = ask_scope(archived, selected)
    assert posted.status_code == 409, posted.text
    assert counts() == before_counts and evidence() == before_evidence
    assert transport["calls"] == []


@pytest.mark.parametrize("change", ["source", "step", "status", "attempt"])
def test_archived_context_change_during_call_discards_reply_without_learning_writes(archived, transport, change):
    response(transport)
    after_change = {}

    def changed():
        with DB.begin() as db:
            if change == "source":
                db.get(Material, archived["material_id"]).revision += 1
            elif change == "step":
                snapshot = db.get(UnitVisualSnapshot, archived["unit_id"])
                question_steps = copy.deepcopy(snapshot.question_steps)
                question_steps["q1"][0]["competence_id"] = "math.fractions.changed"
                snapshot.question_steps = question_steps
            elif change == "status":
                unit = db.get(LearningUnit, archived["unit_id"])
                unit.status, unit.completed = "active", None
            else:
                attempt = db.scalar(select(Attempt).where(Attempt.unit_id == archived["unit_id"]))
                attempt.outcome = "uncertain"
        after_change["evidence"] = evidence()

    transport["effect"] = changed
    sent = ask_scope(archived, archived_scope(archived))
    assert sent.status_code == 202, sent.text
    finish()
    assert len(transport["calls"]) == 1
    result = archived["client"].get("/api/schulbuddy/questions/" + sent.json()["id"])
    assert result.status_code == 200 and result.json()["status"] == "failed", result.text
    assert result.json()["answer"] is None
    with DB() as db:
        turn = db.get(SchulbuddyTurn, sent.json()["id"])
        assert turn.reply is None
    assert evidence() == after_change["evidence"]
