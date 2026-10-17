import io
import json
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import pytest
from schulpilot import schemas as s
from schulpilot.daily_planner import distribute
from schulpilot.db import DB, Assignment, Child, SchoolGrade, now
from schulpilot.grades import focus_summary, priorities
from schulpilot.learning import local_day
from sqlalchemy import func, select
from test_learning import child_client, prepared


def mark(child_id, **changes):
    with DB() as db:
        today = local_day(db.get(Child, child_id)).isoformat()
    return {"subject": "Mathematik", "topic": "Brüche", "kind": "test", "value": 5,
            "scale": "grade_1_6", "weight": 1, "assessed_on": today, "note": "synthetic-only", **changes}


def test_grade_crud_parent_only_revision_and_immediate_priority(api):
    demo, _ = prepared(api)
    path = f"/api/children/{demo['child_id']}/grades"
    response = api.post(path, json=mark(demo["child_id"]))
    assert response.status_code == 201, response.text
    grade = response.json()
    listed = api.get(path).json()
    assert listed["items"][0]["value"] == 5 and listed["can_manage"] is True
    assert listed["focus"][0]["priority"] == 2 and listed["focus"][0]["average"] == 5
    changed = api.put(path + "/" + grade["id"], json=mark(demo["child_id"], value=1, revision=grade["revision"]))
    assert changed.status_code == 200
    assert api.get(path).json()["focus"][0]["priority"] == 0
    assert api.put(path + "/" + grade["id"], json=mark(demo["child_id"], revision=grade["revision"])).status_code == 409
    with child_client(demo) as child:
        assert child.get(path).status_code == 403
        assert child.post(path, json=mark(demo["child_id"])).status_code == 403
        assert child.delete(path + "/" + grade["id"]).status_code == 403
        assert child.put(f"/api/children/{demo['child_id']}/grade-settings", json={"enabled": False}).status_code == 403
    assert api.delete(path + "/" + grade["id"]).status_code == 200
    assert api.get(path).json()["items"] == []


@pytest.mark.parametrize("change", [
    {"value": 0}, {"value": 6.1}, {"value": 2.345}, {"scale": "invented"},
    {"weight": 0}, {"weight": 6}, {"subject": "   "}, {"kind": "arbitrary"},
    {"value": -1, "scale": "points_0_15"}, {"value": 16, "scale": "points_0_15"},
    {"assessed_on": "2099-01-01"},
])
def test_invalid_grade_does_not_create_evidence(api, change):
    demo, _ = prepared(api)
    assert api.post(f"/api/children/{demo['child_id']}/grades", json=mark(demo["child_id"], **change)).status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 0


def test_point_direction_and_mixed_scales_no_invented_school_average(api):
    demo, _ = prepared(api)
    path = f"/api/children/{demo['child_id']}/grades"
    assert api.post(path, json=mark(demo["child_id"], scale="points_0_15", value=3)).status_code == 201
    focus = api.get(path).json()["focus"][0]
    assert focus["priority"] == 2 and focus["average"] == 3
    assert api.post(path, json=mark(demo["child_id"], scale="grade_1_6", value=5)).status_code == 201
    focus = api.get(path).json()["focus"][0]
    assert focus["priority"] == 2 and focus["average"] is None and focus["scale"] is None


def test_focus_uses_only_recent_five_weighted_marks_and_reports_real_trend(api):
    demo, _ = prepared(api)
    with DB.begin() as db:
        child = db.get(Child, demo["child_id"])
        today = local_day(child)
        # The old mark must neither change the recent average nor the trend.
        for days, value in [(150, 6), (5, 3), (4, 3), (3, 3), (2, 5), (1, 5)]:
            db.add(SchoolGrade(child_id=child.id, subject="Mathe", topic="Brüche", kind="test", scale="grade_1_6",
                               value=value, weight=1, assessed_on=(today - timedelta(days=days)).isoformat(), note=""))
        db.flush()
        focus = focus_summary(db, child)[0]
        assert focus["observations"] == 5 and focus["average"] == 3.8
        assert focus["trend"] == "declining" and focus["priority"] >= 1
        assert priorities(db, child)["mathematik"] >= 1


