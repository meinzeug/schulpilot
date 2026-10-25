"""Forty synthetic regressions; never answers in a real child's account.

The separate operator-only RAM helper exercises generated real content read-only.
These cases fix explicit public/artificial oracles and preserve the original
answer, source, disclosure and finite navigation contracts.
"""

import copy

import pytest
from schulpilot import visual_references
from schulpilot.answer_evaluation import evaluate
from schulpilot.db import DB, Activity, Attempt, LearningMemory, LearningUnit, Usage
from schulpilot.subject_content import PROFILES, Graphic, validate_question
from schulpilot.visual_reference_models import VisualReference
from sqlalchemy import func, select
from test_instructional_decisions import profile as existing_profile


def question(prompt, key, kind="choice", options=None):
    return {"id": "artificial_q", "type": kind, "prompt": prompt, "answer": key,
        "accepted": [], "options": [key, "andere Antwort"] if options is None else options, "hints": ["Prüfe den Auftrag."],
        "explanation": "Künstliches öffentliches Beispiel."}


MIXED = question("Schreibe 7/4 als gemischte Zahl.", "1 3/4", options=["1 3/4", "1 1/4", "2 3/4"])
EXPAND = question("Erweitere 2/3 mit dem Faktor 2.", "4/6", "short", [])
REDUCE = question("Kürze 6/8 vollständig.", "3/4", "short", [])
ADD = question("Berechne 1/4 + 1/8.", "3/8", "short", [])
PART = question("Wie lautet der Zähler des Bruchs 3/7?", "3", options=["3", "7", "3/7"])
ENGLISH = question("Complete: She ___ football.", "plays", "gap", [])
CHOICE_ENGLISH = question("Welche Verbform passt zu She?", "plays", options=["plays", "play"])
ACCENT = question("Welches Originalwort ist korrekt übernommen?", "école", options=["école", "ecole"])


@pytest.mark.parametrize("value,answer,outcome", [
    pytest.param(MIXED, "1 3/4", "correct", id="QA01-mixed-number-exact"),
    pytest.param(MIXED, "1 1/4", "incorrect", id="QA02-mixed-number-wrong-remainder"),
    pytest.param(EXPAND, "4/6", "correct", id="QA03-requested-expansion"),
    pytest.param(EXPAND, "8/12", "incorrect", id="QA04-equivalent-wrong-expansion"),
    pytest.param(REDUCE, "3/4", "correct", id="QA05-complete-reduction"),
    pytest.param(REDUCE, "6/8", "incorrect", id="QA06-unreduced-value-not-enough"),
    pytest.param(ADD, "3/8", "correct", id="QA07-unlike-addition-independent-oracle"),
    pytest.param(ADD, "2/12", "incorrect", id="QA08-denominator-addition-error"),
    pytest.param(PART, "3", "correct", id="QA09-numerator-scalar"),
    pytest.param(PART, "3/7", "incorrect", id="QA10-whole-fraction-is-not-numerator"),
    pytest.param({**ADD, "answer": "3/12"}, "3/8", "uncertain", id="QA11-invalid-stored-math-key-stays-open"),
    pytest.param(ENGLISH, "plays", "correct", id="QA12-exact-gap-key"),
    pytest.param(ENGLISH, "play", "incorrect", id="QA13-morphology-distractor"),
    pytest.param(ACCENT, "e\u0301cole", "correct", id="QA14-nfc-equivalent-original"),
    pytest.param(ACCENT, "ecole", "incorrect", id="QA15-accent-not-silently-dropped"),
    pytest.param(CHOICE_ENGLISH, "A", "incorrect", id="QA16-no-guessed-choice-letter"),
    pytest.param(CHOICE_ENGLISH, "0", "incorrect", id="QA17-no-guessed-choice-index"),
    pytest.param(question("Welche Zahl ist null?", "0", options=["0", "1"]), "0", "correct", id="QA18-literal-zero-is-allowed-key"),
    pytest.param(question("Erkläre gleich große Bruchteile.", "gleich große Teile", "short", []),
        "Ich verteile das Ganze in passende Stücke.", "uncertain", id="QA19-unknown-prose-not-fake-correct-or-wrong"),
    pytest.param(ENGLISH, "  plays  ", "correct", id="QA20-formatting-not-new-content"),
])
def test_synthetic_answer_contracts_with_explicit_independent_oracles(value, answer, outcome):
    original = copy.deepcopy(value)
    result = evaluate(value, answer)
    assert result["outcome"] == outcome
    assert value == original
    assert result["dimensions"]["content"] in ("correct", "incorrect", "uncertain")


def fraction(numbers):
    return {"kind": "fraction", "title": "Belegte Teile", "disclosure": "solution",
        "source_excerpt": "2 von 3 gleich großen Teilen.", "labels": [], "numbers": numbers,
        "connections": [], "marks": [], "unit": "", "variant": "", "scene": None, "text_probe": None, "lab": None}


@pytest.mark.parametrize("numbers,valid", [
    pytest.param([2, 3], True, id="QA21-proper-fraction"),
    pytest.param([0, 3], True, id="QA22-zero-part"),
    pytest.param([3, 3], True, id="QA23-whole-fraction"),
    pytest.param([4, 3], False, id="QA24-improper-not-proper-circle"),
    pytest.param([2, 0], False, id="QA25-positive-denominator"),
    pytest.param([2.5, 3], False, id="QA26-whole-segment-counts"),
    pytest.param([25, 30], False, id="QA27-finite-renderer-cap"),
    pytest.param([2], False, id="QA28-paired-parameters-required"),
])
def test_fraction_renderer_has_meaningful_bounded_parameters(numbers, valid):
    value = fraction(numbers)
    if valid:
        assert Graphic.model_validate(value).numbers == numbers
    else:
        with pytest.raises(ValueError):
            Graphic.model_validate(value)


