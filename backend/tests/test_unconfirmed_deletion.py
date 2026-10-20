"""Unconfirmed deletion uses only artificial uploads and isolated local data."""

from datetime import date, timedelta

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.config import settings
from schulpilot.db import DB, Attempt, Family, Job, LearningUnit, Material, Membership, SchoolDay, Usage, User, now
from schulpilot.fixtures import DAY_FIXTURE_IDS
from schulpilot.main import app
from schulpilot.providers import ProviderError
from schulpilot.school_preparation import advance_one, validate_job
from schulpilot.security import password_hash
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_school_preparation import capture


def child_client():
    client = TestClient(app, headers=HEADERS)
    login = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert login.status_code == 200
    client.headers["Authorization"] = "Bearer " + login.json()["token"]
    return client


def review_day(api, child, monkeypatch, *, count=2, archived=False):
    day, _ = capture(api, child, monkeypatch, count)
    with DB.begin() as db:
        stored = db.get(SchoolDay, day["id"])
        stored.stage = "review"
        if archived:
            stored.school_date = (date.fromisoformat(stored.school_date) - timedelta(days=1)).isoformat()
        materials = list(
            db.scalars(select(Material).where(Material.school_day_id == stored.id).order_by(Material.page_number))
        )
        for page in materials:
            page.status, page.legibility = "review", "readable"
            page.subject, page.topic, page.content = "Mathematik", "Brüche", "Künstliche Heftnotiz."
        stored.preparation = {
            "status": "needs_review",
            "phase": "review",
            "run_id": "old-run",
            "day_revision": stored.revision,
            "sources": [{"id": m.id, "revision": m.revision} for m in materials],
            "extract_attempts": {materials[-1].id: {"revision": 1, "count": 1}},
            "notice_created": int(now()),
            "notice_status": "needs_review",
        }
        ids = [page.id for page in materials]
        paths = [settings.data_dir / "uploads" / page.path for page in materials]
    return day, ids, paths


@pytest.mark.parametrize("archived", [False, True])
def test_child_counted_review_deletion_removes_linked_rounds_and_last_page_resets_inbox(
    api, household, monkeypatch, archived
):
    _, child = household
    day, ids, paths = review_day(api, child, monkeypatch, archived=archived)
    with DB.begin() as db:
        unit = LearningUnit(
            child_id=child["id"],
            material_id=ids[0],
            school_day_id=day["id"],
            provider="synthetic",
            synthetic=True,
            status="completed",
            completed=int(now()),
            **sample_unit(),
        )
        db.add(unit)
        db.flush()
        answer = Attempt(
            unit_id=unit.id,
            question_id=unit.questions[0]["id"],
            answer="synthetic saved answer",
            outcome="correct",
            assisted=False,
        )
        db.add(answer)
        db.flush()
        unit_id, answer_id = unit.id, answer.id
        revision = db.get(SchoolDay, day["id"]).revision
    with child_client() as kid:
        assert kid.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        selection = kid.post(f"/api/children/{child['id']}/materials/delete-preview", json={"ids": [ids[0]]}).json()
        assert selection['unit_count'] == selection['answer_count'] == 1
        response = kid.post(f"/api/children/{child['id']}/materials/bulk-delete", json={
            "selection_token": selection["selection_token"], "delete_linked_units": True})
        assert response.status_code == 200, response.text
        state = kid.get(f"/api/school-days/{day['id']}").json()
        assert len(state["pages"]) == 1 and state["preparation"]["status"] == "needs_review"
        assert not paths[0].exists() and paths[1].exists()
        with DB() as db:
            stored = db.get(SchoolDay, day["id"])
            assert stored.revision == revision + 1 and stored.preparation["run_id"] != "old-run"
            assert stored.preparation["sources"] == [{"id": ids[1], "revision": 1}]
            assert stored.preparation["extract_attempts"][ids[1]]["count"] == 1
            assert stored.preparation["notice_created"] == 0
        response = kid.delete(f"/api/school-days/{day['id']}/pages/{ids[1]}")
        assert response.status_code == 200, response.text
        state = response.json()
        assert state["pages"] == [] and state["stage"] == "collecting"
        assert state["preparation"]["status"] == "idle" and state["preparation"]["job"] is None
        assert state["allow_uploads"] is (not archived) and not paths[1].exists()
        overview = kid.get(f"/api/children/{child['id']}/overview?compact=true").json()
        assert not overview["pending_preparations"]
    advance_one()
    with DB() as db:
        assert db.get(LearningUnit, unit_id) is None
        assert db.get(Attempt, answer_id) is None
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_child_general_material_delete_uses_same_archived_day_guards(api, household, monkeypatch):
    _, child = household
    day, ids, paths = review_day(api, child, monkeypatch, count=1, archived=True)
    with child_client() as kid:
        response = kid.delete(f"/api/materials/{ids[0]}")
        assert response.status_code == 200, response.text
        assert response.json()["id"] == day["id"] and response.json()["preparation"]["status"] == "idle"
    assert not paths[0].exists()


