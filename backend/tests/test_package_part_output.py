"""Complete small part responses through the real adapter and old validators."""

import copy
import json

import httpx
import pytest
from package_output_helpers import PackageOutputCapture
from schulpilot import package_part_output, providers
from test_package_output_transport import fixture
from test_package_transport import config


def part():
    data, context, _ = fixture()
    data["units"] = data["units"][:1]
    data["units"][0]["questions"] = data["units"][0]["questions"][:2]
    unit = data["units"][0]
    for item in [unit, *unit["questions"]]:
        for step in item["explanation_steps"]:
            for block in step["presentation"]["blocks"]:
                block["scene"]["steps"] = block["scene"]["steps"][:2]
    context["visual_context"]["sources"] = context["visual_context"]["sources"][:1]
    context["visual_context"]["references"] = context["visual_context"]["references"][:1]
    context["visual_context"]["references"][0]["kind"] = "scene"
    payload = {**context, "materials": [{"subject": unit["subject"], "group_id": unit["group_id"],
        "topic": f"Künstliches Thema {index}", "content": context["visual_context"]["sources"][0]["content"]}
        for index in range(3)], "selected_groups": [{"id": unit["group_id"], "subject": unit["subject"],
        "estimated_minutes": 8}], "package_partition": 0, "package_plan_digest": "a" * 64}
    return data, payload


@pytest.mark.parametrize("fault", [None, "three_questions", "two_steps", "long_prompt", "three_phases", "mixed_scene_numbers", "solution_visual_prompt"])
def test_actual_part_adapter_uses_two_questions_one_graphic_step_and_rejects_oversize(monkeypatch, fault):
    data, payload = part()
    if fault == "three_questions":
        data["units"][0]["questions"].append({**copy.deepcopy(data["units"][0]["questions"][0]), "id": "extra"})
    elif fault == "two_steps":
        data["units"][0]["questions"][0]["explanation_steps"].append(
            {**copy.deepcopy(data["units"][0]["questions"][0]["explanation_steps"][0]), "id": "extra"})
    elif fault == "long_prompt":
        data["units"][0]["questions"][0]["prompt"] = "x" * 301
    elif fault == "solution_visual_prompt":
        data["units"][0]["questions"][0]["prompt"] = (
            "Welche Vergangenheitsform gehört in den Satz? Die Lösungsgrafik vergleicht play und played."
        )
    elif fault == "three_phases":
        scene = data["units"][0]["explanation_steps"][0]["presentation"]["blocks"][0]["scene"]
        scene["steps"].append(copy.deepcopy(scene["steps"][0]))
    elif fault == "mixed_scene_numbers":
        for item in [data["units"][0], *data["units"][0]["questions"]]:
            item["explanation_steps"][0]["presentation"]["blocks"][0]["numbers"] = [1]
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["max_tokens"] == 8000 and body["reasoning"]["effort"] == "medium"
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {
            "content": json.dumps(output.wire(data), ensure_ascii=False)}}],
            "usage": {"prompt_tokens": 100, "completion_tokens": 2000, "cost": 0.0202}})

    monkeypatch.setattr(providers.httpx, "Client", lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, "external_allowed", lambda *a, **kw: None)
    monkeypatch.setattr(providers, "decrypt", lambda _: "synthetic-no-network-key")
    monkeypatch.setattr("schulpilot.model_routing.selection", lambda _: {"route": {"upstreams": ["azure"]}, "region": "standard"})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    if fault:
        with pytest.raises(providers.ProviderError) as caught:
            providers.request_provider(value, "package", payload)
        if fault == "mixed_scene_numbers":
            billed = caught.value.billing_result
            assert billed.cost_micros == 20200 and billed.cost_source == "reported"
            errors = billed.telemetry["validation"]["errors"]
            assert len(errors) == 3 and {item["reason"] for item in errors} == {"scene_parameters"}
            assert all(item["location"].endswith("presentation.blocks.0") for item in errors)
            assert "synthetic-no-network-key" not in json.dumps(billed.telemetry)
        elif fault == "solution_visual_prompt":
            assert caught.value.billing_result.telemetry['validation']['errors'][0]['reason'] == 'part_solution_in_prompt'
    else:
        result = providers.request_provider(value, "package", payload)
        assert len(result.data["units"]) == 1 and len(result.data["units"][0]["questions"]) == 2
        assert result.cost_micros == 20200
        assert package_part_output.enabled(payload)  # index zero is a real part.
    assert len(calls) == 1


@pytest.mark.parametrize('field', ['prompt', 'explanation', 'hint'])
def test_repeated_generated_words_rejected_without_modifying_tasks(field):
    data, _ = part()
    q = data['units'][0]['questions'][0]
    if field == 'hint':
        q['hints'][0] = 'So bleibt das bleiben bleiben bleiben bleiben bleiben bleiben.'
    else:
        q[field] = 'So soll es bleiben bleiben bleiben bleiben bleiben bleiben.'
    before = copy.deepcopy(data)
    with pytest.raises(ValueError, match='stark wiederholte Formulierung'):
        package_part_output.validate(data)
    assert data == before


def test_short_repetitions_in_a_language_exercise_are_not_suppressed():
    data, _ = part()
    data['units'][0]['questions'][0]['prompt'] = 'Vergleiche: sehr sehr groß und sehr groß.'
    package_part_output.validate(data)


@pytest.mark.parametrize('text', [
    'Die Lösungsgrafik vergleicht „play“ und „played“. Welche Verbform gehört in den Satz?',
    'Welche Vergangenheitsform von eat passt? Die Lösungsgrafik vergleicht „eat“ und „ate“.',
    'Finde das Ergebnis. Die Antwortdarstellung zeigt 3/4.',
])
def test_solution_visual_cannot_be_described_in_question_prompt(text):
    data, _ = part()
    data['units'][0]['questions'][0]['prompt'] = text
    before = copy.deepcopy(data)
    with pytest.raises(ValueError, match='Lösungsgrafik'):
        package_part_output.validate(data)
    assert data == before


def test_visible_problem_data_can_still_be_named_in_prompt():
    data, _ = part()
    data['units'][0]['questions'][0]['prompt'] = 'Beim Bruch 2/3: Welche Zahl ist der Nenner?'
    package_part_output.validate(data)
