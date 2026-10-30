"""Artificial photographed rules, real transports/validators, no learner data."""
import copy
from decimal import Decimal

import pytest
from schulpilot import package_decimal_addition as decimal
from schulpilot import package_output_transport, package_transport, visual_references
from schulpilot.db import DB, LearningUnit
from schulpilot.schemas import PackageOutput
from schulpilot.subject_content import PROFILES, Graphic, public_presentation, validate_question
from test_package_prepared_graphics import bind, payload_for, wire_step

SOURCE = "Dezimalzahlen addieren\nKommas untereinander schreiben.\n1,2 + 0,6 = 1,8\n4,5 + 2,3 = 6,8"


def payload(content=SOURCE):
    value = payload_for(content)
    with DB() as db:
        value['visual_context']['references'] = visual_references.candidates(db, 'Mathematik', content, package_prepared=True)
    return value


def wire(context=None):
    context = context or payload()
    schema, binding = bind(context)
    assert isinstance(binding, decimal.Binding)
    intro, *questions = binding.candidates
    value = {'units': [{'group_id': 'g1', 'subject': 'Mathematik', 'topic': 'Dezimalzahlen addieren',
        'explanation': intro['text'], 'explanation_steps': [wire_step(intro)],
        'questions': [{**row['question_core'], 'hints': ['Schreibe die Kommas untereinander.'],
                       'explanation': row['text'], 'presentation': None, 'field_group': None,
                       'explanation_steps': [wire_step(row)]} for row in questions]}]}
    return value, context, schema, binding


@pytest.mark.parametrize('content', [SOURCE, SOURCE.replace(',', '{,}'), SOURCE.replace('Kommas untereinander', 'Komma unter Komma')])
def test_literal_rule_with_plain_or_latex_original(content):
    proof = decimal.evidence(content)
    assert proof and proof['quote'] in content and proof['numbers'] == [12, 6, 1]
    rows = decimal.compile_candidates(payload(content))
    assert len(rows) == 3
    assert rows[0]['block']['numbers'] == [12, 6, 1]
    assert len({row['question_core']['prompt'] for row in rows[1:]}) == 2
    for row in rows[1:]:
        a, b, p = row['block']['numbers']
        assert decimal.signature(Decimal(a) / 10**p, Decimal(b) / 10**p) not in decimal.original_pairs([content])
        assert row['question_core']['answer'] == decimal.written(Decimal(a+b) / 10**p)


@pytest.mark.parametrize('content', [
    SOURCE.replace('1,8', '1,9').replace('6,8', '6,9'),
    'Dezimalzahlen addieren\n1,2 + 0,6 = 1,8',
    'Nicht Kommas untereinander schreiben.\n1,2 + 0,6 = 1,8',
    'Kommas untereinander schreiben.\n1,9 + 0,6 = 2,5',
    'Kommas untereinander schreiben.\n11,2 + 0,6 = 11,8',
    'Kommas untereinander schreiben.\n- 1,2 + 0,6 = 1,8',
])
def test_no_rule_no_valid_example_or_unsupported_carry_is_not_inferred(content):
    assert decimal.evidence(content) is None
    assert not decimal.compile_candidates(payload(content))


def test_real_codec_schema_and_all_canonical_graphic_checks():
    value, context, schema, binding = wire()
    codec = package_output_transport.bind(package_transport.schema_projection(schema))
    output = binding.hydrate(codec.decode(codec.encode(value)))
    output = PackageOutput.model_validate(output).model_dump(mode='json')
    with DB() as db:
        visual_references.validate_output(db, output, context)
    for row in binding.candidates:
        question = row.get('question_core', {'prompt': '', 'type': 'short', 'answer': '', 'accepted': []})
        validate_question({'version': 1, 'evidence_kind': 'knowledge', 'blocks': [row['block']]},
            question, [SOURCE], PROFILES['Mathematik'], structured=True, subject='Mathematik')
    assert public_presentation(output['units'][0]['questions'][0]['explanation_steps'][0]['presentation'])['blocks'] == []


@pytest.mark.parametrize('mutation', ['answer', 'prompt', 'numbers', 'source', 'ref', 'stage', 'duplicate'])
def test_mutated_task_graphic_scope_and_disclosure_are_rejected(mutation):
    value, context, _, binding = wire()
    if mutation in ('answer', 'prompt'):
        value['units'][0]['questions'][0][mutation] = '3,5'
    elif mutation == 'duplicate':
        value['units'][0]['questions'][1] = copy.deepcopy(value['units'][0]['questions'][0])
    elif mutation == 'ref':
        value['units'][0]['questions'][0]['explanation_steps'][0]['reference']['id'] = 'foreign'
    elif mutation == 'stage':
        value['units'][0]['questions'][0]['explanation_steps'][0]['disclosure'] = 'given'
    else:
        decoded = binding.hydrate(value)
        block = decoded['units'][0]['questions'][0]['explanation_steps'][0]['presentation']['blocks'][0]
        if mutation == 'numbers':
            block['numbers'][0] += 1
        else:
            block['source_excerpt'] = 'Kommas untereinander schreiben.\n1,2 + 0,6 = 1,9'
        with DB() as db, pytest.raises(ValueError):
            visual_references.validate_output(db, decoded, context)
        return
    with pytest.raises(ValueError):
        binding.hydrate(value)


