"""Artificial full-byte sources and real adapter serialization; no paid calls."""

import copy
import hashlib
import json
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import competences, learning_entry, package_transport, providers, source_lineage, visual_references
from schulpilot.config import settings
from schulpilot.db import ProviderConfig
from schulpilot.provider_cost_preflight import projection
from schulpilot.provider_receipts import request_receipt
from schulpilot.schemas import PackageOutput, Preferences


class Captured(Exception):
    pass


def artificial(
    monkeypatch, subjects=("Mathematik", "Deutsch", "Physik"), *, blocks=8, entry=True, chars=11641, catalog=True
):
    rows = json.loads(visual_references.BUNDLE.read_text())["references"]
    recipes = [
        SimpleNamespace(id=r["id"], version=r["version"], digest=visual_references.digest(r), recipe=r) for r in rows
    ]

    class VisualDb:
        def get(self, model, key):
            # This synthetic child has no explicit curriculum profile.
            from schulpilot.curriculum_models import ChildCurriculumProfile

            assert model is ChildCurriculumProfile and key == "c" * 32
            return None

        def scalar(self, statement):
            return None

        def scalars(self, statement):
            return recipes

    class EntryDb:
        def scalars(self, statement):
            return []

    def safe(db, material, revision=None):
        return {
            "content": material.content,
            "source_refs": [
                {"material_id": material.id, "revision": 1, "block_id": f"{n + 1:032x}"} for n in range(blocks)
            ],
            "factual_status": "not_assessed",
        }

    monkeypatch.setattr(source_lineage, "learning_source", safe)
    monkeypatch.setattr(competences, "matches", lambda *a: [])
    monkeypatch.setattr(learning_entry, "_proof", lambda *a: [])
    groups = [
        {
            "id": f"g{i + 1}",
            "subject": subject,
            "estimated_minutes": 12,
            "instructional_support": "practice_and_retrieval",
        }
        for i, subject in enumerate(subjects)
    ]
    materials = []
    for i in range(23):
        group = groups[i % len(groups)]
        length = chars // 23 + (i < chars % 23)
        text = (
            "Kuenstlicher Stoff: Bruch Zaehler Nenner Satz Subjekt Spiegel Winkel Stromkreis. "
            + "Ein eigener Beispielsatz beschreibt einen Zusammenhang. " * 2000
        )[:length]
        materials.append(
            SimpleNamespace(
                id=f"{i + 1:032x}",
                child_id="c" * 32,
                purpose="notebook",
                confirmed=True,
                revision=1,
                subject=group["subject"],
                topic=f"Eigenes Thema {i + 1}",
                content=text,
            )
        )
    for group in groups:
        group["material_ids"] = [m.id for m in materials if m.subject == group["subject"]]
    payload = {
        "function": "package",
        "grade": 7,
        "material": None,
        "goal": None,
        "preferences": Preferences().model_dump(mode="json"),
        "feedback": [],
        "recent_units": [],
        "recent_outcomes": [],
        "review": False,
        "instructional_support": "practice_and_retrieval",
        "materials": [],
        "selected_groups": [{k: v for k, v in g.items() if k != "material_ids"} for g in groups],
    }
    payload = visual_references.with_visual_context(
        VisualDb(), SimpleNamespace(id="c" * 32), payload, materials, groups=groups
    )
    if entry:
        payload = learning_entry.with_learning_entry(
            EntryDb(), SimpleNamespace(id="c" * 32), payload, materials, groups=groups, enabled=True
        )
    if catalog:
        seed = json.loads(
            Path(visual_references.__file__).with_name("reference").joinpath("subjects-v1.json").read_text()
        )["subjects"]
        subjects_meta = [{"id": hashlib.sha256(s["key"].encode()).hexdigest()[:32], "title": s["title"]} for s in seed]
        payload["catalog_context"] = {
            "snapshot_id": "artificial-catalog",
            "subjects": subjects_meta,
            "subject_aliases": {
                label.casefold(): subject["id"]
                for raw, subject in zip(seed, subjects_meta, strict=True)
                for label in [subject["title"], *raw["aliases"]]
            },
            "source_subject_labels": list(subjects),
            "candidates": [
                {
                    "id": f"{i + 100:032x}",
                    "subject_id": subjects_meta[i % len(subjects_meta)]["id"],
                    "title": ("Eigenes kuenstliches Thema " + str(i) + " ") * 2,
                    "context_ref": groups[i % len(groups)]["id"],
                }
                for i in range(12)
            ],
            "context_refs": [g["id"] for g in groups],
        }
    return payload


