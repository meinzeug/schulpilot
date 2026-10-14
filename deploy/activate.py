"""Safely activate an uploaded immutable release; retain rollback pointer."""

import re
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

release_id = sys.argv[1]
if not re.fullmatch(r"[a-zA-Z0-9._-]+", release_id):
    raise SystemExit("Invalid release identifier")
base = Path("/opt/schulpilot")
release = base / "releases" / release_id
if not (release / "web/index.html").is_file() or not (release / "backend/requirements.lock").is_file():
    raise SystemExit("Release is incomplete")
current = base / "current"
previous = current.resolve() if current.is_symlink() else None
caddy = Path("/etc/caddy/Caddyfile")
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
backup = Path(str(caddy) + ".before-schulpilot-" + stamp)
shutil.copy2(caddy, backup)
before = caddy.read_text()
fragment = Path("/etc/caddy/schulpilot.caddy")
fragment_before = fragment.read_text() if fragment.exists() else None
try:
    if not (release / "venv/bin/pip").exists():
        subprocess.run(["python3", "-m", "venv", str(release / "venv")], check=True)
        subprocess.run(
            [
                str(release / "venv/bin/pip"),
                "install",
                "--disable-pip-version-check",
                "-r",
                str(release / "backend/requirements.lock"),
            ],
            check=True,
        )
    fragment.write_text((release / "deploy/Caddyfile.schulpilot").read_text())
    if "import /etc/caddy/schulpilot.caddy" not in before:
        if "schulpilot.dorfspy.de" in before:
            raise RuntimeError("Existing SCHULPILOT host block needs manual reconciliation")
        caddy.write_text(before.rstrip() + "\n\nimport /etc/caddy/schulpilot.caddy\n")
    subprocess.run(["caddy", "validate", "--config", str(caddy), "--adapter", "caddyfile"], check=True)
    temporary = base / ".current-new"
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(release)
    temporary.replace(current)
    for name in [
        "schulpilot-api.service",
        "schulpilot-worker.service",
        "schulpilot-backup.service",
        "schulpilot-backup.timer",
    ]:
        shutil.copy2(release / "deploy" / name, Path("/etc/systemd/system") / name)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(
        ["systemctl", "enable", "schulpilot-api", "schulpilot-worker", "schulpilot-backup.timer"], check=True
    )
    environment = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    import shlex

    for line in Path("/etc/schulpilot/environment").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            environment[key] = " ".join(shlex.split(value)) if value else ""
    if "--rollback-compatible" not in sys.argv[2:]:
        subprocess.run(
            ["runuser", "-u", "schulpilot", "--", str(release / "venv/bin/python"), "-m", "schulpilot.migrate"],
            cwd=release / "backend",
            env=environment,
            check=True,
        )
    subprocess.run(["systemctl", "restart", "schulpilot-api", "schulpilot-worker"], check=True)
    subprocess.run(["systemctl", "start", "schulpilot-backup.timer"], check=True)
    healthy = False
    for _ in range(30):
        try:
            with urllib.request.urlopen("http://127.0.0.1:3240/api/health", timeout=2) as response:
                healthy = response.status == 200
            if healthy:
                break
        except OSError:
            pass
        time.sleep(1)
    if not healthy:
        raise RuntimeError("API healthcheck failed")
    subprocess.run(["systemctl", "reload", "caddy"], check=True)
    if previous and previous != release:
        prior = base / "previous"
        prior.unlink(missing_ok=True)
        prior.symlink_to(previous)
    print("SCHULPILOT activated: " + release_id)
except Exception:
    caddy.write_text(before)
    if fragment_before is not None:
        fragment.write_text(fragment_before)
    elif fragment.exists():
        fragment.unlink()
    if previous:
        current.unlink(missing_ok=True)
        current.symlink_to(previous)
        subprocess.run(["systemctl", "restart", "schulpilot-api", "schulpilot-worker"], check=False)
    else:
        subprocess.run(["systemctl", "stop", "schulpilot-api", "schulpilot-worker"], check=False)
    subprocess.run(["systemctl", "reload", "caddy"], check=False)
    raise
