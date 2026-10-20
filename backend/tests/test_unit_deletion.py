"""Synthetic-only round erasure, counted confirmation and restore safety."""

import pytest
from conftest import create_child
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Activity,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Mastery,
    Material,
    SchoolDay,
    UnitSource,
    Usage,
)
from schulpilot.erasure import reconcile, verify
from sqlalchemy import select
from test_notebook_actions import confirm_delete, kid, photo, preview, saved_round


def unit_preview(client, unit):
    response = client.post(f"/api/units/{unit}/delete-preview", json={})
    assert response.status_code == 200, response.text
    return response.json()


def remove(client, unit, token):
    return client.post(f"/api/units/{unit}/delete", json={"selection_token": token})


def test_unit_delete_preserves_photo_other_round_and_usage(api, household):
    _, child = household
    mid, path = photo(api, child)
    unit, attempt = saved_round(child, mid)
    keep, _ = saved_round(child, mid)
    with DB.begin() as db:
        day = SchoolDay(
            child_id=child["id"],
            school_date="2026-10-20",
            learning_plan={"blocks": [{"id": "removed", "unit_id": unit}, {"id": "kept", "unit_id": keep}]},
        )
        db.add(day)
        job = Job(
            child_id=child["id"],
            kind="unit",
            status="completed",
            idempotency="unit-delete-test",
            payload={"unit_id": unit},
            result={"unit_id": unit},
        )
        db.add(job)
        db.flush()
        job_id, day_id = job.id, day.id
    with kid() as client:
        data = unit_preview(client, unit)
        assert data["unit_count"] == data["answer_count"] == 1
        assert remove(client, unit, data["selection_token"]).json() == {"deleted_count": 1}
        assert remove(client, unit, data["selection_token"]).status_code == 404
        assert client.get(f"/api/units/{unit}").status_code == 404
    with DB() as db:
        assert db.get(Attempt, attempt) is None
        assert db.get(LearningUnit, keep) is not None
        assert db.get(Material, mid) is not None and path.exists()
        assert db.get(SchoolDay, day_id).learning_plan["blocks"] == [{"id": "kept", "unit_id": keep}]
        assert db.get(Job, job_id).result == {"deleted": True}
        assert db.get(Job, job_id).idempotency == "unit-delete-test"
        assert not list(db.scalars(select(Usage)))
    records = [
        verify(line, settings.master_key)
        for line in (settings.data_dir / "erasure-ledger.jsonl").read_text().splitlines()
    ]
    assert any(r["scope"] == "unit" and r["target"] == unit for r in records)


@pytest.mark.parametrize("change", ["answer", "activity", "unit", "job"])
def test_round_changed_after_preview_rejected_without_partial_delete(api, household, change):
    _, child = household
    mid, _ = photo(api, child)
    unit, attempt = saved_round(child, mid)
    data = unit_preview(api, unit)
    with DB.begin() as db:
        if change == "answer":
            db.get(Attempt, attempt).answer = "changed synthetic answer"
        elif change == "activity":
            db.add(Activity(child_id=child["id"], unit_id=unit, kind="hint"))
        elif change == "unit":
            db.get(LearningUnit, unit).status = "paused"
        else:
            db.add(
                Job(
                    child_id=child["id"],
                    kind="coach",
                    status="queued",
                    payload={"unit_id": unit},
                    idempotency="new-busy-job",
                )
            )
    assert remove(api, unit, data["selection_token"]).status_code == 409
    with DB() as db:
        assert db.get(LearningUnit, unit) is not None and db.get(Attempt, attempt) is not None


def test_round_token_cannot_cross_session_or_round(api, household):
    _, child = household
    mid, _ = photo(api, child)
    one, _ = saved_round(child, mid)
    two, _ = saved_round(child, mid)
    token = unit_preview(api, one)["selection_token"]
    assert remove(api, two, token).status_code == 409
    with kid() as client:
        assert remove(client, one, token).status_code == 409


def test_sibling_cannot_delete(api, household):
    owner, child = household
    sibling = create_child(api, owner, "delete-sibling")
    mid, _ = photo(api, sibling)
    unit, _ = saved_round(sibling, mid)
    with kid() as client:
        assert client.post(f"/api/units/{unit}/delete-preview", json={}).status_code == 404


def test_parent_permission_revoked_after_preview_blocks_round_deletion(api, household):
    from schulpilot.db import Membership

    owner, child = household
    mid, _ = photo(api, child)
    unit, _ = saved_round(child, mid)
    token = unit_preview(api, unit)["selection_token"]
    with DB.begin() as db:
        db.scalar(select(Membership).where(Membership.user_id == owner["id"])).permission = "view"
    assert remove(api, unit, token).status_code == 403
    assert api.post(f"/api/units/{unit}/delete-preview", json={}).status_code == 403


