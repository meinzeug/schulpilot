"""Artificial full unit requests at recorded price bounds; no external calls."""
import copy
import json

import httpx
import pytest
from schulpilot import learning_entry, provider_cost_preflight, providers, visual_references
from schulpilot.db import DB, Child, Material
from test_model_routing import policy
from test_presentation_capability_paths import _config, _submitted


@pytest.mark.parametrize("reason", ["material_graphic_teaching", "notebook_graphic_teaching"])
@pytest.mark.parametrize("subject,entry,padding,allowed", [("Deutsch", False, 0, True),
    ("Deutsch", True, 40000, True), ("Mathematik", True, 30000, True),
    ("Mathematik", True, 40000, False), ("Deutsch", True, 200000, False)])
def test_unit_transport_preserves_schema_and_existing_cost_boundary(monkeypatch, household, subject, entry, padding, allowed, reason):
    content = ("Der Vogel singt - Die Vögel singen. Artikel und Nomen gehören zusammen."
        if subject == "Deutsch" else "Vielfache von 6 sind 6, 12, 18 und 24. Multipliziere 6 mit einer natürlichen Zahl.")
    requested = {"grade": 6, "material": {"subject": subject, "topic": "Künstlicher Vergleich", "content": content}}
    with DB.begin() as db:
        child = db.get(Child, household[1]["id"])
        material = Material(child_id=child.id, title="PUBLIC SYNTHETIC", subject=subject,
            topic="Künstlicher Vergleich", content=content, confirmed=True, status="confirmed")
        db.add(material)
        db.flush()
        requested = visual_references.with_visual_context(db, child, requested, [material])
        if entry:
            requested = learning_entry.with_learning_entry(db, child, requested, [material], enabled=True)
    # Artificial byte load represents a longer request context; no private
    # history, photographed source or fake learning evidence is used.
    if padding:
        requested["synthetic_transport_sizing"] = "x" * padding
    original = copy.deepcopy(requested)
    config = _config("openrouter")
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    approved = policy()
    config._selected_route = {"reason": reason, "tier": "sol", "budget": approved["budget"],
        "route": {**approved["routes"]["sol"], "upstreams": ["fixture-upstream"],
            "max_output_tokens": 8000, "reserve_micros": 250000,
            "input_per_million_micros": 2000000, "output_per_million_micros": 10000000}}
    before = (config.max_output_tokens, config.reserve_micros, config.input_per_million_micros, config.output_per_million_micros)
    captures, projections = [], []
    project = provider_cost_preflight.projection

    def observed(*args, **kwargs):
        result = project(*args, **kwargs)
        projections.append(result)
        return result

    class Captured(BaseException):
        pass

    def handler(request):
        captures.append(json.loads(request.content))
        raise Captured

    real_client = httpx.Client
    monkeypatch.setattr(provider_cost_preflight, "projection", observed)
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    if not allowed:
        with pytest.raises(providers.ProviderError) as caught:
            providers.request_provider(config, "unit", requested)
        assert caught.value.code == "cost_preflight" and not captures
        assert len(projections) == 1 and projections[0]["projected_micros"] > 250000
        assert caught.value.billing_result.cost_micros == 0
        assert caught.value.billing_result.cost_source == "cancelled"
        assert requested == original
        assert (config.max_output_tokens, config.reserve_micros, config.input_per_million_micros, config.output_per_million_micros) == before
        return
    with pytest.raises(Captured):
        providers.request_provider(config, "unit", requested)
    assert len(captures) == len(projections) == 1
    sent, schema, instructions = _submitted("openrouter", captures[0])
    compact = json.dumps(schema, ensure_ascii=False, separators=(",", ":"))
    assert json.loads(compact) == schema
    expected_bytes = len((instructions + json.dumps(sent, ensure_ascii=False, separators=(",", ":")) + compact).encode())
    assert projections[0]["text_bytes"] == expected_bytes
    assert projections[0]["projected_micros"] <= projections[0]["reserved_micros"] == 250000
    assert captures[0]["max_tokens"] == 8000 and captures[0]["reasoning"]["effort"] == "medium"
    from test_graphic_native_transport import subset_record

    subset_record(schema)
    assert requested == original
    assert (config.max_output_tokens, config.reserve_micros, config.input_per_million_micros, config.output_per_million_micros) == before
