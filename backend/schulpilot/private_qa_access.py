"""One-off local grant for the two independently inspected artificial QA photos.

No HTTP endpoint, no public trial configuration change, no provider request.
The existing family-trial ledger enforces the time, call and money bounds.
"""

import json
import re
import sys

from sqlalchemy import select

from .commerce import DAY, store
from .db import DB, BankOrder, Child, Family, FamilyTrial, Job, LearningUnit, Material, Membership, User, now
from .security import audit

VERSION = "private-photo-qa-20261028-1"
ARTIFICIAL_DIGESTS = frozenset({
    "aca73ab2f3a8fa05863f1292394a3aad90e6083b1915bf796421abd6f63da651",
    "1f6e31a23b213947dfa4c22f3c38d9d4fc3104464c3f6cce0bf0f59bae1cac8e",
})


def grant(db, request):
    if not isinstance(request, dict) or set(request) != {"family_id", "parent_id", "child_id", "material_ids"}:
        raise ValueError("Ungültiger interner Testauftrag.")
    ids = [request["family_id"], request["parent_id"], request["child_id"], *(request["material_ids"] if isinstance(request["material_ids"], list) else [])]
    if len(ids) != 5 or len(set(ids)) != 5 or not all(isinstance(i, str) and re.fullmatch(r"[a-f0-9]{32}", i) for i in ids):
        raise ValueError("Ungültige Testkennungen.")
    family = db.scalar(select(Family).where(Family.id == ids[0]).with_for_update())
    parent, child = db.get(User, ids[1]), db.get(Child, ids[2])
    if not family or not parent or not child or family.synthetic or not family.commerce_required:
        raise ValueError("Kein passender regulärer Testhaushalt.")
    if (family.name != "Regulärer KI-Test mit künstlichem Schulstoff" or child.family_id != family.id
            or parent.role != "parent" or not parent.verified or parent.disabled
            or not re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@(gmail\.com|googlemail\.com)$", parent.username)):
        raise ValueError("Die künstliche Testfamilie ist nicht eindeutig gebunden.")
    members = list(db.scalars(select(Membership).where(Membership.family_id == family.id)))
    children = list(db.scalars(select(Child).where(Child.family_id == family.id)))
    child_user = db.get(User, child.user_id)
    nonce = re.search(r"\+schulpilot-normal-qa-([a-f0-9]{12})@", parent.username).group(1)
    if (len(members) != 1 or members[0].user_id != parent.id or members[0].permission != "owner"
            or len(children) != 1 or children[0].id != child.id or not child_user
            or child_user.role != "child" or child_user.disabled
            or child_user.username != "normal-child-" + nonce):
        raise ValueError("Der künstliche Testhaushalt ist nicht isoliert.")
    pages = list(db.scalars(select(Material).where(Material.child_id == child.id)))
    if (len(pages) != 2 or {p.id for p in pages} != set(ids[3:])
            or {p.image_digest for p in pages} != ARTIFICIAL_DIGESTS
            or any(p.synthetic or p.purpose != "notebook" for p in pages)):
        raise ValueError("Nur die beiden geprüften künstlichen Fotos sind zulässig.")
    if (db.scalar(select(Job.id).where(Job.child_id == child.id).limit(1))
            or db.scalar(select(LearningUnit.id).where(LearningUnit.child_id == child.id).limit(1))
            or db.scalar(select(BankOrder.id).where(BankOrder.family_id == family.id).limit(1))):
        raise ValueError("Der Testhaushalt enthält bereits Aufträge oder Lernbelege.")
    if store(db)[0].trial_enabled:
        raise ValueError("Der öffentliche Testphasenstand hat sich geändert.")
    existing = db.get(FamilyTrial, family.id)
    if existing:
        if existing.version == VERSION and existing.owner_user_id == parent.id:
            return {"already_applied": True, "ends": existing.ends}
        raise ValueError("Ein anderer Zugang besteht bereits.")
    start = int(now())
    db.add(FamilyTrial(family_id=family.id, owner_user_id=parent.id, starts=start, ends=start + 30 * DAY,
                       child_limit=1, call_limit=100, budget_micros=15_000_000, version=VERSION))
    audit(db, "local-operator", "trial.private_artificial_qa", family.id)
    return {"already_applied": False, "ends": start + 30 * DAY, "call_limit": 100, "budget_usd": 15}


def main():
    request = json.load(sys.stdin)
    with DB.begin() as db:
        result = grant(db, request)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
