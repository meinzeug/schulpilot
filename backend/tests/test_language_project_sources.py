"""Artificial workshop evidence through the actual adapter and queue paths."""

import copy
import json
from concurrent.futures import ThreadPoolExecutor

import httpx
import pytest
from fastapi import HTTPException
from schulpilot import language_projects, providers
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Audit,
    Family,
    Job,
    LanguageProject,
    LearningUnit,
    Material,
    ProviderConfig,
    Session,
    Usage,
    VocabularyItem,
)
from schulpilot.language_repair import ACTION, queue_repair
from schulpilot.language_tasks import LanguageProjectOutput
from schulpilot.providers import ProviderError, Result, request_provider, strict_schema
from sqlalchemy import func, select, update
from test_language_jobs import notebook as notebook
from test_language_jobs import project_request, proposal, run_job
from test_providers import configured
from test_vocabulary import child_login, import_words


@pytest.fixture
def workshop_transport(api, household, monkeypatch):
    parent, _ = household
    configured(parent["families"][0]["id"])
    with DB() as db:
        config = db.get(ProviderConfig, 1)
    config.capability_evidence = "artificial transport; upstream=test/fp8"
    config.input_per_million_micros = config.output_per_million_micros = 0
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/synthetic/private-worker.sock")
    object.__setattr__(settings, "codex_auth_mode", "account")
    calls = []
    payload = {
        "mode": "exam",
        "target_locale": "en-GB",
        "grade": 6,
        "goal": "Schulwörter anwenden",
        "words": [
            {"id": "a" * 32, "word": "apple", "meaning": "Apfel", "context": "", "variants": []},
            {"id": "b" * 32, "word": "school", "meaning": "Schule", "context": "", "variants": []},
        ],
        # A table is confirmed too; the original page need not contain '='.
        "materials": [{"ref": "p1", "content": "Wort\tBedeutung\napple\tApfel\nschool\tSchule"}],
    }
    output = proposal("a" * 32)

    class Client:
        def __init__(self, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def post(self, url, **kwargs):
            body = kwargs["json"]
            calls.append((url, body))
            data = copy.deepcopy(output)
            if config.provider in ("codex", "openrouter"):
                for question in data["questions"]:
                    if question["type"] == "choice":
                        question["answer"] = question["options"].index(question["answer"])
            if config.provider == "codex":
                response = {"data": data, "usage": {"input_tokens": 123, "output_tokens": 234}}
            elif config.provider == "openrouter":
                response = {
                    "choices": [{"finish_reason": "stop", "message": {"content": json.dumps(data)}}],
                    "usage": {"prompt_tokens": 123, "completion_tokens": 234, "cost": 0},
                }
            else:
                response = {
                    "status": "completed",
                    "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(data)}]}],
                    "usage": {"input_tokens": 123, "output_tokens": 234},
                }
            return httpx.Response(200, json=response)

    monkeypatch.setattr(providers.httpx, "Client", Client)
    monkeypatch.setattr(providers, "verify_free_endpoint", lambda *args: None)
    return config, payload, output, calls


@pytest.mark.parametrize("provider", ["codex", "openrouter", "openai"])
def test_confirmed_pair_quotes_bound_before_generation_and_decoded(workshop_transport, provider):
    config, payload, output, calls = workshop_transport
    config.provider, config.model = provider, "artificial-model:free"
    original = copy.deepcopy(payload)
    output["questions"][0].update(type="choice", options=["school", "apple"])
    result = request_provider(config, "language_project", payload)
    assert len(calls) == 1 and result.data == LanguageProjectOutput.model_validate(output).model_dump()
    assert payload == original
    _, body = calls[0]
    if provider == "codex":
        schema, submitted, instructions = body["schema"], body["payload"], body["system"]
    elif provider == "openrouter":
        schema = body["response_format"]["json_schema"]["schema"]
        submitted = json.loads(body["messages"][1]["content"][0]["text"])
        instructions = body["messages"][0]["content"]
        assert body["provider"]["allow_fallbacks"] is False
    else:
        schema = body["text"]["format"]["schema"]
        submitted = json.loads(body["input"][0]["content"][0]["text"])
        instructions = body["instructions"]
        assert body["store"] is False
    assert schema["properties"]["source_excerpt"]["enum"] == ["apple = Apfel", "school = Schule"]
    definition = schema["$defs"]["LanguageGeneratedQuestion"]
    branches = definition.get("anyOf", [definition])
    for branch in branches:
        props = branch["properties"]
        assert props["source_excerpt"]["enum"] == ["apple = Apfel", "school = Schule"]
        assert props["vocabulary_item_id"]["enum"] == ["a" * 32, "b" * 32]
        assert props["task_kind"]["enum"] == ["context_gap", "sentence_order", "free_sentence"]
        assert props["cue_locale"]["enum"] == ["de-DE", "en-GB"]
    assert submitted["source_evidence"][0] == {"vocabulary_item_id": "a" * 32, "source_excerpt": "apple = Apfel"}
    assert "EXAKT" in instructions and result.input_tokens == 123


@pytest.mark.parametrize("provider", ["codex", "openrouter", "openai"])
@pytest.mark.parametrize("invalid", ["paraphrase", "combined", "question", "other_word"])
def test_schema_ignoring_provider_cannot_bypass_literal_or_word_binding(workshop_transport, provider, invalid):
    config, payload, output, calls = workshop_transport
    config.provider, config.model = provider, "artificial-model:free"
    if invalid == "paraphrase":
        output["source_excerpt"] = "Ein Apfel heißt apple."
    elif invalid == "combined":
        output["source_excerpt"] = "apple = Apfel; school = Schule"
    elif invalid == "question":
        output["questions"][0]["source_excerpt"] = "apple – Apfel"
    else:
        output["questions"][0]["source_excerpt"] = "school = Schule"
    with pytest.raises(ProviderError, match="bestätigten Wortbeleg"):
        request_provider(config, "language_project", payload)
    assert len(calls) == 1


@pytest.mark.parametrize("mode", ["context_gap", "sentence_order", "grammar"])
def test_selected_project_mode_keeps_specific_schema(workshop_transport, mode):
    _, payload, _, _ = workshop_transport
    payload["mode"] = mode
    schema = strict_schema(LanguageProjectOutput)
    providers.bind_language_project_sources(schema, payload)
    props = schema["$defs"]["LanguageGeneratedQuestion"]["properties"]
    assert props["task_kind"]["enum"] == [mode]
    if mode == "sentence_order":
        assert props["type"]["enum"] == ["short"]


def failed_project(api, child, material_id, monkeypatch):
    import_words(api, child)
    child_login(api)
    response, _, item_id = project_request(api, child, material_id, mode="exam")
    assert response.status_code == 202
    row = response.json()
    bad = proposal(item_id, source="Ein nicht vorhandenes Zitat.")
    monkeypatch.setattr(language_projects, "request_provider", lambda *args: Result(bad, 12, 34, None))
    run_job(row["job_id"])
    return row, item_id


def test_one_local_repair_is_concurrent_idempotent_reserved_and_preserves_failure(api, notebook, monkeypatch):
    _, child, material_id = notebook
    row, item_id = failed_project(api, child, material_id, monkeypatch)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda _: queue_repair(row["id"], row["job_id"]), range(4)))
    assert len({result["job_id"] for result in results}) == 1
    assert sum(not result["replayed"] for result in results) == 1
    repair = results[0]
    with DB() as db:
        assert db.get(Job, row["job_id"]).status == "failed"
        assert "Beleg" in db.get(Job, row["job_id"]).error
        usages = list(db.scalars(select(Usage)))
        assert len(usages) == 2 and {u.status for u in usages} == {"failed_unknown", "reserved"}
        old_usage = next(u for u in usages if u.job_id == row["job_id"])
        assert (old_usage.input_tokens, old_usage.output_tokens) == (12, 34)
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == ACTION)) == 1
    monkeypatch.setattr(language_projects, "request_provider", lambda *args: Result(proposal(item_id), 20, 30, None))
    run_job(repair["job_id"])
    visible = api.get(f"/api/children/{child['id']}/language-projects/{row['id']}").json()
    assert visible["status"] == "ready" and visible["unit_id"]
    assert "source_excerpt" not in visible["result"]  # Exam feedback remains hidden.
    unit = api.get(f"/api/units/{visible['unit_id']}").json()
    assert all("answer" not in q and "accepted" not in q for q in unit["questions"])
    assert queue_repair(row["id"], row["job_id"])["replayed"]
    with pytest.raises(HTTPException):
        queue_repair(row["id"], repair["job_id"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Job)) == 2


@pytest.mark.parametrize("block", ["source", "item", "logout", "quota", "active_job"])
def test_operator_repair_keeps_session_revision_quota_and_single_job_guards(api, notebook, monkeypatch, block):
    parent, child, material_id = notebook
    row, _ = failed_project(api, child, material_id, monkeypatch)
    with DB.begin() as db:
        if block == "source":
            db.get(Material, material_id).revision += 1
        elif block == "item":
            db.scalar(select(VocabularyItem)).revision += 1
        elif block == "logout":
            db.execute(update(Session).values(revoked=True))
        elif block == "quota":
            db.get(Family, parent["families"][0]["id"]).call_limit = 1
        else:
            db.add(Job(child_id=child["id"], kind="language_project", payload={}, idempotency="artificial-active-job"))
    with pytest.raises(HTTPException):
        queue_repair(row["id"], row["job_id"])
    with DB() as db:
        assert db.get(LanguageProject, row["id"]).status == "failed"
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == ACTION)) == 0