@pytest.mark.parametrize("job_status", ["queued", "running"])
def test_day_deletion_blocks_jobs_and_confirmed_sources_but_notebook_allows_own_deletion(api, household, monkeypatch, job_status):
    _, child = household
    day, ids, paths = review_day(api, child, monkeypatch, count=1)
    with DB.begin() as db:
        job = Job(
            child_id=child["id"],
            kind="extract",
            payload={"material_id": ids[0]},
            status=job_status,
            idempotency="synthetic-deletion-job",
        )
        db.add(job)
        db.flush()
        job_id = job.id
    with child_client() as kid:
        assert kid.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        assert kid.delete(f"/api/materials/{ids[0]}").status_code == 409
        assert api.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        assert paths[0].exists()
        with DB.begin() as db:
            db.get(Job, job_id).status = "completed"
            material = db.get(Material, ids[0])
            material.confirmed, material.status = True, "confirmed"
        assert kid.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        assert api.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        # The explicit notebook deletion also permits confirmed own pages.
        assert kid.delete(f"/api/materials/{ids[0]}").status_code == 200
    assert api.delete(f"/api/materials/{ids[0]}").status_code == 404
    assert not paths[0].exists()


def test_sibling_page_and_mismatched_day_cannot_be_deleted(api, household, monkeypatch):
    owner, child = household
    sibling = create_child(api, owner, "sibling-child")
    day, ids, paths = review_day(api, child, monkeypatch, count=1)
    other, sibling_ids, sibling_paths = review_day(api, sibling, monkeypatch, count=1)
    with child_client() as kid:
        assert kid.delete(f"/api/school-days/{other['id']}/pages/{sibling_ids[0]}").status_code == 404
        assert kid.delete(f"/api/school-days/{day['id']}/pages/{sibling_ids[0]}").status_code == 404
        assert kid.delete(f"/api/materials/{sibling_ids[0]}").status_code == 404
    assert all(path.exists() for path in [*paths, *sibling_paths])


@pytest.mark.parametrize("synthetic", [False, True])
def test_child_can_delete_unconfirmed_standalone_import_including_plain_demo(api, household, monkeypatch, synthetic):
    _, child = household
    day, ids, paths = review_day(api, child, monkeypatch, count=1)
    with DB.begin() as db:
        material = db.get(Material, ids[0])
        material.school_day_id, material.page_number, material.synthetic = None, None, synthetic
    with child_client() as kid:
        response = kid.delete(f"/api/materials/{ids[0]}")
        assert response.status_code == 200, response.text
        assert kid.get(f"/api/materials/{ids[0]}").status_code == 404
    assert not paths[0].exists()


