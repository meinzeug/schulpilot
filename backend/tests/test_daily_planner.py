"""Daily routine, large growing notebooks, real limits and private check-ins."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot import learning
from schulpilot.daily_planner import distribute, period_starts
from schulpilot.db import DB, Activity, Child, Job, LearningUnit, Material, SchoolDay, Usage, now
from schulpilot.main import app
from schulpilot.schemas import Preferences
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


def step(number, **kwargs):
    return {
        "kind": "study_path",
        "id": str(number),
        "topic": f"Künstliches Thema {number}",
        "subject": "Mathematik",
        "status": "planned",
        "estimated_minutes": 8,
        **kwargs,
    }


def test_hundreds_of_stages_stay_inside_daily_and_calendar_week_limits():
    prefs = Preferences(weekdays=list(range(7)), daily_minutes=20, weekly_minutes=50)
    result = distribute(
        [step(i) for i in range(300)], prefs, date(2026, 10, 15), daily_seconds=5 * 60, weekly_seconds=30 * 60
    )
    assert len(result["week"]) == 7 and result["beyond_week_steps"] > 250
    weeks = {}
    for day in result["week"]:
        assert day["planned_minutes"] <= day["available_minutes"] <= 20
        assert day["planned_minutes"] == sum(item["estimated_minutes"] for item in day["items"])
        d = date.fromisoformat(day["date"])
        monday = (d - timedelta(days=d.weekday())).isoformat()
        weeks[monday] = weeks.get(monday, 30 if d < date(2026, 10, 19) else 0) + day["planned_minutes"]
    assert all(minutes <= 50 for minutes in weeks.values())
    assert result["planned_minutes"] <= 15


def test_source_order_subject_rotation_reviews_and_mandatory_dates():
    prefs = Preferences(weekdays=list(range(7)), daily_minutes=30, weekly_minutes=150)
    candidates = [step(i, _chain="first", _sequence=i, source_date="2026-10-01") for i in range(5)]
    candidates += [step(10, subject="Englisch", kind="review", not_before="2026-10-12")]
    candidates += [step(11, subject="Deutsch", mandatory=True, due="2026-10-12")]
    result = distribute(candidates, prefs, date(2026, 10, 12))
    assert [s["id"] for s in result["today"]] == ["11", "10", "0"]
    assert result["today"][1]["reason"] == "review"
    chain = [x for day in result["week"] for x in day["items"] if x.get("block_id") or x["id"] in map(str, range(5))]
    assert [int(x["id"]) for x in chain] == list(range(5))


def test_subject_days_pause_and_missing_days_never_add_to_daily_target():
    prefs = Preferences(
        weekdays=[0, 1, 2, 3, 4],
        daily_minutes=20,
        weekly_minutes=100,
        subject_days={"Mathematik": [1, 3]},
        pause_until="2026-10-13",
    )
    result = distribute([step(i) for i in range(40)], prefs, date(2026, 10, 12))
    assert not result["today"]
    assert [d["date"] for d in result["week"] if d["items"]] == ["2026-10-15"]
    assert max(d["planned_minutes"] for d in result["week"]) <= 20


def test_unfinished_long_unit_is_portioned_without_shifting_its_deadline():
    prefs = Preferences(weekdays=list(range(7)), daily_minutes=10, weekly_minutes=100, session_minutes=10)
    result = distribute(
        [step(1, kind="unit", estimated_minutes=25, mandatory=True, due="2026-10-12")], prefs, date(2026, 10, 12)
    )
    assert [d["planned_minutes"] for d in result["week"][:3]] == [10, 10, 5]
    assert result["today"][0]["due"] == "2026-10-12"
    assert result["today"][0]["estimated_minutes"] == 10


def test_impossible_parent_dates_are_reported_instead_of_extending_the_day():
    prefs = Preferences(weekdays=list(range(7)), daily_minutes=10, weekly_minutes=20)
    result = distribute([step(i, mandatory=True, due="2026-10-12") for i in range(5)], prefs, date(2026, 10, 12))
    assert result["planned_minutes"] == 8
    assert len(result["conflicts"]) == 4
    assert all(x["due"] == "2026-10-12" for x in result["conflicts"])


def test_day_and_week_start_follow_local_calendar_across_clock_change():
    start, week = period_starts(date(2026, 10, 26), "Europe/Berlin")
    assert start == week
    start, week = period_starts(date(2026, 10, 25), "Europe/Berlin")
    zone = ZoneInfo("Europe/Berlin")
    assert datetime.fromtimestamp(week, zone).isoformat() == "2026-10-19T00:00:00+02:00"
    assert datetime.fromtimestamp(start, zone).hour == 0


def login_child():
    client = TestClient(app, headers=HEADERS)
    response = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert response.status_code == 200
    client.headers["Authorization"] = "Bearer " + response.json()["token"]
    return client


def test_check_in_is_private_idempotent_and_resets_each_local_day(api, household, monkeypatch):
    parent, kid = household
    sibling = create_child(api, parent, "another-child")
    current = [date(2026, 10, 12)]
    monkeypatch.setattr(learning, "local_day", lambda child: current[0])
    route = f"/api/children/{kid['id']}/day-check-in"
    assert api.post(route).status_code == 403
    with login_child() as child:
        assert child.post(f"/api/children/{sibling['id']}/day-check-in").status_code == 404
        for _ in range(2):
            assert child.post(route).status_code == 200
        view = child.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert view["daily_capture"]["status"] == "skipped"
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "daily_checkin")) == 1
        current[0] += timedelta(days=1)
        view = child.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert view["daily_capture"]["status"] == "empty"


def test_old_notebooks_are_scheduled_without_get_creating_jobs_or_changing_sources(api, household):
    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 20, "weekly_minutes": 100}
        today = learning.local_day(child)
        for offset in range(60):
            day = SchoolDay(child_id=child.id, school_date=(today - timedelta(days=offset)).isoformat(), stage="ready")
            db.add(day)
            db.flush()
            day.learning_plan = {
                "blocks": [
                    {"id": f"b{i}", "title": "Künstlicher Heftstoff", "subject": "Mathematik", "question_count": 4}
                    for i in range(6)
                ]
            }
    first = api.get(f"/api/children/{kid['id']}/overview?compact=true").json()
    second = api.get(f"/api/children/{kid['id']}/overview?compact=true").json()
    assert first["plan"] == second["plan"]
    assert first["plan"]["backlog_steps"] == 360
    assert first["plan"]["today"][0]["source_date"] == today.isoformat()
    assert any(
        x["source_date"] == (today - timedelta(days=59)).isoformat() for d in first["plan"]["week"] for x in d["items"]
    )
    assert first["plan"]["planned_minutes"] <= 20
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0


def test_confirmed_pages_can_be_scheduled_during_a_pause_without_an_ai_call(api, household):
    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        today = learning.local_day(child)
        child.preferences = {"weekdays": list(range(7)), "pause_until": (today + timedelta(days=1)).isoformat()}
        day = SchoolDay(child_id=child.id, school_date=today.isoformat(), stage="review")
        db.add(day)
        db.flush()
        day_id = day.id
        db.add(
            Material(
                child_id=child.id,
                school_day_id=day.id,
                title="Künstliche Heftseite",
                subject="Biologie",
                topic="Die Sonne",
                content="Die Sonne ist ein Stern. " * 100,
                confirmed=True,
                status="confirmed",
            )
        )
    with login_child() as child:
        result = child.post(f"/api/school-days/{day_id}/save-for-later")
        assert result.status_code == 200, result.text
        view = child.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert view["daily_capture"]["status"] == "ready" and view["daily_capture"]["page_count"] == 1
        assert not view["plan"]["today"]
        assert any(d["items"] for d in view["plan"]["week"][2:])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.get(SchoolDay, day_id).learning_plan["blocks"]


def test_daily_budget_applies_to_regular_units_and_heartbeat_cannot_overrun_it(api, household):
    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 5, "weekly_minutes": 20}
        unit = LearningUnit(
            child_id=child.id,
            **sample_unit(),
            provider="fixture",
            synthetic=True,
            estimated_minutes=8,
            status="active",
            heartbeat=int(now()) - 20,
        )
        db.add(unit)
        db.flush()
        unit_id = unit.id
        db.add(Activity(child_id=child.id, unit_id=unit.id, kind="active_time", detail={"seconds": 295}))
    with login_child() as child:
        assert child.post(f"/api/units/{unit_id}/heartbeat").status_code == 200
        assert child.post(f"/api/units/{unit_id}/start").status_code == 409
        view = child.get(f"/api/children/{kid['id']}/overview").json()
        assert view["plan"]["available_minutes"] == 0 and not view["plan"]["today"]
    with DB() as db:
        assert (
            sum(a.detail["seconds"] for a in db.scalars(select(Activity).where(Activity.kind == "active_time"))) == 300
        )


def test_fast_completed_portions_do_not_refill_the_day_or_fabricate_learning_time(api, household):
    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 20, "weekly_minutes": 100}
        for _ in range(2):
            db.add(
                LearningUnit(
                    child_id=child.id,
                    **sample_unit(),
                    provider="fixture",
                    synthetic=True,
                    estimated_minutes=10,
                    status="completed",
                    completed=int(now()),
                )
            )
        remaining = LearningUnit(
            child_id=child.id, **sample_unit(), provider="fixture", synthetic=True, estimated_minutes=8
        )
        db.add(remaining)
        db.flush()
        unit_id = remaining.id
    with login_child() as child:
        view = child.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert view["plan"]["available_minutes"] == 0 and not view["plan"]["today"]
        assert view["plan"]["completed_portion_minutes"] == 20
        assert view["day_summary"]["active_minutes_approx"] == 0
        assert child.post(f"/api/units/{unit_id}/start").status_code == 409
        assert any(d["items"] for d in view["plan"]["week"][1:])


def test_parent_subject_days_can_choose_english_before_unfinished_maths_in_the_same_notebooks(api, household):
    from schulpilot.study_path import ensure_plan

    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        today = learning.local_day(child)
        child.preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 20,
            "weekly_minutes": 100,
            "subject_days": {"Mathematik": [(today.weekday() + 1) % 7], "Englisch": [today.weekday()]},
        }
        day = SchoolDay(child_id=child.id, school_date=today.isoformat(), stage="ready")
        db.add(day)
        db.flush()
        day_id = day.id
        for index, (subject, content) in enumerate(
            [("Mathematik", "Ein Bruch hat Zähler und Nenner."), ("Englisch", "I learn. You learn. We learn.")]
        ):
            db.add(
                Material(
                    child_id=child.id,
                    school_day_id=day.id,
                    page_number=index + 1,
                    title=f"Künstliche Seite {index}",
                    topic=subject,
                    subject=subject,
                    content=content,
                    confirmed=True,
                    status="confirmed",
                )
            )
        db.flush()
        value = ensure_plan(db, day)
        english = next(block["id"] for block in value["blocks"] if block["subject"] == "Englisch")
    with login_child() as child:
        view = child.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert {x["subject"] for x in view["plan"]["today"]} == {"Englisch"}
        path = child.get(f"/api/school-days/{day_id}/study-path").json()
        assert path["next_block_id"] == english and path["can_continue"]
