"""Artificial source erasure also covers planned, not-yet-generated stages."""

import copy

import pytest
from schulpilot.db import DB, Activity, Child, Job, LearningUnit, Material, SchoolDay, Usage, now
from schulpilot.erasure import reconcile
from schulpilot.learning import local_day
from schulpilot.source_cleanup import apply, selection
from schulpilot.worker import maintenance
from sqlalchemy import func, select
from test_notebook_actions import confirm_delete, photo, preview, saved_round


def plan_fixture(api, child):
    kept, _ = photo(api, child)
    removed, _ = photo(api, child)
    unit_id, _ = saved_round(child, kept)
    with DB.begin() as db:
        day = SchoolDay(child_id=child['id'], school_date=local_day(db.get(Child, child['id'])).isoformat(), stage='ready')
        db.add(day)
        db.flush()
        for mid in [kept, removed]:
            material = db.get(Material, mid)
            material.school_day_id = day.id
            material.confirmed = True
        db.get(LearningUnit, unit_id).school_day_id = day.id
        blocks = [
            {'id': 'kept', 'title': 'Valid planned stage', 'material_ids': [kept]},
            {'id': 'removed', 'title': 'Orphan planned stage', 'material_ids': [removed]},
            {'id': 'mixed', 'title': 'Incomplete source group', 'material_ids': [kept, removed]},
            {'id': 'saved', 'title': 'Saved answers', 'unit_id': unit_id},
        ]
        day.learning_plan = {'version': 1, 'source_hash': 'old-source-hash', 'blocks': [
            {'phase': 'apply', 'label': 'Anwenden', 'question_count': 2, 'subject': 'Mathematik',
             'unit_id': None, 'job_id': None, **b} for b in blocks]}
        day_id = day.id
    return kept, removed, unit_id, day_id


def test_page_deletion_discards_only_unbacked_unmade_stages(api, household):
    _, child = household
    kept, removed, unit, day = plan_fixture(api, child)
    result = confirm_delete(api, child, preview(api, child, ids=[removed])['selection_token'])
    assert result.status_code == 200, result.text
    with DB() as db:
        assert {b['id'] for b in db.get(SchoolDay, day).learning_plan['blocks']} == {'kept', 'saved'}
        assert db.get(Material, kept) and db.get(LearningUnit, unit)


def test_legacy_orphan_plans_are_hidden_without_get_writes(api, household):
    _, child = household
    _, removed, unit, day = plan_fixture(api, child)
    with DB.begin() as db:
        db.delete(db.get(Material, removed))
    with DB() as db:
        before = copy.deepcopy(db.get(SchoolDay, day).learning_plan)
        counts = [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)]
    overview = api.get(f"/api/children/{child['id']}/overview?compact=true").json()
    listing = api.get(f"/api/children/{child['id']}/learning?page_size=50").json()
    path = api.get(f'/api/school-days/{day}/study-path').json()
    for items in [overview['plan']['today'], overview['plan']['later'], overview['plan']['voluntary'], listing['items']]:
        assert not any(item.get('block_id') in {'removed', 'mixed'} for item in items)
    assert {b['id'] for b in path['blocks']} == {'kept', 'saved'}
    assert path['stale'] is True
    with DB() as db:
        assert db.get(SchoolDay, day).learning_plan == before
        assert [db.scalar(select(func.count()).select_from(model)) for model in (Job, Usage, Activity)] == counts
        assert db.get(LearningUnit, unit)


@pytest.mark.parametrize('changed', [False, True])
def test_operator_plan_cleanup_is_counted_and_snapshot_bound(api, household, changed):
    _, child = household
    _, removed, unit, day_id = plan_fixture(api, child)
    with DB.begin() as db:
        db.delete(db.get(Material, removed))
    with DB() as db:
        picked = selection(db, child['id'])
        assert picked['planned_stage_count'] == 2 and picked['unit_count'] == 0
    if changed:
        with DB.begin() as db:
            db.get(SchoolDay, day_id).revision += 1
    with DB.begin() as db:
        if changed:
            with pytest.raises(ValueError):
                apply(db, child['id'], picked['digest'])
            assert len(db.get(SchoolDay, day_id).learning_plan['blocks']) == 4
        else:
            result = apply(db, child['id'], picked['digest'])
            assert result['planned_stage_count'] == 2
            assert {b['id'] for b in db.get(SchoolDay, day_id).learning_plan['blocks']} == {'kept', 'saved'}
        assert db.get(LearningUnit, unit)


@pytest.mark.parametrize('route', ['retention', 'restore'])
def test_non_ui_erasure_discards_unmade_stages_as_well(api, household, route):
    _, child = household
    _, removed, unit, day_id = plan_fixture(api, child)
    if route == 'retention':
        with DB.begin() as db:
            db.get(Material, removed).created = int(now()) - 366 * 86400
        maintenance()
    else:
        with DB.begin() as db:
            reconcile(db, [{'scope': 'material', 'target': removed}])
    with DB() as db:
        assert db.get(Material, removed) is None
        assert {b['id'] for b in db.get(SchoolDay, day_id).learning_plan['blocks']} == {'kept', 'saved'}
        assert db.get(LearningUnit, unit)
