"""Session-bound, explicit deletion of a single saved learning round."""

import json

from cryptography.fernet import InvalidToken
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update

from . import unit_erasure
from .db import Child, LearningUnit, get_db, now
from .material_actions import TTL, DeleteConfirm, ensure_idle
from .security import authenticated, child_access, crypt, rate_limit

router = APIRouter(tags=["Lernrunden"])


def owned(db, p, unit_id):
    unit = db.get(LearningUnit, unit_id)
    if not unit:
        raise HTTPException(404, "Diese Lernrunde ist nicht mehr vorhanden.")
    return unit, child_access(db, p, unit.child_id, write=p.user.role == "parent")


@router.post("/units/{unit_id}/delete-preview")
def preview(unit_id: str, p=Depends(authenticated), db=Depends(get_db)):
    unit, child = owned(db, p, unit_id)
    ensure_idle(db, child.id)
    rate_limit(db, "unit-delete-preview:" + p.user.id, 30, 60, commit=False)
    payload = {
        "v": 1,
        "actor": p.user.id,
        "session": p.session.id,
        "unit": unit.id,
        "child": child.id,
        "snapshot": unit_erasure.snapshot(db, [unit.id]),
    }
    token = crypt().encrypt(json.dumps(payload, separators=(",", ":")).encode()).decode()
    result = unit_erasure.counts(db, [unit.id])
    db.commit()
    return {**result, "selection_token": token, "expires_in": TTL}


@router.post("/units/{unit_id}/delete")
def confirm(unit_id: str, data: DeleteConfirm, p=Depends(authenticated), db=Depends(get_db)):
    unit, child = owned(db, p, unit_id)
    try:
        token = json.loads(crypt().decrypt(data.selection_token.encode(), ttl=TTL))
        if (token["v"], token["actor"], token["session"], token["unit"], token["child"]) != (
            1,
            p.user.id,
            p.session.id,
            unit.id,
            child.id,
        ):
            raise ValueError("scope")
    except (InvalidToken, ValueError, KeyError, TypeError):
        raise HTTPException(409, "Die Löschvorschau ist abgelaufen. Bitte erneut auswählen.") from None
    list(
        db.scalars(
            select(LearningUnit.id).where(LearningUnit.child_id == child.id).order_by(LearningUnit.id).with_for_update()
        )
    )
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    db.expire_all()
    if p.session.revoked or p.session.expires <= now() or p.user.disabled or not p.user.verified:
        raise HTTPException(401, "Bitte erneut anmelden.")
    unit, child = owned(db, p, unit_id)
    ensure_idle(db, child.id)
    if unit_erasure.snapshot(db, [unit.id]) != token["snapshot"]:
        raise HTTPException(409, "Die Lernrunde wurde inzwischen geändert. Bitte die Vorschau neu öffnen.")
    result = unit_erasure.remove(db, child, [unit.id])
    from .erasure import flush_journal
    from .learning import record
    from .security import audit

    record(db, child.id, "unit_deleted", {"count": result})
    audit(db, p.user.id, "learning.unit_deleted", unit_id)
    db.commit()
    flush_journal()
    return {"deleted_count": result}
