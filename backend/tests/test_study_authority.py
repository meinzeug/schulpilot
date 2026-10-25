"""No external provider: real stored submission and before/after guards."""
import copy

import pytest
from schulpilot.db import DB, Child, Job, LearningUnit, Session, Usage, User, now
from sqlalchemy import func, select
from test_study_path import create, finish, generate
from test_study_path import stage_transport as _stage_transport
from test_study_path import study as _study

study = _study
stage_transport = _stage_transport


def queued(study):
    plan = create(study)
    response = generate(study, plan["next_block_id"])
    assert response.status_code == 202, response.text
    return response.json()["id"]


@pytest.mark.parametrize("when", ["before", "after"])
@pytest.mark.parametrize("fault", ["revoked", "expired", "disabled", "role", "foreign_session"])
def test_study_submission_authority_revoked_before_or_during_provider_is_never_published(study, stage_transport, when, fault):
    job_id = queued(study)
    def change():
        with DB.begin() as db:
            job = db.get(Job, job_id)
            value = job.payload["study_authority"]
            session, user = db.get(Session, value["session_id"]), db.get(User, value["user_id"])
            if fault == "revoked":
                session.revoked = True
            elif fault == "expired":
                session.expires = int(now()) - 1
            elif fault == "disabled":
                user.disabled = True
            elif fault == "role":
                user.role = "admin"
            else:
                session.user_id = study["parent"]["id"]
    if when == "before":
        change()
    else:
        stage_transport["effect"] = change
    finish()
    assert len(stage_transport["calls"]) == (when == "after")
    with DB() as db:
        job = db.get(Job, job_id)
        assert job.status == "failed" and "Anmeldung" in job.error
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        assert usage.settlement_version == 1
        if when == "before":
            assert usage.cost_source == "cancelled" and usage.cost_micros == 0


def test_legacy_unproven_queued_job_fails_closed_without_changing_published_rounds(study, stage_transport):
    job_id = queued(study)
    with DB.begin() as db:
        job = db.get(Job, job_id)
        payload = copy.deepcopy(job.payload)
        payload.pop("study_authority")
        job.payload = payload
    finish()
    assert stage_transport["calls"] == []
    with DB() as db:
        assert db.get(Job, job_id).status == "failed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 0


def test_real_study_queue_binds_server_identity_and_valid_job_still_completes(study, stage_transport):
    job_id = queued(study)
    with DB() as db:
        value = db.get(Job, job_id).payload["study_authority"]
        assert value["user_id"] == db.get(Child, study["child"]["id"]).user_id and value["family_id"] == study["parent"]["families"][0]["id"]
        assert db.get(Session, value["session_id"]).user_id == value["user_id"]
    finish()
    assert len(stage_transport["calls"]) == 1
    with DB() as db:
        assert db.get(Job, job_id).status == "completed"
        assert db.scalar(select(func.count()).select_from(LearningUnit)) == 1
