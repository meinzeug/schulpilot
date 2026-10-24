"""Synthetic metadata admin controls: no provider calls or real accounts."""

from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest
from conftest import HEADERS, create_child
from fastapi.testclient import TestClient
from schulpilot import admin_users, worker
from schulpilot.admin_user_models import AdminUserOperation, AdminUserVersion
from schulpilot.config import settings
from schulpilot.db import (
    DB,
    Attempt,
    Audit,
    Child,
    ErasureRequest,
    Family,
    LearningUnit,
    Material,
    Membership,
    Session,
    Usage,
    User,
    now,
)
from schulpilot.erasure import verify
from schulpilot.main import app
from schulpilot.security import digest
from sqlalchemy import func, select, update


@pytest.fixture
def operator():
    with DB.begin() as db:
        user = User(
            username="admin-users-operator",
            display_name="Synthetic admin",
            role="admin",
            verified=True,
            password_hash="no-real-password",
        )
        db.add(user)
        db.flush()
        identifier = user.id
        session = Session(
            user_id=identifier,
            token_hash=digest("admin-users-test-token"),
            device="Synthetic admin device",
            expires=int(now()) + 3600,
        )
        db.add(session)
        db.flush()
        session_id = session.id
    headers = {**HEADERS, "Authorization": "Bearer admin-users-test-token", "X-Schulpilot-Account": identifier}
    with TestClient(app, headers=headers) as client:
        client.operator_id, client.session_id = identifier, session_id
        yield client


def child_user(child):
    with DB() as db:
        return db.get(Child, child["id"]).user_id


def get_detail(operator, identifier):
    response = operator.get("/api/admin/users/" + identifier)
    assert response.status_code == 200, response.text
    return response.json()


def mutation(operator, identifier, action, body, key=None, method="post"):
    return getattr(operator, method)(
        "/api/admin/users/" + identifier + "/" + action, json=body, headers={"Idempotency-Key": key or uuid4().hex}
    )


def preview(operator, identifier, scope="account_only"):
    current = get_detail(operator, identifier)
    response = mutation(operator, identifier, "delete-preview", {"revision": current["revision"], "scope": scope})
    assert response.status_code == 200, response.text
    return response.json()


def confirm(operator, identifier, value, key=None):
    return mutation(
        operator,
        identifier,
        "delete",
        {k: value[k] for k in ("revision", "preview_id", "preview_digest", "confirmation")},
        key,
    )


def another_parent(db, family_id, permission="manage"):
    user = User(
        username="other-parent-" + uuid4().hex[:8],
        display_name="Another synthetic parent",
        email=None,
        role="parent",
        verified=True,
        password_hash="private-hash-never-output",
    )
    db.add(user)
    db.flush()
    db.add(Membership(family_id=family_id, user_id=user.id, permission=permission))
    return user.id


def private_rows(child):
    with DB.begin() as db:
        material = Material(
            child_id=child["id"],
            title="PRIVATE_PAGE_TITLE",
            content="PRIVATE_PAGE_TEXT",
            subject="Mathematik",
            topic="Private topic",
            confirmed=True,
            status="ready",
        )
        db.add(material)
        db.flush()
        unit = LearningUnit(
            child_id=child["id"],
            material_id=material.id,
            subject="Mathematik",
            topic="PRIVATE_UNIT_TOPIC",
            explanation="PRIVATE_EXPLANATION",
            questions=[],
            provider="sample",
        )
        db.add(unit)
        db.flush()
        db.add(Attempt(unit_id=unit.id, question_id="private-question", answer="PRIVATE_ANSWER", outcome="correct"))
        return material.id, unit.id


def test_list_filter_pagination_contains_only_allowed_metadata(api, household, operator):
    parent, child = household
    private_rows(child)
    response = operator.get("/api/admin/users", params={"role": "child", "q": "test-child", "page_size": 1})
    assert response.status_code == 200
    body = response.json()
    assert body["pagination"] == {"page": 1, "pages": 1, "page_size": 1, "total": 1}
    assert [u["id"] for u in body["items"]] == [child_user(child)]
    assert body["items"][0]["role"] == "child"
    assert not any(
        value in response.text
        for value in ("PRIVATE_", "password_hash", "token_hash", "encrypted_token", "no-real-password")
    )
    assert operator.get("/api/admin/users", params={"q": "%"}).json()["pagination"]["total"] == 0
    assert operator.get("/api/admin/users", params={"role": "parent"}).json()["items"][0]["id"] == parent["id"]
    assert operator.get("/api/admin/users", params={"state": "disabled"}).json()["items"] == []
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(AdminUserOperation)) == 0


