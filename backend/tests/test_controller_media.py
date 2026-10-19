"""Own artificial learner, local catalog and a bounded mocked model response."""

import copy

import pytest
from catalog_fixture import sample_catalog
from fastapi import HTTPException
from schulpilot import controller_jobs
from schulpilot.catalog_import import import_catalog
from schulpilot.catalog_jobs import refresh_context
from schulpilot.catalog_models import LearningTipInteraction
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Family,
    Job,
    LearningMemory,
    LearningUnit,
    Material,
    ProviderConfig,
    Session,
    Usage,
)
from schulpilot.learning_controller import generation_guard
from schulpilot.model_routing import job_config
from schulpilot.providers import Result
from schulpilot.subject_registry import resolve
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit
from test_coaching import process_next
from test_learning_controller import endpoint, start


@pytest.fixture
def media_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def tips(client, unit_id, child_id):
    with DB.begin() as db:
        import_catalog(db, sample_catalog())
        unit = db.get(LearningUnit, unit_id)
        unit.subject_id = resolve(db, 'Mathematik').id
        unit.topic = 'Brüche addieren'
        refresh_context(db, 'unit', unit)
    path = f'/api/children/{child_id}/learning-tips/unit/{unit_id}'
    response = client.get(path)
    assert response.status_code == 200 and response.json()['state'] == 'ready', response.text
    data = response.json()
    item = data['recommended'][0]
    return path, {'revision': data['revision'], 'topic_id': item['topic_id'], 'content_id': item['id'], 'question_id': 'sum'}


def returned(client, unit_id, child_id):
    start(client, unit_id)
    path, item = tips(client, unit_id, child_id)
    for kind in ('open', 'watched'):
        response = client.post(path + '/interactions', json={**item, 'kind': kind, 'request_key': 'media-' + kind + '-0001'})
        assert response.status_code == 200, response.text
    return path, item


def ask_check(client, unit_id):
    state = client.get(endpoint(unit_id)).json()
    response = client.post(endpoint(unit_id) + '/check', json={'kind': 'check_understanding',
        'request_key': 'media-new-check-0001', 'revision': state['revision']})
    assert response.status_code == 202, response.text
    return response.json()['id']


def test_open_and_watched_are_not_answers_progress_or_active_time(media_unit):
    client, unit_id, _, _, child = media_unit
    path, item = returned(client, unit_id, child['id'])
    state = client.get(endpoint(unit_id)).json()
    assert state['action']['kind'] == 'check_understanding'
    assert state['working_memory']['media']['status'] == 'watched'
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.get(LearningUnit, unit_id).active_seconds == 0
        assert db.scalar(select(func.count()).select_from(Activity).where(Activity.kind == 'explanation')) == 1
    assert client.post(path + '/interactions', json={**item, 'kind': 'watched', 'request_key': 'media-watched-0002'}).status_code == 200
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningTipInteraction).where(LearningTipInteraction.kind == 'watched')) == 1
    result = client.post(f'/api/units/{unit_id}/questions/sum/answer', json={'answer': '2/4'}).json()
    assert result['assisted'] is True
    assert result['unit']['learning_session']['observations']['independent_first_answers'] == 0


