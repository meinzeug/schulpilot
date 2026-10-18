"""Synthetic subject shelves and photo-album metadata; never AI or progress."""

from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot.db import DB, Activity, Job, Material, Usage
from schulpilot.main import app
from schulpilot.subject_registry import resolve
from sqlalchemy import func, select


def test_album_uses_canonical_subject_aliases_and_bounded_metadata(api, household):
    _, child = household
    with DB.begin() as db:
        sid = resolve(db, "Mathematik").id
        for n in range(47):
            db.add(Material(child_id=child["id"], title=f"Seite {n}", subject="Mathe" if n % 2 else "Mathematik",
                            path=f"private-{n}.jpg", content="PRIVATE SOURCE NOT FOR LISTS", created=1700000000+n))
        db.add(Material(child_id=child["id"], title="Andere Seite", subject="Biologie"))
    seen = []
    for page in (1, 2, 3):
        response = api.get(f"/api/children/{child['id']}/materials", params={"subject_id": sid, "sort": "oldest", "page": page})
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["total"] == 47 and data["pages"] == 3
        for row in data["items"]:
            assert row["subject_id"] == sid and row["has_image"] is True and row["revision"] == 1
            assert not {"path", "content", "image_digest", "extraction_model"} & row.keys()
            seen.append(row["id"])
    assert len(seen) == len(set(seen)) == 47
    with DB() as db:
        for table in (Job, Usage, Activity):
            assert db.scalar(select(func.count()).select_from(table)) == 0


def test_empty_subject_and_unassigned_pages_have_honest_counts(api, household):
    _, child = household
    with DB.begin() as db:
        english = resolve(db, "Englisch").id
        db.add(Material(child_id=child["id"], title="Text ohne Foto", subject=""))
    route = f"/api/children/{child['id']}/materials"
    assert api.get(route, params={"subject_id": english}).json()["total"] == 0
    result = api.get(route, params={"subject_id": "unassigned"}).json()
    assert result["total"] == 1 and result["items"][0]["has_image"] is False
    assert api.get(route, params={"subject_id": english, "subject": "Englisch"}).status_code == 422
    assert api.get(route, params={"subject_id": "invented"}).status_code == 422
    assert api.get(route, params={"subject_id": "f"*32}).status_code == 404


def test_child_cannot_probe_sibling_private_notebook(api, household):
    parent, child = household
    sibling = create_child(api, parent, "sibling-notebook")
    private = api.post(f"/api/children/{sibling['id']}/subjects", json={"title": "Privates Wahlfach", "confirmed": True}).json()
    route = f"/api/children/{child['id']}/materials"
    assert api.get(route, params={"subject_id": private["id"]}).status_code == 200
    with TestClient(app, headers=HEADERS) as own:
        signed = own.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        own.headers["Authorization"] = "Bearer " + signed["token"]
        assert own.get(route, params={"subject_id": private["id"]}).status_code == 404
        assert own.get(f"/api/children/{sibling['id']}/materials", params={"subject_id": private["id"]}).status_code == 404
