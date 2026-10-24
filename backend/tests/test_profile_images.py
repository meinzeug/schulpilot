"""Synthetic profile photographs exercise private transport, CAS and erasure."""

import hashlib
import io
import json
import os
import threading
import uuid
import zipfile
from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import HEADERS
from conftest import register as register_account
from fastapi.testclient import TestClient
from PIL import Image
from schulpilot import profile_images
from schulpilot.config import settings
from schulpilot.db import DB, Activity, Audit, Family, Job, Session, Usage, User, UserAvatar, now
from schulpilot.erasure import prune_orphan_images, reconcile
from schulpilot.main import app, request_body_limit
from schulpilot.security import digest
from sqlalchemy import func, select

URL = "/api/auth/me/avatar"


def register(api, mailbox):
    user = register_account(api, mailbox)
    api.headers["X-Schulpilot-Account"] = user["id"]
    return user


def bind_actor(api):
    if "X-Schulpilot-Account" not in api.headers:
        api.headers["X-Schulpilot-Account"] = api.get("/api/auth/me").json()["id"]


def picture(fmt="PNG", size=(840, 460), color=(50, 100, 180), **kwargs):
    output = io.BytesIO()
    Image.new("RGB", size, color).save(output, fmt, **kwargs)
    return output.getvalue()


def headers(revision=None, key=None):
    return {"If-Match": revision or "none", "Idempotency-Key": key or uuid.uuid4().hex}


def upload(api, raw=None, revision=None, key=None, mime="application/octet-stream"):
    bind_actor(api)
    return api.put(
        URL, files={"file": ("private-original-name.png", raw or picture(), mime)}, headers=headers(revision, key)
    )


def own_files(user_id):
    return list(
        (settings.data_dir / "uploads").glob("avatar-" + hashlib.sha256(user_id.encode()).hexdigest() + "-*.jpg")
    )


def assert_no_learning():
    with DB() as db:
        for model in (Activity, Job, Usage):
            assert db.scalar(select(func.count()).select_from(model)) == 0


def assert_meta(data, present):
    assert set(data) == {"has_avatar", "avatar_revision", "avatar_url", "avatar_updated_at"}
    assert data["has_avatar"] is present
    assert len(data["avatar_revision"]) == 32
    assert data["avatar_url"] == ("/auth/me/avatar?revision=" + data["avatar_revision"] if present else None)
    assert isinstance(data["avatar_updated_at"], int)


@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP"])
def test_upload_actual_format_private_revision_and_metadata_only(api, mailbox, fmt):
    user = register(api, mailbox)
    assert api.get("/api/auth/me").json()["avatar_revision"] is None
    result = upload(api, picture(fmt))
    assert result.status_code == 200, result.text
    meta = result.json()
    assert_meta(meta, True)
    assert {k: api.get("/api/auth/me").json()[k] for k in meta} == meta
    image = api.get("/api" + meta["avatar_url"])
    assert image.status_code == 200
    assert image.headers["cache-control"] == "no-store"
    assert image.headers["x-content-type-options"] == "nosniff"
    assert image.headers["content-type"] == "image/jpeg"
    with Image.open(io.BytesIO(image.content)) as thumb:
        assert max(thumb.size) == 512
        assert not thumb.getexif()
        assert "exif" not in thumb.info and "icc_profile" not in thumb.info
    paths = own_files(user["id"])
    assert len(paths) == 1 and paths[0].stat().st_mode & 0o777 == 0o600
    assert "private-original-name" not in paths[0].name
    assert_no_learning()


def test_exif_rotation_and_metadata_are_processed_locally(api, mailbox):
    register(api, mailbox)
    exif = Image.Exif()
    exif[274] = 6
    exif[270] = "PRIVATE synthetic metadata"
    result = upload(api, picture("JPEG", (800, 400), exif=exif, icc_profile=b"synthetic-icc"))
    assert result.status_code == 200
    response = api.get("/api" + result.json()["avatar_url"])
    with Image.open(io.BytesIO(response.content)) as thumb:
        assert thumb.size == (256, 512)
        assert not thumb.getexif() and "icc_profile" not in thumb.info
    assert b"PRIVATE" not in response.content and b"synthetic-icc" not in response.content


