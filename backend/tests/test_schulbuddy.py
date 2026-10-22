"""Real private routes/queue, exclusively artificial content and mocked adapters."""

import copy
import uuid

import httpx
import pytest
from schulpilot import codex_setup, schulbuddy, schulbuddy_provider, schulbuddy_setup
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Job,
    Membership,
    ProviderConfig,
    SchulbuddyTurn,
    Usage,
    now,
)
from schulpilot.providers import Result
from schulpilot.schulbuddy_provider import binding_key
from schulpilot.security import audit
from schulpilot.worker import claim, process
from sqlalchemy import func, select
from test_codex_models import operator as operator_fixture
from test_tutor import notebook as notebook_fixture


def catalog():
    return {"source": "codex_cli", "cli_version": "0.162.1", "models": [{"id": "synthetic-luna",
        "name": "Artificial Luna", "reasoning_efforts": ["medium", "high"], "default_reasoning_effort": "medium",
        "input_modalities": ["text"], "hidden": False}]}


@pytest.fixture
def operator():
    yield from operator_fixture.__wrapped__()


@pytest.fixture
def book(api, household, monkeypatch):
    object.__setattr__(settings, "codex_approved", True)
    object.__setattr__(settings, "codex_socket", "/synthetic/no-network.sock")
    object.__setattr__(settings, "codex_auth_mode", "account")
    object.__setattr__(settings, "synthetic_ai_enabled", True)
    monkeypatch.setattr(codex_setup, "worker_models", catalog)
    monkeypatch.setattr(codex_setup, "worker_health", lambda: {"ready": True})
    for value in notebook_fixture.__wrapped__(api, household):
        with DB.begin() as db:
            base = db.get(ProviderConfig, 1)
            base.routing_policy = {"budget": {"target_eur_micros": 7000000, "warning_eur_micros": 9000000,
                "hard_eur_micros": 12000000, "eur_per_usd": "1", "fx_evidence": "Synthetic conservative test conversion",
                "fx_checked_at": int(now()), "fee_reserve_bps": 800}}
            binding = schulbuddy_provider.select_local(db, "synthetic-luna", "Synthetic explicit account privacy approval")
            binding.production_block_reason = ""
            binding.capability_evidence = "Synthetic mocked capability proof, no actual inference"
            audit(db, "synthetic-operator", "schulbuddy.binding_accepted", binding_key(binding))
        yield value


@pytest.fixture
def transport(monkeypatch):
    state = {"calls": [], "effect": None, "output": {"answer": "Die Sonne ist ein Stern.",
        "sources": [{"ref": "p1", "quote": "Die Sonne ist ein Stern."}], "next_question": None, "starters": []}}

    def request(config, function, payload):
        assert (config.provider, config.model, config.reasoning_effort, function) == ("codex", "synthetic-luna", "high", "schulbuddy")
        state["calls"].append(copy.deepcopy(payload))
        if state["effect"]:
            state["effect"]()
        return Result(copy.deepcopy(state["output"]), 50, 80, None, cost_source="unknown")

    monkeypatch.setattr(schulbuddy, "request_provider", request)
    return state


def ask(book, *, client=None, key=None, **extra):
    return (client or book["client"]).post("/api/schulbuddy/questions", json={"page_kind": "learn",
        "unit_id": book["unit_id"], "question": "Was ist die Sonne?", **extra},
        headers={"Idempotency-Key": key or uuid.uuid4().hex})


def finish():
    with DB() as db:
        identifier = claim(db)
    assert identifier
    process(identifier)
    return identifier


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt, Activity))


def test_context_and_starters_are_local_page_specific_and_never_reserve(api, book, transport, monkeypatch):
    monkeypatch.setattr(codex_setup, "worker_models", lambda: pytest.fail("GET must not invoke the CLI catalogue"))
    before = counts()
    value = book["client"].get("/api/schulbuddy/context", params={"page_kind": "learn", "unit_id": book["unit_id"]})
    assert value.status_code == 200, value.text
    data = value.json()
    assert data["available"] and data["model"] == "synthetic-luna" and data["reasoning_effort"] == "high"
    assert "Sonnensystem" in data["label"] and "Sonnensystem" in data["starters"][0] and len(data["starters"]) <= 3
    other = book["client"].get("/api/schulbuddy/context", params={"page_kind": "words"}).json()
    assert other["starters"] != data["starters"] and not other["history"]
    assert counts() == before and transport["calls"] == []


