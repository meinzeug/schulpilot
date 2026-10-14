"""Pull existing project ciphertext to an independent, authorized host.

Uses the operator's existing SSH alias; never transfers SSH or backup keys.
Only constrained backup filenames are passed to the remote shell.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path


def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=120, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", type=Path, default=Path.home() / ".local/share/schulpilot-offsite")
    args = parser.parse_args()
    os.umask(0o077)
    args.destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.destination.chmod(0o700)
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "dorfspy"]
    inventory_code = """import hashlib,json,time
from pathlib import Path
items=[]
for p in Path('/var/backups/schulpilot').glob('*.tar.enc'):
 if p.is_file() and not p.is_symlink():
  h=hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
  items.append({'name':p.name,'size':p.stat().st_size,'sha256':h})
print(json.dumps({'backups':items,'server_now':int(time.time())}))
"""
    inventory = json.loads(run([*ssh, "python3 -"], input=inventory_code, capture_output=True, text=True).stdout)
    copied = 0
    for item in inventory["backups"]:
        name = item["name"]
        if not re.fullmatch(r"\d{8}T\d{6}Z\.tar\.enc", name):
            raise RuntimeError("Unexpected backup filename")
        target = args.destination / name
        if not target.exists():
            partial = target.with_suffix(".partial")
            try:
                with partial.open("wb") as output:
                    run([*ssh, "cat /var/backups/schulpilot/" + name], stdout=output, stderr=subprocess.PIPE)
                with partial.open("rb") as source:
                    digest = hashlib.file_digest(source, "sha256").hexdigest()
                if partial.stat().st_size != item["size"] or digest != item["sha256"]:
                    raise RuntimeError("Offsite ciphertext checksum mismatch")
                partial.replace(target)
                copied += 1
            finally:
                partial.unlink(missing_ok=True)
        else:
            with target.open("rb") as source:
                if hashlib.file_digest(source, "sha256").hexdigest() != item["sha256"]:
                    raise RuntimeError("Existing offsite ciphertext checksum mismatch")
    if not inventory["backups"]:
        raise RuntimeError("No server backup available")
    ledger = args.destination / "erasure-ledger.enc"
    partial = ledger.with_suffix(".partial")
    try:
        with partial.open("wb") as output:
            run(
                [*ssh, "/opt/schulpilot/current/venv/bin/python /opt/schulpilot/current/deploy/export_ledger.py"],
                stdout=output,
                stderr=subprocess.PIPE,
            )
        with partial.open("rb") as source:
            if source.read(4) != b"SPB1" or partial.stat().st_size < 32:
                raise RuntimeError("Invalid encrypted ledger")
        partial.replace(ledger)
    finally:
        partial.unlink(missing_ok=True)
    # Match the 14-day retention of the server; encryption does not extend it.
    for path in args.destination.glob("*.tar.enc"):
        from datetime import datetime, timezone

        stamp = datetime.strptime(path.name[:16], "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).timestamp()
        if stamp < inventory["server_now"] - 14 * 86400:
            path.unlink()
    available = list(args.destination.glob("*.tar.enc"))
    if not available:
        raise RuntimeError("No retained offsite backup available")
    newest = (
        datetime.strptime(max(p.name for p in available)[:16], "%Y%m%dT%H%M%SZ")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )
    if inventory["server_now"] - newest > 30 * 3600:
        raise RuntimeError("Server backup is stale")
    (args.destination / "last-success.json").write_text(
        json.dumps(
            {
                "checked_at": int(time.time()),
                "copied": copied,
                "backups": len(available),
                "ledger_source_time": inventory["server_now"],
                "encrypted_ledger": True,
            }
        )
        + "\n"
    )
    print("Encrypted offsite copies and deletion ledger verified; copied=" + str(copied))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Avoid subprocess messages containing private SSH configuration.
        raise SystemExit("Offsite backup failed: " + type(error).__name__) from None
