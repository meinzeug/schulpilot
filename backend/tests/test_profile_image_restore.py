"""Actual offline journal reconciliation keeps live avatars in restored copies."""

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.config import settings
from schulpilot.db import Base, ProviderConfig, Session, Token, User, UserAvatar, now
from schulpilot.erasure import signed
from schulpilot.profile_images import filename
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session as DatabaseSession

ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("forged", [False, True])
def test_real_offline_reconcile_keeps_retained_avatars_and_deletes_only_signed_user(tmp_path, forged):
    database = tmp_path / "profile_restore_test"
    url = "sqlite:///" + str(database)
    tested = create_engine(url)
    Base.metadata.create_all(tested)
    originals, restored = tmp_path / "original-uploads", tmp_path / "restored-uploads"
    originals.mkdir()
    erased, kept = uuid.uuid4().hex, uuid.uuid4().hex
    paths = {}
    with DatabaseSession(tested) as db:
        db.add(ProviderConfig(id=1, emergency_stop=False))
        for user_id in (erased, kept):
            db.add(
                User(
                    id=user_id,
                    username=user_id,
                    display_name="Synthetic restore account",
                    password_hash="synthetic-no-login",
                    role="parent",
                    verified=True,
                )
            )
            db.flush()
            revision = uuid.uuid4().hex
            data = b"synthetic-private-profile-" + user_id.encode()
            paths[user_id] = filename(user_id, revision)
            (originals / paths[user_id]).write_bytes(data)
            db.add(
                UserAvatar(
                    user_id=user_id,
                    revision=revision,
                    image_digest=hashlib.sha256(data).hexdigest(),
                    updated=int(now()),
                    request_key="synthetic-key",
                    request_digest="d" * 64,
                )
            )
            db.add(
                Session(
                    user_id=user_id,
                    token_hash=hashlib.sha256(user_id.encode()).hexdigest(),
                    device="synthetic",
                    expires=int(now()) + 1000,
                )
            )
        db.add(Token(user_id=kept, purpose="reset", digest="c" * 64, expires=int(now()) + 1000))
        db.commit()
    orphan = filename(uuid.uuid4().hex, uuid.uuid4().hex)
    (originals / orphan).write_bytes(b"synthetic-orphan")
    shutil.copytree(originals, restored)
    original_bytes = {p.name: p.read_bytes() for p in originals.iterdir()}
    ledger, key = tmp_path / "ledger.jsonl", tmp_path / "master.key"
    record = {"id": uuid.uuid4().hex, "scope": "user", "target": erased, "created": int(now())}
    entry = signed(record, settings.master_key)
    if forged:
        value = json.loads(entry)
        value["record"]["target"] = kept
        entry = json.dumps(value)
    ledger.write_text(entry + "\n")
    key.write_text(settings.master_key)
    key.chmod(0o600)
    try:
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/reconcile_restore.py"),
                "--database-url",
                url,
                "--ledger",
                str(ledger),
                "--master-key-file",
                str(key),
                "--uploads",
                str(restored),
            ],
            cwd=tmp_path,
            env={**os.environ, "DATA_DIR": str(tmp_path / "isolated-data"), "ENVIRONMENT": "test"},
            capture_output=True,
            timeout=30,
        )
        assert {p.name: p.read_bytes() for p in originals.iterdir()} == original_bytes
        with DatabaseSession(tested) as db:
            if forged:
                assert result.returncode != 0
                assert {p.name: p.read_bytes() for p in restored.iterdir()} == original_bytes
                assert db.get(User, erased) is not None
                assert db.get(ProviderConfig, 1).emergency_stop is False
                assert db.scalar(select(Session.revoked).where(Session.user_id == kept)) is False
            else:
                assert result.returncode == 0, result.stderr.decode(errors="replace")[-1500:]
                assert not (restored / paths[erased]).exists()
                assert (restored / paths[kept]).read_bytes() == original_bytes[paths[kept]]
                assert not (restored / orphan).exists()
                assert db.get(User, erased) is None and db.get(UserAvatar, erased) is None
                assert db.get(User, kept) is not None and db.get(UserAvatar, kept) is not None
                assert db.get(ProviderConfig, 1).emergency_stop is True
                assert db.scalar(select(Session.revoked).where(Session.user_id == kept)) is True
                assert db.scalar(select(Token.used).where(Token.user_id == kept)) is True
    finally:
        tested.dispose()


def restore_checker(monkeypatch):
    monkeypatch.syspath_prepend(str(ROOT / "deploy"))
    spec = importlib.util.spec_from_file_location("avatar_restore_check", ROOT / "deploy/restore_check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_scheduled_restore_image_cleanup_retains_current_avatar_and_legacy_image(tmp_path, monkeypatch):
    checker = restore_checker(monkeypatch)
    live_avatar, erased_avatar = filename("synthetic-kept", "a" * 32), filename("synthetic-erased", "b" * 32)
    legacy, orphan = "c" * 32 + ".jpg", filename("synthetic-orphan", "d" * 32)
    for name in (live_avatar, erased_avatar, legacy, orphan):
        (tmp_path / name).write_bytes(b"synthetic-private-file")
    assert checker.cleanup_images(tmp_path, {live_avatar, legacy}, [erased_avatar]) == (1, 1)
    assert sorted(p.name for p in tmp_path.iterdir()) == sorted([live_avatar, legacy])


@pytest.mark.parametrize(
    "bad", ["../" + "a" * 32 + ".jpg", "/tmp/private.jpg", "avatar-" + "z" * 64 + "-" + "b" * 32 + ".jpg", "photo.svg"]
)
def test_scheduled_restore_still_rejects_non_server_paths_before_deleting_anything(tmp_path, monkeypatch, bad):
    checker = restore_checker(monkeypatch)
    name = filename("synthetic-kept", "a" * 32)
    (tmp_path / name).write_bytes(b"synthetic-safe-file")
    with pytest.raises(RuntimeError, match="Unexpected private image path"):
        checker.cleanup_images(tmp_path, set(), [name, bad])
    assert (tmp_path / name).read_bytes() == b"synthetic-safe-file"
