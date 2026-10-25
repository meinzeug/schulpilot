"""Recorded OCR length in one explicit notebook batch; no external calls."""
from copy import deepcopy

import pytest
from conftest import create_child
from fastapi import HTTPException
from schulpilot.db import DB, Family, Job, Material, ProviderConfig, SchoolDay, Usage, uid
from schulpilot.job_failures import generation_availability
from schulpilot.model_routing import choose_tier, extraction_failed, features_for, job_config
from schulpilot.providers import reserve
from sqlalchemy import func, select
from test_model_routing import setup_policy

LENGTH = ("Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
          "kein automatischer Wiederholungsversuch.")


@pytest.fixture
def batch(api, household):
    parent, child = household
    family_id = parent['families'][0]['id']
    setup_policy(family_id)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.reserve_micros = 500000
        config.max_output_tokens = 8000
        config.routing_policy = {**config.routing_policy, 'routes': {
            tier: {**route, 'reserve_micros': 150000 if tier == 'luna' else 250000,
                   'max_output_tokens': 4000 if tier == 'luna' else 8000}
            for tier, route in config.routing_policy['routes'].items()}}
        day = SchoolDay(child_id=child['id'], school_date='2026-10-25', stage='review')
        db.add(day)
        db.flush()
        previous = Material(child_id=child['id'], school_day_id=day.id, page_number=1,
                            title='SYNTHETIC previous page', status='review')
        current = Material(child_id=child['id'], school_day_id=day.id, page_number=2,
                           title='SYNTHETIC next page', status='uploaded')
        db.add_all([previous, current])
        db.flush()
        failed = Job(child_id=child['id'], kind='extract', status='failed', error=LENGTH,
                     error_code='invalid_output', payload={'material_id': previous.id,
                         'material_revision': previous.revision, 'school_day_id': day.id}, idempotency=uid())
        upcoming = Job(child_id=child['id'], kind='extract', payload={'material_id': current.id,
                           'material_revision': current.revision, 'school_day_id': day.id}, idempotency=uid())
        db.add_all([failed, upcoming])
        db.flush()
        return {'parent': parent, 'child': child, 'family': family_id, 'day': day.id,
                'previous': previous.id, 'current': current.id, 'failed': failed.id, 'upcoming': upcoming.id}


def test_next_page_preflight_and_normal_reservation_use_existing_sol_after_batch_length(batch, monkeypatch):
    def forbidden(*args, **kwargs):
        pytest.fail('Routing/reservation must not invoke a provider')
    monkeypatch.setattr('schulpilot.providers.request_provider', forbidden)
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        before = deepcopy(cfg.routing_policy)
        facts = features_for(db, batch['child']['id'], batch['upcoming'])
        assert not facts['poor_image'] and facts['extraction_failed']
        assert choose_tier('extract', facts, economy=True) == ('sol', 'recorded_transcription_failure')
        assert generation_availability(db, db.get(Family, batch['family']), 'extract',
            child_id=batch['child']['id'], job_id=batch['upcoming']) is None
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert not db.dirty
        usage = reserve(db, db.get(Family, batch['family']), batch['child']['id'], batch['upcoming'], 'extract')
        assert usage.route_snapshot['tier'] == 'sol' and usage.reserved_micros == 250000
        selected = job_config(db, db.get(Job, batch['upcoming']))
        assert selected.max_output_tokens == 8000 and selected.reserve_micros == 250000
        assert selected.reasoning_effort == 'medium' and cfg.routing_policy == before
        assert cfg.reserve_micros == 500000
        assert db.get(Job, batch['failed']).status == 'failed'
        assert db.get(Job, batch['upcoming']).status == 'queued'
        assert not db.get(Material, batch['current']).confirmed
        assert db.scalar(select(func.count()).select_from(Job)) == 2


