"""Independent-host public HTTPS and offsite watchdog; no private API calls."""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "deploy"))
from monitor import environment, notify  # noqa: E402


def main():
    os.umask(0o077)
    base = Path.home() / ".local/share/schulpilot-offsite"
    config_file = Path.home() / ".local/share/schulpilot-operations/monitor.env"
    config = environment(config_file) if config_file.exists() else {}
    failures = []
    try:
        with urllib.request.urlopen("https://schulpilot.dorfspy.de/api/health", timeout=20) as response:
            if response.status != 200 or json.load(response).get("status") != "ok":
                failures.append("public_https_health")
    except Exception:
        failures.append("public_https_health")
    success = base / "last-success.json"
    if not success.exists() or time.time() - json.loads(success.read_text())["checked_at"] > 3600:
        failures.append("offsite_copy_stale")
    path = base / "watch-state.json"
    previous = json.loads(path.read_text()) if path.exists() else {}
    state = notify(config, failures, previous, path, dry_run="--dry-run" in sys.argv)
    print(
        json.dumps(
            {
                "failures": failures,
                "alert_configured": bool(config.get("OPERATIONS_ALERT_EMAIL")),
                "alert_error": state.get("alert_error"),
            }
        )
    )
    return bool(failures or state.get("alert_error"))


if __name__ == "__main__":
    raise SystemExit(main())