ORIGINALS = ["I play football.", "She plays football.", "They play football.", "We play football."]
SOURCE = "\n".join(ORIGINALS)


@pytest.mark.parametrize("change,valid", [
    pytest.param("two", True, id="QA29-two-original-examples"),
    pytest.param("four", True, id="QA30-four-original-examples"),
    pytest.param("duplicate", False, id="QA31-no-duplicate-word-boxes"),
    pytest.param("wrong_case", False, id="QA32-original-case-preserved"),
    pytest.param("reordered", False, id="QA33-no-invented-reordering"),
    pytest.param("unrelated_question", False, id="QA34-question-anchor-required"),
    pytest.param("substring_question", False, id="QA35-whole-expression-anchor"),
    pytest.param("intro", True, id="QA36-intro-does-not-pretend-question-grading"),
])
def test_language_comparison_is_literal_and_question_bound(change, valid):
    block = {**fraction([]), "kind": "forms", "variant": "classification", "source_excerpt": SOURCE,
        "labels": ORIGINALS[:4 if change == "four" else 2]}
    q = question("Which word changes in I play football.?", "play", "short", [])
    if change == "duplicate":
        block["labels"] = [ORIGINALS[0], ORIGINALS[0]]
    elif change == "wrong_case":
        block["labels"][0] = "i play football."
    elif change == "reordered":
        block["labels"][1] = "Football plays she."
    elif change == "unrelated_question":
        q["prompt"] = "Which number is even?"
    elif change == "substring_question":
        q["prompt"] = "Which word is in xI play football.y?"
    elif change == "intro":
        q = None
        block["disclosure"] = "given"
    original = copy.deepcopy(block)
    with DB() as db:
        recipe = db.get(VisualReference, ("language.forms.original_comparison", 1)).recipe
        def check():
            graphic = Graphic.model_validate(block)
            validate_question({"version": 1, "evidence_kind": "knowledge", "blocks": [block]},
                q or {"prompt": "", "type": "short", "answer": "", "accepted": []}, [SOURCE], PROFILES["Englisch"],
                structured=True, subject="Englisch")
            visual_references._meaningful(graphic, recipe, sources=[SOURCE], question=q)
        if valid:
            check()
        else:
            with pytest.raises(ValueError):
                check()
    assert block == original


@pytest.fixture
def profile(api, household):
    fixture = existing_profile.__wrapped__(api, household)
    yield next(fixture)
    fixture.close()


@pytest.mark.parametrize("state", [
    pytest.param("exhausted", id="QA37-exhausted-plan-does-not-intercept-answer"),
    pytest.param("unsupported_clarify", id="QA38-false-clarification-does-not-intercept-answer"),
    pytest.param("generic_smaller_step", id="QA39-optional-plan-is-not-answer-prerequisite"),
    pytest.param("genuine_explanation", id="QA40-real-saved-explanation-stays-protected"),
])
def test_actual_answer_endpoint_preserves_attempts_and_finite_learning_flow(profile, monkeypatch, state):
    client, uid, *_ = profile
    monkeypatch.setattr("schulpilot.providers.request_provider", lambda *_a, **_k: pytest.fail("No provider in answer tests"))
    with DB.begin() as db:
        previous = list(db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created, Attempt.id)))
        before = [(a.id, a.answer, a.outcome, a.assisted, copy.deepcopy(a.evaluation)) for a in previous]
        step = {"kind": "clarify_assessment" if state == "unsupported_clarify" else "explain",
            "question_id": "sum", "learning_goal_id": None, "resource_id": None,
            "evidence_refs": ["attempt:" + previous[-1].id], "reason": "Künstlicher gespeicherter Lernschritt.",
            "expected_result": "Den nächsten bewussten Schritt wählen.", "on_success": None, "on_error": None}
        memory = db.get(LearningMemory, uid)
        memory.working = {**memory.working, "instructional_plan": {"version": 1,
            "steps": [step], "cursor": 0 if state in ("unsupported_clarify", "genuine_explanation") else 1, "shown": False}}
        if state == "generic_smaller_step":
            db.add(Activity(child_id=db.get(LearningUnit, uid).child_id, unit_id=uid,
                kind="feedback", detail={"kind": "too_hard", "question_id": "sum"}))
        usage_count = db.scalar(select(func.count()).select_from(Usage))
        key = next(q["answer"] for q in db.get(LearningUnit, uid).questions if q["id"] == "sum")
    body = {"answer": key, "request_id": "qa120-third-answer-unique", "guided_feedback": True}
    response = client.post(f"/api/units/{uid}/questions/sum/answer", json=body)
    if state == "genuine_explanation":
        assert response.status_code == 409
    else:
        assert response.status_code == 200, response.text
        assert response.json()["outcome"] == "correct" and response.json()["assisted"]
        replay = client.post(f"/api/units/{uid}/questions/sum/answer", json=body)
        assert replay.status_code == 200 and replay.json()["attempt_id"] == response.json()["attempt_id"]
        value = response.json()["unit"]
        assert value["pending_feedback"]["attempt_id"] == response.json()["attempt_id"]
        assert value["status"] == "active"  # The genuinely unattempted second question remains.
    with DB() as db:
        after = list(db.scalars(select(Attempt).where(Attempt.unit_id == uid).order_by(Attempt.created, Attempt.id)))
        assert [(a.id, a.answer, a.outcome, a.assisted, a.evaluation) for a in after[:2]] == before
        assert len(after) == 2 if state == "genuine_explanation" else len(after) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == usage_count
