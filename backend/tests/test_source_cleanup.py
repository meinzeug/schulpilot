"""Operator and restore cleanup uses only artificial, isolated household data."""

import pytest
from fastapi import HTTPException
from schulpilot.db import DB, Assignment, Attempt, Audit, Job, LearningUnit, Material, UnitSource, VocabularyItem, now
from schulpilot.erasure import reconcile
from schulpilot.source_cleanup import apply, selection
from schulpilot.worker import maintenance
from sqlalchemy import select
from test_notebook_actions import photo, saved_round


def test_preview_apply_retains_valid_heft_roots_and_manual_words(api, household):
    _, child = household
    mid, _ = photo(api, child)
    valid, _ = saved_round(child, mid)
    detached, old_answer = saved_round(child, mid)
    follow, _ = saved_round(child, mid)
    vocab, _ = saved_round(child, mid)
    with DB.begin() as db:
        for unit_id in (detached, follow, vocab):
            db.get(LearningUnit, unit_id).material_id = None
            db.delete(db.get(UnitSource, (unit_id, mid)))
        db.get(LearningUnit, follow).followup_of = valid
        word = VocabularyItem(child_id=child['id'], identity='word-key', target_locale='en-GB',
                              word='synthetic', meaning='künstlich', origin='manual', confirmed=True)
        db.add(word)
        db.flush()
        row = db.get(LearningUnit, vocab)
        row.round_kind = 'vocabulary'
        row.questions = [{'id': 'synthetic-question', 'language': {'vocabulary_item_id': word.id}}]
        goal = Assignment(child_id=child['id'], kind='parent', subject='Mathematik', topic='Künstliches Ziel')
        db.add(goal)
        db.flush()
        linked_goal = Assignment(child_id=child['id'], kind='parent', subject='Mathematik', topic='Ziel mit indirekter Heftquelle')
        db.add(linked_goal)
        db.flush()
        db.get(LearningUnit, valid).assignment_id = linked_goal.id
        goal_id = goal.id
        db.add(Job(child_id=child['id'], kind='unit', status='completed', payload={'assignment_id': goal_id},
                   result={'assignment_id': goal_id}, idempotency='erased-order-job'))
    with DB.begin() as db:
        default = selection(db, child['id'])
        assert default['unit_ids'] == [detached] and default['assignment_count'] == 0
        picked = selection(db, child['id'], include_manual_assignments=True)
        assert picked['assignment_ids'] == [goal_id]
        result = apply(db, child['id'], picked['digest'], include_manual_assignments=True)
        assert result == {'unit_count': 1, 'answer_count': 1, 'assignment_count': 1, 'planned_stage_count': 0}
    with DB() as db:
        assert db.get(Attempt, old_answer) is None
        assert db.get(LearningUnit, valid) and db.get(LearningUnit, follow) and db.get(LearningUnit, vocab)
        assert db.get(Assignment, goal_id) is None
        assert db.scalar(select(Job).where(Job.idempotency == 'erased-order-job')).result == {'deleted': True}
        assert db.scalar(select(Audit).where(Audit.action == 'operator.source_orphans_removed'))


def test_changed_or_busy_cleanup_never_deletes(api, household):
    _, child = household
    mid, _ = photo(api, child)
    unit, answer = saved_round(child, mid)
    with DB.begin() as db:
        db.delete(db.get(Material, mid))
    with DB() as db:
        preview = selection(db, child['id'])
    with DB.begin() as db:
        db.get(Attempt, answer).answer = 'Another artificial answer'
    with DB.begin() as db:
        with pytest.raises(ValueError):
            apply(db, child['id'], preview['digest'])
        assert db.get(LearningUnit, unit)
        db.add(Job(child_id=child['id'], kind='unit', status='running', payload={}, idempotency='busy-orphan'))
    with DB.begin() as db:
        current = selection(db, child['id'])
        with pytest.raises(HTTPException) as error:
            apply(db, child['id'], current['digest'])
        assert error.value.status_code == 409
        assert db.get(LearningUnit, unit)


def test_old_page_only_restore_journal_also_erases_rounds(api, household):
    _, child = household
    mid, _ = photo(api, child)
    root, attempt = saved_round(child, mid)
    follow, _ = saved_round(child, mid)
    with DB.begin() as db:
        db.get(LearningUnit, follow).followup_of = root
        db.get(LearningUnit, follow).material_id = None
        db.delete(db.get(UnitSource, (follow, mid)))
        reconcile(db, [{'scope': 'material', 'target': mid}])
        reconcile(db, [{'scope': 'material', 'target': mid}])
    with DB() as db:
        assert db.get(LearningUnit, root) is None and db.get(LearningUnit, follow) is None
        assert db.get(Attempt, attempt) is None


