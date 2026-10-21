"""Bounded original-task context for referential homework follow-ups."""

import copy
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from schulpilot import homework
from schulpilot.db import Material, TutorTurn
from schulpilot.providers import ProviderError

FIRST = r"1) Berechne \(\frac{1}{3} + \frac{1}{6}\)."
SECOND = r"2) Berechne \(\frac{2}{5} + \frac{1}{10}\)."
FOLLOWUP = "Beschreibe deinen ersten Schritt."
RULE = "Erweitere Zähler und Nenner mit derselben Zahl."


def context_fixture(extra_tasks=None):
    tasks = extra_tasks or [
        {"id": "t1", "title": "Aufgabe 1", "source_quote": FIRST, "instruction_quote": RULE},
        {"id": "t2", "title": "Aufgabe 2", "source_quote": SECOND, "instruction_quote": RULE},
    ]
    tasks = [*tasks, {"id": "followup", "title": "Ersten Schritt beschreiben", "source_quote": FOLLOWUP, "instruction_quote": ""}]
    material = SimpleNamespace(id="artificial-page", child_id="artificial-child", revision=2,
        confirmed=True, purpose="homework", content="\n\n".join([RULE, *(t["source_quote"] for t in tasks)]))
    analysis = SimpleNamespace(id="artificial-analysis", child_id=material.child_id, material_id=material.id,
        status="ready", homework_context={"action": "analyze"}, reply={"tasks": tasks},
        source_revisions=[{"id": material.id, "revision": material.revision}])
    turn = SimpleNamespace(material_id=material.id, homework_context={"action": "explain",
        "analysis_id": analysis.id, "task_id": "followup", "draft": ""})
    rows = {(Material, material.id): material, (TutorTurn, analysis.id): analysis}
    db = SimpleNamespace(get=lambda model, row_id: rows.get((model, row_id)))
    payload = {"grade": 6, "sources": [{"ref": "p1", "content": material.content}], "history": []}
    return db, material, analysis, turn, payload


def enrich(values):
    db, material, _, turn, payload = values
    return homework.enrich_context(db, SimpleNamespace(id=material.child_id), turn, payload)


def output(explanation):
    return {"phase": "scaffold", "tasks": [], "more_tasks": False, "explanation": explanation,
        "next_step": "Wähle die passende Aufgabe.", "understanding_question": "Meinst du Aufgabe 1 oder Aufgabe 2?",
        "steps": [], "source_quote": FOLLOWUP, "example": None}


def test_followup_retains_only_literal_tasks_from_the_same_current_analysis():
    values = context_fixture()
    payload = enrich(values)
    assert payload["sources"][0]["content"] == FOLLOWUP
    assert payload["homework"]["task"]["source_quote"] == FOLLOWUP
    related = payload["homework"]["related_tasks"]
    assert [task["ref"] for task in related] == ["t1", "t2"]
    assert [task["source_quote"] for task in related] == [FIRST, SECOND]
    assert all(task["instruction_quote"] == RULE for task in related)
    assert "artificial-child" not in str(payload)
    assert "artificial-page" not in str(payload)
    assert "artificial-analysis" not in str(payload)


def test_self_contained_math_task_does_not_receive_sibling_context():
    values = context_fixture()
    values[3].homework_context["task_id"] = "t1"
    payload = enrich(values)
    assert "related_tasks" not in payload["homework"]
    assert SECOND not in str(payload)


@pytest.mark.parametrize("damage", ["revision", "foreign-child", "foreign-material", "quote", "instruction"])
def test_related_context_never_bypasses_source_ownership_revision_or_quotes(damage):
    values = context_fixture()
    _, material, analysis, _, _ = values
    if damage == "revision":
        material.revision += 1
    elif damage == "foreign-child":
        analysis.child_id = "foreign-child"
    elif damage == "foreign-material":
        analysis.material_id = "foreign-page"
    elif damage == "quote":
        analysis.reply["tasks"][0]["source_quote"] = "Berechne 5/7 + 2/9."
    else:
        analysis.reply["tasks"][0]["instruction_quote"] = "Eine erfundene Anweisung."
    with pytest.raises(HTTPException) as error:
        enrich(values)
    assert error.value.status_code == 409


def test_context_is_bounded_to_three_short_nearby_tasks_and_never_whole_photos():
    tasks = [{"id": f"t{i}", "title": f"Aufgabe {i}", "source_quote": f"{i}) Berechne {i}/7 + 1/9.", "instruction_quote": ""}
             for i in range(1, 8)]
    related = enrich(context_fixture(tasks))["homework"]["related_tasks"]
    assert [item["ref"] for item in related] == ["t5", "t6", "t7"]
    assert len(related) == 3
    assert sum(len(item["source_quote"]) + len(item["instruction_quote"]) for item in related) <= 2400
    tasks[-1]["source_quote"] = "Berechne 2/7 + 1/9. " * 40
    related = enrich(context_fixture(tasks))["homework"]["related_tasks"]
    assert "t7" not in [item["ref"] for item in related]
    assert all(len(item["source_quote"]) <= 600 for item in related)


@pytest.mark.parametrize("answer", ["Das ergibt 1/2.", r"Du erhältst \(\frac{1}{2}\)."])
def test_related_original_result_cannot_leak_through_a_non_numeric_followup(answer):
    payload = enrich(context_fixture())
    with pytest.raises(ProviderError) as error:
        homework.checked_reply(output(answer), payload, [{"id": "artificial-page", "label": "Künstlich"}])
    assert error.value.validation_reason == "Original result disclosed"
    checked = homework.checked_reply(output("Du kannst den ersten Schritt an Aufgabe 1 oder Aufgabe 2 erklären."),
                                     payload, [{"id": "artificial-page", "label": "Künstlich"}])
    assert checked["sources"][0]["quote"] == FOLLOWUP


def test_related_original_language_gap_remains_protected():
    payload = enrich(context_fixture())
    payload = copy.deepcopy(payload)
    payload["homework"]["related_tasks"] = [{"ref": "t1", "title": "Englischlücke",
        "source_quote": "Yesterday, Tom ___ (play) football.", "instruction_quote": "Setze ins simple past."}]
    with pytest.raises(ProviderError) as error:
        homework.checked_reply(output("Schreibe played in die Lücke."), payload,
                               [{"id": "artificial-page", "label": "Künstlich"}])
    assert error.value.validation_reason == "Completed original language gap"
