#!/usr/bin/python3
"""Local operator entrypoint. No network listener or user-supplied commands."""

import getpass
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HOME = Path("/var/lib/schulpilot-codex")
AUTH = HOME / "auth"


def main():
    if os.geteuid() != 0:
        raise SystemExit("Bitte mit sudo auf dem SCHULPILOT-Server ausführen.")
    command = sys.argv[1:]
    if command == ["status"]:
        try:
            data = json.loads((AUTH / "auth.json").read_text())
            mode = "api_key" if data.get("OPENAI_API_KEY") else "account" if data.get("tokens") else "missing"
        except (OSError, ValueError, TypeError):
            mode = "missing"
        print(json.dumps({"credential_mode": mode, "upstream_connection_verified": False}))
        return
    if command == ["probe"]:
        subprocess.run(["/usr/bin/python3", "/opt/schulpilot/current/deploy/admin.py", "probe-codex"], check=True)
        return
    if command not in (["login"], ["login-api"], ["logout"]):
        raise SystemExit("Verwendung: schulpilot-codex login | login-api | status | probe | logout")
    if not sys.stdin.isatty():
        raise SystemExit("Die Anmeldung benötigt ein eigenes interaktives Terminal.")
    subprocess.run(["systemctl", "stop", "schulpilot-codex.service"], check=True)
    environment = {"PATH": "/usr/bin:/bin", "HOME": str(HOME), "CODEX_HOME": str(AUTH), "LANG": "C.UTF-8"}
    args = [
        "/usr/sbin/runuser",
        "-u",
        "schulpilot-codex",
        "--",
        "/opt/schulpilot-codex/bin/codex",
        "-c",
        'cli_auth_credentials_store="file"',
    ]
    try:
        if command == ["logout"]:
            subprocess.run([*args, "logout"], env=environment, cwd=HOME, check=True)
            return
        if command == ["login-api"]:
            key = getpass.getpass("Eigener SCHULPILOT-OpenAI-API-Schlüssel: ")
            subprocess.run(
                [*args, "login", "--with-api-key"], input=key.encode(), env=environment, cwd=HOME, check=True
            )
        else:
            subprocess.run([*args, "login", "--device-auth"], env=environment, cwd=HOME, check=True)
        (AUTH / "auth.json").chmod(0o600)
    finally:
        subprocess.run(["systemctl", "start", "schulpilot-codex.service"], check=True)
    # Actual activation follows only successful counted synthetic tests.
    for _ in range(30):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.connect("/run/schulpilot-provider/codex.sock")
            break
        except OSError:
            time.sleep(0.2)
    subprocess.run(["/usr/bin/python3", "/opt/schulpilot/current/deploy/admin.py", "probe-codex"], check=True)


if __name__ == "__main__":
    main()
