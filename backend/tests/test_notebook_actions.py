"""Notebook actions use artificial uploads only; no real providers or children."""

import io
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot import material_actions, materials
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Attempt,
    Job,
    LearningUnit,
    Material,
    Membership,
    ProviderConfig,
    Session,
    UnitSource,
    Usage,
    User,
    now,
)
from schulpilot.main import app
from schulpilot.providers import ProviderError
from schulpilot.security import crypt, password_hash
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


def photo(api, child, *, title="Künstliche Seite", subject="Mathematik", confirmed=True):
    image = io.BytesIO()
    Image.new("RGB", (600, 800), "white").save(image, "JPEG")
    object.__setattr__(settings, "real_data_approved", True)
    object.__setattr__(settings, "privacy_evidence", "Isolated synthetic notebook action test")
    response = api.post(
        f"/api/children/{child['id']}/materials", files={"file": ("synthetic.jpg", image.getvalue(), "image/jpeg")}
    )
    assert response.status_code == 201, response.text
    material_id = response.json()["id"]
    with DB.begin() as db:
        material = db.get(Material, material_id)
        material.title, material.subject, material.topic = title, subject, "Künstlicher Unterrichtsstoff"
        material.status, material.confirmed = ("confirmed", True) if confirmed else ("review", False)
        path = settings.data_dir / "uploads" / material.path
    return material_id, path


def kid():
    client = TestClient(app, headers=HEADERS)
    response = client.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert response.status_code == 200
    client.headers["Authorization"] = "Bearer " + response.json()["token"]
    return client


def preview(client, child, **selection):
    response = client.post(f"/api/children/{child['id']}/materials/delete-preview", json=selection)
    assert response.status_code == 200, response.text
    return response.json()


def confirm_delete(client, child, token):
    return client.post(f"/api/children/{child['id']}/materials/bulk-delete", json={"selection_token": token, "delete_linked_units": True})


def saved_round(child, material_id):
    with DB.begin() as db:
        unit = LearningUnit(
            child_id=child["id"],
            material_id=material_id,
            status="completed",
            completed=int(now()),
            synthetic=True,
            provider="synthetic",
            **sample_unit(),
        )
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material_id, revision=1))
        attempt = Attempt(
            unit_id=unit.id,
            question_id=unit.questions[0]["id"],
            answer="synthetic stored answer",
            outcome="correct",
            assisted=False,
        )
        db.add(attempt)
        db.flush()
        return unit.id, attempt.id


def test_child_delete_confirmed_photo_cascades_round_and_answers_after_counted_preview(api, household):
    _, child = household
    mid, path = photo(api, child)
    unit_id, attempt_id = saved_round(child, mid)
    with kid() as client:
        assert client.delete(f"/api/materials/{mid}").status_code == 409
        data = preview(client, child, ids=[mid])
        assert data['unit_count'] == 1 and data['answer_count'] == 1
        assert confirm_delete(client, child, data['selection_token']).status_code == 200
        assert client.get(f"/api/materials/{mid}/image").status_code == 404
    assert not path.exists()
    with DB() as db:
        assert db.get(Material, mid) is None
        assert db.get(LearningUnit, unit_id) is None
        assert db.get(Attempt, attempt_id) is None
        assert not list(db.scalars(select(UnitSource).where(UnitSource.unit_id == unit_id)))


def test_bulk_all_matching_spans_pages_and_filters_without_inference(api, household):
    _, child = household
    selected = [photo(api, child, title=f"Mathe {i}")[0] for i in range(24)]
    keep, _ = photo(api, child, subject="Englisch")
    with kid() as client:
        before = client.get(f"/api/children/{child['id']}/materials?page_size=20").json()
        assert before["pages"] == 2
        data = preview(client, child, all_matching=True, filters={"subject": "Mathematik", "status": "confirmed"})
        assert data["count"] == 24 and len(data["sample"]) == 5
        assert confirm_delete(client, child, data["selection_token"]).json() == {"deleted_count": 24}
        assert confirm_delete(client, child, data["selection_token"]).status_code == 409
    with DB() as db:
        assert list(db.scalars(select(Material.id))) == [keep]
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert not list(db.scalars(select(Material).where(Material.id.in_(selected))))


