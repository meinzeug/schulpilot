"""Source extent, durable stages, read-only views and bounded provider jobs."""

import copy
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot import study_path
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    UnitSource,
    Usage,
    now,
)
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.providers import ProviderError, Result
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_providers import configured


def test_large_dense_batches_keep_every_page_inside_the_total_cap():
    from types import SimpleNamespace

    pages = [SimpleNamespace(id=str(index), content="Wissen " * 900) for index in range(24)]
    extents = study_path.bounded_extents(pages)
    assert len(extents) == 24
    assert sum(e["target_questions"] for e in extents) == 120
    assert all(e["target_questions"] == 5 for e in extents)


def test_existing_five_question_intro_leaves_one_three_question_stage_for_two_pages(study):
    from schulpilot.synthetic import sample_unit

    with DB.begin() as db:
        for material_id in study["materials"][2:]:
            db.delete(db.get(Material, material_id))
        data = sample_unit()
        extra = {
            **data["questions"][-1],
            "id": "intro-extra",
            "prompt": "Welche Zahl steht bei 1/4 im Nenner?",
            "answer": "4",
            "accepted": [],
            "explanation": "Beim Bruch 1/4 steht die Vier unter dem Bruchstrich.",
        }
        unit = LearningUnit(
            child_id=study["child"]["id"],
            school_day_id=study["day_id"],
            subject="Sachunterricht",
            topic="Erste Runde",
            explanation=data["explanation"],
            questions=[*data["questions"], extra],
            synthetic=False,
            provider="fixture",
        )
        db.add(unit)
        db.flush()
        assert len(unit.questions) == 5
        for material_id in study["materials"][:2]:
            material = db.get(Material, material_id)
            db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
    result = create(study)
    assert result["total_questions"] == 8
    assert [b["question_count"] for b in result["blocks"]] == [5, 3]
    assert result["completed_questions"] == 0 and result["ready_questions"] == 5


@pytest.fixture
def study(api, household):
    parent, kid = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        family = db.get(Family, parent["families"][0]["id"])
        family.call_limit, family.budget_micros = 40, 40_000
        child = db.get(Child, kid["id"])
        child.preferences = {
            "weekdays": list(range(7)),
            "daily_minutes": 60,
            "weekly_minutes": 300,
            "session_minutes": 10,
        }
        day = SchoolDay(child_id=child.id, school_date=local_day(child).isoformat(), stage="ready")
        db.add(day)
        db.flush()
        material_ids = []
        for index in range(5):
            material = Material(
                child_id=child.id,
                school_day_id=day.id,
                page_number=index + 1,
                title=f"Künstliche Unterrichtsseite {index + 1}",
                subject="Sachunterricht",
                topic=f"Weltraum {index + 1}",
                content="Die Sonne ist ein Stern. " * 44,
                confirmed=True,
                status="confirmed",
                synthetic=False,
            )
            db.add(material)
            db.flush()
            material_ids.append(material.id)
        day_id = day.id
    with TestClient(app, headers=HEADERS) as client:
        login = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        client.headers["Authorization"] = "Bearer " + login.json()["token"]
        yield {"client": client, "parent": parent, "child": kid, "day_id": day_id, "materials": material_ids}


@pytest.fixture
def stage_transport(monkeypatch):
    state = {"calls": [], "effect": None}

    def request(config, function, payload):
        assert function == "unit"
        state["calls"].append(copy.deepcopy(payload))
        if state["effect"]:
            state["effect"]()
        return Result(
            {
                "subject": payload["required_subject"],
                "topic": payload["required_topic"],
                "explanation": "Die Sonne ist ein Stern. Dies ist eine künstliche Testetappe.",
                "questions": [
                    {
                        "id": f"q{index + 1}",
                        "type": "choice",
                        "prompt": f"{payload['required_topic']}, {payload['study_block']['mode']}, Frage {index + 1}: Was ist die Sonne?",
                        "options": ["Ein Stern", "Ein Planet", "Ein Mond"],
                        "answer": "Ein Stern",
                        "accepted": [],
                        "hints": ["Lies den ersten Satz auf der Heftseite."],
                        "explanation": "Die Sonne ist ein Stern.",
                    }
                    for index in range(payload["study_block"]["question_count"])
                ],
            },
            100,
            150,
            0,
        )

    monkeypatch.setattr(study_path, "request_provider", request)
    return state