def test_all_original_examples_and_past_question_pairs_are_excluded():
    context = payload()
    rows = decimal.compile_candidates(context)
    context[decimal.HISTORY] = [decimal.signature(Decimal(r['block']['numbers'][0])/10, Decimal(r['block']['numbers'][1])/10) for r in rows[1:]]
    fresh = decimal.compile_candidates(context)
    assert not {r['question_core']['prompt'] for r in fresh[1:]} & {r['question_core']['prompt'] for r in rows[1:]}
    context[decimal.HISTORY] = [decimal.signature(Decimal(a)/10, Decimal(b)/10) for a,b,_ in decimal.inputs(1)]
    with pytest.raises(ValueError, match='bereits geübt'):
        decimal.compile_candidates(context)


def test_historical_original_never_counts_as_new_practice_even_on_direct_validation():
    proof = decimal.evidence(SOURCE)
    row = Graphic.model_validate(decimal.block([45, 23, 1], proof['quote'], 'solution'))
    with pytest.raises(ValueError, match='stimmen nicht'):
        decimal.validate(row, [SOURCE], decimal.core([45, 23, 1]))


def test_history_is_child_and_subject_scoped_and_rechecked_at_publication():
    from schulpilot.db import Child, Family, User
    value, context, _, binding = wire()
    decoded = binding.hydrate(value)
    with DB.begin() as db:
        family = Family(name='Synthetic decimal family')
        db.add(family)
        db.flush()
        users = [User(username=f'decimal-{i}@example.invalid', role='child', display_name='Synthetic child', password_hash='synthetic-unused') for i in range(2)]
        db.add_all(users)
        db.flush()
        first, second = [Child(family_id=family.id, grade=6, user_id=u.id) for u in users]
        db.add_all([first, second])
        db.flush()
        question = decoded['units'][0]['questions'][0]
        db.add(LearningUnit(child_id=second.id, subject='Mathematik', topic='Addition', questions=[question], explanation='', provider='synthetic-test'))
        db.flush()
        assert decimal.history(db, first.id) == []
        decimal.validate_history(db, first.id, decoded)
        db.add(LearningUnit(child_id=first.id, subject='Mathematik', topic='Addition', questions=[question], explanation='', provider='synthetic-test'))
        db.flush()
        with pytest.raises(ValueError, match='zwischenzeitlich'):
            decimal.validate_history(db, first.id, decoded)


@pytest.mark.parametrize('entry_mode', [None, 'source_probe', 'reuse_evidence'])
def test_actual_provider_adapter_binds_indexed_branches_and_accounts_once(monkeypatch, entry_mode):
    import json

    import httpx
    from package_output_helpers import PackageOutputCapture
    from schulpilot import providers
    from test_package_transport import config

    context = payload()
    if entry_mode:
        context['learning_entry'] = {'units': [{'group_id': 'g1', 'subject': 'Mathematik', 'entry_mode': entry_mode, 'prefix': 'entry', 'probes': [], 'allocation_version': 2}]}
    model_data, context, _, _ = wire(context)
    output, real_client, calls = PackageOutputCapture(monkeypatch), httpx.Client, []

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop', 'message': {
            'content': json.dumps(output.wire(model_data), ensure_ascii=False)}}],
            'usage': {'prompt_tokens': 111, 'completion_tokens': 2223, 'cost': 0.0321}})

    monkeypatch.setattr(providers.httpx, 'Client', lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, 'external_allowed', lambda *a, **kw: None)
    monkeypatch.setattr(providers, 'decrypt', lambda _: 'synthetic-no-network-key')
    monkeypatch.setattr('schulpilot.model_routing.selection', lambda _: {'route': {'upstreams': ['azure']}, 'region': 'standard'})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    result = providers.request_provider(value, 'package', context)
    assert len(calls) == 1 and result.cost_micros == 32100
    assert [q['prompt'] for q in result.data['units'][0]['questions']] == [q['prompt'] for q in model_data['units'][0]['questions']]