@pytest.mark.parametrize("change", ["revision", "new_match", "delete", "confirmation"])
def test_bulk_rejects_changed_snapshot_without_partial_deletion(api, household, change):
    _, child = household
    mids = [photo(api, child)[0] for _ in range(2)]
    data = preview(api, child, all_matching=True, filters={"subject": "Mathematik"})
    with DB.begin() as db:
        if change == "revision":
            db.get(Material, mids[0]).revision += 1
        elif change == "confirmation":
            db.get(Material, mids[0]).confirmed = False
        elif change == "delete":
            db.delete(db.get(Material, mids[0]))
    if change == "new_match":
        photo(api, child)
    response = confirm_delete(api, child, data["selection_token"])
    assert response.status_code == 409, response.text
    with DB() as db:
        assert db.get(Material, mids[1]) is not None


def test_bulk_token_scope_expiry_tampering_and_cross_child(api, household):
    owner, child = household
    mid, _ = photo(api, child)
    sibling = create_child(api, owner, "synthetic-sibling")
    data = preview(api, child, ids=[mid])
    with kid() as client:
        assert confirm_delete(client, child, data["selection_token"]).status_code == 409
        assert (
            client.post(f"/api/children/{child['id']}/materials/delete-preview", json={"ids": ["f" * 32]}).status_code
            == 404
        )
    assert confirm_delete(api, sibling, data["selection_token"]).status_code == 409
    assert confirm_delete(api, child, data["selection_token"][:-4] + "AAAA").status_code == 409
    plain = crypt().decrypt(data["selection_token"].encode())
    expired = crypt().encrypt_at_time(plain, int(time.time()) - 601).decode()
    assert confirm_delete(api, child, expired).status_code == 409
    with DB() as db:
        assert db.get(Material, mid)


def test_bulk_child_cannot_select_sibling_and_view_parent_admin_blocked(api, household):
    owner, child = household
    mid, _ = photo(api, child)
    sibling = create_child(api, owner, "synthetic-sibling")
    other, _ = photo(api, sibling)
    with kid() as client:
        assert (
            client.post(f"/api/children/{child['id']}/materials/delete-preview", json={"ids": [mid, other]}).status_code
            == 404
        )
        assert (
            client.post(
                f"/api/children/{sibling['id']}/materials/delete-preview", json={"all_matching": True}
            ).status_code
            == 404
        )
    with DB.begin() as db:
        for role in ("parent", "admin"):
            user = User(
                username="synthetic-" + role,
                display_name="Artificial",
                role=role,
                verified=True,
                password_hash=password_hash("synthetic-secure-password"),
            )
            db.add(user)
            db.flush()
            if role == "parent":
                db.add(Membership(user_id=user.id, family_id=owner["families"][0]["id"], permission="view"))
    for role in ("parent", "admin"):
        with TestClient(app, headers=HEADERS) as client:
            response = client.post(
                "/api/auth/login", json={"username": "synthetic-" + role, "password": "synthetic-secure-password"}
            )
            assert response.status_code == 200, response.text
            client.headers["Authorization"] = "Bearer " + response.json()["token"]
            assert (
                client.post(f"/api/children/{child['id']}/materials/delete-preview", json={"ids": [mid]}).status_code
                == 403
            )
            assert client.delete(f"/api/materials/{mid}").status_code == 403
            assert (
                client.post(
                    f"/api/materials/{mid}/reprocess",
                    json={"revision": 1},
                    headers={"Idempotency-Key": "notebook-permission"},
                ).status_code
                == 403
            )


