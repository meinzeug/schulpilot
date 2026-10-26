"""Real Buddy/API guards with artificial saved graphics and mocked inference."""

import copy
import uuid

import pytest
from pydantic import ValidationError
from schulpilot.db import DB, Activity, Attempt, Job, Material, Usage
from schulpilot.schulbuddy import protocol_fields
from schulpilot.schulbuddy_graphics import _phase
from schulpilot.schulbuddy_schemas import BuddyScope
from schulpilot.source_lineage import learning_source
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import func, select
from test_schulbuddy import book as book_fixture
from test_schulbuddy import finish
from test_schulbuddy import transport as transport_fixture
from test_visual_references import SOURCE, generated_visual_unit


@pytest.fixture
def book(api, household, monkeypatch):
    yield from book_fixture.__wrapped__(api, household, monkeypatch)


@pytest.fixture
def transport(monkeypatch):
    return transport_fixture.__wrapped__(monkeypatch)


@pytest.fixture
def graphic_book(book, household):
    unit_id, material_id, _ = generated_visual_unit.__wrapped__(household)
    return {**book, "unit_id": unit_id, "material_id": material_id}


def scope(book, **extra):
    return {
        "page_kind": "learn",
        "unit_id": book["unit_id"],
        "explanation_kind": "intro",
        "explanation_step_id": "e1",
        "graphic_index": 0,
        "graphic_phase": "fraction-circle-denominator",
        **extra,
    }


def ask(book, **extra):
    return book["client"].post(
        "/api/schulbuddy/questions",
        json={**scope(book), "question": "Erkläre mir diese Grafik.", **extra},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )


def response(transport):
    transport["output"] = {
        "answer": "Betrachte die gleich großen Teile der gezeigten Grafik.",
        "sources": [{"ref": "p1", "quote": SOURCE}],
        "next_question": None,
        "starters": [],
    }


def test_nullable_new_fields_preserve_legacy_chat_protocol_and_replay_identity():
    expected = dict(page_kind="general", child_id=None, unit_id=None, material_id=None, day_id=None, question_id=None)
    assert protocol_fields(BuddyScope()) == expected
    assert (
        protocol_fields(
            BuddyScope(explanation_kind=None, explanation_step_id=None, graphic_index=None, graphic_phase=None)
        )
        == expected
    )
    for changes in [
        dict(graphic_index=0),
        dict(explanation_kind="intro"),
        dict(graphic_phase="initial"),
        dict(unit_id="u", explanation_kind="question", explanation_step_id="e"),
        dict(unit_id="u", explanation_kind="intro", explanation_step_id="e", graphic_index=True),
        dict(unit_id="u", explanation_kind="intro", explanation_step_id="e", graphic_index=0, graphic_phase="<script>"),
        dict(
            unit_id="u", explanation_kind="intro", explanation_step_id="e", graphic_index=0, graphic_phase="science-100"
        ),
    ]:
        with pytest.raises(ValidationError):
            BuddyScope(**changes)


def test_finite_science_and_scene_states_derive_only_saved_values():
    assert _phase(dict(kind="function_graph", variant="polynomial2", numbers=[0, 2, 1]), "science-50") == {
        "phase": "science-50",
        "point_index": 50,
        "x": 1.0,
        "y": 3.0,
        "derived_locally": True,
    }
    assert _phase(dict(kind="data_plot", variant="scatter", numbers=[1, 5, 2, 7]), "science-1")["y"] == 7
    assert _phase(dict(kind="logic_table", variant="and_gate"), "science-3")["Y"] == 1
    assert _phase(dict(kind="logic_table", variant="not_gate"), "science-0")["Y"] == 1
    scene = dict(
        kind="scene",
        scene=dict(
            objects=[dict(id="a", label="Wasser"), dict(id="b", label="Dampf")],
            steps=[
                dict(caption="Wasser wird Dampf", highlight=["b"], edges=[dict(start="a", end="b", label="erwärmen")])
            ],
        ),
    )
    state = _phase(scene, "scene-0")
    assert state["highlighted_labels"] == ["Dampf"]
    assert state["connections"] == [dict(start="Wasser", end="Dampf", label="erwärmen")]
    from fastapi import HTTPException

    for block, phase in [
        (dict(kind="fraction", numbers=[1, 2]), "science-1"),
        (dict(kind="function_graph", variant="polynomial2", numbers=[0, 2, 1]), "science-81"),
        (dict(kind="data_plot", numbers=[1, 5]), "science-1"),
        (dict(kind="logic_table", variant="not_gate"), "science-2"),
        (scene, "scene-1"),
    ]:
        with pytest.raises(HTTPException):
            _phase(block, phase)