def test_two_new_questions_are_explicit_metered_and_resume_original_draft(media_unit, monkeypatch):
    client, unit_id, _, _, child = media_unit
    returned(client, unit_id, child['id'])
    state = client.get(endpoint(unit_id)).json()
    assert client.put(endpoint(unit_id) + '/draft', json={'request_key': 'media-draft-0001',
        'question_id': 'sum', 'answer': '2/', 'revision': state['draft_revision']}).status_code == 200
    job_id = ask_check(client, unit_id)
    assert ask_check(client, unit_id) == job_id
    assert client.get(endpoint(unit_id)).json()['preparation'] == {'id': job_id, 'status': 'queued', 'unit_id': None}
    overview = client.get(f"/api/children/{child['id']}/overview?compact=true").json()
    assert overview['learning_preparation']['id'] == job_id
    calls = []
    def generate(config, function, payload):
        assert function == 'unit' and payload['review'] and payload['practice_kind'] == 'check'
        calls.append(payload)
        data = sample_unit()
        data['topic'] = 'Brüche addieren'
        data['questions'] = [dict(data['questions'][2], id='new1', learning_goal_id=payload['focus_goal_ids'][0]),
            dict(data['questions'][3], id='new2', learning_goal_id=payload['focus_goal_ids'][-1])]
        # The selected goals are source-bound components/addition, so use new,
        # exact, valid examples for these goals instead of relabelling exercises.
        data['questions'][0].update(type='short', options=[], accepted=[], prompt='Wie heißt die Zahl unter dem Bruchstrich bei 2/7?', answer='Nenner')
        data['questions'][1].update(type='short', options=[], accepted=[], prompt='Berechne 1/6 + 2/6.', answer='3/6')
        return Result(data, 100, 200, 0)
    monkeypatch.setattr(controller_jobs, 'request_provider', generate)
    process_next()
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == 'completed', job.error
        followup = db.get(LearningUnit, job.result['unit_id'])
        assert len(followup.questions) == 2 and followup.status == 'not_started'
        assert followup.learning_root_id == unit_id and followup.round_kind == 'check'
        assert db.get(LearningUnit, unit_id).status == 'paused'
        assert db.get(LearningMemory, unit_id).working['draft']['answer'] == '2/'
        assert db.scalar(select(func.count()).select_from(Usage).where(Usage.job_id == job_id)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
    assert client.get(endpoint(unit_id)).json()['preparation']['unit_id'] == followup.id
    assert len(calls) == 1


def test_unhelpful_media_gets_another_resource_and_budget_block_keeps_round(media_unit):
    client, unit_id, _, parent, child = media_unit
    path, item = returned(client, unit_id, child['id'])
    response = client.post(path + '/interactions', json={**item, 'kind': 'not_helpful', 'request_key': 'media-not-helpful-0001'})
    assert response.status_code == 200, response.text
    view = client.get(path).json()
    assert item['content_id'] not in {c['id'] for c in view['recommended'] + view['additional']}
    with DB.begin() as db:
        db.get(Family, parent['families'][0]['id']).call_limit = 0
    state = client.get(endpoint(unit_id)).json()
    response = client.post(endpoint(unit_id) + '/check', json={'request_key': 'budget-check-0001',
        'revision': state['revision'], 'kind': 'check_understanding'})
    assert response.status_code == 429
    assert client.get(f'/api/units/{unit_id}').json()['status'] == 'active'
    with DB() as db:
        assert not db.scalar(select(Job.id))


@pytest.mark.parametrize('change', ['source', 'session', 'decision'])
def test_late_generation_cannot_overwrite_changed_state(media_unit, monkeypatch, change):
    client, unit_id, material_id, _, child = media_unit
    returned(client, unit_id, child['id'])
    job_id = ask_check(client, unit_id)
    def late(config, function, payload):
        with DB.begin() as db:
            if change == 'source':
                db.get(Material, material_id).revision += 1
            elif change == 'session':
                db.get(Session, db.get(Job, job_id).payload['session_id']).revoked = True
            else:
                db.get(LearningMemory, unit_id).plan_revision += 1
        return Result(copy.deepcopy(sample_unit()), 100, 200, 0)
    monkeypatch.setattr(controller_jobs, 'request_provider', late)
    process_next()
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == 'failed'
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        assert db.scalar(select(Usage).where(Usage.job_id == job_id)).status == 'failed_billed'


def test_generation_guard_ignores_draft_changes_but_rejects_new_learning_decision(media_unit):
    client, unit_id, _, _, _ = media_unit
    start(client, unit_id)
    with DB() as db:
        before = generation_guard(db, unit_id)
    state = client.get(endpoint(unit_id)).json()
    assert client.put(endpoint(unit_id) + '/draft', json={'request_key': 'guard-draft-001', 'revision': state['draft_revision'],
        'question_id': 'sum', 'answer': '2/4'}).status_code == 200
    with DB() as db:
        assert generation_guard(db, unit_id) == before
    client.post(f'/api/units/{unit_id}/questions/sum/hint')
    with DB() as db:
        # Hints may leave the same action; changed evidence still increments the
        # session revision, but only a changed plan invalidates a pending action.
        memory = db.get(LearningMemory, unit_id)
        memory.plan_revision += 1
        db.flush()
        job = Job(child_id=db.get(LearningUnit, unit_id).child_id, kind='unit', payload={'unit_id': unit_id,
            'controller_guard': before}, idempotency='stale-plan-test')
        with pytest.raises(HTTPException):
            job_config(db, job)


def test_changed_legacy_provider_configuration_never_reaches_transport(media_unit, monkeypatch):
    client, unit_id, _, _, child = media_unit
    returned(client, unit_id, child['id'])
    job_id = ask_check(client, unit_id)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        assert not config.routing_policy  # Revision binding also applies outside the new mix.
        config.model = 'different-synthetic-model'
        config.revision += 1
    calls = []

    def must_not_call(config, function, payload):
        calls.append(function)
        raise AssertionError('Changed provider configuration reached transport')

    monkeypatch.setattr(controller_jobs, 'request_provider', must_not_call)
    process_next()
    assert calls == []
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == 'failed'
        assert 'KI-Einstellung' in job.error
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.model != 'different-synthetic-model'
        assert usage.status == 'failed_unknown'
        assert usage.cost_micros is None


def test_public_demo_cannot_turn_media_return_into_an_arbitrary_external_call(media_unit):
    client, unit_id, _, _, child = media_unit
    path, _ = returned(client, unit_id, child['id'])
    with DB.begin() as db:
        db.get(LearningUnit, unit_id).synthetic = True
    assert client.get(path).json()['media_return'] is None
    state = client.get(endpoint(unit_id)).json()
    response = client.post(endpoint(unit_id) + '/check', json={'kind': 'check_understanding',
        'request_key': 'demo-no-external-001', 'revision': state['revision']})
    assert response.status_code == 409
    with DB() as db:
        assert not db.scalar(select(Job.id)) and not db.scalar(select(Usage.id))
