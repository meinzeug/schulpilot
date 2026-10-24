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
from .db import DB, Assignment, Child, ErasureRequest, Family, LearningUnit, Material, Membership, SchoolDay, User, now

SCOPES = ("family", "child", "user", "material", "membership", "unit", "assignment")


def request(db, scope, target):
    if scope not in SCOPES or not re.fullmatch(r"[a-f0-9]{32}", target):
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
    if record.get("resource_kind") not in (None, "assignment") or (
        record.get("resource_kind") and record["scope"] != "unit"
    ):
        raise ValueError("Invalid erasure resource kind")
    if record["scope"] not in SCOPES:
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
                    if row.scope == "assignment":
                        # Old live journal readers accept/preserve extra fields
                        # of a unit record. Current restore tools resolve this
                        # explicitly typed resource before looking up its ID.
                        record["scope"] = "unit"
                        record["resource_kind"] = "assignment"
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

    records = [
        {**record, "scope": "assignment"}
        if record["scope"] == "unit" and record.get("resource_kind") == "assignment"
        else record
        for record in records
    ]
    paths = []
    # Collect image paths before user cascades can remove their Material rows.
    order = {"family": 0, "child": 1, "unit": 2, "assignment": 3, "material": 4, "membership": 5, "user": 6}
    for record in sorted(records, key=lambda record: order[record["scope"]]):
        scope, target = record["scope"], record["target"]
        model = {
            "family": Family,
            "child": Child,
            "user": User,
            "material": Material,
            "membership": Membership,
            "unit": LearningUnit,
            "assignment": Assignment,
        }[scope]
        row = db.get(model, target)
        if row is None:
            continue
        if scope == "family":
            paths.extend(remove_family(db, row))
        elif scope == "child":
            paths.extend(remove_child(db, row))
        elif scope == "user":
            from .profile_images import deletion_paths

            paths.extend(deletion_paths(db, target))
            db.execute(delete(User).where(User.id == target))
        elif scope == "membership":
            db.delete(row)
        elif scope == "assignment":
            from .source_cleanup import erase_assignments

            erase_assignments(db, row.child_id, [row.id], journal=False)
        elif scope == "unit":
            from .unit_erasure import remove

            remove(db, db.get(Child, row.child_id), [row.id], journal=False)
        else:
            from .school_preparation import sources_removed
            from .tutor import purge_source_turns
            from .unit_erasure import linked_ids, remove

            # Older journals only recorded the page. A restore must not revive
            # its rounds, follow-ups or evidence after replaying that deletion.
            remove(db, db.get(Child, row.child_id), linked_ids(db, row.child_id, [row.id]), journal=False)
            from .source_lineage import purge_diagnostic_outputs

            purge_diagnostic_outputs(db, [row.id])
            purge_source_turns(db, [row.id], child_id=row.child_id)
            if row.path:
                paths.append(row.path)
            day = db.get(SchoolDay, row.school_day_id) if row.school_day_id else None
            db.delete(row)
            db.flush()
            if day:
                day.revision += 1
                sources_removed(db, day)
        db.flush()
    return paths


def retained_image_names(db):
    """Current private file pointers, including own-account profile images."""
    from .db import UserAvatar
    from .profile_images import filename

    known = set(db.scalars(select(Material.path).where(Material.path.is_not(None))))
    known.update(
        filename(row.user_id, row.revision)
        for row in db.scalars(select(UserAvatar).where(UserAvatar.image_digest.is_not(None)))
    )
    return known


def valid_image_name(name):
    return bool(re.fullmatch(r"(?:[a-f0-9]{32}|avatar-[a-f0-9]{64}-[a-f0-9]{32})\.jpg", name))


def prune_orphan_images(db):
    """Remove interrupted upload writes after a grace period, within our directory."""
    known = retained_image_names(db)
    removed = 0
    for path in (settings.data_dir / "uploads").glob("*.jpg"):
        try:
            modified = path.lstat().st_mtime
        except FileNotFoundError:
            continue
        if valid_image_name(path.name) and path.name not in known and modified < now() - 3600:
            path.unlink(missing_ok=True)
            removed += 1
    return removed
