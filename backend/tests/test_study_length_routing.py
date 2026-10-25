"""One conscious study-stage retry routes from exact recorded length evidence."""
from copy import deepcopy

import pytest
from conftest import create_child
from fastapi import HTTPException
from schulpilot.db import DB, Child, Family, Job, Material, ProviderConfig, SchoolDay, Usage, uid
from schulpilot.job_failures import generation_availability
from schulpilot.model_routing import choose_tier, features_for, job_config
from schulpilot.providers import Result, reserve, settle
from schulpilot.school_day import planning_fingerprint
from schulpilot.study_path import fingerprint, sources
from sqlalchemy import func, select
from test_model_routing import setup_policy

LENGTH = ("Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; "
          "kein automatischer Wiederholungsversuch.")


@pytest.fixture
def stage(api, household):
    parent, child = household
    family_id = parent['families'][0]['id']
    setup_policy(family_id)
    with DB.begin() as db:
        config = db.get(ProviderConfig, 1)
        config.reserve_micros, config.max_output_tokens = 500000, 8000
        config.routing_policy = {**config.routing_policy, 'economy_mode': True, 'routes': {
            tier: {**route, 'reserve_micros': 150000 if tier == 'luna' else 250000,
                   'max_output_tokens': 4000 if tier == 'luna' else 8000}
            for tier, route in config.routing_policy['routes'].items()}}
        day = SchoolDay(child_id=child['id'], school_date='2026-10-25', stage='ready')
        db.add(day)
        db.flush()
        material = Material(child_id=child['id'], school_day_id=day.id, title='PUBLIC SYNTHETIC',
            subject='Mathematik', topic='Brüche', content='Ein Bruch 1/4 beschreibt einen von vier gleich großen Teilen.',
            confirmed=True, status='confirmed')
        db.add(material)
        db.flush()
        source_hash = fingerprint(sources(db, day), db)
        planning = planning_fingerprint(db, db.get(Child, child['id']))
        block_id = uid()
        common = {'day_id': day.id, 'block_id': block_id, 'source_hash': source_hash, 'planning': planning}
        old = Job(child_id=child['id'], kind='study_block', payload=common, idempotency=uid())
        db.add(old)
        db.flush()
        day.learning_plan = {'version': 1, 'source_hash': source_hash, 'blocks': [{'id': block_id,
            'subject': 'Mathematik', 'title': 'Brüche', 'phase': 'understand', 'material_ids': [material.id],
            'question_count': 2, 'unit_id': None, 'job_id': old.id}]}
        usage = reserve(db, db.get(Family, family_id), child['id'], old.id, 'unit')
        assert usage.route_snapshot['tier'] == 'luna'
        settle(db, usage, Result({}, 100, 200, 3210), failed=True)
        old.status, old.error = 'failed', LENGTH
        upcoming = Job(child_id=child['id'], kind='study_block', payload=dict(common), idempotency=uid())
        db.add(upcoming)
        db.flush()
        return {'parent': parent, 'child': child, 'family': family_id, 'day': day.id, 'material': material.id,
            'block': block_id, 'old': old.id, 'upcoming': upcoming.id, 'usage': usage.id}


def test_fresh_readonly_fact_and_regular_reservation_use_existing_sol_without_any_provider(stage, monkeypatch):
    monkeypatch.setattr('schulpilot.providers.request_provider', lambda *a, **kw: pytest.fail('No provider may run'))
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        policy, plan = deepcopy(cfg.routing_policy), deepcopy(db.get(SchoolDay, stage['day']).learning_plan)
        old_usage = db.get(Usage, stage['usage'])
        old_cost = (old_usage.cost_micros, old_usage.settlement_version, old_usage.status, old_usage.route_snapshot)
        facts = features_for(db, stage['child']['id'], stage['upcoming'])
        assert facts['study_length_failed'] and not facts['extraction_failed']
        assert choose_tier('unit', facts, economy=True) == ('sol', 'recorded_study_output_length')
        assert generation_availability(db, db.get(Family, stage['family']), 'unit',
            child_id=stage['child']['id'], job_id=stage['upcoming']) is None
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        usage = reserve(db, db.get(Family, stage['family']), stage['child']['id'], stage['upcoming'], 'unit')
        assert usage.route_snapshot['tier'] == 'sol' and usage.reserved_micros == 250000
        bound = job_config(db, db.get(Job, stage['upcoming']), 'unit')
        assert bound.max_output_tokens == 8000 and bound.reserve_micros == 250000
        assert bound.reasoning_effort == 'medium' and cfg.routing_policy == policy
        assert db.get(SchoolDay, stage['day']).learning_plan == plan
        assert db.get(Job, stage['old']).status == 'failed'
        assert (old_usage.cost_micros, old_usage.settlement_version, old_usage.status, old_usage.route_snapshot) == old_cost
        assert db.scalar(select(func.count()).select_from(Job)) == 2


@pytest.mark.parametrize('fault', ['source_revision', 'safe_content_same_revision', 'unconfirmed', 'deleted_source',
    'moved_source', 'missing_block', 'published', 'different_block', 'different_day', 'missing_hash',
    'previous_hash', 'plan_hash', 'previous_planning', 'current_planning', 'other_error', 'partial_message',
    'other_kind', 'target_other_kind', 'not_failed', 'foreign_job', 'foreign_material', 'foreign_day'])
