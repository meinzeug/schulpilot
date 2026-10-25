"""Explicit regular notebook practice: isolated artificial API/worker/adapter tests."""

import copy
from types import SimpleNamespace

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot import learning_entry, providers, worker
from schulpilot.db import (
    DB,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    Membership,
    SchoolDay,
    UnitSource,
    Usage,
)
from schulpilot.main import app
from schulpilot.providers import Result
from schulpilot.schemas import UnitOutput
from schulpilot.subject_registry import identity
from sqlalchemy import func, select
from test_learning_entry import CONTENT as ENTRY_CONTENT
from test_presentation_capability_paths import _config, _submitted, _transport
from test_providers import configured
from test_unit_graphic_schema import output as graphic_output
from test_unit_graphic_schema import payload as graphic_payload

CONTENT = "Der Nenner steht unter dem Bruchstrich. Brüche: 1/13, 2/13, 3/13, 4/13, 5/13."


@pytest.fixture
def notebook(api, household):
    parent, child = household
    configured(parent["families"][0]["id"])
    with DB.begin() as db:
        db.get(Child, child["id"]).preferences = {"weekdays": list(range(7))}
        days = [SchoolDay(child_id=child["id"], school_date=value) for value in ("2026-10-01", "2026-10-02")]
        db.add_all(days)
        db.flush()
        pages = [
            Material(
                child_id=child["id"],
                school_day_id=days[index % 2].id,
                page_number=index + 1,
                title=f"Künstliche Heftseite{index + 1}",
                subject="Mathematik",
                subject_id=identity("mathematik"),
                topic="Brüche",
                content=CONTENT if index < 2 else "UNSELECTED_PRIVATE_TEST_MARKER",
                confirmed=True,
                status="confirmed",
            )
            for index in range(3)
        ]
        db.add_all(pages)
        old = LearningUnit(
            child_id=child["id"],
            subject="Mathematik",
            topic="Künstlicher Altbestand",
            explanation="Gespeicherter Alttext.",
            questions=[
                {
                    "id": "old",
                    "type": "short",
                    "prompt": "Alte künstliche Frage?",
                    "answer": "Alter künstlicher Schlüssel",
                    "options": [],
                    "accepted": [],
                    "hints": [],
                    "explanation": "Alttext.",
                }
            ],
            status="completed",
            synthetic=False,
            provider="synthetic-fixture",
        )
        db.add(old)
        db.flush()
        db.add(
            Attempt(
                unit_id=old.id,
                question_id="old",
                answer="Eigene künstliche Altantwort",
                outcome="correct",
                assisted=False,
            )
        )
        refs = [{"id": page.id, "revision": page.revision} for page in pages]
        old_id = old.id
    client = TestClient(app, headers=HEADERS)
    login = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200
    client.headers["Authorization"] = "Bearer " + login.json()["token"]
    yield SimpleNamespace(
        client=client,
        parent_api=api,
        child=child,
        parent=parent,
        actor_id=login.json()["user"]["id"],
        refs=refs,
        old_id=old_id,
    )
    client.close()


def body(book, count=2):
    return {
        "material_id": book.refs[0]["id"],
        "notebook_sources": copy.deepcopy(book.refs[:2]),
        "question_count": count,
    }


def post(book, value=None, key="notebook-practice-request-0001", client=None):
    return (client or book.client).post(
        f"/api/children/{book.child['id']}/units",
        json=body(book) if value is None else value,
        headers={
            "Idempotency-Key": key,
            "X-Schulpilot-Account": book.parent["id"] if client is book.parent_api else book.actor_id,
        },
    )


def inventory():
    with DB() as db:
        return tuple(
            db.scalar(select(func.count()).select_from(model))
            for model in (Job, Usage, LearningUnit, Attempt, UnitSource)
        )


def output(count):
    return UnitOutput.model_validate(
        {
            "subject": "Mathematik",
            "topic": "Nenner aus dem gewählten Heftstoff",
            "explanation": CONTENT,
            "questions": [
                {
                    "id": f"new{index}",
                    "type": "short",
                    "prompt": f"Wie lautet der Nenner des Bruchs {index + 1}/13?",
                    "answer": "13",
                    "options": [],
                    "accepted": [],
                    "hints": ["Die untere Zahl heißt Nenner."],
                    "explanation": "Der Nenner ist13.",
                }
                for index in range(count)
            ],
        }
    ).model_dump()


