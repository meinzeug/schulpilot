import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot import coaching
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Mastery,
    Material,
    ProviderConfig,
    UnitCoaching,
    UnitSource,
    Usage,
    now,
)
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.providers import Result
from schulpilot.synthetic import CONTENT, sample_unit
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_learning import child_client, prepared
from test_providers import configured


@pytest.fixture
def normal_unit(api, household):
    parent, kid = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        # These tests exercise coaching, not the parent's weekday schedule.
        # Keep their explicit learning opportunity valid on weekend test runs.
        db.get(Child, kid["id"]).preferences = {"weekdays": list(range(7))}
        material = Material(
            child_id=kid["id"],
            title="Künstlicher Stoff",
            status="confirmed",
            confirmed=True,
            synthetic=False,
            subject="Mathematik",
            topic="Brüche",
            content=CONTENT,
        )
        db.add(material)
        db.flush()
        data = sample_unit()
        unit = LearningUnit(
            child_id=kid["id"],
            material_id=material.id,
            subject=data["subject"],
            topic=data["topic"],
            explanation=data["explanation"],
            questions=data["questions"][:2],
            estimated_minutes=5,
            provider="openai",
            model="synthetic-model-fixture",
            synthetic=False,
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        unit_id, material_id = unit.id, material.id
    with TestClient(app, headers=HEADERS) as client:
        logged = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert logged.status_code == 200
        client.headers["Authorization"] = "Bearer " + logged.json()["token"]
        yield client, unit_id, material_id, parent, kid


def finish(client, unit_id, *, help_first=False):
    response = client.post(f"/api/units/{unit_id}/start")
    assert response.status_code == 200, response.text
    with DB() as db:
        questions = db.get(LearningUnit, unit_id).questions
    if help_first:
        assert client.post(f"/api/units/{unit_id}/questions/{questions[0]['id']}/hint").status_code == 200
    for question in questions:
        response = client.post(
            f"/api/units/{unit_id}/questions/{question['id']}/answer", json={"answer": question["answer"]}
        )
        assert response.status_code == 200, response.text
    assert response.json()["unit"]["status"] == "completed"
    return response.json()["unit"]


def mocked_review(monkeypatch, change=None):
    calls = []

    def request(config, function, payload):
        assert function == "coach" and "materials" in payload
        calls.append(payload)
        with DB() as db:
            item = db.scalar(select(UnitCoaching).where(UnitCoaching.status == "pending"))
            unit = db.get(LearningUnit, item.unit_id)
            data = coaching.synthetic_report(db, unit, payload["next_action"])
            if change:
                change(data, unit.id)
        return Result(data, input_tokens=100, output_tokens=200, cost_micros=0)

    monkeypatch.setattr(coaching, "request_provider", request)
    return calls


def process_next():
    with DB() as db:
        job_id = claim(db)
    assert job_id
    process(job_id)
    return job_id


def test_completed_answers_receive_one_review_and_source_bound_followup(normal_unit, monkeypatch):
    client, unit_id, material_id, _, kid = normal_unit
    calls = mocked_review(monkeypatch)
    result = finish(client, unit_id, help_first=True)
    assert result["coaching"]["status"] == "pending"
    assert result["learning_progress"]["secure_observation"] is False
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    coach = result["coaching"]
    assert coach["status"] == "ready" and coach["decision"] == "repair"
    assert len(coach["report"]["question_reviews"]) == 2 and "next_unit" not in coach["report"]
    assert len(calls) == 1 and calls[0]["completed_questions"][0]["hints_used"] == 1
    assert calls[0]["completed_questions"][0]["attempts"][0]["assisted"] is True
    assert "family_id" not in calls[0] and "child_id" not in calls[0]
    next_unit = client.get("/api/units/" + coach["next_unit_id"]).json()
    assert next_unit["learning_root_id"] == unit_id and next_unit["followup_of"] == unit_id
    assert next_unit["round_kind"] == "repair" and next_unit["source_material_ids"] == [material_id]
    assert all("answer" not in q and "hints" not in q for q in next_unit["questions"])
    assert client.post(f"/api/units/{unit_id}/coaching").json()["next_unit_id"] == next_unit["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.get(Child, kid["id"]).id == kid["id"]


def test_ai_opinion_does_not_upgrade_an_uncertain_short_answer(normal_unit, monkeypatch):
    client, unit_id, _, _, _ = normal_unit
    with DB.begin() as db:
        db.get(LearningUnit, unit_id).questions = [sample_unit()["questions"][-1]]
    assert client.post(f"/api/units/{unit_id}/start").status_code == 200

    def opinion(data, _):
        data["question_reviews"][0].update(
            outcome="correct", feedback="Die Umschreibung erscheint inhaltlich plausibel."
        )

    mocked_review(monkeypatch, opinion)
    response = client.post(f"/api/units/{unit_id}/questions/name/answer", json={"answer": "die untere Zahl"})
    assert response.json()["outcome"] == "uncertain"
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert result["questions"][0]["attempts"][0]["outcome"] == "uncertain"
    review = result["coaching"]["report"]["question_reviews"][0]
    assert review["outcome"] == "correct" and review["assessment_kind"] == "ai_opinion"
    assert result["learning_progress"]["successful_check_days"] == 0
    with DB() as db:
        mastery = db.scalar(select(Mastery))
        assert mastery.independent == 0 and mastery.uncertain_units == 1


@pytest.mark.parametrize(
    "fault", ["contradiction", "repeated_question", "paraphrased_calculation", "invented_source", "legacy_goal"]
)
def test_invalid_review_is_rejected_and_only_one_explicit_retry_is_allowed(normal_unit, monkeypatch, fault):
    client, unit_id, _, _, _ = normal_unit

    def invalid(data, old_id):
        if fault == "contradiction":
            data["question_reviews"][0]["outcome"] = "incorrect"
        elif fault == "invented_source":
            data["learning_goals"][0]["source_excerpt"] = "Dieser Inhalt steht in keiner bestätigten Quelle."
        elif fault == "legacy_goal":
            data["question_reviews"][0]["learning_goal_id"] = "g1"
        else:
            with DB() as db:
                data["next_unit"]["questions"][0] = {
                    **db.get(LearningUnit, old_id).questions[0],
                    "learning_goal_id": coaching.fraction_task_goal(
                        db.get(LearningUnit, old_id).questions[0]["prompt"], data["learning_goals"]
                    ),
                }
                if fault == "paraphrased_calculation":
                    data["next_unit"]["questions"][0]["prompt"] = "Wie viel ist 1/4 + 1/4?"

    calls = mocked_review(monkeypatch, invalid)
    finish(client, unit_id)
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert result["coaching"]["status"] == "failed" and result["coaching"]["can_retry"]
    if fault in ("repeated_question", "paraphrased_calculation"):
        assert "wiederholt" in result["coaching"]["reason"]
    assert result["status"] == "completed" and result["coaching"]["next_unit_id"] is None
    assert len(calls) == 1
    assert client.post(f"/api/units/{unit_id}/coaching").json()["status"] == "pending"
    process_next()
    result = client.post(f"/api/units/{unit_id}/coaching").json()
    assert result["status"] == "failed" and not result["can_retry"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 2
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert all(u.status == "failed_unknown" and u.cost_micros == 0 for u in db.scalars(select(Usage)))


@pytest.mark.parametrize("contradiction", [False, True])
def test_stored_question_goals_are_authoritative_but_answer_results_are_not_overwritten(
    normal_unit, monkeypatch, contradiction
):
    client, unit_id, material_id, _, _ = normal_unit
    with DB.begin() as db:
        db.get(Material, material_id).content = (
            "Brüche kürzen: Teile Zähler und Nenner durch dieselbe Zahl. "
            "Brüche erweitern: Multipliziere Zähler und Nenner mit derselben Zahl."
        )
        question = sample_unit()["questions"][1]
        db.get(LearningUnit, unit_id).questions = [
            {
                **question,
                "id": "expand",
                "learning_goal_id": "g2",
                "prompt": "Erweitere 2/3 mit dem Faktor 3.",
                "answer": "6/9",
                "accepted": [],
                "explanation": "Multipliziere beide Zahlen mit 3. So entsteht 6/9.",
            },
            {
                **question,
                "id": "reduce",
                "learning_goal_id": "g1",
                "prompt": "Kürze 6/18 mit dem Faktor 3.",
                "answer": "2/6",
                "accepted": [],
                "explanation": "Teile beide Zahlen durch 3. So entsteht 2/6.",
            },
        ]

    def model_reassigns_known_goals(data, _):
        data["question_reviews"][0]["learning_goal_id"] = "g1"
        data["question_reviews"][1]["learning_goal_id"] = "g2"
        if contradiction:
            data["question_reviews"][0]["outcome"] = "incorrect"

    calls = mocked_review(monkeypatch, model_reassigns_known_goals)
    finish(client, unit_id)
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert len(calls) == 1
    assert [q["learning_goal_id"] for q in calls[0]["completed_questions"]] == ["g2", "g1"]
    assert result["status"] == "completed"
    assert all(q["attempts"][0]["outcome"] == "correct" for q in result["questions"])
    if contradiction:
        assert result["coaching"]["status"] == "failed"
        assert "widerspricht" in result["coaching"]["reason"]
        assert result["coaching"]["next_unit_id"] is None
    else:
        assert result["coaching"]["status"] == "ready"
        assert [r["learning_goal_id"] for r in result["coaching"]["report"]["question_reviews"]] == ["g2", "g1"]
        assert result["coaching"]["next_unit_id"]
    assert result["learning_progress"]["secure_observation"] is False
    assert result["learning_progress"]["successful_check_days"] == 0


@pytest.mark.parametrize("block", ["quota", "stop"])
def test_provider_or_quota_block_keeps_last_answer_and_unit_completed(normal_unit, block):
    client, unit_id, _, parent, _ = normal_unit
    with DB.begin() as db:
        if block == "quota":
            db.get(Family, parent["families"][0]["id"]).call_limit = 0
        else:
            db.get(ProviderConfig, 1).emergency_stop = True
    result = finish(client, unit_id)
    assert result["coaching"]["status"] == "blocked" and result["status"] == "completed"
    assert all(q["attempts"][0]["outcome"] == "correct" for q in result["questions"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_parallel_requests_share_one_job_and_reservation(normal_unit):
    client, unit_id, _, _, _ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        unit.status, unit.completed = "completed", int(now())
        for q in unit.questions:
            db.add(Attempt(unit_id=unit.id, question_id=q["id"], answer=q["answer"], outcome="correct", assisted=False))
    with ThreadPoolExecutor(max_workers=4) as pool:
        result = list(pool.map(lambda _: coaching.schedule(unit_id), range(8)))
    assert all(r["status"] == "pending" and r["request_count"] == 1 for r in result)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_parent_and_sibling_cannot_trigger_a_childs_coaching(api, normal_unit):
    client, unit_id, _, parent, kid = normal_unit
    finish(client, unit_id)
    assert api.post(f"/api/units/{unit_id}/coaching").status_code == 403
    sibling = create_child(api, parent, "sibling")
    with TestClient(app, headers=HEADERS) as other:
        token = other.post("/api/auth/login", json={"username": "sibling", "password": "secure-child-pass-123"}).json()[
            "token"
        ]
        other.headers["Authorization"] = "Bearer " + token
        assert sibling["id"] != kid["id"]
        assert other.get(f"/api/units/{unit_id}").status_code == 404
        assert other.post(f"/api/units/{unit_id}/coaching").status_code == 404


@pytest.mark.parametrize("when", ["before", "during"])
def test_changed_sources_reject_review_without_losing_answers(normal_unit, monkeypatch, when):
    client, unit_id, material_id, _, _ = normal_unit

    def change(data=None, old_id=None):
        with DB.begin() as db:
            db.get(Material, material_id).revision += 1

    calls = mocked_review(monkeypatch, change if when == "during" else None)
    finish(client, unit_id)
    if when == "before":
        change()
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert result["status"] == "completed" and result["coaching"]["status"] == "failed"
    assert len(calls) == (when == "during")
    assert result["learning_progress"]["state"] == "source_changed"
    assert result["learning_progress"]["secure_observation"] is False
    assert result["coaching"]["next_unit_id"] is None


def test_two_correct_supported_rounds_offer_app_help_without_a_parent_alarm(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as client:
        first = finish(client, unit_id, help_first=True)
        assert first["coaching"]["decision"] == "repair"
        second = finish(client, first["coaching"]["next_unit_id"], help_first=True)
        assert second["coaching"]["decision"] == "repair"
        assert second["coaching"]["next_unit_id"] is not None
        assert not second["learning_progress"]["needs_parent"]
        overview = client.get("/api/child/home").json()
        assert "Brüche" not in overview["day_summary"]["coaching_support_topics"]
        assert second["coaching"]["provider"] == "synthetic"


def test_reading_an_explanation_marks_a_check_as_supported(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as client:
        result = finish(client, unit_id)
        next_id = result["coaching"]["next_unit_id"]
        before = client.get("/api/units/" + next_id).json()
        assert before["round_kind"] == "check" and not before["explanation"] and before["introduction_seen"]
        assert client.post(f"/api/units/{next_id}/explanation").status_code == 200
        result = finish(client, next_id)
        assert all(q["attempts"][0]["assisted"] for q in result["questions"])
        assert result["learning_progress"]["successful_check_days"] == 0


@pytest.mark.parametrize("goal_count", [1, 2])
@pytest.mark.parametrize("oldest_days", [2, 8])
def test_three_check_days_must_span_a_week_and_cover_every_goal(normal_unit, goal_count, oldest_days):
    _, root_id, material_id, _, kid = normal_unit
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        today = local_day(child)
        zone = ZoneInfo("Europe/Berlin")
        root = db.get(LearningUnit, root_id)
        root.status, root.completed = (
            "completed",
            int(datetime.combine(today - timedelta(days=12), datetime.min.time(), zone).timestamp()),
        )
        for q in root.questions:
            db.add(Attempt(unit_id=root.id, question_id=q["id"], answer=q["answer"], outcome="correct", assisted=False))
        db.add(
            UnitCoaching(
                unit_id=root.id,
                status="ready",
                report={
                    "learning_goals": [
                        {"id": f"g{i + 1}", "label": f"Brüche Lernziel {i + 1}", "source_excerpt": CONTENT[:100]}
                        for i in range(goal_count)
                    ]
                },
            )
        )
        for days in (oldest_days, 1 if oldest_days == 2 else 5, 0, 0):
            stamp = int(datetime.combine(today - timedelta(days=days), datetime.min.time(), zone).timestamp()) + 100
            data = sample_unit(days % 3)
            for q in data["questions"]:
                q["learning_goal_id"] = "g1"
            unit = LearningUnit(
                child_id=child.id,
                material_id=material_id,
                learning_root_id=root_id,
                round_kind="spaced_review",
                subject=root.subject,
                topic=root.topic,
                explanation=data["explanation"],
                questions=data["questions"][:2],
                status="completed",
                completed=stamp,
                created=stamp,
                provider="synthetic",
                synthetic=True,
            )
            db.add(unit)
            db.flush()
            for q in unit.questions:
                db.add(
                    Attempt(unit_id=unit.id, question_id=q["id"], answer=q["answer"], outcome="correct", assisted=False)
                )
        db.flush()
        result = coaching.progress(db, root)
        assert result["successful_check_days"] == (3 if goal_count == 1 else 0)
        assert result["secure_observation"] is (goal_count == 1 and oldest_days >= 7)
        assert result["learning_goals"][0]["successful_check_days"] == 3
        if goal_count == 2:
            assert result["learning_goals"][1]["successful_check_days"] == 0
        last = unit
        wrong = db.scalar(select(Attempt).where(Attempt.unit_id == last.id))
        wrong.outcome, wrong.assisted = "incorrect", True
        db.flush()
        result = coaching.progress(db, root)
        assert result["successful_check_days"] == 0 and not result["secure_observation"]


def test_parent_pause_is_advisory_for_prepared_followup_and_coaching_exports(api):
    import io
    import zipfile

    demo, unit_id = prepared(api)
    with child_client(demo) as client:
        result = finish(client, unit_id)
        next_id = result["coaching"]["next_unit_id"]
        with DB.begin() as db:
            child = db.get(Child, demo["child_id"])
            child.preferences = {**child.preferences, "pause_until": (local_day(child) + timedelta(days=2)).isoformat()}
        assert client.post(f"/api/units/{next_id}/start").status_code == 200
    with DB() as db:
        family_id = db.get(Child, demo["child_id"]).family_id
    response = api.get(f"/api/families/{family_id}/export")
    assert response.status_code == 200
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        data = json.loads(archive.read("family.json"))
    assert data["children"][0]["unit_coaching"][0]["report"]
    assert (
        api.request(
            "DELETE", f"/api/children/{demo['child_id']}", json={"password": demo["credentials"]["parent_password"]}
        ).status_code
        == 200
    )
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(UnitCoaching)) == 0


def test_three_round_recommendation_allows_an_explicit_fourth_round(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as client:
        first = finish(client, unit_id, help_first=True)
        second = finish(client, first["coaching"]["next_unit_id"])
        assert second["coaching"]["decision"] == "check"
        third = finish(client, second["coaching"]["next_unit_id"], help_first=True)
        assert third["coaching"]["decision"] == "repair" and third["coaching"]["next_unit_id"]
        assert "Pause" in third["coaching"]["reason"]
        assert "freiwillig" not in third["coaching"]["reason"]  # The measured minimum is still open.
        assert third["coaching"]["next_review"] > client.get("/api/child/home").json()["plan"]["date"]
        fourth_id = third["coaching"]["next_unit_id"]
        with DB() as db:
            assert db.get(LearningUnit, fourth_id).status == "not_started"
            assert db.scalar(select(func.count()).select_from(Attempt).where(Attempt.unit_id == fourth_id)) == 0
        assert client.post(f"/api/units/{fourth_id}/start").status_code == 200


def test_session_break_is_a_recommendation_across_units(api):
    demo, unit_id = prepared(api)
    with child_client(demo) as client:
        result = finish(client, unit_id)
        next_id = result["coaching"]["next_unit_id"]
        with DB.begin() as db:
            for index in range(36):
                db.add(
                    Activity(
                        child_id=demo["child_id"],
                        unit_id=unit_id,
                        kind="active_time",
                        detail={"seconds": 25},
                        created=int(now()) - (35 - index) * 20,
                    )
                )
        response = client.post(f"/api/units/{next_id}/start")
        assert response.status_code == 200, response.text
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "active_time")) == 36


def test_coaching_after_time_goals_free_day_and_pause_keeps_one_bounded_review(normal_unit, monkeypatch):
    client, unit_id, _, _, kid = normal_unit
    with DB.begin() as db:
        child = db.get(Child, kid["id"])
        child.preferences = {
            "weekdays": [],
            "subject_days": {"Mathematik": [(local_day(child).weekday() + 1) % 7]},
            "pause_until": (local_day(child) + timedelta(days=2)).isoformat(),
            "daily_minutes": 5,
            "weekly_minutes": 5,
            "session_minutes": 5,
        }
        db.add(Activity(child_id=child.id, kind="active_time", detail={"seconds": 3600}, created=int(now())))
    calls = mocked_review(monkeypatch)
    completed = finish(client, unit_id)
    assert completed["status"] == "completed" and completed["coaching"]["decision"] == "check"
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert result["coaching"]["status"] == "ready" and result["coaching"]["request_count"] == 1
    assert len(calls) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt).where(Attempt.unit_id == unit_id)) == 2


def test_legacy_parent_goal_is_frozen_before_review_and_later_changes_are_rejected(normal_unit, monkeypatch):
    client, unit_id, _, _, kid = normal_unit
    with DB.begin() as db:
        goal = Assignment(child_id=kid["id"], kind="parent", subject="Mathematik", topic="Brüche", note=CONTENT)
        db.add(goal)
        db.flush()
        db.get(LearningUnit, unit_id).assignment_id = goal.id
        goal_id = goal.id
    calls = mocked_review(monkeypatch)
    finish(client, unit_id)
    with DB.begin() as db:
        assert db.get(LearningUnit, unit_id).goal_revision == 1
        db.get(Assignment, goal_id).revision = 2
    process_next()
    result = client.get(f"/api/units/{unit_id}").json()
    assert result["status"] == "completed" and result["coaching"]["status"] == "failed"
    assert not calls
