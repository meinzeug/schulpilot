"""Scope/help regressions: artificial records and a mocked provider only."""

import copy

import pytest
from schulpilot.db import DB, Activity, Attempt, LearningUnit, Material, Membership, SchulbuddyTurn, UnitSource, now
from schulpilot.schulbuddy_schemas import SYSTEM
from sqlalchemy import func, select
from test_schulbuddy import ask, counts, finish
from test_schulbuddy import book as book_fixture
from test_schulbuddy import transport as transport_fixture


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return transport_fixture.__wrapped__(monkeypatch)


def questions():
    return [{"id": f"q{i}", "type": "short", "prompt": "Was ist die Sonne?", "options": [],
             "answer": "Stern", "accepted": ["Stern"], "hints": [], "explanation": "Künstliche Erklärung"}
            for i in (1, 2)]


def activate(book, status="active"):
    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        unit.status, unit.questions = status, questions()


def helpers():
    with DB() as db:
        return [(row.unit_id, row.detail) for row in db.scalars(select(Activity).where(Activity.kind == "explanation"))]


def test_read_only_parent_retains_own_history_but_form_cannot_offer_a_paid_question(api, book, transport):
    turn = ask(book, client=api)
    assert turn.status_code == 202, turn.text
    finish()
    with DB.begin() as db:
        db.scalar(select(Membership).where(Membership.user_id == book["parent"]["id"])).permission = "view"
    before = counts()
    context = api.get("/api/schulbuddy/context", params={"page_kind": "learn", "unit_id": book["unit_id"]})
    assert context.status_code == 200
    value = context.json()
    assert value["available"] is False and "Familienberechtigung" in value["notice"]
    assert [row["id"] for row in value["history"]] == [turn.json()["id"]]
    assert value["history"][0]["answer"] == "Die Sonne ist ein Stern."
    assert ask(book, client=api).status_code == 403
    assert counts() == before and len(transport["calls"]) == 1


@pytest.mark.parametrize("status", ["active", "paused"])
def test_omitting_question_id_is_normalized_to_actual_child_question_without_get_help(api, book, transport, status):
    activate(book, status)
    before = counts()
    context = book["client"].get("/api/schulbuddy/context", params={"page_kind": "learn", "unit_id": book["unit_id"]})
    assert context.status_code == 200 and counts() == before and helpers() == []
    request = ask(book)
    assert request.status_code == 202, request.text
    assert helpers() == []  # Sending/queued is not successful assistance.
    with DB() as db:
        saved = db.get(SchulbuddyTurn, request.json()["id"])
        assert saved.scope["question_id"] == "q1"
        assert saved.context_key == context.json()["context_key"]
    finish()
    payload = transport["calls"][0]["current_question"]
    assert payload["id"] == "q1" and payload["own_work_attempted"] is False
    assert "answer" not in payload and "accepted" not in payload
    assert len(helpers()) == 1 and helpers()[0][1]["question_id"] == "q1"


def test_implicit_question_help_changes_only_a_later_answer_not_earlier_attempt(api, book, transport):
    activate(book)
    with DB.begin() as db:
        earlier = Attempt(unit_id=book["unit_id"], question_id="old", answer="Vorherige eigene Antwort",
                          outcome="correct", assisted=False, evaluation={"support_reasons": []})
        db.add(earlier)
        db.flush()
        earlier_id = earlier.id
    assert ask(book).status_code == 202
    finish()
    answer = book["client"].post(f"/api/units/{book['unit_id']}/questions/q1/answer", json={"answer": "Stern"})
    assert answer.status_code == 200, answer.text
    assert answer.json()["assisted"] is True
    with DB() as db:
        old = db.get(Attempt, earlier_id)
        assert old.answer == "Vorherige eigene Antwort" and old.assisted is False
        assert old.evaluation == {"support_reasons": []}