def path(study):
    return f"/api/school-days/{study['day_id']}/study-path"


def create(study):
    response = study["client"].post(path(study))
    assert response.status_code == 200, response.text
    return response.json()


def generate(study, block_id, key=None):
    return study["client"].post(
        f"/api/school-days/{study['day_id']}/blocks/{block_id}",
        headers={"Idempotency-Key": key or uuid.uuid4().hex},
    )


def finish():
    with DB() as db:
        job_id = claim(db)
    assert job_id
    process(job_id)
    return job_id


def test_five_confirmed_pages_plan_twenty_questions_without_generating_or_writing_on_get(api, study):
    with DB() as db:
        initial = copy.deepcopy(db.get(SchoolDay, study["day_id"]).learning_plan)
        assert not initial
    for actor in (api, study["client"]):
        response = actor.get(path(study))
        assert response.status_code == 200 and response.json()["available"] is False
    with DB() as db:
        assert db.get(SchoolDay, study["day_id"]).learning_plan == initial
        assert db.scalar(select(func.count()).select_from(Job)) == 0
    planned = create(study)
    assert planned["total_questions"] == 20
    assert planned["completed_questions"] == planned["ready_questions"] == 0
    assert len(planned["blocks"]) == 5
    assert all(2 <= block["question_count"] <= 5 and block["status"] == "planned" for block in planned["blocks"])
    assert {block["phase"] for block in planned["blocks"]} == {"understand", "detective", "apply", "recall"}
    with DB() as db:
        snapshot = copy.deepcopy(db.get(SchoolDay, study["day_id"]).learning_plan)
        assert len(snapshot["extents"]) == 5 and all(e["word_count"] == 220 for e in snapshot["extents"])
    for _ in range(3):
        assert api.get(path(study)).json()["total_questions"] == 20
    with DB() as db:
        assert db.get(SchoolDay, study["day_id"]).learning_plan == snapshot
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