def test_priority_setting_preserves_all_other_parent_preferences(api):
    demo, _ = prepared(api)
    with DB.begin() as db:
        child = db.get(Child, demo["child_id"])
        child.preferences = s.Preferences(daily_minutes=35, focus_subjects=["Englisch"], quiet_start=21).model_dump(mode="json")
    api.post(f"/api/children/{demo['child_id']}/grades", json=mark(demo["child_id"]))
    result = api.put(f"/api/children/{demo['child_id']}/grade-settings", json={"enabled": False})
    assert result.status_code == 200
    with DB() as db:
        child = db.get(Child, demo["child_id"])
        prefs = s.Preferences(**child.preferences)
        assert prefs.daily_minutes == 35 and prefs.focus_subjects == ["Englisch"] and prefs.quiet_start == 21
        assert priorities(db, child) == {}


def test_weighted_week_gives_math_more_practice_without_more_time_or_lost_deadline():
    prefs = s.Preferences(weekdays=list(range(7)), daily_minutes=16, session_minutes=15)
    candidates = [{"kind": "unit", "id": f"{subject}{i}", "subject": subject, "topic": "confirmed-topic",
                   "mandatory": False, "status": "not_started", "estimated_minutes": 8,
                   "_grade_priority": 2 if subject == "Mathematik" else 0}
                  for subject in ("Mathematik", "Englisch") for i in range(20)]
    date_today = date(2026, 10, 12)
    result = distribute(candidates, prefs, date_today)
    minutes = {subject: sum(item["estimated_minutes"] for day in result["week"] for item in day["items"] if item["subject"] == subject)
               for subject in ("Mathematik", "Englisch")}
    assert minutes["Mathematik"] > minutes["Englisch"] > 0
    assert all(day["planned_minutes"] <= 16 for day in result["week"])
    mandatory = {**candidates[-1], "id": "parent", "mandatory": True, "due": date_today.isoformat()}
    assert distribute([*candidates, mandatory], prefs, date_today)["week"][0]["items"][0]["id"] == "parent"
    future = {**candidates[0], "id": "future", "scheduled_for": "2026-11-01"}
    assert all(item["id"] != "future" for day in distribute([future], prefs, date_today)["week"] for item in day["items"])


