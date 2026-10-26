"""Artificial real worker transaction/graphics/ready integration; HTTP is mocked.

SQLite runs only in a fresh private RAM-backed SQLite file. An explicitly supplied
isolated PostgreSQL test URL is honored by the normal guarded test harness.
"""
import copy
import json

import httpx
import pytest
from conftest import _EXPECTED_TEST_DATABASE_URL, require_test_database
from schulpilot import db as storage
from schulpilot import providers, ready_notifications, visual_references, worker
from schulpilot.config import settings
from schulpilot.db import (
    Attempt,
    Child,
    Family,
    Installation,
    Job,
    LearningUnit,
    Material,
    Message,
    ProviderConfig,
    UnitCoaching,
    Usage,
    now,
)
from schulpilot.visual_reference_models import UnitVisualSnapshot
from sqlalchemy import create_engine, func, select
from test_model_routing import policy
from test_providers import configured
from test_review_fraction_compositions_142 import CONTENT, wire
from test_round_ready_notifications import case as ready_case  # noqa: F401


@pytest.fixture(autouse=True)
def clean_database(monkeypatch, tmp_path):
    previous_settings = dict(settings.__dict__)
    previous_engine = storage.engine
    previous_bind = storage.DB.kw['bind']
    own_ram = previous_engine.dialect.name == 'sqlite'
    if own_ram:
        engine = create_engine('sqlite:///' + str(tmp_path / 'worker.sqlite'), connect_args={'check_same_thread': False})
        monkeypatch.setattr(storage, 'engine', engine)
        storage.DB.configure(bind=engine)
    else:
        require_test_database(previous_engine, settings, _EXPECTED_TEST_DATABASE_URL)
        engine = previous_engine
        storage.Base.metadata.drop_all(engine)
    try:
        storage.init_db()
        with storage.DB.begin() as db:
            db.get(Installation, 1).completed = True
        yield
    finally:
        if own_ram:
            storage.DB.configure(bind=previous_bind)
            engine.dispose()
        settings.__dict__.clear()
        settings.__dict__.update(previous_settings)


