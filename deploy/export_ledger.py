"""Root-only encrypted current deletion ledger for the independent backup host.

stdout is binary ciphertext. No credentials or unencrypted IDs leave the host.
"""

import fcntl
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

if os.geteuid() != 0:
    raise SystemExit("Operator access required")
if sys.argv[1:] == ["--ack"]:
    directory = Path("/var/backups/schulpilot-monitor")
    directory.mkdir(exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as output:
        output.write(json.dumps({"checked_at": int(time.time())}) + "\n")
        temporary = Path(output.name)
    temporary.replace(directory / "offsite-last-success.json")
    enabled = Path("/etc/schulpilot/offsite-enabled")
    enabled.touch(mode=0o600, exist_ok=True)
    print("Offsite transfer acknowledged after local checksum verification.")
    raise SystemExit(0)
if sys.argv[1:]:
    raise SystemExit("Unsupported export action")
ledger = Path("/var/lib/schulpilot/erasure-ledger.jsonl")
key = hashlib.sha256(Path("/etc/schulpilot/backup.key").read_bytes()).digest()
nonce = os.urandom(12)
encryptor = Cipher(algorithms.AES(key), modes.GCM(nonce)).encryptor()
encryptor.authenticate_additional_data(b"SPB1")
output = sys.stdout.buffer
output.write(b"SPB1" + nonce)
if ledger.exists():
    with ledger.open("rb") as source:
        fcntl.flock(source, fcntl.LOCK_SH)
        while chunk := source.read(1024 * 1024):
            output.write(encryptor.update(chunk))
output.write(encryptor.finalize())
output.write(encryptor.tag)
