"""Pure synthetic proof/real-adapter tests; no ASGI, database DDL or provider.

The local clean_database override deliberately uses immutable bundled recipes
instead of any app database. Nothing here calls an authorization/API shortcut.
"""
import copy
import json
import os
import socket
from types import SimpleNamespace

from cryptography.fernet import Fernet

os.environ.setdefault('ENVIRONMENT', 'test')
os.environ.setdefault('DATABASE_URL', 'sqlite://')
os.environ.setdefault('DATA_DIR', '/tmp/schulpilot142-public-composition-test')
os.environ.setdefault('MASTER_KEY', Fernet.generate_key().decode())

import httpx
import pytest
from schulpilot import (
    coaching,
    learning_entry,
    learning_sources,  # noqa: F401  -- load aliases before the per-test source stub
    providers,
    review_fraction_plan,
    source_lineage,
    visual_references,
)
from schulpilot import db as storage
from schulpilot import review_fraction_compositions as adapter
from schulpilot import unit_fraction_compositions as composition
from schulpilot.config import settings
from schulpilot.db import LearningUnit, ProviderConfig
from schulpilot.fraction_conversion_rule import inputs
from schulpilot.fraction_practice_plan import ERROR, INVALID
from schulpilot.schemas import PracticeUnitOutput
from schulpilot.security import encrypt
from schulpilot.visual_reference_models import VisualReference
from sqlalchemy import event
from test_graphic_native_transport import subset_record
from test_model_routing import policy

CONTENT = ('Unechte Brüche in gemischte Zahlen umwandeln.\n'
    'Zähler : Nenner → 14 : 5 = 2 Rest 4.\n'
    'Beispiel: 14/5 = 2 + 4/5. Weiteres Beispiel: 7/3 = 2 + 1/3.')
RECORDS = json.loads(visual_references.BUNDLE.read_text())['references']
RECIPES = {(r['id'], r['version']): SimpleNamespace(id=r['id'], version=r['version'], recipe=r,
    digest=visual_references.digest(r)) for r in RECORDS}

class RecipeLookup:
    """Bounded immutable reference lookup, never a SQLAlchemy session."""
    def __enter__(self):
        return self
    def __exit__(self, *_args):
        return False
    def get(self, model, key):
        assert model is VisualReference
        return RECIPES.get(key)

@pytest.fixture(autouse=True)
def clean_database(monkeypatch):
    # Override the broad integration fixture: these tests make zero DB calls.
    previous = dict(settings.__dict__)
    object.__setattr__(settings, 'real_data_approved', True)
    object.__setattr__(settings, 'privacy_evidence', 'Only invented local transport evidence')
    object.__setattr__(settings, 'openrouter_api_key', '')
    monkeypatch.setattr(providers, 'runtime_settings', lambda: settings)
    monkeypatch.setattr(storage, 'DB', RecipeLookup)
    def no_sql(*_args, **_kwargs):
        raise AssertionError('SQL/DDL forbidden in a pure composition proof test')
    event.listen(storage.engine, 'before_cursor_execute', no_sql)
    def refuse(*_a, **_kw):
        raise AssertionError('Real network/provider forbidden in a synthetic proof test')
    monkeypatch.setattr(socket.socket, 'connect', refuse)
    monkeypatch.setattr(socket, 'getaddrinfo', refuse)
    yield
    event.remove(storage.engine, 'before_cursor_execute', no_sql)
    settings.__dict__.clear()
    settings.__dict__.update(previous)

def source(content=CONTENT, *, subject='Mathematik', topic='Gemischte Zahlen', **extra):
    return {'ref': 'p1', 'subject': subject, 'group_id': None, 'material_id': '1' * 32,
        'revision': 2, 'topic': topic, 'content': content, 'source_refs': [], 'factual_status': 'confirmed_source', **extra}

def original_payload(original=None):
    original = original or source()
    value = {'function': 'unit', 'grade': 6, 'required_subject': original['subject'],
        'material': {key: original[key] for key in ('subject', 'topic', 'content')},
        'previous_prompts': [],
        'visual_context': {'version': 1, 'required': True,
            'references': [], 'sources': [copy.deepcopy(original)]}}
    return composition.add_reference(RecipeLookup(), value)

