import io
import uuid
import zipfile
from datetime import timedelta

from conftest import HEADERS
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot.config import settings
from schulpilot.db import DB, Child, Family, Job, LearningUnit, Material, now
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.synthetic import CONTENT
from schulpilot.worker import claim, maintenance, process
from sqlalchemy import select


def prepared(api):
    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    mid = demo["material_id"]
    confirmed = api.put(
        f"/api/materials/{mid}/confirm",
        json={
            "subject": "Mathematik",
            "topic": "Brüche",
            "content": CONTENT,
            "homework": [],
            "uncertainties_resolved": True,
        },
    )
    assert confirmed.status_code == 200, confirmed.text
    result = api.post(
        f"/api/children/{demo['child_id']}/units",
        json={"material_id": mid},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert result.status_code == 202, result.text
    with DB() as db:
        job_id = claim(db)
    process(job_id)
    job = api.get(f"/api/jobs/{job_id}").json()
    assert job["status"] == "completed", job
    return demo, job["result"]["unit_id"]


def child_client(demo):
    client = TestClient(app, headers=HEADERS)
    result = client.post(
        "/api/auth/login",
        json={"username": demo["credentials"]["child_username"], "password": demo["credentials"]["child_password"]},
    )
    client.headers["Authorization"] = "Bearer " + result.json()["token"]
    return client


def test_full_flow_saves_answers_hints_and_parent_view(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as child:
        before = child.get(f"/api/units/{unit_id}").json()
        assert len(before["questions"]) == 4
        assert all("answer" not in q and "hints" not in q for q in before["questions"])
        assert {q["type"] for q in before["questions"]} == {"choice", "gap", "match", "short"}
        assert child.post(f"/api/units/{unit_id}/start").status_code == 200
        assert child.post(f"/api/units/{unit_id}/questions/sum/hint").status_code == 200
        assert child.post(f"/api/units/{unit_id}/explanation").status_code == 200
        with DB() as db:
            answers = {q["id"]: q["answer"] for q in db.get(LearningUnit, unit_id).questions}
        for qid, value in answers.items():
            response = child.post(f"/api/units/{unit_id}/questions/{qid}/answer", json={"answer": value})
            assert response.status_code == 200, response.text
            assert response.json()["outcome"] == "correct"
        assert response.json()["unit"]["status"] == "completed"
    overview = api.get(f"/api/children/{demo['child_id']}/overview").json()
    assert overview["day_summary"]["answer_count"] == 4
    assert overview["day_summary"]["hints_used"] == 1
    assert overview["day_summary"]["completed_units"] == 1
    assert overview["mastery"][0]["assisted_units"] == 1
    assert overview["mastery"][0]["later_review_successes"] == 0
    assert overview["mastery"][0]["next_review"] > overview["plan"]["date"]
    assert overview["units"][0]["questions"][0]["attempts"][0]["assisted"] is True
    activities = api.get(f"/api/children/{demo['child_id']}/activity").json()
    assert {"hint", "explanation", "answer", "unit_completed"}.issubset({a["kind"] for a in activities})


def test_short_answer_uncertain_and_no_fabricated_mastery(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as child:
        child.post(f"/api/units/{unit_id}/start")
        result = child.post(f"/api/units/{unit_id}/questions/name/answer", json={"answer": "die untere Zahl"})
        assert result.json()["outcome"] == "uncertain"
        assert child.post(f"/api/units/{unit_id}/questions/name/answer", json={"answer": "Nenner"}).status_code == 409
    overview = api.get(f"/api/children/{demo['child_id']}/overview").json()
    assert overview["day_summary"]["uncertain_answers"] == 1
    assert overview["mastery"] == []


def test_parent_cannot_submit_child_answers(api):
    _, unit_id = prepared(api)
    assert api.post(f"/api/units/{unit_id}/start").status_code == 403
    assert api.post(f"/api/units/{unit_id}/questions/sum/answer", json={"answer": "2/4"}).status_code == 403


def test_job_idempotency_and_confirmation_requirement(api):
    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    path = f"/api/children/{demo['child_id']}/units"
    assert (
        api.post(path, json={"material_id": demo["material_id"]}, headers={"Idempotency-Key": "test-key"}).status_code
        == 409
    )
    api.put(
        f"/api/materials/{demo['material_id']}/confirm",
        json={
            "subject": "Mathematik",
            "topic": "Brüche",
            "content": CONTENT,
            "homework": [],
            "uncertainties_resolved": True,
        },
    )
    first = api.post(path, json={"material_id": demo["material_id"]}, headers={"Idempotency-Key": "one-key"})
    second = api.post(path, json={"material_id": demo["material_id"]}, headers={"Idempotency-Key": "one-key"})
    assert first.json()["id"] == second.json()["id"]


def test_real_upload_cannot_be_smuggled_into_demo(api):
    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    response = api.post(f"/api/children/{demo['child_id']}/materials", files={"file": ("x.jpg", b"fake", "image/jpeg")})
    assert response.status_code == 403


def test_upload_metadata_removed_and_private(api, household):
    _, child = household
    object.__setattr__(settings, "real_data_approved", True)
    image = Image.new("RGB", (32, 32), "blue")
    exif = Image.Exif()
    exif[270] = "PRIVATE_SYNTHETIC_TEST"
    output = io.BytesIO()
    image.save(output, format="JPEG", exif=exif)
    result = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("sample.jpg", output.getvalue(), "image/jpeg")}
    )
    assert result.status_code == 201, result.text
    mid = result.json()["id"]
    data = api.get(f"/api/materials/{mid}/image")
    assert data.status_code == 200 and not Image.open(io.BytesIO(data.content)).getexif()
    with TestClient(app, headers=HEADERS) as outsider:
        assert outsider.get(f"/api/materials/{mid}/image").status_code == 401
    assert api.delete(f"/api/materials/{mid}").status_code == 200
    assert api.get(f"/api/materials/{mid}/image").status_code == 404


def test_parent_plan_pause_and_bounded_time(api, household):
    _, child = household
    prefs = {
        "weekdays": [0, 1, 2, 3, 4, 5, 6],
        "daily_minutes": 10,
        "weekly_minutes": 30,
        "session_minutes": 15,
        "pause_until": None,
    }
    assert api.put(f"/api/children/{child['id']}/preferences", json=prefs).status_code == 200
    for i in range(4):
        assert (
            api.post(
                f"/api/children/{child['id']}/assignments",
                json={"kind": "parent", "subject": "Englisch", "topic": f"Verben {i}", "mandatory": True},
            ).status_code
            == 201
        )
    overview = api.get(f"/api/children/{child['id']}/overview").json()
    assert len(overview["plan"]["today"]) == 1 and len(overview["plan"]["later"]) == 3
    assert all(x["mandatory"] for x in overview["plan"]["today"]) and overview["plan"]["notices"]
    with DB() as db:
        today = local_day(db.get(Child, child["id"]))
    prefs["pause_until"] = (today + timedelta(days=5)).isoformat()
    api.put(f"/api/children/{child['id']}/preferences", json=prefs)
    plan = api.get(f"/api/children/{child['id']}/overview").json()["plan"]
    assert plan["paused"] and plan["available_minutes"] == 0 and not plan["today"]


def test_help_request_appears_in_summary(api):
    demo, _ = prepared(api)
    with child_client(demo) as child:
        response = child.post(
            f"/api/children/{demo['child_id']}/messages",
            json={"kind": "help", "body": "Bitte Brüche gemeinsam ansehen."},
        )
        assert response.status_code == 201
    overview = api.get(f"/api/children/{demo['child_id']}/overview").json()
    assert overview["day_summary"]["help_requests"] == 1
    mid = overview["messages"][0]["id"]
    assert api.post(f"/api/children/{demo['child_id']}/messages/{mid}/resolve").status_code == 200


def test_export_and_demo_retention(api):
    demo, _ = prepared(api)
    fid = demo["user"]["families"][0]["id"]
    result = api.get(f"/api/families/{fid}/export")
    assert result.status_code == 200
    with zipfile.ZipFile(io.BytesIO(result.content)) as z:
        assert "family.json" in z.namelist() and b"password_hash" not in z.read("family.json")
    with DB.begin() as db:
        db.get(Family, fid).expires = int(now()) - 1
    maintenance()
    with DB() as db:
        assert not db.get(Family, fid) and not db.get(Child, demo["child_id"]) and not db.scalar(select(Material))


def test_abandoned_job_not_replayed(api):
    prepared(api)
    with DB.begin() as db:
        job = db.scalar(select(Job))
        job.status = "running"
        job.started = int(now()) - 300
        job.attempts = 1
    maintenance()
    with DB() as db:
        job = db.scalar(select(Job))
        assert job.status == "failed" and job.attempts == 1 and claim(db) is None