def config(provider="openrouter"):
    return ProviderConfig(
        provider=provider,
        model="openai/gpt-6.1-sol",
        max_output_tokens=4000,
        # Serializer fixture includes all 23 sources and every supported
        # entry/graphic branch. Keep its explicit reservation separate from
        # production route settings and the bounded partition tests.
        reserve_micros=250000,
        input_per_million_micros=2000000,
        output_per_million_micros=10000000,
        capability_evidence="synthetic upstream=azure",
        encrypted_key="not-a-real-key",
        routing_policy={},
    )


def wire(monkeypatch, payload, provider="openrouter"):
    saved = {}
    output = PackageOutputCapture(monkeypatch)
    real_client = httpx.Client

    def handler(request):
        saved["raw"] = request.content
        saved["body"] = json.loads(request.content)
        raise Captured()

    def client(**kwargs):
        return real_client(transport=httpx.MockTransport(handler), follow_redirects=False)

    original = package_transport.schema_projection

    def schema(value):
        saved["canonical_schema"] = copy.deepcopy(value)
        return original(value)

    monkeypatch.setattr(package_transport, "schema_projection", schema)
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr(providers.httpx, "Client", client)
    monkeypatch.setattr(
        "schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"}
    )
    monkeypatch.setattr(providers, "settings", replace(settings, codex_auth_mode="api_key"))
    with pytest.raises(Captured):
        providers.request_provider(config(provider), "package", payload)
    body = saved["body"]
    if provider == "openrouter":
        saved.update(
            schema=body["response_format"]["json_schema"]["schema"],
            instructions=body["messages"][0]["content"],
            payload=json.loads(body["messages"][1]["content"][0]["text"]),
        )
    elif provider == "openai":
        saved.update(
            schema=body["text"]["format"]["schema"],
            instructions=body["instructions"],
            payload=json.loads(body["input"][0]["content"][0]["text"]),
        )
    else:
        saved.update(schema=body["schema"], instructions=body["system"], payload=body["payload"])
    saved["output_binding"] = output.binding
    return saved


def expanded(value, definitions):
    """Compare ALL reachable validation constraints, ignoring only annotations.

    A single-field enum union distributes over anyOf. No JSON Schema constraint
    is ignored, and no JSON Schema interpreter/new dependency is introduced.
    """
    if isinstance(value, list):
        return [expanded(item, definitions) for item in value]
    if not isinstance(value, dict):
        return value
    if "$ref" in value:
        assert set(value) == {"$ref"}
        return expanded(definitions[value["$ref"].split("/")[-1]], definitions)
    result = {k: expanded(v, definitions) for k, v in value.items() if k not in ("$defs", "description")}
    for name in ("enum", "required"):
        if name in result:
            result[name] = sorted(result[name], key=repr)
    if "anyOf" in result:
        branches = []
        for branch in result["anyOf"]:
            ids = branch.get("properties", {}).get("id", {}).get("enum", [])
            if len(ids) > 1:
                for identifier in ids:
                    one = copy.deepcopy(branch)
                    one["properties"]["id"]["enum"] = [identifier]
                    branches.append(one)
            else:
                branches.append(branch)
        distinct = {json.dumps(item, sort_keys=True, separators=(",", ":")): item for item in branches}
        result["anyOf"] = [distinct[k] for k in sorted(distinct)]
    return result


