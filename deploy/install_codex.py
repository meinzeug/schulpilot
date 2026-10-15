"""Install/update only the project's rootless provider. No login credentials in builds."""

import argparse
import grp
import hashlib
import http.client
import json
import os
import pwd
import shutil
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path("/opt/schulpilot-codex")
HOME = Path("/var/lib/schulpilot-codex")
BINARY_HASH = "628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=ROOT / "bin/codex")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Authorized root installation required.")
    source = Path(__file__).resolve().parent.parent
    if hashlib.sha256(args.binary.read_bytes()).hexdigest() != BINARY_HASH:
        raise SystemExit("Pinned Codex 0.162.1 binary hash mismatch.")
    try:
        worker_group = grp.getgrnam("schulpilot-codex")
    except KeyError:
        subprocess.run(["groupadd", "--system", "schulpilot-codex"], check=True)
        worker_group = grp.getgrnam("schulpilot-codex")
    try:
        identity = pwd.getpwnam("schulpilot-codex")
    except KeyError:
        subprocess.run(
            [
                "useradd",
                "--create-home",
                "--home-dir",
                str(HOME),
                "--gid",
                "schulpilot-codex",
                "--shell",
                "/usr/sbin/nologin",
                "schulpilot-codex",
            ],
            check=True,
        )
        identity = pwd.getpwnam("schulpilot-codex")
    if identity.pw_dir != str(HOME):
        raise SystemExit("Existing worker account has an unexpected home; refusing to change it.")
    if identity.pw_gid != worker_group.gr_gid:
        subprocess.run(["systemctl", "stop", "schulpilot-codex.service"], check=True)
        subprocess.run(["usermod", "--gid", "schulpilot-codex", "schulpilot-codex"], check=True)
        identity = pwd.getpwnam("schulpilot-codex")
    for path in (HOME, HOME / "auth", Path("/run/schulpilot-codex-runtime")):
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(0o700)
        os.chown(path, identity.pw_uid, identity.pw_gid)
    provider_dir = Path("/run/schulpilot-provider")
    provider_dir.mkdir(exist_ok=True)
    os.chown(provider_dir, identity.pw_uid, grp.getgrnam("schulpilot").gr_gid)
    provider_dir.chmod(0o2750)
    shutil.copyfile(source / "deploy/schulpilot-provider.conf", "/etc/tmpfiles.d/schulpilot-provider.conf")
    for path in (ROOT, ROOT / "bin", ROOT / "build", ROOT / "build/workers/codex"):
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(0o755)
    if args.binary.resolve() != (ROOT / "bin/codex").resolve():
        shutil.copyfile(args.binary, ROOT / "bin/codex")
    (ROOT / "bin/codex").chmod(0o755)
    shutil.copyfile(ROOT / "bin/codex", ROOT / "build/codex")
    (ROOT / "build/codex").chmod(0o755)
    for name in ("Containerfile", "worker.py", "requirements.lock"):
        shutil.copyfile(source / "workers/codex" / name, ROOT / "build/workers/codex" / name)
    digest = hashlib.sha256()
    for path in ("codex", "workers/codex/Containerfile", "workers/codex/worker.py", "workers/codex/requirements.lock"):
        with (ROOT / "build" / path).open("rb") as stream:
            while block := stream.read(1_048_576):
                digest.update(block)
    fingerprint = digest.hexdigest()
    environment = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(HOME),
        "XDG_RUNTIME_DIR": "/run/schulpilot-codex-runtime",
        "LANG": "C.UTF-8",
    }
    command = ["/usr/sbin/runuser", "-u", "schulpilot-codex", "--", "/usr/bin/podman", "--cgroup-manager=cgroupfs"]
    if not (ROOT / "build-fingerprint").exists() or (ROOT / "build-fingerprint").read_text().strip() != fingerprint:
        subprocess.run(
            [
                *command,
                "build",
                "--layers",
                "--network=slirp4netns:allow_host_loopback=false",
                "--tag=localhost/schulpilot-codex:0.162.1",
                "--file=workers/codex/Containerfile",
                ".",
            ],
            cwd=ROOT / "build",
            env=environment,
            check=True,
        )
        image = subprocess.run(
            [
                *command,
                "image",
                "inspect",
                "--format={{.Id}}",
                "localhost/schulpilot-codex:0.162.1",
            ],
            cwd=HOME,
            capture_output=True,
            text=True,
            env=environment,
            check=True,
        ).stdout.strip()
        if not image.startswith("sha256:"):
            image = "sha256:" + image
        (ROOT / "image-id").write_text(image + "\n")
        (ROOT / "build-fingerprint").write_text(fingerprint + "\n")
    shutil.copyfile(source / "workers/codex/run.py", ROOT / "run.py")
    (ROOT / "run.py").chmod(0o755)
    shutil.copyfile(source / "deploy/codex_login.py", "/usr/local/sbin/schulpilot-codex")
    Path("/usr/local/sbin/schulpilot-codex").chmod(0o755)
    shutil.copyfile(source / "deploy/schulpilot-codex.service", "/etc/systemd/system/schulpilot-codex.service")
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "schulpilot-codex.service"], check=True)
    subprocess.run(["systemctl", "restart", "schulpilot-codex.service"], check=True)
    for _ in range(50):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(2)
                connection.connect("/run/schulpilot-provider/codex.sock")
                connection.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n")
                response = http.client.HTTPResponse(connection)
                response.begin()
                health = json.loads(response.read(2000))
            if (
                health.get("isolated") is True
                and health.get("search") is True
                and health.get("cli_version") == "0.162.1"
            ):
                break
        except (OSError, ValueError, http.client.HTTPException):
            pass
        time.sleep(0.2)
    else:
        raise SystemExit("Codex container healthcheck failed; inspect only this service before activation.")
    print(
        json.dumps(
            {"rootless_worker": "installed", "login": "sudo schulpilot-codex login", "source_fingerprint": fingerprint}
        )
    )


if __name__ == "__main__":
    main()
