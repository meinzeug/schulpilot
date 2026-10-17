"""Real child routes: minimum goals are evidence, never learning stop rules."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import learning
from schulpilot.db import DB, Activity, Assignment, Attempt, Child, Job, LearningUnit, Usage
from schulpilot.main import app
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


@pytest.fixture
def learner(api, household, monkeypatch):
    _, kid = household
    clock = [int(datetime(2026, 10, 15, 12, tzinfo=timezone.utc).timestamp())]
    monkeypatch.setattr(learning, "now", lambda: clock[0])
    monkeypatch.setattr(learning, "local_day", lambda _: datetime.fromtimestamp(clock[0], timezone.utc).date())
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {
            "weekdays": list(range(7)), "timezone": "UTC", "daily_minutes": 5,
            "weekly_minutes": 5, "session_minutes": 5, "break_minutes": 5,
        }
        units = [LearningUnit(child_id=child.id, **sample_unit(), provider="fixture", synthetic=True,
                              estimated_minutes=8, created=clock[0] - 100) for _ in range(2)]
        db.add_all(units)
        db.flush()
        ids = [unit.id for unit in units]
    with TestClient(app, headers=HEADERS) as child_api:
        login = child_api.post("/api/auth/login", json={
            "username": "test-child", "password": "secure-child-pass-123",
        })
        assert login.status_code == 200
        child_api.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield child_api, kid["id"], ids, clock
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def seed_time(child_id, unit_id, clock, seconds, *, segment=0, status="active"):
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.status = status
        unit.active_seconds = seconds
        unit.segment_seconds = segment
        unit.heartbeat = clock[0] - 20
        if seconds:
            db.add(Activity(child_id=child_id, unit_id=unit_id, kind="active_time",
                            detail={"seconds": seconds}, created=clock[0] - 20))


def total_time(child_id):
    with DB() as db:
        return sum(event.detail["seconds"] for event in db.scalars(select(Activity).where(
            Activity.child_id == child_id, Activity.kind == "active_time",
        )))


def test_goals_use_exact_saved_seconds_without_estimated_completion_time(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 299)
    with DB.begin() as db:
        completed = db.get(LearningUnit, ids[1])
        completed.status, completed.completed, completed.estimated_minutes = "completed", clock[0] - 1, 120
    plan = client.get(f"/api/children/{child_id}/overview?compact=true").json()["plan"]
    assert plan["daily_goal_minutes"] == plan["weekly_goal_minutes"] == 5
    assert plan["daily_goal_met"] is False and plan["weekly_goal_met"] is False
    assert total_time(child_id) == 299


def test_weekly_and_daily_goals_remain_independent_actual_evidence(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 299)
    with DB.begin() as db:
        db.add(Activity(child_id=child_id, kind="active_time", detail={"seconds": 1}, created=clock[0] - 86400))
    plan = client.get(f"/api/children/{child_id}/overview?compact=true").json()["plan"]
    assert plan["daily_goal_met"] is False and plan["weekly_goal_met"] is True
    assert total_time(child_id) == 300


def test_start_and_answers_continue_after_all_old_time_limits(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 1200, segment=900, status="paused")
    with DB.begin() as db:
        db.get(LearningUnit, ids[0]).break_until = clock[0] + 600
    started = client.post(f"/api/units/{ids[0]}/start")
    assert started.status_code == 200, started.text
    assert started.json()["status"] == "active" and started.json()["break_until"] is None
    with DB() as db:
        question = db.get(LearningUnit, ids[0]).questions[0]
    answer = client.post(f"/api/units/{ids[0]}/questions/{question['id']}/answer", json={"answer": question["answer"]})
    assert answer.status_code == 200 and answer.json()["outcome"] == "correct"
    plan = client.get(f"/api/children/{child_id}/overview?compact=true").json()["plan"]
    assert plan["daily_goal_met"] is True and plan["weekly_goal_met"] is True
    assert plan["can_continue_voluntarily"] is True
    assert total_time(child_id) == 1200


def test_heartbeat_keeps_counting_past_daily_weekly_and_session_targets(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 1200, segment=900)
    for expected in (1220, 1240):
        response = client.post(f"/api/units/{ids[0]}/heartbeat")
        assert response.status_code == 200
        result = response.json()
        measured = result.pop("learning_time")
        assert result == {
            "active_seconds_approx": expected, "status": "active", "break_until": None,
            "break_recommended": True, "break_minutes": 5,
        }
        assert measured["daily_active_seconds"] == expected
        assert measured["daily_goal_met"] is True
        assert total_time(child_id) == expected
        clock[0] += 20


def test_twenty_minute_round_finished_in_twelve_still_requires_eight_minutes(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 12 * 60)
    with DB.begin() as db:
        child = db.get(Child, child_id)
        child.preferences = {**child.preferences, "daily_minutes": 20, "weekly_minutes": 100}
        unit = db.get(LearningUnit, ids[0])
        unit.estimated_minutes = 20
        unit.status, unit.completed = "completed", clock[0]
    view = client.get(f"/api/units/{ids[0]}").json()
    measured = view["learning_time"]
    assert measured["daily_active_seconds"] == 720
    assert measured["daily_remaining_seconds"] == 480
    assert measured["daily_goal_met"] is False and measured["goal_required"] is True
    plan = client.get(f"/api/children/{child_id}/overview?compact=true").json()["plan"]
    assert plan["daily_goal_met"] is False and plan["daily_remaining_minutes"] == 8
    # A subsequent explicit round resumes the same measured day, not its estimate.
    started = client.post(f"/api/units/{ids[1]}/start").json()
    assert started["learning_time"] == measured
    clock[0] += 20
    pulse = client.post(f"/api/units/{ids[1]}/heartbeat").json()["learning_time"]
    assert pulse["daily_active_seconds"] == 740 and pulse["daily_remaining_seconds"] == 460
    assert pulse["daily_goal_met"] is False
    assert total_time(child_id) == 740


def test_parent_family_and_unit_show_the_same_measured_time_without_sibling_credit(api, learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 299)
    with DB.begin() as db:
        family_id = db.get(Child, child_id).family_id
        db.add_all([
            Assignment(child_id=child_id, kind="parent", subject="Mathematik", topic="Offener Lernauftrag"),
            Assignment(child_id=child_id, kind="parent", subject="Mathematik", topic="Erledigter Lernauftrag", done=True),
        ])
    sibling = api.post(f"/api/families/{family_id}/children", json={
        "username": "synthetic-sibling", "password": "secure-child-pass-123",
        "display_name": "Künstliches Geschwisterkind", "grade": 6,
    })
    assert sibling.status_code == 201
    family = api.get(f"/api/families/{family_id}").json()
    children = {child["id"]: child for child in family["children"]}
    measured = client.get(f"/api/units/{ids[0]}").json()["learning_time"]
    assert children[child_id]["learning_time"] == measured
    assert measured["daily_active_seconds"] == 299 and measured["daily_goal_met"] is False
    assert children[child_id]["open_assignments"] == 1
    assert children[sibling.json()["id"]]["learning_time"]["daily_active_seconds"] == 0
    assert children[sibling.json()["id"]]["open_assignments"] == 0
    assert client.get(f"/api/families/{family_id}").status_code == 403


def test_baseline_and_long_idle_never_credit_background_time(learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 100)
    clock[0] += 10  # A short background gap must not be counted either.
    response = client.post(f"/api/units/{ids[0]}/heartbeat", json={"baseline": True})
    assert response.status_code == 200 and response.json()["active_seconds_approx"] == 100
    clock[0] += 3
    assert client.post(f"/api/units/{ids[0]}/heartbeat").json()["active_seconds_approx"] == 103
    clock[0] += 17
    assert client.post(f"/api/units/{ids[0]}/heartbeat").json()["active_seconds_approx"] == 120
    clock[0] += 600
    assert client.post(f"/api/units/{ids[0]}/heartbeat").json()["active_seconds_approx"] == 120
    clock[0] += 20
    assert client.post(f"/api/units/{ids[0]}/heartbeat").json()["active_seconds_approx"] == 140
    assert total_time(child_id) == 140


@pytest.mark.parametrize("parallel", [False, True])
def test_two_units_do_not_double_count_the_same_child_interval(learner, parallel):
    client, child_id, ids, clock = learner
    for unit_id in ids:
        seed_time(child_id, unit_id, clock, 0)

    def beat(unit_id):
        with TestClient(app, headers=dict(client.headers)) as device:
            return device.post(f"/api/units/{unit_id}/heartbeat").status_code

    for expected in (20, 40):
        if parallel:
            with ThreadPoolExecutor(max_workers=2) as pool:
                statuses = list(pool.map(beat, ids))
        else:
            statuses = [beat(unit_id) for unit_id in ids]
        assert statuses == [200, 200]
        assert total_time(child_id) == expected
        clock[0] += 20
    with DB() as db:
        assert sum(db.get(LearningUnit, unit_id).active_seconds for unit_id in ids) == 40


def test_free_day_and_long_parent_pause_are_recommendations_for_voluntary_start(learner):
    client, child_id, ids, clock = learner
    with DB.begin() as db:
        child = db.get(Child, child_id)
        pause_until = (datetime.fromtimestamp(clock[0], timezone.utc).date() + timedelta(days=3)).isoformat()
        child.preferences = {**child.preferences, "weekdays": [], "pause_until": pause_until}
    plan = client.get(f"/api/children/{child_id}/overview?compact=true").json()["plan"]
    assert plan["goal_required"] is False
    assert client.post(f"/api/units/{ids[0]}/start").status_code == 200
    assert total_time(child_id) == 0


def test_manual_pause_is_preserved_and_parents_cannot_write_child_learning_time(api, learner):
    client, child_id, ids, clock = learner
    seed_time(child_id, ids[0], clock, 100)
    assert client.post(f"/api/units/{ids[0]}/pause").json()["status"] == "paused"
    clock[0] += 20
    assert client.post(f"/api/units/{ids[0]}/heartbeat").json()["active_seconds_approx"] == 100
    assert client.post(f"/api/units/{ids[0]}/start").status_code == 200
    with DB() as db:
        question = db.get(LearningUnit, ids[0]).questions[0]
    for suffix, body in (
        ("start", None), ("pause", None), ("heartbeat", {"baseline": True}),
        (f"questions/{question['id']}/answer", {"answer": question["answer"]}),
    ):
        assert api.post(f"/api/units/{ids[0]}/{suffix}", json=body).status_code == 403
    assert client.put(f"/api/children/{child_id}/preferences", json={"daily_minutes": 5}).status_code == 403
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
    assert total_time(child_id) == 100
