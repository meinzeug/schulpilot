"""Complete artificial arithmetic prompts; never infer from arbitrary prose."""
import pytest
from schulpilot.answer_evaluation import evaluate
from schulpilot.db import DB, Attempt, AttemptAssessment, LearningUnit, Usage
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def question(term, key, **kw):
    return {"type": "short", "prompt": f"Selbst erstellte Übung: Wie viel ist \\({term}\\)? Gib nur das Ergebnis ein.",
            "answer": key, "accepted": [], **kw}


@pytest.mark.parametrize("term,key,answer,outcome", [
    ("81 - 35", "46", "0", "incorrect"), ("81 - 35", "46", "46", "correct"),
    ("47 + 26", "73", "73,0", "correct"), ("9 × 5", "45", "45", "correct"),
    ("2,5 + 1,2", "3,7", "3.700", "correct"), ("0,1 + 0,2", "0,3", "0.3000001", "uncertain"),
    (r"7 \cdot 4", "28", "28", "correct"), (r"7 \times 4", "28", "11", "incorrect"),
    (r"7 \div 4", "1,75", "7/4", "correct"), ("3 : 6", "0,5", "1/2", "correct"),
    ("2 - 5", "-3", "−3", "correct"), ("-3 + 2", "-1", "-1", "correct"),
    ("9 + -2", "7", "7", "correct"), ("8 / 4", "2", "2", "correct"),
])
def test_exact_two_number_results(term, key, answer, outcome):
    assert evaluate(question(term, key), answer)["outcome"] == outcome


@pytest.mark.parametrize("key", ["45", "0", "46 cm", "Ungeprüft"])
def test_bad_key_is_never_accepted_even_as_an_exact_answer(key):
    q = question("81 - 35", key, accepted=["0"])
    assert evaluate(q, key)["outcome"] == evaluate(q, "46")["outcome"] == "uncertain"


@pytest.mark.parametrize("prompt", [
    "Wie viel ist 81 - 35? Runde auf Zehner.",
    "Wie viel ist 81 - 35? Begründe den Rechenweg.",
    "Ein Bus hat 81 Plätze, 35 sind belegt. Wie viele Plätze sind frei?",
    "Berechne den Zähler von 81/35.", "Berechne x aus x + 35 = 81.",
    "Wie viel ist 81 - 35 + 4?", "Wie viel ist 2 cm + 3 cm?",
])
def test_unknown_or_additional_requirements_stay_open(prompt):
    assert evaluate(question("", "46", prompt=prompt), "0")["outcome"] == "uncertain"


def test_zero_division_and_incomplete_tex_stay_open():
    assert evaluate(question("4 / 0", "0"), "0")["outcome"] == "uncertain"
    assert evaluate(question("", "46", prompt=r"Wie viel ist \(81 - 35?"), "0")["outcome"] == "uncertain"
    assert evaluate(question("81 - 35", "46"), "46 oder 47")["outcome"] == "uncertain"


def test_bad_numeric_accepted_variant_does_not_override_computation():
    assert evaluate(question("81 - 35", "46", accepted=["0"]), "0")["outcome"] == "incorrect"


def test_new_answers_and_explicit_legacy_recheck_use_the_computed_value(normal_unit):
    kid, uid, *_ = normal_unit
    q = question("81 - 35", "46", id="arithmetic", options=[], hints=["Rechne in zwei Schritten."], explanation="81 - 30 - 5 = 46.")
    with DB.begin() as db:
        unit = db.get(LearningUnit, uid)
        unit.questions = [q, unit.questions[1]]
    assert kid.post(f"/api/units/{uid}/start").status_code == 200
    path = f"/api/units/{uid}/questions/arithmetic"
    reply = kid.post(path + "/answer", json={"answer": "0", "request_id": "artificial-arithmetic-zero"})
    assert reply.status_code == 200 and reply.json()["outcome"] == "incorrect", reply.text
    with DB.begin() as db:
        attempt = db.scalar(select(Attempt).where(Attempt.unit_id == uid))
        attempt.outcome = "uncertain"  # historical v4 verdict, original answer preserved
        attempt.evaluation = {**attempt.evaluation, "outcome": "uncertain", "method": "subject_rules_v4"}
    for _ in range(2):
        reviewed = kid.post(path + "/recheck")
        assert reviewed.status_code == 200 and reviewed.json()["outcome"] == "incorrect", reviewed.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        assert db.scalar(select(func.count()).select_from(AttemptAssessment)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(Attempt)).answer == "0"