@pytest.mark.parametrize("job_status", ["queued", "running"])
def test_child_standalone_cannot_delete_during_job_but_can_after_confirmation(api, household, monkeypatch, job_status):
    _, child = household
    _, ids, paths = review_day(api, child, monkeypatch, count=1)
    with DB.begin() as db:
        db.get(Material, ids[0]).school_day_id = None
        job = Job(
            child_id=child["id"],
            kind="extract",
            payload={"material_id": ids[0]},
            status=job_status,
            idempotency="synthetic-deletion-job",
        )
        db.add(job)
        db.flush()
        job_id = job.id
    with child_client() as kid:
        assert kid.delete(f"/api/materials/{ids[0]}").status_code == 409
        assert paths[0].exists()
        with DB.begin() as db:
            db.get(Job, job_id).status = "completed"
            db.get(Material, ids[0]).confirmed = True
        assert kid.delete(f"/api/materials/{ids[0]}").status_code == 200
        assert not paths[0].exists()


def test_view_only_parent_cannot_delete_unconfirmed_page_or_standalone(api, household, monkeypatch):
    owner, child = household
    day, ids, _ = review_day(api, child, monkeypatch)
    with DB.begin() as db:
        user = User(
            username="view-parent@example.org",
            email="view-parent@example.org",
            display_name="View",
            role="parent",
            verified=True,
            password_hash=password_hash("synthetic-view-parent-pass"),
        )
        db.add(user)
        db.flush()
        db.add(Membership(user_id=user.id, family_id=owner["families"][0]["id"], permission="view"))
        db.get(Material, ids[1]).school_day_id = None
    with TestClient(app, headers=HEADERS) as viewer:
        login = viewer.post(
            "/api/auth/login", json={"username": "view-parent@example.org", "password": "synthetic-view-parent-pass"}
        )
        assert login.status_code == 200
        viewer.headers["Authorization"] = "Bearer " + login.json()["token"]
        assert viewer.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 403
        assert viewer.delete(f"/api/materials/{ids[1]}").status_code == 403


def test_fixed_two_page_demo_cannot_be_broken_by_single_page_delete(api, household, monkeypatch):
    owner, child = household
    day, ids, paths = review_day(api, child, monkeypatch)
    with DB.begin() as db:
        db.get(Family, owner["families"][0]["id"]).synthetic = True
        for material_id, fixture_id in zip(ids, DAY_FIXTURE_IDS, strict=True):
            material = db.get(Material, material_id)
            material.synthetic, material.fixture_id = True, fixture_id
    with child_client() as kid:
        assert kid.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
        assert kid.delete(f"/api/materials/{ids[0]}").status_code == 409
    assert api.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}").status_code == 409
    assert all(path.exists() for path in paths)
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == 2


def test_delete_between_successful_job_and_next_reservation_cancels_old_intent(api, household, monkeypatch):
    _, child = household
    day, ids, _ = review_day(api, child, monkeypatch)
    with DB.begin() as db:
        db.get(Material, ids[1]).status = "uploaded"
        job = Job(
            child_id=child["id"],
            kind="extract",
            status="completed",
            payload={"material_id": ids[0], "school_day_id": day["id"], "preparation_id": "old-run"},
            idempotency="synthetic-deletion-job",
        )
        db.add(job)
        db.flush()
        stored = db.get(SchoolDay, day["id"])
        stored.preparation = {**stored.preparation, "status": "processing", "phase": "extract", "job_id": job.id}
        old_job_id = job.id
    with child_client() as kid:
        response = kid.delete(f"/api/school-days/{day['id']}/pages/{ids[0]}")
        assert response.status_code == 200, response.text
        assert response.json()["preparation"]["status"] == "blocked"
        advance_one()
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Job)) == 1
            assert db.scalar(select(func.count()).select_from(Usage)) == 0
            with pytest.raises(ProviderError, match="nicht mehr aktuell"):
                validate_job(db, db.get(Job, old_job_id))
        queued = kid.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "explicit-after-delete"})
        assert queued.status_code == 202, queued.text
        assert queued.json()["preparation"]["status"] == "processing"
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Job)) == 2
            assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_family_separation_for_parent_and_child_deletion(api, household, mailbox, monkeypatch):
    _, child = household
    own_day, own_ids, own_paths = review_day(api, child, monkeypatch, count=1)
    # A login on the same client intentionally revokes its previous session.
    # Give the unrelated parent its own client rather than switching accounts.
    with TestClient(app, headers=HEADERS) as other:
        other_parent = register(other, mailbox, "other-parent@example.org")
        other_child = create_child(other, other_parent, "other-child")
        other_day, other_ids, other_paths = review_day(other, other_child, monkeypatch, count=1)
        assert api.get("/api/auth/me").status_code == 200
        assert other.get("/api/auth/me").status_code == 200
        assert api.delete(f"/api/school-days/{other_day['id']}/pages/{other_ids[0]}").status_code == 404
        assert api.delete(f"/api/materials/{other_ids[0]}").status_code == 404
        with child_client() as kid:
            assert kid.get("/api/auth/me").status_code == 200
            assert kid.delete(f"/api/school-days/{other_day['id']}/pages/{other_ids[0]}").status_code == 404
            assert kid.delete(f"/api/materials/{other_ids[0]}").status_code == 404
        assert other.delete(f"/api/school-days/{own_day['id']}/pages/{own_ids[0]}").status_code == 404
    assert all(path.exists() for path in [*own_paths, *other_paths])


