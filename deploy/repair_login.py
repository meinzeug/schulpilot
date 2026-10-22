#!/usr/bin/python3
"""Local explicit repair-account login, separate from the learning login."""

import argparse
import hashlib
import json
import os
import pwd
import subprocess
from pathlib import Path

ROOT = Path("/opt/schulpilot-repair")
HOME = Path("/var/lib/schulpilot-repair")
BINARY_HASH = "628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("login", "status"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Use the authorized local operator through sudo.")
    identity = pwd.getpwnam("schulpilot-repair")
    if identity.pw_dir != str(HOME) or not (ROOT / "bin/codex").is_file() or (ROOT / "bin/codex").is_symlink() or hashlib.sha256((ROOT / "bin/codex").read_bytes()).hexdigest() != BINARY_HASH:
        raise SystemExit("Repair account or pinned binary mismatch.")
    credentials = HOME / "credentials"
    if credentials.is_symlink() or not credentials.is_dir():
        raise SystemExit("Private repair credential directory required.")
    if args.command == "status":
        try:
            path = credentials / "auth.json"
            if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077 or path.stat().st_size > 40000:
                raise ValueError()
            value = json.loads(path.read_text()).get("tokens") or {}
            present = all(isinstance(value.get(key), str) and value[key] for key in ("access_token", "refresh_token"))
        except (OSError, ValueError, TypeError, AttributeError):
            present = False
        print(json.dumps({"account_credential_present": present, "inference_verified": False, "learning_login": "unchanged"}))
        return
    subprocess.run(["systemctl", "stop", "schulpilot-repair.service"], check=True)
    environment = {"PATH": "/usr/bin:/bin", "HOME": str(HOME), "CODEX_HOME": str(credentials), "LANG": "C.UTF-8"}
    try:
        # --device-auth verified on the actual installed 0.162.1 help. The URL
        # and one-time code are interactive output, not written to an app log.
        result = subprocess.run(["/usr/sbin/runuser", "-u", identity.pw_name, "--", str(ROOT / "bin/codex"),
                                 "login", "--device-auth"], cwd=HOME, env=environment, timeout=600)
        raise SystemExit(result.returncode)
    finally:
        subprocess.run(["systemctl", "start", "schulpilot-repair.service"], check=True)


if __name__ == "__main__":
    main()