def config():
    result = ProviderConfig(id=1, revision=1, provider='openrouter', model='synthetic-public-composition-model',
        reasoning_effort='medium', encrypted_key=encrypt('SYNTHETIC-NOT-A-REAL-KEY'),
        emergency_stop=False, image_capable=False, structured_capable=True,
        capability_evidence='Synthetic strict-schema upstream=fixture-upstream', privacy_approved=True,
        privacy_evidence='Only invented local transport evidence', production_block_reason='',
        openrouter_free_only=False, openrouter_require_zdr=True,
        input_per_million_micros=1, output_per_million_micros=1,
        pricing_evidence='Synthetic local receipt, no real call', max_output_tokens=8000,
        reserve_micros=250000, global_limit_micros=10000000, routing_policy={}, status='synthetic')
    approved = policy()
    result._selected_route = {'reason': 'material_graphic_teaching', 'tier': 'sol', 'region': 'standard',
        'route': {**approved['routes']['sol'], 'upstreams': ['fixture-upstream']}, 'budget': approved['budget']}
    return result

class ContextLookup(RecipeLookup):
    def __init__(self, previous):
        self.previous = previous
    def get(self, model, key):
        if model is LearningUnit:
            return self.previous if key == self.previous.id else None
        return super().get(model, key)


@pytest.fixture
def case(monkeypatch):
    child = SimpleNamespace(id='2' * 32)
    page = SimpleNamespace(id='1' * 32, revision=2, child_id=child.id, purpose='notebook',
        confirmed=True, synthetic=False, fixture_id=None, subject='Mathematik', topic='Gemischte Zahlen')
    previous = SimpleNamespace(id='3' * 32, child_id=child.id, material_id=page.id, status='completed',
        subject=page.subject, topic=page.topic, school_day_id='4' * 32,
        questions=[{'id': 'old', 'prompt': 'Schreibe 11/4 als gemischte Zahl.', 'answer': '2 3/4'}])
    job = SimpleNamespace(id='5' * 32, kind='unit', status='running', child_id=child.id, payload={
        'material_id': page.id, 'material_revision': 2, 'review_of': previous.id,
        'sources': [{'id': page.id, 'revision': 2}]})
    goals = [{'id': 'g1', 'label': 'Unechte Brüche in gemischte Zahlen umwandeln',
        'source_excerpt': 'Unechte Brüche in gemischte Zahlen umwandeln.'}]
    state = {'prompts': [q['prompt'] for q in previous.questions], 'chain': [previous], 'goals': goals, 'focus': ['g1'],
        'safe': {k: source()[k] for k in ('content', 'source_refs', 'factual_status')}}
    monkeypatch.setattr(coaching, 'goals_for', lambda _db, _unit: copy.deepcopy(state['goals']))
    monkeypatch.setattr(coaching, 'focus_ids', lambda _db, _unit, action: list(state['focus']))
    monkeypatch.setattr(coaching, '_practice_history_prompts', lambda _db, _unit: list(state['prompts']))
    monkeypatch.setattr(source_lineage, 'learning_source', lambda _db, _page, revision: copy.deepcopy(state['safe']))
    monkeypatch.setattr(coaching, 'root_and_units', lambda _db, _unit: (previous, state['chain']))
    body = original_payload()
    # Reflect the real legacy worker: ordinary visual context does NOT add the
    # composition reference while review=True and practice_kind is absent.
    body['visual_context']['references'] = []
    body.update(review=True, required_topic=page.topic, learning_goals=copy.deepcopy(goals),
        focus_goal_ids=['g1'], previous_prompts=state['prompts'][-80:])
    cfg = config()
    return SimpleNamespace(db=ContextLookup(previous), child=child, page=page, pages=[page], previous=previous,
        job=job, payload=body, config=cfg, route=cfg._selected_route, state=state)


def prepare(case):
    return adapter.prepare(case.db, case.job, case.child, case.page, case.pages,
        case.config, case.route, case.payload)


def publication(case, body, data, receipt):
    adapter.validate(case.db, case.job, case.child, case.page, case.pages,
        case.config, case.route, body, data, receipt)
    coaching.validate_new_round(case.db, case.previous, data)


