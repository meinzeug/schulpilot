"""Currentness is read-only metadata; historical outputs never become new ones."""
import copy

import pytest
from schulpilot import school_preparation as prep
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Material, SchoolDay, Usage
from sqlalchemy import func, select
from test_school_preparation_parts import complete_part, fail_part, make_day, submit


def staged_six(api, household):
    day_id = make_day(household, 19)
    value = submit(api, day_id, "stale127-initial-prepare")
    assert value["total_parts"] == 7
    for _ in range(6):
        complete_part(day_id)
        prep.advance(day_id)
    fail_part(day_id)
    prep.advance(day_id)
    with DB() as db:
        day = db.get(SchoolDay, day_id)
        state = copy.deepcopy(day.preparation)
        assert len(state["package_outputs"]) == 6
    return day_id, state


def inventory():
    with DB() as db:
        return [db.scalar(select(func.count()).select_from(m)) for m in (Job, Usage, LearningUnit, Attempt, Activity)]


def correct_source(api, state):
    with DB() as db:
        page = db.get(Material, state["sources"][0]["id"])
        body = {"subject": page.subject, "topic": page.topic,
            "content": page.content + "\nKünstliche zusätzliche Originalnotiz.", "homework": page.homework,
            "uncertainties_resolved": True, "revision": page.revision}
    response = api.put(f"/api/materials/{state['sources'][0]['id']}/confirm", json=body)
    assert response.status_code == 200, response.text


@pytest.mark.parametrize("changed", [False, True])
def test_six_saved_parts_report_current_source_state_without_get_writes(api, household, changed):
    day_id, before = staged_six(api, household)
    if changed:
        correct_source(api, before)
    counts = inventory()
    for _ in range(2):
        response = api.get(f"/api/school-days/{day_id}")
        assert response.status_code == 200
        data = response.json()["preparation"]
        assert data["sources_changed"] is changed
        assert data["completed_parts"] == 6 and data["total_parts"] == 7
        assert data["can_retry"] is True
        assert data["can_publish_parts"] is not changed
        assert data["ready_prefix_parts"] == (0 if changed else 6)
    with DB() as db:
        assert db.get(SchoolDay, day_id).preparation == before
    assert inventory() == counts


def test_stale_prefix_and_old_key_are_refused_then_conscious_restart_rebuilds(api, household):
    day_id, before = staged_six(api, household)
    correct_source(api, before)
    counts = inventory()
    failed = api.post(f"/api/school-days/{day_id}/publish-ready-parts", json={"plan_digest": before["package_plan"]["digest"]},
        headers={"X-Schulpilot-Account": household[0]["id"], "Idempotency-Key": "stale127-cannot-publish"})
    assert failed.status_code == 409, failed.text
    old_key = api.post(f"/api/school-days/{day_id}/prepare", headers={"Idempotency-Key": "stale127-initial-prepare"})
    assert old_key.status_code == 409
    assert inventory() == counts
    with DB() as db:
        assert db.get(SchoolDay, day_id).preparation == before
        jobs = {j.id: (j.status, copy.deepcopy(j.payload), j.error) for j in db.scalars(select(Job))}
        usage = {u.id: (u.status, u.cost_micros) for u in db.scalars(select(Usage))}
    restarted = submit(api, day_id, "stale127-conscious-current-source")
    assert restarted["sources_changed"] is False and restarted["completed_parts"] == 0
    with DB() as db:
        state = db.get(SchoolDay, day_id).preparation
        assert state["package_plan"]["digest"] != before["package_plan"]["digest"]
        assert state["package_outputs"] == {} and len(state["package_plan"]["parts"]) == 7
        assert db.get(Job, state["job_id"]).payload["package_partition"] == 0
        assert {j.id: (j.status, j.payload, j.error) for j in db.scalars(select(Job)) if j.id in jobs} == jobs
        assert {u.id: (u.status, u.cost_micros) for u in db.scalars(select(Usage)) if u.id in usage} == usage
    assert inventory()[:2] == [counts[0] + 1, counts[1] + 1]
    assert inventory()[2:] == [*counts[2:4], counts[4] + 1]
