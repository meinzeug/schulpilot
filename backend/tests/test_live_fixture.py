import json
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from fastapi import HTTPException
from schulpilot import providers
from schulpilot.config import settings
from schulpilot.db import DB, Family, Job, Material, ProviderConfig, Usage, uid
from schulpilot.fixtures import FIXTURE_ID
from schulpilot.providers import ProviderError, config_for_function, external_allowed, request_provider, reserve
from schulpilot.schemas import Question
from schulpilot.security import encrypt
from schulpilot.synthetic import sample_unit
from schulpilot.worker import claim, process
from sqlalchemy import func, select


def setup_free():
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    with DB.begin() as db:
        c = db.get(ProviderConfig, 1)
        c.provider, c.model = "openrouter", "test-fixture/text:free"
        c.extraction_model = "test-fixture/image:free"
        c.capability_evidence = "synthetic test fixture upstream=test-text"
        c.extraction_capability_evidence = "synthetic test fixture upstream=test-image"
        c.encrypted_key = encrypt("SYNTHETIC-TEST-KEY")
        c.emergency_stop = False
        c.image_capable = c.structured_capable = True
        c.input_per_million_micros = c.output_per_million_micros = 0
        c.pricing_evidence = "synthetic test fixture, no actual prices"
        c.reserve_micros = 1000


def test_free_fixture_never_unlocks_real_data(api, household):
    setup_free()
    _, child = household
    with DB() as db:
        config = db.get(ProviderConfig, 1)
        with pytest.raises(ProviderError):
            external_allowed(config)
        external_allowed(config, synthetic_fixture=True)
        assert config_for_function(config, "extract").model == "test-fixture/image:free"
    assert api.post(f"/api/children/{child['id']}/materials/synthetic-fixture").status_code == 403
    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    material = api.post(f"/api/children/{demo['child_id']}/materials/synthetic-fixture").json()
    assert material["fixture_id"] == FIXTURE_ID and material["status"] == "uploaded"
    assert api.get(f"/api/materials/{material['id']}/image").content.startswith(b"\xff\xd8")
    with DB.begin() as db:
        db.get(ProviderConfig, 1).emergency_stop = True
    before = api.get(f"/api/children/{demo['child_id']}/overview").status_code
    assert before == 200
    response = api.post(f"/api/materials/{material['id']}/extract", headers={"Idempotency-Key": "test-emergency"})
    assert response.status_code == 503
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def test_fixture_rejects_private_edits_and_records_real_provider(api, monkeypatch):
    setup_free()
    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    material = api.post(f"/api/children/{demo['child_id']}/materials/synthetic-fixture").json()

    def response(config, function, payload, image_bytes=None, *, synthetic_fixture=False):
        assert synthetic_fixture is True
        if function == "extract":
            return providers.Result(
                {
                    "subject": "Mathematik",
                    "topic": "Brüche",
                    "content": "Synthetischer Bruchstoff",
                    "uncertainties": [],
                    "homework": [],
                },
                10,
                20,
                0,
            )
        return providers.Result(sample_unit(), 20, 100, 0)

    monkeypatch.setattr("schulpilot.worker.request_provider", response)
    q = api.post(f"/api/materials/{material['id']}/extract", headers={"Idempotency-Key": "extract"}).json()
    with DB() as db:
        assert claim(db) == q["id"]
    process(q["id"])
    m = api.get(f"/api/materials/{material['id']}").json()
    assert m["status"] == "review" and m["extraction_model"] == "test-fixture/image:free"
    confirm = {k: m[k] for k in ("subject", "topic", "content", "homework")}
    assert (
        api.put(
            f"/api/materials/{m['id']}/confirm",
            json={**confirm, "content": "Private caller text", "uncertainties_resolved": True},
        ).status_code
        == 422
    )
    assert (
        api.put(f"/api/materials/{m['id']}/confirm", json={**confirm, "uncertainties_resolved": True}).status_code
        == 200
    )
    q = api.post(
        f"/api/children/{demo['child_id']}/units", headers={"Idempotency-Key": "unit"}, json={"material_id": m["id"]}
    ).json()
    with DB() as db:
        assert claim(db) == q["id"]
    process(q["id"])
    done = api.get(f"/api/jobs/{q['id']}").json()
    assert done["status"] == "completed", done
    unit = api.get(f"/api/units/{done['result']['unit_id']}").json()
    assert unit["synthetic"] is True and unit["provider"] == "openrouter" and unit["model"] == "test-fixture/text:free"
    with DB() as db:
        assert [u.cost_micros for u in db.scalars(select(Usage))] == [0, 0]