def wire(body):
    schema = providers.strict_schema(PracticeUnitOutput, preserve_limits=True)
    providers.indexed_choice_schema(schema, bounded_matches=True)
    providers.bind_practice_tasks(schema, providers.practice_tasks(body))
    visual_references.bind_schema(schema, body)
    binding = review_fraction_plan.bind_schema(schema, body) or composition.bind_schema(schema, body)
    assert binding is not None
    def step(candidate):
        return {'id': candidate['id'], 'text': candidate['text'], 'competence_id': None,
            'disclosure': candidate['disclosure'], 'reference': copy.deepcopy(candidate['reference']),
            'source_refs': copy.deepcopy(candidate['source_refs']), 'presentation': {
                'version': 1, 'evidence_kind': 'knowledge', 'blocks': [candidate['id']]}}
    questions = []
    for task in providers.practice_tasks(body):
        selected = next(c for c in binding.candidates if c.get('question_core', {}).get('id') == task['id'])
        questions.append({**copy.deepcopy(selected['question_core']), 'hints': ['Bündele vollständige Ganze.'],
            'explanation': 'Bestimme volle Ganze und den Rest.', 'explanation_steps': [step(selected)]})
    intro = next(c for c in binding.candidates if c['disclosure'] == 'given')
    return binding, {'subject': body['required_subject'], 'topic': body['required_topic'],
        'explanation': 'Bündele vollständige Ganze und betrachte den Rest.',
        'explanation_steps': [step(intro)], 'questions': questions}


@pytest.mark.parametrize('two_focus', [False, True])
def test_real_mock_provider_binds_existing_review_and_exact_two_cores(case, monkeypatch, two_focus):
    if two_focus:
        case.state['goals'].append({**case.state['goals'][0], 'id': 'g2'})
        case.state['focus'] = ['g1', 'g2']
        case.payload.update(learning_goals=copy.deepcopy(case.state['goals']), focus_goal_ids=['g1', 'g2'])
    original = copy.deepcopy(case.payload)
    old_questions = copy.deepcopy(case.previous.questions)
    body, receipt = prepare(case)
    assert receipt and case.payload == original and body['review'] is True and body['practice_kind'] == 'check'
    assert case.job.kind == 'unit' and case.job.payload['review_of'] == case.previous.id
    assert not body.get('math_tasks') and not body.get('notebook_practice') and not body.get('study_block')
    binding, response = wire(body)
    expected = copy.deepcopy(response)
    requests, real = [], httpx.Client
    def handler(request):
        requests.append(json.loads(request.content))
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(response)}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 500, 'cost': .001}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: real(transport=httpx.MockTransport(handler)))
    before = case.config.max_output_tokens, case.config.reserve_micros, case.config.model
    result = providers.request_provider(case.config, 'unit', body)
    publication(case, body, result.data, receipt)
    assert len(requests) == 1 and requests[0]['max_tokens'] == 8000
    assert requests[0]['provider']['allow_fallbacks'] is False and requests[0]['reasoning']['effort'] == 'medium'
    assert result.cost_micros == 1000 and result.cost_source == 'reported'
    assert before == (case.config.max_output_tokens, case.config.reserve_micros, case.config.model)
    assert result.data['subject'] == case.previous.subject and result.data['topic'] == case.previous.topic
    assert len(result.data['questions']) == 2
    for actual, asked in zip(result.data['questions'], expected['questions'], strict=True):
        assert all(actual[k] == asked[k] for k in ('id', 'learning_goal_id', 'type', 'prompt', 'answer', 'options', 'accepted'))
    assert case.previous.questions == old_questions and response == expected
    assert {q['learning_goal_id'] for q in result.data['questions']} == set(case.state['focus'])
    assert [b['numbers'] for b in result.data['questions'][0]['explanation_steps'][0]['presentation']['blocks']] == [[5, 5], [5, 5], [4, 5]]
    subset_record(requests[0]['response_format']['json_schema']['schema'])
    assert composition.REVISION in requests[0]['messages'][0]['content']
    # A repeated preparation reuses the exact immutable reference, never appends a duplicate.
    case.payload = body
    repeat, _ = prepare(case)
    assert repeat == body
    assert len([r for r in repeat['visual_context']['references'] if r['id'] == composition.RECIPE]) == 1


@pytest.mark.parametrize('change', ['not_review', 'foreign_previous', 'incomplete_previous', 'other_anchor',
    'wrong_route', 'wrong_tier', 'wrong_provider', 'homework', 'exam', 'notebook_selection', 'study',
    'assignment', 'foreign_page', 'page_revision', 'synthetic', 'fixture', 'goal_unrelated', 'unquoted_goal',
    'math_tasks', 'groups', 'missing_goal', 'wrong_subject', 'unconfirmed', 'other_practice', 'other_tasks'])
