"""Explicit same-photo OCR rechecks use recorded reading difficulty, no AI calls."""
from copy import deepcopy

import pytest
from conftest import create_child
from fastapi import HTTPException
from schulpilot import material_actions
from schulpilot.db import DB, Attempt, Family, Job, LearningUnit, Material, ProviderConfig, Session, Usage, uid
from schulpilot.job_failures import generation_availability
from schulpilot.model_routing import choose_tier, extraction_recheck, features_for, job_config
from schulpilot.providers import ProviderError, reserve
from sqlalchemy import func, select
from sqlalchemy.orm.attributes import flag_modified
from test_model_routing import setup_policy
from test_notebook_actions import photo, saved_round


@pytest.fixture
def recheck(api, household, monkeypatch):
    parent, child = household
    family_id = parent['families'][0]['id']
    setup_policy(family_id)
    monkeypatch.setattr('schulpilot.providers.request_provider',
        lambda *a, **kw: pytest.fail('No provider may run in a routing test'))
    with DB.begin() as db:
        cfg = db.get(ProviderConfig, 1)
        cfg.reserve_micros, cfg.max_output_tokens = 500000, 8000
        cfg.routing_policy = {**cfg.routing_policy, 'economy_mode': True, 'routes': {
            tier: {**route, 'reserve_micros': 150000 if tier == 'luna' else 250000,
                   'max_output_tokens': 4000 if tier == 'luna' else 8000}
            for tier, route in cfg.routing_policy['routes'].items()}}
        source = Material(child_id=child['id'], title='PUBLIC SYNTHETIC original', revision=2,
            image_digest='e' * 64, content='Ein kurzer künstlicher Lesetext.',
            legibility='partial', uncertainties=['Eine künstliche Lesestelle ist unklar.'],
            confirmed=True, status='confirmed')
        clone = Material(child_id=child['id'], title='PUBLIC SYNTHETIC recheck', image_digest='e' * 64)
        db.add_all([source, clone])
        db.flush()
        session_id = db.scalar(select(Session.id).where(Session.user_id == parent['id']))
        guard = {'source_id': source.id, 'source_revision': source.revision, 'family_id': family_id,
                 'user_id': parent['id'], 'session_id': session_id}
        job = Job(child_id=child['id'], kind='extract', idempotency=uid(), payload={
            'material_id': clone.id, 'material_revision': clone.revision, 'reprocess_guard': guard})
        db.add(job)
        db.flush()
        return {'parent': parent, 'child': child, 'family': family_id,
                'source': source.id, 'clone': clone.id, 'job': job.id}


def test_recheck_preflight_and_normal_reservation_use_recorded_original_without_copying_it(recheck):
    with DB.begin() as db:
        source, clone = db.get(Material, recheck['source']), db.get(Material, recheck['clone'])
        cfg, job = db.get(ProviderConfig, 1), db.get(Job, recheck['job'])
        before = deepcopy(cfg.routing_policy)
        facts = features_for(db, recheck['child']['id'], job.id)
        assert not facts['poor_image'] and not facts['extraction_failed']
        assert clone.uncertainties == [] and clone.legibility == 'unknown' and clone.content == ''
        assert source.legibility == 'partial' and source.uncertainties
        assert facts['transcription_review']
        assert choose_tier('extract', facts, economy=True) == ('sol', 'recorded_transcription_review')
        # This is the former clone-only behavior: no recorded original feature.
        assert choose_tier('extract', {**facts, 'transcription_review': False}, economy=True) == (
            'luna', 'bounded_source_or_review')
        assert generation_availability(db, db.get(Family, recheck['family']), 'extract',
            child_id=recheck['child']['id'], job_id=job.id) is None
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert not db.new and not db.dirty
        usage = reserve(db, db.get(Family, recheck['family']), recheck['child']['id'], job.id, 'extract')
        assert usage.route_snapshot['tier'] == 'sol'
        assert usage.route_snapshot['reason'] == 'recorded_transcription_review'
        assert usage.reserved_micros == 250000 and usage.model == before['routes']['sol']['model']
        selected = job_config(db, job)
        assert selected.max_output_tokens == 8000 and selected.reserve_micros == 250000
        assert selected.reasoning_effort == 'medium' and cfg.routing_policy == before
        assert cfg.max_output_tokens == 8000 and cfg.reserve_micros == 500000
        assert source.confirmed and source.revision == 2
        assert not clone.confirmed and clone.content == '' and clone.legibility == 'unknown'
        assert job.status == 'queued' and db.scalar(select(func.count()).select_from(Job)) == 1


