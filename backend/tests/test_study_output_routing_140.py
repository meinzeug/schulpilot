"""Artificial study-stage routing and actual native HTTP; no vendor traffic."""
import copy
import json
import socket
import traceback

import httpx
import pytest
from conftest import create_child
from schulpilot import providers, study_path, study_routing, worker
from schulpilot.db import (
    DB,
    Attempt,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    ProviderConfig,
    SchoolDay,
    Session,
    Usage,
    engine,
)
from schulpilot.model_routing import choose_tier, features_for, job_config, selection
from schulpilot.subject_content import Graphic
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import event, func, select
from test_graphic_native_transport import subset_record
from test_model_routing import setup_policy
from test_study_path import create, generate
from test_study_path import study as study

CONTENT = "Lupe - Puppe. Lupe und Puppe haben zwei Silben."


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise AssertionError("No external traffic in synthetic study routing tests")

    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket, "getaddrinfo", refuse)


@pytest.fixture
def routed(study):
    setup_policy(study["parent"]["families"][0]["id"])
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.max_output_tokens, cfg.reserve_micros = 8000, 500000
        cfg.routing_policy = {**cfg.routing_policy, "economy_mode": True, "routes": {
            tier: {**route, "max_output_tokens": 4000 if tier == "luna" else 8000,
                "reserve_micros": 150000 if tier == "luna" else 250000}
            for tier, route in cfg.routing_policy["routes"].items()}}
        for key in study["materials"][1:]:
            db.delete(db.get(Material, key))
        page = db.get(Material, study["materials"][0])
        page.subject, page.topic, page.content = "Deutsch", "Originalwörter", CONTENT
    return study


def queued(book):
    plan = create(book)
    block = next(row for row in plan["blocks"] if row.get("status") == "planned")
    response = generate(book, block["id"], "synthetic-first-study-output-140")
    assert response.status_code == 202, response.text
    repeated = generate(book, block["id"], "synthetic-first-study-output-140")
    assert repeated.json() == response.json() and repeated.status_code == 202
    return response.json()["id"], block["id"]


@pytest.mark.parametrize("subject", ["Mathematik", "Deutsch", "Englisch", "Physik", "Geschichte"])
def test_first_actual_stage_reserves_graphic_contract_not_input_size_or_previous_failure(routed, subject):
    with DB.begin() as db:
        db.get(Material, routed["materials"][0]).subject = subject
    job_id, _ = queued(routed)
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        policy = copy.deepcopy(db.get(ProviderConfig, 1).routing_policy)
        counts = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt, LearningUnit)]
        statements = []

        def observed(_conn, _cursor, statement, _parameters, _context, _many):
            statements.append(statement.lstrip().split()[0].upper())

        event.listen(engine, "before_cursor_execute", observed)
        try:
            facts = features_for(db, routed["child"]["id"], job_id)
        finally:
            event.remove(engine, "before_cursor_execute", observed)
        assert statements and set(statements) == {"SELECT"}
        assert facts["study_extended_output"] and not facts["study_length_failed"]
        assert facts["source_count"] == 1 and facts["source_chars"] < 100
        assert choose_tier("unit", facts, economy=True) == ("sol", "study_graphic_teaching")
        assert usage.route_snapshot["reason"] == "study_graphic_teaching" and usage.route_snapshot["tier"] == "sol"
        bound = job_config(db, db.get(Job, job_id), "unit")
        assert bound.max_output_tokens == 8000 and bound.reserve_micros == usage.reserved_micros == 250000
        assert bound.reasoning_effort == "medium" and db.get(ProviderConfig, 1).routing_policy == policy
        assert [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Attempt, LearningUnit)] == counts
        assert counts == [1, 1, 0, 0] and not db.new and not db.dirty


@pytest.mark.parametrize("fault", ["revision", "same_revision_text", "unconfirmed", "removed", "moved", "plan_hash",
    "missing_block", "published", "duplicate_source", "missing_source", "wrong_subject", "wrong_phase", "wrong_count",
    "planning", "missing_authority", "revoked", "running", "other_kind", "foreign_day", "foreign_source"])