def process(book, monkeypatch, job_id, count=2, callback=None):
    calls = []

    def model(_config, function, payload, *_args, **_kwargs):
        assert function == "unit"
        calls.append(copy.deepcopy(payload))
        if callback:
            callback()
        return Result(output(count), 100, 100, 200, cost_source="reported")

    monkeypatch.setattr(worker, "request_provider", model)
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    with DB() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        result = {
            "status": job.status,
            "result": copy.deepcopy(job.result),
            "error": job.error,
            "usage_status": usage.status,
            "cost": usage.cost_micros,
        }
    return result, calls


def test_exact_two_pages_across_days_publish_once_without_day_expansion(notebook, monkeypatch):
    before = inventory()
    response = post(notebook, body(notebook, 3))
    assert response.status_code == 202, response.text
    jid = response.json()["id"]
    assert post(notebook, body(notebook, 3)).json()["id"] == jid
    assert post(notebook, body(notebook, 3), key="another-notebook-request-0002").status_code == 409
    result, calls = process(notebook, monkeypatch, jid, 3)
    assert result["status"] == "completed", result
    assert len(calls) == 1 and calls[0]["notebook_practice"] == {"version": 1, "question_count": 3}
    assert "UNSELECTED_PRIVATE_TEST_MARKER" not in str(calls[0])
    with DB() as db:
        unit = db.get(LearningUnit, result["result"]["unit_id"])
        assert len(unit.questions) == 3 and unit.subject_id == identity("mathematik")
        assert set(db.scalars(select(UnitSource.material_id).where(UnitSource.unit_id == unit.id))) == {
            x["id"] for x in notebook.refs[:2]
        }
        assert (
            db.scalar(select(Attempt).where(Attempt.unit_id == notebook.old_id)).answer
            == "Eigene künstliche Altantwort"
        )
    for _ in range(2):
        assert notebook.client.get(f"/api/jobs/{jid}").status_code == 200
        assert post(notebook, body(notebook, 3)).json()["id"] == jid
    worker.process(jid)
    assert len(calls) == 1
    assert inventory() == (before[0] + 1, before[1] + 1, before[2] + 1, before[3], before[4] + 2)
    assert post(notebook, body(notebook, 4)).status_code == 409


@pytest.mark.parametrize(
    "change,status",
    [
        ("duplicate", 422),
        ("missing_primary", 422),
        ("stale", 409),
        ("unconfirmed", 409),
        ("other_subject", 422),
        ("unassigned", 409),
        ("synthetic", 403),
        ("fixture", 403),
        ("demo_family", 403),
        ("homework", 422),
        ("exam", 422),
        ("too_large", 422),
    ],
)
def test_invalid_selection_never_reserves(notebook, change, status):
    value = body(notebook)
    if change == "duplicate":
        value["notebook_sources"][1] = copy.deepcopy(value["notebook_sources"][0])
    elif change == "missing_primary":
        value["notebook_sources"] = value["notebook_sources"][1:]
    elif change == "stale":
        value["notebook_sources"][1]["revision"] += 1
    else:
        with DB.begin() as db:
            page = db.get(Material, notebook.refs[1]["id"])
            if change == "unconfirmed":
                page.confirmed = False
            elif change == "other_subject":
                page.subject_id = identity("deutsch")
            elif change == "unassigned":
                page.subject_id = None
            elif change == "synthetic":
                page.synthetic = True
            elif change == "fixture":
                page.fixture_id = "synthetic-test-only"
            elif change == "demo_family":
                db.get(Family, notebook.parent["families"][0]["id"]).synthetic = True
            elif change in ("homework", "exam"):
                page.purpose = change
            elif change == "too_large":
                page.content = "Eigener Stoff. " * 5000
    before = inventory()
    response = post(notebook, value)
    assert response.status_code == status, response.text
    assert inventory() == before


