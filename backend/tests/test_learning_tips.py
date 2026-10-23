from concurrent.futures import ThreadPoolExecutor

import pytest
from catalog_fixture import changed_catalog, sample_catalog
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.catalog_import import BUNDLE, CatalogError, catalog_url, import_catalog, read_catalog, validate
from schulpilot.catalog_jobs import work_one
from schulpilot.catalog_models import (
    CatalogContent,
    CatalogMembership,
    CatalogProvenance,
    CatalogRefresh,
    CatalogSnapshot,
    CatalogTopic,
    LearningTipContext,
    LearningTipInteraction,
)
from schulpilot.catalog_search import candidates, level_for, match_sections
from schulpilot.db import DB, Activity, Attempt, Child, Job, Material, Subject, Usage
from schulpilot.families import export_child
from schulpilot.main import app
from schulpilot.subject_registry import resolve
from sqlalchemy import create_engine, func, select, update
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker


def install(data=None):
    with DB.begin() as db:
        return import_catalog(db, data or sample_catalog())


def drain():
    for _ in range(300):
        if not work_one():
            return
    raise AssertionError("Local catalog batches did not finish")


def material(child_id, title="Brüche addieren", content="Brüche addieren. Zuerst den gemeinsamen Nenner bestimmen."):
    with DB.begin() as db:
        row = Material(
            child_id=child_id,
            subject="Mathe",
            title="Künstliches Unterrichtsblatt",
            topic=title,
            content=content,
            confirmed=True,
            status="confirmed",
        )
        db.add(row)
        db.flush()
        return row.id


def endpoint(child, material_id):
    return f"/api/children/{child['id']}/learning-tips/material/{material_id}"


def test_full_retained_catalog_can_be_validated_and_imported_twice(api):
    data, snapshot = read_catalog(BUNDLE)
    counts = validate(data)
    assert counts | {"csv_compared": False} == {
        "subjects": 16,
        "levels": 126,
        "active_levels": 124,
        "topics": 1558,
        "placements": 4188,
        "contents": 8227,
        "content_types": {"video": 7559, "learning_text": 668},
        "memberships": 9828,
        "curated_memberships": 7876,
        "empty_curated_topics": 4,
        "csv_video_relations": 19603,
        "csv_compared": False,
        "provenance": {
            "sources": 3892,
            "public_topic_documents": 1533,
            "public_topic_links": 12505,
            "content_metadata_sources": 658,
            "sitemap_content_pages": 5871,
        },
    }
    with DB.begin() as db:
        first = import_catalog(db, data, snapshot)
    with DB.begin() as db:
        second = import_catalog(db, data, snapshot)
        assert not first["repeated"] and second["repeated"]
        for model, expected in (
            (CatalogTopic, 1558),
            (CatalogContent, 8227),
            (CatalogMembership, 9828),
            (CatalogProvenance, 24459),
            (CatalogSnapshot, 1),
            (CatalogRefresh, 1),
            (Subject, 24),
        ):
            assert db.scalar(select(func.count()).select_from(model)) == expected


@pytest.mark.parametrize(
    "url",
    [
        "http://www.sofatutor.com/video",
        "https://www.sofatutor.com.evil.org/x",
        "https://sofatutor.com@evil.org/x",
        "https://evil.org@sofatutor.com/x",
        "https://www.sofatutor.com:444/x",
        "https://www.sofatutor.com/\nx",
        "https://www.sofatutor.com/x?access_token=synthetic",
        "https://www.sofatutor.com/x#token",
    ],
)
def test_external_host_and_secret_url_boundaries(url):
    with pytest.raises(CatalogError):
        catalog_url(url)


def test_import_rejects_unverified_type_unknown_subject_and_false_empty_list(api):
    for mutate in (
        lambda d: d["videos"][0].update(content_type="video_candidate"),
        lambda d: d["topics"][0].update(subject_id="erfunden"),
        lambda d: d["topics"][0].update(curated_list_empty_verified=True),
        lambda d: d["topic_placements"][0].update(grade_id="grade-english-1"),
    ):
        data = sample_catalog()
        mutate(data)
        with DB.begin() as db, pytest.raises(CatalogError):
            import_catalog(db, data)
        with DB() as db:
            assert not db.scalar(select(CatalogTopic.id))