def test_assignment_restore_journal_is_idempotent_and_child_scoped(api, household):
    _, child = household
    with DB.begin() as db:
        one = Assignment(child_id=child['id'], kind='parent', subject='Mathematik', topic='Künstliches Ziel')
        two = Assignment(child_id=child['id'], kind='parent', subject='Deutsch', topic='Anderes künstliches Ziel')
        db.add_all([one, two])
        db.flush()
        ids = one.id, two.id
        reconcile(db, [{'scope': 'assignment', 'target': one.id}])
        reconcile(db, [{'scope': 'assignment', 'target': one.id}])
    with DB() as db:
        assert db.get(Assignment, ids[0]) is None and db.get(Assignment, ids[1]) is not None
    from schulpilot.config import settings
    from schulpilot.erasure import flush_journal, request, verify
    with DB.begin() as db:
        request(db, 'assignment', ids[1])
    flush_journal()
    records = [verify(raw, settings.master_key) for raw in (settings.data_dir/'erasure-ledger.jsonl').read_text().splitlines()]
    record = next(r for r in records if r['target'] == ids[1])
    assert record['scope'] == 'unit' and record['resource_kind'] == 'assignment'
    with DB.begin() as db:
        reconcile(db, records)
    with DB() as db:
        assert db.get(Assignment, ids[1]) is None


def test_retention_removes_newer_rounds_of_expired_pages(api, household):
    _, child = household
    mid, _ = photo(api, child)
    unit, answer = saved_round(child, mid)
    with DB.begin() as db:
        db.get(Material, mid).created = int(now()) - 366 * 86400
    maintenance()
    with DB() as db:
        assert db.get(Material, mid) is None
        assert db.get(LearningUnit, unit) is None and db.get(Attempt, answer) is None


def test_legacy_word_round_binding_uses_its_saved_revision(api, household):
    from schulpilot.unit_erasure import linked_ids

    _, child = household
    old, _ = photo(api, child)
    current, _ = photo(api, child)
    old_round, _ = saved_round(child, current)
    new_round, _ = saved_round(child, current)
    with DB.begin() as db:
        word = VocabularyItem(child_id=child['id'], identity='word-history-key', target_locale='en-GB',
            word='synthetic', meaning='künstlich', origin='material', confirmed=True, revision=2,
            source_revisions=[{'id': current, 'revision': 1}],
            history=[{'revision': 1, 'source_revisions': [{'id': old, 'revision': 1}]}])
        db.add(word)
        db.flush()
        for uid, revision in [(old_round, 1), (new_round, 2)]:
            unit = db.get(LearningUnit, uid)
            unit.material_id, unit.round_kind = None, 'vocabulary'
            unit.questions = [{'id': 'synthetic-question', 'language': {
                'vocabulary_item_id': word.id, 'vocabulary_revision': revision}}]
            db.delete(db.get(UnitSource, (uid, current)))
        assert linked_ids(db, child['id'], [old]) == [old_round]
        assert linked_ids(db, child['id'], [current]) == [new_round]


def test_legacy_order_and_project_source_snapshots_are_in_page_cascade(api, household):
    from schulpilot.db import Child, LanguageProject
    from schulpilot.unit_erasure import linked_ids

    _, child = household
    mid, _ = photo(api, child)
    order_unit, _ = saved_round(child, mid)
    project_unit, _ = saved_round(child, mid)
    with DB.begin() as db:
        order = Assignment(child_id=child['id'], kind='parent', subject='Mathematik', topic='Künstlicher Auftrag',
                           source_revisions=[{'id': mid, 'revision': 1}])
        db.add(order)
        db.flush()
        db.get(LearningUnit, order_unit).assignment_id = order.id
        for unit_id in [order_unit, project_unit]:
            db.get(LearningUnit, unit_id).material_id = None
            db.delete(db.get(UnitSource, (unit_id, mid)))
        db.add(LanguageProject(child_id=child['id'], user_id=db.get(Child, child['id']).user_id,
            request_key='legacy-project-binding', request_digest='a'*64, target_locale='en-GB', mode='dialog', inputs={},
            source_revisions=[{'id': mid, 'revision': 1}], unit_id=project_unit, status='ready'))
        db.flush()
        assert set(linked_ids(db, child['id'], [mid])) == {order_unit, project_unit}