def test_public_intro_graphic_context_starters_and_read_are_get_only(graphic_book):
    before = None
    with DB() as db:
        before = [db.scalar(select(func.count()).select_from(table)) for table in (Job, Usage, Attempt, Activity)]
    value = graphic_book["client"].get("/api/schulbuddy/context", params=scope(graphic_book))
    assert value.status_code == 200, value.text
    assert value.json()["starters"][0] == "Erkläre mir diese Grafik."
    with DB() as db:
        assert [
            db.scalar(select(func.count()).select_from(table)) for table in (Job, Usage, Attempt, Activity)
        ] == before


def test_only_disclosed_question_steps_are_accepted_and_explanation_opening_counts(graphic_book, transport):
    value = scope(graphic_book, explanation_kind="question", question_id="q1", graphic_phase="initial")
    route = "/api/schulbuddy/context"
    assert graphic_book["client"].get(route, params=value).status_code == 409
    # A real existing explanation-open receipt grants exactly this question's solution.
    with DB.begin() as db:
        db.add(
            Activity(
                child_id=graphic_book["child"]["id"],
                unit_id=graphic_book["unit_id"],
                kind="explanation",
                detail={"question_id": "q1"},
            )
        )
    opened = graphic_book["client"].get(route, params=value)
    assert opened.status_code == 200, opened.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    assert (
        graphic_book["client"].get(route, params=scope(graphic_book, explanation_step_id="missing")).status_code == 409
    )
    assert graphic_book["client"].get(route, params=scope(graphic_book, graphic_index=5)).status_code == 409


def test_actual_saved_fraction_state_reaches_existing_buddy_call_without_attempt_write(graphic_book, transport):
    response(transport)
    sent = ask(graphic_book)
    assert sent.status_code == 202, sent.text
    finish()
    assert len(transport["calls"]) == 1
    context = transport["calls"][0]["current_explanation"]
    assert context["text"] == SOURCE and context["step_id"] == "e1"
    assert context["graphic_state"] == dict(
        phase="fraction-circle-denominator", representation="circle", focus="denominator", numerator=1, denominator=2
    )
    assert "source_excerpt" not in str(context)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        # Existing successful child-help contract remains the only support write.
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "explanation")) == 1