def test_goal_specific_local_matcher_separates_operations_tenses_and_sections(api):
    install()
    with DB() as db:
        math, english = resolve(db, "Mathe").id, resolve(db, "Englisch").id
        expanded = candidates(db, math, "Brüche erweitern", "Erweitere 1/2 mit drei.", automatic=True)
        assert expanded and expanded[0]["id"] == "topic-expand"
        assert "topic-add" not in {r["id"] for r in expanded}
        past = candidates(db, english, "Simple Past", "We played football yesterday.", automatic=True)
        assert past[0]["id"] == "topic-past" and "topic-perfect" not in {r["id"] for r in past}
        assert not candidates(db, math, "Unbekanntes Thema ohne Übereinstimmung", automatic=True)
        matches = match_sections(db, math, "Rechnen", "Brüche erweitern\n\nBrüche addieren")
        assert {r["topic_id"] for r in matches} == {"topic-add", "topic-expand"}
        assert len({r["context_ref"] for r in matches}) == 2


def test_new_confirmed_page_gets_private_tips_without_ai_or_learning(api, household):
    _, child = household
    install()
    mid = material(child["id"])
    path = endpoint(child, mid)
    assert api.get(path).json()["state"] == "pending"
    drain()
    view = api.get(path).json()
    assert view["state"] == "ready" and view["topics"][0]["id"] == "topic-add"
    assert [r["content_type"] for r in view["recommended"]] == ["video", "learning_text"]
    assert all(r["curated_class_membership_verified"] for r in view["recommended"])
    assert "?topic=add" in view["recommended"][0]["url"]
    with DB() as db:
        before = (
            db.scalar(select(func.count()).select_from(CatalogRefresh)),
            db.get(LearningTipContext, view["context_id"]).revision,
        )
    for _ in range(5):
        assert api.get(path).json() == view
    with DB() as db:
        assert before == (
            db.scalar(select(func.count()).select_from(CatalogRefresh)),
            db.get(LearningTipContext, view["context_id"]).revision,
        )
        for model in (Job, Usage, Attempt, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_unknown_language_year_never_uses_school_grade_then_explicit_level(api, household):
    _, child = household
    install()
    mid = material(child["id"], "Simple Past", "Simple Past: We played football yesterday.")
    with DB.begin() as db:
        row = db.get(Material, mid)
        row.subject = "Englisch"
    drain()
    view = api.get(endpoint(child, mid)).json()
    assert not view["recommended"] and view["additional"]
    assert all(r["relation"] == "general_topic" for r in view["additional"])
    with DB() as db:
        english = resolve(db, "Englisch").id
        assert level_for(db, db.get(Child, child["id"]), english) == (None, None)
    path = f"/api/children/{child['id']}/subjects/{english}"
    bad = {"active": True, "revision": 0, "level_type": "klasse", "level_number": 6, "level_confirmed": True}
    assert api.put(path, json=bad).status_code == 422
    assert api.put(path, json=bad | {"level_type": "lernjahr", "level_number": 1}).status_code == 200
    drain()
    assert api.get(endpoint(child, mid)).json()["recommended"]


def test_verified_empty_list_stays_empty_and_unverified_entry_never_appears(api, household):
    _, child = household
    install()
    with DB() as db:
        math = resolve(db, "Mathe").id
    path = f"/api/children/{child['id']}/subjects/{math}/topics/topic-empty"
    response = api.get(path).json()
    assert response["topic"]["empty_curated"] and not response["recommended"]
    assert [r["id"] for r in response["additional"]] == ["content-general"]


def test_manual_selection_survives_catalog_update_but_source_changes_need_confirmation(api, household):
    _, child = household
    install()
    mid = material(child["id"])
    path = endpoint(child, mid)
    drain()
    before = api.get(path).json()
    payload = {"revision": before["revision"], "topic_ids": ["topic-expand"], "confirmed": True}
    changed = api.put(path + "/selection", json=payload)
    assert changed.status_code == 200, changed.text
    assert changed.json()["topics"][0]["id"] == "topic-expand"
    assert api.put(path + "/selection", json=payload).status_code == 409
    install(changed_catalog())
    drain()
    assert api.get(path).json()["topics"][0]["id"] == "topic-expand"
    with DB.begin() as db:
        source = db.get(Material, mid)
        source.revision += 1
        source.content += "\nNeue Quellenkorrektur."
    assert api.get(path).json()["state"] == "pending"
    drain()
    after = api.get(path).json()
    assert after["selection_needs_confirmation"] and after["topics"][0]["id"] == "topic-add"
    invalid = {"revision": after["revision"], "topic_ids": ["topic-past"], "confirmed": True}
    assert api.put(path + "/selection", json=invalid).status_code == 422
    assert api.put(path + "/selection", json=invalid | {"topic_ids": ["invented-id"]}).status_code == 422


def test_feedback_and_open_are_idempotent_without_completion_and_export_erasure(api, household):
    parent, child = household
    install()
    mid = material(child["id"])
    drain()
    path = endpoint(child, mid)
    view = api.get(path).json()
    data = {
        "request_key": "artificial-open-one",
        "kind": "open",
        "revision": view["revision"],
        "topic_id": "topic-add",
        "content_id": "content-add",
    }
    assert api.post(path + "/interactions", json=data).status_code == 200
    assert api.post(path + "/interactions", json=data).status_code == 200
    assert api.post(path + "/interactions", json=data | {"kind": "not_relevant"}).status_code == 409
    reject = data | {"request_key": "artificial-reject", "kind": "not_relevant", "content_id": None}
    assert api.post(path + "/interactions", json=reject).status_code == 200
    assert not api.get(path).json()["recommended"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningTipInteraction)) == 2
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        data = export_child(db, db.get(Child, child["id"]))
        assert len(data["learning_tip_contexts"]) == 1 and len(data["learning_tip_interactions"]) == 2
    assert (
        api.request("DELETE", f"/api/children/{child['id']}", json={"password": "secure-parent-pass-123"}).status_code
        == 200
    )
    with DB() as db:
        for model in (LearningTipContext, LearningTipInteraction):
            assert db.scalar(select(func.count()).select_from(model)) == 0
        assert db.scalar(select(CatalogTopic.id))


