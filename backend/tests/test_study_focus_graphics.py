"""Use only prevalidated original-list graphics in non-math study stages."""
import copy
import json

import httpx
import pytest
from schulpilot import package_prepared_focus as focus
from schulpilot import providers, study_focus_graphics, visual_references
from schulpilot.db import DB
from schulpilot.graphic_schema import bind_coherent_graphics
from schulpilot.schemas import UnitOutput
from schulpilot.subject_content import bind_graphic_schema
from test_package_original_focus import SOURCES
from test_package_prepared_graphics import payload_for, wire_step


def fixture(subject='Geschichte'):
    raw = payload_for(SOURCES[subject], subject)
    for row in raw['visual_context']['sources']:
        row['group_id'] = None
    payload = {'required_subject': subject, 'required_topic': 'Öffentliche Beispiele',
        'material': {'subject': subject, 'content': SOURCES[subject]},
        'study_block': {'mode': 'detective', 'question_count': 2, 'tasks': []},
        'visual_context': raw['visual_context']}
    schema = providers.strict_schema(UnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    bind_graphic_schema(schema, [subject])
    bind_coherent_graphics(schema)
    visual_references.bind_schema(schema, payload)
    schema['properties']['questions'].update(minItems=2, maxItems=2)
    binding = study_focus_graphics.bind_schema(schema, payload)
    assert binding is not None
    selected = next(x for x in binding.binding.candidates if x['disclosure'] == 'solution')
    intro = next(x for x in binding.binding.candidates if x['disclosure'] == 'given')
    questions = [{'id': f'q{i}', 'type': 'choice', 'prompt': prompt,
        'options': focus.options_slot(selected), 'answer': i, 'accepted': [],
        'hints': ['Lies die Aussagen.'], 'explanation': 'Vergleiche die Aussagen.',
        'presentation': None, 'field_group': None, 'explanation_steps': [wire_step(selected)]}
        for i, prompt in enumerate(['Welche Aussage beschreibt das Zusammenleben?',
                                    'Welche Aussage beschreibt die Herstellung?'])]
    data = {'subject': subject, 'topic': 'Öffentliche Beispiele', 'explanation': 'Vergleiche die Aussagen.',
            'explanation_steps': [wire_step(intro)], 'questions': questions}
    return payload, schema, binding, data


def test_bound_study_round_preserves_count_and_original_options_and_passes_visual_checks():
    payload, schema, binding, data = fixture()
    before = copy.deepcopy(data)
    assert schema['properties']['questions']['minItems'] == schema['properties']['questions']['maxItems'] == 2
    decoded = binding.hydrate(data)
    providers.decode_choice_indices(decoded)
    validated = UnitOutput.model_validate(decoded).model_dump(mode='json')
    with DB() as db:
        visual_references.validate_output(db, validated, payload)
    assert data == before
    for q in validated['questions']:
        assert q['options'] == q['explanation_steps'][0]['presentation']['blocks'][0]['labels']
        assert q['answer'] in q['options']


@pytest.mark.parametrize('fault', ['slot', 'foreign_id', 'wrong_source', 'wrong_stage', 'answer_index'])
def test_scope_and_answer_faults_are_never_repaired(fault):
    _, _, binding, data = fixture()
    q = data['questions'][0]
    if fault == 'slot':
        q['options'] = 'foreign'
    elif fault == 'foreign_id':
        q['explanation_steps'][0]['presentation']['blocks'] = ['foreign']
    elif fault == 'wrong_source':
        q['explanation_steps'][0]['source_refs'] = ['p2']
    elif fault == 'wrong_stage':
        q['explanation_steps'][0]['disclosure'] = 'given'
    else:
        q['answer'] = 999
    with pytest.raises(ValueError):
        binding.hydrate(data)


def test_plain_prose_and_non_study_units_are_not_fabricated():
    payload, schema, _, _ = fixture()
    payload['visual_context']['sources'][0]['content'] = 'Nur zusammenhängende Prosa ohne Liste.'
    assert study_focus_graphics.bind_schema(schema, payload) is None
    payload.pop('study_block')
    assert study_focus_graphics.bind_schema(schema, payload) is None


def test_coach_practice_keeps_fixed_goal_pairs_and_source_graphics():
    from schulpilot.schemas import PracticeUnitOutput
    from test_unit_reference_graphics_135 import branches

    payload, _, _, data = fixture()
    payload.pop('study_block')
    tasks = [{'id': 'q1', 'learning_goal_id': 'g1', 'source_excerpt': 'Im Dorf lebten mehrere Familien.'},
             {'id': 'q2', 'learning_goal_id': 'g2', 'source_excerpt': 'Die Menschen stellten Schalen aus Ton her.'}]
    payload.update(review=True, practice_tasks=tasks)
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    bind_graphic_schema(schema, ['Geschichte'])
    bind_coherent_graphics(schema)
    visual_references.bind_schema(schema, payload)
    providers.bind_practice_tasks(schema, tasks)
    binding = study_focus_graphics.bind_schema(schema, payload)
    assert binding is not None
    questions = list(branches(schema, schema['properties']['questions']['items']))
    assert {(q['properties']['id']['enum'][0], q['properties']['learning_goal_id']['enum'][0])
            for q in questions} == {('q1', 'g1'), ('q2', 'g2')}
    for i, question in enumerate(data['questions']):
        question['id'] = tasks[i]['id']
        question['learning_goal_id'] = tasks[i]['learning_goal_id']
    decoded = binding.hydrate(data)
    providers.decode_choice_indices(decoded)
    validated = PracticeUnitOutput.model_validate(decoded).model_dump(mode='json')
    with DB() as db:
        visual_references.validate_output(db, validated, payload)
    assert [(q['id'], q['learning_goal_id']) for q in validated['questions']] == [('q1', 'g1'), ('q2', 'g2')]


def test_coach_graphic_cannot_bind_to_an_unrelated_goal_source():
    from schulpilot.schemas import PracticeUnitOutput

    payload, _, _, _ = fixture()
    payload.pop('study_block')
    tasks = [{'id': 'q1', 'learning_goal_id': 'g1', 'source_excerpt': 'Im Dorf lebten mehrere Familien.'},
             {'id': 'q2', 'learning_goal_id': 'g2', 'source_excerpt': 'Inhalt einer fremden Quelle'}]
    payload.update(review=True, practice_tasks=tasks)
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    bind_graphic_schema(schema, ['Geschichte'])
    bind_coherent_graphics(schema)
    visual_references.bind_schema(schema, payload)
    providers.bind_practice_tasks(schema, tasks)
    before = copy.deepcopy(schema)
    assert study_focus_graphics.bind_schema(schema, payload) is None
    assert schema == before


def test_real_coach_transport_keeps_prepared_ids_and_goal_pairs(monkeypatch):
    from test_model_routing import policy
    from test_presentation_capability_paths import _config

    payload, _, _, data = fixture()
    payload.pop('study_block')
    goals = [{'id': 'g1', 'label': 'Zusammenleben', 'source_excerpt': 'Im Dorf lebten mehrere Familien.'},
             {'id': 'g2', 'label': 'Herstellung', 'source_excerpt': 'Die Menschen stellten Schalen aus Ton her.'}]
    payload.update(review=True, practice_kind='repair', learning_goals=goals, focus_goal_ids=['g1', 'g2'])
    for index, question in enumerate(data['questions']):
        question['id'] = f'q{index + 1}'
        question['learning_goal_id'] = goals[index]['id']
    calls = []
    real_client = httpx.Client
    def handler(request):
        body = json.loads(request.content)
        calls.append(body)
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(data, ensure_ascii=False)}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 100, 'cost': 0.01}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **kwargs: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, 'external_allowed', lambda *args, **kwargs: None)
    monkeypatch.setattr(providers, 'decrypt', lambda _: 'synthetic-offline-key')
    config = _config('openrouter')
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    approved = policy()
    config._selected_route = {'reason': 'material_or_new_teaching', 'tier': 'sol', 'region': 'standard',
        'route': {**approved['routes']['sol'], 'upstreams': ['fixture-upstream']}, 'budget': approved['budget']}
    result = providers.request_provider(config, 'unit', payload)
    assert len(calls) == 1
    assert [(q['id'], q['learning_goal_id']) for q in result.data['questions']] == [('q1', 'g1'), ('q2', 'g2')]
    assert all(q['options'] == q['explanation_steps'][0]['presentation']['blocks'][0]['labels']
               for q in result.data['questions'])