def test_other_review_scopes_remain_exactly_unchanged_without_planning(case, change):
    if change == 'not_review':
        case.payload['review'] = False
    elif change == 'foreign_previous':
        case.previous.child_id = 'a' * 32
    elif change == 'incomplete_previous':
        case.previous.status = 'paused'
    elif change == 'other_anchor':
        case.previous.material_id = 'b' * 32
    elif change == 'wrong_route':
        case.route['reason'] = 'bounded_source_help'
    elif change == 'wrong_tier':
        case.route['tier'] = 'luna'
    elif change == 'wrong_provider':
        case.config.provider = 'codex'
    elif change in ('homework', 'exam'):
        case.page.purpose = change
    elif change == 'notebook_selection':
        case.job.payload['notebook_practice'] = {'version': 1, 'question_count': 5}
    elif change == 'study':
        case.job.payload['study_block'] = {'mode': 'recall'}
    elif change == 'assignment':
        case.job.payload['assignment_id'] = 'c' * 32
    elif change == 'foreign_page':
        case.page.child_id = 'd' * 32
    elif change == 'page_revision':
        case.page.revision += 1
    elif change == 'synthetic':
        case.page.synthetic = True
    elif change == 'fixture':
        case.page.fixture_id = 'test'
    elif change == 'goal_unrelated':
        case.payload['learning_goals'][0]['label'] = 'Brüche erweitern'
    elif change == 'unquoted_goal':
        case.payload['learning_goals'][0]['source_excerpt'] = 'Eine nicht vorhandene Regel.'
    elif change == 'math_tasks':
        case.payload['math_tasks'] = [{'id': 'q1'}]
    elif change == 'groups':
        case.job.payload['groups'] = [{'id': 'g1'}]
    elif change == 'missing_goal':
        case.payload['learning_goals'] = []
    elif change == 'wrong_subject':
        case.payload['required_subject'] = 'Deutsch'
    elif change == 'unconfirmed':
        case.page.confirmed = False
    elif change == 'other_practice':
        case.payload['practice_kind'] = 'repair'
    elif change == 'other_tasks':
        case.payload['practice_tasks'] = [{'id': 'different'}]
    before = copy.deepcopy(case.payload)
    result, receipt = prepare(case)
    assert result == before and receipt is None and case.payload == before


@pytest.mark.parametrize('history', [
    ['Schreibe neun Viertel als gemischte Zahl.'],
    ['Schreibe 14/5 als gemischte Zahl.', 'Schreibe 7/3 als gemischte Zahl.'],
    [f'Schreibe {n}/{d} als gemischte Zahl.' for n, d in inputs()],
])
def test_complete_history_refuses_unknown_or_exhausted_plan_without_a_request(case, monkeypatch, history):
    case.state['prompts'] = history
    # Without the division rule there are only the two actual source literals.
    case.payload['visual_context']['sources'][0]['content'] = CONTENT.replace('Zähler : Nenner → 14 : 5 = 2 Rest 4.', '')
    case.payload['material']['content'] = case.payload['visual_context']['sources'][0]['content']
    requests = []
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: requests.append(True))
    before = copy.deepcopy(case.payload)
    with pytest.raises(ValueError) as caught:
        prepare(case)
    assert caught.value.args == (ERROR,) and requests == [] and case.payload == before


@pytest.mark.parametrize('change', ['history', 'history_before_80', 'worded_history', 'goal', 'focus',
    'source_content', 'source_status', 'source_refs', 'source_topic', 'source_revision', 'scope', 'job',
    'answer', 'goal_pair', 'prompt', 'count', 'reference_digest'])
def test_publication_rechecks_current_history_sources_goals_and_never_repairs_data(case, change):
    body, receipt = prepare(case)
    binding, response = wire(body)
    data = binding.hydrate(response)
    if change in ('history', 'history_before_80'):
        prompt = data['questions'][0]['prompt']
        case.state['prompts'] = [prompt] + (['Eine andere Frage.'] * 100 if change.endswith('80') else [])
    elif change == 'worded_history':
        case.state['prompts'] += ['Schreibe neun Viertel als gemischte Zahl.']
    elif change == 'goal':
        case.state['goals'][0]['source_excerpt'] = 'Andere bestätigte Regel.'
    elif change == 'focus':
        case.state['focus'] = ['g2']
    elif change == 'source_content':
        case.state['safe']['content'] += ' Geänderte Abschrift.'
    elif change == 'source_status':
        case.state['safe']['factual_status'] = 'excluded'
    elif change == 'source_refs':
        case.state['safe']['source_refs'] = [{'id': 'other'}]
    elif change == 'source_topic':
        case.page.topic += ' anders'
    elif change == 'source_revision':
        case.page.revision += 1
    elif change == 'scope':
        case.previous.child_id = 'e' * 32
    elif change == 'job':
        case.job.payload['review_of'] = 'f' * 32
    elif change == 'answer':
        data['questions'][0]['answer'] = '3 1/5'
    elif change == 'goal_pair':
        data['questions'][0]['learning_goal_id'] = 'g2'
    elif change == 'prompt':
        data['questions'][0]['prompt'] = 'Schreibe 17/5 als gemischte Zahl.'
    elif change == 'count':
        data['questions'].pop()
    elif change == 'reference_digest':
        body['visual_context']['references'][0]['digest'] = '0' * 64
    before = copy.deepcopy(data)
    with pytest.raises(ValueError):
        publication(case, body, data, receipt)
    assert data == before


