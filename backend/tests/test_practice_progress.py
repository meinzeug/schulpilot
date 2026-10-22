"""Every persisted exercise contributes, regardless of schedule or minimum."""

import pytest
from schulpilot import coaching
from schulpilot.db import DB, Activity, Attempt, Child, LearningUnit, now
from schulpilot.learning import local_day
from schulpilot.learning_progress import read_ledger, totals
from schulpilot.synthetic import sample_unit
from sqlalchemy import select
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


@pytest.mark.parametrize("outcome,bucket", [("correct", "assisted_tasks"),
    ("uncertain", "uncertain_tasks"), ("incorrect", "needs_practice_tasks")])
def test_exact_timestamp_ties_use_saved_attempt_order_not_random_ids(api, outcome, bucket):
    demo, unit_id = prepared(api)
    with DB.begin() as db:
        db.add(Attempt(id="f" * 32, unit_id=unit_id, question_id="sum", answer="synthetic first",
            outcome="incorrect", assisted=False, created=100.25, evaluation={"attempt_number": 1}))
        db.flush()
        db.add(Attempt(id="0" * 32, unit_id=unit_id, question_id="sum", answer="synthetic second",
            outcome=outcome, assisted=True, created=100.25, evaluation={"attempt_number": 2}))
    data = api.get(f"/api/children/{demo['child_id']}/learning-progress").json()["totals"]
    assert data["practiced_tasks"] == 1 and data["attempts"] == 2
    assert data[bucket] == 1 and data["independent_tasks"] == 0
    assert sum(data[key] for key in ("assisted_tasks", "uncertain_tasks", "needs_practice_tasks")) == 1
    with DB() as db:
        assert [(a.id, a.outcome, a.assisted, a.created) for a in db.scalars(select(Attempt).order_by(Attempt.id))] == [
            ("0" * 32, outcome, True, 100.25), ("f" * 32, "incorrect", False, 100.25)]


def test_real_timestamp_order_remains_authoritative_for_legacy_attempts(api):
    demo, unit_id = prepared(api)
    with DB.begin() as db:
        db.add(Attempt(id="f" * 32, unit_id=unit_id, question_id="sum", answer="synthetic first",
            outcome="incorrect", assisted=False, created=100.25, evaluation={"attempt_number": 3}))
        db.add(Attempt(id="0" * 32, unit_id=unit_id, question_id="sum", answer="synthetic newer legacy",
            outcome="correct", assisted=True, created=100.5, evaluation=None))
    data = api.get(f"/api/children/{demo['child_id']}/learning-progress").json()["totals"]
    assert data["assisted_tasks"] == 1 and data["needs_practice_tasks"] == 0


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


@pytest.mark.parametrize('category,expected_counter', [
    ('independent', 'independent_tasks'), ('assisted', 'assisted_tasks'),
    ('needs_practice', 'needs_practice_tasks'), ('uncertain', 'uncertain_tasks'),
    ('reflection', 'reflection_tasks'),
])
def test_rr020_category_filters_tasks_before_aggregation_without_changing_answers(api, category, expected_counter):
    from schulpilot.db import Job
    from sqlalchemy import func

    demo, unit_id = prepared(api)
    # Six artificial tasks in the SAME round prevent a round-only filter from
    # accidentally passing this test. The retried success is not independent.
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        for index, (outcome, assisted, evaluation) in enumerate([
            ('correct', False, None), ('correct', True, None),
            ('incorrect', False, None), ('uncertain', False, None),
            ('uncertain', False, {'method': 'open_learning_v1'}),
        ]):
            db.add(Attempt(unit_id=unit.id, question_id=f'synthetic-{index}', answer='private synthetic answer',
                           outcome=outcome, assisted=assisted, evaluation=evaluation, created=100 + index))
        db.add(Attempt(unit_id=unit.id, question_id='retried', answer='synthetic old', outcome='incorrect', assisted=False, created=100))
        db.add(Attempt(unit_id=unit.id, question_id='retried', answer='synthetic newer', outcome='correct', assisted=False, created=101))
    with DB() as db:
        before = list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted).order_by(Attempt.id)))
        jobs = db.scalar(select(func.count()).select_from(Job))
    path = f"/api/children/{demo['child_id']}/learning-progress"
    response = api.get(path, params={'category': category})
    assert response.status_code == 200
    data = response.json()
    expected = 2 if category == 'assisted' else 1
    assert data['category'] == category
    assert data['totals']['practiced_tasks'] == 6
    assert data['selected_totals']['practiced_tasks'] == expected
    assert data['selected_totals'][expected_counter] == expected
    assert data['selected_totals']['attempts'] == (3 if category == 'assisted' else 1)
    assert len(data['items']) == 1
    assert data['items'][0][expected_counter] == expected
    assert 'private synthetic answer' not in response.text
    with child_client(demo) as child:
        assert child.get(path, params={'category': category}).json() == data
    with DB() as db:
        assert list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome, Attempt.assisted).order_by(Attempt.id))) == before
        assert db.scalar(select(func.count()).select_from(Job)) == jobs


def test_rr020_category_validation_pagination_and_family_permissions(api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    demo, _ = prepared(api)
    with DB.begin() as db:
        for index in range(4):
            stored_unit(db, demo['child_id'], topic=f'Synthetisches Thema {index}', outcomes=('correct', 'incorrect'))
    path = f"/api/children/{demo['child_id']}/learning-progress"
    result = api.get(path, params={'category': 'needs_practice', 'subject': 'Biologie', 'page_size': 2, 'page': 2}).json()
    assert result['pagination'] == {'page': 2, 'pages': 2, 'page_size': 2, 'total': 4}
    assert result['selected_totals']['practiced_tasks'] == 4
    assert all(row['practiced_tasks'] == row['needs_practice_tasks'] == 1 for row in result['items'])
    assert api.get(path, params={'category': 'invented'}).status_code == 422
    empty = api.get(path, params={'category': 'uncertain'}).json()
    assert empty['items'] == [] and empty['selected_totals']['practiced_tasks'] == 0
    with TestClient(app, headers=HEADERS) as other:
        other.post('/api/demo')
        assert other.get(path, params={'category': 'needs_practice'}).status_code == 404
