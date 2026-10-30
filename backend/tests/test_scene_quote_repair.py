"""Only literal, same-source scene evidence may be expanded."""
import copy

import pytest
from schulpilot.db import DB
from schulpilot.scene_quote_repair import expand_scene_quotes
from schulpilot.subject_content import public_presentation, validate_question
from schulpilot.visual_references import candidates, validate_steps


def sample():
    block = {
        'kind': 'scene', 'title': 'Wege', 'disclosure': 'solution',
        'source_excerpt': 'Wald → Fluss', 'labels': ['Wald', 'Fluss'],
        'numbers': [], 'connections': [], 'marks': [], 'unit': '', 'variant': '',
        'scene': {'version': 1, 'layout': 'row', 'transition_ms': 0,
                  'objects': [{'id': 'a', 'label': 'Wald', 'shape': 'box', 'tone': 'neutral'},
                              {'id': 'b', 'label': 'Fluss', 'shape': 'box', 'tone': 'accent'}],
                  'steps': [
                      {'caption': 'Wald', 'source_excerpt': 'Wald → Fluss',
                       'placements': [{'object_id': 'a', 'slot': 0}, {'object_id': 'b', 'slot': 1}],
                       'highlight': ['a'], 'edges': [{'start': 'a', 'end': 'b', 'label': ''}]},
                      {'caption': 'Fluss', 'source_excerpt': 'Wald → Fluss',
                       'placements': [{'object_id': 'a', 'slot': 0}, {'object_id': 'b', 'slot': 1}],
                       'highlight': ['b'], 'edges': [{'start': 'a', 'end': 'b', 'label': ''}]},
                  ]},
    }
    question = {'id': 'q', 'type': 'choice', 'prompt': 'Was folgt?',
                'answer': 'Fluss', 'accepted': [], 'explanation_steps': [
                    {'source_refs': ['p1'], 'presentation': {'version': 1, 'evidence_kind': 'knowledge', 'blocks': [block]}}
                ]}
    data = {'subject': 'Geschichte', 'questions': [question]}
    context = {'required': True, 'sources': [
        {'ref': 'p1', 'subject': 'Geschichte', 'group_id': None, 'content': 'Wege: Wald → Fluss.'}
    ]}
    return data, context


def test_literal_nearby_title_extends_exact_quote_and_passes_normal_validation():
    data, context = sample()
    question = data['questions'][0]
    presentation = question['explanation_steps'][0]['presentation']
    with pytest.raises(ValueError, match='Szenenbeschriftung'):
        validate_question(presentation, question, [context['sources'][0]['content']], ('scene',), structured=True)
    before = copy.deepcopy(data)
    expand_scene_quotes(data, context)
    block = presentation['blocks'][0]
    assert block['source_excerpt'] == 'Wege: Wald → Fluss'
    before['questions'][0]['explanation_steps'][0]['presentation']['blocks'][0]['source_excerpt'] = block['source_excerpt']
    assert data == before
    validate_question(presentation, question, [context['sources'][0]['content']], ('scene',), structured=True)
    assert 'source_excerpt' not in str(public_presentation(presentation, closed=True))
    with DB() as db:
        context['references'] = candidates(db, 'Geschichte', context['sources'][0]['content'])
        step = {**question['explanation_steps'][0], 'id': 's1', 'text': 'Wald und Fluss.',
                'competence_id': None, 'disclosure': 'solution',
                'reference': {'id': 'general.source_relation.phases', 'version': 1}}
        assert validate_steps(db, [step], 'Geschichte', context, question=question)[0]['id'] == 's1'


@pytest.mark.parametrize('change', ['invented', 'foreign_subject', 'wrong_group', 'uncited', 'distant'])
def test_unproven_or_foreign_labels_remain_invalid(change):
    data, context = sample()
    source = context['sources'][0]
    if change == 'invented':
        data['questions'][0]['explanation_steps'][0]['presentation']['blocks'][0]['title'] = 'Erfunden'
    elif change == 'foreign_subject':
        source['subject'] = 'Deutsch'
    elif change == 'wrong_group':
        source['group_id'] = 'other'
    elif change == 'uncited':
        data['questions'][0]['explanation_steps'][0]['source_refs'] = ['p2']
    else:
        source['content'] = 'Wege' + ' ' * 501 + 'Wald → Fluss'
    before = copy.deepcopy(data)
    expand_scene_quotes(data, context)
    assert data == before
    question = data['questions'][0]
    with pytest.raises(ValueError, match='Szenenbeschriftung'):
        validate_question(question['explanation_steps'][0]['presentation'], question, [source['content']], ('scene',), structured=True)


def test_expanded_quote_never_legalizes_a_reversed_relation():
    data, context = sample()
    question = data['questions'][0]
    block = question['explanation_steps'][0]['presentation']['blocks'][0]
    block['scene']['steps'][0]['edges'][0].update(start='b', end='a')
    expand_scene_quotes(data, context)
    with pytest.raises(ValueError, match='Szenenpfeil'):
        validate_question(question['explanation_steps'][0]['presentation'], question,
                          [context['sources'][0]['content']], ('scene',), structured=True)
