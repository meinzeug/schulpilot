"""Real local executable replacement, no model/container/service/server calls."""

import errno
import hashlib
import importlib.util
import os
import shutil
import subprocess
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("install_repair", Path(__file__).resolve().parents[2] / "deploy/install_repair.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_identical_busy_executable_is_kept_and_login_process_survives(tmp_path):
    source, target = tmp_path / "source", tmp_path / "codex"
    shutil.copyfile("/bin/sleep", source)
    shutil.copyfile(source, target)
    target.chmod(0o755)
    original = target.stat().st_ino
    process = subprocess.Popen([str(target), "10"])
    try:
        with pytest.raises(OSError) as blocked:
            with target.open("wb"):
                pass
        assert blocked.value.errno == errno.ETXTBSY
        assert installer.install_binary(source, target, sha(source)) is False
        assert target.stat().st_ino == original
        assert process.poll() is None and sha(target) == sha(source)
    finally:
        process.terminate()
        process.wait(timeout=2)


def test_changed_busy_executable_is_atomically_replaced_without_stopping_old_process(tmp_path):
    source, target = tmp_path / "source", tmp_path / "codex"
    shutil.copyfile("/bin/true", source)
    shutil.copyfile("/bin/sleep", target)
    target.chmod(0o755)
    previous = target.stat().st_ino
    process = subprocess.Popen([str(target), "10"])
    try:
        assert installer.install_binary(source, target, sha(source)) is True
        assert target.stat().st_ino != previous and sha(target) == sha(source)
        assert target.stat().st_mode & 0o777 == 0o755
        assert subprocess.run([str(target)], check=False).returncode == 0
        assert process.poll() is None
        assert not list(tmp_path.glob(".codex-*"))
    finally:
        process.terminate()
        process.wait(timeout=2)


@pytest.mark.parametrize("position,kind", [("source", "fifo"), ("target", "fifo"), ("source", "link"), ("target", "link")])
def test_binary_install_refuses_fifo_or_symlink_without_reading_or_overwriting(tmp_path, position, kind):
    source, target = tmp_path / "source", tmp_path / "codex"
    other = tmp_path / "other"
    other.write_bytes(b"unchanged")
    selected = source if position == "source" else target
    if position == "target":
        source.write_bytes(b"valid source")
    if kind == "fifo":
        os.mkfifo(selected, 0o600)
    else:
        selected.symlink_to(other)
    with pytest.raises((OSError, ValueError)):
        installer.install_binary(source, target, sha(source) if position == "target" else "a" * 64)
    assert other.read_bytes() == b"unchanged"
    assert selected.is_symlink() if kind == "link" else not selected.is_file()
    assert not list(tmp_path.glob(".codex-*"))


def test_wrong_source_hash_does_not_replace_existing_binary(tmp_path):
    source, target = tmp_path / "source", tmp_path / "codex"
    source.write_bytes(b"unexpected")
    target.write_bytes(b"kept")
    previous = target.stat().st_ino
    with pytest.raises(ValueError, match="Pinned binary mismatch"):
        installer.install_binary(source, target)
    assert target.read_bytes() == b"kept" and target.stat().st_ino == previous
    assert not list(tmp_path.glob(".codex-*"))