@pytest.mark.parametrize('legibility,uncertainties', [
    ('partial', []), ('unreadable', ['Synthetic unreadable word.']), ('readable', ['Synthetic ambiguous word.']),
])
def test_only_recorded_reading_metadata_is_needed(recheck, legibility, uncertainties):
    with DB.begin() as db:
        source = db.get(Material, recheck['source'])
        source.legibility, source.uncertainties = legibility, uncertainties
    with DB() as db:
        assert features_for(db, recheck['child']['id'], recheck['job'])['transcription_review']
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


@pytest.mark.parametrize('fault', [
    'missing_guard', 'malformed_guard', 'missing_source_id', 'missing_source_revision', 'boolean_source_revision',
    'stale_source', 'stale_clone', 'boolean_clone_revision', 'same_source', 'foreign_source', 'foreign_clone',
    'deleted_source', 'deleted_clone', 'different_image', 'empty_image', 'missing_image',
    'source_fixture', 'clone_fixture', 'source_synthetic', 'clone_synthetic', 'source_purpose', 'clone_purpose',
    'nonextract', 'running', 'no_reading_difficulty',
])
def test_recheck_fact_rejects_invalid_owner_revision_image_or_explicit_job_binding(api, recheck, fault):
    sibling = create_child(api, recheck['parent'], 'ocr-recheck-sibling') if fault.startswith('foreign') else None
    with DB.begin() as db:
        source, clone = db.get(Material, recheck['source']), db.get(Material, recheck['clone'])
        job = db.get(Job, recheck['job'])
        data, guard = deepcopy(job.payload), deepcopy(job.payload['reprocess_guard'])
        if fault == 'missing_guard':
            data.pop('reprocess_guard')
        elif fault == 'malformed_guard':
            data['reprocess_guard'] = ['not a server guard']
        elif fault == 'missing_source_id':
            guard.pop('source_id')
        elif fault == 'missing_source_revision':
            guard.pop('source_revision')
        elif fault == 'boolean_source_revision':
            guard['source_revision'] = True
        elif fault == 'stale_source':
            source.revision += 1
        elif fault == 'stale_clone':
            clone.revision += 1
        elif fault == 'boolean_clone_revision':
            data['material_revision'] = True
        elif fault == 'same_source':
            data.update(material_id=source.id, material_revision=source.revision)
        elif fault == 'foreign_source':
            source.child_id = sibling['id']
        elif fault == 'foreign_clone':
            clone.child_id = sibling['id']
        elif fault == 'deleted_source':
            db.delete(source)
        elif fault == 'deleted_clone':
            db.delete(clone)
        elif fault == 'different_image':
            clone.image_digest = 'a' * 64
        elif fault == 'empty_image':
            source.image_digest = clone.image_digest = ''
        elif fault == 'missing_image':
            source.image_digest = clone.image_digest = None
        elif fault in ('source_fixture', 'clone_fixture'):
            (source if fault == 'source_fixture' else clone).fixture_id = 'fixed-synthetic-template'
        elif fault in ('source_synthetic', 'clone_synthetic'):
            (source if fault == 'source_synthetic' else clone).synthetic = True
        elif fault in ('source_purpose', 'clone_purpose'):
            (source if fault == 'source_purpose' else clone).purpose = 'exam'
        elif fault == 'nonextract':
            job.kind = 'unit'
        elif fault == 'running':
            job.status = 'running'
        elif fault == 'no_reading_difficulty':
            source.legibility, source.uncertainties = 'readable', []
        if fault not in ('missing_guard', 'malformed_guard'):
            data['reprocess_guard'] = guard
        job.payload = data
        if fault == 'boolean_clone_revision':
            # JSON equality otherwise treats True == the old integer1 as unchanged.
            flag_modified(job, 'payload')
    with DB() as db:
        job = db.get(Job, recheck['job'])
        assert not extraction_recheck(db, recheck['child']['id'], job)
        if fault == 'foreign_clone':
            with pytest.raises(HTTPException) as denied:
                features_for(db, recheck['child']['id'], job.id)
            assert denied.value.status_code == 403
        else:
            assert not features_for(db, recheck['child']['id'], job.id)['transcription_review']
        assert not db.new and not db.dirty
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_client_route_request_without_reprocess_guard_cannot_select_sol(recheck):
    with DB.begin() as db:
        job = db.get(Job, recheck['job'])
        job.payload = {key: value for key, value in job.payload.items() if key != 'reprocess_guard'} | {
            'model': 'openai/gpt-6.1-sol', 'tier': 'sol', 'transcription_review': True}
    with DB() as db:
        facts = features_for(db, recheck['child']['id'], recheck['job'])
        assert not facts['transcription_review']
        assert choose_tier('extract', facts, economy=True) == ('luna', 'bounded_source_or_review')