@pytest.mark.parametrize("existing_plan", [False, True])
@pytest.mark.parametrize("problem", ["unconfirmed", "empty"])
def test_pending_source_review_is_actionable_without_replanning_or_generation(study, existing_plan, problem):
    if existing_plan:
        create(study)
    with DB.begin() as db:
        material = db.get(Material, study["materials"][1])
        material.revision += 1
        if problem == "unconfirmed":
            material.confirmed = False
        else:
            material.content = " "
        before = copy.deepcopy(db.get(SchoolDay, study["day_id"]).learning_plan)
    for _ in range(2):
        response = study["client"].get(path(study))
        assert response.status_code == 200
        data = response.json()
        assert data["pending_review_count"] == 1
        assert data["next_review_material_id"] == study["materials"][1]
        assert data["available"] is existing_plan and data["can_continue"] is False
        if existing_plan:
            assert data["stale"] is True and "offenen Heftseiten prüfen" in data["block_reason"]
    assert study["client"].post(path(study)).status_code == 409
    with DB() as db:
        assert db.get(SchoolDay, study["day_id"]).learning_plan == before
        for model in (Job, Usage, Attempt, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0
    # Explicit source confirmation permits planning again, never a GET or retry.
    with DB.begin() as db:
        material = db.get(Material, study["materials"][1])
        material.confirmed = True
        material.content = "Die Sonne ist ein Stern. " * 44
    data = create(study)
    assert data["pending_review_count"] == 0 and data["next_review_material_id"] is None
    assert data["can_continue"] is True and data["stale"] is False


def test_parents_only_read_and_other_children_or_families_cannot_open_path(api, mailbox, study):
    planned = create(study)
    assert api.get(path(study)).status_code == 200
    assert api.post(path(study)).status_code == 403
    assert (
        api.post(
            f"/api/school-days/{study['day_id']}/blocks/{planned['next_block_id']}",
            headers={"Idempotency-Key": uuid.uuid4().hex},
        ).status_code
        == 403
    )
    create_child(api, study["parent"], "study-sibling")
    with TestClient(app, headers=HEADERS) as outsider:
        login = outsider.post(
            "/api/auth/login", json={"username": "study-sibling", "password": "secure-child-pass-123"}
        )
        outsider.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert outsider.get(path(study)).status_code == 404
        assert outsider.post(path(study)).status_code == 404
        register(outsider, mailbox, "foreign-study-parent@example.org")
        assert outsider.get(path(study)).status_code == 404


def test_one_small_stage_is_persisted_and_progress_comes_from_saved_answers(api, study, stage_transport):
    planned = create(study)
    block = planned["next_block_id"]
    key = uuid.uuid4().hex
    queued = generate(study, block, key)
    assert queued.status_code == 202, queued.text
    assert generate(study, block, key).json()["id"] == queued.json()["id"]
    assert generate(study, planned["blocks"][1]["id"]).status_code == 409
    assert api.get(path(study)).json()["blocks"][0]["status"] == "generating"
    finish()
    current = api.get(path(study)).json()
    assert current["total_questions"] == 20 and current["ready_questions"] == 4 and current["completed_questions"] == 0
    unit_id = current["blocks"][0]["unit_id"]
    assert unit_id
    with DB() as db:
        unit = db.get(LearningUnit, unit_id)
        assert len(unit.questions) == 4 and unit.round_kind == "study_block"
        assert db.scalar(select(UnitSource).where(UnitSource.unit_id == unit_id)).material_id == study["materials"][0]
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    assert generate(study, block, key).json()["id"] == queued.json()["id"]
    assert len(stage_transport["calls"]) == 1
    assert study["client"].post(f"/api/units/{unit_id}/start").status_code == 200
    for index in range(4):
        response = study["client"].post(
            f"/api/units/{unit_id}/questions/q{index + 1}/answer", json={"answer": "Ein Stern"}
        )
        assert response.status_code == 200, response.text
        if index == 0:
            partial = api.get(path(study)).json()
            assert partial["completed_questions"] == 1
            assert partial["ready_questions"] == 3
            assert partial["blocks"][0]["status"] == "ready"
    complete = api.get(path(study)).json()
    assert complete["completed_questions"] == 4 and complete["ready_questions"] == 0
    assert complete["blocks"][0]["status"] == "completed" and complete["next_block_id"] == planned["blocks"][1]["id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 4


@pytest.mark.parametrize("when", ["before", "during"])
@pytest.mark.parametrize("change", ["source", "planning"])
def test_sources_and_parent_planning_are_checked_before_and_after_generation(api, study, stage_transport, when, change):
    block = create(study)["next_block_id"]
    assert generate(study, block).status_code == 202

    def changed():
        with DB.begin() as db:
            if change == "source":
                db.get(Material, study["materials"][0]).revision += 1
            else:
                child = db.get(Child, study["child"]["id"])
                child.preferences = {
                    **child.preferences,
                    "pause_until": (local_day(child) + timedelta(days=2)).isoformat(),
                }

    if when == "before":
        changed()
    else:
        stage_transport["effect"] = changed
    finish()
    with DB() as db:
        job = db.scalar(select(Job).where(Job.kind == "study_block"))
        assert job.status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        usage = db.scalar(select(Usage))
        assert usage.cost_micros == 0
        assert usage.status == ("failed_billed" if when == "during" else "failed_not_sent")
    assert len(stage_transport["calls"]) == (1 if when == "during" else 0)
    current = api.get(path(study)).json()
    assert current["can_continue"] is (change == "planning")
    assert current["stale"] is (change == "source")


def test_parent_assignments_keep_priority_without_blocking_voluntary_stage(study):
    with DB.begin() as db:
        child = db.get(Child, study["child"]["id"])
        child.preferences = {**child.preferences, "daily_minutes": 20}
        for index in range(2):
            db.add(
                Assignment(
                    child_id=child.id,
                    kind="parent",
                    subject="Deutsch",
                    topic=f"Pflichtauftrag {index + 1}",
                    note="Künstlicher Elternauftrag",
                    mandatory=True,
                )
            )
    planned = create(study)
    assert planned["can_continue"] is True
    assert generate(study, planned["next_block_id"]).status_code == 202
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Assignment).where(Assignment.done.is_(False))) == 2
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


