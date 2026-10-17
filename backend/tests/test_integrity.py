import os
import sqlite3
import subprocess
import sys
import uuid
from pathlib import Path

from schulpilot.db import DB, Assignment, Child, LearningUnit, Mastery, now
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.worker import claim, process
from sqlalchemy import select
from test_learning import child_client, prepared


def test_unexpected_error_does_not_log_private_content(api, caplog):
    secret = "SYNTHETIC_PRIVATE_CHILD_ANSWER"

    def crash():
        raise RuntimeError(secret)

    app.add_api_route("/api/_test-private-error", crash, methods=["GET"])
    route = app.router.routes[-1]
    try:
        result = api.get("/api/_test-private-error")
        assert result.status_code == 500 and secret not in result.text
        assert secret not in caplog.text and "request_failed" in caplog.text
    finally:
        app.router.routes.remove(route)


def test_mail_transport_verifies_tls_and_never_uses_plaintext(monkeypatch):
    import ssl

    from fastapi import HTTPException
    from schulpilot import mail
    from schulpilot.config import settings

    object.__setattr__(settings, "smtp_host", "smtp.example.invalid")
    object.__setattr__(settings, "smtp_from", "synthetic@example.org")

    class SMTP:
        def __init__(self, *args, **kwargs):
            context = kwargs.get("context")
            if context is not None:
                assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def starttls(self, context):
            assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname

        def send_message(self, message):
            assert "token=" in message.get_content()

    monkeypatch.setattr(mail.smtplib, "SMTP_SSL", SMTP)
    monkeypatch.setattr(mail.smtplib, "SMTP", SMTP)
    for mode in ["tls", "starttls"]:
        object.__setattr__(settings, "smtp_mode", mode)
        mail.send_link("synthetic@example.org", "Synthetic", "Synthetic", "verify", "SYNTHETIC_TOKEN")
    object.__setattr__(settings, "smtp_mode", "plain")
    try:
        mail.require_mail()
    except HTTPException as error:
        assert error.status_code == 503
    else:
        raise AssertionError("Plaintext mail transport accepted")