@pytest.mark.parametrize("kind", ["svg", "gif", "corrupt", "animated", "pixels", "empty", "bytes"])
def test_invalid_or_oversized_images_do_not_write_or_echo_input(api, mailbox, kind):
    user = register(api, mailbox)
    if kind == "svg":
        raw = b'<svg xmlns="http://www.w3.org/2000/svg"><text>private-synthetic</text></svg>'
    elif kind == "gif":
        raw = picture("GIF")
    elif kind == "corrupt":
        raw = b"private-synthetic-not-an-image"
    elif kind == "animated":
        output = io.BytesIO()
        Image.new("RGB", (20, 20), "red").save(
            output, "PNG", save_all=True, append_images=[Image.new("RGB", (20, 20), "blue")], duration=100, loop=0
        )
        raw = output.getvalue()
    elif kind == "pixels":
        raw = picture(size=(4000, 2001))
    elif kind == "empty":
        raw = b""
    else:
        raw = b"x" * (profile_images.MAX_UPLOAD + 1)
    result = api.put(URL, files={"file": ("private-synthetic.png", raw, "image/png")}, headers=headers())
    assert result.status_code == (413 if kind == "bytes" else 422), result.text
    assert "private-synthetic" not in result.text
    assert not own_files(user["id"])
    with DB() as db:
        assert db.get(UserAvatar, user["id"]) is None
    assert_no_learning()


def test_header_csrf_actual_received_body_and_origin_limits(api, mailbox):
    register(api, mailbox)
    assert api.put(URL, files={"file": ("a.png", picture())}).status_code == 428
    for bad in (
        {"If-Match": "other", "Idempotency-Key": "k"},
        {"If-Match": "none"},
        {"If-Match": "none", "Idempotency-Key": "x" * 101},
    ):
        assert api.put(URL, files={"file": ("a.png", picture())}, headers=bad).status_code == 422
    assert upload(api, key="valid", mime="image/svg+xml").status_code == 200  # actual bytes, never MIME trust
    assert api.delete(URL, headers={**headers(), "Origin": "https://foreign.invalid"}).status_code == 403
    with TestClient(app, headers={"Authorization": api.headers["Authorization"]}) as unsafe:
        assert unsafe.delete(URL, headers=headers()).status_code == 403
    assert request_body_limit(URL) == 6 * 1024 * 1024
    assert request_body_limit("/api/auth/me") == 64 * 1024

    # No Content-Length: the same policy must bound actual received chunks.
    def chunks():
        yield b'--synthetic-boundary\r\nContent-Disposition: form-data; name="file"; filename="test.png"\r\nContent-Type: image/png\r\n\r\n'
        for _ in range(13):
            yield b"x" * (512 * 1024)
        yield b"\r\n--synthetic-boundary--\r\n"

    result = api.put(
        URL, content=chunks(), headers={**headers(), "Content-Type": "multipart/form-data; boundary=synthetic-boundary"}
    )
    assert result.status_code == 413, result.text


def test_replace_delete_idempotency_and_aba_guard(api, mailbox):
    user = register(api, mailbox)
    first = upload(api, key="first").json()
    first_path = own_files(user["id"])[0]
    assert upload(api, key="first").json() == first
    assert upload(api, picture(color=(1, 2, 3)), key="first").status_code == 409
    assert api.delete(URL, headers=headers(key="first")).status_code == 409
    assert upload(api).status_code == 409
    second = upload(api, picture(color=(1, 2, 3)), first["avatar_revision"], "second").json()
    assert_meta(second, True)
    assert not first_path.exists() and len(own_files(user["id"])) == 1
    assert api.get("/api" + first["avatar_url"]).status_code == 404
    deleted = api.delete(URL, headers=headers(second["avatar_revision"], "delete")).json()
    assert_meta(deleted, False)
    assert deleted["avatar_revision"] != second["avatar_revision"]
    assert not own_files(user["id"])
    assert api.delete(URL, headers=headers(second["avatar_revision"], "delete")).json() == deleted
    assert upload(api, key="after-delete").status_code == 409
    assert upload(api, revision=deleted["avatar_revision"], key="after-delete").status_code == 200
    with DB() as db:
        actions = list(
            db.scalars(select(Audit.action).where(Audit.actor == user["id"], Audit.action.like("account.avatar_%")))
        )
        assert actions == [
            "account.avatar_upload",
            "account.avatar_upload",
            "account.avatar_delete",
            "account.avatar_upload",
        ]
    assert_no_learning()