def test_unknown_scope_does_not_run_post_checks(case):
    before = copy.deepcopy(case.payload)
    adapter.validate(case.db, case.job, case.child, case.page, case.pages, case.config,
        case.route, case.payload, {}, None)
    assert case.payload == before


@pytest.mark.parametrize('change', ['goals_raced', 'missing_recipe', 'conflicting_digest', 'duplicate_reference'])
def test_invalid_preflight_fails_closed_before_any_mock_http(case, monkeypatch, change):
    if change == 'goals_raced':
        case.state['goals'][0]['source_excerpt'] = 'Andere Quelle.'
    elif change == 'missing_recipe':
        original = case.db.get
        monkeypatch.setattr(case.db, 'get', lambda model, key: None if model is VisualReference else original(model, key))
    else:
        body, _ = prepare(case)
        case.payload = body
        if change == 'conflicting_digest':
            body['visual_context']['references'][0]['digest'] = '0' * 64
        else:
            body['visual_context']['references'] *= 2
    calls = []
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: calls.append(True))
    before = copy.deepcopy(case.payload)
    with pytest.raises(ValueError) as caught:
        prepare(case)
    assert caught.value.args == (INVALID,) and calls == [] and case.payload == before


def test_worker_wires_prepare_before_dispatch_and_fresh_check_before_publication():
    import ast
    from pathlib import Path

    source = Path(__file__).parents[1] / 'schulpilot' / 'worker.py'
    module = ast.parse(source.read_text())
    process = next(node for node in module.body if isinstance(node, ast.FunctionDef) and node.name == '_process')
    calls = {}
    for node in ast.walk(process):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            calls.setdefault(node.func.id, []).append(node)
    assert calls['prepare_review_composition'][0].lineno < calls['request_provider'][0].lineno
    child_lock = next(node for node in calls['update'] if node.args and isinstance(node.args[0], ast.Name)
        and node.args[0].id == 'Child' and node.lineno > calls['request_provider'][0].lineno)
    assert child_lock.lineno < calls['validate_review_composition'][0].lineno < calls['validate_new_round'][0].lineno
    assert calls['validate_new_round'][0].lineno < calls['LearningUnit'][0].lineno
    assert len(calls['request_provider']) == len(calls['validate_new_round']) == 1


@pytest.mark.parametrize('fault', ['answer', 'goal_pair', 'count', 'reference', 'disclosure'])
def test_billed_model_fault_is_rejected_once_without_output_repair(case, monkeypatch, fault):
    body, _ = prepare(case)
    _, response = wire(body)
    if fault == 'answer':
        response['questions'][0]['answer'] = '3 1/5'
    elif fault == 'goal_pair':
        response['questions'][0]['learning_goal_id'] = 'g2'
    elif fault == 'count':
        response['questions'].pop()
    elif fault == 'reference':
        response['questions'][0]['explanation_steps'][0]['reference']['version'] = 77
    else:
        response['questions'][0]['explanation_steps'][0]['disclosure'] = 'given'
    before = copy.deepcopy(response)
    calls, real = [], httpx.Client
    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(response)}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 500, 'cost': .001}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: real(transport=httpx.MockTransport(handler)))
    with pytest.raises(providers.ProviderError) as caught:
        providers.request_provider(case.config, 'unit', body)
    assert len(calls) == 1 and calls[0]['max_tokens'] == 8000 and response == before
    assert caught.value.billing_result.cost_micros == 1000 and caught.value.billing_result.cost_source == 'reported'