def test_foreign_family_sibling_private_subject_and_view_parent_are_enforced(api, household, mailbox):
    parent, child = household
    install()
    mid = material(child["id"])
    drain()
    path = endpoint(child, mid)
    with TestClient(app, headers=HEADERS) as other:
        user = register(other, mailbox, "other@example.org")
        create_child(other, user, "other-kid")
        assert other.get(path).status_code == 404
        assert (
            other.put(path + "/selection", json={"revision": 1, "topic_ids": [], "confirmed": True}).status_code == 404
        )
    # Existing backend administrator has no implicit family membership.
    from schulpilot.db import User
    from schulpilot.security import password_hash

    with DB.begin() as db:
        db.add(
            User(
                username="tip-operator",
                display_name="Betrieb",
                role="admin",
                verified=True,
                password_hash=password_hash("secure-operator-pass-123"),
            )
        )
    with TestClient(app, headers=HEADERS) as operator:
        signed = operator.post(
            "/api/auth/login", json={"username": "tip-operator", "password": "secure-operator-pass-123"}
        ).json()
        operator.headers["Authorization"] = "Bearer " + signed["token"]
        assert operator.get(path).status_code == 403
        assert operator.get(f"/api/children/{child['id']}/subjects").status_code == 403


def test_source_deletion_cascades_context_without_catalog_or_other_child_loss(api, household):
    _, child = household
    install()
    mid = material(child["id"])
    drain()
    with DB.begin() as db:
        db.delete(db.get(Material, mid))
    with DB() as db:
        assert not db.scalar(select(LearningTipContext.id))
        assert db.scalar(select(CatalogTopic.id))


def test_parallel_local_batches_create_one_context_and_parallel_link_posts_one_event(api, household):
    _, child = household
    install()
    ids = [material(child["id"]) for _ in range(6)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for _ in range(5):
            list(pool.map(lambda _: work_one(), range(4)))
    drain()
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningTipContext)) == 6
        assert not db.scalar(select(CatalogRefresh.id).where(CatalogRefresh.status == "failed"))
    path = endpoint(child, ids[0])
    view = api.get(path).json()
    headers = dict(api.headers)
    body = {
        "request_key": "parallel-link-request",
        "kind": "open",
        "revision": view["revision"],
        "content_id": "content-add",
        "topic_id": "topic-add",
    }

    def post(_):
        with TestClient(app, headers=headers) as client:
            return client.post(path + "/interactions", json=body)

    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(post, range(4)))
    assert {r.status_code for r in responses} == {200}, [r.status_code for r in responses]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningTipInteraction)) == 1


