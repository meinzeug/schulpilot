"""Exam plans use explicit dates, real private sources and ordinary reserved jobs."""

import uuid
from datetime import date, datetime, timedelta, timezone

import pytest
from conftest import HEADERS
from fastapi.testclient import TestClient
from schulpilot import exams
from schulpilot.db import DB, Attempt, Child, Job, LearningUnit, Material, Membership, Session, Usage, User
from schulpilot.exam_models import Exam, ExamRound, ExamSession
from schulpilot.exam_schemas import ExamCreate
from schulpilot.main import app
from schulpilot.providers import ProviderError
from sqlalchemy import func, select
from test_providers import configured


@pytest.fixture
def book(api, household):
    parent, child = household
    with DB.begin() as db:
        material = Material(child_id=child["id"], title="Künstliche Bruchseite", subject="Mathematik",
            topic="Brüche", content="Brüche. Der Nenner nennt die Zahl gleich großer Teile.",
            confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        ref = {"id": material.id, "revision": material.revision}
    client = TestClient(app, headers=HEADERS)
    login = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200, login.text
    client.headers["Authorization"] = "Bearer " + login.json()["token"]
    yield {"parent": parent, "child": child, "ref": ref, "client": client}
    client.close()


def body(book, *, days=1, topics=1, count=5):
    start = date(2030, 2, 1)
    return {"title": "Künstliche Klassenarbeit", "subject": "Mathematik", "kind": "classwork",
        "purpose": "preparation", "exam_date": (start + timedelta(days=days)).isoformat(),
        "timezone": "Europe/Berlin", "minutes": 20, "reminders": False, "reminder_time": "16:00",
        "topics": [{"id": "topic_" + str(i), "label": "Brüche " + str(i), "question_count": count,
                    "material_refs": [book["ref"]]} for i in range(topics)],
        "schedule": {"dates": [(start + timedelta(days=i)).isoformat() for i in range(days)]}}


def create(api, book, value=None, key=None):
    response = api.post(f"/api/children/{book['child']['id']}/exams", json=value or body(book),
                       headers={"Idempotency-Key": key or uuid.uuid4().hex})
    assert response.status_code == 201, response.text
    return response.json()


def prepare(book, exam, key=None):
    return book["client"].post(f"/api/exams/{exam['id']}/sessions/{exam['sessions'][0]['id']}/prepare",
        headers={"Idempotency-Key": key or uuid.uuid4().hex})


@pytest.mark.parametrize("days,topics,count,expected", [(1, 8, 10, 80), (2, 5, 3, 15), (30, 1, 3, 90), (30, 8, 10, 300)])
def test_exact_dates_have_nonempty_finite_work_without_generation(api, book, days, topics, count, expected):
    result = create(api, book, body(book, days=days, topics=topics, count=count))
    assert len(result["sessions"]) == days
    assert result["requested_questions"] == expected
    assert result["planned_days"] == days
    assert all(s["requested_questions"] > 0 and s["minutes"] == 20 for s in result["sessions"])
    assert all(2 <= r["question_count"] <= 5 for s in result["sessions"] for r in s["rounds"])
    assert all(s["status"] == "planned" for s in result["sessions"])
    assert result["can_manage"] and not result["can_prepare"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
    child = book["client"].get(f"/api/exams/{result['id']}").json()
    assert child["can_manage"] and child["can_prepare"]


def test_child_can_plan_and_missing_exam_date_is_not_inferred(api, book):
    value = body(book)
    value["exam_date"] = None
    result = create(book["client"], book, value)
    assert result["exam_date"] is None
    assert result["can_prepare"]
    assert result["schedule"] == value["schedule"]


def test_review_record_can_exist_before_photos_and_plan(api, book):
    value = {**body(book), "purpose": "review", "topics": [], "schedule": {"dates": []}}
    result = create(api, book, value)
    assert result["purpose"] == "review" and not result["sessions"]
    assert result["requested_questions"] == result["planned_days"] == 0


@pytest.mark.parametrize("change", [
    {"minutes": 4}, {"minutes": 61}, {"timezone": "Invented/School"}, {"reminder_time": "24:00"},
    {"schedule": {"dates": []}}, {"topics": []}, {"kind": "grade"}, {"exam_date": "2030-01-31"},
])
def test_invalid_plan_never_creates_rows(api, book, change):
    value = {**body(book), **change}
    result = api.post(f"/api/children/{book['child']['id']}/exams", json=value,
                     headers={"Idempotency-Key": uuid.uuid4().hex})
    assert result.status_code == 422
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Exam)) == 0


