"""Explicit local install of the separate rootless repair broker; never inference.

Independent account authentication stays outside Git and all tool mounts.
Installation starts no login, provider switch, inference or deployment.
"""

import argparse
import grp
import hashlib
import json
import os
import pwd
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path("/opt/schulpilot-repair")
HOME = Path("/var/lib/schulpilot-repair")
BINARY_HASH = "628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1"
MAX_BINARY = 512 * 1024 * 1024


def _regular_binary(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_BINARY:
            raise ValueError("Regular bounded binary required.")
        return os.fdopen(descriptor, "rb")
    except BaseException:
        os.close(descriptor)
        raise


def _binary_digest(stream):
    result, total = hashlib.sha256(), 0
    while block := stream.read(1024 * 1024):
        total += len(block)
        if total > MAX_BINARY:
            raise ValueError("Binary size limit.")
        result.update(block)
    return result.hexdigest()


def install_binary(source, target, expected_hash=BINARY_HASH):
    """Never overwrite an executing inode or follow a link/FIFO.

    Identical pinned executables keep their inode, including an active device
    login. A changed executable is verified in a sibling temp file and atomically
    replaced; a running process retains its original inode until it exits.
    """
    with _regular_binary(source) as original:
        if _binary_digest(original) != expected_hash:
            raise ValueError("Pinned binary mismatch.")
        try:
            with _regular_binary(target) as existing:
                if _binary_digest(existing) == expected_hash:
                    os.fchmod(existing.fileno(), 0o755)
                    return False
        except FileNotFoundError:
            pass
        descriptor, temporary = tempfile.mkstemp(prefix=".codex-", dir=target.parent)
        try:
            original.seek(0)
            with os.fdopen(descriptor, "wb") as output:
                total = 0
                while block := original.read(1024 * 1024):
                    total += len(block)
                    if total > MAX_BINARY:
                        raise ValueError("Binary size limit.")
                    output.write(block)
                output.flush()
                os.fchmod(output.fileno(), 0o755)
                os.fsync(output.fileno())
            with _regular_binary(Path(temporary)) as staged:
                if _binary_digest(staged) != expected_hash:
                    raise ValueError("Staged binary mismatch.")
            try:
                if not stat.S_ISREG(target.lstat().st_mode):
                    raise ValueError("Regular destination binary required.")
            except FileNotFoundError:
                pass
            os.replace(temporary, target)
            return True
        finally:
            Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=Path("/opt/schulpilot-codex/bin/codex"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Authorized root installation required.")
    source = Path(__file__).resolve().parent.parent
    with _regular_binary(args.binary) as binary:
        if _binary_digest(binary) != BINARY_HASH:
            raise SystemExit("Pinned Codex 0.162.1 binary mismatch.")
    try:
        identity = pwd.getpwnam("schulpilot-repair")
    except KeyError:
        subprocess.run(["useradd", "--system", "--user-group", "--create-home", "--home-dir", str(HOME),
                        "--shell", "/usr/sbin/nologin", "schulpilot-repair"], check=True)
        identity = pwd.getpwnam("schulpilot-repair")
    if identity.pw_dir != str(HOME):
        raise SystemExit("Existing repair account has unexpected home.")
    # Rootless podman requires a private subordinate ID range. Never overlap an
    # existing range or change another service account's allocation.
    for filename, flag in (("/etc/subuid", "--add-subuids"), ("/etc/subgid", "--add-subgids")):
        entries = [line.split(":") for line in Path(filename).read_text().splitlines()
                   if line and not line.startswith("#")]
        if any(len(parts) != 3 or not parts[1].isdigit() or not parts[2].isdigit() for parts in entries):
            raise SystemExit("Invalid existing subordinate ID allocation; refusing to change it.")
        if not any(parts[0] == identity.pw_name for parts in entries):
            start = 100000
            intervals = [(int(p[1]), int(p[1]) + int(p[2])) for p in entries]
            while any(start < upper and start + 65536 > lower for lower, upper in intervals):
                start += 65536
            subprocess.run(["usermod", flag, f"{start}-{start + 65535}", identity.pw_name], check=True)
    app_group = grp.getgrnam("schulpilot").gr_gid
    for path, mode, group in ((HOME, 0o700, identity.pw_gid), (HOME / "credentials", 0o700, identity.pw_gid),
                              (HOME / "jobs", 0o700, identity.pw_gid),
                              (Path("/run/schulpilot-repair-runtime"), 0o700, identity.pw_gid),
                              (Path("/run/schulpilot-repair"), 0o2750, app_group)):
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(mode)
        os.chown(path, identity.pw_uid, group)
    # Never copy a refresh token from the existing learning login. Independent
    # refresh-token rotation could revoke that login. Initial catalog stays
    # unavailable until an explicitly separate local operator login is complete.
    for path in (ROOT, ROOT / "bin", ROOT / "build", ROOT / "build/workers/repair", ROOT / "build/backend/schulpilot"):
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(0o755)
    install_binary(args.binary, ROOT / "bin/codex")
    install_binary(args.binary, ROOT / "build/codex")
    for name in ("Containerfile", "agent.py", "candidate_rpc.py"):
        shutil.copyfile(source / "workers/repair" / name, ROOT / "build/workers/repair" / name)
    shutil.copyfile(source / "backend/requirements.lock", ROOT / "build/backend/requirements.lock")
    shutil.copyfile(source / "backend/schulpilot/repair_source.py", ROOT / "build/backend/schulpilot/repair_source.py")
    for name in ("broker.py", "catalog.py", "policy.py", "observer_tests.py"):
        shutil.copyfile(source / "workers/repair" / name, ROOT / name)
    shutil.copyfile(source / "backend/schulpilot/repair_source.py", ROOT / "source_policy.py")
    if not (ROOT / "venv/bin/python").exists():
        subprocess.run(["python3", "-m", "venv", str(ROOT / "venv")], check=True)
    subprocess.run([str(ROOT / "venv/bin/pip"), "install", "--disable-pip-version-check", "-r",
                    str(source / "workers/codex/requirements.lock"), "pytest==9.1.1"], check=True, stdout=subprocess.DEVNULL)
    env = {"HOME": str(HOME), "PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": "/run/schulpilot-repair-runtime", "LANG": "C.UTF-8"}
    command = ["/usr/sbin/runuser", "-u", identity.pw_name, "--", "/usr/bin/podman", "--cgroup-manager=cgroupfs"]
    subprocess.run([*command, "build", "--layers", "--network=slirp4netns:allow_host_loopback=false",
                    "--tag=localhost/schulpilot-repair:0.162.1", "--file=workers/repair/Containerfile", "."],
                   cwd=ROOT / "build", env=env, check=True)
    image = subprocess.check_output([*command, "image", "inspect", "--format={{.Id}}", "localhost/schulpilot-repair:0.162.1"],
                                    cwd=HOME, env=env, text=True).strip()
    if not image.startswith("sha256:"):
        image = "sha256:" + image
    (ROOT / "image-id").write_text(image + "\n")
    for name in ("schulpilot-repair.service", "schulpilot-repair-dispatcher.service"):
        shutil.copyfile(source / "deploy" / name, Path("/etc/systemd/system") / name)
    Path("/etc/tmpfiles.d/schulpilot-repair.conf").write_text(
        "d /run/schulpilot-repair 2750 schulpilot-repair schulpilot -\n")
    shutil.copyfile(source / "deploy/repair_login.py", "/usr/local/sbin/schulpilot-repair")
    Path("/usr/local/sbin/schulpilot-repair").chmod(0o755)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "--now", "schulpilot-repair.service"], check=True)
    # Dispatcher is installed but never started by an installer: deployment must
    # first contain the bound source bundle and migration, with operator review.
    print(json.dumps({"broker": "installed", "cli_version": "0.162.1", "learning_worker": "unchanged",
                      "dispatcher": "installed_not_started", "inference": "not_run"}))


if __name__ == "__main__":
    main()
