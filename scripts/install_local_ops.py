"""Install only SCHULPILOT user timers; no sudo or changes to other projects."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "deploy"))
from monitor import environment  # noqa: E402

os.umask(0o077)
base = Path.home() / ".local/share/schulpilot-operations"
units = Path.home() / ".config/systemd/user"
for path in (base / "scripts", base / "deploy", units):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
for name in ("offsite_backup.py", "watch_public.py"):
    shutil.copy2(root / "scripts" / name, base / "scripts" / name)
shutil.copy2(root / "deploy/monitor.py", base / "deploy/monitor.py")
recovery = Path.home() / ".local/share/schulpilot-recovery/server-environment"
if recovery.exists():
    import shlex

    values = environment(recovery)
    allowed = {k: v for k, v in values.items() if k.startswith("SMTP_") or k == "OPERATIONS_ALERT_EMAIL"}
    config = base / "monitor.env"
    config.write_text("\n".join(k + "=" + shlex.quote(v) for k, v in allowed.items()) + "\n")
    config.chmod(0o600)
for name in ("schulpilot-offsite", "schulpilot-watch-public"):
    for suffix in ("service", "timer"):
        content = (root / "deploy" / (name + "." + suffix)).read_text()
        content = content.replace("%h/schulpilot/scripts/", "%h/.local/share/schulpilot-operations/scripts/")
        (units / (name + "." + suffix)).write_text(content)
subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
subprocess.run(["systemctl", "--user", "start", "schulpilot-offsite.service"], check=True)
subprocess.run(
    ["systemctl", "--user", "enable", "--now", "schulpilot-offsite.timer", "schulpilot-watch-public.timer"], check=True
)
print("SCHULPILOT independent-host backup and health timers installed.")