@pytest.mark.parametrize("provider", ["openrouter", "openai", "codex"])
@pytest.mark.parametrize("blocks", [1, 8])
@pytest.mark.parametrize("entry", [False, True])
def test_real_adapters_keep_all_twenty_three_sources_and_identical_schema_contract(
    monkeypatch, provider, blocks, entry
):
    payload = artificial(monkeypatch, blocks=blocks, entry=entry)
    before = copy.deepcopy(payload)
    saved = wire(monkeypatch, payload, provider)
    assert payload == before
    assert sum(len(m["content"]) for m in payload["materials"]) == 11641
    assert saved["payload"]["materials"] == payload["materials"]
    for source, compact in zip(
        payload["visual_context"]["sources"], saved["payload"]["visual_context"]["sources"], strict=True
    ):
        index = compact["content_ref"]
        material = saved["payload"]["materials"][index]
        assert material["content"].encode() == source["content"].encode()
        assert all(material[k] == source[k] for k in ("subject", "topic", "group_id"))
        assert compact["ref"] == source["ref"]
    original = saved["canonical_schema"]
    assert expanded(original, original["$defs"]) == expanded(saved["output_binding"].canonical_schema, saved["output_binding"].canonical_schema["$defs"])
    assert b'"schema":' + package_transport.json_text(saved["schema"]).encode() in saved["raw"]
    if provider == "openrouter":
        assert saved["body"]["provider"]["only"] == ["azure"]
        assert saved["body"]["provider"]["allow_fallbacks"] is False
        assert saved["body"]["max_tokens"] == 4000
    receipt = request_receipt(provider, saved["body"], saved["schema"])
    assert (
        receipt["schema_sha256"]
        == hashlib.sha256(
            json.dumps(saved["schema"], ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
    )


@pytest.mark.parametrize("subjects", [("Deutsch",), ("Deutsch", "Physik"), ("Mathematik", "Deutsch", "Physik")])
@pytest.mark.parametrize("blocks", [1, 8])
def test_multisubject_11641_character_packages_fit_without_a_changed_reservation(monkeypatch, subjects, blocks):
    payload = artificial(monkeypatch, subjects, blocks=blocks)
    saved = wire(monkeypatch, payload)
    length = sum(
        len(value.encode())
        for value in (
            saved["instructions"],
            package_transport.json_text(saved["payload"]),
            package_transport.json_text(saved["schema"]),
        )
    )
    preflight = projection(config(), "package", length, None, 0)
    assert preflight["projected_micros"] <= 250000
    assert preflight["reserved_micros"] == 250000


def test_large_sources_still_fail_before_dispatch_without_a_fallback_or_retry(monkeypatch):
    payload = artificial(monkeypatch, chars=100000)
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: pytest.fail("No HTTP may be constructed."))
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(config(), "package", payload)
    assert error.value.code == "cost_preflight"
    result = error.value.billing_result
    assert result.cost_micros == result.input_tokens == result.output_tokens == 0
    assert result.telemetry["cost_preflight"]["transport_revision"] == package_transport.REVISION
    assert result.telemetry["pre_dispatch"] is True


@pytest.mark.parametrize("changed", ["content", "subject", "group_id", "topic"])
def test_untrusted_pointer_or_cross_group_text_is_not_referenced(monkeypatch, changed):
    payload = artificial(monkeypatch)
    source = payload["visual_context"]["sources"][0]
    source["content_ref"] = "materials[22].content"
    source[changed] += " "
    result = package_transport.payload_projection(payload)["visual_context"]["sources"][0]
    assert result["content"] == source["content"]
    assert "content_ref" not in result


def test_unicode_whitespace_and_curated_reference_identity_remain_literal(monkeypatch):
    payload = artificial(monkeypatch)
    text = 'CO ≠ Co; „Öl“ e\u0301 é 🦋\\n{"a":"b"}  '
    payload["materials"][0]["content"] = payload["visual_context"]["sources"][0]["content"] = text
    payload["visual_context"]["sources"].append(
        {
            "ref": "r1",
            "source_type": "curated_foundation",
            "subject": "Mathematik",
            "group_id": "g1",
            "content": "Eigene Zusatzregel: vollständig.",
        }
    )
    saved = wire(monkeypatch, payload)
    assert saved["payload"]["materials"][0]["content"].encode() == text.encode()
    assert saved["payload"]["visual_context"]["sources"][-1]["content"] == "Eigene Zusatzregel: vollständig."
    assert saved["payload"]["visual_context"]["sources"][-1]["source_type"] == "curated_foundation"
    assert "material_id" not in saved["payload"]["visual_context"]["sources"][-1]


def test_unknown_annotations_and_all_validation_keywords_survive():
    schema = {
        "type": "object",
        "properties": {"description": {"type": "string", "description": "New policy must survive."}},
        "required": ["description"],
        "additionalProperties": False,
    }
    result = package_transport.schema_projection(schema)
    assert result["properties"]["description"]["description"] == "New policy must survive."
    assert expanded(schema, {}) == expanded(result, result["$defs"])


def test_fixed_prerequisite_prompt_answer_pairs_cannot_cross_bind(monkeypatch):
    payload = artificial(monkeypatch, ("Mathematik",), catalog=False)
    payload["learning_entry"]["units"][0].update(
        entry_mode="prerequisite_probe",
        allocation_version=1,  # Replay the legacy all-probe contract; new plans reserve application.
        probes=[
            {
                "id": "prior_a",
                "role": "prior_check",
                "type": "short",
                "prompt": "Beim Bruch 3/4: Wie heißt der Nenner?",
                "answer": "4",
                "options": [],
                "accepted": [],
            },
            {
                "id": "prior_b",
                "role": "prior_check",
                "type": "short",
                "prompt": "Beim Bruch 2/5: Wie heißt der Nenner?",
                "answer": "5",
                "options": [],
                "accepted": [],
            },
        ],
    )
    saved = wire(monkeypatch, payload)
    original = saved["canonical_schema"]
    assert expanded(original, original["$defs"]) == expanded(saved["output_binding"].canonical_schema, saved["output_binding"].canonical_schema["$defs"])
    data = {
        "units": [
            {
                "subject": "Mathematik",
                "group_id": "g1",
                "questions": [
                    {k: p[k] for k in learning_entry.CORE} for p in payload["learning_entry"]["units"][0]["probes"]
                ],
            }
        ]
    }
    # Entry checks the fixed cores; the package/schema guard separately keeps
    # the requested total. Do not invent a stronger contract for this helper.
    learning_entry.validate_entry_output(payload, data)
    questions = original["properties"]["units"]["items"]["anyOf"][0]["properties"]["questions"]
    assert questions["minItems"] == questions["maxItems"] == 5
    data["units"][0]["questions"][0]["answer"] = "5"
    with pytest.raises(ValueError):
        learning_entry.validate_entry_output(payload, data)


@pytest.mark.parametrize("provider", ["openrouter", "openai", "codex"])
@pytest.mark.parametrize("invalid", [False, True])
def test_full_response_validation_still_checks_group_local_literal_answers(monkeypatch, provider, invalid):
    payload = {
        "materials": [
            {"group_id": "g1", "subject": "Englisch", "topic": "Eigene Wörter", "content": "cat = Katze\ndog = Hund"}
        ],
        "selected_groups": [{"id": "g1", "subject": "Englisch", "estimated_minutes": 5}],
    }
    questions = [
        {
            "id": f"q{i}",
            "type": "short",
            "prompt": prompt,
            "answer": answer,
            "options": [],
            "accepted": [],
            "hints": ["Lies das Wortpaar."],
            "explanation": "Das Wortpaar steht auf der künstlichen Seite.",
        }
        for i, (prompt, answer) in enumerate(
            (("Was bedeutet cat?", "Katze"), ("Was bedeutet dog?", "Banane" if invalid else "Hund")), 1
        )
    ]
    data = PackageOutput.model_validate(
        {
            "units": [
                {
                    "group_id": "g1",
                    "subject": "Englisch",
                    "topic": "Eigene Wörter",
                    "explanation": "Dies sind künstliche bestätigte Wortpaare.",
                    "questions": questions,
                }
            ]
        }
    ).model_dump(mode="json")
    if invalid and provider == "openai":
        # The existing OpenAI package path has structural validation; literal
        # factual-package binding is specific to the compact OR/Codex contract.
        data["units"][0]["questions"][1]["id"] = "q1"
    real_client = httpx.Client
    calls = []
    output = PackageOutputCapture(monkeypatch)

    def handler(request):
        calls.append(request)
        if provider == "openrouter":
            raw = {
                "choices": [{"message": {"content": json.dumps(output.wire(data))}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "cost": 0},
            }
        elif provider == "openai":
            raw = {
                "status": "completed",
                "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(output.wire(data))}]}],
                "usage": {"input_tokens": 10, "output_tokens": 10},
            }
        else:
            raw = {"data": output.wire(data), "input_tokens": 10, "output_tokens": 10, "cost_micros": 0, "search_calls": 0}
        return httpx.Response(200, json=raw)

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr(
        "schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"}
    )
    monkeypatch.setattr(providers, "settings", replace(settings, codex_auth_mode="api_key"))
    if invalid:
        with pytest.raises(providers.ProviderError):
            providers.request_provider(config(provider), "package", payload)
    else:
        result = providers.request_provider(config(provider), "package", payload)
        assert result.data["units"][0]["questions"][1]["answer"] == "Hund"
    assert len(calls) == 1


@pytest.mark.parametrize("provider", ["openrouter", "openai", "codex"])
@pytest.mark.parametrize("invalid_response", [False, True])
def test_package_choice_instructions_and_real_response_match_provider_wire_format(
    monkeypatch, provider, invalid_response
):
    payload = {
        "materials": [
            {"group_id": "g1", "subject": "Englisch", "topic": "Eigene Wörter", "content": "cat = Katze\ndog = Hund"}
        ],
        "selected_groups": [{"id": "g1", "subject": "Englisch", "estimated_minutes": 5}],
    }
    questions = [
        {
            "id": f"q{i}", "type": "choice", "prompt": prompt,
            "answer": answer, "options": ["Katze", "Hund"], "accepted": [],
            "hints": ["Lies das Wortpaar."],
            "explanation": "Das Wortpaar steht auf der künstlichen Seite.",
        }
        for i, (prompt, answer) in enumerate((("Was bedeutet cat?", "Katze"), ("Was bedeutet dog?", "Hund")), 1)
    ]
    data = PackageOutput.model_validate({"units": [{
        "group_id": "g1", "subject": "Englisch", "topic": "Eigene Wörter",
        "explanation": "Dies sind künstliche bestätigte Wortpaare.", "questions": questions,
    }]}).model_dump(mode="json")
    indexed = provider in ("openrouter", "codex")
    if indexed or invalid_response:
        for index, question in enumerate(data["units"][0]["questions"]):
            question["answer"] = 99 if invalid_response else index
    calls = []
    real_client = httpx.Client
    output = PackageOutputCapture(monkeypatch)

    def handler(request):
        body = json.loads(request.content)
        if provider == "openrouter":
            instructions = body["messages"][0]["content"]
            schema = body["response_format"]["json_schema"]["schema"]
            response = {
                "choices": [{"message": {"content": json.dumps(output.wire(data))}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 10, "cost": 0},
            }
        elif provider == "openai":
            instructions = body["instructions"]
            schema = body["text"]["format"]["schema"]
            response = {
                "status": "completed",
                "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(output.wire(data))}]}],
                "usage": {"input_tokens": 10, "output_tokens": 10},
            }
        else:
            instructions, schema = body["system"], body["schema"]
            response = {"data": output.wire(data), "input_tokens": 10, "output_tokens": 10, "cost_micros": 0, "search_calls": 0}
        schema = output.schema(schema)
        actual = expanded(schema, schema["$defs"])

        def answer_types(node):
            if isinstance(node, dict):
                props = node.get("properties", {})
                if {"prompt", "answer", "options", "type"} <= props.keys() and "choice" in props["type"].get("enum", []):
                    yield props["answer"]["type"]
                for child in node.values():
                    yield from answer_types(child)
            elif isinstance(node, list):
                for child in node:
                    yield from answer_types(child)

        assert set(answer_types(actual)) == {"integer" if indexed else "string"}
        assert ("choice.answer: NULLBASIERTER INTEGERINDEX" in instructions) is indexed
        assert ("choice.answer: exakt der VOLLSTÄNDIGE ANTWORTTEXT" in instructions) is not indexed
        calls.append(body)
        return httpx.Response(200, json=response)

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr(
        "schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"}
    )
    monkeypatch.setattr(providers, "settings", replace(settings, codex_auth_mode="api_key"))
    if invalid_response:
        with pytest.raises(providers.ProviderError):
            providers.request_provider(config(provider), "package", payload)
    else:
        result = providers.request_provider(config(provider), "package", payload)
        assert [q["answer"] for q in result.data["units"][0]["questions"]] == ["Katze", "Hund"]
    assert len(calls) == 1


def table_records(container, name):
    if name in container:
        return container[name]
    table = container[name + "_table"]
    return [dict(zip(table["columns"], row, strict=True)) for row in table["rows"]]


def test_entry_evidence_table_keeps_every_zero_null_id_and_distinct_group():
    records = [
        {"id": f"math.fractions.test{i}", "status": "unknown", "confidence": "unverified", "tasks": 0,
         "independent": 0, "supported": 0, "needs_practice": 0, "uncertain": 0, "evidence_total": 0,
         "evidence_refs": [], "last_independent_success": None, "last_difficulty": None}
        for i in range(6)
    ]
    payload = {"learning_entry": {"units": [
        {"group_id": "g1", "subject": "Mathematik", "evidence": records},
        {"group_id": "g2", "subject": "Deutsch", "evidence": [{**row, "id": "german." + row["id"]} for row in records]},
    ]}}
    before = copy.deepcopy(payload)
    wire_data = package_transport.payload_projection(payload)
    assert payload == before
    for original, wire_unit in zip(payload["learning_entry"]["units"], wire_data["learning_entry"]["units"], strict=True):
        assert wire_unit["group_id"] == original["group_id"]
        assert "evidence_table" in wire_unit and "evidence" not in wire_unit
        assert table_records(wire_unit, "evidence") == original["evidence"]
    assert len(package_transport.json_text(wire_data)) < len(package_transport.json_text(payload))


@pytest.mark.parametrize("records", [[{"id": "x"}], [{"id": "x"}, {"id": "y", "extra": None}], [{"id": "x"}, None]])
def test_unknown_or_small_entry_records_are_not_reinterpreted_as_tables(records):
    payload = {"learning_entry": {"units": [{"evidence": records, "evidence_table": {"rows": [["forged"]]}}]}}
    result = package_transport.payload_projection(payload)
    assert result["learning_entry"]["units"][0]["evidence"] == records
    assert "evidence_table" not in result["learning_entry"]["units"][0]


@pytest.mark.parametrize("changed", [None, "material_id", "revision", "subject", "group_id", "quote"])
def test_entry_quote_pointer_is_exact_unicode_and_bound_to_original_material(changed):
    excerpt = "😀 e\u0301\tLernen\n  eigene Werte  " * 7
    content = "Vorlauf 😀\n" + excerpt + "\nNachlauf"
    material = {"subject": "Deutsch", "topic": "Eigene Begriffe", "group_id": "g1", "content": content}
    source = {**material, "ref": "p1", "material_id": "a" * 32, "revision": 3}
    target = {"id": "german.test", "source_ref": {"material_id": "a" * 32, "revision": 3},
              "source_excerpt": excerpt, "source_excerpt_ref": {"content_ref": 999, "start": 0, "end": 9}}
    if changed in ("material_id", "revision"):
        target["source_ref"][changed] = "b" * 32 if changed == "material_id" else 4
    elif changed in ("subject", "group_id"):
        source[changed] = "fremd"
    elif changed == "quote":
        target["source_excerpt"] = excerpt + "NEU"
    payload = {"materials": [material], "visual_context": {"sources": [source]},
               "learning_entry": {"units": [{"subject": "Deutsch", "group_id": "g1", "targets": [target]}]}}
    before = copy.deepcopy(payload)
    result = package_transport.payload_projection(payload)
    assert payload == before and result["materials"] == [material]
    actual = result["learning_entry"]["units"][0]["targets"][0]
    if changed is not None:
        assert "source_excerpt_ref" not in actual
        assert actual["source_excerpt"] == target["source_excerpt"]
    else:
        pointer = actual["source_excerpt_ref"]
        full = result["materials"][pointer["content_ref"]]["content"]
        assert full[pointer["start"]:pointer["end"]] == excerpt
        assert "source_excerpt" not in actual and "source_ref" not in actual
        assert result["visual_context"]["sources"][0]["content_ref"] == pointer["content_ref"]


@pytest.mark.parametrize("changed", [None, "reference_id", "version", "digest", "source_type", "prefix"])
def test_curated_reference_slice_never_becomes_a_photo_or_other_recipe(changed):
    content = "Eigene kuratierte Zusatzregel e\u0301 😀. " * 6
    reference = {"reference_id": "math.fractions.meaning", "version": "competencies-1", "digest": "d" * 64,
                 "content": content, "competence_id": "math.fractions.meaning"}
    source = {**reference, "ref": "r1", "source_type": "curated_foundation", "content": content + "\nEigenes Beispiel"}
    if changed in ("reference_id", "version", "digest", "source_type"):
        source[changed] = "other"
    elif changed == "prefix":
        source["content"] = "Nicht dieselbe Regel\n" + source["content"]
    payload = {"visual_context": {"sources": [source]}, "learning_entry": {"references": [reference]}}
    before = copy.deepcopy(payload)
    result = package_transport.payload_projection(payload)
    assert payload == before
    actual = result["learning_entry"]["references"][0]
    assert result["visual_context"]["sources"][0]["content"] == source["content"]
    assert result["visual_context"]["sources"][0]["source_type"] == source["source_type"]
    if changed is not None:
        assert actual["content"] == content and "content_slice" not in actual
    else:
        pointer = actual["content_slice"]
        assert pointer["ref"] == "r1"
        assert source["content"][pointer["start"]:pointer["end"]] == content
        assert actual["digest"] == reference["digest"]
        assert "content" not in actual


def test_small_identical_schema_nodes_are_shared_without_constraint_changes():
    field = {"type": "string", "minLength": 1, "maxLength": 80, "pattern": "^[a-z]+$"}
    assert len(package_transport.json_text(field)) < 90
    schema = {"type": "object", "properties": {f"f{i}": copy.deepcopy(field) for i in range(12)},
              "required": [f"f{i}" for i in range(12)], "additionalProperties": False}
    original = copy.deepcopy(schema)
    result = package_transport.schema_projection(schema)
    assert schema == original
    assert expanded(original, {}) == expanded(result, result["$defs"])
    assert len(package_transport.json_text(result)) < len(package_transport.json_text(schema))
    assert all(set(node) == {"$ref"} for node in result["properties"].values())
