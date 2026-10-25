"""Authorised, version-bound source reading; only invented private fixtures."""

import copy
import io

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot.config import settings
from schulpilot.db import DB, Activity, Attempt, Job, LearningUnit, Material, Session, UnitSource, Usage, User, now
from schulpilot.main import app
from schulpilot.security import digest
from sqlalchemy import func, select
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def book(api, household):
    yield from _normal_unit.__wrapped__(api, household)


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in (Attempt, Activity, Job, Usage))


def endpoint(uid, mid, *, image=False, revision=1):
    return f"/api/units/{uid}/sources/{mid}{'/image' if image else ''}?revision={revision}"


def test_unit_projects_snapshots_and_child_and_parent_read_without_mutations(api, book):
    child, uid, mid, *_ = book
    before = counts()
    with DB() as db:
        material = db.get(Material, mid)
        original = {"content": material.content, "revision": material.revision, "title": material.title}
        unit_questions = copy.deepcopy(db.get(LearningUnit, uid).questions)
    value = child.get(f"/api/units/{uid}")
    assert value.status_code == 200
    assert value.json()["sources"] == [{"material_id": mid, "revision": 1, "current_revision": 1,
        "status": "ready", "title": original["title"], "has_image": False}]
    assert value.json()["source_material_ids"] == [mid]
    for client in (child, api):
        response = client.get(endpoint(uid, mid))
        assert response.status_code == 200, response.text
        data = response.json()
        assert set(data) == {"unit_id", "child_id", "material_id", "revision", "confirmed", "title", "content", "has_image"}
        assert data["content"] == original["content"] and data["revision"] == 1 and data["confirmed"]
    assert counts() == before
    with DB() as db:
        assert db.get(Material, mid).revision == 1
        assert db.get(LearningUnit, uid).questions == unit_questions


@pytest.mark.parametrize("change,status", [("revision", "changed"), ("unconfirmed", "unconfirmed")])
def test_changed_or_unconfirmed_sources_are_visible_as_unavailable_and_never_served(book, change, status):
    child, uid, mid, *_ = book
    with DB.begin() as db:
        material = db.get(Material, mid)
        if change == "revision":
            material.revision += 1
            material.content = "PRIVATE NEW REVISION MUST NOT LEAK THROUGH THE OLD UNIT"
        else:
            material.confirmed = False
    response = child.get(f"/api/units/{uid}")
    assert response.status_code == 200
    assert response.json()["sources"][0]["status"] == status
    for image in (False, True):
        result = child.get(endpoint(uid, mid, image=image))
        assert result.status_code == 409 and "PRIVATE NEW REVISION" not in result.text


def test_client_cannot_substitute_the_current_revision_for_the_saved_snapshot(book):
    child, uid, mid, *_ = book
    with DB.begin() as db:
        db.get(Material, mid).revision = 2
    for revision in (1, 2):
        for image in (False, True):
            assert child.get(endpoint(uid, mid, image=image, revision=revision)).status_code == 409


def test_legacy_direct_pointer_has_no_invented_revision_or_unbound_photo_fallback(book):
    child, uid, mid, *_ = book
    with DB.begin() as db:
        db.delete(db.get(UnitSource, (uid, mid)))
    result = child.get(f"/api/units/{uid}")
    assert result.status_code == 200
    ref = result.json()["sources"][0]
    assert ref["status"] == "legacy" and ref["revision"] is None
    for image in (False, True):
        assert child.get(endpoint(uid, mid, image=image)).status_code == 404


def test_unlinked_own_material_is_not_a_source_of_this_round(book):
    child, uid, mid, *_ = book
    with DB.begin() as db:
        original = db.get(Material, mid)
        other = Material(child_id=original.child_id, title="PRIVATE UNLINKED TITLE", content="PRIVATE UNLINKED TEXT",
            subject=original.subject, topic=original.topic, confirmed=True, status="confirmed", synthetic=False)
        db.add(other)
        db.flush()
        other_id = other.id
    for image in (False, True):
        response = child.get(endpoint(uid, other_id, image=image))
        assert response.status_code == 404 and "PRIVATE UNLINKED" not in response.text