def test_all_roles_own_only_and_cookie_transport(api, mailbox, household):
    parent, child = household
    parent_meta = upload(api).json()
    token = api.headers["Authorization"]
    with TestClient(app, headers=HEADERS) as kid:
        logged = kid.post(
            "/api/auth/login", json={"username": child["username"], "password": "secure-child-pass-123"}
        ).json()
        kid.headers["Authorization"] = "Bearer " + logged["token"]
        kid.headers["X-Schulpilot-Account"] = logged["user"]["id"]
        assert kid.get("/api" + parent_meta["avatar_url"]).status_code == 404
        kid_meta = upload(kid, picture(color=(1, 2, 3))).json()
        assert kid_meta["avatar_revision"] != parent_meta["avatar_revision"]
        assert (
            kid.get(URL + "?revision=" + parent_meta["avatar_revision"] + "&user_id=" + parent["id"]).status_code == 404
        )
    with DB.begin() as db:
        admin = User(
            username="synthetic-avatar-admin",
            display_name="Example admin",
            password_hash="not-used",
            role="admin",
            verified=True,
        )
        db.add(admin)
        db.flush()
        admin_id = admin.id
        db.add(
            Session(
                user_id=admin.id,
                token_hash=digest("synthetic-avatar-admin-token"),
                device="synthetic",
                expires=int(now()) + 1000,
            )
        )
    with TestClient(
        app,
        headers={**HEADERS, "Authorization": "Bearer synthetic-avatar-admin-token", "X-Schulpilot-Account": admin_id},
    ) as admin_api:
        assert admin_api.get("/api" + parent_meta["avatar_url"]).status_code == 404
        assert upload(admin_api).status_code == 200
        assert len(own_files(admin_id)) == 1
    # A normal HttpOnly-cookie session needs no public asset URL or bearer in URL.
    with TestClient(app, headers={"X-Schulpilot-Request": "1"}) as web:
        response = web.post(
            "/api/auth/login", json={"username": parent["username"], "password": "secure-parent-pass-123"}
        )
        assert "token" not in response.json()
        web.headers["X-Schulpilot-Account"] = parent["id"]
        assert web.get("/api" + parent_meta["avatar_url"]).status_code == 200
        assert web.post("/api/auth/logout").status_code == 200
        assert web.get("/api" + parent_meta["avatar_url"]).status_code == 401
    assert api.headers["Authorization"] == token
    with TestClient(app, headers=HEADERS) as anonymous:
        assert anonymous.get("/api" + parent_meta["avatar_url"]).status_code == 401
    assert_no_learning()


@pytest.mark.parametrize("change", ["revoke", "disable", "delete"])
def test_revoked_session_or_disabled_account_during_decode_cannot_save(api, mailbox, monkeypatch, change):
    user = register(api, mailbox)
    normalize = profile_images.normalize

    def revoked(raw):
        data = normalize(raw)
        with DB.begin() as db:
            if change == "revoke":
                db.scalar(select(Session).where(Session.user_id == user["id"])).revoked = True
            elif change == "disable":
                db.get(User, user["id"]).disabled = True
            else:
                db.delete(db.get(User, user["id"]))
        return data

    monkeypatch.setattr(profile_images, "normalize", revoked)
    assert upload(api).status_code == 401
    assert not own_files(user["id"])
    with DB() as db:
        assert db.get(UserAvatar, user["id"]) is None


def test_two_concurrent_first_uploads_have_one_cas_winner(api, mailbox, monkeypatch):
    user = register(api, mailbox)
    normalize = profile_images.normalize
    barrier = threading.Barrier(2)

    def synchronized(raw):
        value = normalize(raw)
        barrier.wait(timeout=10)
        return value

    monkeypatch.setattr(profile_images, "normalize", synchronized)
    auth = api.headers["Authorization"]

    def send(color):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            return upload(client, picture(color=color)).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(send, [(1, 2, 3), (50, 100, 180)]))
    assert sorted(results) == [200, 409]
    assert len(own_files(user["id"])) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(UserAvatar)) == 1
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "account.avatar_upload")) == 1