@pytest.mark.parametrize("status", ["queued", "running"])
def test_bulk_blocks_processing_including_after_preview(api, household, status):
    _, child = household
    mid, path = photo(api, child)
    data = preview(api, child, ids=[mid])
    with DB.begin() as db:
        db.add(
            Job(
                child_id=child["id"],
                kind="extract",
                status=status,
                payload={"material_id": mid},
                idempotency="pending-synthetic",
            )
        )
    assert confirm_delete(api, child, data["selection_token"]).status_code == 409
    assert api.delete(f"/api/materials/{mid}").status_code == 409
    assert path.exists()


def allow_reserved(monkeypatch):
    def reserve(db, family, child_id, job_id, kind, **kwargs):
        config = db.get(ProviderConfig, 1)
        db.add(
            Usage(
                family_id=family.id,
                child_id=child_id,
                job_id=job_id,
                function=kind,
                provider=config.provider,
                model=config.model,
                config_revision=config.revision,
                reserved_micros=17,
                bucket_ids=[],
                input_tokens=0,
                output_tokens=0,
                cost_micros=None,
            )
        )

    monkeypatch.setattr(materials, "reserve", reserve)
    monkeypatch.setattr("schulpilot.providers.external_allowed", lambda *args, **kwargs: None)


def test_reprocess_copies_photo_once_and_keeps_original_unit_answers(api, household, monkeypatch):
    _, child = household
    mid, path = photo(api, child)
    unit_id, attempt_id = saved_round(child, mid)
    allow_reserved(monkeypatch)
    with kid() as client:
        headers = {"Idempotency-Key": "synthetic-reprocess-one"}
        response = client.post(f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers=headers)
        assert response.status_code == 202, response.text
        data = response.json()
        assert data["material_id"] != mid
        assert client.post(f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers=headers).json() == data
        assert client.post(f"/api/materials/{mid}/reprocess", json={"revision": 2}, headers=headers).status_code == 409
        fresh = client.get(f"/api/materials/{data['material_id']}").json()
        assert fresh["confirmed"] is False and fresh["status"] == "uploaded" and fresh["has_image"]
        assert fresh["processing_job"]["id"] == data["id"]
        assert fresh["processing_job"]["status"] == "queued"
        own_job = client.get(f"/api/jobs/{data['id']}").json()
        assert own_job["material_id"] == data["material_id"] and own_job["material_id"] != mid
    with DB() as db:
        old, new = db.get(Material, mid), db.get(Material, data["material_id"])
        assert old.confirmed and old.revision == 1
        assert old.path != new.path
        assert path.read_bytes() == (settings.data_dir / "uploads" / new.path).read_bytes()
        assert (settings.data_dir / "uploads" / new.path).stat().st_mode & 0o777 == 0o600
        assert db.get(Attempt, attempt_id).answer == "synthetic stored answer"
        assert db.get(LearningUnit, unit_id).material_id == mid
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1
        material_actions.validate_reprocess_job(db, db.get(Job, data["id"]))


@pytest.mark.parametrize("invalid", ["revision", "missing_photo", "synthetic"])
def test_reprocess_rejects_invalid_photo_without_job(api, household, invalid):
    _, child = household
    mid, path = photo(api, child)
    with DB.begin() as db:
        row = db.get(Material, mid)
        if invalid == "revision":
            row.revision = 2
        if invalid == "synthetic":
            row.synthetic = True
    if invalid == "missing_photo":
        path.unlink()
    response = api.post(
        f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers={"Idempotency-Key": "synthetic-invalid"}
    )
    assert response.status_code == 409
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Material)) == 1


def test_reprocess_reservation_failure_rolls_back_new_source_and_file(api, household, monkeypatch):
    _, child = household
    mid, path = photo(api, child)
    existing_files = set(path.parent.glob("*.jpg"))
    monkeypatch.setattr(
        materials, "reserve", lambda *args, **kwargs: (_ for _ in ()).throw(ProviderError("synthetic quota failure"))
    )
    response = api.post(
        f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers={"Idempotency-Key": "synthetic-quota"}
    )
    assert response.status_code == 503
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Material)) == 1
    assert set(path.parent.glob("*.jpg")) == existing_files


