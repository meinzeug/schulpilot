"""Adoption touches only this worker's private files, through non-following FDs."""

import importlib.util
import json
import os
from pathlib import Path
from types import SimpleNamespace

import pytest

spec = importlib.util.spec_from_file_location(
    "codex_login_helper", Path(__file__).resolve().parents[2] / "deploy/codex_login.py"
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
LOGIN = {"auth_mode": "chatgpt", "tokens": {"access_token": "SYNTHETIC-ACCESS", "refresh_token": "SYNTHETIC-REFRESH"}}


@pytest.fixture
def own_home(tmp_path, monkeypatch):
    home = tmp_path / "worker"
    home.mkdir(mode=0o700)
    source_directory = home / ".codex"
    source_directory.mkdir(mode=0o700)
    source = source_directory / "auth.json"
    source.write_text(json.dumps(LOGIN))
    source.chmod(0o600)
    monkeypatch.setattr(helper, "HOME", home)
    monkeypatch.setattr(helper, "AUTH", home / "auth")
    monkeypatch.setattr(helper.pwd, "getpwnam", lambda name: SimpleNamespace(pw_uid=os.getuid(), pw_gid=os.getgid()))
    return home, source


def test_adopt_copies_validated_bytes_not_source_inode(own_home, capsys):
    home, source = own_home
    original = source.stat()
    helper.adopt_worker_login()
    target = home / "auth/auth.json"
    assert json.loads(target.read_text()) == LOGIN and target.stat().st_ino != original.st_ino
    assert target.stat().st_mode & 0o777 == 0o600 and not source.exists()
    assert home.joinpath("auth").stat().st_mode & 0o777 == 0o700
    assert "SYNTHETIC" not in capsys.readouterr().out


@pytest.mark.parametrize("component", [".codex", ".codex/auth.json", "auth"])
def test_adopt_rejects_symlink_components_without_touching_target(own_home, component):
    home, source = own_home
    external = home.parent / "external"
    external.mkdir(mode=0o700)
    external_file = external / "auth.json"
    external_file.write_text(json.dumps(LOGIN))
    external_file.chmod(0o600)
    if component == ".codex":
        source.unlink()
        source.parent.rmdir()
        source.parent.symlink_to(external, target_is_directory=True)
    elif component == ".codex/auth.json":
        source.unlink()
        source.symlink_to(external_file)
    else:
        (home / "auth").symlink_to(external, target_is_directory=True)
    before = external_file.read_bytes()
    with pytest.raises(SystemExit, match="Import abgebrochen"):
        helper.adopt_worker_login()
    assert external_file.read_bytes() == before


def test_existing_destination_is_never_overwritten(own_home):
    home, source = own_home
    directory = home / "auth"
    directory.mkdir(mode=0o700)
    target = directory / "auth.json"
    target.write_text("existing-private-login")
    target.chmod(0o600)
    with pytest.raises(SystemExit, match="bereits vorhanden"):
        helper.adopt_worker_login()
    assert target.read_text() == "existing-private-login" and source.exists()


@pytest.mark.parametrize("kind", ["fifo", "hardlink", "public", "wrong_auth_mode"])
def test_adopt_rejects_nonprivate_nonregular_or_ambiguous_login(own_home, kind):
    home, source = own_home
    if kind == "fifo":
        source.unlink()
        os.mkfifo(source, 0o600)
    elif kind == "hardlink":
        os.link(source, home.parent / "duplicate-login")
    elif kind == "public":
        source.chmod(0o644)
    else:
        source.write_text(json.dumps({**LOGIN, "auth_mode": "apikey"}))
    with pytest.raises(SystemExit, match="Import abgebrochen"):
        helper.adopt_worker_login()
    assert not (home / "auth/auth.json").exists()


def test_foreign_file_owner_is_rejected_before_copy(own_home, monkeypatch):
    home, source = own_home
    original = os.fstat

    def foreign_owner(descriptor):
        info = original(descriptor)
        if info.st_ino == source.stat().st_ino:
            class Foreign:
                st_uid = info.st_uid + 1

                def __getattr__(self, key):
                    return getattr(info, key)
            return Foreign()
        return info

    monkeypatch.setattr(helper.os, "fstat", foreign_owner)
    with pytest.raises(SystemExit, match="Import abgebrochen"):
        helper.adopt_worker_login()
    assert source.exists() and not (home / "auth/auth.json").exists()


def test_every_open_uses_nofollow_and_destination_is_exclusive(own_home, monkeypatch):
    calls = []
    original = os.open

    def tracked_open(name, flags, *args, **kwargs):
        calls.append((name, flags, kwargs.get("dir_fd")))
        return original(name, flags, *args, **kwargs)

    monkeypatch.setattr(helper.os, "open", tracked_open)
    helper.adopt_worker_login()
    assert calls and all(flags & os.O_NOFOLLOW for _, flags, _ in calls)
    target = next(call for call in calls if call[1] & os.O_WRONLY)
    assert target[1] & os.O_EXCL and target[1] & os.O_CREAT and target[2] is not None


def test_failed_write_removes_only_new_partial_destination(own_home, monkeypatch):
    home, source = own_home

    def fail(*_):
        raise OSError("synthetic disk error")

    monkeypatch.setattr(helper.os, "write", fail)
    with pytest.raises(SystemExit, match="Import abgebrochen"):
        helper.adopt_worker_login()
    assert source.exists() and not (home / "auth/auth.json").exists()


def test_concurrent_source_replacement_wins_and_new_copy_is_removed(own_home, monkeypatch):
    home, source = own_home
    original = os.fsync
    replaced = False

    def replace_source(descriptor):
        nonlocal replaced
        if not replaced:
            replaced = True
            source.unlink()
            source.write_text("newer-worker-login")
            source.chmod(0o600)
        return original(descriptor)

    monkeypatch.setattr(helper.os, "fsync", replace_source)
    with pytest.raises(SystemExit, match="Import abgebrochen"):
        helper.adopt_worker_login()
    assert source.read_text() == "newer-worker-login" and not (home / "auth/auth.json").exists()


def test_root_privileges_are_dropped_before_opening_worker_paths(own_home, monkeypatch):
    current = {"uid": 0}
    calls = []
    original = os.open
    monkeypatch.setattr(helper.os, "geteuid", lambda: current["uid"])
    monkeypatch.setattr(helper.os, "setgroups", lambda groups: calls.append(("groups", groups)))
    monkeypatch.setattr(helper.os, "setgid", lambda gid: calls.append(("gid", gid)))

    def setuid(uid):
        current["uid"] = uid
        calls.append(("uid", uid))

    def open_without_root(*args, **kwargs):
        assert current["uid"] == os.getuid()
        return original(*args, **kwargs)

    monkeypatch.setattr(helper.os, "setuid", setuid)
    monkeypatch.setattr(helper.os, "open", open_without_root)
    helper.adopt_worker_login()
    assert [name for name, _ in calls] == ["groups", "gid", "uid"]