@pytest.mark.parametrize('phase,place,left,right,result', [
    ('decimal-0', 'Hundertstel', 5, 3, None), ('decimal-1', 'Hundertstel', 5, 3, 8),
    ('decimal-2', 'Zehntel', 2, 2, 4), ('decimal-3', 'Einer', 1, 0, 1),
])
def test_tutor_receives_only_the_actual_selected_column(phase, place, left, right, result):
    from schulpilot.schulbuddy_graphics import _phase
    value = _phase({'kind': 'decimal_sum', 'numbers': [125, 23, 2]}, phase)
    assert (value['column'], value['left_digit'], value['right_digit'], value['shown_result_digit']) == (place, left, right, result)


def test_tutor_rejects_foreign_or_out_of_range_decimal_phase():
    from fastapi import HTTPException
    from schulpilot.schulbuddy_graphics import _phase
    for block, phase in [({'kind': 'fraction', 'numbers': [1, 2]}, 'decimal-1'),
                         ({'kind': 'decimal_sum', 'numbers': [12, 6, 1]}, 'decimal-3')]:
        with pytest.raises(HTTPException):
            _phase(block, phase)


def test_previous_latex_or_reordered_arithmetic_is_also_excluded():
    pairs = decimal.original_pairs([r'Berechne \(2{,}30 + 4{,}5\), ohne Ergebnis.'])
    assert decimal.signature(Decimal('4.50'), Decimal('2.3')) in pairs


@pytest.mark.parametrize('mode', ['source_probe', 'reuse_evidence'])
def test_server_entry_ids_are_preserved_instead_of_being_replaced(mode):
    from schulpilot import learning_entry
    value = payload()
    plan = {'group_id': 'g1', 'subject': 'Mathematik', 'entry_mode': mode, 'prefix': 'decimal-entry', 'probes': [], 'allocation_version': 2}
    value['learning_entry'] = {'units': [plan]}
    schema, _ = bind(value)
    learning_entry.bind_entry_schema(schema, value)
    from schulpilot.package_part_output import bind_schema
    binding = bind_schema(schema, value)
    assert {r['question_core']['id'] for r in binding.candidates if r.get('question_core')} == {s['id'] for s in learning_entry._specs(plan, 2)}


def test_curated_foundation_and_new_decimal_task_keep_their_own_cores_and_graphics():
    from schulpilot import competences, learning_entry
    value = payload()
    probe = learning_entry._probe(competences.catalogue()['math.fractions.meaning'], 'decimal-synthetic', set(), '1')
    plan = {'group_id': 'g1', 'subject': 'Mathematik', 'entry_mode': 'prerequisite_probe', 'prefix': 'synthetic', 'probes': [probe], 'allocation_version': 2}
    value['learning_entry'] = {'units': [plan], 'references': [competences.resolve_reference(probe['reference_id'], competences.VERSION)]}
    with DB() as db:
        value = visual_references.with_foundation_context(db, value)
    from test_package_entry_graphics_145 import bind as bind_entry
    _, binding = bind_entry(value)
    assert isinstance(binding, decimal.Binding)
    foundation = next(r for r in binding.candidates if r['kind'] == 'fraction')
    assert foundation['question_core'] == {k: probe[k] for k in learning_entry.CORE}
    practice = next(r for r in binding.candidates if r['kind'] == decimal.KIND and r.get('question_core'))
    assert practice['question_core']['id'] == 'main_synthetic_1'


def test_feedback_points_to_decimal_place_without_changing_answer_or_claiming_a_diagnosis():
    from schulpilot.answer_evaluation import evaluate
    question = {**decimal.core([46, 51, 1]), 'explanation_steps': [{
        'reference': {'id': decimal.REFERENCE, 'version': 1},
        'presentation': {'blocks': [decimal.block([46, 51, 1], decimal.evidence(SOURCE)['quote'], 'solution')]}}]}
    original = copy.deepcopy(question)
    wrong = evaluate(question, '9,07')
    assert wrong['outcome'] == 'incorrect' and 'Zehntel' in wrong['reason']
    assert evaluate(question, '9,7')['outcome'] == 'correct'
    assert question == original
    question['answer'] = '8,7'
    assert evaluate(question, '9,7')['outcome'] == 'uncertain'


def test_whole_operand_is_a_valid_new_decimal_sum_and_history_signature():
    question = decimal.core([20, 37, 1])
    assert question['prompt'] == 'Wie viel ist 2 + 3,7?'
    assert decimal._PROMPT.fullmatch(question['prompt'])
    assert decimal.signature(Decimal('2'), Decimal('3.7')) in decimal.original_pairs([question['prompt']])
    proof = decimal.evidence(SOURCE)
    decimal.validate(Graphic.model_validate(decimal.block([20, 37, 1], proof['quote'], 'solution')), [SOURCE], question)


