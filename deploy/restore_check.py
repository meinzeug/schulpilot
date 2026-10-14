"""Root-only, isolated restore rehearsal; production DB is never overwritten.

Authenticates ciphertext, restores a uniquely named temporary database, applies
the current signed erasure ledger, revokes old sessions/tokens, reports counts,
then drops only the database this invocation created.
"""

import fcntl
import hashlib
import json
import os
import re
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from monitor import environment


def command(args, **kwargs):
    return subprocess.run(args, check=True, timeout=120, capture_output=True, **kwargs)


def decrypt(backup, destination):
    key = hashlib.sha256(Path("/etc/schulpilot/backup.key").read_bytes()).digest()
    with backup.open("rb") as source:
        if source.read(4) != b"SPB1":
            raise ValueError("Unsupported backup format")
        nonce = source.read(12)
        source.seek(-16, 2)
        end = source.tell()
        tag = source.read(16)
        decryptor = Cipher(algorithms.AES(key), modes.GCM(nonce, tag)).decryptor()
        decryptor.authenticate_additional_data(b"SPB1")
        source.seek(16)
        with destination.open("xb") as output:
            while source.tell() < end:
                output.write(decryptor.update(source.read(min(1024 * 1024, end - source.tell()))))
            output.write(decryptor.finalize())


def main():
    if os.geteuid() != 0:
        raise SystemExit("Operator access required")
    os.umask(0o077)
    candidates = sorted(Path("/var/backups/schulpilot").glob("*.tar.enc"))
    if not candidates:
        raise RuntimeError("No backup available")
    backup = candidates[-1]
    if not re.fullmatch(r"\d{8}T\d{6}Z\.tar\.enc", backup.name):
        raise RuntimeError("Invalid backup name")
    name = "schulpilot_" + uuid.uuid4().hex[:12] + "_restore_test"
    created = False
    config = environment("/etc/schulpilot/environment")
    report = {"backup": backup.name, "production_overwritten": False}
    try:
        with tempfile.TemporaryDirectory(prefix="schulpilot-restore-") as directory:
            directory = Path(directory)
            archive = directory / "backup.tar"
            decrypt(backup, archive)  # authenticate before reading/extracting tar
            with tarfile.open(archive) as source:
                source.extractall(directory / "unpacked", filter="data")
            command(["runuser", "-u", "postgres", "--", "createdb", "--owner=schulpilot", name])
            created = True
            with (directory / "unpacked/database.dump").open("rb") as source:
                command(
                    [
                        "runuser",
                        "-u",
                        "schulpilot",
                        "--",
                        "pg_restore",
                        "--exit-on-error",
                        "--no-owner",
                        "--no-acl",
                        "-d",
                        name,
                    ],
                    stdin=source,
                )
            ledger = Path("/var/lib/schulpilot/erasure-ledger.jsonl")
            contents = ""
            if ledger.exists():
                with ledger.open() as source:
                    fcntl.flock(source, fcntl.LOCK_SH)
                    contents = source.read()
            config["DATABASE_URL"] = "postgresql+psycopg://schulpilot@/" + name + "?host=/var/run/postgresql"
            code = """import json,sys
from sqlalchemy import select,func,text,update
from schulpilot.db import DB,Family,Child,Material,LearningUnit,Attempt,Session,Token,ProviderConfig
from schulpilot.erasure import verify,reconcile
from schulpilot.config import settings
from schulpilot.migrate import upgrade
upgrade()
records=[verify(line,settings.master_key) for line in sys.stdin.read().splitlines() if line]
models=(Family,Child,Material,LearningUnit,Attempt)
with DB.begin() as db:
 before={m.__tablename__:db.scalar(select(func.count()).select_from(m)) for m in models}
 paths=reconcile(db,records)
 db.execute(update(Session).values(revoked=True))
 db.execute(update(Token).values(used=True))
 db.execute(update(ProviderConfig).values(emergency_stop=True))
 after={m.__tablename__:db.scalar(select(func.count()).select_from(m)) for m in models}
 version=db.scalar(text('SELECT version_num FROM alembic_version'))
print(json.dumps({'schema':version,'before':before,'after':after,'paths':paths,'verified_erasure_records':len(records)}))
"""
            result = command(
                ["runuser", "-u", "schulpilot", "--", "/opt/schulpilot/current/venv/bin/python", "-c", code],
                cwd="/opt/schulpilot/current/backend",
                env={**config, "PATH": "/usr/sbin:/usr/bin:/sbin:/bin"},
                input=contents.encode(),
            )
            data = json.loads(result.stdout)
            for filename in data.pop("paths"):
                if not re.fullmatch(r"[a-f0-9]{32}\.jpg", filename):
                    raise RuntimeError("Unexpected private image path")
                (directory / "unpacked/uploads" / filename).unlink(missing_ok=True)
            report.update(data)
            report["authenticated_restore"] = True
            report["sessions_revoked"] = True
            report["ai_emergency_stop"] = True
    finally:
        if created:
            command(["runuser", "-u", "postgres", "--", "dropdb", name])
    import time

    report["checked_at"] = int(time.time())
    path = Path("/var/backups/schulpilot-monitor/restore-check.json")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(json.dumps(report) + "\n")
    path.chmod(0o600)
    print(json.dumps(report))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # pg_restore errors can echo SQL values. Never print captured bodies.
        raise SystemExit("Restore rehearsal failed: " + type(error).__name__) from None