def test_unsafe_original_blocks_are_not_sent_as_learning_groundtruth(graphic_book, transport):
    response(transport)
    with DB.begin() as db:
        material = db.get(Material, graphic_book["material_id"])
        material.content = SOURCE + "\n\n2+2=5"
        material.source_blocks = [dict(kind="paragraph", text=SOURCE), dict(kind="formula", text="2+2=5")]
    with DB() as db:
        before = [db.scalar(select(func.count()).select_from(table)) for table in (Job, Usage, Attempt, Activity)]
        revision = db.get(Material, graphic_book["material_id"]).revision
    # The older graphic/question binding must fail closed after a source-policy
    # change, even when its unchanged paragraph remains useful independently.
    stale = ask(graphic_book)
    assert stale.status_code == 409 and "Lernquellen" in stale.json()["detail"]
    assert transport["calls"] == []
    fresh_scope = {"page_kind": "notebooks", "material_id": graphic_book["material_id"], "material_revision": revision}
    context = graphic_book["client"].get("/api/schulbuddy/context", params=fresh_scope)
    assert context.status_code == 200, context.text
    with DB() as db:
        assert [db.scalar(select(func.count()).select_from(table)) for table in (Job, Usage, Attempt, Activity)] == before
    sent = graphic_book["client"].post("/api/schulbuddy/questions", json={**fresh_scope, "question": "Erklär mir den Inhalt der Seite"},
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert sent.status_code == 202, sent.text
    finish()
    payload = transport["calls"][0]
    # Page reading preserves the literal pupil error, explicitly separated
    # from the unchanged filtered learning/answer ground truth.
    source = payload["sources"][0]
    assert source["content"] == SOURCE + "\n\n2+2=5"
    assert source["evidence_kind"] == "notebook_literal_reading"
    assert source["authoritative_solution"] is False
    assert source["learning_exclusions"][0]["reason"] == "false_equality"
    assert payload["source_exclusions"][0]["reasons"] == ["false_equality"]
    with DB() as db:
        material = db.get(Material, graphic_book["material_id"])
        assert "2+2=5" in material.content
        assert learning_source(db, material)["content"] == SOURCE
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


@pytest.mark.parametrize("change", ["source", "graphic"])
def test_changed_source_or_saved_graphic_rejects_late_reply_without_help_or_attempt(graphic_book, transport, change):
    response(transport)

    def changed():
        with DB.begin() as db:
            if change == "source":
                db.get(Material, graphic_book["material_id"]).revision += 1
            else:
                row = db.get(UnitVisualSnapshot, graphic_book["unit_id"])
                steps = copy.deepcopy(row.steps)
                steps[0]["presentation"]["blocks"][0]["title"] = "Geänderte gespeicherte Darstellung"
                row.steps = steps

    transport["effect"] = changed
    sent = ask(graphic_book)
    assert sent.status_code == 202, sent.text
    finish()
    result = graphic_book["client"].get("/api/schulbuddy/questions/" + sent.json()["id"])
    assert result.status_code == 200 and result.json()["status"] == "failed"
    assert result.json()["answer"] is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "explanation")) == 0


def test_photo_scope_revision_and_exact_starters_are_get_only(book):
    params = dict(page_kind="notebooks", material_id=book["material_id"], material_revision=1)
    route = "/api/schulbuddy/context"
    response = book["client"].get(route, params=params)
    assert response.status_code == 200, response.text
    assert response.json()["starters"] == [
        "Erklär mir den Inhalt der Seite",
        "Erklär mir die Abbildung",
        "Stell mir eine Frage zum Inhalt",
    ]
    assert book["client"].get(route, params={**params, "material_revision": 2}).status_code == 409
    assert book["client"].get(route, params={**params, "material_revision": 0}).status_code == 422
    with pytest.raises(ValidationError):
        BuddyScope(material_revision=1)
    assert "material_revision" not in protocol_fields(BuddyScope())
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
    with DB.begin() as db:
        db.get(Material, book["material_id"]).confirmed = False
    unconfirmed = book["client"].get(route, params=params)
    assert unconfirmed.status_code == 200
    assert unconfirmed.json()["starters"] == ["Wie prüfe und bestätige ich den erkannten Text dieser Seite?"]


def test_photo_revision_change_rejects_late_answer_and_never_claims_image_transport(book, transport):
    def changed():
        with DB.begin() as db:
            db.get(Material, book["material_id"]).revision += 1

    transport["effect"] = changed
    posted = book["client"].post(
        "/api/schulbuddy/questions",
        json=dict(
            page_kind="notebooks",
            material_id=book["material_id"],
            material_revision=1,
            question="Erklär mir die Abbildung",
        ),
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert posted.status_code == 202, posted.text
    finish()
    assert transport["calls"][0]["source_view"]["provider_has_photo"] is False
    value = book["client"].get("/api/schulbuddy/questions/" + posted.json()["id"])
    assert value.json()["status"] == "failed" and value.json()["answer"] is None
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "explanation")) == 0