@pytest.mark.parametrize("count", [True, 1, 6, 2.0, "3"])
def test_count_is_bounded_strict_integer(notebook, count):
    before = inventory()
    assert post(notebook, body(notebook, count)).status_code == 422
    assert inventory() == before


def test_new_fields_require_selection_and_cannot_mix_old_paths(notebook):
    for value in (
        {"material_id": notebook.refs[0]["id"], "question_count": 3},
        {**body(notebook), "assignment_id": "a" * 32},
        {**body(notebook), "review_of": "b" * 32},
        {**body(notebook), "notebook_sources": []},
    ):
        assert post(notebook, value).status_code == 422
    value = body(notebook)
    value.pop("question_count")
    response = post(notebook, value)
    assert response.status_code == 202
    with DB() as db:
        assert db.get(Job, response.json()["id"]).payload["notebook_practice"]["question_count"] == 2


def test_foreign_child_unauthenticated_and_parent_readonly_fail_before_reserve(notebook):
    other = create_child(notebook.parent_api, notebook.parent, "other-test-child")
    with DB.begin() as db:
        db.get(Material, notebook.refs[1]["id"]).child_id = other["id"]
    before = inventory()
    assert post(notebook).status_code == 404
    with TestClient(app, headers=HEADERS) as guest:
        assert post(notebook, client=guest).status_code == 401
    with DB.begin() as db:
        db.get(Material, notebook.refs[1]["id"]).child_id = notebook.child["id"]
        db.scalar(select(Membership).where(Membership.user_id == notebook.parent["id"])).permission = "view"
    assert post(notebook, client=notebook.parent_api).status_code == 403
    assert inventory() == before


@pytest.mark.parametrize("when", ["before", "during"])
def test_selected_revision_change_stops_before_dispatch_or_before_publish(notebook, monkeypatch, when):
    response = post(notebook)
    assert response.status_code == 202

    def change():
        with DB.begin() as db:
            db.get(Material, notebook.refs[1]["id"]).revision += 1

    if when == "before":
        change()
    before = inventory()
    result, calls = process(notebook, monkeypatch, response.json()["id"], callback=change if when == "during" else None)
    assert result["status"] == "failed", result
    assert len(calls) == (1 if when == "during" else 0)
    assert result["usage_status"] == ("failed_billed" if when == "during" else "failed_not_sent")
    assert result["cost"] == (200 if when == "during" else 0)
    assert inventory()[2:] == before[2:]


def test_changed_unselected_page_does_not_invalidate_explicit_selection(notebook, monkeypatch):
    response = post(notebook)
    with DB.begin() as db:
        db.get(Material, notebook.refs[2]["id"]).revision += 1
    result, calls = process(notebook, monkeypatch, response.json()["id"])
    assert result["status"] == "completed" and len(calls) == 1


def test_wrong_returned_count_is_billed_once_and_never_published(notebook, monkeypatch):
    response = post(notebook, body(notebook, 3))
    before = inventory()
    result, calls = process(notebook, monkeypatch, response.json()["id"], count=2)
    assert result["status"] == "failed" and len(calls) == 1
    assert result["usage_status"] == "failed_billed" and result["cost"] == 200
    assert inventory()[2:] == before[2:]


@pytest.mark.parametrize("count", [2, 3, 4, 5])
def test_entry_preserves_exact_selected_count_without_extra_prerequisites(notebook, count, monkeypatch):
    with DB.begin() as db:
        material = db.get(Material, notebook.refs[0]["id"])
        material.content = ENTRY_CONTENT
        payload = learning_entry.with_learning_entry(
            db,
            db.get(Child, notebook.child["id"]),
            {
                "material": {"subject": material.subject, "topic": material.topic, "content": material.content},
                "required_subject": material.subject,
                "notebook_practice": {"version": 1, "question_count": count},
            },
            [material],
            enabled=True,
        )
    plan = payload["learning_entry"]["units"][0]
    assert len(plan["probes"]) <= min(3, count - 1)
    schema = UnitOutput.model_json_schema()
    learning_entry.bind_entry_schema(schema, payload)
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    value = output(count)
    for question, spec in zip(value["questions"], learning_entry._specs(plan, count), strict=True):
        question.update({key: spec[key] for key in learning_entry.CORE if key in spec})
        question["id"] = spec["id"]
    learning_entry.validate_entry_output(payload, value)
    calls = _transport(monkeypatch, "openrouter", value)
    actual = providers.request_provider(_config("openrouter"), "unit", payload)
    assert len(calls) == 1 and len(actual.data["questions"]) == count
    sent, actual_schema, _ = _submitted("openrouter", calls[0])
    assert sent["learning_entry"] == payload["learning_entry"]
    assert actual_schema["properties"]["questions"]["minItems"] == count
    assert actual_schema["properties"]["questions"]["maxItems"] == count
    value["questions"].pop()
    with pytest.raises(ValueError):
        learning_entry.validate_entry_output(payload, value)


