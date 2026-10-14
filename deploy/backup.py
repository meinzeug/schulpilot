"""Project-only encrypted daily backup; run as root by systemd timer."""

import fcntl
import hashlib
import os
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

destination = Path("/var/backups/schulpilot")
destination.mkdir(exist_ok=True, mode=0o700)
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
final = destination / (stamp + ".tar.enc")
with tempfile.TemporaryDirectory(prefix="schulpilot-backup-") as directory:
    directory = Path(directory)
    dump = directory / "database.dump"
    with dump.open("wb") as output:
        subprocess.run(
            ["runuser", "-u", "schulpilot", "--", "pg_dump", "--format=custom", "schulpilot"], stdout=output, check=True
        )
    archive = directory / "backup.tar"
    with tarfile.open(archive, "w") as bundle:
        bundle.add(dump, arcname="database.dump")
        bundle.add("/var/lib/schulpilot/uploads", arcname="uploads")
        ledger = Path("/var/lib/schulpilot/erasure-ledger.jsonl")
        if ledger.exists():
            with ledger.open("rb") as source:
                fcntl.flock(source, fcntl.LOCK_SH)
                snapshot = directory / "erasure-ledger.jsonl"
                snapshot.write_bytes(source.read())
            bundle.add(snapshot, arcname="erasure-ledger.jsonl")
    partial = final.with_suffix(".partial")
    key = hashlib.sha256(Path("/etc/schulpilot/backup.key").read_bytes()).digest()
    nonce = os.urandom(12)
    encryptor = Cipher(algorithms.AES(key), modes.GCM(nonce)).encryptor()
    encryptor.authenticate_additional_data(b"SPB1")
    with archive.open("rb") as source, partial.open("wb") as output:
        output.write(b"SPB1" + nonce)
        while chunk := source.read(1024 * 1024):
            output.write(encryptor.update(chunk))
        output.write(encryptor.finalize())
        output.write(encryptor.tag)
    partial.chmod(0o600)
    partial.replace(final)
for old in destination.glob("*.tar.enc"):
    if old.stat().st_mtime < time.time() - 14 * 86400:
        old.unlink()
print("SCHULPILOT backup created: " + final.name)