@pytest.mark.parametrize("field,value", [("question_count", 0), ("question_count", 51), ("question_count", True), ("question_count", 1.5), ("id", "unsafe/identifier")])
def test_topic_contract_is_bounded(api, book, field, value):
    data = body(book)
    data["topics"][0][field] = value
    assert api.post(f"/api/children/{book['child']['id']}/exams", json=data,
        headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 422


def test_duplicate_days_and_topic_ids_are_not_silently_normalized(book):
    value = body(book)
    value["schedule"]["dates"] *= 2
    with pytest.raises(ValueError, match="einmal"):
        ExamCreate(**value)
    value = body(book)
    value["topics"] *= 2
    with pytest.raises(ValueError, match="eindeutig"):
        ExamCreate(**value)


def test_create_idempotency_and_read_paths_have_no_side_effects(api, book):
    key = uuid.uuid4().hex
    result = create(api, book, key=key)
    assert create(api, book, key=key)["id"] == result["id"]
    value = body(book)
    value["title"] = "Andere Prüfung"
    assert api.post(f"/api/children/{book['child']['id']}/exams", json=value,
        headers={"Idempotency-Key": key}).status_code == 409
    for _ in range(2):
        assert api.get(f"/api/children/{book['child']['id']}/exams").json()["exams"][0]["id"] == result["id"]
        assert api.get(f"/api/exams/{result['id']}").status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamSession)) == 1
        assert db.scalar(select(func.count()).select_from(ExamRound)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_update_cas_keeps_history_but_replaces_current_schedule(api, book):
    result = create(api, book)
    value = body(book, days=3, count=10)
    edited = api.put(f"/api/exams/{result['id']}", json={**value, "revision": 1})
    assert edited.status_code == 200, edited.text
    assert edited.json()["revision"] == 2 and len(edited.json()["sessions"]) == 3
    assert api.put(f"/api/exams/{result['id']}", json={**value, "revision": 1}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(ExamSession)) == 4
    assert prepare(book, result).status_code == 409


def test_archive_preserves_history_and_cas(api, book):
    result = create(api, book)
    route = f"/api/exams/{result['id']}/archive"
    assert api.post(route, json={"revision": 2}).status_code == 409
    saved = api.post(route, json={"revision": 1})
    assert saved.status_code == 200 and saved.json()["archived"]
    assert not api.get(f"/api/children/{book['child']['id']}/exams").json()["exams"]
    assert api.get(f"/api/children/{book['child']['id']}/exams?include_archived=true").json()["total"] == 1
    assert prepare(book, result).status_code == 409


@pytest.mark.parametrize("change", ["unconfirmed", "revision", "wrong_subject", "homework", "foreign_child"])
def test_only_current_confirmed_own_notebook_sources_are_accepted(api, book, change):
    with DB.begin() as db:
        material = db.get(Material, book["ref"]["id"])
        if change == "unconfirmed":
            material.confirmed = False
        elif change == "revision":
            material.revision += 1
        elif change == "wrong_subject":
            material.subject = "Biologie"
        elif change == "homework":
            material.purpose = "homework"
        else:
            user = User(username="other-child", display_name="Other", role="child", verified=True, password_hash="x")
            db.add(user)
            db.flush()
            other = Child(user_id=user.id, family_id=db.get(Child, book["child"]["id"]).family_id, grade=6)
            db.add(other)
            db.flush()
            material.child_id = other.id
    response = api.post(f"/api/children/{book['child']['id']}/exams", json=body(book),
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 409


def test_view_member_can_read_but_cannot_edit_or_prepare(api, book):
    result = create(api, book)
    with DB.begin() as db:
        db.scalar(select(Membership).where(Membership.user_id == book["parent"]["id"])).permission = "view"
    assert api.get(f"/api/exams/{result['id']}").json()["can_manage"] is False
    assert api.put(f"/api/exams/{result['id']}", json={**body(book), "revision": 1}).status_code == 403
    assert api.post(f"/api/exams/{result['id']}/sessions/{result['sessions'][0]['id']}/prepare",
        headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 403


def test_admin_has_no_private_exam_access(api, book):
    result = create(api, book)
    with DB.begin() as db:
        db.get(User, book["parent"]["id"]).role = "admin"
    assert api.get(f"/api/exams/{result['id']}").status_code == 403
    assert api.get(f"/api/children/{book['child']['id']}/exams").status_code == 403


def test_preparation_reserves_one_normal_job_and_replays_without_extra_usage(api, book):
    configured(book["parent"]["families"][0]["id"])
    result = create(api, book)
    key = uuid.uuid4().hex
    response = prepare(book, result, key)
    assert response.status_code == 202, response.text
    assert response.json()["kind"] == "job"
    assert prepare(book, result, key).json() == response.json()
    assert prepare(book, result).json() == response.json()
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        assert job.kind == "unit" and job.attempts == 0
        assert exams.preparation_context(db, job)["requested_question_count"] == 5
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


@pytest.mark.parametrize("mutation", ["source", "plan", "archive", "session", "actor", "count"])
def test_worker_guard_rejects_changed_plan_source_or_login(api, book, mutation):
    configured(book["parent"]["families"][0]["id"])
    result = create(api, book)
    response = prepare(book, result)
    assert response.status_code == 202, response.text
    with DB.begin() as db:
        job = db.get(Job, response.json()["id"])
        if mutation == "source":
            db.get(Material, book["ref"]["id"]).revision += 1
        elif mutation == "plan":
            db.get(Exam, result["id"]).plan_revision += 1
        elif mutation == "archive":
            db.get(Exam, result["id"]).archived = True
        elif mutation == "session":
            db.get(Session, job.payload["exam_actor_session_id"]).revoked = True
        elif mutation == "actor":
            db.get(User, job.payload["exam_actor_id"]).disabled = True
        else:
            job.payload = {**job.payload, "requested_question_count": 4}
    with DB() as db, pytest.raises(ProviderError, match="geändert"):
        exams.guard_preparation(db, db.get(Job, response.json()["id"]))


def test_exact_count_and_new_questions_required_before_attach(api, book):
    configured(book["parent"]["families"][0]["id"])
    result = create(api, book, body(book, days=2, count=3))
    response = prepare(book, result)
    with DB.begin() as db:
        job = db.get(Job, response.json()["id"])
        with pytest.raises(ProviderError, match="Aufgabenanzahl"):
            exams.validate_requested_count(job, {"questions": [{"prompt": "a"}]})
        unit = LearningUnit(child_id=job.child_id, subject="Mathematik", topic="Brüche 0", explanation="Beispiel",
            questions=[{"prompt": "Frage " + str(i)} for i in range(3)], provider="synthetic", status="completed")
        db.add(unit)
        db.flush()
        exams.attach_prepared_unit(db, job, unit)
        job.status = "completed"
    other_session = {**result, "sessions": [result["sessions"][1]]}
    second = prepare(book, other_session)
    with DB() as db:
        job = db.get(Job, second.json()["id"])
        context = exams.preparation_context(db, job)
        assert len(context["previous_prompts"]) == 3
        with pytest.raises(ProviderError, match="bereits"):
            exams.validate_prepared_output(db, job, {"subject": "Mathematik", "topic": "Brüche 0", "questions": [{"prompt": "Frage " + str(i)} for i in range(3)]})
        exams.validate_prepared_output(db, job, {"subject": "Mathematik", "topic": "Brüche 0", "questions": [{"prompt": "Neue Frage " + str(i)} for i in range(3)]})
    overview = api.get(f"/api/exams/{result['id']}").json()
    assert overview["sessions"][0]["completed_rounds"] == 1
    assert "Frage 0" not in str(overview)


def test_stale_source_never_returns_previously_ready_unit(api, book):
    result = create(api, book)
    with DB.begin() as db:
        row = db.scalar(select(ExamRound))
        unit = LearningUnit(child_id=book["child"]["id"], subject="Mathematik", topic="Brüche",
            explanation="Gespeichert", questions=[], provider="synthetic")
        db.add(unit)
        db.flush()
        row.unit_id = unit.id
        db.get(Material, book["ref"]["id"]).revision += 1
    assert prepare(book, result).status_code == 409
    assert api.get(f"/api/exams/{result['id']}").json()["sessions"][0]["status"] == "stale"


def test_reminders_are_today_only_explicit_and_nonmutating(api, book):
    value = body(book, days=3)
    value["reminders"] = True
    result = create(api, book, value)
    with DB() as db:
        child = db.get(Child, book["child"]["id"])
        assert not exams.due_reminders(db, child, datetime(2030, 2, 1, 14, 59, tzinfo=timezone.utc))
        notices = exams.due_reminders(db, child, datetime(2030, 2, 1, 15, 0, tzinfo=timezone.utc))
        assert len(notices) == 1
        assert notices[0]["scheduled_date"] == "2030-02-01"
        assert notices[0]["route"] == f"/exams/{child.id}?exam={result['id']}&session={result['sessions'][0]['id']}"
        assert not exams.due_reminders(db, child, datetime(2030, 2, 4, 18, 0, tzinfo=timezone.utc))
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_export_keeps_private_plan_and_child_erasure_cascades_only_metadata(api, book):
    result = create(api, book)
    with DB.begin() as db:
        exported = exams.export_exams(db, book["child"]["id"])
        assert exported[0]["id"] == result["id"] and exported[0]["sessions"]
        assert "create_key" not in str(exported) and "request_digest" not in str(exported)
        assert "answer" not in str(exported) and "password" not in str(exported)
        db.delete(db.get(Child, book["child"]["id"]))
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Exam)) == 0
        assert db.scalar(select(func.count()).select_from(ExamSession)) == 0
        assert db.scalar(select(func.count()).select_from(ExamRound)) == 0


def test_parallel_revision_updates_have_one_winner(api, book):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    result = create(api, book)
    gate = Barrier(2)
    headers = {**HEADERS, "Authorization": api.headers["Authorization"]}

    def change(index):
        with TestClient(app, headers=headers) as client:
            gate.wait(timeout=5)
            return client.put(f"/api/exams/{result['id']}",
                json={**body(book, days=2), "title": "Plan " + str(index), "revision": 1}).status_code

    with ThreadPoolExecutor(max_workers=2) as executor:
        statuses = list(executor.map(change, [1, 2]))
    assert sorted(statuses) == [200, 409]
    with DB() as db:
        assert db.get(Exam, result["id"]).revision == 2
        assert db.scalar(select(func.count()).select_from(ExamSession)) == 3
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_prepare_owner_parent_forbidden_and_one_child_job_guard_preserved(api, book):
    configured(book["parent"]["families"][0]["id"])
    first = create(api, book)
    second = create(api, book)
    route = f"/api/exams/{first['id']}/sessions/{first['sessions'][0]['id']}/prepare"
    assert api.post(route, headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 403
    assert prepare(book, first).status_code == 202
    assert prepare(book, second).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Job)) == 1