@pytest.mark.parametrize("change", ["source", "session", "provider", "family_permission"])
def test_reprocess_guard_rejects_revoked_authority_or_changed_source(api, household, monkeypatch, change):
    owner, child = household
    mid, _ = photo(api, child)
    allow_reserved(monkeypatch)
    response = api.post(
        f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers={"Idempotency-Key": "synthetic-guard"}
    )
    assert response.status_code == 202, response.text
    with DB.begin() as db:
        job = db.get(Job, response.json()["id"])
        if change == "source":
            db.get(Material, mid).revision += 1
        elif change == "session":
            db.get(Session, job.payload["reprocess_guard"]["session_id"]).revoked = True
        elif change == "provider":
            db.get(ProviderConfig, 1).revision += 1
        elif change == "family_permission":
            db.scalar(select(Membership).where(Membership.family_id == owner["families"][0]["id"])).permission = "view"
    with DB() as db:
        with pytest.raises((ProviderError, __import__("fastapi").HTTPException)):
            material_actions.validate_reprocess_job(db, db.get(Job, response.json()["id"]))


def test_parallel_reprocess_requests_create_one_source_and_reservation(api, household, monkeypatch):
    _, child = household
    if settings.database_url.startswith("sqlite"):
        pytest.skip("PostgreSQL row-lock concurrency check")
    mid, _ = photo(api, child)
    allow_reserved(monkeypatch)

    def send():
        with TestClient(app, headers={**HEADERS, "Authorization": api.headers["Authorization"]}) as client:
            return client.post(
                f"/api/materials/{mid}/reprocess",
                json={"revision": 1},
                headers={"Idempotency-Key": "same-synthetic-reprocess"},
            )

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: send(), range(2)))
    assert [r.status_code for r in results] == [202, 202]
    assert results[0].json()["material_id"] == results[1].json()["material_id"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Material)) == 2
        assert db.scalar(select(func.count()).select_from(Job)) == 1
        assert db.scalar(select(func.count()).select_from(Usage)) == 1


def test_all_matching_token_stays_small_for_thousands_of_pages(api, household):
    _, child = household
    with DB.begin() as db:
        db.add_all(
            [
                Material(
                    child_id=child["id"],
                    title=f"Künstliche Notiz {index}",
                    subject="Mathematik",
                    content="Nur synthetische Daten",
                    confirmed=True,
                    status="confirmed",
                )
                for index in range(1100)
            ]
        )
    data = preview(api, child, all_matching=True)
    assert data["count"] == 1100
    assert len(data["selection_token"]) < 2000
    assert confirm_delete(api, child, data["selection_token"]).json() == {"deleted_count": 1100}


def test_bulk_filters_match_library_date_subject_status_and_search(api, household):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from schulpilot.db import Subject

    _, child = household
    selected, _ = photo(api, child, title="Künstliche Bruchseite")
    photo(api, child, title="Künstliche Bruchseite", subject="Englisch")
    photo(api, child, title="Künstliche Bruchseite", confirmed=False)
    photo(api, child, title="Alte Bruchseite")
    with DB.begin() as db:
        subject_id = db.scalar(select(Subject.id).where(Subject.title == "Mathematik"))
        for row in db.scalars(select(Material).where(Material.subject == "Mathematik")):
            row.subject_id = subject_id
            row.created = int(
                datetime(
                    2026, 10, 19 if row.title.startswith("Künstliche") else 18, 14, tzinfo=ZoneInfo("Europe/Berlin")
                ).timestamp()
            )
    filters = {
        "q": "Künstliche Bruchseite",
        "subject_id": subject_id,
        "status": "confirmed",
        "since": "2026-10-19",
        "until": "2026-10-19",
        "sort": "oldest",
    }
    listing = api.get(f"/api/children/{child['id']}/materials", params=filters).json()
    assert [row["id"] for row in listing["items"]] == [selected]
    data = preview(api, child, all_matching=True, filters=filters)
    assert data["count"] == 1 and data["sample"][0]["id"] == selected
    assert confirm_delete(api, child, data["selection_token"]).json() == {"deleted_count": 1}
    assert api.get(f"/api/children/{child['id']}/materials").json()["total"] == 3


