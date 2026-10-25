"""Artificial wrapped rules activate the unchanged native proof contract."""

import copy
import json

import httpx
import pytest
from schulpilot import notebook_fraction_expansions as notebook
from schulpilot import providers, visual_references
from schulpilot.db import DB, Child, LearningUnit
from schulpilot.visual_reference_models import UnitVisualSnapshot
from test_notebook_fraction_expansions import prepared
from test_presentation_capability_paths import _config

RULE = "Zum Erweitern\nmultiplizieren wir Zähler und Nenner\nmit der selben Zahl."
CONTENT = RULE + " Unabhängige Beispiele: 3/8 und 4/9."


@pytest.mark.parametrize("count,entry", [(2, True), (5, False)])
def test_wrapped_rule_binds_fixed_cores_and_graphics_before_actual_http(household, monkeypatch, count, entry):
    import test_notebook_fraction_expansions as fixtures

    monkeypatch.setattr(fixtures, "CONTENT", CONTENT)
    page_id, payload, planned, _, wire = prepared(household, count, entry)
    assert notebook.eligible(payload) and notebook._supported(payload)
    assert any(ref["id"] == "math.fraction.expansion" for ref in payload["visual_context"]["references"])
    assert notebook.HISTORY_KEY in payload
    assert all(task["source_excerpt"] == RULE for task in planned[notebook.KEY]["tasks"])
    events, requests = [], []
    real_bind, real_client = notebook.bind_schema, httpx.Client

    def bind(schema, value):
        assert value[notebook.KEY] == planned[notebook.KEY]
        result = real_bind(schema, value)
        assert result is not None
        events.append("bound")
        return result

    def handler(request):
        assert events == ["bound"]
        events.append("http")
        requests.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(wire)}}], "usage": {"prompt_tokens": 100, "completion_tokens": 500, "cost": .001}})

    monkeypatch.setattr(notebook, "bind_schema", bind)
    monkeypatch.setattr(providers.httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(handler)))
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 4000, 150000  # Existing cap; fixture rates are artificial.
    result = providers.request_provider(config, "unit", payload)
    assert events == ["bound", "http"] and len(requests) == 1
    assert requests[0]["max_tokens"] == 4000
    outgoing = json.loads(requests[0]["messages"][1]["content"][0]["text"])
    assert notebook.HISTORY_KEY not in outgoing
    assert outgoing[notebook.KEY] == planned[notebook.KEY]
    assert notebook.REVISION in requests[0]["messages"][0]["content"]
    plan = planned[notebook.KEY]
    assert len(result.data["questions"]) == len(plan["probes"]) + len(plan["tasks"]) == count
    for core in [*plan["probes"], *plan["tasks"]]:
        actual = next(question for question in result.data["questions"] if question["id"] == core["id"])
        assert all(actual[key] == core[key] for key in notebook.CORE)
        step = actual["explanation_steps"][0]
        if core in plan["tasks"]:
            assert step["reference"]["id"] == "math.fraction.expansion"
            assert len(step["presentation"]["blocks"]) == 2
            assert all(block["source_excerpt"] == RULE for block in step["presentation"]["blocks"])
    with DB.begin() as db:
        visual_references.validate_output(db, result.data, payload)
        unit = LearningUnit(child_id=household[1]["id"], material_id=page_id, subject="Mathematik",
            topic=result.data["topic"], explanation=result.data["explanation"], questions=copy.deepcopy(result.data["questions"]),
            provider="synthetic", model="own-wording-fixture")
        db.add(unit)
        db.flush()
        visual_references.remember(db, unit, result.data, payload)
        db.flush()
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == "ready" and visual_references.projection(db, unit)["explanation_visual_status"] == "ready"
        assert db.get(Child, household[1]["id"]) is not None