def test_prompt_context_cap_does_not_weaken_full_history_duplicate_guard(api, book):
    configured(book["parent"]["families"][0]["id"])
    result = create(api, book, body(book, count=3))
    response = prepare(book, result)
    with DB.begin() as db:
        for index in range(12):
            session = ExamSession(exam_id=result["id"], exam_revision=2, date=f"2029-02-{index + 1:02d}",
                minutes=15, topics=[])
            unit = LearningUnit(child_id=book["child"]["id"], subject="Mathematik", topic="Brüche 0",
                explanation="Künstlich", provider="synthetic", questions=[{"prompt": f"Alte Frage {index} " + "x" * 1480}])
            db.add_all([session, unit])
            db.flush()
            db.add(ExamRound(session_id=session.id, ordinal=0, topic_id="topic_0", topic_label="Brüche 0",
                question_count=3, source_revisions=[book["ref"]], unit_id=unit.id))
    with DB() as db:
        job = db.get(Job, response.json()["id"])
        context = exams.preparation_context(db, job)
        assert sum(map(len, context["previous_prompts"])) <= 12_000
        omitted = "Alte Frage 0 " + "x" * 1480
        assert omitted not in context["previous_prompts"]
        with pytest.raises(ProviderError, match="bereits"):
            exams.validate_prepared_output(db, job, {"subject": "Mathematik", "topic": "Brüche 0",
                "questions": [{"prompt": omitted}, {"prompt": "Neu 1"}, {"prompt": "Neu 2"}]})
        for field in ("subject", "topic"):
            value = {"subject": "Mathematik", "topic": "Brüche 0",
                "questions": [{"prompt": "Neu " + str(i)} for i in range(3)]}
            value[field] = "Falsche Zuordnung"
            with pytest.raises(ProviderError, match="Fach oder Thema"):
                exams.validate_prepared_output(db, job, value)