def test_failed_commit_keeps_previous_image_and_removes_new_file(api, mailbox, monkeypatch):
    user = register(api, mailbox)
    old = upload(api).json()
    original = DB.class_.commit

    def fail_avatar_commit(db):
        if any(isinstance(row, UserAvatar) and row.revision != old["avatar_revision"] for row in db.dirty):
            raise RuntimeError("synthetic commit interruption")
        return original(db)

    monkeypatch.setattr(DB.class_, "commit", fail_avatar_commit)
    result = upload(api, picture(color=(1, 2, 3)), old["avatar_revision"])
    assert result.status_code == 500
    assert len(own_files(user["id"])) == 1
    assert api.get("/api" + old["avatar_url"]).status_code == 200
    assert api.get("/api/auth/me").json()["avatar_revision"] == old["avatar_revision"]


def test_exports_include_only_authorized_profile_photos_and_without_photo_option(api, mailbox, household):
    user, child = household
    upload(api)
    with TestClient(app, headers=HEADERS) as kid:
        token = kid.post(
            "/api/auth/login", json={"username": child["username"], "password": "secure-child-pass-123"}
        ).json()["token"]
        kid.headers["Authorization"] = "Bearer " + token
        kid_meta = upload(kid).json()
    exported = api.get(f"/api/children/{child['id']}/export")
    assert exported.status_code == 200
    with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
        assert "profile/avatar.jpg" in archive.namelist()
        child_json = json.loads(archive.read("child.json"))
        assert child_json["profile_image"]["avatar_revision"] == kid_meta["avatar_revision"]
        assert "request_digest" not in archive.read("child.json").decode()
        assert "account/avatar.jpg" not in archive.namelist()
    no_photo = api.get(f"/api/children/{child['id']}/export?include_photos=false")
    with zipfile.ZipFile(io.BytesIO(no_photo.content)) as archive:
        assert archive.namelist() == ["child.json"]
    family_export = api.get(f"/api/families/{user['families'][0]['id']}/export")
    with zipfile.ZipFile(io.BytesIO(family_export.content)) as archive:
        assert "account/avatar.jpg" in archive.namelist()
        assert f"children/{child['id']}/avatar.jpg" in archive.namelist()
        assert "request_key" not in archive.read("family.json").decode()


def test_account_child_erasure_and_retention_remove_private_files(api, mailbox, household):
    user, child = household
    upload(api)
    with TestClient(app, headers=HEADERS) as kid:
        token = kid.post(
            "/api/auth/login", json={"username": child["username"], "password": "secure-child-pass-123"}
        ).json()["token"]
        kid.headers["Authorization"] = "Bearer " + token
        upload(kid)
        kid_id = kid.get("/api/auth/me").json()["id"]
    assert (
        api.request("DELETE", f"/api/children/{child['id']}", json={"password": "secure-parent-pass-123"}).status_code
        == 200
    )
    assert not own_files(kid_id)
    assert len(own_files(user["id"])) == 1
    assert api.request("DELETE", "/api/account", json={"password": "secure-parent-pass-123"}).status_code == 200
    assert not own_files(user["id"])
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(UserAvatar)) == 0
    # Journal replay collects a restored user's avatar before its FK cascade.
    with DB.begin() as db:
        restored = User(
            id=uuid.uuid4().hex,
            username="restored-synthetic",
            display_name="Example",
            role="parent",
            password_hash="none",
            verified=True,
        )
        db.add(restored)
        db.flush()
        row = UserAvatar(
            user_id=restored.id,
            revision=uuid.uuid4().hex,
            image_digest="a" * 64,
            updated=int(now()),
            request_key="key",
            request_digest="b" * 64,
        )
        db.add(row)
        db.flush()
        restored_name = profile_images.filename(restored.id, row.revision)
        paths = reconcile(db, [{"scope": "user", "target": restored.id}])
        assert paths == [restored_name]
        assert db.scalar(select(func.count()).select_from(UserAvatar).where(UserAvatar.user_id == restored.id)) == 0
    orphan = settings.data_dir / "uploads" / restored_name
    orphan.write_bytes(b"synthetic orphan")
    os.utime(orphan, (now() - 7200, now() - 7200))
    with DB() as db:
        assert prune_orphan_images(db) >= 1
    assert not orphan.exists()