def test_explicit_request_is_idempotent_bound_to_high_and_account_unknown_budget(api, book, transport):
    key = uuid.uuid4().hex
    first = ask(book, key=key)
    assert first.status_code == 202, first.text
    assert ask(book, key=key).json()["id"] == first.json()["id"]
    assert ask(book, key=key, question="Andere Frage").status_code == 409
    assert counts()[:2] == (1, 1)
    finish()
    turn = book["client"].get("/api/schulbuddy/questions/" + first.json()["id"]).json()
    assert turn["status"] == "ready" and turn["answer"] == "Die Sonne ist ein Stern."
    assert turn["sources"][0]["material_id"] == book["material_id"]
    with DB() as db:
        usage = db.scalar(select(Usage))
        assert usage.provider == "codex" and usage.model == "synthetic-luna" and usage.cost_micros is None
        assert usage.child_budget_id and usage.route_snapshot["binding"]
        job = db.scalar(select(Job))
        assert job.payload["model_binding"]["reasoning_effort"] == "high"
        assert "question" not in job.payload and "sources" not in job.payload
        assert db.get(ProviderConfig, 1).provider == "openai"
    assert len(transport["calls"]) == 1 and counts()[2:] == (0, 0)


def test_admin_and_other_parent_cannot_read_or_submit_private_context(api, book, operator, transport):
    first = ask(book).json()
    assert operator.get("/api/schulbuddy/context", params={"unit_id": book["unit_id"]}).status_code == 403
    assert operator.get("/api/schulbuddy/questions/" + first["id"]).status_code == 404
    assert operator.post("/api/schulbuddy/questions", json={"question": "Hallo"}, headers={"Idempotency-Key": uuid.uuid4().hex}).status_code == 403
    assert api.get("/api/schulbuddy/questions/" + first["id"]).status_code == 404
    status = operator.get("/api/schulbuddy/context", params={"page_kind": "admin"}).json()
    assert not status["available"] and not status["history"]


def test_read_only_parent_may_read_context_but_cannot_spend_family_budget(api, book):
    with DB.begin() as db:
        membership = db.scalar(select(Membership).where(Membership.user_id == book["parent"]["id"]))
        membership.permission = "view"
    assert api.get("/api/schulbuddy/context", params={"unit_id": book["unit_id"]}).status_code == 200
    assert ask(book, client=api).status_code == 403
    assert counts()[:2] == (0, 0)


@pytest.mark.parametrize("change", ["source", "provider", "binding", "session"])
def test_changes_after_dispatch_discard_answer_and_preserve_billed_unknown(api, book, transport, change):
    first = ask(book).json()
    def mutate():
        from schulpilot.db import Material, Session

        with DB.begin() as db:
            if change == "source":
                db.get(Material, book["material_id"]).revision += 1
            elif change == "provider":
                db.get(ProviderConfig, 1).revision += 1
            elif change == "binding":
                db.get(ProviderConfig, 2).revision += 1
            else:
                turn = db.get(SchulbuddyTurn, first["id"])
                db.get(Session, turn.session_id).revoked = True
    transport["effect"] = mutate
    finish()
    with DB() as db:
        turn = db.get(SchulbuddyTurn, first["id"])
        assert turn.status == "failed" and turn.reply is None
        assert db.scalar(select(Usage)).cost_micros is None
    assert counts()[2:] == (0, 0) and len(transport["calls"]) == 1


def test_missing_high_catalog_is_a_blocker_without_provider_substitution(api, book, transport, monkeypatch):
    value = catalog()
    value["models"][0]["reasoning_efforts"] = ["medium"]
    monkeypatch.setattr(codex_setup, "worker_models", lambda: value)
    response = ask(book)
    assert response.status_code == 503 and "Luna/high" in response.text
    assert counts()[:2] == (0, 0) and not transport["calls"]


def test_ui_only_account_context_omits_all_learning_evidence(api, book, transport):
    first = ask(book, page_kind="account", unit_id=None)
    assert first.status_code == 202, first.text
    transport["output"]["sources"] = []
    finish()
    payload = transport["calls"][0]
    assert payload["knowledge"] == {} and payload["sources"] == [] and "grade" not in payload


def test_source_revision_marks_history_old_and_prevents_old_reply_chain(api, book, transport):
    from schulpilot.db import Material

    first = ask(book).json()
    finish()
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    old = book["client"].get("/api/schulbuddy/questions/" + first["id"]).json()
    assert old["source_changed"] and "älteren Quellenfassung" in old["notice"]
    assert ask(book, reply_to=first["id"]).status_code == 409


def test_actual_successful_question_help_is_recorded_once_without_rewriting_answers(api, book, transport):
    from schulpilot.db import LearningUnit

    with DB.begin() as db:
        unit = db.get(LearningUnit, book["unit_id"])
        unit.status = "active"
        unit.questions = [{"id": "q1", "type": "short", "prompt": "Was ist die Sonne?", "options": [],
                           "answer": "Stern", "accepted": [], "hints": [], "explanation": "Synthetisch"}]
    key = uuid.uuid4().hex
    first = ask(book, question_id="q1", key=key)
    assert first.status_code == 202, first.text
    before = counts()[2:]
    identifier = finish()
    process(identifier)
    with DB() as db:
        rows = list(db.scalars(select(Activity).where(Activity.kind == "explanation")))
        assert len(rows) == 1 and rows[0].detail["question_id"] == "q1"
        assert db.scalar(select(func.count()).select_from(Attempt)) == before[0]
        assert "answer" not in transport["calls"][0]["current_question"]
    assert ask(book, question_id="q1", key=key).json()["id"] == first.json()["id"]


