"""Fresh/legacy subject identities, empty subjects and private scopes."""

from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.db import DB, Child, Material, Subject, SubjectProvider
from schulpilot.main import app
from schulpilot.subject_registry import backfill_connection, create_private_connection, resolve, seed_connection
from sqlalchemy import func, select


def test_reference_subjects_exist_before_any_account_or_material(api):
    listed = api.get("/api/subjects").json()["items"]
    titles = {r["title"] for r in listed}
    assert {
        "Mathematik",
        "Englisch",
        "Deutsch",
        "Deutsch als Zweitsprache",
        "Biologie",
        "Sachunterricht",
        "Sport",
        "Kunst",
    } <= titles
    assert len({r["id"] for r in listed}) == len(listed) == 24
    with DB.begin() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == 0
        assert (
            db.scalar(select(func.count()).select_from(SubjectProvider).where(SubjectProvider.provider == "sofatutor"))
            == 16
        )
        before = {r.key: r.id for r in db.scalars(select(Subject))}
        seed_connection(db.connection())
        seed_connection(db.connection())
        assert before == {r.key: r.id for r in db.scalars(select(Subject))}


def test_new_parent_and_independent_child_can_open_all_empty_subjects(api, household):
    parent, child = household
    path = f"/api/children/{child['id']}/subjects"
    parent = api.get(path).json()
    assert len(parent["items"]) == 24
    assert all(row["page_count"] == row["photo_count"] == row["review_count"] == 0 for row in parent["items"])
    with TestClient(app, headers=HEADERS) as kid:
        login = kid.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}).json()
        kid.headers["Authorization"] = "Bearer " + login["token"]
        listed = kid.get(path).json()
        assert [r["id"] for r in listed["items"]] == [r["id"] for r in parent["items"]]
        assert not listed["can_manage"] and parent["can_manage"]
        assert kid.post(path, json={"title": "Eigene Erfindung", "confirmed": True}).status_code == 403


def test_explicit_aliases_converge_without_merging_related_subjects(household):
    parent, child = household
    with DB() as db:
        assert resolve(db, " Mathe ", parent["families"][0]["id"]).id == resolve(db, "MATHEMATIK").id
        assert resolve(db, "Erdkunde").id == resolve(db, "Geographie").id
        assert resolve(db, "DaZ").id == resolve(db, "Deutsch als Zweitsprache").id != resolve(db, "Deutsch").id
        assert resolve(db, "Sachunterricht").id != resolve(db, "Biologie").id
        assert resolve(db, "Biologie und Sachkunde") is None


def test_unknown_runtime_subject_does_not_create_any_registry_row(household):
    parent, child = household
    with DB.begin() as db:
        before = db.scalar(select(func.count()).select_from(Subject))
        a = Material(child_id=child["id"], title="Synthetic", subject="Mathe", topic="Brüche", content="synthetic")
        b = Material(
            child_id=child["id"],
            title="Synthetic",
            subject="Frei erfundenes Modellfach",
            topic="Quelle",
            content="synthetic",
        )
        db.add_all([a, b])
        db.flush()
        assert a.subject_id == resolve(db, "Mathematik").id
        assert b.subject_id is None
        backfill_connection(db.connection())
        assert db.scalar(select(func.count()).select_from(Subject)) == before