def test_metadata_detail_links_multiple_families_and_children_without_learning_content(api, household, operator):
    parent, child = household
    private_rows(child)
    with DB.begin() as db:
        family = Family(name="Second synthetic family")
        db.add(family)
        db.flush()
        db.add(Membership(family_id=family.id, user_id=parent["id"], permission="view"))
        another_parent(db, family.id, "owner")
    result = get_detail(operator, parent["id"])
    assert len(result["families"]) == 2
    assert {f["permission"] for f in result["families"]} == {"view", "owner"}
    assert sum(len(f["children"]) for f in result["families"]) == 1
    assert any(p["user_id"] == parent["id"] for f in result["families"] for p in f["parents"])
    assert result["editable_fields"] == ["display_name", "username"]
    assert "PRIVATE_" not in str(result)
    assert operator.get("/api/admin/users/" + operator.operator_id).status_code == 404
    assert operator.get("/api/materials/" + private_rows(child)[0]).status_code in (403, 404)


@pytest.mark.parametrize("path", ["/api/admin/users", "/api/admin/users/" + "a" * 32])
def test_admin_actor_header_and_roles_are_required(api, household, operator, path):
    assert api.get(path).status_code == 403
    with TestClient(app, headers=HEADERS) as anonymous:
        assert anonymous.get(path).status_code == 401
    assert operator.get(path, headers={"X-Schulpilot-Account": "f" * 32}).status_code == 409


def test_metadata_cas_idempotency_and_same_text_aba_are_strict(household, operator):
    _, child = household
    identifier = child_user(child)
    old = get_detail(operator, identifier)
    key = uuid4().hex
    body = {"revision": old["revision"], "display_name": "New synthetic name", "username": "new-child-name"}
    response = mutation(operator, identifier, "metadata", body, key, "put")
    assert response.status_code == 200, response.text
    assert response.json()["revision"] != old["revision"]
    assert mutation(operator, identifier, "metadata", body, key, "put").json() == response.json()
    assert mutation(operator, identifier, "metadata", body, uuid4().hex, "put").status_code == 409
    latest = get_detail(operator, identifier)
    back = mutation(
        operator,
        identifier,
        "metadata",
        {
            "revision": latest["revision"],
            "display_name": old["user"]["display_name"],
            "username": old["user"]["username"],
        },
        method="put",
    )
    assert back.status_code == 200 and back.json()["revision"] != old["revision"]
    assert mutation(operator, identifier, "metadata", body, method="put").status_code == 409
    with DB() as db:
        assert db.get(AdminUserVersion, identifier).revision == 2
        rows = list(db.scalars(select(AdminUserOperation)))
        assert len(rows) == 2
        assert "New synthetic name" not in str([r.result for r in rows])
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_two_parallel_drafts_commit_only_one_revision(household, operator):
    _, child = household
    identifier = child_user(child)
    version = get_detail(operator, identifier)["revision"]
    headers = dict(operator.headers)

    def save(number):
        with TestClient(app, headers=headers) as client:
            return mutation(
                client,
                identifier,
                "metadata",
                {
                    "revision": version,
                    "display_name": "Concurrent name " + str(number),
                    "username": "parallel-child-" + str(number),
                },
                method="put",
            ).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        result = list(pool.map(save, [1, 2]))
    assert sorted(result) == [200, 409]
    with DB() as db:
        assert db.get(AdminUserVersion, identifier).revision == 1
        assert db.scalar(select(func.count()).select_from(AdminUserOperation)) == 1
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.user_metadata")) == 1


def test_metadata_rejects_unknown_fields_duplicate_names_and_control_chars(household, operator):
    parent, child = household
    identifier = child_user(child)
    version = get_detail(operator, identifier)["revision"]
    body = {"revision": version, "display_name": "Synthetic", "username": "safe-child-name"}
    assert mutation(operator, identifier, "metadata", {**body, "role": "admin"}, method="put").status_code == 422
    assert (
        mutation(operator, identifier, "metadata", {**body, "email": "changed@example.org"}, method="put").status_code
        == 422
    )
    assert (
        mutation(operator, identifier, "metadata", {**body, "username": parent["username"]}, method="put").status_code
        == 422
    )
    assert (
        mutation(
            operator,
            parent["id"],
            "metadata",
            {
                "revision": get_detail(operator, parent["id"])["revision"],
                "display_name": "Synthetic",
                "username": child["username"].upper(),
            },
            method="put",
        ).status_code
        == 409
    )
    assert (
        mutation(operator, identifier, "metadata", {**body, "display_name": "Bad\nName"}, method="put").status_code
        == 422
    )
    assert (
        mutation(operator, identifier, "metadata", {**body, "username": "white space"}, method="put").status_code == 422
    )
    assert get_detail(operator, identifier)["revision"] == version


