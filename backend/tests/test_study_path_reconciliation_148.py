"""Synthetic regression: metadata upgrades, true source changes and saved origins."""
import copy
import hashlib
import json

import pytest
from schulpilot import providers, study_path
from schulpilot.db import DB, Attempt, Child, LearningUnit, Material, SchoolDay, UnitSource
from schulpilot.learning import plan
from schulpilot.learning_origins import next_item, open_rounds, round_days
from schulpilot.source_lineage import learning_source
from sqlalchemy import func, select
from test_study_path import create
from test_study_path import study as shared_study
from test_unit_multiples_common import binding_and_wire, prepared

study = shared_study


def legacy(db, items, policy):
    return hashlib.sha256(json.dumps([(m.id, m.revision, {**learning_source(db, m), 'policy_version': policy})
        for m in items], sort_keys=True).encode()).hexdigest()


@pytest.mark.parametrize('policy', ['literal-safety-1', 'literal-safety-2'])
def test_metadata_compatible_plan_is_readable_without_writes_and_keeps_block_ids(study, policy):
    create(study)
    with DB.begin() as db:
        day = db.get(SchoolDay, study['day_id'])
        day.learning_plan = {**day.learning_plan, 'source_hash': legacy(db, study_path.sources(db, day), policy)}
        original = copy.deepcopy(day.learning_plan)
    with DB() as db:
        day = db.get(SchoolDay, study['day_id'])
        assert study_path.plan_sources_current(db, day)
        assert not plan(db, db.get(Child, day.child_id))['blocked_study_paths']
        assert day.learning_plan == original
        assert not db.dirty
    with DB.begin() as db:
        day = db.get(SchoolDay, study['day_id'])
        revised = study_path.ensure_plan(db, day)
        assert revised['blocks'] == original['blocks']
        assert revised['fingerprint_version'] == 2
        assert revised['source_hash'] == study_path.fingerprint(study_path.sources(db, day), db)


@pytest.mark.parametrize('change', ['content', 'unreadable', 'revision'])
def test_content_and_quarantine_changes_still_invalidate_plan(study, change):
    create(study)
    with DB.begin() as db:
        page = db.get(Material, study['materials'][0])
        if change == 'content':
            page.content += '\nDer Mond kreist um die Erde.'
        elif change == 'unreadable':
            page.legibility = 'unreadable'
        else:
            page.revision += 1
        assert not study_path.plan_sources_current(db, db.get(SchoolDay, study['day_id']))


def test_related_rounds_use_own_single_day_sources_without_changing_anything(study):
    create(study)
    with DB.begin() as db:
        page = db.get(Material, study['materials'][0])
        unit = LearningUnit(child_id=page.child_id, material_id=page.id, subject='Sachunterricht',
            topic='Gezielt festigen', explanation='Künstliches Beispiel.', questions=[], provider='fixture',
            round_kind='repair')
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=page.id, revision=page.revision))
        identifier = unit.id
    with DB() as db:
        assert round_days(db, study['child']['id'])[identifier] == study['day_id']
        related = open_rounds(db, study['child']['id'], study['day_id'])
        assert related == [{'id': identifier, 'topic': 'Gezielt festigen', 'subject': 'Sachunterricht',
            'status': 'not_started', 'round_kind': 'repair'}]
        assert study_path.path_data(db, db.get(SchoolDay, study['day_id']), db.get(Child, study['child']['id']))['related_rounds'] == related
        assert not db.dirty and not db.new
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_ready_round_precedes_new_review_but_not_active_or_mandatory_work():
    review = {'kind':'review', 'id':'old', 'status':'not_started'}
    ready = {'kind':'unit', 'id':'ready', 'status':'not_started'}
    active = {'kind':'unit', 'id':'active', 'status':'paused'}
    mandatory = {'kind':'assignment', 'id':'goal', 'status':'not_started', 'mandatory':True}
    value = {'date':'2026-10-27', 'today':[review, ready], 'voluntary':[]}
    assert next_item(value) == ready
    value['today'].insert(0, mandatory)
    assert next_item(value) == mandatory
    value['voluntary'].append(active)
    assert next_item(value) == active


@pytest.mark.parametrize('count', [2, 4, 5])
def test_study_kgv_uses_same_arithmetic_and_graphic_proof(household, count):
    _, payload = prepared(household, count=count, entry=False)
    payload.pop('notebook_practice')
    payload['study_block'] = {'mode':'understand', 'question_count':count, 'tasks':[]}
    planned, schema, binding, wire = binding_and_wire(payload)
    actual = binding.hydrate(wire)
    assert len(actual['questions']) == count
    assert all(q['explanation_steps'][0]['presentation']['blocks'][0]['scene'] for q in actual['questions'])
    assert schema['properties']['questions']['minItems'] == count


@pytest.mark.parametrize('count', [2, 4])
def test_study_kgv_full_adapter_uses_fixed_graphics_once(household, monkeypatch, count):
    from test_notebook_fraction_expansions import http_mock
    from test_presentation_capability_paths import _config
    _, payload = prepared(household, count=count, entry=False)
    payload.pop('notebook_practice')
    payload['required_topic'] = 'Kleinstes gemeinsames Vielfaches'
    payload['study_block'] = {'mode':'understand', 'question_count':count, 'tasks':[]}
    _, _, binding, wire = binding_and_wire(payload)
    calls = []
    http_mock(monkeypatch, wire, calls)
    config = _config('openrouter')
    config.max_output_tokens, config.reserve_micros = 8000, 250000
    config.input_per_million_micros, config.output_per_million_micros = 2000000, 10000000
    result = providers.request_provider(config, 'unit', payload)
    assert len(calls) == 1
    sent = json.loads(calls[0]['messages'][1]['content'][0]['text'])
    assert sent['content_context']['max_blocks'] == 1
    assert len(result.data['questions']) == count
    assert all(q['explanation_steps'][0]['presentation']['blocks'][0]['scene'] for q in result.data['questions'])
