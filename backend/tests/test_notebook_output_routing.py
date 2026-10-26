"""Synthetic API reservations distinguish fixed compiler steps from free graphics."""
import copy
import json

import httpx
import pytest
from conftest import create_child
from schulpilot import providers, worker
from schulpilot.db import DB, Attempt, Job, LearningUnit, Material, ProviderConfig, Usage, engine
from schulpilot.model_routing import choose_tier, features_for, job_config
from schulpilot.notebook_routing import extended_output
from schulpilot.visual_reference_models import UnitVisualSnapshot, VisualReference
from sqlalchemy import event, func, select
from sqlalchemy.orm.attributes import flag_modified
from test_model_routing import setup_policy
from test_notebook_fraction_expansions import CONTENT as EXPANSION
from test_notebook_fraction_expansions import binding_and_wire, http_mock
from test_notebook_practice import notebook as notebook
from test_notebook_practice import post
from test_unit_fraction_compositions import CONTENT as COMPOSITION

FREE = "Die Vielfachen von6 sind6,12,18 und24. Beim Multiplizieren von6 mit einer natürlichen Zahl erhältst du ein Vielfaches."


@pytest.fixture
def routed(notebook):
    setup_policy(notebook.parent["families"][0]["id"])
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.max_output_tokens, config.reserve_micros = 8000, 500000
        config.routing_policy = {**config.routing_policy, "economy_mode": True, "routes": {
            tier: {**route, "reserve_micros": 150000 if tier == "luna" else 250000,
                   "max_output_tokens": 4000 if tier == "luna" else 8000}
            for tier, route in config.routing_policy["routes"].items()}}
    return notebook


def select_source(book, kind="expansion", count=2):
    with DB.begin() as db:
        source = db.get(Material, book.refs[0]["id"])
        source.content, source.topic = {
            "expansion": (EXPANSION, "Brüche erweitern"),
            "composition": (COMPOSITION, "Unechte Brüche in gemischte Zahlen"),
            "free": (FREE, "Vielfache"),
        }[kind]
    return {"material_id": book.refs[0]["id"], "notebook_sources": copy.deepcopy(book.refs[:1]), "question_count": count}


def counts(db):
    return [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, LearningUnit, Attempt)]


@pytest.mark.parametrize("kind,count,tier", [
    ("expansion", 2, "luna"), ("composition", 2, "luna"), ("free", 2, "sol"),
    ("expansion", 5, "sol"), ("composition", 5, "sol"), ("free", 5, "sol"),
])
def test_actual_api_reserves_output_contract_once_without_changing_configuration_or_old_answers(routed, kind, count, tier):
    value = select_source(routed, kind, count)
    with DB() as db:
        configuration = copy.deepcopy(db.get(ProviderConfig, 1).routing_policy)
        old_answers = list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome)))
    first = post(routed, value)
    second = post(routed, value)
    assert first.status_code == second.status_code == 202 and first.json() == second.json()
    with DB() as db:
        job = db.get(Job, first.json()["id"])
        usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
        before, statements = counts(db), []

        def observed(_connection, _cursor, statement, _parameters, _context, _executemany):
            statements.append(statement.lstrip().split()[0].upper())

        event.listen(engine, "before_cursor_execute", observed)
        try:
            facts = features_for(db, routed.child["id"], job.id)
        finally:
            event.remove(engine, "before_cursor_execute", observed)
        assert statements and set(statements) == {"SELECT"}
        assert not db.new and not db.dirty and counts(db) == before
        assert facts["notebook_extended_output"] == (tier == "sol")
        assert choose_tier("unit", facts, economy=True) == (tier, "notebook_graphic_teaching" if tier == "sol" else "focused_source_practice")
        route = job_config(db, job, "unit")
        assert usage.route_snapshot["tier"] == tier
        assert usage.reserved_micros == route.reserve_micros == (150000 if tier == "luna" else 250000)
        assert route.max_output_tokens == (4000 if tier == "luna" else 8000) and route.reasoning_effort == "medium"
        assert db.get(ProviderConfig, 1).routing_policy == configuration
        assert list(db.execute(select(Attempt.id, Attempt.answer, Attempt.outcome))) == old_answers
        assert db.get(LearningUnit, routed.old_id).status == "completed"
        assert before[:2] == [1, 1]


@pytest.mark.parametrize("entry,count", [(True, 2), (False, 2), (True, 5)])
def test_real_worker_adapter_uses_actual_fixed_schema_binder_on_reserved_route(routed, monkeypatch, entry, count):
    value = select_source(routed, count=count)
    if entry:
        routed.client.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
    response = post(routed, value)
    assert response.status_code == 202, response.text
    job_id, calls, seen = response.json()["id"], [], []
    actual = providers.request_provider

    def request(config, function, payload, *args, **kwargs):
        assert function == "unit"
        planned, binding, wire = binding_and_wire(payload)
        seen.append((config.model, config.max_output_tokens, config.reserve_micros, planned, binding))
        http_mock(monkeypatch, wire, calls)
        return actual(config, function, payload, *args, **kwargs)

    monkeypatch.setattr(worker, "request_provider", request)
    with DB() as db:
        assert worker.claim(db) == job_id
    worker.process(job_id)
    assert len(calls) == len(seen) == 1
    cap = 4000 if count == 2 else 8000
    assert seen[0][1:3] == (cap, 150000 if count == 2 else 250000)
    assert calls[0]["max_tokens"] == cap and calls[0]["reasoning"]["effort"] == "medium"
    assert "notebook-fraction-expansion-1" in calls[0]["messages"][0]["content"]
    outgoing = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert outgoing["prepared_graphics"]["revision"] == "notebook-fraction-expansion-1"
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == count
    assert all(candidate["id"] in json.dumps(schema) for candidate in seen[0][4].candidates)
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "completed", job.error
        unit = db.get(LearningUnit, job.result["unit_id"])
        assert len(unit.questions) == count and db.get(UnitVisualSnapshot, unit.id).status == "ready"
        assert db.scalar(select(Usage).where(Usage.job_id == job_id)).cost_micros == 1000
        assert db.get(LearningUnit, routed.old_id).status == "completed"
    worker.process(job_id)
    assert len(calls) == 1