def old_unit(case, prompt, *, child_id=None):
    return SimpleNamespace(id='a' * 32, child_id=child_id or case.child.id,
        school_day_id='b' * 32, questions=[{'id': 'older', 'prompt': prompt, 'answer': 'unchanged'}])


def test_history_is_unbounded_own_chain_plus_day_union_before_compaction(case):
    earlier = 'Schreibe 14/5 als gemischte Zahl.'
    other_day = old_unit(case, earlier)
    foreign = old_unit(case, 'Schreibe 7/3 als gemischte Zahl.', child_id='f' * 32)
    case.state['chain'] = [other_day, case.previous, foreign]
    case.state['prompts'] = [case.previous.questions[0]['prompt'], *[f'Andere Frage {i}.' for i in range(100)]]
    body, _ = prepare(case)
    prompts = adapter._history(case.db, case.previous)
    assert len(prompts) == 102 and prompts[0] == earlier
    assert prompts.count(case.previous.questions[0]['prompt']) == 1
    assert foreign.questions[0]['prompt'] not in prompts
    assert '14/5' in body['fraction_practice_history']['used_values']
    _, response = wire(body)
    assert response['questions'][0]['prompt'] == 'Schreibe 7/3 als gemischte Zahl.'


def test_no_day_uses_complete_own_chain_without_a_day_query(case, monkeypatch):
    case.previous.school_day_id = None
    earlier = 'Schreibe 14/5 als gemischte Zahl.'
    case.state['chain'] = [old_unit(case, earlier), case.previous]
    def no_day_query(*_args):
        raise AssertionError('No day query without a school day')
    monkeypatch.setattr(coaching, '_practice_history_prompts', no_day_query)
    body, _ = prepare(case)
    assert adapter._history(case.db, case.previous) == [earlier, case.previous.questions[0]['prompt']]
    assert body['fraction_practice_history']['used_values'] == ['11/4', '14/5']


def test_old_chain_and_current_day_jointly_exhaust_original_source_values_before_http(case, monkeypatch):
    case.state['chain'] = [old_unit(case, 'Schreibe 14/5 als gemischte Zahl.'), case.previous]
    case.state['prompts'] = ['Schreibe 7/3 als gemischte Zahl.']
    case.payload['visual_context']['sources'][0]['content'] = CONTENT.replace('Zähler : Nenner → 14 : 5 = 2 Rest 4.', '')
    calls = []
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: calls.append(True))
    with pytest.raises(ValueError) as caught:
        prepare(case)
    assert caught.value.args == (ERROR,) and calls == []


def test_unknown_conversion_in_older_chain_is_not_hidden_by_current_day(case, monkeypatch):
    case.state['chain'] = [old_unit(case, 'Schreibe neun Viertel als gemischte Zahl.'), case.previous]
    case.state['prompts'] = ['Welches Wort fehlt?'] * 100
    calls = []
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: calls.append(True))
    with pytest.raises(ValueError) as caught:
        prepare(case)
    assert caught.value.args == (ERROR,) and calls == []


@pytest.mark.parametrize('with_day', [False, True])
def test_newly_used_value_on_older_chain_day_rejects_publication_without_repair(case, with_day):
    if not with_day:
        case.previous.school_day_id = None
    body, receipt = prepare(case)
    binding, response = wire(body)
    data = binding.hydrate(response)
    before = copy.deepcopy(data)
    case.state['chain'].insert(0, old_unit(case, data['questions'][0]['prompt']))
    with pytest.raises(ValueError) as caught:
        publication(case, body, data, receipt)
    assert caught.value.args == (adapter.CURRENT_ERROR,) and data == before


def test_new_unknown_conversion_on_old_chain_rejects_post_lock_publication(case):
    body, receipt = prepare(case)
    binding, response = wire(body)
    data = binding.hydrate(response)
    before = copy.deepcopy(data)
    case.state['chain'].insert(0, old_unit(case, 'Schreibe neun Viertel als gemischte Zahl.'))
    with pytest.raises(ValueError) as caught:
        publication(case, body, data, receipt)
    assert caught.value.args == (adapter.CURRENT_ERROR,) and data == before


@pytest.fixture
def mixed_case(case):
    case.state['goals'].append({'id': 'g2', 'label': 'Einen Bruch mit Zähler und Nenner notieren.',
        'source_excerpt': 'Unechte Brüche in gemischte Zahlen umwandeln.'})
    case.state['focus'] = ['g1', 'g2']
    case.payload.update(learning_goals=copy.deepcopy(case.state['goals']), focus_goal_ids=['g1', 'g2'])
    return case