def test_output_need_never_crosses_current_stage_sources_plan_authority_or_child(routed, api, fault):
    job_id, block_id = queued(routed)
    sibling = create_child(api, routed["parent"], "study140-sibling") if fault.startswith("foreign") else None
    with DB.begin() as db:
        job, day, page = db.get(Job, job_id), db.get(SchoolDay, routed["day_id"]), db.get(Material, routed["materials"][0])
        plan = copy.deepcopy(day.learning_plan)
        block = next(row for row in plan["blocks"] if row["id"] == block_id)
        if fault == "revision":
            page.revision += 1
        elif fault == "same_revision_text":
            page.content += " Weitere Aussage."
        elif fault == "unconfirmed":
            page.confirmed = False
        elif fault == "removed":
            db.delete(page)
        elif fault == "moved":
            page.school_day_id = None
        elif fault == "plan_hash":
            plan["source_hash"] = "0" * 64
        elif fault == "missing_block":
            plan["blocks"] = []
        elif fault == "published":
            block["unit_id"] = "a" * 32
        elif fault == "duplicate_source":
            block["material_ids"] *= 2
        elif fault == "missing_source":
            block["material_ids"] = ["a" * 32]
        elif fault == "wrong_subject":
            block["subject"] = "Englisch"
        elif fault == "wrong_phase":
            block["phase"] = "unknown"
        elif fault == "wrong_count":
            block["question_count"] = True
        elif fault == "planning":
            db.get(Child, routed["child"]["id"]).grade += 1
        elif fault == "missing_authority":
            job.payload = {key: value for key, value in job.payload.items() if key != "study_authority"}
        elif fault == "revoked":
            db.get(Session, job.payload["study_authority"]["session_id"]).revoked = True
        elif fault == "running":
            job.status = "running"
        elif fault == "other_kind":
            job.kind = "coach_practice"
        elif fault == "foreign_day":
            day.child_id = sibling["id"]
        else:
            page.child_id = sibling["id"]
        day.learning_plan = plan
    with DB() as db:
        assert study_routing.extended_output(db, routed["child"]["id"], db.get(Job, job_id)) is False
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0