def test_read_only_parent_can_read_and_open_but_not_change_private_context(api, household):
    from schulpilot.db import Membership, User
    from schulpilot.security import password_hash

    parent, child = household
    install()
    mid = material(child["id"])
    drain()
    with DB.begin() as db:
        user = User(
            username="viewer@example.org",
            display_name="Lesende Eltern",
            role="parent",
            verified=True,
            password_hash=password_hash("secure-viewer-pass-123"),
        )
        db.add(user)
        db.flush()
        db.add(Membership(user_id=user.id, family_id=parent["families"][0]["id"], permission="view"))
    with TestClient(app, headers=HEADERS) as client:
        login = client.post(
            "/api/auth/login", json={"username": "viewer@example.org", "password": "secure-viewer-pass-123"}
        ).json()
        client.headers["Authorization"] = "Bearer " + login["token"]
        path = endpoint(child, mid)
        view = client.get(path).json()
        assert not view["can_respond"] and view["recommended"]
        assert (
            client.put(
                path + "/selection", json={"revision": view["revision"], "topic_ids": ["topic-add"], "confirmed": True}
            ).status_code
            == 403
        )
        body = {
            "request_key": "view-parent-open-one",
            "kind": "open",
            "revision": view["revision"],
            "content_id": "content-add",
            "topic_id": "topic-add",
        }
        assert client.post(path + "/interactions", json=body).status_code == 200
        assert (
            client.post(
                path + "/interactions", json=body | {"request_key": "view-parent-reject", "kind": "not_relevant"}
            ).status_code
            == 403
        )


def test_browsing_a_subject_without_photos_and_link_events_are_not_learning(api, household):
    _, child = household
    install()
    with DB() as db:
        sid = resolve(db, "Mathe").id
    path = f"/api/children/{child['id']}/subjects/{sid}"
    view = api.get(path + "/topics?q=Brüche&page_size=2").json()
    assert view["total"] == 3 and len(view["items"]) == 2
    assert api.get(path + "/topics?q=Brüche&page_size=2&page=2").json()["items"][0]["id"] not in {
        r["id"] for r in view["items"]
    }
    body = {
        "request_key": "browse-open-artificial",
        "kind": "open",
        "content_id": "content-add",
        "topic_id": "topic-add",
    }
    assert api.post(path + "/topic-interactions", json=body).status_code == 200
    assert api.post(path + "/topic-interactions", json=body).status_code == 200
    assert api.post(path + "/topic-interactions", json=body | {"content_id": "content-past"}).status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(LearningTipInteraction)) == 1
        for model in (Material, Attempt, Activity, Job, Usage):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def test_local_refresh_defers_busy_units_and_resumes_without_retrying_any_model(api, household):
    from schulpilot.db import LearningUnit, UnitSource

    _, child = household
    install()
    mid = material(child["id"])
    drain()
    with DB.begin() as db:
        unit = LearningUnit(
            child_id=child["id"],
            material_id=mid,
            subject="Mathe",
            topic="Brüche addieren",
            explanation="Künstlich",
            questions=[],
            provider="synthetic",
            model="fixed",
        )
        db.add(unit)
        db.flush()
        unit_id = unit.id
        db.add(UnitSource(unit_id=unit.id, material_id=mid, revision=1))
    with DB.begin() as busy:
        if busy.bind.dialect.name == "sqlite":
            # SQLite ignores FOR UPDATE; a real writer represents the same
            # unavailable resource without assuming PostgreSQL row locking.
            busy.execute(update(LearningUnit).where(LearningUnit.id == unit_id).values(topic=LearningUnit.topic))
        else:
            busy.scalar(select(LearningUnit).where(LearningUnit.id == unit_id).with_for_update())
        with ThreadPoolExecutor(max_workers=1) as pool:
            assert pool.submit(work_one).result(timeout=3) is False
    drain()
    with DB() as db:
        assert db.scalar(select(LearningTipContext.id).where(LearningTipContext.unit_id == unit_id))
        assert not db.scalar(select(CatalogRefresh.id).where(CatalogRefresh.status == "failed"))
        assert not db.scalar(select(Job.id)) and not db.scalar(select(Usage.id))


def test_interrupted_local_lease_is_recoverable_and_unknown_language_scope_empty(api, household):
    from schulpilot.db import now

    _, child = household
    install()
    with DB.begin() as db:
        job = db.scalar(select(CatalogRefresh))
        job.status, job.lease, job.updated = "running", "artificial-abandoned-lease", int(now()) - 121
        english = resolve(db, "Englisch").id
    drain()
    response = api.get(f"/api/children/{child['id']}/subjects/{english}/topics?scope=known").json()
    assert not response["items"] and not response["has_known_level"]
    with DB() as db:
        assert db.scalar(select(CatalogRefresh.status)) == "completed"


def test_sqlite_local_claim_does_not_hide_non_lock_database_errors(monkeypatch):
    from schulpilot import catalog_jobs

    isolated = create_engine("sqlite://")
    monkeypatch.setattr(catalog_jobs, "DB", sessionmaker(isolated))
    try:
        with pytest.raises(OperationalError, match="no such table"):
            catalog_jobs.work_one()
        with isolated.connect() as connection:
            assert connection.exec_driver_sql("PRAGMA busy_timeout").scalar() == 5000
    finally:
        isolated.dispose()