def test_normal_higher_route_budget_still_applies(recheck):
    with DB.begin() as db:
        db.get(Family, recheck['family']).budget_micros = 200000
    with DB() as db:
        assert generation_availability(db, db.get(Family, recheck['family']), 'extract',
            child_id=recheck['child']['id'], job_id=recheck['job'])['code'] == 'quota_exhausted'
        with pytest.raises(HTTPException) as denied:
            reserve(db, db.get(Family, recheck['family']), recheck['child']['id'], recheck['job'], 'extract')
        assert denied.value.status_code == 429
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_reservation_stays_bound_and_worker_rejects_changed_original(recheck):
    with DB.begin() as db:
        job = db.get(Job, recheck['job'])
        usage = reserve(db, db.get(Family, recheck['family']), recheck['child']['id'], job.id, 'extract')
        snapshot = deepcopy(usage.route_snapshot)
        db.get(Material, recheck['source']).revision += 1
        usage_id = usage.id
    with DB() as db:
        job = db.get(Job, recheck['job'])
        assert not features_for(db, recheck['child']['id'], job.id)['transcription_review']
        assert job_config(db, job).model == snapshot['route']['model']
        assert db.get(Usage, usage_id).route_snapshot == snapshot
        with pytest.raises(ProviderError, match='ursprüngliche Heftseite'):
            material_actions.validate_reprocess_job(db, job)
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_actual_reprocess_api_keeps_original_answers_and_idempotent_existing_reservation(api, recheck):
    child = recheck['child']
    # The manually planned fixture job is not an actual user request.
    with DB.begin() as db:
        db.delete(db.get(Job, recheck['job']))
    source_id, original_file = photo(api, child)
    with DB.begin() as db:
        source = db.get(Material, source_id)
        source.legibility, source.uncertainties, source.quality_warnings = 'partial', ['Synthetic unclear word.'], []
        before = (source.revision, source.confirmed, source.content, source.status, source.uncertainties)
    unit_id, attempt_id = saved_round(child, source_id)
    headers = {'Idempotency-Key': 'recorded-partial-recheck-api'}
    response = api.post(f'/api/materials/{source_id}/reprocess', json={'revision': before[0]}, headers=headers)
    assert response.status_code == 202, response.text
    result = response.json()
    assert api.post(f'/api/materials/{source_id}/reprocess', json={'revision': before[0]}, headers=headers).json() == result
    with DB() as db:
        source, clone = db.get(Material, source_id), db.get(Material, result['material_id'])
        assert (source.revision, source.confirmed, source.content, source.status, source.uncertainties) == before
        assert source.image_digest == clone.image_digest and source.path != clone.path
        assert clone.legibility == 'unknown' and clone.uncertainties == [] and not clone.confirmed
        assert clone.content == '' and clone.quality_warnings == []
        facts = features_for(db, child['id'], result['id'])
        assert not facts['poor_image'] and facts['transcription_review']
        usage = db.scalar(select(Usage).where(Usage.job_id == result['id']))
        assert usage.route_snapshot['tier'] == 'sol' and usage.route_snapshot['reason'] == 'recorded_transcription_review'
        assert usage.reserved_micros == 250000 and db.scalar(select(func.count()).select_from(Usage)) == 1
        assert db.get(LearningUnit, unit_id).material_id == source_id
        assert db.get(Attempt, attempt_id).answer == 'synthetic stored answer'
        assert original_file.is_file()
        material_actions.validate_reprocess_job(db, db.get(Job, result['id']))
