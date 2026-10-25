"""Server-bound submitting identity for new study jobs, checked before/after AI."""
import re

from fastapi import HTTPException

from .db import Session, User, now
from .providers import ProviderError
from .security import Principal, child_access

MESSAGE = "Die Anmeldung oder Familienberechtigung für diese Etappe ist nicht mehr gültig. Bitte melde dich erneut an."


def validate(db, child, value):
    if (not isinstance(value, dict) or set(value) != {"version", "user_id", "session_id", "family_id"}
            or type(value["version"]) is not int or value["version"] != 1
            or any(not isinstance(value[key], str) or not re.fullmatch(r"[a-f0-9]{32}", value[key])
                   for key in ("user_id", "session_id", "family_id"))):
        raise ProviderError(MESSAGE)
    db.refresh(child)
    user = db.get(User, value["user_id"], populate_existing=True)
    session = db.get(Session, value["session_id"], populate_existing=True)
    if (not user or not session or user.disabled or not user.verified or user.role not in ("parent", "child")
            or session.user_id != user.id or session.revoked or session.expires <= now()
            or now() - session.seen > 7 * 86400 or child.family_id != value["family_id"]):
        raise ProviderError(MESSAGE)
    try:
        current = child_access(db, Principal(user, session), child.id, write=user.role == "parent")
    except HTTPException:
        raise ProviderError(MESSAGE) from None
    if current.family_id != value["family_id"]:
        raise ProviderError(MESSAGE)
    return current


def bind(db, principal, child):
    value = {"version": 1, "user_id": principal.user.id, "session_id": principal.session.id, "family_id": child.family_id}
    validate(db, child, value)
    return value