@pytest.mark.parametrize('fault', ['old_revision', 'wrong_target_revision', 'foreign_job', 'foreign_material',
    'other_day', 'missing_recorded_day', 'moved_source', 'removed_source', 'foreign_day',
    'wrong_source_purpose', 'wrong_target_purpose', 'other_error', 'not_failed'])
def test_batch_observation_cannot_cross_source_child_day_or_failure_binding(api, batch, fault):
    sibling = create_child(api, batch['parent'], 'routing-sibling')
    with DB.begin() as db:
        failed = db.get(Job, batch['failed'])
        previous = db.get(Material, batch['previous'])
        current = db.get(Material, batch['current'])
        if fault == 'old_revision':
            previous.revision += 1
        elif fault == 'wrong_target_revision':
            current.revision += 1
        elif fault == 'foreign_job':
            failed.child_id = sibling['id']
        elif fault == 'foreign_material':
            previous.child_id = sibling['id']
        elif fault in ('other_day', 'moved_source'):
            day = SchoolDay(child_id=batch['child']['id'], school_date='2026-10-24')
            db.add(day)
            db.flush()
            if fault == 'other_day':
                previous.school_day_id = day.id
                failed.payload = {**failed.payload, 'school_day_id': day.id}
            else:
                previous.school_day_id = day.id
        elif fault == 'missing_recorded_day':
            failed.payload = {k: v for k, v in failed.payload.items() if k != 'school_day_id'}
        elif fault == 'removed_source':
            db.delete(previous)
        elif fault == 'foreign_day':
            db.get(SchoolDay, batch['day']).child_id = sibling['id']
        elif fault == 'wrong_source_purpose':
            previous.purpose = 'exam'
        elif fault == 'wrong_target_purpose':
            current.purpose = 'homework'
        elif fault == 'other_error':
            failed.error = 'Die Quelle wurde geändert.'
        elif fault == 'not_failed':
            failed.status = 'completed'
    with DB() as db:
        facts = features_for(db, batch['child']['id'], batch['upcoming'])
        assert not facts['extraction_failed']
        assert choose_tier('extract', facts)[0] == 'luna'
        assert not db.new and not db.dirty and db.scalar(select(func.count()).select_from(Usage)) == 0


def test_recorded_need_does_not_bypass_normal_higher_route_budget(batch):
    with DB.begin() as db:
        db.get(Family, batch['family']).budget_micros = 200000
    with DB() as db:
        blocker = generation_availability(db, db.get(Family, batch['family']), 'extract',
            child_id=batch['child']['id'], job_id=batch['upcoming'])
        assert blocker['code'] == 'quota_exhausted'
        with pytest.raises(HTTPException) as raised:
            reserve(db, db.get(Family, batch['family']), batch['child']['id'], batch['upcoming'], 'extract')
        assert raised.value.status_code == 429
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_unrelated_page_change_does_not_erase_current_observation_or_reroute_reserved_job(batch):
    with DB.begin() as db:
        extra = Material(child_id=batch['child']['id'], school_day_id=batch['day'], title='SYNTHETIC extra', revision=7)
        db.add(extra)
        db.flush()
        assert extraction_failed(db, batch['child']['id'], batch['current'])
        usage = reserve(db, db.get(Family, batch['family']), batch['child']['id'], batch['upcoming'], 'extract')
        assert usage.route_snapshot['tier'] == 'sol'
        db.get(Material, batch['previous']).revision += 1
        assert not extraction_failed(db, batch['child']['id'], batch['current'])
        assert job_config(db, db.get(Job, batch['upcoming'])).model == usage.model
        assert usage.route_snapshot['tier'] == 'sol'


def test_no_recorded_failure_preserves_existing_first_page_route(batch):
    with DB.begin() as db:
        db.delete(db.get(Job, batch['failed']))
    with DB() as db:
        facts = features_for(db, batch['child']['id'], batch['upcoming'])
        assert not facts['extraction_failed']
        assert choose_tier('extract', facts) == ('luna', 'bounded_literal_transcription')
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