@pytest.mark.parametrize('reverse', [False, True])
def test_actual_mixed_notation_http_wire_preserves_both_real_goals_and_curated_source(mixed_case, monkeypatch, reverse):
    case = mixed_case
    if reverse:
        case.state['focus'].reverse()
        case.payload['focus_goal_ids'].reverse()
    original = copy.deepcopy(case.payload)
    body, receipt = prepare(case)
    assert receipt and case.payload == original
    assert body.get('learning_entry') is None and 'fraction_practice_history' not in body
    assert not composition._focused_practice(body) and review_fraction_plan.supported(body)
    binding, response = wire(body)
    expected = copy.deepcopy(response)
    calls, real = [], httpx.Client
    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(response)}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 500, 'cost': .001}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: real(transport=httpx.MockTransport(handler)))
    result = providers.request_provider(case.config, 'unit', body)
    publication(case, body, result.data, receipt)
    assert len(calls) == 1 and calls[0]['max_tokens'] == 8000 and result.cost_micros == 1000
    assert calls[0]['provider']['allow_fallbacks'] is False and calls[0]['reasoning']['effort'] == 'medium'
    assert (case.config.max_output_tokens, case.config.reserve_micros) == (8000, 250000)
    assert response == expected and len(result.data['questions']) == 2
    assert [(q['id'], q['learning_goal_id']) for q in result.data['questions']] == [
        (f'q{i + 1}', key) for i, key in enumerate(case.state['focus'])]
    for actual, asked in zip(result.data['questions'], expected['questions'], strict=True):
        assert all(actual[key] == asked[key] for key in review_fraction_plan.CORE)
    assert set(q['learning_goal_id'] for q in result.data['questions']) == {'g1', 'g2'}
    notation = next(q for q in result.data['questions'] if q['learning_goal_id'] == 'g2')
    assert 'Welchen Bruch beschreibt das?' in notation['prompt'] and 'Schreibe Zähler/Nenner.' in notation['prompt']
    assert 'Welche Zahl ist der Nenner?' not in notation['prompt']
    curated = [s for s in body['visual_context']['sources'] if s.get('source_type') == 'curated_foundation']
    assert len(curated) == 1 and curated[0]['reference_id'] == 'math.fractions.meaning'
    assert curated[0]['example_question_id'] == notation['id'] and curated[0]['example_digest'] == review_fraction_plan._digest({
        key: notation[key] for key in learning_entry.CORE})
    visual_references.validate_output(case.db, result.data, body)
    outbound = calls[0]['response_format']['json_schema']['schema']
    subset_record(outbound)
    assert outbound['properties']['questions']['minItems'] == outbound['properties']['questions']['maxItems'] == 2
    outgoing = json.loads(calls[0]['messages'][1]['content'][0]['text'])
    assert review_fraction_plan.HISTORY not in outgoing


@pytest.mark.parametrize('fault', ['wrong_label', 'component_alias', 'wrong_quote', 'missing_goal', 'wrong_route'])
def test_mixed_notation_requires_exact_supported_semantics_and_literal_saved_goal(mixed_case, fault):
    case = mixed_case
    if fault == 'wrong_label':
        case.payload['learning_goals'][1]['label'] = 'Gemischte Zahlen kürzen'
    elif fault == 'component_alias':
        case.payload['learning_goals'][1]['label'] = 'Zähler und Nenner benennen'
    elif fault == 'wrong_quote':
        case.payload['learning_goals'][1]['source_excerpt'] = 'Erfundene Notationsdefinition.'
    elif fault == 'missing_goal':
        case.payload['focus_goal_ids'] = ['g1', 'g3']
    else:
        case.route['reason'] = 'bounded_source_help'
    before = copy.deepcopy(case.payload)
    result, receipt = prepare(case)
    assert receipt is None and result == before