def test_background_time_stops_and_session_break_is_only_recommended(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as child:
        child.post(f"/api/units/{unit_id}/start")
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            unit.heartbeat = int(now()) - 500
        result = child.post(f"/api/units/{unit_id}/heartbeat").json()
        assert result["active_seconds_approx"] == 0
        with DB.begin() as db:
            unit = db.get(LearningUnit, unit_id)
            unit.heartbeat = int(now()) - 20
            unit.segment_seconds = 899
        result = child.post(f"/api/units/{unit_id}/heartbeat").json()
        assert result["status"] == "active" and 20 <= result["active_seconds_approx"] <= 25
        assert result["break_until"] is None and result["break_recommended"] is True
        before = result["active_seconds_approx"]
        assert child.post(f"/api/units/{unit_id}/start").status_code == 200
        with DB.begin() as db:
            db.get(LearningUnit, unit_id).heartbeat = int(now()) - 500
        result = child.post(f"/api/units/{unit_id}/heartbeat").json()
        assert result["active_seconds_approx"] == before
        assert result["status"] == "active" and result["break_recommended"] is False


def test_repeat_preferences_create_visible_goals_and_subject_days(api, household):
    _, child = household
    with DB() as db:
        today = local_day(db.get(Child, child["id"]))
    other_day = (today.weekday() + 1) % 7
    result = api.put(
        f"/api/children/{child['id']}/preferences",
        json={
            "weekdays": [0, 1, 2, 3, 4, 5, 6],
            "repeat_topics": ["Englisch: unregelmäßige Verben"],
            "subject_days": {"Englisch": [other_day]},
        },
    )
    assert result.status_code == 200
    view = api.get(f"/api/children/{child['id']}/overview").json()
    assert view["assignments"][0]["mandatory"] and view["assignments"][0]["subject"] == "Englisch"
    assert view["plan"]["today"] == [] and len(view["plan"]["later"]) == 1


def test_queued_material_revision_cannot_be_overwritten(api):
    demo, _ = prepared(api)
    queued = api.post(
        f"/api/children/{demo['child_id']}/units",
        json={"material_id": demo["material_id"]},
        headers={"Idempotency-Key": uuid.uuid4().hex},
    )
    assert queued.status_code == 202
    from schulpilot.synthetic import CONTENT

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
    with DB() as db:
        job_id = claim(db)
    process(job_id)
    result = api.get(f"/api/jobs/{job_id}").json()
    assert result["status"] == "failed" and "geändert" in result["error"]


def test_uncertain_unit_does_not_become_a_difficulty(api):
    demo, unit_id = prepared(api)
    authoritative = api.get(f"/api/units/{unit_id}").json()
    with child_client(demo) as child:
        child.post(f"/api/units/{unit_id}/start")
        for q in authoritative["questions"]:
            answer = "eine nicht sicher bewertbare Variante" if q["type"] == "short" else q["answer"]
            response = child.post(f"/api/units/{unit_id}/questions/{q['id']}/answer", json={"answer": answer})
            assert response.status_code == 200
    with DB() as db:
        mastery = db.scalar(select(Mastery))
        assert mastery.uncertain_units == 1 and mastery.difficulties == 0 and mastery.independent == 0


def test_only_parent_can_close_binding_goal(api):
    demo, unit_id = prepared(api)
    result = api.post(
        f"/api/children/{demo['child_id']}/assignments",
        json={"subject": "Mathematik", "topic": "Brüche", "material_id": demo["material_id"]},
    )
    assignment = result.json()
    with child_client(demo) as child:
        assert (
            child.post(f"/api/children/{demo['child_id']}/assignments/{assignment['id']}/complete").status_code == 403
        )
    assert api.post(f"/api/children/{demo['child_id']}/assignments/{assignment['id']}/complete").status_code == 200
    with DB() as db:
        assert db.get(Assignment, assignment["id"]).done


def test_chunked_requests_cannot_bypass_actual_body_limit(api):
    def body():
        yield b'{"email":"'
        for _ in range(8):
            yield b"x" * 16_384
        yield b'"}'

    response = api.post("/api/auth/register", content=body(), headers={"Content-Type": "application/json"})
    assert response.status_code == 413
    assert "x" * 100 not in response.text


def test_migration_preserves_existing_rows(tmp_path):
    path = tmp_path / "migration.sqlite"
    env = {**os.environ, "DATABASE_URL": "sqlite:///" + str(path), "ENVIRONMENT": "test"}
    config = Path(__file__).resolve().parents[1] / "alembic.ini"
    command = [sys.executable, "-m", "alembic", "-c", str(config), "upgrade"]
    subprocess.run([*command, "0001"], env=env, check=True, capture_output=True)
    with sqlite3.connect(path) as db:
        db.executescript("""
INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','F',1,0,4,100,2000000,'Pilot');
INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,totp_last_step,created) VALUES('u','u','U','synthetic-hash','child',1,0,0,0);
INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,totp_secret,totp_last_step,created) VALUES('a','admin','A','synthetic-admin-hash','admin',1,0,'old-encrypted-totp',42,0);
INSERT INTO sessions(id,user_id,token_hash,device,created,seen,expires,revoked) VALUES('sc','u','synthetic-child-hash','child-device',0,0,9999999999,0);
INSERT INTO sessions(id,user_id,token_hash,device,created,seen,expires,revoked) VALUES('sa','a','synthetic-admin-hash','admin-device',0,0,9999999999,0);
INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}');
INSERT INTO materials(id,child_id,title,status,subject,topic,content,uncertainties,homework,confirmed,synthetic,created) VALUES('m','c','Fixture','review','Math','X','x','[]','[]',0,1,0);
""")
    subprocess.run([*command, "0004"], env=env, check=True, capture_output=True)
    with sqlite3.connect(path) as db:
        db.executescript("""
INSERT INTO school_days(id,child_id,school_date,stage,revision,created) VALUES('day','c','2026-10-14','ready',1,0);
INSERT INTO learning_units(id,child_id,school_day_id,material_id,subject,topic,explanation,questions,status,synthetic,provider,created,active_seconds,segment_seconds) VALUES('unit','c','day','m','Math','X','Fixture','[]','active',1,'synthetic',0,0,0);
INSERT INTO attempts(id,unit_id,question_id,answer,outcome,assisted,created) VALUES('attempt','unit','q1','"synthetic"','correct',0,0);
INSERT INTO provider_config(id,revision,provider,model,emergency_stop,image_capable,structured_capable,capability_evidence,privacy_approved,privacy_evidence,reserve_micros,pricing_evidence,max_output_tokens,global_limit_micros,status) VALUES(1,1,'openrouter','fixture/model:free',1,1,1,'fixture',1,'fixture',1000,'fixture',4000,1000000,'fixture');
INSERT INTO usage(id,family_id,child_id,job_id,provider,model,config_revision,function,status,reserved_micros,bucket_ids,created) VALUES('legacy-usage','f','c','legacy-job','codex','synthetic-model',1,'unit','completed',1000,'[]',0);
""")
    subprocess.run([*command, "head"], env=env, check=True, capture_output=True)
    with sqlite3.connect(path) as db:
        assert db.execute("select revision,content from materials where id='m'").fetchone() == (1, "x")
        assert db.execute("select version_num from alembic_version").fetchone()[0] == "0015"
        assert db.execute("select count(*) from vocabulary_items").fetchone()[0] == 0
        assert db.execute("select input_method,request_key,evaluation from attempts where id='attempt'").fetchone() == ("typed", None, None)
        assert db.execute("select grade_planning_enabled,preferences from children where id='c'").fetchone() == (1, "{}")
        assert db.execute("select count(*) from school_grades").fetchone()[0] == 0
        assert db.execute("select reasoning_effort,revision,model from provider_config where id=1").fetchone() == (
            "medium", 1, "fixture/model:free"
        )
        assert db.execute("select count(*) from google_identities").fetchone()[0] == 0
        assert db.execute("select count(*) from google_flows").fetchone()[0] == 0
        assert db.execute("select count(*) from tutor_turns").fetchone()[0] == 0
        assert db.execute("select learning_plan from school_days where id='day'").fetchone()[0] == "{}"
        assert db.execute("select preparation from school_days where id='day'").fetchone()[0] == "{}"
        assert db.execute("select search_calls,cost_micros,reserved_micros from usage where id='legacy-usage'").fetchone() == (None, None, 1000)
        assert db.execute("select commerce_required from families where id='f'").fetchone()[0] == 0
        assert db.execute("select count(*) from bank_orders").fetchone()[0] == 0
        assert db.execute("select completed,bootstrap_digest from installation").fetchone() == (1, None)
        assert db.execute("select id,revoked from sessions order by id").fetchall() == [("sa", 1), ("sc", 0)]
        assert not {"totp_secret", "totp_last_step"} & {
            row[1] for row in db.execute("pragma table_info(users)").fetchall()
        }
        assert db.execute("select password_hash from users where id='a'").fetchone()[0] == "synthetic-admin-hash"
        assert db.execute("select openrouter_free_only,openrouter_require_zdr from provider_config").fetchone() == (
            1,
            1,
        )
        assert db.execute(
            "select package_version,introduction_seen,status from learning_units where id='unit'"
        ).fetchone() == (1, 1, "active")
        assert db.execute("select answer,outcome from attempts where id='attempt'").fetchone() == (
            '"synthetic"',
            "correct",
        )
        assert db.execute("select package_version from school_days where id='day'").fetchone()[0] == 1
        assert db.execute("select upload_key,legibility from materials where id='m'").fetchone() == (None, "unknown")
        assert db.execute("select school_day_id,page_number from materials where id='m'").fetchone() == (None, None)
        assert db.execute("select count(*) from school_days").fetchone()[0] == 1
        assert db.execute("select extraction_model,fixture_id from materials where id='m'").fetchone() == ("", None)