def test_parent_consultation_does_not_record_child_support(api, book, transport):
    first = ask(book, client=api)
    assert first.status_code == 202
    finish()
    assert counts()[2:] == (0, 0)


def test_source_erasure_removes_quotes_and_cancels_only_unsent_reservation(api, book):
    first = ask(book).json()
    with DB.begin() as db:
        schulbuddy.purge_sources(db, [book["material_id"]], child_id=book["child"]["id"])
    with DB() as db:
        assert db.get(SchulbuddyTurn, first["id"]) is None
        assert db.scalar(select(Usage)).status == "failed_not_sent"
    assert book["client"].get("/api/schulbuddy/questions/" + first["id"]).status_code == 404


def test_operator_selection_is_disabled_until_fixed_accounted_probe(api, book, monkeypatch):
    from schulpilot.schulbuddy_schemas import synthetic_payload

    with DB.begin() as db:
        schulbuddy_provider.select_local(db, "synthetic-luna", "Synthetic explicit account privacy approval")
    assert not book["client"].get("/api/schulbuddy/context").json()["available"]
    calls = []
    def fixed(config, function, payload, **kwargs):
        calls.append((config.model, config.reasoning_effort, kwargs))
        text = synthetic_payload()["sources"][0]["content"]
        return Result({"answer": "Künstliche Antwort", "next_question": None, "sources": [{"ref": "p1", "quote": text}], "starters": []},
                      40, 30, None, cost_source="unknown")
    monkeypatch.setattr(schulbuddy_setup, "request_provider", fixed)
    result = schulbuddy_setup.probe_once()
    assert result["available"] and len(calls) == 1 and calls[0][0:2] == ("synthetic-luna", "high")
    assert calls[0][2] == {"synthetic_fixture": True, "private_probe": True}
    assert book["client"].get("/api/schulbuddy/context").json()["available"]


def test_unknown_quote_is_rejected_without_hidden_repair_or_retry(api, book, transport):
    first = ask(book).json()
    transport["output"]["sources"][0]["quote"] = "Unbelegte künstliche Behauptung"
    finish()
    value = book["client"].get("/api/schulbuddy/questions/" + first["id"]).json()
    assert value["status"] == "failed" and value["answer"] is None and len(transport["calls"]) == 1


def test_codex_transport_forces_no_search_even_with_operator_search_enabled(api, book, monkeypatch):
    from schulpilot import providers

    calls = []
    object.__setattr__(settings, "codex_web_search", True)
    class Client:
        def __init__(self, **kwargs):
            assert kwargs["follow_redirects"] is False
        def __enter__(self):
            return self
        def __exit__(self, *_):
            pass
        def post(self, url, json):
            calls.append(json)
            assert url == "http://localhost/generate"
            return httpx.Response(200, json={"data": {"answer": "Künstliche Bedienhilfe", "next_question": None,
                "sources": [], "starters": []}, "usage": {"input_tokens": 40, "output_tokens": 25}, "search_calls": 0})
    monkeypatch.setattr(providers.httpx, "Client", Client)
    with DB() as db:
        config = schulbuddy_provider.configured(db)
    providers.request_provider(config, "schulbuddy", {"question": "SYNTHETIC-PRIVATE-NO-SEARCH", "sources": []})
    assert len(calls) == 1 and calls[0]["web_search"] is False and calls[0]["reasoning_effort"] == "high"
    assert "Websuche ist für eine fachliche Gegenprüfung erlaubt" not in calls[0]["system"]


def test_parallel_same_request_creates_exactly_one_job_and_hold(api, book):
    from concurrent.futures import ThreadPoolExecutor

    key = uuid.uuid4().hex
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: ask(book, key=key), range(2)))
    assert [r.status_code for r in results] == [202, 202]
    assert len({r.json()["id"] for r in results}) == 1
    assert counts()[:2] == (1, 1)


def test_changed_source_before_dispatch_makes_no_call_and_releases_unsent_hold(api, book, transport):
    from schulpilot.db import Material

    first = ask(book).json()
    with DB.begin() as db:
        db.get(Material, book["material_id"]).revision += 1
    finish()
    assert transport["calls"] == []
    with DB() as db:
        assert db.get(SchulbuddyTurn, first["id"]).status == "failed"
        assert db.scalar(select(Usage)).status == "failed_not_sent"


def test_unit_erasure_clears_related_advice_without_refunding_spent_usage(api, book, transport):
    from schulpilot.schulbuddy import purge_units

    first = ask(book).json()
    finish()
    with DB.begin() as db:
        before = db.scalar(select(Usage)).status
        purge_units(db, book["child"]["id"], [book["unit_id"]])
    with DB() as db:
        assert db.get(SchulbuddyTurn, first["id"]) is None
        assert db.scalar(select(Usage)).status == before
