"""Root-only encrypted current deletion ledger for the independent backup host.

stdout is binary ciphertext. No credentials or unencrypted IDs leave the host.
"""

import fcntl
import hashlib
import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

if os.geteuid() != 0:
    raise SystemExit("Operator access required")
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
