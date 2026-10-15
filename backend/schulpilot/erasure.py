"""Deletion outbox plus authenticated journal, kept outside database restores.

Only random record IDs, scopes and timestamps; no names or learning content.
Restore tools must verify the journal before applying any record.
"""

import fcntl
import hashlib
import hmac
import json
import os
import re
import tempfile

from sqlalchemy import delete, select

from .config import settings
from .db import DB, Child, ErasureRequest, Family, Material, Membership, User, now


def request(db, scope, target):
    if scope not in ("family", "child", "user", "material", "membership") or not re.fullmatch(r"[a-f0-9]{32}", target):
        raise ValueError("Invalid erasure identifier")
    db.add(ErasureRequest(scope=scope, target=target))


def signed(record, key):
    payload = json.dumps(record, sort_keys=True, separators=(",", ":"))
    signature = hmac.new(key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return json.dumps({"record": record, "signature": signature}, separators=(",", ":"))


def verify(raw, key):
    value = json.loads(raw)
    record = value["record"]
    expected = json.loads(signed(record, key))["signature"]
    if not hmac.compare_digest(value["signature"], expected):
        raise ValueError("Erasure journal authentication failed")
    if record["scope"] not in ("family", "child", "user", "material", "membership"):
        raise ValueError("Invalid erasure scope")
    if not all(re.fullmatch(r"[a-f0-9]{32}", record[k]) for k in ("id", "target")):
        raise ValueError("Invalid erasure identifier")
    return record


def flush_journal():
    path = settings.data_dir / "erasure-ledger.jsonl"
    with DB.begin() as db:
        rows = list(db.scalars(select(ErasureRequest).where(ErasureRequest.published.is_(False))))
        if not rows:
            return
        if not settings.master_key:
            raise RuntimeError("An erasure journal requires the protected master key")
        lock = os.open(settings.data_dir / ".erasure-ledger.lock", os.O_CREAT | os.O_RDWR, 0o600)
        with os.fdopen(lock, "r+") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(descriptor, "a") as output:
                fcntl.flock(output, fcntl.LOCK_EX)
                for row in rows:
                    record = {k: getattr(row, k) for k in ("id", "scope", "target", "created")}
                    output.write(signed(record, settings.master_key) + "\n")
                    row.published = True
                output.flush()
                os.fsync(output.fileno())
        # A crash before this commit can append duplicate signed IDs; replay is
        # deliberately idempotent. Pending outbox rows are retried by maintenance.


def prune_journal():
    """35 days exceeds all allowed 14-day backups; never keep private names."""
    cutoff = int(now()) - 35 * 86400
    path = settings.data_dir / "erasure-ledger.jsonl"
    lock = os.open(settings.data_dir / ".erasure-ledger.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock, "r+") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        if path.exists():
            records = [verify(line, settings.master_key) for line in path.read_text().splitlines() if line]
            kept = {r["id"]: r for r in records if r["created"] >= cutoff}
            with tempfile.NamedTemporaryFile(
                mode="w", dir=settings.data_dir, prefix=".erasure-", delete=False
            ) as output:
                temporary = output.name
                for record in kept.values():
                    output.write(signed(record, settings.master_key) + "\n")
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, path)
    with DB.begin() as db:
        db.execute(delete(ErasureRequest).where(ErasureRequest.published.is_(True), ErasureRequest.created < cutoff))


def reconcile(db, records):
    """Apply verified IDs in an isolated restore DB; return obsolete image paths."""
    from .families import remove_child, remove_family

    paths = []
    # Collect image paths before user cascades can remove their Material rows.
    order = {"family": 0, "child": 1, "material": 2, "membership": 3, "user": 4}
    for record in sorted(records, key=lambda record: order[record["scope"]]):
        scope, target = record["scope"], record["target"]
        model = {"family": Family, "child": Child, "user": User, "material": Material, "membership": Membership}[scope]
        row = db.get(model, target)
        if row is None:
            continue
        if scope == "family":
            paths.extend(remove_family(db, row))
        elif scope == "child":
            paths.extend(remove_child(db, row))
        elif scope == "user":
            db.execute(delete(User).where(User.id == target))
        elif scope == "membership":
            db.delete(row)
        else:
            from .tutor import purge_source_turns

            purge_source_turns(db, [row.id], child_id=row.child_id)
            if row.path:
                paths.append(row.path)
            db.delete(row)
        db.flush()
    return paths


def prune_orphan_images(db):
    """Remove interrupted upload writes after a grace period, within our directory."""
    known = set(db.scalars(select(Material.path).where(Material.path.is_not(None))))
    removed = 0
    for path in (settings.data_dir / "uploads").glob("*.jpg"):
        try:
            modified = path.lstat().st_mtime
        except FileNotFoundError:
            continue
        if re.fullmatch(r"[a-f0-9]{32}\.jpg", path.name) and path.name not in known and modified < now() - 3600:
            path.unlink(missing_ok=True)
            removed += 1
    return removed