def test_ram_worker_publishes_exact_mixed_notation_round_with_curated_graphics_and_ready_notice(api, request, monkeypatch):
    case = request.getfixturevalue("ready_case")
    with storage.DB() as db:
        family_id = db.get(Family, db.get(Child, case['child']).family_id).id
    configured(family_id)
    with storage.DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.provider = 'openrouter'
        cfg.model = 'openai/gpt-6.1-sol'
        cfg.capability_evidence = 'Synthetic supported parameters upstream=fixture-upstream'
        cfg.max_output_tokens, cfg.reserve_micros = 8000, 250000
        approved = policy()
        cfg.routing_policy = {**approved, 'economy_mode': True, 'routes': {
            tier: {**route, 'upstreams': ['fixture-upstream'], 'reserve_micros': 150000 if tier == 'luna' else 250000,
                'max_output_tokens': 4000 if tier == 'luna' else 8000}
            for tier, route in approved['routes'].items()}}
        family = db.get(Family, family_id)
        family.call_limit, family.budget_micros = 100, 10000000
        page, previous = db.get(Material, case['material']), db.get(LearningUnit, case['unit'])
        page.content, page.topic = CONTENT, 'Unechte Brüche und Bruchnotation'
        previous.topic = page.topic
        previous.status, previous.completed = 'completed', int(now())
        previous.questions = [
            {'id': 'old1', 'type': 'short', 'prompt': 'Schreibe 11/4 als gemischte Zahl.', 'answer': '2 3/4',
                'options': [], 'accepted': [], 'hints': ['Bündele vollständige Ganze.'], 'explanation': 'Gespeicherte Erklärung.', 'learning_goal_id': 'g1'},
            {'id': 'old2', 'type': 'short', 'prompt': 'Ein Ganzes ist in 5 gleich große Teile geteilt. 2 Teile sind ausgewählt. Welchen Bruch beschreibt das? Schreibe Zähler/Nenner.',
                'answer': '2/5', 'options': [], 'accepted': [], 'hints': ['Zähle die Teile.'], 'explanation': 'Gespeicherte Erklärung.', 'learning_goal_id': 'g2'}]
        goals = [{'id': 'g1', 'label': 'Unechte Brüche als gemischte Zahlen darstellen.',
                'source_excerpt': 'Unechte Brüche in gemischte Zahlen umwandeln.'},
            {'id': 'g2', 'label': 'Einen Bruch mit Zähler und Nenner notieren.',
                'source_excerpt': 'Unechte Brüche in gemischte Zahlen umwandeln.'}]
        db.add(UnitCoaching(unit_id=previous.id, status='ready', decision='check',
            report={'learning_goals': goals, 'question_reviews': []}))
        old_questions = copy.deepcopy(previous.questions)
        before_attempts = db.scalar(select(func.count()).select_from(Attempt))
    api.headers['X-Schulpilot-Capabilities'] = 'learning-entry-v1'
    response = api.post(f"/api/children/{case['child']}/units", json={'material_id': case['material'], 'review_of': case['unit']},
        headers={'Idempotency-Key': 'synthetic-mixed-notation-worker-142'})
    assert response.status_code == 202, response.text
    job_id = response.json()['id']
    with storage.DB() as db:
        created = db.get(Job, job_id)
        assert created is not None and created.status == 'queued', (response.json(), [(j.kind, j.status) for j in db.scalars(select(Job))])
        assert worker.claim(db) == job_id
    captured, replies = [], []
    original_request, real = worker.request_provider, httpx.Client
    def observe(config, function, payload, *args, **kwargs):
        assert function == 'unit'
        captured.append(copy.deepcopy(payload))
        _, reply = wire(payload)
        replies.append(reply)
        return original_request(config, function, payload, *args, **kwargs)
    def handler(request):
        assert len(replies) == 1
        captured.append(json.loads(request.content))
        return httpx.Response(200, json={'choices': [{'finish_reason': 'stop',
            'message': {'content': json.dumps(replies[0])}}],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 500, 'cost': .001}})
    monkeypatch.setattr(worker, 'request_provider', observe)
    monkeypatch.setattr(providers.httpx,
        'Client', lambda **_kw: real(transport=httpx.MockTransport(handler)))
    import inspect
    def reveal_synthetic_worker_error(*_args, **_kwargs):
        error = inspect.currentframe().f_back.f_locals.get('exc')
        if error is not None:
            raise error
    monkeypatch.setattr(worker.log, 'warning', reveal_synthetic_worker_error)
    worker.process(job_id)
    with storage.DB() as db:
        job = db.get(Job, job_id)
        assert job.status == 'completed', job.error
        unit = db.get(LearningUnit, job.result['unit_id'])
        assert unit.status == 'not_started' and unit.review_of == case['unit']
        assert len(unit.questions) == 2 and {q['learning_goal_id'] for q in unit.questions} == {'g1', 'g2'}
        assert [(q['id'], q['learning_goal_id']) for q in unit.questions] == [('q1', 'g1'), ('q2', 'g2')]
        assert db.get(LearningUnit, case['unit']).questions == old_questions
        assert db.scalar(select(func.count()).select_from(Attempt)) == before_attempts
        assert len(captured) == 2 and captured[1]['max_tokens'] == 8000
        assert len(captured[0]['learning_entry']['units']) == 1
        assert captured[0]['learning_entry']['units'][0]['entry_mode'] == 'existing_contract'
        assert captured[0]['learning_entry']['units'][0]['probes'] == []
        snapshot = db.get(UnitVisualSnapshot, unit.id)
        assert snapshot.status == 'ready' and set(snapshot.question_steps) == {'q1', 'q2'}
        assert visual_references.projection(db, unit)['explanation_visual_status'] == 'ready'
        assert visual_references.source_bindings_current(db, unit, require_question_binding=True)
        curated = [ref for ref in snapshot.source_bindings if ref.get('source_kind') == 'curated_foundation']
        assert len(curated) == 1 and curated[0]['reference_id'] == 'math.fractions.meaning'
        assert curated[0]['example_question_id'] == 'q2'
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.route_snapshot['reason'] == 'material_graphic_teaching'
        assert usage.reserved_micros == 250000 and usage.cost_source == 'reported' and usage.cost_micros == 1000
        message = db.scalar(select(Message).where(Message.kind == ready_notifications.KIND))
        assert message is not None and message.context == {'unit_id': unit.id}
        assert message.body == 'Deine Lernrunde ist bereit.'
        assert len(job.payload[ready_notifications.RECEIPTS]) == 1