@pytest.mark.parametrize('fault', ['answer', 'idswap', 'goal_id', 'count', 'numbers', 'source_revision', 'curated_content', 'curated_digest'])
def test_mixed_notation_faults_cannot_repair_or_replace_fixed_core(mixed_case, monkeypatch, fault):
    case = mixed_case
    body, receipt = prepare(case)
    binding, response = wire(body)
    if fault == 'answer':
        response['questions'][1]['answer'] = '1/99'
    elif fault == 'idswap':
        response['questions'][0]['id'], response['questions'][1]['id'] = response['questions'][1]['id'], response['questions'][0]['id']
    elif fault == 'goal_id':
        response['questions'][1]['learning_goal_id'] = 'g1'
    elif fault == 'count':
        response['questions'].pop()
    elif fault == 'source_revision':
        body['visual_context']['sources'][0]['revision'] += 1
    elif fault.startswith('curated_'):
        curated = next(s for s in body['visual_context']['sources'] if s.get('source_type') == 'curated_foundation')
        curated['content' if fault.endswith('content') else 'digest'] += ' changed'
    else:
        response['questions'][1]['explanation_steps'][0]['presentation']['blocks'] = ['wrong_numbers']
    before = copy.deepcopy(response)
    calls, real = [], httpx.Client
    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(response)}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 500, 'cost': .001}})
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: real(transport=httpx.MockTransport(handler)))
    with pytest.raises(providers.ProviderError):
        providers.request_provider(case.config, 'unit', body)
    assert response == before and len(calls) <= 1


@pytest.mark.parametrize('fault', ['part_whole_digest', 'foundation_version'])
def test_post_publication_checks_actual_part_whole_and_foundation_pins(mixed_case, monkeypatch, fault):
    body, receipt = prepare(mixed_case)
    binding, response = wire(body)
    data = binding.hydrate(response)
    if fault == 'part_whole_digest':
        monkeypatch.setattr(RECIPES[('math.fraction.part_whole', 1)], 'digest', '0' * 64)
    else:
        actual_resolve = review_fraction_plan.competences.resolve_reference
        def changed(identifier, version, digest=None):
            result = actual_resolve(identifier, version, digest)
            return {**result, 'version': 'changed-version'} if result else None
        monkeypatch.setattr(review_fraction_plan.competences, 'resolve_reference', changed)
    before = copy.deepcopy(data)
    with pytest.raises(ValueError) as caught:
        publication(mixed_case, body, data, receipt)
    assert caught.value.args == (adapter.CURRENT_ERROR,) and data == before


@pytest.mark.parametrize('mode', ['new_used_chain', 'new_equivalent_day', 'source_revision', 'changed_goal'])
def test_mixed_post_checks_full_own_chain_day_history_and_original_snapshots(mixed_case, mode):
    case = mixed_case
    body, receipt = prepare(case)
    binding, response = wire(body)
    data = binding.hydrate(response)
    notation = next(q for q in data['questions'] if q['learning_goal_id'] == 'g2')
    if mode == 'new_used_chain':
        case.state['chain'].insert(0, old_unit(case, notation['prompt']))
    elif mode == 'new_equivalent_day':
        n, d = map(int, notation['answer'].split('/'))
        case.state['prompts'] = [f'Welcher Anteil ist {n * 2}/{d * 2}?'] + ['Andere Frage.'] * 100
    elif mode == 'source_revision':
        case.page.revision += 1
    else:
        case.state['goals'][1]['label'] = 'Zähler und Nenner benennen'
    before = copy.deepcopy(data)
    with pytest.raises(ValueError) as caught:
        publication(case, body, data, receipt)
    assert caught.value.args == (adapter.CURRENT_ERROR,) and data == before


def test_mixed_notation_finite_pool_exhaustion_is_zero_call(mixed_case, monkeypatch):
    case = mixed_case
    seed = review_fraction_plan._digest([case.job.id, case.job.payload])
    case.state['prompts'] = [probe['prompt'] for probe in review_fraction_plan._notation_pool(seed)]
    calls = []
    monkeypatch.setattr(providers.httpx, 'Client', lambda **_kw: calls.append(True))
    with pytest.raises(ValueError) as caught:
        prepare(case)
    assert caught.value.args == (ERROR,) and calls == []


def test_notation_history_also_excludes_unambiguous_written_fraction_values():
    assert review_fraction_plan._values(['Notiere den Bruch zwei Drittel.', 'Schreibe drei Viertel.']) == {'2/3', '3/4'}


def test_mixed_malformed_focus_ids_and_boolean_recipe_versions_fail_closed(mixed_case):
    case = mixed_case
    case.payload['focus_goal_ids'] = [{'id': 'g1'}, 'g2']
    assert review_fraction_plan.supported(case.payload) is False
    case.payload['focus_goal_ids'] = ['g1', 'g2']
    body, _ = prepare(case)
    next(ref for ref in body['visual_context']['references'] if ref['id'] == 'math.fraction.part_whole')['version'] = True
    with pytest.raises(ValueError):
        review_fraction_plan.add_references(case.db, body)
