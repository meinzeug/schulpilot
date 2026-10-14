"""Root-only project configuration change based on explicit operator evidence.

Input is approval metadata, never provider keys. The existing private environment
is backed up, parsed without execution, and only the named approval keys change.
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

if os.geteuid() != 0:
    raise SystemExit("Operator access required")
data = json.loads(sys.stdin.read(4096))
if set(data) != {"evidence", "technical_block"}:
    raise SystemExit("Only evidence and technical_block are accepted")
if not isinstance(data["evidence"], str) or not 20 <= len(data["evidence"]) <= 500:
    raise SystemExit("A concrete operator decision reference is required")
if not isinstance(data["technical_block"], str) or len(data["technical_block"]) > 500:
    raise SystemExit("Invalid technical routing record")
if any("\n" in value or "\r" in value for value in data.values()):
    raise SystemExit("Approval records must be single-line values")
path = Path("/etc/schulpilot/environment")
original = path.read_text()
metadata = path.stat()
original_mode = metadata.st_mode & 0o777


def replace_environment(text):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".environment-", delete=False) as output:
        temporary = Path(output.name)
        output.write(text)
        output.flush()
        os.fsync(output.fileno())
    temporary.chmod(original_mode)
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    temporary.replace(path)


backup = path.with_name("environment.before-approval-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
shutil.copy2(path, backup)
backup.chmod(0o600)
values = {}
for line in original.splitlines():
    if line.strip() and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        values[key] = " ".join(shlex.split(value)) if value else ""
updates = {
    "REAL_DATA_APPROVED": "true",
    "PRIVACY_EVIDENCE": data["evidence"],
}
# Alerts go to the already authorized operator mailbox, never another recipient.
if values.get("SMTP_USER") and not values.get("OPERATIONS_ALERT_EMAIL"):
    updates["OPERATIONS_ALERT_EMAIL"] = values["SMTP_USER"]
values.update(updates)
lines = []
for line in original.splitlines():
    if line.strip() and not line.lstrip().startswith("#") and line.split("=", 1)[0] in updates:
        key = line.split("=", 1)[0]
        lines.append(key + "=" + shlex.quote(updates.pop(key)))
    else:
        lines.append(line)
lines.extend(key + "=" + shlex.quote(value) for key, value in updates.items())
replace_environment("\n".join(lines) + "\n")
result = subprocess.run(
    [
        "runuser",
        "-u",
        "schulpilot",
        "--",
        "/opt/schulpilot/current/venv/bin/python",
        "-m",
        "schulpilot.record_approval",
    ],
    input=json.dumps(data),
    text=True,
    cwd="/opt/schulpilot/current/backend",
    env={**values, "PATH": "/usr/sbin:/usr/bin:/sbin:/bin"},
    capture_output=True,
)
if result.returncode:
    replace_environment(original)
    raise SystemExit("Approval record failed; protected environment restored. No secrets printed.")
subprocess.run(["systemctl", "restart", "schulpilot-api", "schulpilot-worker"], check=True)
print("SCHULPILOT operator approval configured; technical route blocker is separate; secrets retained privately.")
