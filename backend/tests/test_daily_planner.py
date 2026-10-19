"""Small daily proposals, honest minimum goals and voluntary continuation."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot import learning
from schulpilot.daily_planner import distribute, period_starts, voluntary_steps
from schulpilot.db import DB, Activity, Child, Job, LearningUnit, Material, SchoolDay, UnitSource, Usage, now
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


def test_hundreds_of_stages_keep_proposals_small_without_a_weekly_time_ceiling():
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
    assert any(minutes > 50 for minutes in weeks.values())
    assert result["planned_minutes"] <= 15
    # A fulfilled weekly minimum does not cancel the next daily suggestion.
    after_goal = distribute([step(1)], prefs, date(2026, 10, 15), weekly_seconds=100 * 60)
    assert after_goal["today"] and after_goal["planned_minutes"] == 8


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


def test_voluntary_steps_keep_source_order_and_real_future_dates():
    items = [step(i, _chain="source", _sequence=i) for i in range(4)]
    items += [step(9, scheduled_for="2026-10-18"), step(10, not_before="2026-10-18")]
    items += [step(11, subject="Englisch")]
    ready = voluntary_steps(items, date(2026, 10, 17))
    assert [item["id"] for item in ready] == ["0", "11"]
    assert not any(key.startswith("_") for item in ready for key in item)


def test_completed_material_offers_normal_optional_practice_without_early_review(api):
    from test_learning import child_client, prepared

    demo, unit_id = prepared(api)
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.status, unit.completed = "completed", int(now())
    with child_client(demo) as child:
        route = f"/api/children/{demo['child_id']}"
        view = child.get(route + "/overview?compact=true").json()
        choice = next(item for item in view["plan"]["voluntary"] if item["kind"] == "material")
        assert choice["id"] == demo["material_id"] and not choice["mandatory"]
        response = child.post(
            route + "/units", json={"material_id": choice["id"]}, headers={"Idempotency-Key": "extra-practice"}
        )
        assert response.status_code == 202, response.text
        with DB() as db:
            job = db.get(Job, response.json()["id"])
            assert job.kind == "unit" and not job.payload.get("review_of")
            assert db.get(LearningUnit, unit_id).status == "completed"


@pytest.mark.parametrize("status", ["not_started", "active", "paused"])
@pytest.mark.parametrize("primary_source", [True, False])
def test_open_normal_round_prevents_another_material_offer_for_its_entire_source_group(
    api, household, status, primary_source
):
    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7))}
        day = SchoolDay(child_id=child.id, school_date=learning.local_day(child).isoformat(), stage="ready")
        db.add(day)
        db.flush()
        pages = [
            Material(
                child_id=child.id,
                school_day_id=day.id,
                page_number=index + 1,
                title="Künstliche Heftseite",
                topic="Künstlicher Stoff",
                subject=subject,
                content="Ein Bruch hat Zähler und Nenner." if index < 2 else "I learn. You learn.",
                confirmed=True,
                status="confirmed",
            )
            for index, subject in enumerate(("Mathematik", "MATHEMATIK", "Englisch"))
        ]
        db.add_all(pages)
        db.flush()
        finished = []
        for material, subject in ((pages[0], "Mathematik"), (pages[2], "Englisch")):
            unit = LearningUnit(
                child_id=child.id,
                school_day_id=day.id,
                material_id=material.id,
                **(sample_unit() | {"subject": subject}),
                provider="synthetic-fixture",
                status="completed",
                completed=int(now()),
            )
            db.add(unit)
            db.flush()
            finished.append(unit)
        day.learning_plan = {
            "blocks": [
                {"id": unit.id, "unit_id": unit.id, "subject": unit.subject, "question_count": len(unit.questions)}
                for unit in finished
            ]
        }
        pending = LearningUnit(
            child_id=child.id,
            material_id=pages[0].id if primary_source else None,
            **sample_unit(),
            provider="synthetic-fixture",
            status=status,
        )
        db.add(pending)
        db.flush()
        for unit, sources in ((finished[0], pages[:2]), (finished[1], pages[2:]), (pending, pages[:2])):
            for source in sources:
                db.add(UnitSource(unit_id=unit.id, material_id=source.id, revision=source.revision))
        pending_id = pending.id
        math_ids = {page.id for page in pages[:2]}
        assert pending.school_day_id is None
    route = f"/api/children/{kid['id']}/overview?compact=true"
    response = api.get(route)
    assert response.status_code == 200, response.text
    options = response.json()["plan"]["voluntary"]
    assert any(item["kind"] == "unit" and item["id"] == pending_id for item in options)
    materials = [item for item in options if item["kind"] == "material"]
    assert len(materials) == 1 and materials[0]["subject"] == "Englisch"
    assert not any(item["id"] in math_ids for item in materials)
    with DB.begin() as db:
        unit = db.get(LearningUnit, pending_id)
        unit.status, unit.completed = "completed", int(now())
    options = api.get(route).json()["plan"]["voluntary"]
    materials = [item for item in options if item["kind"] == "material"]
    assert len(materials) == 2
    assert sum(item["id"] in math_ids for item in materials) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


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


def test_daily_goal_does_not_stop_a_regular_unit_or_cap_heartbeat_credit(api, household):
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
        db.add(
            Activity(
                child_id=child.id, unit_id=unit.id, kind="active_time", detail={"seconds": 295}, created=int(now()) - 20
            )
        )
    with login_child() as child:
        assert child.post(f"/api/units/{unit_id}/heartbeat").status_code == 200
        assert child.post(f"/api/units/{unit_id}/start").status_code == 200
        view = child.get(f"/api/children/{kid['id']}/overview").json()
        assert view["plan"]["available_minutes"] == 0 and not view["plan"]["today"]
        assert view["plan"]["daily_goal_met"]
        assert view["plan"]["can_continue_voluntarily"]
        assert view["plan"]["daily_active_seconds"] >= 315
    with DB() as db:
        assert (
            sum(a.detail["seconds"] for a in db.scalars(select(Activity).where(Activity.kind == "active_time"))) >= 315
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
        assert not view["plan"]["daily_goal_met"] and view["plan"]["daily_remaining_minutes"] == 20
        assert any(item["id"] == unit_id for item in view["plan"]["voluntary"])
        assert child.post(f"/api/units/{unit_id}/start").status_code == 200
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


@pytest.mark.parametrize("legacy", [False, True])
@pytest.mark.parametrize("status", ["active", "paused"])
def test_multisubject_initial_round_remains_reachable_after_native_restart(api, household, legacy, status):
    """Initial blocks without a subject must not form a cross-subject chain."""
    import copy

    from schulpilot.study_path import ensure_plan

    _, kid = household
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {"weekdays": list(range(7)), "daily_minutes": 20, "weekly_minutes": 100}
        day = SchoolDay(child_id=child.id, school_date=learning.local_day(child).isoformat(), stage="ready")
        db.add(day)
        db.flush()
        saved_ids = []
        for index, subject in enumerate(("Biologie", "Mathematik")):
            material = Material(
                child_id=child.id, school_day_id=day.id, page_number=index + 1,
                title="Künstliche Heftseite", topic=subject, subject=subject,
                content="Künstlicher bestätigter Unterrichtsstoff.", confirmed=True, status="confirmed",
            )
            db.add(material)
            db.flush()
            unit = LearningUnit(
                child_id=child.id, school_day_id=day.id, material_id=material.id,
                **(sample_unit() | {"subject": subject, "topic": subject}),
                status="not_started" if index == 0 else status,
                estimated_minutes=8, provider="synthetic-fixture", created=now() + index,
            )
            db.add(unit)
            db.flush()
            db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
            saved_ids.append(unit.id)
        db.flush()
        value = copy.deepcopy(ensure_plan(db, day))
        if legacy:
            for block in value["blocks"]:
                if block.get("unit_id"):
                    block.pop("subject", None)
            day.learning_plan = value
        else:
            assert [b["subject"] for b in value["blocks"] if b.get("unit_id")] == ["Biologie", "Mathematik"]
        day_id = day.id
    with login_child() as child_api:
        overview = child_api.get(f"/api/children/{kid['id']}/overview?compact=true").json()
        assert set(saved_ids) <= {x["id"] for x in overview["plan"]["voluntary"] if x["kind"] == "unit"}
        assert overview["plan"]["voluntary"][0]["id"] == saved_ids[1]
        listed = child_api.get(f"/api/children/{kid['id']}/learning").json()
        assert set(saved_ids) <= {x["id"] for x in listed["items"] if x["kind"] == "unit"}
        assert child_api.post(f"/api/units/{saved_ids[1]}/start").status_code == 200
    with DB() as db:
        assert db.get(SchoolDay, day_id).learning_plan == value
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
