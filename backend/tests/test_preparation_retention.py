"""Synthetic-only month boundary regression; no provider calls or retry resets."""
import copy

import pytest
from schulpilot.db import DB, Child, Job, Material, SchoolDay, Usage, User, now
from schulpilot.preparation_retention import purge
from sqlalchemy import select


def records(household, *, status="failed", age=100):
    user, child = household
    with DB.begin() as db:
        day = SchoolDay(child_id=child["id"], school_date="2026-01-01", stage="review")
        db.add(day)
        db.flush()
        job = Job(child_id=child["id"], kind="package", status="failed", idempotency="old-current",
                  created=int(now()) - age * 86400,
                  payload={"school_day_id": day.id, "package_plan_digest": "same-plan"})
        db.add(job)
        db.flush()
        day.preparation = {"status": status, "job_id": job.id, "package_plan": {"digest": "same-plan"},
                           "package_part_attempts": {"same-plan:0": 2}, "error": "Artificial failure"}
        usage = Usage(family_id=user["families"][0]["id"], child_id=child["id"], job_id=job.id,
                      function="package", provider="synthetic", model="fixed", config_revision=1,
                      status="failed_billed", reserved_micros=100, cost_micros=10, bucket_ids=[],
                      created=job.created)
        db.add(usage)
        db.flush()
        return day.id, job.id, usage.id, copy.deepcopy(day.preparation)


@pytest.mark.parametrize("status", ["processing", "failed", "blocked", "needs_review", "needs_photo"])
def test_open_day_retains_current_job_and_usage_without_changing_attempts(household, status):
    day_id, job_id, usage_id, before = records(household, status=status)
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.get(Usage, usage_id).cost_micros == 10
        assert db.get(SchoolDay, day_id).preparation == before
        assert list(db.scalars(select(Job.status))) == ["failed"]


@pytest.mark.parametrize("status", ["ready", "saved", "idle"])
def test_finished_day_keeps_normal_job_and_usage_expiry(household, status):
    _, job_id, usage_id, _ = records(household, status=status)
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert db.get(Job, job_id) is None
        assert db.get(Usage, usage_id) is None


def test_dependency_never_extends_the_365_day_private_retention(household):
    day_id, job_id, usage_id, before = records(household, age=366)
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert db.get(Job, job_id) is None
        assert db.get(Usage, usage_id) is None
        assert db.get(SchoolDay, day_id).preparation == before


def test_prior_part_receipts_survive_but_unrelated_or_foreign_jobs_do_not(household):
    day_id, _, _, _ = records(household)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        user = User(username="synthetic-sibling", display_name="Künstliches Geschwister",
                    role="child", password_hash="unused-artificial-test-hash", verified=True)
        db.add(user)
        db.flush()
        sibling = Child(family_id=db.get(Child, day.child_id).family_id, user_id=user.id, grade=6, preferences={})
        db.add(sibling)
        db.flush()
        ids = []
        for key, digest, child_id in [("part", "same-plan", day.child_id),
                                       ("unrelated", "old-plan", day.child_id),
                                       ("foreign", "same-plan", sibling.id)]:
            job = Job(child_id=child_id, kind="package", status="completed", idempotency=key,
                      created=int(now()) - 100 * 86400,
                      payload={"school_day_id": day.id, "package_plan_digest": digest})
            db.add(job)
            db.flush()
            ids.append(job.id)
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert db.get(Job, ids[0]) is not None
        assert db.get(Job, ids[1]) is None
        assert db.get(Job, ids[2]) is None
        day = db.get(SchoolDay, day_id)
        day.preparation = {**day.preparation, "status": "ready"}
        db.commit()
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert db.get(Job, ids[0]) is None


def test_normal_30_and_90_day_cutoffs_and_active_jobs_are_unchanged(household):
    _, child = household
    with DB.begin() as db:
        for age, status in [(29, "failed"), (31, "failed"), (400, "queued"), (400, "running")]:
            db.add(Job(child_id=child["id"], kind="extract", status=status, payload={},
                       created=int(now()) - age * 86400, idempotency=f"{age}-{status}"))
        for age in [89, 91]:
            db.add(Usage(family_id=db.get(Child, child["id"]).family_id, child_id=child["id"],
                         job_id=f"old-{age}", function="extract", provider="synthetic", model="fixed",
                         config_revision=1, status="completed", reserved_micros=0, bucket_ids=[],
                         created=int(now()) - age * 86400))
    with DB.begin() as db:
        purge(db, int(now()))
    with DB() as db:
        assert set(db.scalars(select(Job.idempotency))) == {"29-failed", "400-queued", "400-running"}
        assert list(db.scalars(select(Usage.job_id))) == ["old-89"]


def test_missing_inflight_receipt_is_visible_and_never_silently_redispatched(api, household):
    from schulpilot import school_preparation as prep
    from test_school_preparation_parts import make_day, submit

    day_id = make_day(household, 3)
    submit(api, day_id)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        before = copy.deepcopy(day.preparation)
        db.delete(db.get(Job, before["job_id"]))
        usage_ids = list(db.scalars(select(Usage.id)))
    response = api.get(f"/api/school-days/{day_id}")
    assert response.status_code == 200
    assert response.json()["preparation"]["status"] == "failed"
    assert response.json()["preparation"]["error_code"] == "interrupted"
    with DB() as db:
        assert db.get(SchoolDay, day_id).preparation == before  # GET stays read-only.
    prep.advance(day_id)
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["status"] == "failed" and state["error_code"] == "interrupted"
        assert state["package_part_attempts"] == before["package_part_attempts"]
        assert state["job_id"] == before["job_id"]
        assert list(db.scalars(select(Job.id))) == []
        assert list(db.scalars(select(Usage.id))) == usage_ids


def test_explicitly_repaired_transcript_reports_new_sources_before_any_package_plan(household):
    from schulpilot import school_preparation as prep

    day_id, _, _, _ = records(household)
    with DB.begin() as db:
        day = db.get(SchoolDay, day_id)
        material = Material(child_id=day.child_id, school_day_id=day.id, title="Künstliche Abschrift",
                            content="Bestätigter künstlicher Text.", subject="Deutsch", revision=2,
                            status="confirmed", confirmed=True)
        db.add(material)
        db.flush()
        day.preparation = {"status": "failed", "phase": "extract", "day_revision": day.revision,
                           "sources": [{"id": material.id, "revision": 1}]}
        before = copy.deepcopy(day.preparation)
        result = prep.preparation_data(db, day, db.get(Child, day.child_id))
        assert result["sources_changed"] is True and result["retry_kind"] == "package"
        assert day.preparation == before