def test_provider_replaces_all_caller_data_with_owned_fixture(api, monkeypatch):
    setup_free()
    captured = []

    class Client:
        def __init__(self, **_):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def post(self, url, headers, json):
            captured.append(json)
            return httpx.Response(
                200,
                json={
                    "choices": [
                        {"finish_reason": "stop", "message": {"content": __import__("json").dumps(sample_unit())}}
                    ],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "cost": 0},
                },
            )

    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *_: None)
    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    result = request_provider(
        config, "unit", {"name": "PRIVATE-NAME", "answers": "PRIVATE-ANSWER"}, b"PRIVATE-IMAGE", synthetic_fixture=True
    )
    body = captured[0]
    assert all(value not in json.dumps(body) for value in ["PRIVATE-NAME", "PRIVATE-ANSWER", "PRIVATE-IMAGE"])
    assert body["provider"]["max_price"] == {"prompt": 0, "completion": 0, "request": 0}
    assert body["provider"]["allow_fallbacks"] is False and body["provider"]["only"] == ["test-text"]
    assert result.cost_micros == 0
    config.model = "test-fixture/paid"
    with pytest.raises(ProviderError):
        request_provider(config, "unit", {}, synthetic_fixture=True)


def test_free_global_limit_is_atomic_and_does_not_commit_partial_jobs(api):
    setup_free()
    demo = api.post("/api/demo").json()
    with DB() as db:
        material = db.get(Material, demo["material_id"])
        fid = db.scalar(select(Family.id))
        child_id = material.child_id
    object.__setattr__(settings, "synthetic_ai_daily_limit", 3)

    def attempt(_):
        try:
            with DB.begin() as db:
                reserve(db, db.get(Family, fid), child_id, uid(), "unit", synthetic_fixture=True)
            return 200
        except HTTPException as error:
            return error.status_code

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(attempt, range(8)))
    assert results.count(200) == 3 and results.count(429) == 5
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 3


def test_known_fraction_error_is_rejected_without_another_ai_call():
    question = {
        "id": "q1",
        "type": "gap",
        "prompt": "Rechne aus: 1/4 + 2/4 = ?/4",
        "options": [],
        "answer": "4",
        "accepted": [],
        "hints": ["Addiere die Zähler."],
        "explanation": "Der Nenner bleibt 4.",
    }
    with pytest.raises(ValueError, match="Bruchlösung"):
        Question.model_validate(question)
    assert Question.model_validate({**question, "answer": "3"}).answer == "3"
    with pytest.raises(ValueError, match="Bruchlösung"):
        Question.model_validate({**question, "answer": "3", "accepted": ["4"]})


def test_fraction_equivalence_and_non_calculation_questions():
    from schulpilot.checks import fraction_result

    fraction_result("Wie viel ist 1/4 + 1/4?", "2/4", ["1/2"])
    fraction_result("Wie lautet der Nenner von 1/4 + 1/4?", "4", [])


@pytest.mark.parametrize(
    ("prompt", "answer"),
    [
        ("Welchen Zähler hat das Ergebnis von 1/4 + 3/4?", "4"),
        ("Wie lautet der Nenner des Ergebnisses von 1/4 + 1/4?", "4"),
    ],
)
def test_component_question_is_not_mistaken_for_a_whole_fraction(prompt, answer):
    from schulpilot.checks import fraction_result

    fraction_result(prompt, answer, [])
    with pytest.raises(ValueError, match="Bruchlösung"):
        fraction_result("Wie viel ist 1/4 + 3/4?", "4", [])


def test_child_cannot_rewrite_confirmed_material_or_its_homework(api):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    demo = api.post("/api/demo").json()
    api.headers["Authorization"] = "Bearer " + demo["token"]
    material = api.get("/api/materials/" + demo["material_id"]).json()
    confirmation = {k: material[k] for k in ("subject", "topic", "content", "homework")}
    confirmation["uncertainties_resolved"] = True
    assert api.put("/api/materials/" + material["id"] + "/confirm", json=confirmation).status_code == 200
    with TestClient(app, headers=HEADERS) as kid:
        credentials = demo["credentials"]
        logged = kid.post(
            "/api/auth/login",
            json={"username": credentials["child_username"], "password": credentials["child_password"]},
        ).json()
        kid.headers["Authorization"] = "Bearer " + logged["token"]
        assert kid.put("/api/materials/" + material["id"] + "/confirm", json=confirmation).status_code == 403