def test_grade_priority_drives_real_plan_and_confirmed_goal_without_ai(api):
    demo, _ = prepared(api)
    path = f"/api/children/{demo['child_id']}/grades"
    row = api.post(path, json=mark(demo["child_id"])).json()
    plan = api.get(f"/api/children/{demo['child_id']}/overview").json()["plan"]
    assert any(item["subject"] == "Mathematik" and item["priority"] == 2 for item in plan["subject_focus"])
    response = api.post(path + "/" + row["id"] + "/goal", json={"mandatory": True})
    assert response.status_code == 200, response.text
    assignment = response.json()
    assert assignment["material_id"] == demo["material_id"] and assignment["mandatory"] is True
    assert api.post(path + "/" + row["id"] + "/goal", json={"mandatory": True}).json()["id"] == assignment["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Assignment).where(Assignment.id == assignment["id"])) == 1
    # Deleting a grade cannot silently delete an accepted parent learning goal.
    assert api.delete(path + "/" + row["id"]).status_code == 200
    with DB() as db:
        assert db.get(Assignment, assignment["id"]) is not None


def test_goal_without_matching_confirmed_material_fails_honestly(api):
    demo, _ = prepared(api)
    path = f"/api/children/{demo['child_id']}/grades"
    grade = api.post(path, json=mark(demo["child_id"], subject="Biologie", topic="Nicht vorhanden")).json()
    assert api.post(path + "/" + grade["id"] + "/goal", json={}).status_code == 409
    with DB() as db:
        assert db.get(SchoolGrade, grade["id"]).assignment_id is None


def test_export_and_account_erasure_include_grades(api):
    demo, _ = prepared(api)
    api.post(f"/api/children/{demo['child_id']}/grades", json=mark(demo["child_id"]))
    export = api.get(f"/api/families/{demo['user']['families'][0]['id']}/export")
    assert export.status_code == 200
    with zipfile.ZipFile(io.BytesIO(export.content)) as archive:
        raw = json.loads(archive.read("family.json"))
        assert raw["children"][0]["school_grades"][0]["value"] == 5
    assert api.request("DELETE", "/api/account", json={"password": demo["credentials"]["parent_password"]}).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 0


def test_grade_retention_uses_existing_learning_retention(api):
    from schulpilot.worker import maintenance

    demo, _ = prepared(api)
    with DB.begin() as db:
        db.add(SchoolGrade(child_id=demo["child_id"], subject="Biologie", topic="old", kind="test", scale="grade_1_6",
                           value=3, weight=1, assessed_on="2025-01-01", note="", created=int(now()) - 366 * 86400))
    maintenance()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 0


def test_view_parent_can_follow_subjects_and_grades_but_not_change_them(api, mailbox, household):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    user, child = household
    path = f"/api/children/{child['id']}/grades"
    grade = api.post(path, json=mark(child["id"])).json()
    family_id = user["families"][0]["id"]
    assert api.post(f"/api/families/{family_id}/invitations", json={"email": "view-grades@example.org", "permission": "view"}).status_code == 201
    token = mailbox[-1]["token"]
    with TestClient(app, headers=HEADERS) as guest:
        assert guest.post("/api/invitations/accept", json={"token": token, "display_name": "Gast", "password": "secure-view-parent-pass"}).status_code == 200
        login = guest.post("/api/auth/login", json={"username": "view-grades@example.org", "password": "secure-view-parent-pass"}).json()
        guest.headers["Authorization"] = "Bearer " + login["token"]
        result = guest.get(path)
        assert result.status_code == 200 and not result.json()["can_manage"]
        assert guest.get(f"/api/children/{child['id']}/learning-progress").status_code == 200
        assert guest.post(path, json=mark(child["id"])).status_code == 403
        assert guest.delete(path + "/" + grade["id"]).status_code == 403
        assert guest.put(f"/api/children/{child['id']}/grade-settings", json={"enabled": False}).status_code == 403
        member = next(m for m in api.get(f"/api/families/{family_id}/members").json() if m["permission"] == "view")
        assert api.delete(f"/api/families/{family_id}/members/{member['id']}").status_code == 200
        assert guest.get(path).status_code == 401


def test_foreign_family_grade_and_admin_have_no_private_access(api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.db import Session, User
    from schulpilot.main import app

    demo, _ = prepared(api)
    with TestClient(app, headers=HEADERS) as foreign:
        other = foreign.post("/api/demo").json()
        foreign.headers["Authorization"] = "Bearer " + other["token"]
        row = foreign.post(f"/api/children/{other['child_id']}/grades", json=mark(other["child_id"])).json()
    path = f"/api/children/{demo['child_id']}/grades/{row['id']}"
    assert api.delete(path).status_code == 404
    assert api.get(f"/api/children/{other['child_id']}/grades").status_code == 404
    # Operating privileges do not imply permission to read private grades.
    with DB.begin() as db:
        from schulpilot.security import digest

        session = db.scalar(select(Session).where(Session.token_hash == digest(demo["token"])))
        db.get(User, session.user_id).role = "admin"
    assert api.get(f"/api/children/{demo['child_id']}/grades").status_code == 403
    assert api.get(f"/api/children/{demo['child_id']}/learning-progress").status_code == 403


def test_parallel_grade_retries_create_one_record_and_reject_changed_payload(api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    demo, _ = prepared(api)
    path = f"/api/children/{demo['child_id']}/grades"
    body = mark(demo["child_id"])
    headers = {**HEADERS, "Authorization": "Bearer " + demo["token"], "Idempotency-Key": "grade-parallel-test-123"}

    def submit(_):
        with TestClient(app, headers=headers) as client:
            response = client.post(path, json=body)
            assert response.status_code == 201, response.text
            return response.json()["id"]

    with ThreadPoolExecutor(max_workers=4) as pool:
        identifiers = list(pool.map(submit, range(4)))
    assert len(set(identifiers)) == 1
    assert api.post(path, json={**body, "value": 4}, headers=headers).status_code == 409
    assert api.post(path, json=body, headers={"Idempotency-Key": "short"}).status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(SchoolGrade)) == 1


def test_grade_aware_strategy_reaches_worker_without_exporting_private_results(api, monkeypatch):
    import uuid

    from schulpilot import worker
    from schulpilot.db import Family, Job, LearningUnit, Material
    from schulpilot.providers import Result
    from schulpilot.synthetic import sample_unit
    from test_school_day import allow_synthetic_test_transport

    demo, unit_id = prepared(api)
    body = mark(demo["child_id"], note="PRIVATE-SYNTHETIC-NOTE-DO-NOT-EXPORT", value=5.37)
    assert api.post(f"/api/children/{demo['child_id']}/grades", json=body).status_code == 201
    allow_synthetic_test_transport()
    with DB.begin() as db:
        db.get(LearningUnit, unit_id).status = "completed"
        db.get(Material, demo["material_id"]).synthetic = False
        db.get(Family, demo["user"]["families"][0]["id"]).synthetic = False
    calls = []

    def capture(config, function, payload, *args, **kwargs):
        calls.append(payload)
        return Result(sample_unit(), 0, 0, 0)

    monkeypatch.setattr(worker, "request_provider", capture)
    response = api.post(f"/api/children/{demo['child_id']}/units", json={"material_id": demo["material_id"]},
                        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    job_id = response.json()["id"]
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        assert db.get(Job, job_id).status == "completed"
    assert len(calls) == 1 and calls[0]["instructional_support"] == "guided_example"
    serialized = json.dumps(calls[0])
    assert body["note"] not in serialized and "5.37" not in serialized and "school_grades" not in serialized


def test_recent_difficulties_guide_teaching_even_without_any_school_grades(api):
    from schulpilot.learning_guidance import strategies
    from test_practice_progress import stored_unit

    demo, _ = prepared(api)
    with DB.begin() as db:
        child = db.get(Child, demo["child_id"])
        stored_unit(db, child.id, subject="Biologie", outcomes=("incorrect",))
        stored_unit(db, child.id, subject="Englisch", outcomes=("correct",))
        db.flush()
        choices = strategies(db, child)
        assert choices["biologie"] == "guided_example"
        assert choices["englisch"] == "practice_and_retrieval"


def test_new_grade_and_settings_change_package_revision_without_breaking_legacy_jobs(api):
    import hashlib

    from schulpilot.school_day import planning_fingerprint

    demo, _ = prepared(api)
    with DB() as db:
        child = db.get(Child, demo["child_id"])
        goals = [(a.id, a.revision, a.done) for a in db.scalars(select(Assignment).where(
            Assignment.child_id == child.id).order_by(Assignment.id))]
        old = hashlib.sha256(json.dumps([child.grade, child.preferences, goals], sort_keys=True).encode()).hexdigest()
        assert planning_fingerprint(db, child) == old
    path = f"/api/children/{demo['child_id']}"
    row = api.post(path + "/grades", json=mark(demo["child_id"])).json()
    with DB() as db:
        first = planning_fingerprint(db, db.get(Child, demo["child_id"]))
        assert first != old
    assert api.put(path + "/grades/" + row["id"], json=mark(demo["child_id"], value=4, revision=1)).status_code == 200
    with DB() as db:
        second = planning_fingerprint(db, db.get(Child, demo["child_id"]))
        assert second != first
    assert api.put(path + "/grade-settings", json={"enabled": False}).status_code == 200
    with DB() as db:
        assert planning_fingerprint(db, db.get(Child, demo["child_id"])) != second


def test_after_school_package_includes_weaker_subject_without_extra_provider_calls(api, household, monkeypatch):
    from test_school_day import prepare_day

    _, child = household
    day, calls = prepare_day(api, child, monkeypatch, subjects=("Englisch", "Biologie", "Deutsch", "Mathematik"))
    before = len(calls)
    assert {group["subject"] for group in day["plan"]["groups"] if group["selected"]} == {"Englisch", "Biologie", "Deutsch"}
    assert api.post(f"/api/children/{child['id']}/grades", json=mark(child["id"], topic="")).status_code == 201
    current = api.get(f"/api/school-days/{day['id']}").json()
    selected = [group for group in current["plan"]["groups"] if group["selected"]]
    assert len(selected) == 3 and "Mathematik" in {group["subject"] for group in selected}
    assert current["confirmed_count"] == 4 and len(calls) == before