def output(payload):
    def step(key, disclosure):
        block = Graphic.model_validate({"kind": "sentence", "title": "Originalwörter", "disclosure": disclosure,
            "source_excerpt": CONTENT, "labels": ["Lupe", "Puppe"], "numbers": [], "connections": [],
            "marks": [], "unit": "", "variant": "classification"}).model_dump(mode="json")
        return {"id": key, "text": "Vergleiche die Originalwörter Lupe und Puppe.", "competence_id": None,
            "disclosure": disclosure, "reference": {"id": "german.original_examples.comparison", "version": 1},
            "source_refs": ["p1"], "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [block]}}

    result = {"subject": payload["required_subject"], "topic": payload["required_topic"],
        "explanation": "Die Originalwörter Lupe und Puppe haben zwei Silben.", "explanation_steps": [step("intro", "given")],
        "questions": [{"id": "q1", "type": "choice", "prompt": "Wie viele Silben hat Lupe?", "options": ["zwei", "drei"],
            "answer": 0, "accepted": [], "hints": ["Lies die bestätigte Aussage zu Lupe."], "explanation": "Lupe hat zwei Silben.",
            "explanation_steps": [step("q1solution", "solution")], "presentation": None, "field_group": None},
            {"id": "q2", "type": "choice", "prompt": "Welches weitere Wort hat wie Lupe zwei Silben?", "options": ["Puppe", "Haus"],
            "answer": 0, "accepted": [], "hints": ["Vergleiche die Originalwörter."], "explanation": "Auch Puppe hat zwei Silben.",
            "explanation_steps": [step("q2solution", "solution")], "presentation": None, "field_group": None}]}
    if context := payload.get("catalog_context"):
        result["catalog_assignment"] = {"subject_ids": [context["subject_aliases"]["deutsch"]],
            "matches": [], "unmatched_context_refs": context["context_refs"]}
    return result


@pytest.mark.parametrize("race", ["none", "source", "authority", "configuration"])
def test_actual_worker_keeps_reserved_reason_exact_stage_count_native_graphics_and_one_billed_post(routed, monkeypatch, race):
    job_id, _ = queued(routed)
    with DB() as db:
        snapshot = copy.deepcopy(db.scalar(select(Usage).where(Usage.job_id == job_id)).route_snapshot)
        session_id = db.get(Job, job_id).payload["study_authority"]["session_id"]
    actual, decisions, calls, callback_errors = providers.request_provider, [], [], []
    from package_output_helpers import PackageOutputCapture

    transport = PackageOutputCapture(monkeypatch)

    def request(config, function, payload):
        assert function == "unit" and selection(config) == snapshot
        decisions.append(copy.deepcopy(selection(config)))
        assert payload["study_block"]["mode"] == "understand" and payload["study_block"]["question_count"] == 2
        assert len(payload["study_block"]["tasks"]) == 2 and payload["visual_context"]["required"] is True
        return actual(config, function, payload)

    monkeypatch.setattr(study_path, "request_provider", request)
    real = httpx.Client

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        schema = body["response_format"]["json_schema"]["schema"]
        subset_record(schema)
        assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == 2
        assert all(key.startswith("d") for key in schema["$defs"])
        payload = json.loads(body["messages"][1]["content"][0]["text"])
        if race == "source":
            with DB.begin() as db:
                page = db.get(Material, routed["materials"][0])
                page.revision += 1
        elif race == "authority":
            with DB.begin() as db:
                db.get(Session, session_id).revoked = True
        elif race == "configuration":
            with DB.begin() as db:
                db.get(ProviderConfig, 1).revision += 1
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(transport.wire(output(payload)))}}],
            "usage": {"prompt_tokens": 1000, "completion_tokens": 1000, "cost": .001}})

    def checked_handler(request):
        try:
            return handler(request)
        except AssertionError:
            callback_errors.append(traceback.format_exc())
            raise

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(checked_handler)))
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    assert not callback_errors, "\n".join(callback_errors)
    with DB() as db:
        job = db.get(Job, job_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert len(calls) == len(decisions) == 1 and usage.cost_micros == 1000 and usage.cost_source == "reported"
        assert usage.route_snapshot == snapshot
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        if race == "none":
            assert job.status == "completed", job.error
            unit = db.get(LearningUnit, job.result["unit_id"])
            assert unit.round_kind == "study_block" and len(unit.questions) == 2
            assert db.get(UnitVisualSnapshot, unit.id).status == "ready"
        else:
            assert job.status == "failed" and usage.status == "failed_billed"
            assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
    worker.process(job_id)
    assert len(calls) == 1


def test_feature_cannot_change_other_functions_or_override_existing_length_precedence():
    assert choose_tier("unit", {"study_extended_output": True, "study_length_failed": True}, economy=True) == (
        "sol", "recorded_study_output_length")
    assert choose_tier("coach", {"study_extended_output": True}, economy=True) == ("luna", "bounded_source_or_review")


def test_initial_graphic_route_still_requires_the_ordinary_budget(routed):
    plan = create(routed)
    block = next(row for row in plan["blocks"] if row.get("status") == "planned")
    with DB.begin() as db:
        db.get(Family, routed["parent"]["families"][0]["id"]).budget_micros = 200000
    response = generate(routed, block["id"], "synthetic-too-small-budget-140")
    assert response.status_code == 429
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0


def test_native_study_request_without_selected_graphic_route_keeps_4500_cap(household, monkeypatch):
    from schulpilot.visual_references import with_visual_context
    from test_presentation_capability_paths import _config

    class Captured(BaseException):
        pass

    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        page = Material(child_id=child.id, title="PUBLIC SYNTHETIC", subject="Deutsch", topic="Originalwörter",
            content=CONTENT, confirmed=True, status="confirmed")
        db.add(page)
        db.flush()
        payload = with_visual_context(db, child, {"grade": 6, "required_subject": "Deutsch",
            "required_topic": "Originalwörter", "material": {"subject": "Deutsch", "topic": "Originalwörter", "content": CONTENT},
            "study_block": {"mode": "understand", "question_count": 2, "tasks": []}}, [page])
    calls, real = [], httpx.Client

    def handler(request):
        calls.append(json.loads(request.content))
        raise Captured

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    cfg = _config("openrouter")
    cfg.max_output_tokens, cfg.reserve_micros = 8000, 250000
    assert selection(cfg) == {} and payload["visual_context"]["required"] is True
    with pytest.raises(Captured):
        providers.request_provider(cfg, "unit", payload)
    assert len(calls) == 1 and calls[0]["max_tokens"] == 4500
    assert cfg.max_output_tokens == 8000 and cfg.reserve_micros == 250000