@pytest.mark.parametrize("source_kind", ["material", "day"])
def test_material_explanation_marks_only_matching_active_and_paused_real_units(api, book, transport, source_kind):
    activate(book)
    ids = {}
    with DB.begin() as db:
        original = db.get(LearningUnit, book["unit_id"])
        material = db.get(Material, book["material_id"])
        other = Material(child_id=original.child_id, title="Andere künstliche Seite", subject="Sachunterricht",
                         topic="Anderer Stoff", content="Andere sichere Quelle.", confirmed=True, status="confirmed")
        db.add(other)
        db.flush()
        for name, status, synthetic, source in [("paused", "paused", False, material),
                                                ("legacy", "active", False, material),
                                                ("completed", "completed", False, material),
                                                ("synthetic", "active", True, material),
                                                ("other", "active", False, other)]:
            row = LearningUnit(child_id=original.child_id, material_id=source.id, subject=source.subject,
                               topic=source.topic, explanation="Künstlich", questions=copy.deepcopy(questions()),
                               status=status, synthetic=synthetic, completed=int(now()) if status == "completed" else None,
                               provider="openai", model="fixture")
            db.add(row)
            db.flush()
            if name != "legacy":
                db.add(UnitSource(unit_id=row.id, material_id=source.id, revision=source.revision))
            ids[name] = row.id
    scope = {"material_id": book["material_id"]} if source_kind == "material" else {"day_id": book["day_id"]}
    value = ask(book, unit_id=None, **scope)
    assert value.status_code == 202, value.text
    assert helpers() == []
    finish()
    assert {identifier for identifier, _ in helpers()} == {book["unit_id"], ids["paused"], ids["legacy"]}
    assert all("question_id" not in detail for _, detail in helpers())
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_material_operating_guidance_without_source_citation_does_not_claim_subject_help(api, book, transport):
    activate(book)
    transport["output"] = {"answer": "Öffne die Hefte im Menü.", "next_question": None,
                           "sources": [], "starters": []}
    assert ask(book, unit_id=None, material_id=book["material_id"], question="Wo sind meine Hefte?").status_code == 202
    finish()
    assert helpers() == []


def test_advancing_the_implicit_question_after_dispatch_discards_old_answer_and_no_help(api, book, transport):
    activate(book)
    first = ask(book).json()

    def advance():
        with DB.begin() as db:
            db.add(Attempt(unit_id=book["unit_id"], question_id="q1", answer="Stern",
                           outcome="correct", assisted=False))

    transport["effect"] = advance
    finish()
    value = book["client"].get("/api/schulbuddy/questions/" + first["id"]).json()
    assert value["status"] == "failed" and value["answer"] is None
    assert helpers() == []
    with DB() as db:
        attempt = db.scalar(select(Attempt))
        assert attempt.assisted is False and attempt.answer == "Stern"


def test_completion_while_source_help_is_prepared_does_not_retroactively_mark_round(api, book, transport):
    activate(book)

    def complete():
        with DB.begin() as db:
            row = db.get(LearningUnit, book["unit_id"])
            row.status, row.completed = "completed", int(now())

    transport["effect"] = complete
    assert ask(book, unit_id=None, material_id=book["material_id"]).status_code == 202
    finish()
    assert helpers() == []


def test_child_prompt_requires_own_thinking_without_leaking_a_stored_answer(api, book, transport):
    activate(book)
    with DB.begin() as db:
        db.add(Attempt(unit_id=book["unit_id"], question_id="q1", answer="Privater falscher Eigenversuch",
                       outcome="incorrect", assisted=False))
    assert ask(book).status_code == 202
    finish()
    assert transport["calls"][0]["current_question"]["own_work_attempted"] is True
    assert "Privater falscher Eigenversuch" not in str(transport["calls"])
    assert "Verrate vor einem eigenen Versuch weder das Endergebnis" in SYSTEM
    assert "Allgemeine Begriffe und Grundlagen dürfen verständlich erklärt werden" in SYSTEM


def test_source_reference_order_stays_canonical_when_database_returns_other_row_order(api, book, monkeypatch):
    from schulpilot.db import Child, Session, User
    from schulpilot.learning_controller import source_state
    from schulpilot.schulbuddy import scope_context
    from schulpilot.schulbuddy_schemas import BuddyScope
    from schulpilot.security import Principal

    with DB.begin() as db:
        original = db.get(Material, book["material_id"])
        extra = Material(child_id=original.child_id, title="Zweite künstliche Seite", subject=original.subject,
                         topic=original.topic, content="Weitere bestätigte künstliche Beobachtung.",
                         confirmed=True, status="confirmed", page_number=2)
        db.add(extra)
        db.flush()
        db.add(UnitSource(unit_id=book["unit_id"], material_id=extra.id, revision=extra.revision))
    with DB() as db:
        child = db.get(Child, book["child"]["id"])
        principal = Principal(db.get(User, child.user_id), db.scalar(select(Session).where(
            Session.user_id == child.user_id, Session.revoked.is_(False))))
        scope = BuddyScope(unit_id=book["unit_id"], page_kind="learn")
        first = scope_context(db, principal, scope)

        def reversed_sources(db, unit):
            signature, valid, rows = source_state(db, unit)
            return signature, valid, list(reversed(rows))

        monkeypatch.setattr("schulpilot.learning_controller.source_state", reversed_sources)
        second = scope_context(db, principal, scope)
        assert first[2] == second[2] and first[5:] == second[5:]
        assert first[4]["sources"] == second[4]["sources"]


