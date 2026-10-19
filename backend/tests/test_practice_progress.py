"""Every persisted exercise contributes, regardless of schedule or minimum."""


from schulpilot import coaching
from schulpilot.db import DB, Activity, Attempt, Child, LearningUnit, now
from schulpilot.learning import local_day
from schulpilot.learning_progress import read_ledger, totals
from schulpilot.synthetic import sample_unit
from test_learning import child_client, prepared


def stored_unit(db, child_id, *, subject="Biologie", topic="Wirbeltiere", outcomes=("correct",), status="completed", root=None):
    data = sample_unit(0)
    unit = LearningUnit(child_id=child_id, subject=subject, topic=topic, explanation=data["explanation"],
                        questions=data["questions"][:len(outcomes)], provider="synthetic", synthetic=True,
                        status=status, completed=int(now()) if status == "completed" else None,
                        learning_root_id=root, round_kind="learning")
    db.add(unit)
    db.flush()
    for question, outcome in zip(unit.questions, outcomes, strict=True):
        db.add(Attempt(unit_id=unit.id, question_id=question["id"], answer="synthetic-only", outcome=outcome, assisted=False))
    return unit


def test_partial_exercise_and_retries_are_immediate_and_identical_for_parent_and_child(api):
    demo, unit_id = prepared(api)
    with DB() as db:
        expected = db.get(LearningUnit, unit_id).questions[0]["answer"]
    with child_client(demo) as child:
        assert child.post(f"/api/units/{unit_id}/start").status_code == 200
        assert child.post(f"/api/units/{unit_id}/questions/sum/answer", json={"answer": "2/8"}).status_code == 200
        first = child.get(f"/api/children/{demo['child_id']}/learning-progress").json()
        assert first["totals"]["practiced_tasks"] == first["totals"]["attempts"] == 1
        assert first["totals"]["needs_practice_tasks"] == first["totals"]["ongoing_rounds"] == 1
        assert first["totals"]["completed_rounds"] == 0
        assert first["totals"] == api.get(f"/api/children/{demo['child_id']}/learning-progress").json()["totals"]
        assert child.post(f"/api/units/{unit_id}/questions/sum/hint").status_code == 200
        assert child.post(f"/api/units/{unit_id}/questions/sum/answer", json={"answer": expected}).status_code == 200
        second = child.get(f"/api/children/{demo['child_id']}/learning-progress").json()["totals"]
        assert second["practiced_tasks"] == 1 and second["attempts"] == 2
        assert second["assisted_tasks"] == 1 and second["independent_tasks"] == second["needs_practice_tasks"] == 0
        assert second["hints_used"] == 1
        assert child.get(f"/api/units/{unit_id}").json()["learning_progress"]["practice"]["practiced_tasks"] == 1


def test_voluntary_normal_rounds_after_minimum_on_free_day_and_different_roots_all_count(api):
    demo, unit_id = prepared(api)
    with DB.begin() as db:
        kid = db.get(Child, demo["child_id"])
        today = local_day(kid)
        kid.preferences = {"weekdays": [(today.weekday() + 1) % 7], "daily_minutes": 5}
        db.add(Activity(child_id=kid.id, kind="active_time", detail={"seconds": 600}))
        stored_unit(db, kid.id, outcomes=("correct", "incorrect"))
        stored_unit(db, kid.id, outcomes=("uncertain",), status="paused")
        stored_unit(db, kid.id, subject="Englisch", topic="Words", outcomes=("correct",))
    with child_client(demo) as child:
        all_data = child.get(f"/api/children/{demo['child_id']}/learning-progress").json()
        assert all_data["totals"]["practiced_tasks"] == 4
        assert all_data["totals"]["attempts"] == 4
        assert all_data["totals"]["independent_tasks"] == 2
        assert all_data["totals"]["uncertain_tasks"] == all_data["totals"]["needs_practice_tasks"] == 1
        assert all_data["totals"]["practiced_rounds"] == 3
        biology = child.get(f"/api/children/{demo['child_id']}/learning-progress?subject=Biologie").json()
        assert biology["selected_totals"]["practiced_tasks"] == 3
        assert len(biology["items"]) == 1 and biology["items"][0]["topic"] == "Wirbeltiere"
        rounds = child.get(f"/api/children/{demo['child_id']}/learning-progress?subject=Biologie&topic=Wirbeltiere").json()
        assert rounds["level"] == "rounds" and len(rounds["items"]) == 2
        assert rounds["totals"]["practiced_tasks"] == 4
        assert all("questions" not in row and "answer" not in row and "prompt" not in row for row in rounds["items"])
        overview = child.get(f"/api/children/{demo['child_id']}/overview?compact=true").json()
        assert overview["plan"]["free_day"] and not overview["plan"]["goal_required"]
        assert not overview["plan"]["daily_goal_met"]  # No daily target on a free day.
        assert overview["plan"]["daily_active_seconds"] == 600
        # Empty, prepared rounds must not appear as performed work.
        assert unit_id not in {row["id"] for row in rounds["items"]}