def test_bulk_snapshot_detects_ocr_text_update_without_revision_increment(api, household):
    _, child = household
    mid, path = photo(api, child, confirmed=False)
    data = preview(api, child, ids=[mid])
    with DB.begin() as db:
        db.get(Material, mid).content = "Eine neue künstliche Abschrift derselben OCR-Revision."
    assert confirm_delete(api, child, data["selection_token"]).status_code == 409
    assert path.exists()


def test_bulk_keeps_unit_before_child_lock_order_with_concurrent_answer(api, household):
    from threading import Event

    from schulpilot.db import Child, engine
    from sqlalchemy import update

    if engine.dialect.name != "postgresql":
        pytest.skip("Requires genuine PostgreSQL row locks")
    _, child = household
    mid, _ = photo(api, child)
    unit_id, attempt_id = saved_round(child, mid)
    data = preview(api, child, ids=[mid])
    begun = Event()

    def remove():
        with TestClient(app, headers={**HEADERS, "Authorization": api.headers["Authorization"]}) as client:
            begun.set()
            return confirm_delete(client, child, data["selection_token"])

    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as answer:
            answer.scalar(select(LearningUnit).where(LearningUnit.id == unit_id).with_for_update())
            pending = pool.submit(remove)
            assert begun.wait(5)
            # The deletion must wait for Unit, leaving Child obtainable by the
            # answer transaction. PostgreSQL's bounded timeout catches reversal.
            answer.execute(__import__("sqlalchemy").text("SET LOCAL lock_timeout = '2s'"))
            answer.execute(update(Child).where(Child.id == child["id"]).values(grade=Child.grade))
        response = pending.result(10)
    assert response.status_code == 200, response.text
    with DB() as db:
        assert db.get(Attempt, attempt_id) is None


@pytest.mark.parametrize("change", ["none", "source_after", "session_before", "provider_after"])
def test_reprocess_worker_checks_before_and_after_transport_and_keeps_billed_errors(
    api, household, monkeypatch, change
):
    from schulpilot import worker
    from schulpilot.providers import Result

    _, child = household
    mid, _ = photo(api, child)
    allow_reserved(monkeypatch)
    response = api.post(
        f"/api/materials/{mid}/reprocess", json={"revision": 1}, headers={"Idempotency-Key": "synthetic-worker"}
    )
    assert response.status_code == 202, response.text
    job_id, clone_id = response.json()["id"], response.json()["material_id"]
    with DB.begin() as db:
        job = db.get(Job, job_id)
        job.status, job.started = "running", int(now())
        if change == "session_before":
            db.get(Session, job.payload["reprocess_guard"]["session_id"]).revoked = True
    calls = []

    def transport(*args, **kwargs):
        calls.append(True)
        with DB.begin() as db:
            if change == "source_after":
                db.get(Material, mid).revision += 1
            elif change == "provider_after":
                db.get(ProviderConfig, 1).revision += 1
        return Result(
            {
                "legibility": "readable",
                "subject": "Mathematik",
                "topic": "Brüche kürzen",
                "content": "Künstlicher Stoff: Beim Kürzen teilen wir Zähler und Nenner durch dieselbe Zahl.",
                "uncertainties": [],
                "homework": [],
                "source_blocks": [],
            },
            30,
            12,
            9,
            cost_source="reported",
        )

    monkeypatch.setattr(worker, "request_provider", transport)
    worker.process(job_id)
    with DB() as db:
        job, clone = db.get(Job, job_id), db.get(Material, clone_id)
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        if change == "none":
            assert job.status == "completed" and clone.status == "review" and clone.content
            from schulpilot.source_lineage_models import SourceRevision

            assert job.result["material_id"] == clone_id and not clone.confirmed
            source = db.get(SourceRevision, job.result["source_snapshot_id"])
            assert source and source.material_id == clone_id and source.revision == clone.revision
            assert usage.cost_micros == 9
        else:
            assert job.status == "failed" and clone.status == "uploaded" and clone.content == ""
            assert usage.cost_micros == (None if change == "session_before" else 9)
            assert usage.status == ("failed_unknown" if change == "session_before" else "failed_billed")
        assert db.get(Material, mid).confirmed
    assert len(calls) == (0 if change == "session_before" else 1)