@pytest.mark.parametrize("quota_exhausted", [False, True])
def test_voluntary_stage_ignores_time_schedule_but_preserves_provider_quota(study, stage_transport, quota_exhausted):
    with DB.begin() as db:
        child = db.get(Child, study["child"]["id"])
        child.preferences = {
            "weekdays": [],
            "subject_days": {"Sachunterricht": [(local_day(child).weekday() + 1) % 7]},
            "pause_until": (local_day(child) + timedelta(days=3)).isoformat(),
            "daily_minutes": 5,
            "weekly_minutes": 5,
            "session_minutes": 5,
        }
        db.add(Activity(child_id=child.id, kind="active_time", detail={"seconds": 7200}, created=int(now())))
        if quota_exhausted:
            db.get(Family, child.family_id).call_limit = 0
    current = create(study)
    assert current["can_continue"] is True and current["block_reason"] is None
    result = generate(study, current["next_block_id"])
    assert result.status_code == (429 if quota_exhausted else 202), result.text
    if not quota_exhausted:
        finish()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == int(not quota_exhausted)
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == int(not quota_exhausted)
    assert len(stage_transport["calls"]) == int(not quota_exhausted)


@pytest.mark.parametrize("change", ["provider", "privacy", "entitlement"])
def test_configuration_privacy_and_family_access_are_checked_after_response(study, stage_transport, change):
    block = create(study)["next_block_id"]
    assert generate(study, block).status_code == 202

    def changed():
        with DB.begin() as db:
            if change == "provider":
                db.get(ProviderConfig, 1).revision += 1
            elif change == "privacy":
                db.get(ProviderConfig, 1).privacy_approved = False
            else:
                family = db.get(Family, study["parent"]["families"][0]["id"])
                family.commerce_required = True

    stage_transport["effect"] = changed
    finish()
    with DB() as db:
        assert db.scalar(select(Job).where(Job.kind == "study_block")).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(Usage)).cost_micros == 0


def test_parallel_stage_requests_reserve_only_once(study, stage_transport):
    block = create(study)["next_block_id"]
    key = uuid.uuid4().hex
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(lambda _: generate(study, block, key), range(6)))
    assert all(response.status_code == 202 for response in responses)
    assert len({response.json()["id"] for response in responses}) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
    finish()
    assert len(stage_transport["calls"]) == 1


def test_three_explicit_failures_stop_without_automatic_retries(study, stage_transport, monkeypatch):
    calls = []

    def unavailable(*args):
        calls.append(True)
        raise ProviderError("Künstlicher Testfehler, kein echter Anbieteraufruf.")

    monkeypatch.setattr(study_path, "request_provider", unavailable)
    block = create(study)["next_block_id"]
    for _ in range(3):
        response = generate(study, block)
        assert response.status_code == 202
        finish()
    assert len(calls) == 3
    assert generate(study, block).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 3
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == "unit_created")) == 0


@pytest.mark.parametrize("phase", ["understand", "detective", "apply", "recall"])
def test_task_briefs_prioritize_unasked_literal_passages_and_different_thinking(phase):
    from types import SimpleNamespace

    old = "Die Sonne ist ein Stern."
    new = "Das Mondlicht ist zurückgeworfenes Sonnenlicht."
    material = SimpleNamespace(content=old + "\n" + new)
    briefs = study_path.task_briefs([material], ["Die Sonne ist ein Stern: Was ist die Sonne?"], phase, 3)
    assert len(briefs) == 3
    assert [b["number"] for b in briefs] == [1, 2, 3]
    assert briefs[0]["source_excerpt"] == new
    assert {b["source_excerpt"] for b in briefs} == {old, new}
    assert len({b["action"] for b in briefs}) == 3
    assert all(b["source_excerpt"] in material.content for b in briefs)
    assert [b["action"] for b in briefs] == list(study_path.STAGE_ACTIONS[phase])


