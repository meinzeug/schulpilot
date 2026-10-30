"""Synthetic source-bound shadow model; no provider calls or learner data."""
import copy

import pytest
from schulpilot import package_output_transport, package_part_output, package_transport, visual_references
from schulpilot.db import DB
from schulpilot.package_prepared_shadow import REFERENCE, bases
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import Graphic
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = ('Licht und Schatten\n\nLicht breitet sich geradlinig aus.\n\n'
          'Ein undurchsichtiger Gegenstand wirft einen Schatten.\n\n'
          'Lampe und Wand bleiben am selben Platz.\n\n'
          'Näher an der Lampe wird der Schatten größer.')


@pytest.mark.parametrize('source', [
    'Ein Gegenstand wirft einen Schatten. Lampe und Wand bleiben am selben Platz. Näher an der Lampe wird der Schatten größer.',
    'Ein undurchsichtiger Gegenstand wirft keinen Schatten. Lampe und Wand bleiben am selben Platz. Näher an der Lampe wird der Schatten größer.',
    'Ein undurchsichtiger Gegenstand wirft einen Schatten. Die Lampe bewegt sich. Näher an der Lampe wird der Schatten größer.',
    'Ein undurchsichtiger Gegenstand wirft einen Schatten. Lampe und Wand bleiben am selben Platz. Näher an der Lampe wird der Schatten kleiner.',
])
def test_never_infer_unconfirmed_shadow_relationship(source):
    assert not list(bases(source))


def test_original_shadow_source_and_two_positions_bind_to_immutable_reference():
    payload = payload_for(SOURCE, 'Physik')
    with DB() as db:
        payload['visual_context']['references'] = visual_references.candidates(db, 'Physik', SOURCE, package_prepared=True)
    schema, binding = bind(payload)
    assert binding is not None
    assert {row['reference']['id'] for row in binding.candidates} == {REFERENCE}
    intro = next(row for row in binding.candidates if row['disclosure'] == 'given')
    solution = next(row for row in binding.candidates if row['disclosure'] == 'solution')
    assert solution['block']['labels'] == ['Lampe', 'Gegenstand', 'Wand', 'Schatten']
    assert not binding.question_bound(solution, {'prompt': 'Was macht der Mond?'})
    assert not binding.question_bound(solution, {'prompt': 'Was bleibt stehen? Schatten'})
    assert not binding.question_bound(solution, {'prompt': 'Was bleibt stehen?\u200bSchatten'})
    questions = [
        {'id': 'q1', 'type': 'choice', 'prompt': 'Was geschieht mit dem Schatten nahe der Lampe?',
         'answer': 'Er wird größer.', 'options': ['Er wird größer.', 'Er wird kleiner.'], 'accepted': [],
         'hints': ['Vergleiche die beiden Positionen.'], 'explanation': 'Der Schatten wird größer.',
         'presentation': None, 'field_group': None, 'explanation_steps': [wire_step(solution)]},
        {'id': 'q2', 'type': 'short', 'prompt': 'Was bleibt beim Schatten fest: Lampe oder Gegenstand?',
         'answer': 'Lampe', 'options': [], 'accepted': [], 'hints': ['Lies den Satz.'],
         'explanation': 'Lampe und Wand bleiben stehen.', 'presentation': None, 'field_group': None,
         'explanation_steps': [wire_step(solution)]},
    ]
    wire = {'units': [{'group_id': 'g1', 'subject': 'Physik', 'topic': 'Licht und Schatten',
                       'explanation': 'Lampe und Wand bleiben stehen. Der Schatten wird näher an der Lampe größer.',
                       'explanation_steps': [wire_step(intro)], 'questions': questions}]}
    original = copy.deepcopy(wire)
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    decoded = binding.hydrate(codec.decode(codec.encode(wire)))
    assert wire == original
    decoded = PackageOutput.model_validate(decoded).model_dump(mode='json')
    package_part_output.validate(decoded)
    with DB() as db:
        visual_references.validate_output(db, decoded, payload)
    changed = copy.deepcopy(solution['block'])
    changed['labels'][1] = 'Spiegel'
    with pytest.raises(ValueError):
        visual_references._meaningful(Graphic.model_validate(changed), {'id': REFERENCE, 'kind': 'shadow_size'}, sources=[SOURCE])


def test_explicit_followup_retains_checked_source_and_required_goal():
    from schulpilot import providers
    from schulpilot.package_prepared_shadow import bind_followup
    from schulpilot.schemas import PracticeUnitOutput
    from schulpilot.subject_content import bind_graphic_schema

    base = payload_for(SOURCE, 'Physik')
    with DB() as db:
        refs = visual_references.candidates(db, 'Physik', SOURCE, package_prepared=True)
    source = {**base['visual_context']['sources'][0], 'group_id': None}
    payload = {'review': True, 'practice_kind': 'repair', 'required_subject': 'Physik',
        'required_topic': 'Licht und Schatten', 'focus_goal_ids': ['g1'],
        'learning_goals': [{'id': 'g1', 'label': 'Schatten vergleichen', 'source_excerpt': SOURCE}],
        'visual_context': {'required': True, 'references': refs, 'sources': [source]}}
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(payload))
    bind_graphic_schema(schema, ['Physik'])
    visual_references.bind_schema(schema, payload)
    binding = bind_followup(schema, payload)
    assert binding is not None
    intro = next(row for row in binding.candidates if row['disclosure'] == 'given')
    solution = next(row for row in binding.candidates if row['disclosure'] == 'solution')
    questions = [{'id': f'q{n}', 'learning_goal_id': 'g1', 'type': 'short', 'prompt': prompt,
        'answer': answer, 'options': [], 'accepted': [], 'hints': ['Lies den Satz.'],
        'explanation': SOURCE, 'presentation': None, 'field_group': None, 'explanation_steps': [wire_step(solution)]}
        for n, (prompt, answer) in enumerate((('Wird der Schatten näher an der Lampe größer?', 'Ja'),
            ('Was bleibt beim Schatten stehen: Lampe oder Gegenstand?', 'Lampe')), 1)]
    wire = {'subject': 'Physik', 'topic': 'Licht und Schatten', 'explanation': SOURCE,
            'explanation_steps': [wire_step(intro)], 'questions': questions}
    result = PracticeUnitOutput.model_validate(binding.hydrate(wire)).model_dump(mode='json')
    with DB() as db:
        visual_references.validate_output(db, result, payload)
