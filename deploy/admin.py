"""Interactive admin CLI wrapper; never prints the environment or secrets."""

import os
import shlex
import sys
from pathlib import Path

if os.geteuid() != 0:
    raise SystemExit("Run through the authorized server administrator.")
environment = {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "TERM": os.getenv("TERM", "xterm"),
}
for line in Path("/etc/schulpilot/environment").read_text().splitlines():
    if line.strip() and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        environment[key] = " ".join(shlex.split(value)) if value else ""
os.chdir("/opt/schulpilot/current/backend")
args = sys.argv[1:] or ["create-admin"]
os.execvpe(
    "runuser",
    ["runuser", "-u", "schulpilot", "--", "/opt/schulpilot/current/venv/bin/python", "-m", "schulpilot.cli", *args],
    environment,
)