def test_status_revokes_sessions_and_enable_never_revives_them(household, operator, api):
    parent, _ = household
    version = get_detail(operator, parent["id"])["revision"]
    response = mutation(operator, parent["id"], "status", {"revision": version, "disabled": True})
    assert response.status_code == 200 and response.json()["revoked_sessions"] >= 1
    assert api.get("/api/auth/me").status_code == 401
    assert operator.get("/api/admin/users", params={"state": "disabled"}).json()["items"][0]["id"] == parent["id"]
    response = mutation(operator, parent["id"], "status", {"revision": response.json()["revision"], "disabled": False})
    assert response.status_code == 200
    assert api.get("/api/auth/me").status_code == 401
    with DB() as db:
        assert not db.get(User, parent["id"]).disabled
        assert all(s.revoked for s in db.scalars(select(Session).where(Session.user_id == parent["id"])))


def test_session_selection_does_not_revoke_other_user_or_other_device(household, operator):
    parent, child = household
    identifier = child_user(child)
    with DB.begin() as db:
        first = Session(
            user_id=identifier, token_hash=digest("first-child-token"), device="First", expires=int(now()) + 3600
        )
        second = Session(
            user_id=identifier, token_hash=digest("second-child-token"), device="Second", expires=int(now()) + 3600
        )
        db.add_all([first, second])
        db.flush()
        first_id, second_id = first.id, second.id
    version = get_detail(operator, identifier)["revision"]
    bad = mutation(operator, identifier, "sessions/revoke", {"revision": version, "session_ids": [operator.session_id]})
    assert bad.status_code == 409
    response = mutation(operator, identifier, "sessions/revoke", {"revision": version, "session_ids": [first_id]})
    assert response.status_code == 200 and response.json()["revoked_sessions"] == 1
    with DB() as db:
        assert db.get(Session, first_id).revoked and not db.get(Session, second_id).revoked
        assert not db.get(Session, operator.session_id).revoked


@pytest.mark.parametrize("change", ["revoked", "role", "disabled"])
def test_post_lock_admin_recheck_rejects_stale_authority(household, operator, monkeypatch, change):
    parent, _ = household
    version = get_detail(operator, parent["id"])["revision"]
    original = admin_users.lock_target

    def changing(db, identifier, **kwargs):
        result = original(db, identifier, **kwargs)
        if change == "revoked":
            db.execute(update(Session).where(Session.id == operator.session_id).values(revoked=True))
        elif change == "role":
            db.execute(update(User).where(User.id == operator.operator_id).values(role="parent"))
        else:
            db.execute(update(User).where(User.id == operator.operator_id).values(disabled=True))
        return result

    monkeypatch.setattr(admin_users, "lock_target", changing)
    response = mutation(operator, parent["id"], "status", {"revision": version, "disabled": True})
    assert response.status_code == (403 if change == "role" else 401)
    with DB() as db:
        assert not db.get(User, parent["id"]).disabled
        assert db.scalar(select(func.count()).select_from(AdminUserOperation)) == 0


def test_shared_owner_deletion_is_blocked_without_losing_other_parents_children(household, operator):
    parent, child = household
    family_id = parent["families"][0]["id"]
    with DB.begin() as db:
        other = another_parent(db, family_id)
    value = preview(operator, parent["id"], "account_and_sole_families")
    assert not value["can_delete"] and "letzte Familieninhaber" in str(value["blockers"])
    assert value["impact"]["preserved_family_ids"] == [family_id]
    assert value["impact"]["child_ids"] == []
    assert confirm(operator, parent["id"], value).status_code == 409
    with DB() as db:
        assert db.get(User, other) and db.get(User, parent["id"]) and db.get(Child, child["id"])
        assert db.scalar(select(func.count()).select_from(ErasureRequest)) == 0


