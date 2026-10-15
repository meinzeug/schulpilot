"""Synthetic private pages; no external AI, mail or push calls."""

import uuid
from datetime import timedelta

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot.db import DB, Child, Family, Job, LearningUnit, Material, Message, SchoolDay, Session, Usage
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result
from schulpilot.school_preparation import advance_one
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_school_day import allow_synthetic_test_transport, image_bytes, unit_for


def capture(api, child, monkeypatch, count=2):
    allow_synthetic_test_transport()
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 40,
            "weekly_minutes": 240,
            "session_minutes": 10,
            "quiet_start": 0,
            "quiet_end": 0,
        }
    day = api.post(f"/api/children/{child['id']}/school-day/today").json()
    for _ in range(count):
        response = api.post(
            f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
            files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")},
        )
        assert response.status_code == 201, response.text
    calls = []

    def provider(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        calls.append(function)
        if function == "extract":
            return Result(
                {
                    "subject": "Mathematik",
                    "topic": "Brüche",
                    "content": "SYNTHETISCHER SEITENINHALT: Ein Bruch besteht aus Zähler und Nenner.",
                    "uncertainties": ["Bitte die künstliche Stelle prüfen."],
                    "homework": [],
                },
                10,
                20,
                0,
            )
        assert function == "package"
        return Result(
            {"units": [{**unit_for(g["subject"]), "group_id": g["id"]} for g in payload["selected_groups"]]}, 20, 40, 0
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    return day, calls


def submit(api, day, key=None):
    response = api.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": key or uuid.uuid4().hex})
    assert response.status_code == 202, response.text
    return response.json()["preparation"]


def step():
    advance_one()
    with DB() as db:
        job_id = claim(db)
    if job_id:
        process(job_id)
    advance_one()
    return job_id


def review(api, day):
    value = api.get(f"/api/school-days/{day['id']}").json()
    for page in value["pages"]:
        response = api.put(
            f"/api/materials/{page['id']}/confirm",
            json={
                **{k: page[k] for k in ("subject", "topic", "content", "homework")},
                "uncertainties_resolved": True,
            },
        )
        assert response.status_code == 200, response.text


def test_child_background_ocr_stops_for_review_then_explicit_package_no_autostart(api, household, monkeypatch):
    _, child = household
    day, calls = capture(api, child, monkeypatch, 3)
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        first = submit(kid, day, "first-submit")
        assert first["status"] == "processing" and first["phase"] == "extract"
        assert first["total_pages"] == 3 and first["completed_pages"] == 0
        assert submit(kid, day)["job"]["id"] == first["job"]["id"]
        # No browser polling and no open application is needed by these ticks.
        assert all(step() for _ in range(3))
        state = kid.get(f"/api/school-days/{day['id']}").json()
        assert state["preparation"]["status"] == "needs_review"
        assert state["preparation"]["completed_pages"] == 3
        assert state["confirmed_count"] == 0 and state["units"] == []
        assert step() is None and calls == ["extract"] * 3
        assert submit(kid, day)["status"] == "needs_review"
        review(kid, day)
        assert step() is None  # Confirmation never dispatches a package.
        prepared = submit(kid, day)
        assert prepared["phase"] == "package" and prepared["status"] == "processing"
        assert step()
        ready = kid.get(f"/api/school-days/{day['id']}").json()
        assert ready["preparation"]["status"] == "ready"
        assert ready["units"] and all(u["status"] == "not_started" for u in ready["units"])
        assert submit(kid, day)["status"] == "ready" and step() is None
        assert "session_id" not in str(ready["preparation"]) and "user_id" not in str(ready["preparation"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 4
        assert db.scalar(select(func.count()).select_from(Job)) == 4
        messages = list(db.scalars(select(Message).where(Message.kind == "preparation")))
        assert len(messages) == 2 and all(m.sender_id is None for m in messages)
        assert all("SEITENINHALT" not in m.body for m in messages)


def test_persisted_intent_is_picked_up_after_request_interruption(api, household, monkeypatch):
    _, child = household
    day, calls = capture(api, child, monkeypatch)
    monkeypatch.setattr("schulpilot.school_preparation.advance", lambda day_id: None)
    state = submit(api, day)
    assert state["status"] == "processing" and state["job"] is None
    monkeypatch.undo()

    # Restore only the synthetic transport; no real service is called.
    def provider(*args, **kwargs):
        calls.append("extract")
        return Result(
            {
                "subject": "Mathematik",
                "topic": "Brüche",
                "content": "Künstliche Heftnotiz.",
                "uncertainties": [],
                "homework": [],
            },
            1,
            1,
            0,
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    assert step() and step()
    assert api.get(f"/api/school-days/{day['id']}").json()["preparation"]["status"] == "needs_review"


def test_quota_exhaustion_keeps_completed_page_and_settlement(api, household, monkeypatch):
    owner, child = household
    day, calls = capture(api, child, monkeypatch)
    with DB.begin() as db:
        db.get(Family, owner["families"][0]["id"]).call_limit = 1
    submit(api, day)
    assert step()
    current = api.get(f"/api/school-days/{day['id']}").json()
    assert current["preparation"]["status"] == "blocked"
    assert current["preparation"]["completed_pages"] == 1
    assert [p["status"] for p in current["pages"]] == ["review", "uploaded"]
    assert step() is None and calls == ["extract"]
    with DB() as db:
        usage = db.scalar(select(Usage))
        assert usage.status == "completed" and usage.cost_micros == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 1


def test_ocr_failures_need_explicit_retry_and_two_attempts_are_final(api, household, monkeypatch):
    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    calls = []

    def fail(*args, **kwargs):
        calls.append(1)
        raise ProviderError("Synthetischer Providerfehler.")

    monkeypatch.setattr("schulpilot.worker.request_provider", fail)
    initial = submit(api, day, "first")
    assert step()
    assert step() is None
    assert submit(api, day, "first")["job"]["id"] == initial["job"]["id"]
    assert len(calls) == 1
    second = submit(api, day, "second")
    assert second["status"] == "processing" and step()
    final = api.get(f"/api/school-days/{day['id']}").json()["preparation"]
    assert final["status"] == "failed" and final["can_retry"] is False
    assert submit(api, day, "third")["status"] == "blocked"
    assert step() is None and len(calls) == 2


@pytest.mark.parametrize("when", ["before", "during"])
def test_revoked_submitting_session_prevents_dispatch_or_result_and_chain(api, household, monkeypatch, when):
    _, child = household
    day, calls = capture(api, child, monkeypatch)
    first = submit(api, day)
    with DB() as db:
        session_id = db.get(SchoolDay, day["id"]).preparation["session_id"]

    def revoke():
        with DB.begin() as db:
            db.get(Session, session_id).revoked = True

    if when == "before":
        revoke()
    else:

        def provider(*args, **kwargs):
            calls.append("extract")
            revoke()
            return Result(
                {
                    "subject": "Mathematik",
                    "topic": "Brüche",
                    "content": "Synthetic text.",
                    "uncertainties": [],
                    "homework": [],
                },
                1,
                1,
                0,
            )

        monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    assert step() and step() is None
    with DB() as db:
        assert db.get(Job, first["job"]["id"]).status == "failed"
        assert all(m.status == "uploaded" and not m.content for m in db.scalars(select(Material)))
        assert db.get(SchoolDay, day["id"]).preparation["status"] == "blocked"
        assert db.scalar(select(func.count()).select_from(Message).where(Message.kind == "preparation")) == 0
    assert calls == ([] if when == "before" else ["extract"])


def test_source_revision_change_during_call_discards_result(api, household, monkeypatch):
    _, child = household
    day, calls = capture(api, child, monkeypatch, 1)
    first = submit(api, day)

    def provider(*args, **kwargs):
        with DB.begin() as db:
            db.scalar(select(Material)).revision += 1
        return Result(
            {
                "subject": "Mathematik",
                "topic": "Brüche",
                "content": "STALE SYNTHETIC.",
                "uncertainties": [],
                "homework": [],
            },
            1,
            1,
            0,
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    assert step()
    with DB() as db:
        assert db.get(Job, first["job"]["id"]).status == "failed"
        assert db.scalar(select(Material)).content == ""
        assert db.scalar(select(Usage)).cost_micros == 0


def test_midnight_ocr_finishes_review_is_possible_and_no_time_saves_learning_path(api, household, monkeypatch):
    _, child = household
    day, calls = capture(api, child, monkeypatch)
    submit(api, day)
    assert step()
    from schulpilot.learning import local_day

    with DB() as db:
        tomorrow = local_day(db.get(Child, child["id"])) + timedelta(days=1)
    monkeypatch.setattr("schulpilot.school_day.local_day", lambda child: tomorrow)
    monkeypatch.setattr("schulpilot.school_preparation.local_day", lambda child: tomorrow)
    assert step()
    old = api.get(f"/api/school-days/{day['id']}").json()
    assert old["read_only"] is True and old["allow_uploads"] is False
    assert old["preparation"]["status"] == "needs_review"
    review(api, day)
    result = submit(api, day)
    assert result["status"] == "saved" and result["phase"] == "deferred"
    assert submit(api, day)["status"] == "saved" and step() is None
    assert calls == ["extract", "extract"]
    with DB() as db:
        saved = db.get(SchoolDay, day["id"])
        assert saved.learning_plan and saved.stage == "ready"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
    upload = api.post(
        f"/api/children/{child['id']}/materials?school_day_id={day['id']}",
        files={"file": ("synthetic.jpg", image_bytes(), "image/jpeg")},
    )
    assert upload.status_code == 409


@pytest.mark.parametrize("when", ["before", "during"])
def test_package_midnight_defers_without_false_failure_or_units(api, household, monkeypatch, when):
    _, child = household
    day, calls = capture(api, child, monkeypatch, 1)
    submit(api, day)
    assert step()
    review(api, day)
    result = submit(api, day)
    from schulpilot.learning import local_day

    with DB() as db:
        tomorrow = local_day(db.get(Child, child["id"])) + timedelta(days=1)

    def midnight():
        monkeypatch.setattr("schulpilot.school_day.local_day", lambda child: tomorrow)
        monkeypatch.setattr("schulpilot.school_preparation.local_day", lambda child: tomorrow)

    if when == "before":
        midnight()
    else:

        def provider(config, function, payload, image_bytes=None, **kwargs):
            calls.append(function)
            midnight()
            return Result(
                {"units": [{**unit_for(g["subject"]), "group_id": g["id"]} for g in payload["selected_groups"]]},
                20,
                40,
                0,
            )

        monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    assert step()
    state = api.get(f"/api/school-days/{day['id']}").json()["preparation"]
    assert state["status"] == "saved" and state["error"] is None
    with DB() as db:
        job = db.get(Job, result["job"]["id"])
        assert job.status == "completed" and job.result["deferred"] is True
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.get(SchoolDay, day["id"]).learning_plan
    assert calls == (["extract"] if when == "before" else ["extract", "package"])


def test_child_cannot_prepare_sibling_and_new_key_dedupes_existing_work(api, household, monkeypatch):
    owner, child = household
    sibling = create_child(api, owner, "sibling-child")
    day, _ = capture(api, sibling, monkeypatch, 1)
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        assert (
            kid.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "wrong-child"}).status_code
            == 404
        )
    assert api.post(f"/api/school-days/{day['id']}/prepare").status_code == 422
    first = submit(api, day)
    assert submit(api, day)["job"]["id"] == first["job"]["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1


def test_unreadable_photo_is_never_confirmed_or_turned_into_package(api, household, monkeypatch):
    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    monkeypatch.setattr(
        "schulpilot.worker.request_provider",
        lambda *a, **kw: Result(
            {
                "subject": "Unklar",
                "topic": "Unlesbar",
                "content": "",
                "legibility": "unreadable",
                "uncertainties": ["Die künstliche Seite ist nicht lesbar."],
                "homework": [],
            },
            1,
            1,
            0,
        ),
    )
    submit(api, day)
    assert step()
    value = api.get(f"/api/school-days/{day['id']}").json()
    assert value["preparation"]["status"] == "needs_photo"
    assert value["confirmed_count"] == 0 and value["units"] == []
    assert submit(api, day)["status"] == "needs_photo" and step() is None


def test_provider_stop_during_call_rejects_result_and_stops_chain(api, household, monkeypatch):
    from schulpilot.db import ProviderConfig

    _, child = household
    day, _ = capture(api, child, monkeypatch)
    submit(api, day)

    def provider(*args, **kwargs):
        with DB.begin() as db:
            db.get(ProviderConfig, 1).emergency_stop = True
        return Result(
            {
                "subject": "Mathematik",
                "topic": "Brüche",
                "content": "SYNTHETIC PRIVATE TEXT.",
                "uncertainties": [],
                "homework": [],
            },
            1,
            1,
            0,
        )

    monkeypatch.setattr("schulpilot.worker.request_provider", provider)
    assert step() and step() is None
    with DB() as db:
        assert all(not m.content for m in db.scalars(select(Material)))
        assert db.scalar(select(Job)).status == "failed"
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(Usage)).cost_micros == 0


def test_progress_helper_reads_only_small_material_metadata(api, household, monkeypatch):
    from schulpilot.db import engine
    from schulpilot.school_preparation import preparation_data
    from sqlalchemy import event

    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    statements = []

    def before_execute(connection, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    with DB() as db:
        stored = db.get(SchoolDay, day["id"])
        event.listen(engine, "before_cursor_execute", before_execute)
        try:
            assert preparation_data(db, stored)["total_pages"] == 1
        finally:
            event.remove(engine, "before_cursor_execute", before_execute)
    assert len(statements) == 1
    assert all(
        "materials.content" not in query
        and "materials.homework" not in query
        and "materials.uncertainties" not in query
        for query in statements
    )


def test_preparation_push_is_opt_in_neutral_bundled_and_session_revoked_before_send(
    api, household, monkeypatch, tmp_path
):
    from schulpilot import notifications as n
    from schulpilot.db import PushDelivery, PushDevice
    from test_notifications import device, enable

    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    enable(tmp_path)
    with DB.begin() as db:
        c = db.get(Child, child["id"])
        c.preferences = {**c.preferences, "push_consent": True, "reminders": True}
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        registration = device(kid)
        submit(kid, day)
        assert step()
        with DB.begin() as db:
            n.prepare(db)
            n.prepare(db)
            deliveries = list(db.scalars(select(PushDelivery).where(PushDelivery.kind == "preparation_review")))
            assert len(deliveries) == 1
            assert (
                n.due_kinds(db, db.get(PushDevice, registration["id"]), int(n.now())).count("preparation_review") == 1
            )
            # Only test the new queued category; ordinary reminders are covered elsewhere.
            for other in db.scalars(select(PushDelivery).where(PushDelivery.kind != "preparation_review")):
                other.status = "suppressed"
            stored = db.get(PushDevice, registration["id"])
            db.get(Session, stored.session_id).revoked = True
        calls = []
        monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: calls.append(args))
        assert n.deliver_one(DB)
        assert calls == []
        with DB() as db:
            assert (
                db.scalar(select(PushDelivery).where(PushDelivery.kind == "preparation_review")).status == "suppressed"
            )


def test_parallel_prepare_keys_reserve_only_one_job(api, household, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor

    from schulpilot.db import engine

    if engine.dialect.name != "postgresql":
        pytest.skip("Real row-lock concurrency is covered on PostgreSQL")
    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    headers = {**HEADERS, "Authorization": api.headers["Authorization"]}

    def request(index):
        with TestClient(app, headers=headers) as client:
            response = client.post(
                f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "concurrent-" + str(index)}
            )
            assert response.status_code == 202, response.text
            return response.json()["preparation"]["job"]["id"]

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(request, range(2)))
    assert results[0] == results[1]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_unreadable_archived_day_can_be_postponed_without_losing_sources_or_answers(api, household, monkeypatch):
    from schulpilot.db import Attempt, now
    from schulpilot.learning import local_day

    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    monkeypatch.setattr(
        "schulpilot.worker.request_provider",
        lambda *a, **kw: Result(
            {
                "subject": "Unklar",
                "topic": "Unlesbar",
                "content": "",
                "legibility": "unreadable",
                "uncertainties": ["Die künstliche Seite ist nicht lesbar."],
                "homework": [],
            },
            1,
            1,
            0,
        ),
    )
    submit(api, day)
    assert step()
    with DB.begin() as db:
        tomorrow = local_day(db.get(Child, child["id"])) + timedelta(days=1)
        # Existing finished work from before this extra unreadable photo.
        previous = LearningUnit(
            child_id=child["id"],
            school_day_id=day["id"],
            provider="synthetic",
            synthetic=True,
            status="completed",
            completed=int(now()),
            **unit_for("Mathematik"),
        )
        db.add(previous)
        db.flush()
        attempt = Attempt(
            unit_id=previous.id,
            question_id=previous.questions[0]["id"],
            answer=previous.questions[0]["answer"],
            outcome="correct",
            assisted=False,
        )
        db.add(attempt)
        db.flush()
        unit_id, attempt_id = previous.id, attempt.id
    monkeypatch.setattr("schulpilot.school_day.local_day", lambda child: tomorrow)
    response = api.post(f"/api/school-days/{day['id']}/postpone")
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["preparation"]["status"] == "postponed" and value["preparation"]["phase"] == "review"
    assert value["read_only"] is True and value["allow_uploads"] is False
    assert value["confirmed_count"] == 0 and len(value["pages"]) == 1
    assert api.post(f"/api/school-days/{day['id']}/postpone").status_code == 200
    assert step() is None
    with DB() as db:
        assert db.get(LearningUnit, unit_id).status == "completed"
        assert db.get(Attempt, attempt_id).outcome == "correct"
        assert db.get(SchoolDay, day["id"]).learning_plan == {}
        assert db.scalar(select(func.count()).select_from(Job)) == 1


def test_explicit_save_clears_pending_review_without_calling_ai(api, household, monkeypatch):
    _, child = household
    day, calls = capture(api, child, monkeypatch, 1)
    submit(api, day)
    assert step()
    review(api, day)
    response = api.post(f"/api/school-days/{day['id']}/save-for-later")
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["preparation"]["status"] == "saved" and value["stage"] == "ready"
    assert calls == ["extract"] and step() is None
    with DB() as db:
        assert db.get(SchoolDay, day["id"]).preparation["status"] == "saved"
        assert db.get(SchoolDay, day["id"]).learning_plan
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(
            select(Message).where(Message.kind == "preparation").order_by(Message.created.desc(), Message.id.desc())
        )


def test_ready_push_does_not_require_daily_learning_reminders(api, household, monkeypatch, tmp_path):
    from schulpilot import notifications as n
    from schulpilot.db import PushDelivery, PushDevice
    from test_notifications import device, enable

    _, child = household
    day, _ = capture(api, child, monkeypatch, 1)
    enable(tmp_path)
    with DB.begin() as db:
        stored = db.get(Child, child["id"])
        stored.preferences = {**stored.preferences, "push_consent": True, "reminders": False}
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        registration = device(kid)
        submit(kid, day)
        assert step()
        review(kid, day)
        submit(kid, day)
        assert step()
        with DB.begin() as db:
            stored_device = db.get(PushDevice, registration["id"])
            kinds = n.due_kinds(db, stored_device, int(n.now()))
            assert "preparation_ready" in kinds and "reminder" not in kinds
            n.prepare(db)
            assert db.scalar(select(PushDelivery)).kind == "preparation_ready"
        sent = []
        monkeypatch.setattr(n, "send_fcm", lambda *args, **kwargs: sent.append(args))
        assert n.deliver_one(DB)
        assert len(sent) == 1 and sent[0][1] == "preparation_ready"
        with DB() as db:
            assert db.scalar(select(PushDelivery)).status == "accepted"
