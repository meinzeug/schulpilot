"""Artificial German examples exercise the real package graphic contract."""
import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_part_output, providers, visual_references
from schulpilot.db import DB
from schulpilot.subject_content import PROFILES
from schulpilot.visual_reference_models import VisualReference
from test_package_transport import config

REFERENCE = "german.original_examples.comparison"
EXAMPLES = ["Das Heft liegt hier.", "Die Hefte liegen hier."]
SOURCE = "\n".join(EXAMPLES)


def context(db):
    return {"required": True, "references": visual_references.candidates(db, "Deutsch", SOURCE),
        "sources": [{"ref": "p1", "subject": "Deutsch", "group_id": "g1", "content": SOURCE}]}


def step(stage="solution"):
    return {"id": "e1", "text": "Vergleiche die beiden vollständigen Originalbeispiele.",
        "competence_id": None, "disclosure": stage,
        "reference": {"id": REFERENCE, "version": 1}, "source_refs": ["p1"],
        "presentation": {"version": 1, "evidence_kind": "knowledge", "blocks": [{
            "kind": "sentence", "title": "Originalbeispiele vergleichen", "disclosure": stage,
            "source_excerpt": SOURCE, "labels": list(EXAMPLES), "numbers": [], "connections": [],
            "marks": [], "unit": "", "variant": "classification", "scene": None,
            "text_probe": None, "lab": None}]}}


def output():
    questions = [{"id": "q1", "type": "short",
        "prompt": "Welche Verbform steht im Beispiel Die Hefte liegen hier.?", "answer": "liegen"},
        {"id": "q2", "type": "short",
         "prompt": "Welches Nomen steht im Beispiel Das Heft liegt hier.?", "answer": "Heft"}]
    return {"units": [{"group_id": "g1", "subject": "Deutsch", "topic": "Originalbeispiele",
        "explanation": "Lies beide Originalbeispiele und vergleiche ihre Wörter.",
        "explanation_steps": [step("given")], "questions": [
            {**question, "options": [], "accepted": [], "hints": ["Lies das genannte Beispiel."],
             "explanation": "Das Wort steht unverändert im genannten Originalbeispiel.",
             "presentation": None, "explanation_steps": [step()]} for question in questions]}]}


def test_new_recipe_uses_existing_german_sentence_profile_and_keeps_old_recipe_immutable():
    assert "sentence" in PROFILES["Deutsch"] and "forms" not in PROFILES["Deutsch"]
    with DB() as db:
        rows = context(db)["references"]
        selected = next(row for row in rows if row["id"] == REFERENCE)
        stored = db.get(VisualReference, (REFERENCE, 1))
        assert selected["kind"] == "sentence" and selected["variant"] == "classification"
        assert selected["digest"] == stored.digest == visual_references.digest(stored.recipe)
        old = db.get(VisualReference, ("language.forms.original_comparison", 1))
        assert "Deutsch" not in old.recipe["subjects"]
        assert old.digest == visual_references.digest(old.recipe)
        assert not any(row["id"] == REFERENCE for row in visual_references.candidates(db, "Mathematik", SOURCE))


@pytest.mark.parametrize("fault", ["spelling", "invented", "substring", "marks", "numbers", "group", "prompt"])
def test_new_comparison_keeps_literal_source_question_and_disclosure_guards(fault):
    value = step()
    block = value["presentation"]["blocks"][0]
    question = output()["units"][0]["questions"][0]
    with DB() as db:
        visual = context(db)
        if fault == "spelling":
            block["labels"][1] = "die Hefte liegen hier."
        elif fault == "invented":
            block["labels"][1] = "Ein Ball liegt dort."
        elif fault == "substring":
            block["labels"] = ["Heft", "eft"]
        elif fault == "marks":
            block["marks"] = [{"index": 0, "role": "subject"}]
        elif fault == "numbers":
            block["numbers"] = [1]
        elif fault == "group":
            visual["sources"][0]["group_id"] = "other"
        else:
            question["prompt"] = "Welche Verbform ist richtig?"
        with pytest.raises(ValueError):
            visual_references.validate_steps(db, [value], "Deutsch", visual, question=question, group_id="g1")


def test_actual_package_adapter_sends_german_comparison_without_invented_arrows(monkeypatch):
    with DB() as db:
        visual = context(db)
    payload = {"package_partition": 5, "package_plan_digest": "a" * 64, "visual_context": visual,
        "selected_groups": [{"id": "g1", "subject": "Deutsch", "estimated_minutes": 8}],
        "materials": [{"subject": "Deutsch", "group_id": "g1", "topic": "Originalbeispiele", "content": SOURCE}]}
    data = output()
    original = copy.deepcopy(data)
    capture, real, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        assert REFERENCE in json.dumps(body["response_format"])
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(capture.wire(data), ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 1000, "cost": 0.01}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-not-a-provider-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    provider = config()
    provider.max_output_tokens, provider.reserve_micros = 8000, 250000
    result = providers.request_provider(provider, "package", payload)
    assert len(calls) == 1 and result.cost_micros == 10000
    assert data == original and payload["materials"][0]["content"] == SOURCE
    assert [q["answer"] for q in result.data["units"][0]["questions"]] == ["liegen", "Heft"]
    package_part_output.validate(result.data)
    for item in [result.data["units"][0], *result.data["units"][0]["questions"]]:
        graphic = item["explanation_steps"][0]["presentation"]["blocks"][0]
        assert graphic["kind"] == "sentence" and graphic["variant"] == "classification"
        assert graphic["labels"] == EXAMPLES and graphic["connections"] == []