def test_coparent_delete_preserves_shared_family_children_and_owner(household, operator):
    parent, child = household
    with DB.begin() as db:
        other = another_parent(db, parent["families"][0]["id"])
        membership_id = db.scalar(select(Membership.id).where(
            Membership.user_id == other, Membership.family_id == parent["families"][0]["id"]
        ))
    assert membership_id
    ledger = settings.data_dir / "erasure-ledger.jsonl"
    previous_ids = {verify(line, settings.master_key)["id"] for line in ledger.read_text().splitlines()} if ledger.exists() else set()
    value = preview(operator, other)
    assert value["can_delete"] and value["impact"]["counts"]["children"] == 0
    response = confirm(operator, other, value)
    assert response.status_code == 200, response.text
    with DB() as db:
        assert not db.get(User, other)
        assert db.get(User, parent["id"]) and db.get(Child, child["id"])
        assert db.get(Family, parent["families"][0]["id"])
    records = [
        verify(line, settings.master_key)
        for line in (settings.data_dir / "erasure-ledger.jsonl").read_text().splitlines()
    ]
    current_records = [record for record in records if record["id"] not in previous_ids]
    assert {(record["scope"], record["target"]) for record in current_records} == {
        ("membership", membership_id), ("user", other)
    }
    assert not any(record["scope"] in ("family", "child") for record in current_records)


def test_sole_parent_requires_explicit_scope_and_delete_replay_is_idempotent(household, operator):
    parent, child = household
    private_rows(child)
    blocked = preview(operator, parent["id"])
    assert not blocked["can_delete"] and confirm(operator, parent["id"], blocked).status_code == 409
    value = preview(operator, parent["id"], "account_and_sole_families")
    assert value["can_delete"]
    assert value["impact"]["counts"] == {
        "users": 2,
        "families": 1,
        "children": 1,
        "materials": 1,
        "units": 1,
        "attempts": 1,
    }
    assert "PRIVATE_" not in str(value)
    key = uuid4().hex
    response = confirm(operator, parent["id"], value, key)
    assert response.status_code == 200, response.text
    assert confirm(operator, parent["id"], value, key).json() == response.json()
    with DB() as db:
        assert not db.get(User, parent["id"]) and not db.get(Child, child["id"])
        assert not db.get(Family, parent["families"][0]["id"])
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
        receipt = db.scalar(select(AdminUserOperation))
        assert receipt.action == "delete" and "PRIVATE_" not in str(receipt.result)
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.user_delete")) == 1


def test_child_delete_removes_only_selected_child_and_authenticated_files(household, operator, api):
    parent, child = household
    other = create_child(api, parent, username="other-synthetic-child")
    material_id, unit_id = private_rows(child)
    path = uuid4().hex + ".jpg"
    (settings.data_dir / "uploads").mkdir(exist_ok=True)
    (settings.data_dir / "uploads" / path).write_bytes(b"synthetic local image")
    with DB.begin() as db:
        db.get(Material, material_id).path = path
    identifier = child_user(child)
    value = preview(operator, identifier)
    assert value["can_delete"] and value["impact"]["counts"]["children"] == 1
    response = confirm(operator, identifier, value)
    assert response.status_code == 200, response.text
    assert not (settings.data_dir / "uploads" / path).exists()
    with DB() as db:
        assert not db.get(User, identifier) and not db.get(Child, child["id"])
        assert db.get(Child, other["id"]) and db.get(User, parent["id"])
        assert not db.get(LearningUnit, unit_id) and not db.get(Material, material_id)


@pytest.mark.parametrize("change", ["new_page", "page_revision", "membership", "new_session", "metadata"])
def test_delete_preview_rejects_changed_snapshot(household, operator, change):
    parent, child = household
    material_id, _ = private_rows(child)
    value = preview(operator, parent["id"], "account_and_sole_families")
    with DB.begin() as db:
        if change == "new_page":
            db.add(Material(child_id=child["id"], title="Fresh page"))
        elif change == "page_revision":
            db.get(Material, material_id).revision += 1
        elif change == "membership":
            another_parent(db, parent["families"][0]["id"])
        elif change == "new_session":
            db.add(
                Session(user_id=parent["id"], token_hash=digest("late-login"), device="Late", expires=int(now()) + 3600)
            )
        else:
            db.get(User, parent["id"]).display_name = "Changed externally"
    assert confirm(operator, parent["id"], value).status_code == 409
    with DB() as db:
        assert db.get(User, parent["id"]) and db.get(Child, child["id"])
        assert db.scalar(select(func.count()).select_from(ErasureRequest)) == 0


def test_preview_expiration_session_binding_and_key_reuse_are_fail_closed(household, operator):
    parent, child = household
    identifier = child_user(child)
    value = preview(operator, identifier)
    with DB.begin() as db:
        db.get(AdminUserOperation, value["preview_id"]).expires = int(now()) - 1
    assert confirm(operator, identifier, value).status_code == 409
    value = preview(operator, identifier)
    assert confirm(operator, parent["id"], value).status_code == 409
    version = get_detail(operator, identifier)["revision"]
    key = uuid4().hex
    body = {"revision": version, "disabled": False}
    first = mutation(operator, identifier, "status", body, key)
    assert first.status_code == 200
    assert mutation(operator, identifier, "status", {**body, "disabled": True}, key).status_code == 409
    assert operator.post("/api/admin/users/" + identifier + "/status", json=body).status_code == 428


