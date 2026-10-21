"""Artificial geometry cases; no private notebook or child data."""

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot.answer_evaluation import VERSION, evaluate
from schulpilot.db import DB, Activity, Attempt, AttemptAssessment, Job, LearningUnit, Usage, now
from schulpilot.main import app
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def rectangle(**changes):
    return {
        "id": "rectangle-area", "type": "short",
        "prompt": "Übung: Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in cm²?",
        "answer": "28 cm²", "accepted": [], "options": [],
        "hints": ["Die Fläche berechnest du mit Länge mal Breite."],
        "explanation": "7 cm mal 4 cm ergibt 28 cm².", **changes,
    }


@pytest.mark.parametrize("answer", ["28", " 28 ", "28,0", "28.00", "28 cm²", "28cm2", "28 cm^2"])
def test_number_and_area_notation_use_the_unit_supplied_by_the_question(answer):
    verdict = evaluate(rectangle(), answer)
    assert verdict["outcome"] == verdict["dimensions"]["content"] == "correct"
    assert verdict["method"] == VERSION


@pytest.mark.parametrize("answer", ["11", "22", "27,999", "29", "56 cm²"])
def test_wrong_rectangle_values_are_definitely_incorrect(answer):
    assert evaluate(rectangle(), answer)["outcome"] == "incorrect"


@pytest.mark.parametrize("key", ["11 cm²", "56 cm²", "28 m²", "nicht geprüft"])
def test_stored_key_must_agree_with_the_given_sides_even_for_an_exact_match(key):
    q = rectangle(answer=key, accepted=["28"])
    assert evaluate(q, key)["outcome"] == evaluate(q, "28")["outcome"] == "uncertain"


@pytest.mark.parametrize("answer", ["28 m²", "28 mm²"])
def test_an_explicit_wrong_unit_is_not_ignored(answer):
    verdict = evaluate(rectangle(), answer)
    assert verdict["outcome"] == "incorrect"
    assert verdict["dimensions"] == {"content": "correct", "form": "incorrect"}


@pytest.mark.parametrize("instruction", ["Gib das Ergebnis mit Einheit an.", "Nenne Zahl und Einheit."])
def test_explicitly_requested_written_unit_is_still_required(instruction):
    q = rectangle(prompt=rectangle()["prompt"] + " " + instruction)
    assert evaluate(q, "28")["dimensions"] == {"content": "correct", "form": "incorrect"}
    assert evaluate(q, "28 cm²")["outcome"] == "correct"


def test_decimal_sides_are_multiplied_exactly_and_gap_inputs_share_the_check():
    q = rectangle(type="gap", prompt="Ein Rechteck ist 2,5 m lang und 1,2 m breit. Wie groß ist seine Fläche in m²?",
                  answer="3 m²")
    assert evaluate(q, "3,00")["outcome"] == "correct"
    assert evaluate(q, "3.0001")["outcome"] == "incorrect"


def test_triangle_uses_the_same_given_unit_convention():
    q = rectangle(prompt="Ein Dreieck hat g = 8 cm und h = 3 cm. Wie groß ist seine Fläche in cm²?",
                  answer="12 cm²")
    assert evaluate(q, "12")["outcome"] == "correct"
    assert evaluate(q, "24")["outcome"] == "incorrect"
    q["prompt"] += " Nenne Zahl und Einheit."
    assert evaluate(q, "12")["dimensions"] == {"content": "correct", "form": "incorrect"}
    assert evaluate(q, "12 cm²")["outcome"] == "correct"


@pytest.mark.parametrize("answer", ["28 oder 29", "28, weil der Umfang 28 ist", "ungefähr 28", "28 cm"])
def test_unrecognised_prose_and_dimension_do_not_gain_a_numeric_success(answer):
    assert evaluate(rectangle(), answer)["outcome"] == "uncertain"


