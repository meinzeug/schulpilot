"""Run as root on the existing host. Creates only SCHULPILOT resources."""

import os
import pwd
import secrets
import subprocess
from pathlib import Path


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


try:
    user = pwd.getpwnam("schulpilot")
except KeyError:
    run(["useradd", "--system", "--home-dir", "/var/lib/schulpilot", "--shell", "/usr/sbin/nologin", "schulpilot"])
    user = pwd.getpwnam("schulpilot")

for path, mode in [
    ("/opt/schulpilot", 0o755),
    ("/opt/schulpilot/releases", 0o755),
    ("/var/lib/schulpilot", 0o700),
    ("/var/lib/schulpilot/uploads", 0o700),
    ("/var/backups/schulpilot", 0o700),
    ("/var/backups/schulpilot-monitor", 0o700),
    ("/etc/schulpilot", 0o750),
]:
    directory = Path(path)
    directory.mkdir(parents=True, exist_ok=True, mode=mode)
    directory.chmod(mode)
    if path.startswith("/var/lib/"):
        os.chown(directory, user.pw_uid, user.pw_gid)

run(
    ["runuser", "-u", "postgres", "--", "psql", "-v", "ON_ERROR_STOP=1"],
    input="""
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='schulpilot') THEN
   CREATE ROLE schulpilot LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
 END IF;
END $$;
""",
    text=True,
)
exists = subprocess.check_output(
    ["runuser", "-u", "postgres", "--", "psql", "-Atc", "SELECT 1 FROM pg_database WHERE datname='schulpilot'"],
    text=True,
).strip()
if not exists:
    run(["runuser", "-u", "postgres", "--", "createdb", "--owner=schulpilot", "schulpilot"])

env = Path("/etc/schulpilot/environment")
if not env.exists():
    # Fernet's key is urlsafe base64 of 32 independent random bytes.
    import base64

    master = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode()
    env.write_text(
        "\n".join(
            [
                "ENVIRONMENT=production",
                "PUBLIC_URL=https://schulpilot.dorfspy.de",
                "DATABASE_URL=postgresql+psycopg://schulpilot@/schulpilot?host=/var/run/postgresql",
                "DATA_DIR=/var/lib/schulpilot",
                "MASTER_KEY=" + master,
                "SYNTHETIC_DEMO=true",
                "REAL_DATA_APPROVED=false",
                "PRIVACY_EVIDENCE=",
                "CODEX_APPROVED=false",
                "CODEX_SOCKET=",
                "SMTP_HOST=",
                "SMTP_FROM=",
                "",
            ]
        )
    )
    env.chmod(0o640)
    os.chown(env, 0, user.pw_gid)
os.chown(env.parent, 0, user.pw_gid)

key = Path("/etc/schulpilot/backup.key")
if not key.exists():
    key.write_text(secrets.token_urlsafe(48))
    key.chmod(0o600)

print(
    "SCHULPILOT: separater Benutzer, Datenbank, Datenpfade und lokale Secrets vorbereitet. Keine anderen Dienste geändert."
)