def unit_fixture(count=2, *, practice=False):
    from schulpilot import providers
    from schulpilot.schemas import PracticeUnitOutput, UnitOutput
    from schulpilot.subject_content import bind_graphic_schema
    base = payload()
    base['visual_context']['sources'][0]['group_id'] = None
    context = {'required_subject': 'Mathematik', 'required_topic': 'Dezimalzahlen addieren',
        'material': {'subject': 'Mathematik', 'topic': 'Dezimalzahlen addieren', 'content': SOURCE},
        'visual_context': base['visual_context'], 'previous_prompts': ['Wie viel ist 4,6 + 5,1?']}
    if practice:
        context.update(review=True, practice_kind='repair', focus_goal_ids=['g1'],
            learning_goals=[{'id': 'g1', 'label': 'Dezimalzahlen addieren', 'source_excerpt': SOURCE}],
            practice_tasks=[{'id': 'q1', 'learning_goal_id': 'g1'}, {'id': 'q2', 'learning_goal_id': 'g1'}])
    else:
        context['study_block'] = {'mode': 'apply', 'question_count': count}
    model = PracticeUnitOutput if practice else UnitOutput
    schema = providers.strict_schema(model, preserve_limits=True)
    schema['properties']['questions'].update(minItems=count, maxItems=count)
    bind_graphic_schema(schema, ['Mathematik'])
    visual_references.bind_schema(schema, context)
    binding = decimal.bind_unit(schema, context)
    assert binding is not None
    intro, *rows = binding.candidates
    wire = {'subject': 'Mathematik', 'topic': 'Dezimalzahlen addieren', 'explanation': intro['text'],
        'explanation_steps': [wire_step(intro)], 'questions': [
            {**r['question_core'], 'hints': ['Schreibe die Kommas untereinander.'],
             'explanation': r['text'], 'field_group': None, 'presentation': None,
             'explanation_steps': [wire_step(r)]} for r in rows]}
    return context, binding, wire, schema, model


@pytest.mark.parametrize('count', [2, 3, 5])
def test_subsequent_study_round_has_exact_requested_count_and_new_distinct_pairs(count):
    context, binding, wire, schema, model = unit_fixture(count)
    output = model.model_validate(binding.hydrate(wire)).model_dump(mode='json')
    assert len(output['questions']) == count
    assert len({q['id'] for q in output['questions']}) == count
    assert not set(q['prompt'] for q in output['questions']) & set(context['previous_prompts'])
    with DB() as db:
        visual_references.validate_output(db, output, context)


def test_targeted_followup_preserves_each_existing_goal_and_cannot_relabel_another_one():
    context, binding, wire, schema, model = unit_fixture(practice=True)
    output = model.model_validate(binding.hydrate(wire)).model_dump(mode='json')
    assert {q['learning_goal_id'] for q in output['questions']} == {'g1'}
    other = copy.deepcopy(context)
    other['learning_goals'][0]['label'] = 'Brüche kürzen'
    assert decimal.bind_unit(schema, other) is None


def test_actual_openrouter_adapter_can_prepare_a_goal_bound_followup(monkeypatch):
    import json

    import httpx
    from schulpilot import providers
    from test_package_transport import config
    context, binding, wire, _, _ = unit_fixture(practice=True)
    real_client, calls = httpx.Client, []
    def handler(request):
        calls.append(request)
        assert 'prepared_graphics' in json.loads(request.content)['messages'][1]['content'][0]['text']
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop', 'message': {'content': json.dumps(wire)}}],
            'usage': {'prompt_tokens': 300, 'completion_tokens': 500, 'cost': 0.001}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **kw: real_client(transport=httpx.MockTransport(handler)))
    monkeypatch.setattr(providers, 'external_allowed', lambda *a, **kw: None)
    monkeypatch.setattr(providers, 'decrypt', lambda _: 'synthetic-no-network-key')
    monkeypatch.setattr('schulpilot.model_routing.selection', lambda _: {'route': {'upstreams': ['azure']}, 'region': 'standard'})
    value = config()
    value.max_output_tokens, value.reserve_micros = 8000, 250000
    result = providers.request_provider(value, 'unit', context)
    assert len(calls) == 1 and result.cost_micros == 1000
    assert [q['learning_goal_id'] for q in result.data['questions']] == ['g1', 'g1']


def test_old_outputs_with_null_explanations_do_not_trigger_decimal_history_queries():
    class NoDatabase:
        def execute(self, *args):
            raise AssertionError('Legacy/nondecimal output must not read decimal history')
    decimal.validate_history(NoDatabase(), 'synthetic-child', {'units': [{'questions': [{'explanation_steps': None}]}]})
