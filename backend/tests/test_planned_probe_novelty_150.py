"""Synthetic prerequisite/practice collision gates; no provider call or learner evidence."""
import pytest
from schulpilot import material_fraction_expansions as material
from schulpilot import notebook_fraction_expansions as notebook
from schulpilot.coaching import fraction_task_signature
from test_material_fraction_expansions_140 import prepared as material_payload
from test_notebook_fraction_expansions import prepared as notebook_payload


@pytest.mark.parametrize('kind', ['material', 'notebook'])
def test_future_probe_examples_are_excluded_before_planning_across_seeds(household, monkeypatch, kind):
    module, fixture = (material, material_payload) if kind == 'material' else (notebook, notebook_payload)
    _, payload, initial, *_ = fixture(household)
    probes = [probe['prompt'] for probe in initial[module.KEY]['probes']]
    original_digest, original_planner = module._digest, module.fraction_tasks
    calls = []

    def checked_planner(*args, **kwargs):
        assert probes
        assert set(probes) <= set(kwargs['excluded_prompts'])
        calls.append(1)
        return original_planner(*args, **kwargs)

    monkeypatch.setattr(module, 'fraction_tasks', checked_planner)
    for seed in range(64):
        def seeded_digest(value):
            if isinstance(value, list) and value and value[0] == module.REVISION:
                return f'controlled-novelty-seed-{seed}'
            return original_digest(value)
        monkeypatch.setattr(module, '_digest', seeded_digest)
        planned = module.prepare(payload)[module.KEY]
        questions = [*planned['probes'], *planned['tasks']]
        prompts = [question['prompt'] for question in questions]
        signatures = [signature for prompt in prompts if (signature := fraction_task_signature(prompt)) is not None]
        assert len(prompts) == len(set(prompts))
        assert len(signatures) == len(set(signatures))
    assert len(calls) == 64