def test_recorded_length_never_crosses_current_source_plan_block_child_or_exact_error(stage, api, fault):
    sibling = create_child(api, stage['parent'], 'study-routing-sibling') if fault.startswith('foreign') else None
    with DB.begin() as db:
        old, upcoming = db.get(Job, stage['old']), db.get(Job, stage['upcoming'])
        material, day = db.get(Material, stage['material']), db.get(SchoolDay, stage['day'])
        if fault == 'source_revision':
            material.revision += 1
        elif fault == 'safe_content_same_revision':
            material.content += ' Neuer bestätigter Satz.'
        elif fault == 'unconfirmed':
            material.confirmed = False
        elif fault == 'deleted_source':
            db.delete(material)
        elif fault == 'moved_source':
            material.school_day_id = None
        elif fault in ('missing_block', 'published', 'plan_hash'):
            plan = deepcopy(day.learning_plan)
            if fault == 'missing_block':
                plan['blocks'] = []
            elif fault == 'published':
                plan['blocks'][0]['unit_id'] = 'd' * 32
            else:
                plan['source_hash'] = 'd' * 64
            day.learning_plan = plan
        elif fault in ('different_block', 'different_day', 'previous_hash', 'previous_planning'):
            key = {'different_block': 'block_id', 'different_day': 'day_id', 'previous_hash': 'source_hash',
                'previous_planning': 'planning'}[fault]
            old.payload = {**old.payload, key: 'd' * (64 if 'hash' in fault or 'planning' in fault else 32)}
        elif fault == 'missing_hash':
            upcoming.payload = {key: value for key, value in upcoming.payload.items() if key != 'source_hash'}
        elif fault == 'current_planning':
            db.get(Child, stage['child']['id']).grade += 1
        elif fault == 'other_error':
            old.error = 'HTTP400 invalid_schema'
        elif fault == 'partial_message':
            old.error = 'Die KI hat die begrenzte Ausgabelänge erreicht.'
        elif fault == 'other_kind':
            old.kind = 'coach_practice'
        elif fault == 'target_other_kind':
            upcoming.kind = 'unit'
        elif fault == 'not_failed':
            old.status = 'completed'
        elif fault == 'foreign_job':
            old.child_id = sibling['id']
        elif fault == 'foreign_material':
            material.child_id = sibling['id']
        else:
            day.child_id = sibling['id']
    with DB() as db:
        if fault == 'foreign_day':
            with pytest.raises(HTTPException) as denied:
                features_for(db, stage['child']['id'], stage['upcoming'])
            assert denied.value.status_code == 403
        else:
            facts = features_for(db, stage['child']['id'], stage['upcoming'])
            assert not facts['study_length_failed']
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_only_whitespace_normalization_of_complete_known_length_message_is_allowed(stage):
    with DB.begin() as db:
        old = db.get(Job, stage['old'])
        old.error = '\n  ' + LENGTH.replace(' ', '\n  ') + '  '
    with DB() as db:
        assert features_for(db, stage['child']['id'], stage['upcoming'])['study_length_failed']


def test_no_length_evidence_keeps_first_explicit_stage_on_luna(stage):
    with DB.begin() as db:
        db.get(Job, stage['old']).error = 'Andere sichere Ablehnung.'
    with DB() as db:
        facts = features_for(db, stage['child']['id'], stage['upcoming'])
        assert not facts['study_length_failed']
        assert choose_tier('unit', facts, economy=True) == ('luna', 'focused_source_practice')


def test_higher_route_still_requires_normal_reservation_budget(stage):
    with DB.begin() as db:
        db.get(Family, stage['family']).budget_micros = 200000
    with DB() as db:
        blocker = generation_availability(db, db.get(Family, stage['family']), 'unit',
            child_id=stage['child']['id'], job_id=stage['upcoming'])
        assert blocker['code'] == 'quota_exhausted'
        with pytest.raises(HTTPException) as caught:
            reserve(db, db.get(Family, stage['family']), stage['child']['id'], stage['upcoming'], 'unit')
        assert caught.value.status_code == 429
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_reserved_snapshot_is_not_rerouted_after_evidence_changes(stage):
    with DB.begin() as db:
        usage = reserve(db, db.get(Family, stage['family']), stage['child']['id'], stage['upcoming'], 'unit')
        assert usage.route_snapshot['tier'] == 'sol'
        db.get(Material, stage['material']).revision += 1
        assert not features_for(db, stage['child']['id'], stage['upcoming'])['study_length_failed']
        bound = job_config(db, db.get(Job, stage['upcoming']), 'unit')
        assert bound.model == usage.model and bound.max_output_tokens == 8000


def test_recorded_study_need_does_not_affect_other_provider_functions():
    assert choose_tier('coach', {'study_length_failed': True}, economy=True) == ('luna', 'bounded_source_or_review')
    assert choose_tier('extract', {'study_length_failed': True}, economy=True) == ('luna', 'bounded_source_or_review')