def test_plan_mutations_are_bounded_and_idempotent_replays_free(api, book, monkeypatch):
    calls = []
    monkeypatch.setattr(exams, "rate_limit", lambda *args, **kwargs: calls.append((args[1:], kwargs)))
    key = uuid.uuid4().hex
    result = create(api, book, key=key)
    create(api, book, key=key)
    edited = api.put(f"/api/exams/{result['id']}", json={**body(book), "revision": 1})
    assert edited.status_code == 200
    assert api.post(f"/api/exams/{result['id']}/archive", json={"revision": 2}).status_code == 200
    assert len(calls) == 3
    assert all(args[1:] == (20, 3600) and options == {"commit": False} for args, options in calls)


def test_active_exam_limit_requires_explicit_archive(api, book, monkeypatch):
    monkeypatch.setattr(exams, "MAX_OPEN_EXAMS", 1)
    result = create(api, book)
    response = api.post(f"/api/children/{book['child']['id']}/exams", json=body(book),
        headers={"Idempotency-Key": uuid.uuid4().hex})
    assert response.status_code == 409 and "archivieren" in response.text
    assert api.post(f"/api/exams/{result['id']}/archive", json={"revision": 1}).status_code == 200
    assert create(api, book)["id"] != result["id"]


@pytest.mark.parametrize("count,expected", [(1, [1]), (2, [2]), (4, [4]), (6, [3, 3]), (11, [4, 4, 3]), (50, [5] * 10)])
def test_individual_question_count_is_exact_and_does_not_leave_single_remainder(api, book, count, expected):
    result = create(api, book, body(book, count=count))
    assert [r["question_count"] for r in result["sessions"][0]["rounds"]] == expected
    assert result["requested_questions"] == count
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_requested_single_question_is_exam_only(book):
    class Request:
        payload = {"exam_round_id": "synthetic-round", "requested_question_count": 1}

    exams.validate_requested_count(Request(), {"questions": [{"prompt": "Eine Frage"}]})
    with pytest.raises(ProviderError, match="Aufgabenanzahl"):
        exams.validate_requested_count(Request(), {"questions": [{}, {}]})