def test_deleting_last_unconfirmed_page_allows_explicit_package_for_confirmed_remainder(api, household, monkeypatch):
    _, child = household
    day, ids, _ = review_day(api, child, monkeypatch)
    with child_client() as kid:
        page = kid.get(f"/api/materials/{ids[0]}").json()
        confirmed = kid.put(
            f"/api/materials/{ids[0]}/confirm",
            json={
                **{key: page[key] for key in ("subject", "topic", "content", "homework")},
                "uncertainties_resolved": True,
            },
        )
        assert confirmed.status_code == 200, confirmed.text
        removed = kid.delete(f"/api/school-days/{day['id']}/pages/{ids[1]}")
        assert removed.status_code == 200, removed.text
        assert removed.json()["confirmed_count"] == 1
        advance_one()
        with DB() as db:
            assert db.scalar(select(func.count()).select_from(Job)) == 0
        queued = kid.post(f"/api/school-days/{day['id']}/prepare", headers={"Idempotency-Key": "confirmed-remainder"})
        assert queued.status_code == 202, queued.text
        assert queued.json()["preparation"]["status"] == "processing"
        assert queued.json()["preparation"]["phase"] == "package"
        with DB() as db:
            job = db.scalar(select(Job))
            assert job.kind == "package" and job.payload["sources"] == [{"id": ids[0], "revision": 2}]


@pytest.mark.parametrize("standalone", [False, True])
def test_confirm_wins_child_lock_race_and_prevents_unconfirmed_deletion(api, household, monkeypatch, standalone):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event

    from schulpilot import materials, school_day
    from schulpilot.db import Child, engine
    from sqlalchemy import update

    if engine.dialect.name != "postgresql":
        pytest.skip("Requires genuine row locks")
    _, child = household
    day, ids, paths = review_day(api, child, monkeypatch, count=1)
    if standalone:
        with DB.begin() as db:
            db.get(Material, ids[0]).school_day_id = None
    module = materials if standalone else school_day
    original = module.lock_material_units
    deletion_reached = Event()

    def reached(db, child_id, material_id):
        original(db, child_id, material_id)
        deletion_reached.set()

    monkeypatch.setattr(module, "lock_material_units", reached)
    route = f"/api/materials/{ids[0]}" if standalone else f"/api/school-days/{day['id']}/pages/{ids[0]}"
    with child_client() as kid, ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as locker:
            locker.execute(update(Child).where(Child.id == child["id"]).values(grade=Child.grade))
            pending = pool.submit(kid.delete, route)
            assert deletion_reached.wait(timeout=5), "Child deletion did not reach its pre-Child lock point"
            page = locker.get(Material, ids[0])
            page.confirmed, page.status, page.revision = True, "confirmed", page.revision + 1
        response = pending.result(timeout=10)
    assert response.status_code == 409, response.text
    assert paths[0].exists()
    with DB() as db:
        assert db.get(Material, ids[0]).confirmed is True