def test_free_graphic_actual_native_schema_dispatch_keeps_approved_sol_limits(routed, monkeypatch):
    value = select_source(routed, "free")
    routed.client.headers["X-Schulpilot-Capabilities"] = "learning-entry-v1"
    response = post(routed, value)
    assert response.status_code == 202
    job_id, calls = response.json()["id"], []
    real = httpx.Client

    class CaptureComplete(BaseException):
        pass

    def handler(request):
        calls.append(json.loads(request.content))
        raise CaptureComplete

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    with DB() as db:
        assert worker.claim(db) == job_id
    with pytest.raises(CaptureComplete):
        worker.process(job_id)
    assert len(calls) == 1
    assert calls[0]["max_tokens"] == 8000 and calls[0]["reasoning"]["effort"] == "medium"
    outgoing = json.loads(calls[0]["messages"][1]["content"][0]["text"])
    assert outgoing["notebook_practice"]["question_count"] == 2 and outgoing["visual_context"]["required"] is True
    assert "prepared_graphics" not in outgoing
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    assert schema["properties"]["questions"]["minItems"] == schema["properties"]["questions"]["maxItems"] == 2
    assert "Graphic" in schema["$defs"]
    with DB() as db:
        assert db.scalar(select(Usage).where(Usage.job_id == job_id)).route_snapshot["reason"] == "notebook_graphic_teaching"


@pytest.mark.parametrize("damage", ["revision", "unconfirmed", "same_revision_content", "foreign_owner", "signature", "anchor_revision"])
def test_source_selection_cannot_claim_a_current_output_profile_after_change(routed, damage):
    value = select_source(routed, "free")
    result = post(routed, value)
    assert result.status_code == 202
    sibling = create_child(routed.parent_api, routed.parent, "output-profile-sibling") if damage == "foreign_owner" else None
    with DB.begin() as db:
        page, job = db.get(Material, routed.refs[0]["id"]), db.get(Job, result.json()["id"])
        if damage == "revision":
            page.revision += 1
        elif damage == "unconfirmed":
            page.confirmed = False
        elif damage == "same_revision_content":
            page.content += " Neuer künstlicher Hefteintrag."
        elif damage == "foreign_owner":
            page.child_id = sibling["id"]
        elif damage == "signature":
            meta = {**job.payload["notebook_practice"], "source_signature": "f" * 64}
            job.payload = {**job.payload, "notebook_practice": meta}
        else:
            job.payload = {**job.payload, "material_revision": True}
            flag_modified(job, "payload")  # Python True == 1 must not suppress this intentionally corrupt fixture.
    with DB() as db:
        if damage == "anchor_revision":
            assert type(db.get(Job, result.json()["id"]).payload["material_revision"]) is bool
        before = counts(db)
        assert extended_output(db, routed.child["id"], db.get(Job, result.json()["id"])) is False
        assert not db.new and not db.dirty and counts(db) == before
        # The already reserved route never changes after its source is stale.
        assert job_config(db, db.get(Job, result.json()["id"]), "unit").max_output_tokens == 8000


@pytest.mark.parametrize("proof,damage", [("expansion", "missing"), ("expansion", "digest"), ("composition", "missing"), ("composition", "digest")])
def test_missing_or_unverified_immutable_recipe_never_claims_a_bounded_template(routed, proof, damage):
    value = select_source(routed, proof)
    recipe = "math.fraction.expansion" if proof == "expansion" else "math.fraction.wholes_remainder"
    with DB.begin() as db:
        for row in db.scalars(select(VisualReference).where(VisualReference.id == recipe)):
            if damage == "missing":
                db.delete(row)
            else:
                row.digest = "0" * 64
    result = post(routed, value)
    assert result.status_code == 202, result.text
    with DB() as db:
        job = db.get(Job, result.json()["id"])
        assert features_for(db, routed.child["id"], job.id)["notebook_extended_output"] is True
        assert db.scalar(select(Usage).where(Usage.job_id == job.id)).route_snapshot["tier"] == "sol"


def test_expansion_rule_without_a_literal_prepared_intro_is_not_mislabelled_bounded(routed):
    value = select_source(routed)
    with DB.begin() as db:
        db.get(Material, routed.refs[0]["id"]).content = "Beim Erweitern multiplizierst du Zähler und Nenner mit derselben Zahl."
    result = post(routed, value)
    assert result.status_code == 202, result.text
    with DB() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == result.json()["id"]))
        assert usage.route_snapshot["tier"] == "sol" and usage.route_snapshot["reason"] == "notebook_graphic_teaching"
