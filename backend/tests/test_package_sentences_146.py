"""Original sentence words through the real adapter, without inferred roles."""
import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_prepared_sentences as prepared
from schulpilot import providers, visual_references
from schulpilot.db import DB
from schulpilot.provider_validation import annotate
from test_package_prepared_graphics import bind, payload_for, wire_step
from test_package_transport import config


def fixture():
    value = payload_for("Satzglieder bestimmen\n\nDer Hund schläft.\n\nMia spielt heute Fußball.", "Deutsch")
    value["learning_entry"] = {"units": [{"group_id": "g1", "subject": "Deutsch", "prefix": "artificial",
        "entry_mode": "source_probe", "probes": []}]}
    return value


def output(value):
    _, binding = bind(value)
    intro = next(c for c in binding.candidates if c["disclosure"] == "given")
    questions = []
    for i, (sentence, answer, ask) in enumerate((("Der Hund schläft.", "schläft", "Welches Wort beschreibt die Tätigkeit?"),
            ("Mia spielt heute Fußball.", "Mia", "Wer spielt?"))):
        candidate = next(c for c in binding.candidates if c["disclosure"] == "solution" and c["block"]["source_excerpt"] == sentence)
        step = wire_step(candidate)
        step["text"] = "Lies den Satz. Frage nach der Tätigkeit oder danach, wer etwas tut. Die Kästen zeigen nur Originalwörter, keine fertige Satzgliedzuordnung."
        questions.append({"id": f"prior_artificial_{i+1}", "type": "short", "prompt": f'Lies „{sentence}“ {ask}',
            "answer": answer, "options": [], "accepted": [], "hints": ["Lies die Frage und den Originalsatz noch einmal."],
            "explanation": step["text"], "presentation": None, "explanation_steps": [step]})
    return {"units": [{"group_id": "g1", "subject": "Deutsch", "topic": "Satzglieder bestimmen",
        "explanation": intro["text"], "explanation_steps": [wire_step(intro)], "questions": questions}]}


def test_only_complete_original_words_are_compiled_without_grammatical_role_claims():
    value = fixture()
    schema, binding = bind(value)
    before = copy.deepcopy(value)
    assert binding and binding.context["revision"] == prepared.REVISION
    for candidate in binding.candidates:
        block = candidate["block"]
        assert block["source_excerpt"] in value["visual_context"]["sources"][0]["content"]
        assert block["marks"] == block["numbers"] == block["connections"] == []
        assert " ".join(block["labels"]) == block["source_excerpt"][:-1]
    hydrated = binding.hydrate(output(value))
    with DB() as db:
        visual_references.validate_output(db, hydrated, value)
    assert value == before and schema


@pytest.mark.parametrize("text", ["Mila | Wer liest?", "1. Subjekt bestimmen:", "Der Hund", "Der Hund schläft. Mia liest.",
    "https://example.org", "2 Hunde spielen.", "A -> B.", "Mila: Subjekt.", "Am Montag ist Schulschluss; dann geht Mia."])
def test_no_fragment_task_table_link_or_invented_grouping_is_compiled(text):
    assert list(prepared.sentence_bases(text)) == []


@pytest.mark.parametrize("change", ["quote", "word", "marks", "foreign_source", "prompt"])
def test_full_quote_source_and_question_remain_bound(change):
    value = fixture()
    _, binding = bind(value)
    wire = output(value)
    q = wire["units"][0]["questions"][0]
    if change == "prompt":
        q["prompt"] = "Welche Tätigkeit wird beschrieben?"
    elif change == "foreign_source":
        q["explanation_steps"][0]["source_refs"] = ["foreign"]
    else:
        c = next(c for c in binding.candidates if c["disclosure"] == "solution")
        block = copy.deepcopy(c["block"])
        if change == "quote":
            block["source_excerpt"] = "Ein anderer Satz."
        elif change == "word":
            block["labels"][0] = "Unbelegt"
        else:
            block["marks"] = [{"index": 0, "role": "subject"}]
        q["explanation_steps"][0]["presentation"]["blocks"] = [block]
    with pytest.raises(ValueError):
        binding.hydrate(wire)


def test_actual_adapter_keeps_original_questions_answers_and_canonical_visual_checks(monkeypatch):
    value = fixture()
    data = output(value)
    capture, client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []
    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        sent = json.loads(body["messages"][1]["content"][0]["text"])
        assert sent["prepared_graphics"]["revision"] == prepared.REVISION
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(capture.wire(data))}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 100, "cost": 0.002}})
    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "artificial-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    route = config()
    route.max_output_tokens, route.reserve_micros = 8000, 250000
    result = providers.request_provider(route, "package", value)
    assert len(calls) == 1 and result.cost_micros == 2000
    assert [q["answer"] for q in result.data["units"][0]["questions"]] == ["schläft", "Mia"]


def test_role_evidence_error_becomes_public_tag_without_storing_text_or_changing_cost():
    receipt = providers.Result({}, 1, 2, 3000, telemetry={}, cost_source="reported")
    annotate(receipt, ValueError("Satzmarkierung hat keinen eindeutigen Rollenbeleg."), phase="visual")
    assert receipt.telemetry["validation"]["errors"] == [{"location": "field", "reason": "sentence_role_evidence"}]
    assert receipt.cost_micros == 3000 and receipt.cost_source == "reported"
