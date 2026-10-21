"""Synthetic controller trace, original errors, distinct goals and later recall."""

import copy
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from schulpilot.db import DB, Attempt, Child, LearningUnit, Material, UnitSource, now
from schulpilot.learning_knowledge import evidence
from sqlalchemy import select
from test_adaptive_plan import action, session, submit
from test_adaptive_plan import fraction_profile as original_profile


@pytest.fixture
def profile(api, household):
    yield from original_profile.__wrapped__(api, household)


def test_full_fraction_trace_retains_errors_and_schedules_distinct_later_recall(profile):
    client, uid, mid, _, _, child = profile
    submit(client, uid, "sum", "2/9")
    assert action(client, uid, "review_prerequisite", "trace-probe-0001").status_code == 200
    probe = session(client, uid)["action"]["question_id"]
    submit(client, uid, probe, "2/6", key="trace-probe-answer-0001")
    assert action(client, uid, "visual_example", "trace-example-0001").status_code == 200
    assert action(client, uid, "check_understanding", "trace-fresh-0001").status_code == 200
    fresh = session(client, uid)["action"]["question_id"]
    submit(client, uid, fresh, "3/8", key="trace-fresh-answer-0001")
    knowledge = client.get(f"/api/units/{uid}/learning-session/knowledge").json()
    by_label = {g["label"]: g for g in knowledge["long_term"]}
    assert by_label["Brüche addieren"]["independent"] == 1
    assert by_label["Brüche addieren"]["needs_practice"] == 1
    assert by_label["Gleichwertige Brüche erkennen"]["independent"] == 1
    assert by_label["Brüche addieren"]["confidence"] != "repeated_recall"
    assert by_label["Brüche addieren"]["review_due"]
    # A reload only derives evidence. It does not manufacture another check day.
    assert client.get(f"/api/units/{uid}/learning-session/knowledge").json() == knowledge
    with DB.begin() as db:
        for attempt in db.scalars(select(Attempt).where(Attempt.unit_id == uid)):
            attempt.created = int(now()) - 9 * 86400
        template = copy.deepcopy(db.get(LearningUnit, uid).questions[0])
        revision = db.get(Material, mid).revision
    for day, prompt, answer in ((-8, "Berechne 2/5 + 1/10.", "1/2"),
            (-4, "Berechne 1/4 + 1/6.", "5/12"), (0, "Berechne 1/3 + 1/12.", "5/12")):
        with DB.begin() as db:
            q = dict(template, id="recall", prompt=prompt, answer=answer, explanation=prompt + " Ergebnis: " + answer)
            unit = LearningUnit(child_id=child["id"], material_id=mid, subject="Mathematik", topic="Brüche",
                explanation="Erinnere dich an die gemeinsame Einteilung.", questions=[q],
                learning_root_id=uid, followup_of=uid, round_kind="spaced_review", introduction_seen=True,
                provider="openai", model="synthetic-model-fixture", synthetic=False)
            db.add(unit)
            db.flush()
            db.add(UnitSource(unit_id=unit.id, material_id=mid, revision=revision))
            check_id = unit.id
        assert client.post(f"/api/units/{check_id}/start").status_code == 200
        result = submit(client, check_id, "recall", answer, key=f"trace-later-answer-{abs(day):04}")
        assert result["outcome"] == "correct" and not result["assisted"]
        with DB.begin() as db:
            attempt = db.get(Attempt, result["attempt_id"])
            attempt.created = int(now()) + day * 86400
    with DB() as db:
        states = evidence(db, db.get(LearningUnit, uid), [db.get(Material, mid)])
        state = next(g for g in states if g["label"] == "Brüche addieren")
        assert state["independent"] == 4 and state["needs_practice"] == 1
        assert state["confidence"] == "repeated_recall"
        assert len(state["successful_check_dates"]) == 3
        zone = ZoneInfo(db.get(Child, child["id"]).preferences.get("timezone", "Europe/Berlin"))
        assert state["review_due"] >= (datetime.fromtimestamp(now(), zone).date() + timedelta(days=7)).isoformat()
    # A corrected source keeps historical practice without asserting current mastery.
    with DB.begin() as db:
        db.get(Material, mid).revision += 1
    assert not client.get(f"/api/units/{uid}/learning-session/knowledge").json()["source_valid"]