def test_unknown_geometry_and_mixed_units_are_not_guessed():
    for prompt in (
        "Ein Rechteck ist 7 cm lang und 4 m breit. Wie groß ist seine Fläche in cm²?",
        "Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in m²?",
        "Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist sein Umfang in cm?",
        "Ein Rechteck ist 7 cm lang und 4 cm breit. Daraus wird ein Kreis ausgeschnitten. Wie groß ist die Fläche?",
    ):
        assert evaluate(rectangle(prompt=prompt), "28")["outcome"] == "uncertain"


def test_new_numeric_answer_is_correct_in_the_guided_learning_room(normal_unit):
    kid, uid, mid, *_ = normal_unit
    q = rectangle()
    with DB.begin() as db:
        unit = db.get(LearningUnit, uid)
        # Keep the round open: completion has its own existing coach job.
        unit.questions = [q, unit.questions[1]]
        unit.explanation = q["explanation"]
    assert kid.post(f"/api/units/{uid}/start").status_code == 200
    response = kid.post(f"/api/units/{uid}/questions/{q['id']}/answer",
                        json={"answer": "28", "request_id": "rectangle-number-answer", "guided_feedback": True})
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["outcome"] == "correct" and not value["assisted"]
    assert value["unit"]["pending_feedback"]["question_id"] == q["id"]
    assert value["unit"]["learning_session"]["observations"]["independent_first_answers"] == 1
    saved = kid.get(f"/api/units/{uid}").json()
    assert saved["pending_feedback"]["outcome"] == "correct"
    assert saved["learning_progress"]["practice"]["uncertain_tasks"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1


@pytest.mark.parametrize("assisted", [False, True])
def test_explicit_recheck_corrects_only_the_verdict_with_history_and_no_new_practice(api, household, assisted):
    _, child = household
    q, stamp = rectangle(), now() - 3600
    with DB.begin() as db:
        unit = LearningUnit(child_id=child["id"], subject="Mathematik", topic="Rechteckflächen",
                            questions=[q], explanation=q["explanation"], provider="synthetic", synthetic=True,
                            status="paused", active_seconds=23)
        db.add(unit)
        db.flush()
        uid = unit.id
        attempt = Attempt(unit_id=uid, question_id=q["id"], answer="28", outcome="uncertain", created=stamp,
                          assisted=assisted, evaluation={"method": "subject_rules_v3", "outcome": "uncertain",
                          "support_reasons": ["hint"] if assisted else [], "attempt_number": 1,
                          "independent_attempt": not assisted})
        db.add(attempt)
        db.flush()
        aid = attempt.id
    route = f"/api/units/{uid}/questions/{q['id']}/recheck"
    assert api.post(route).status_code == 403  # parent cannot submit as child
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        for _ in range(2):
            response = kid.post(route)
            assert response.status_code == 200, response.text
            assert response.json()["outcome"] == "correct"
            assert response.json()["assisted"] is assisted
        saved = kid.get(f"/api/units/{uid}").json()
        assert saved["learning_session"]["observations"]["uncertain_answers"] == 0
        assert saved["learning_progress"]["practice"]["uncertain_tasks"] == 0
    with DB() as db:
        attempt = db.get(Attempt, aid)
        assert attempt.answer == "28" and attempt.created == stamp and attempt.assisted is assisted
        assert attempt.evaluation["support_reasons"] == (["hint"] if assisted else [])
        assert attempt.evaluation["independent_evidence"] is not assisted
        history = list(db.scalars(select(AttemptAssessment)))
        assert len(history) == 1 and history[0].previous_outcome == "uncertain" and history[0].outcome == "correct"
        assert db.get(LearningUnit, uid).questions == [q]
        assert db.get(LearningUnit, uid).active_seconds == 23
        assert db.scalar(select(func.count()).select_from(Attempt)) == 1
        for model in (Activity, Job, Usage):
            assert db.scalar(select(func.count()).select_from(model)) == 0