def test_malformed_cross_child_source_never_projects_foreign_metadata(api, book):
    child, uid, mid, parent, _ = book
    other = create_child(api, parent, username="source-other-child")
    with DB.begin() as db:
        foreign = Material(child_id=other["id"], title="PRIVATE OTHER CHILD TITLE", content="PRIVATE OTHER CHILD TEXT",
            subject="Mathematik", topic="Private", confirmed=True, status="confirmed", synthetic=False)
        db.add(foreign)
        db.flush()
        foreign_id = foreign.id
        db.add(UnitSource(unit_id=uid, material_id=foreign_id, revision=1))
    response = child.get(f"/api/units/{uid}")
    assert response.status_code == 200
    assert [row["material_id"] for row in response.json()["sources"]] == [mid]
    assert "PRIVATE OTHER CHILD" not in response.text
    for image in (False, True):
        denied = child.get(endpoint(uid, foreign_id, image=image))
        assert denied.status_code == 404 and "PRIVATE OTHER CHILD" not in denied.text


def test_source_photo_is_authenticated_no_store_and_checks_revision_again(book):
    child, uid, mid, *_ = book
    directory = settings.data_dir / "uploads"
    directory.mkdir(exist_ok=True)
    photo = io.BytesIO()
    Image.new("RGB", (8, 8), "purple").save(photo, "JPEG")
    filename = "synthetic-source-reading.jpg"
    (directory / filename).write_bytes(photo.getvalue())
    with DB.begin() as db:
        db.get(Material, mid).path = filename
    before = counts()
    assert child.get(endpoint(uid, mid)).json()["has_image"]
    result = child.get(endpoint(uid, mid, image=True))
    assert result.status_code == 200 and result.content == photo.getvalue()
    assert result.headers["cache-control"] == "no-store"
    assert result.headers["x-content-type-options"] == "nosniff"
    with DB.begin() as db:
        db.get(Material, mid).revision = 2
    assert child.get(endpoint(uid, mid, image=True)).status_code == 409
    assert counts() == before


def test_missing_photo_and_deleted_source_return_no_private_content(book):
    child, uid, mid, *_ = book
    assert child.get(endpoint(uid, mid, image=True)).status_code == 404
    with DB.begin() as db:
        db.delete(db.get(Material, mid))
    assert child.get(endpoint(uid, mid)).status_code == 404
    assert child.get(endpoint(uid, mid, image=True)).status_code == 404


def test_operator_and_other_child_cannot_read_unit_sources(api, book):
    _, uid, mid, parent, _ = book
    create_child(api, parent, username="source-denied-child")
    with DB.begin() as db:
        admin = User(username="source-operator", display_name="Synthetic operator", role="admin",
            verified=True, password_hash="not-a-real-password")
        db.add(admin)
        db.flush()
        admin_id = admin.id
        db.add(Session(user_id=admin.id, token_hash=digest("source-reading-operator-token"),
            device="Synthetic", expires=int(now()) + 3600))
    with TestClient(app, headers={**HEADERS, "Authorization": "Bearer source-reading-operator-token",
            "X-Schulpilot-Account": admin_id}) as operator:
        for path in (f"/api/units/{uid}", endpoint(uid, mid), endpoint(uid, mid, image=True)):
            assert operator.get(path).status_code == 403
    with TestClient(app, headers=HEADERS) as other:
        login = other.post("/api/auth/login", json={"username": "source-denied-child", "password": "secure-child-pass-123"})
        assert login.status_code == 200
        other.headers["Authorization"] = "Bearer " + login.json()["token"]
        for path in (f"/api/units/{uid}", endpoint(uid, mid), endpoint(uid, mid, image=True)):
            # Existing child_access deliberately conceals another child's ID.
            assert other.get(path).status_code == 404