@pytest.mark.parametrize("existing", [False, True])
def test_duplicate_questions_are_rejected_without_replacement_or_losing_old_answers(
    study, stage_transport, monkeypatch, existing
):
    block = create(study)["next_block_id"]
    previous = "Was ist die Sonne?"
    old_id = None
    if existing:
        question = {
            "id": "old",
            "type": "choice",
            "prompt": previous,
            "options": ["Ein Stern", "Ein Planet"],
            "answer": "Ein Stern",
            "accepted": [],
            "hints": ["Lies den Satz zur Sonne."],
            "explanation": "Die Sonne ist ein Stern.",
        }
        with DB.begin() as db:
            unit = LearningUnit(
                child_id=study["child"]["id"],
                school_day_id=study["day_id"],
                subject="Sachunterricht",
                topic="Gespeicherte Runde",
                explanation="Die Sonne ist ein Stern.",
                questions=[question],
                status="completed",
                completed=int(now()),
                synthetic=False,
                provider="fixture",
            )
            db.add(unit)
            db.flush()
            old_id = unit.id
            db.add(Attempt(unit_id=unit.id, question_id="old", answer="Ein Stern", outcome="correct", assisted=False))
    original = study_path.request_provider

    def repeat(config, function, payload):
        assert len(payload["study_block"]["tasks"]) == payload["study_block"]["question_count"]
        result = original(config, function, payload)
        if existing:
            assert payload["previous_prompts"] == [previous]
            result.data["questions"][0]["prompt"] = "  WAS ist die Sonne! "
        else:
            result.data["questions"][1]["prompt"] = result.data["questions"][0]["prompt"]
        return result

    monkeypatch.setattr(study_path, "request_provider", repeat)
    assert generate(study, block).status_code == 202
    finish()
    assert len(stage_transport["calls"]) == 1
    with DB() as db:
        job = db.scalar(select(Job).where(Job.kind == "study_block"))
        assert job.status == "failed" and "wiederholt" in job.error
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == int(existing)
        assert db.scalar(select(Usage)).cost_micros == 0
        if existing:
            assert db.get(LearningUnit, old_id).questions == [question]
            attempt = db.scalar(select(Attempt).where(Attempt.unit_id == old_id))
            assert attempt.answer == "Ein Stern" and attempt.outcome == "correct" and not attempt.assisted


def ready_recall(study):
    block = create(study)["next_block_id"]
    with DB.begin() as db:
        day = db.get(SchoolDay, study["day_id"])
        value = copy.deepcopy(day.learning_plan)
        value["blocks"][0].update(phase="recall", label="Erinnern")
        day.learning_plan = value
    assert generate(study, block).status_code == 202
    finish()
    return study["client"].get(path(study)).json()["blocks"][0]["unit_id"]


def test_recall_starts_without_preexposed_solution_and_requested_explanation_counts_as_help(
    api, study, stage_transport
):
    unit_id = ready_recall(study)
    client = study["client"]
    before = client.get(f"/api/units/{unit_id}").json()
    assert before["round_kind"] == "study_recall" and before["introduction_seen"] is True
    assert before["explanation"] == ""
    assert api.get(f"/api/units/{unit_id}").json()["explanation"]
    active = client.post(f"/api/units/{unit_id}/start")
    assert active.status_code == 200 and active.json()["explanation"] == ""
    with DB() as db:
        assert not db.scalar(select(Activity.id).where(Activity.unit_id == unit_id, Activity.kind == "explanation"))
    help_response = client.post(f"/api/units/{unit_id}/explanation")
    assert help_response.status_code == 200 and help_response.json()["explanation"]
    for index in range(4):
        response = client.post(f"/api/units/{unit_id}/questions/q{index + 1}/answer", json={"answer": "Ein Stern"})
        assert response.status_code == 200, response.text
        assert response.json()["assisted"] is True
    completed = client.get(f"/api/units/{unit_id}").json()
    assert completed["status"] == "completed" and completed["explanation"]


def test_recall_still_rejects_changed_sources_during_learning(study, stage_transport):
    unit_id = ready_recall(study)
    assert study["client"].post(f"/api/units/{unit_id}/start").status_code == 200
    with DB.begin() as db:
        db.get(Material, study["materials"][0]).revision += 1
    response = study["client"].post(f"/api/units/{unit_id}/questions/q1/answer", json={"answer": "Ein Stern"})
    assert response.status_code == 409
    with DB() as db:
        assert not db.scalar(select(Attempt.id).where(Attempt.unit_id == unit_id))