def test_repeated_failure_after_help_finishes_without_a_fourth_attempt(profile):
    client, uid, _, _, _, _ = profile
    submit(client, uid, "sum", "2/9")
    action(client, uid, "review_prerequisite", "failure-probe-0001")
    probe = session(client, uid)["action"]["question_id"]
    submit(client, uid, probe, "2/6", key="failure-probe-answer-0001")
    action(client, uid, "visual_example", "failure-example-0001")
    action(client, uid, "check_understanding", "failure-fresh-0001")
    fresh = session(client, uid)["action"]["question_id"]
    for index in range(3):
        value = submit(client, uid, fresh, "2/12", key=f"failure-answer-{index:04}")
        if index < 2:
            action(client, uid, "visual_example", f"failure-example-{index + 2:04}")
            action(client, uid, "practice", f"failure-retry-{index:04}")
    assert value["unit"]["learning_session"]["short_plan"]["phase"] == "closed"
    assert session(client, uid)["action"]["question_id"] == "reduce"
    assert client.post(f"/api/units/{uid}/questions/{fresh}/answer", json={"answer": "3/8"}).status_code == 409


def test_legacy_answers_without_source_revision_remain_practice_not_current_mastery(profile):
    from fractions import Fraction

    from schulpilot.learning_progress import read_ledger, totals

    _, uid, mid, _, _, child = profile
    with DB.begin() as db:
        source = db.get(Material, mid)
        question = copy.deepcopy(db.get(LearningUnit, uid).questions[0])
        # Three old, successful checks would ordinarily satisfy the product's
        # recall criterion. Their legacy material_id proves no source revision.
        for days in (9, 5, 1):
            prompt = f"Berechne 1/{days + 1} + 1/{days + 1}."
            answer = str(Fraction(2, days + 1))
            q = {**question, "prompt": prompt, "answer": answer, "explanation": prompt + " Ergebnis: " + answer}
            old = LearningUnit(child_id=child["id"], material_id=mid,
                subject="Mathematik", topic="Brüche", questions=[q],
                explanation="Künstliche alte Runde.", round_kind="spaced_review",
                status="completed", completed=int(now()) - days * 86400,
                provider="openai", model="synthetic-model-fixture", synthetic=False)
            db.add(old)
            db.flush()
            db.add(Attempt(unit_id=old.id, question_id=q["id"], answer=answer,
                outcome="correct", assisted=False, created=old.completed))
        source.revision += 1
    with DB() as db:
        states = evidence(db, db.get(LearningUnit, uid), [db.get(Material, mid)])
        addition = next(g for g in states if g["label"] == "Brüche addieren")
        assert addition["tasks"] == addition["independent"] == 0
        assert addition["historical_tasks"] == 3
        assert addition["successful_check_dates"] == []
        assert addition["confidence"] == "unverified" and addition["review_due"] is None
        # Original dated answers still count in the ordinary practice overview.
        practice = totals(read_ledger(db, child["id"]))
        assert practice["practiced_tasks"] == practice["independent_tasks"] == 3
        assert len(list(db.scalars(select(Attempt)))) == 3


def test_deliberate_skip_is_idempotent_and_never_an_answer(profile):
    client, uid, _, _, _, _ = profile
    state = session(client, uid)
    body = {"request_key": "skip-artificial-0001", "revision": state["revision"], "question_id": "sum"}
    response = client.post(f"/api/units/{uid}/learning-session/skip", json=body)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "paused"
    assert client.post(f"/api/units/{uid}/learning-session/skip", json=body).status_code == 200
    with DB() as db:
        assert not db.scalar(select(Attempt.id).where(Attempt.unit_id == uid))
        assert db.get(LearningUnit, uid).completed is None
