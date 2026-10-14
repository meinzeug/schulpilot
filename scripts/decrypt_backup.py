"""Authenticate and decrypt a SCHULPILOT backup into a new archive file."""

import argparse
import hashlib
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

parser = argparse.ArgumentParser()
parser.add_argument("backup", type=Path)
parser.add_argument("--key-file", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
if args.output.exists():
    raise SystemExit("Output already exists; nothing was overwritten.")
key = hashlib.sha256(args.key_file.read_bytes()).digest()
partial = args.output.with_suffix(".partial")
try:
    with args.backup.open("rb") as source:
        if source.read(4) != b"SPB1":
            raise ValueError("Unsupported backup format")
        nonce = source.read(12)
        source.seek(-16, 2)
        end = source.tell()
        tag = source.read(16)
        decryptor = Cipher(algorithms.AES(key), modes.GCM(nonce, tag)).decryptor()
        decryptor.authenticate_additional_data(b"SPB1")
        source.seek(16)
        with partial.open("xb") as output:
            partial.chmod(0o600)
            while source.tell() < end:
                output.write(decryptor.update(source.read(min(1024 * 1024, end - source.tell()))))
            output.write(decryptor.finalize())
    partial.replace(args.output)
except Exception:
    partial.unlink(missing_ok=True)
    raise
print("Backup authentication succeeded; decrypted archive is ready.")