def test_round_deletion_keeps_financial_reservation_and_rebuilds_progress(api, household):
    _, child = household
    mid, _ = photo(api, child)
    unit, _ = saved_round(child, mid)
    with DB.begin() as db:
        row = db.get(LearningUnit, unit)
        db.add(
            Mastery(
                child_id=child["id"],
                subject=row.subject,
                topic=row.topic,
                independent=4,
                next_review="2026-10-21",
                last_practiced="2026-10-20",
            )
        )
        usage = Usage(
            family_id=db.get(Child, child["id"]).family_id,
            child_id=child["id"],
            job_id="a" * 32,
            provider="synthetic",
            model="test",
            config_revision=1,
            function="unit",
            status="completed",
            reserved_micros=100,
            cost_micros=None,
            bucket_ids=[],
        )
        db.add(usage)
        db.flush()
        usage_id = usage.id
    token = unit_preview(api, unit)["selection_token"]
    assert remove(api, unit, token).status_code == 200
    with DB() as db:
        assert not list(db.scalars(select(Mastery)))
        usage = db.get(Usage, usage_id)
        assert usage.reserved_micros == 100 and usage.cost_micros is None


def test_unit_scope_restore_replay_is_idempotent_and_removes_derived_rows(api, household):
    _, child = household
    mid, _ = photo(api, child)
    unit, _ = saved_round(child, mid)
    with DB.begin() as db:
        row = db.get(LearningUnit, unit)
        db.add(
            Mastery(
                child_id=child["id"],
                subject=row.subject,
                topic=row.topic,
                independent=1,
                next_review="2026-10-21",
                last_practiced="2026-10-20",
            )
        )
        records = [{"scope": "unit", "target": unit}]
        reconcile(db, records)
        reconcile(db, records)
    with DB() as db:
        assert not list(db.scalars(select(Mastery)))
        assert db.get(Material, mid) is not None


def test_round_erasure_keeps_later_language_step_and_erases_old_project_content(api, household):
    from schulpilot.db import LanguageProject
    from schulpilot.language_projects import project_data

    _, child = household
    mid, _ = photo(api, child)
    unit, _ = saved_round(child, mid)
    later, _ = saved_round(child, mid)
    with DB.begin() as db:
        user_id = db.get(Child, child['id']).user_id
        first = LanguageProject(child_id=child['id'], user_id=user_id, request_key='first-language-key',
            request_digest='a' * 64, target_locale='en-GB', mode='dialog', unit_id=unit,
            inputs={'goal': 'Artificial goal', 'draft': 'Artificial private draft', 'item_ids': [], 'grammar_topic': None},
            result={'response': 'Artificial response'}, status='ready')
        db.add(first)
        db.flush()
        second = LanguageProject(child_id=child['id'], user_id=user_id, request_key='second-language-key',
            request_digest='b' * 64, target_locale='en-GB', mode='dialog', previous_id=first.id, unit_id=later,
            inputs={'goal': 'Artificial goal', 'draft': 'Second artificial draft', 'item_ids': [], 'grammar_topic': None},
            result={'response': 'Second response'}, status='ready', step=2)
        db.add(second)
        db.flush()
        first_id, second_id = first.id, second.id
    token = unit_preview(api, unit)['selection_token']
    assert remove(api, unit, token).status_code == 200
    with DB() as db:
        first, second = db.get(LanguageProject, first_id), db.get(LanguageProject, second_id)
        assert first.request_key == 'first-language-key'
        data = project_data(db, first)
        assert data['draft'] == '' and data['result'] is None and data['can_retry'] is False
        assert second.status == 'ready' and second.result['response'] == 'Second response'
        assert db.get(LearningUnit, later) is not None


def test_material_cascade_includes_legacy_followups_and_shared_source_round(api, household):
    _, child = household
    mid, _ = photo(api, child)
    other, path = photo(api, child)
    root, _ = saved_round(child, mid)
    shared, _ = saved_round(child, other)
    follow, attempt = saved_round(child, other)
    with DB.begin() as db:
        db.add(UnitSource(unit_id=shared, material_id=mid, revision=1))
        db.get(LearningUnit, follow).followup_of = root
    data = preview(api, child, ids=[mid])
    assert data["unit_count"] == data["answer_count"] == 3
    assert (
        api.post(
            f"/api/children/{child['id']}/materials/bulk-delete", json={"selection_token": data["selection_token"]}
        ).status_code
        == 409
    )
    assert confirm_delete(api, child, data["selection_token"]).status_code == 200
    with DB() as db:
        assert not list(db.scalars(select(LearningUnit)))
        assert db.get(Attempt, attempt) is None
        assert db.get(Material, other) is not None and path.exists()


def test_new_attempt_after_material_preview_blocks_cascade(api, household):
    _, child = household
    mid, path = photo(api, child)
    unit, attempt = saved_round(child, mid)
    data = preview(api, child, ids=[mid])
    with DB.begin() as db:
        db.get(Attempt, attempt).outcome = "incorrect"
    assert confirm_delete(api, child, data["selection_token"]).status_code == 409
    assert path.exists()


def test_restore_unit_scope_cannot_resurrect_deleted_evidence(api, household):
    _, child = household
    mid, _ = photo(api, child)
    unit, attempt = saved_round(child, mid)
    with DB.begin() as db:
        db.add(
            Mastery(
                child_id=child["id"],
                subject="Mathematik",
                topic="Brüche",
                independent=7,
                next_review="2026-10-21",
                last_practiced="2026-10-20",
            )
        )
        reconcile(db, [{"scope": "unit", "target": unit}])
    with DB() as db:
        assert db.get(LearningUnit, unit) is None and db.get(Attempt, attempt) is None
        assert db.get(Child, child["id"]) is not None and db.get(Material, mid) is not None