def test_fixed_fixture_in_bulk_is_never_silently_omitted_or_deleted(api, household):
    from schulpilot.fixtures import FIXTURE_ID

    _, child = household
    own, path = photo(api, child)
    fixed, fixed_path = photo(api, child)
    with DB.begin() as db:
        db.get(Material, fixed).fixture_id = FIXTURE_ID
        db.get(Material, fixed).synthetic = True
    response = api.post(f"/api/children/{child['id']}/materials/delete-preview", json={"all_matching": True})
    assert response.status_code == 409
    assert api.delete(f"/api/materials/{fixed}").status_code == 409
    assert path.exists() and fixed_path.exists()
    with DB() as db:
        assert db.get(Material, own) and db.get(Material, fixed)


def test_bulk_rechecks_session_revocation_after_waiting_for_child_lock(api, household, monkeypatch):
    from threading import Event

    from schulpilot.db import Child, engine
    from sqlalchemy import update

    if engine.dialect.name != "postgresql":
        pytest.skip("Requires genuine PostgreSQL row locks")
    _, child = household
    mid, path = photo(api, child)
    data = preview(api, child, ids=[mid])
    reached = Event()
    original = material_actions.lock_units

    def before_child(db, child_id, ids):
        result = original(db, child_id, ids)
        reached.set()
        return result

    monkeypatch.setattr(material_actions, "lock_units", before_child)

    def remove():
        with TestClient(app, headers={**HEADERS, "Authorization": api.headers["Authorization"]}) as client:
            return confirm_delete(client, child, data["selection_token"])

    payload = __import__("json").loads(crypt().decrypt(data["selection_token"].encode()))
    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as locker:
            locker.execute(update(Child).where(Child.id == child["id"]).values(grade=Child.grade))
            pending = pool.submit(remove)
            assert reached.wait(5)
            locker.get(Session, payload["session"]).revoked = True
        response = pending.result(10)
    assert response.status_code == 401, response.text
    assert path.exists()
    with DB() as db:
        assert db.get(Material, mid)


def test_job_status_binds_extract_to_its_actual_material_and_denies_sibling(api, household):
    owner, child = household
    sibling = create_child(api, owner, "synthetic-job-sibling")
    first, _ = photo(api, child)
    second, _ = photo(api, child)
    foreign, _ = photo(api, sibling)
    with DB.begin() as db:
        own = Job(
            child_id=child["id"], kind="extract", payload={"material_id": second}, idempotency="synthetic-own-status"
        )
        other = Job(
            child_id=sibling["id"],
            kind="extract",
            payload={"material_id": foreign},
            idempotency="synthetic-foreign-status",
        )
        db.add_all([own, other])
        db.flush()
        own_id, foreign_id = own.id, other.id
    with kid() as client:
        response = client.get(f"/api/jobs/{own_id}")
        assert response.status_code == 200
        assert response.json()["material_id"] == second and response.json()["material_id"] != first
        assert client.get(f"/api/jobs/{foreign_id}").status_code == 404
        assert client.get(f"/api/materials/{foreign}").status_code == 404
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