def test_active_file_survives_orphan_sweep_and_demo_retention_deletes_owner(api, mailbox, household):
    from schulpilot.worker import maintenance

    user, _ = household
    upload(api)
    photo = own_files(user["id"])[0]
    os.utime(photo, (now() - 7200, now() - 7200))
    with DB() as db:
        prune_orphan_images(db)
    assert photo.exists()
    with DB.begin() as db:
        db.get(Family, user["families"][0]["id"]).expires = int(now()) - 1
    maintenance()
    assert not photo.exists()
    with DB() as db:
        assert db.get(UserAvatar, user["id"]) is None


def test_concurrent_replay_uses_one_revision_file_and_audit(api, mailbox, monkeypatch):
    user = register(api, mailbox)
    original = profile_images.normalize
    barrier = threading.Barrier(2)

    def together(raw):
        data = original(raw)
        barrier.wait(timeout=10)
        return data

    monkeypatch.setattr(profile_images, "normalize", together)
    auth = api.headers["Authorization"]
    raw = picture()

    def send(_):
        with TestClient(app, headers={**HEADERS, "Authorization": auth}) as client:
            response = upload(client, raw, key="same-synthetic-request")
            assert response.status_code == 200, response.text
            return response.json()

    with ThreadPoolExecutor(max_workers=2) as pool:
        replies = list(pool.map(send, range(2)))
    assert replies[0] == replies[1]
    assert len(own_files(user["id"])) == 1
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "account.avatar_upload")) == 1


def test_private_reader_rejects_tampering_and_symlinks_without_serving_target(api, mailbox, tmp_path):
    user = register(api, mailbox)
    meta = upload(api).json()
    photo = own_files(user["id"])[0]
    photo.write_bytes(b"synthetic-tampered-bytes")
    assert api.get("/api" + meta["avatar_url"]).status_code == 404
    target = tmp_path / "private-other-file"
    target.write_bytes(b"synthetic-other-file-never-read")
    photo.unlink()
    photo.symlink_to(target)
    response = api.get("/api" + meta["avatar_url"])
    assert response.status_code == 404
    assert b"synthetic-other-file" not in response.content
    # Removing an owned pointer never follows the symlink to another file.
    assert api.delete(URL, headers=headers(meta["avatar_revision"])).status_code == 200
    assert target.read_bytes() == b"synthetic-other-file-never-read"


@pytest.mark.parametrize("operation", ["PUT", "DELETE", "GET"])
def test_cookie_switched_in_another_tab_cannot_modify_or_read_other_account(api, mailbox, operation):
    account_a = register(api, mailbox)
    with TestClient(app, headers=HEADERS) as tab_b:
        account_b = register_account(tab_b, mailbox, email="other-avatar-tab@example.org")
        bind_actor(tab_b)
        if operation != "PUT":
            assert upload(tab_b).status_code == 200
        before = tab_b.get("/api/auth/me").json()
        b_token = tab_b.headers["Authorization"][7:]
        b_files = {p.name: p.read_bytes() for p in own_files(account_b["id"])}
        # Same browser cookie jar changes without notifying tab A's AppState.
        api.headers.pop("Authorization")
        api.cookies.clear()
        api.cookies.set("sp_session", b_token)
        assert api.headers["X-Schulpilot-Account"] == account_a["id"]
        if operation == "PUT":
            result = upload(api)
        elif operation == "DELETE":
            result = api.delete(URL, headers=headers(before["avatar_revision"]))
        else:
            result = api.get(URL, params={"revision": before["avatar_revision"]})
        assert result.status_code == 409, result.text
        assert tab_b.get("/api/auth/me").json() == before
        assert {p.name: p.read_bytes() for p in own_files(account_b["id"])} == b_files
        assert not own_files(account_a["id"])
        assert_no_learning()


def test_private_avatar_get_also_requires_matching_actor_assertion(api, mailbox):
    register(api, mailbox)
    meta = upload(api).json()
    del api.headers["X-Schulpilot-Account"]
    assert api.get("/api" + meta["avatar_url"]).status_code == 409
    assert api.delete(URL, headers=headers(meta["avatar_revision"])).status_code == 409
    assert (
        api.put(URL, files={"file": ("a.png", picture())}, headers=headers(meta["avatar_revision"])).status_code == 409
    )
