"""Use only prevalidated original-list graphics in non-math study stages."""
import copy

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