def feedback(book, *, status="active"):
    activate(book, status)
    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        if status == "completed":
            unit.questions = questions()[:1]
            unit.completed = int(now())
        attempt = Attempt(unit_id=unit.id, question_id="q1", answer="Eigener gespeicherter Stern",
                          outcome="correct", assisted=False, evaluation={"attempt_number": 1})
        db.add(attempt)
        db.flush()
        db.add(Activity(child_id=unit.child_id, unit_id=unit.id, kind="feedback_pending",
                        detail={"attempt_id": attempt.id}))
        return attempt.id


@pytest.mark.parametrize("explicit", [False, True])
@pytest.mark.parametrize("status", ["active", "paused", "completed"])
def test_latest_unread_feedback_is_visible_buddy_context_without_new_question_help(api, book, transport, explicit, status):
    saved = feedback(book, status=status)
    parameters = {"page_kind": "learn", "unit_id": book["unit_id"]}
    if explicit:
        parameters["question_id"] = "q1"
    before = counts()
    context = book["client"].get("/api/schulbuddy/context", params=parameters)
    assert context.status_code == 200, context.text
    assert counts() == before and helpers() == []
    submitted = ask(book, **({"question_id": "q1"} if explicit else {}))
    assert submitted.status_code == 202, submitted.text
    finish()
    value = book["client"].get("/api/schulbuddy/questions/" + submitted.json()["id"]).json()
    assert value["status"] == "ready"
    focused = transport["calls"][0]["current_question"]
    assert focused["id"] == "q1" and focused["feedback_pending"] is True
    assert focused["own_work_attempted"] is True and focused["observed_outcome"] == "correct"
    assert "Eigener gespeicherter Stern" not in str(transport["calls"])
    assert helpers() == []
    with DB() as db:
        old = db.get(Attempt, saved)
        assert old.assisted is False and old.answer == "Eigener gespeicherter Stern"
        assert old.evaluation == {"attempt_number": 1}
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
    if status == "active":
        ack = book["client"].post(f"/api/units/{book['unit_id']}/feedback/acknowledge", json={"attempt_id": saved})
        assert ack.status_code == 200, ack.text
        answer = book["client"].post(f"/api/units/{book['unit_id']}/questions/q2/answer", json={"answer": "Stern"})
        assert answer.status_code == 200, answer.text
        assert answer.json()["assisted"] is False


def test_next_open_question_cannot_replace_unread_visible_feedback(api, book):
    feedback(book)
    response = ask(book, question_id="q2")
    assert response.status_code == 409
    assert counts()[:2] == (0, 0) and helpers() == []


@pytest.mark.parametrize("change", ["acknowledged", "newer_answer"])
def test_old_answer_outside_latest_unread_feedback_remains_unavailable(api, book, change):
    saved = feedback(book)
    with DB.begin() as db:
        if change == "acknowledged":
            db.add(Activity(child_id=book["child"]["id"], unit_id=book["unit_id"], kind="feedback_seen",
                            detail={"attempt_id": saved}))
        else:
            newer = Attempt(unit_id=book["unit_id"], question_id="q2", answer="Späterer eigener Versuch",
                            outcome="incorrect", assisted=False, created=int(now()) + 1)
            db.add(newer)
            db.flush()
            db.add(Activity(child_id=book["child"]["id"], unit_id=book["unit_id"], kind="feedback_pending",
                            detail={"attempt_id": newer.id}))
    assert ask(book, question_id="q1").status_code == 409
    assert counts()[:2] == (0, 0)


def test_feedback_acknowledgement_during_provider_call_discards_old_context(api, book, transport):
    saved = feedback(book)
    submitted = ask(book, question_id="q1").json()

    def acknowledge():
        with DB.begin() as db:
            db.add(Activity(child_id=book["child"]["id"], unit_id=book["unit_id"], kind="feedback_seen",
                            detail={"attempt_id": saved}))

    transport["effect"] = acknowledge
    finish()
    response = book["client"].get("/api/schulbuddy/questions/" + submitted["id"]).json()
    assert response["status"] == "failed" and response["answer"] is None
    assert helpers() == []


def test_page_starters_use_short_child_language_without_another_model_request():
    from schulpilot.schulbuddy import starters_for

    pages = {
        "today": "Was ist heute mein nächster Schritt?",
        "learn": "Wie übe ich dieses Thema?",
        "words": "Wie kann ich mir diese Wörter merken?",
        "homework": "Wie fange ich an, ohne die Lösung zu sehen?",
        "notebooks": "Was kann ich mit meinen Heftseiten machen?",
        "account": "Wie ändere ich meine Einstellungen?",
        "messages": "Wie frage ich nach Hilfe?",
        "progress": "Was kann ich schon gut, was übe ich als Nächstes?",
    }
    for page, starter in pages.items():
        result = starters_for(page, "Künstliches Thema", {"sources": [], "knowledge": {}})
        assert result[0] == starter and len(result) <= 3
