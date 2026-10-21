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
migration_started = False
schema_before = None
environment = None


def database_revision():
    """Read only the schema marker, never database credentials or private data."""
    script = (
        "from sqlalchemy import create_engine, inspect, text; import os; "
        "e=create_engine(os.environ['DATABASE_URL']); "
        "c=e.connect(); "
        "print(','.join(sorted(c.execute(text('SELECT version_num FROM alembic_version')).scalars())) "
        "if inspect(e).has_table('alembic_version') else '<empty>')"
    )
    result = subprocess.run(
        ["runuser", "-u", "schulpilot", "--", str(release / "venv/bin/python"), "-c", script],
        cwd=release / "backend",
        env=environment,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


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
    if previous:
        subprocess.run(["systemctl", "start", "schulpilot-backup.service"], check=True)
        backup_result = subprocess.run(
            ["systemctl", "show", "schulpilot-backup.service", "-p", "Result", "--value"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if backup_result != "success":
            raise RuntimeError("Pre-deployment database backup failed")
    temporary = base / ".current-new"
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(release)
    temporary.replace(current)
    for name in [
        "schulpilot-api.service",
        "schulpilot-worker.service",
        "schulpilot-backup.service",
        "schulpilot-backup.timer",
        "schulpilot-monitor.service",
        "schulpilot-monitor.timer",
        "schulpilot-restore-check.service",
        "schulpilot-restore-check.timer",
    ]:
        source = release / "deploy" / name
        if source.is_file():
            shutil.copy2(source, Path("/etc/systemd/system") / name)
    # An existing operator-installed relay is maintained, never auto-installed.
    turn = Path("/etc/schulpilot-turn")
    if (turn / "turnserver.conf").is_file():
        for name in ("schulpilot-turn.service", "schulpilot-turn-cert.service", "schulpilot-turn-cert.timer"):
            source = release / "deploy" / name
            if source.is_file():
                shutil.copy2(source, Path("/etc/systemd/system") / name)
        source = release / "deploy/turn_certificate.py"
        if source.is_file():
            shutil.copy2(source, turn / "refresh_certificate.py")
            (turn / "refresh_certificate.py").chmod(0o644)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    timers = ["schulpilot-backup.timer"]
    if (release / "deploy/schulpilot-restore-check.timer").is_file():
        timers.append("schulpilot-restore-check.timer")
    elif Path("/etc/systemd/system/schulpilot-restore-check.timer").exists():
        subprocess.run(["systemctl", "stop", "schulpilot-restore-check.timer"], check=True)
    if (release / "deploy/schulpilot-monitor.timer").is_file():
        timers.append("schulpilot-monitor.timer")
    elif Path("/etc/systemd/system/schulpilot-monitor.timer").exists():
        subprocess.run(["systemctl", "stop", "schulpilot-monitor.timer"], check=True)
    subprocess.run(["systemctl", "enable", "schulpilot-api", "schulpilot-worker", *timers], check=True)
    environment = {"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    import shlex

    for line in Path("/etc/schulpilot/environment").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            environment[key] = " ".join(shlex.split(value)) if value else ""
    if "--rollback-compatible" not in sys.argv[2:]:
        schema_before = database_revision()
        # Drain this application's workers before changing their database schema.
        subprocess.run(["systemctl", "stop", "schulpilot-api", "schulpilot-worker"], check=True)
        if previous:
            # Capture answers/jobs completed while the old worker was draining.
            subprocess.run(["systemctl", "start", "schulpilot-backup.service"], check=True)
        migration_started = True
        subprocess.run(
            ["runuser", "-u", "schulpilot", "--", str(release / "venv/bin/python"), "-m", "schulpilot.migrate"],
            cwd=release / "backend",
            env=environment,
            check=True,
        )
    subprocess.run(["systemctl", "restart", "schulpilot-api", "schulpilot-worker"], check=True)
    subprocess.run(["systemctl", "start", *timers], check=True)
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
    compatible = not migration_started
    if migration_started:
        try:
            compatible = database_revision() == schema_before
        except Exception:
            compatible = False
    if previous and compatible:
        current.unlink(missing_ok=True)
        current.symlink_to(previous)
        subprocess.run(["systemctl", "restart", "schulpilot-api", "schulpilot-worker"], check=False)
    else:
        subprocess.run(["systemctl", "stop", "schulpilot-api", "schulpilot-worker"], check=False)
        if migration_started and not compatible:
            print(
                "Schema changed: services stopped. Restore the verified pre-deployment database backup before activating the previous release.",
                file=sys.stderr,
            )
    subprocess.run(["systemctl", "reload", "caddy"], check=False)
    raise
