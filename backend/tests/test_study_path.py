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
        assert db.scalar(select(Usage)).cost_micros == (0 if when == "during" else None)
    assert len(stage_transport["calls"]) == (1 if when == "during" else 0)
    current = api.get(path(study)).json()
    assert current["can_continue"] is False
    assert current["stale"] is (change == "source")


def test_parent_assignments_keep_their_reserved_daily_time(study):
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
    assert planned["can_continue"] is False
    assert generate(study, planned["next_block_id"]).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


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