def test_topic_evidence_combines_independent_roots_and_retains_real_retrieval_days(api):
    demo, root_id = prepared(api)
    with DB.begin() as db:
        root = db.get(LearningUnit, root_id)
        independent = stored_unit(db, root.child_id, subject=root.subject, topic=root.topic)
        stored_unit(db, root.child_id, subject=root.subject, topic=root.topic, outcomes=("uncertain",), root=root.id)
        db.flush()
        result = coaching.progress(db, root)
        assert result["topic_practice"]["practiced_tasks"] == 2
        assert result["topic_practice"]["independent_tasks"] == 1
        assert result["topic_practice"]["uncertain_tasks"] == 1
        assert result["practice"]["practiced_tasks"] == 1
        assert result["successful_check_days"] == 0 and not result["secure_observation"]
        assert independent.id not in (root.id,)


def test_all_history_is_counted_and_pages_are_stable_beyond_old_one_hundred_roots(api):
    demo, _ = prepared(api)
    with DB.begin() as db:
        for index in range(123):
            stored_unit(db, demo["child_id"], topic=f"Thema {index:03d}")
    url = f"/api/children/{demo['child_id']}/learning-progress?subject=Biologie&page_size=20"
    first = api.get(url).json()
    last = api.get(url + "&page=7").json()
    assert first["totals"]["practiced_tasks"] == last["totals"]["practiced_tasks"] == 123
    assert first["pagination"]["total"] == 123 and last["pagination"]["pages"] == 7
    assert len(first["items"]) == 20 and len(last["items"]) == 3
    assert api.get(url + "&page=9999").json()["pagination"]["page"] == 7
    assert api.get(url).json() == first


def test_ledger_never_loads_answer_bodies_and_keeps_unknown_verdict_unclassified(api):
    from sqlalchemy import event

    demo, _ = prepared(api)
    with DB.begin() as db:
        stored_unit(db, demo["child_id"], outcomes=("future_unknown",))
        statements = []

        def capture(_connection, _cursor, statement, _parameters, _context, _many):
            statements.append(statement.lower())

        event.listen(db.bind, "before_cursor_execute", capture)
        try:
            result = totals(read_ledger(db, demo["child_id"]))
        finally:
            event.remove(db.bind, "before_cursor_execute", capture)
        assert result["practiced_tasks"] == result["uncertain_tasks"] == 1
        assert result["independent_tasks"] == result["needs_practice_tasks"] == 0
        assert statements and all("attempts.answer" not in query and "learning_units.questions" not in query for query in statements)


def test_progress_is_scoped_and_revoked_child_cannot_read_it(api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    demo, _ = prepared(api)
    with TestClient(app, headers=HEADERS) as other:
        foreign = other.post("/api/demo").json()
    assert api.get(f"/api/children/{foreign['child_id']}/learning-progress").status_code == 404
    with child_client(demo) as child:
        assert child.get(f"/api/children/{foreign['child_id']}/learning-progress").status_code == 404
        child.post("/api/auth/logout")
        assert child.get(f"/api/children/{demo['child_id']}/learning-progress").status_code == 401
    assert api.get(f"/api/children/{demo['child_id']}/learning-progress?page_size=999").status_code == 422
    assert api.get(f"/api/children/{demo['child_id']}/learning-progress?topic=Only").status_code == 422