def test_dst_missing_reminder_minute_uses_first_real_minute(api, book):
    value = body(book)
    value.update(reminders=True, reminder_time="02:30", exam_date=None,
                 schedule={"dates": ["2030-03-31"]})
    create(api, book, value)
    with DB() as db:
        child = db.get(Child, book["child"]["id"])
        assert not exams.due_reminders(db, child, datetime(2030, 3, 31, 0, 59, tzinfo=timezone.utc))
        instant = datetime(2030, 3, 31, 1, 0, tzinfo=timezone.utc)
        notices = exams.due_reminders(db, child, instant)
        assert len(notices) == 1 and notices[0]["created"] == int(instant.timestamp())


def test_demo_cannot_claim_free_custom_exam_generation(api, book):
    from schulpilot.db import Family

    result = create(api, book)
    with DB.begin() as db:
        db.get(Family, book["parent"]["families"][0]["id"]).synthetic = True
    assert prepare(book, result).status_code == 403
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0


@pytest.mark.parametrize("change", ["role", "session", "disabled", "unverified"])
def test_prepare_rechecks_actor_after_waiting_for_child_lock(api, book, monkeypatch, change):
    result = create(api, book)
    original = exams.lock_child

    def race(db, principal, child_id, **kwargs):
        with DB.begin() as other:
            user = other.get(User, principal.user.id)
            if change == "role":
                user.role = "parent"
                other.add(Membership(user_id=user.id, family_id=book["parent"]["families"][0]["id"], permission="manage"))
            elif change == "session":
                other.get(Session, principal.session.id).revoked = True
            elif change == "disabled":
                user.disabled = True
            else:
                user.verified = False
        return original(db, principal, child_id, **kwargs)

    monkeypatch.setattr(exams, "lock_child", race)
    response = prepare(book, result)
    assert response.status_code == (403 if change == "role" else 401), response.text
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_new_question_guard_preserves_scientific_case_distinctions(api, book):
    configured(book["parent"]["families"][0]["id"])
    with DB.begin() as db:
        material = db.get(Material, book["ref"]["id"])
        material.subject, material.topic, material.content = "Chemie", "Formeln", "CO bezeichnet Kohlenstoffmonoxid. Co ist das Symbol für Cobalt."
    value = body(book, days=2, count=1)
    value["subject"] = "Chemie"
    value["topics"][0]["label"] = "Formeln"
    result = create(api, book, value)
    first = prepare(book, result)
    with DB.begin() as db:
        job = db.get(Job, first.json()["id"])
        unit = LearningUnit(child_id=job.child_id, subject="Chemie", topic="Formeln", explanation="Künstlicher Vergleich",
            questions=[{"prompt": "Was bedeutet CO?"}], provider="synthetic", status="completed")
        db.add(unit)
        db.flush()
        exams.attach_prepared_unit(db, job, unit)
        job.status = "completed"
    second = prepare(book, {**result, "sessions": [result["sessions"][1]]})
    with DB() as db:
        job = db.get(Job, second.json()["id"])
        exams.validate_prepared_output(db, job, {"subject": "Chemie", "topic": "Formeln",
            "questions": [{"prompt": "Was bedeutet Co?"}]})
        with pytest.raises(ProviderError, match="bereits"):
            exams.validate_prepared_output(db, job, {"subject": "Chemie", "topic": "Formeln",
                "questions": [{"prompt": "Was bedeutet  CO?"}]})