def test_legacy_backfill_is_repeatable_and_keeps_additional_names_family_private(api, household, mailbox):
    parent, child = household
    with DB.begin() as db:
        # Simulate the pre-registry shape, bypassing the new ORM binder.
        db.connection().execute(
            Material.__table__.insert().values(
                id="old",
                child_id=child["id"],
                title="Synthetic",
                subject="   Mathe ",
                topic="Brüche",
                content="original source",
                confirmed=True,
            )
        )
        db.connection().execute(
            Material.__table__.insert().values(
                id="extra",
                child_id=child["id"],
                title="Synthetic",
                subject="Eigene Schulwerkstatt",
                topic="Quelle",
                content="original source",
            )
        )
        db.get(Child, child["id"]).subjects = ["Mathe", "Eigene Schulwerkstatt"]
    with DB.begin() as db:
        first = backfill_connection(db.connection(), preserve_legacy_extras=True)
        assert first["references_migrated"] == 2
        assert backfill_connection(db.connection(), preserve_legacy_extras=True)["references_migrated"] == 0
        assert db.get(Material, "old").subject_id == resolve(db, "Mathematik").id
        assert db.get(Material, "old").subject == "   Mathe " and db.get(Material, "old").content == "original source"
        extra = resolve(db, "Eigene Schulwerkstatt", parent["families"][0]["id"])
        assert extra.owner_family_id == parent["families"][0]["id"]
    assert "Eigene Schulwerkstatt" not in [r["title"] for r in api.get("/api/subjects").json()["items"]]
    own = api.get(f"/api/children/{child['id']}/subjects").json()
    assert next(r for r in own["items"] if r["title"] == "Eigene Schulwerkstatt")["page_count"] == 1
    foreign = register(api, mailbox, "other-subject-family@example.org")
    another = create_child(api, foreign, "other-subject-child")
    other = api.get(f"/api/children/{another['id']}/subjects").json()
    assert "Eigene Schulwerkstatt" not in [r["title"] for r in other["items"]]
    assert api.get(f"/api/children/{child['id']}/subjects").status_code == 404


def test_parent_explicit_custom_subject_is_idempotent_and_does_not_change_seed(api, household):
    parent, child = household
    route = f"/api/children/{child['id']}/subjects"
    one = api.post(route, json={"title": "Naturwissenschaften", "confirmed": True})
    two = api.post(route, json={"title": " naturwissenschaften ", "confirmed": True})
    assert one.status_code == two.status_code == 201
    assert one.json()["id"] == two.json()["id"]
    assert one.json()["family_subject"]
    assert len(api.get("/api/subjects").json()["items"]) == 24
    with DB() as db:
        assert resolve(db, "Naturwissenschaften", parent["families"][0]["id"]).id != resolve(db, "Biologie").id


def test_family_custom_names_are_not_visible_to_a_sibling_child(api, household):
    parent, child = household
    another = create_child(api, parent, "other-subject-child")
    subject = api.post(
        f"/api/children/{child['id']}/subjects", json={"title": "Eigene Schulwerkstatt", "confirmed": True}
    ).json()
    with TestClient(app, headers=HEADERS) as kid:
        signed = kid.post(
            "/api/auth/login", json={"username": "other-subject-child", "password": "secure-child-pass-123"}
        ).json()
        kid.headers["Authorization"] = "Bearer " + signed["token"]
        data = kid.get(f"/api/children/{another['id']}/subjects").json()
        assert subject["id"] not in [r["id"] for r in data["items"]]
    assert (
        api.request("DELETE", f"/api/children/{child['id']}", json={"password": "secure-parent-pass-123"}).status_code
        == 200
    )
    with DB() as db:
        assert db.get(Subject, subject["id"]) is None


def test_custom_subject_limit_also_applies_to_profile_writes(api, household):
    parent, child = household
    with DB.begin() as db:
        for index in range(40):
            create_private_connection(db.connection(), f"Synthetic subject {index}", parent["families"][0]["id"], legacy=True)
    response = api.post(f"/api/children/{child['id']}/subjects", json={"title": "Synthetic subject extra", "confirmed": True})
    assert response.status_code == 409
    response = api.put(f"/api/children/{child['id']}", json={"display_name": child["display_name"], "grade": 6,
                       "subjects": ["Synthetic subject extra"], "school_type": "", "region": ""})
    assert response.status_code == 409
    with DB() as db:
        assert db.get(Child, child["id"]).subjects == ["Mathematik"]
        assert db.scalar(select(func.count()).select_from(Subject).where(Subject.owner_family_id == parent["families"][0]["id"])) == 40