@pytest.mark.parametrize("provider", ["openai", "openrouter"])
@pytest.mark.parametrize("count", [2, 3, 4, 5])
def test_real_http_mock_schema_instructions_and_return_bind_count(monkeypatch, provider, count):
    original = graphic_output()
    template = copy.deepcopy(original["questions"][0])
    original["questions"] = [{**copy.deepcopy(template), "id": f"test{index}"} for index in range(count)]
    requested = {
        **graphic_payload(),
        "required_subject": "Mathematik",
        "notebook_practice": {"version": 1, "question_count": count},
    }
    calls = _transport(monkeypatch, provider, original)
    result = providers.request_provider(_config(provider), "unit", requested)
    assert len(calls) == 1 and len(result.data["questions"]) == count
    sent, schema, instructions = _submitted(provider, calls[0])
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert sent["notebook_practice"]["question_count"] == count
    assert f"GENAU {count} Aufgaben" in instructions
    if count != 2:
        assert "GENAU 2 Aufgaben" not in instructions
    for actual, expected in zip(result.data["questions"], original["questions"], strict=True):
        assert all(actual[key] == expected[key] for key in ("id", "type", "prompt", "answer", "options", "accepted"))


def test_new_selection_requires_captured_actor_even_for_another_authorized_parent(notebook, monkeypatch):
    from schulpilot import notebook_practice

    selected = []
    original = notebook_practice.selection

    def capture(*args, **kwargs):
        selected.append(True)
        return original(*args, **kwargs)

    monkeypatch.setattr(notebook_practice, "selection", capture)
    path = f"/api/children/{notebook.child['id']}/units"
    headers = {"Idempotency-Key": "notebook-actor-bound-request-0001"}
    before = inventory()
    missing = notebook.client.post(path, json=body(notebook), headers=headers)
    assert missing.status_code == 409
    stale = notebook.parent_api.post(
        path, json=body(notebook), headers={**headers, "X-Schulpilot-Account": notebook.actor_id}
    )
    assert stale.status_code == 409
    assert not selected and inventory() == before
    correct_headers = {**headers, "X-Schulpilot-Account": notebook.actor_id}
    first = notebook.client.post(path, json=body(notebook), headers=correct_headers)
    assert first.status_code == 202, first.text
    repeated = notebook.client.post(path, json=body(notebook), headers=correct_headers)
    assert repeated.status_code == 202 and repeated.json()["id"] == first.json()["id"]
    after = inventory()
    assert after == (before[0] + 1, before[1] + 1, *before[2:])
    # A cookie/account switch cannot turn replay into a fresh parent reservation.
    assert notebook.parent_api.post(path, json=body(notebook), headers=correct_headers).status_code == 409
    assert inventory() == after


def test_legacy_material_request_still_needs_no_account_header(notebook):
    path = f"/api/children/{notebook.child['id']}/units"
    headers = {"Idempotency-Key": "legacy-notebook-material-request-0001"}
    value = {"material_id": notebook.refs[0]["id"]}
    first = notebook.client.post(path, json=value, headers=headers)
    assert first.status_code == 202, first.text
    replay = notebook.client.post(path, json=value, headers=headers)
    assert replay.status_code == 202 and replay.json()["id"] == first.json()["id"]