def test_maintenance_purges_only_expired_admin_receipts_and_keeps_versions(household, operator):
    _, child = household
    identifier = child_user(child)
    value = preview(operator, identifier)
    response = mutation(operator, identifier, "status", {"revision": value["revision"], "disabled": False})
    assert response.status_code == 200
    with DB.begin() as db:
        db.get(AdminUserOperation, value["preview_id"]).expires = int(now()) - 1
    worker.maintenance()
    with DB() as db:
        assert not db.get(AdminUserOperation, value["preview_id"])
        assert db.scalar(select(func.count()).select_from(AdminUserOperation)) == 1
        assert db.get(AdminUserVersion, identifier).revision == 1


def test_delete_preview_is_bound_to_exact_admin_session(household, operator):
    _, child = household
    identifier = child_user(child)
    value = preview(operator, identifier)
    with DB.begin() as db:
        db.add(
            Session(
                user_id=operator.operator_id,
                token_hash=digest("second-admin-session"),
                device="Second admin",
                expires=int(now()) + 3600,
            )
        )
    headers = {**HEADERS, "Authorization": "Bearer second-admin-session", "X-Schulpilot-Account": operator.operator_id}
    with TestClient(app, headers=headers) as second:
        assert confirm(second, identifier, value).status_code == 409
    with DB() as db:
        assert db.get(User, identifier) is not None
        assert db.scalar(select(func.count()).select_from(ErasureRequest)) == 0


def test_last_shared_owner_block_does_not_block_explicit_status_and_session_controls(household, operator):
    parent, _ = household
    with DB.begin() as db:
        another_parent(db, parent["families"][0]["id"])
    detail = get_detail(operator, parent["id"])
    assert not detail["allowed_actions"]["delete"] and detail["delete_blockers"]
    assert detail["allowed_actions"]["edit_metadata"] and detail["allowed_actions"]["disable"]
    assert detail["allowed_actions"]["end_sessions"]
    response = mutation(operator, parent["id"], "status", {"revision": detail["revision"], "disabled": True})
    assert response.status_code == 200
    with DB() as db:
        assert db.get(Family, parent["families"][0]["id"]) is not None


def test_deleted_target_expired_receipt_cannot_recreate_or_repeat_deletion(household, operator):
    _, child = household
    identifier = child_user(child)
    value = preview(operator, identifier)
    key = uuid4().hex
    assert confirm(operator, identifier, value, key).status_code == 200
    with DB.begin() as db:
        row = db.scalar(select(AdminUserOperation).where(AdminUserOperation.action == "delete"))
        row.expires = int(now()) - 1
        admin_users.purge_expired(db)
    assert confirm(operator, identifier, value, key).status_code == 404
    with DB() as db:
        assert not db.get(User, identifier)
        assert db.scalar(select(func.count()).select_from(Audit).where(Audit.action == "admin.user_delete")) == 1


def test_unknown_reused_key_and_missing_actor_never_modify_another_target(household, operator):
    parent, child = household
    identifier = child_user(child)
    key = uuid4().hex
    current = get_detail(operator, identifier)
    assert (
        mutation(operator, identifier, "status", {"revision": current["revision"], "disabled": False}, key).status_code
        == 200
    )
    parent_detail = get_detail(operator, parent["id"])
    assert (
        mutation(
            operator, parent["id"], "status", {"revision": parent_detail["revision"], "disabled": True}, key
        ).status_code
        == 409
    )
    body = {"revision": parent_detail["revision"], "disabled": True}
    headers = {**HEADERS, "Authorization": operator.headers["Authorization"]}
    with TestClient(app, headers=headers) as missing_actor:
        assert mutation(missing_actor, parent["id"], "status", body).status_code == 409
    assert not get_detail(operator, parent["id"])["user"]["disabled"]


@pytest.mark.parametrize("username", [" a ", "İ" * 254])
def test_parent_username_limits_apply_after_trimming_and_lowercasing(household, operator, username):
    parent, _ = household
    current = get_detail(operator, parent["id"])
    result = mutation(
        operator,
        parent["id"],
        "metadata",
        {"revision": current["revision"], "display_name": current["user"]["display_name"], "username": username},
        method="put",
    )
    assert result.status_code == 422
    assert get_detail(operator, parent["id"])["revision"] == current["revision"]
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(AdminUserOperation)) == 0
