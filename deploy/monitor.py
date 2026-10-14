"""Project-only health watchdog with optional neutral operator email.

This runs independently of the API/worker. It cannot detect loss of the whole
host; scripts/watch_public.py supplies the independent-host check.
"""

import argparse
import json
import os
import shlex
import shutil
import smtplib
import ssl
import subprocess
import time
import urllib.request
from email.message import EmailMessage
from pathlib import Path


def environment(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key] = " ".join(shlex.split(value)) if value else ""
    return values


def notify(config, failures, previous, path, *, dry_run=False):
    fingerprint = ",".join(sorted(failures))
    stamp = int(time.time())
    should_send = fingerprint != previous.get("fingerprint", "") or (
        failures and stamp - previous.get("sent", 0) > 21600
    )
    if not failures and not previous.get("sent"):
        should_send = False
    state = {"checked_at": stamp, "fingerprint": fingerprint, "failures": failures, "sent": previous.get("sent", 0)}
    recipient = config.get("OPERATIONS_ALERT_EMAIL", "")
    if should_send and recipient and not dry_run:
        message = EmailMessage()
        message["Subject"] = (
            "SCHULPILOT: Betriebsprüfung fehlgeschlagen" if failures else "SCHULPILOT: Betrieb wieder erreichbar"
        )
        if config.get("ALERT_TEST_TOKEN"):
            message.replace_header("Subject", "TEST SCHULPILOT Alarmtest " + config["ALERT_TEST_TOKEN"])
        message["From"] = config["SMTP_FROM"]
        message["To"] = recipient
        message.set_content(
            "Technische Prüfungen: " + (fingerprint or "wieder erfolgreich") + ". Keine Lerninhalte enthalten."
        )
        if config.get("ALERT_TEST_TOKEN"):
            message.set_content(
                "Dies ist ein ausdrücklich ausgelöster technischer Alarmtest von SCHULPILOT. Es liegt keine gemeldete Betriebsstörung vor. Testkennung: "
                + config["ALERT_TEST_TOKEN"]
            )
        try:
            mode = config.get("SMTP_MODE", "starttls")
            context = ssl.create_default_context()
            if mode not in ("tls", "starttls"):
                raise ValueError("TLS configuration required")
            server = (
                smtplib.SMTP_SSL(config["SMTP_HOST"], int(config.get("SMTP_PORT", "465")), timeout=15, context=context)
                if mode == "tls"
                else smtplib.SMTP(config["SMTP_HOST"], int(config.get("SMTP_PORT", "587")), timeout=15)
            )
            with server:
                if mode == "starttls":
                    server.starttls(context=context)
                if config.get("SMTP_USER"):
                    server.login(config["SMTP_USER"], config["SMTP_PASSWORD"])
                server.send_message(message)
            state["sent"] = stamp
        except Exception:
            # Keep the previous fingerprint so the next scheduled check retries
            # the alert, independently of application mail delivery.
            state["fingerprint"] = previous.get("fingerprint", "")
            state["alert_error"] = "smtp_delivery_failed"
    if not dry_run:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        partial = path.with_suffix(".partial")
        partial.write_text(json.dumps(state) + "\n")
        partial.chmod(0o600)
        partial.replace(path)
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    config = environment("/etc/schulpilot/environment")
    failures = []
    for service in ("schulpilot-api", "schulpilot-worker", "schulpilot-backup.timer"):
        if subprocess.run(["systemctl", "is-active", "--quiet", service]).returncode:
            failures.append(service + "_inactive")
    try:
        with urllib.request.urlopen("http://127.0.0.1:3240/api/health", timeout=10) as response:
            if response.status != 200:
                failures.append("api_health")
    except Exception:
        failures.append("api_health")
    try:
        result = subprocess.run(
            [
                "runuser",
                "-u",
                "schulpilot",
                "--",
                "/opt/schulpilot/current/venv/bin/python",
                "-m",
                "schulpilot.operations",
            ],
            cwd="/opt/schulpilot/current/backend",
            env={**config, "PATH": "/usr/bin:/bin"},
            timeout=20,
            capture_output=True,
            check=True,
            text=True,
        )
        metrics = json.loads(result.stdout)
        if metrics["worker_age_seconds"] is None or metrics["worker_age_seconds"] > 240:
            failures.append("worker_heartbeat")
        if metrics["stalled_queued"] or metrics["stalled_running"]:
            failures.append("jobs_stalled")
        if metrics["pending_erasure_journal"]:
            failures.append("erasure_journal_pending")
    except Exception:
        failures.append("database_metrics")
    backups = list(Path("/var/backups/schulpilot").glob("*.tar.enc"))
    if not backups or time.time() - max(p.stat().st_mtime for p in backups) > 30 * 3600:
        failures.append("backup_stale")
    restore = Path("/var/backups/schulpilot-monitor/restore-check.json")
    if subprocess.run(["systemctl", "is-failed", "--quiet", "schulpilot-restore-check.service"]).returncode == 0:
        failures.append("restore_rehearsal_failed")
    if restore.exists() and time.time() - json.loads(restore.read_text())["checked_at"] > 14 * 86400:
        failures.append("restore_rehearsal_stale")
    disk = shutil.disk_usage("/var/lib/schulpilot")
    if disk.free < 1024**3 or disk.used / disk.total > 0.9:
        failures.append("disk_space")
    path = Path("/var/backups/schulpilot-monitor/state.json")
    previous = json.loads(path.read_text()) if path.exists() else {}
    state = notify(config, failures, previous, path, dry_run=args.dry_run)
    print(
        json.dumps(
            {
                "failures": failures,
                "alert_configured": bool(config.get("OPERATIONS_ALERT_EMAIL")),
                "dry_run": args.dry_run,
                "alert_error": state.get("alert_error"),
            }
        )
    )
    return bool(failures or state.get("alert_error"))


if __name__ == "__main__":
    raise SystemExit(main())
