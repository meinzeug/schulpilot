"""Explicit CAS reading positions; reads never record learning or save state."""
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import delete, select, update

from .db import Child, get_db, now
from .learning import get_unit, unit_data
from .learning_labs import ForceLabView, SentenceLabView, checked_view
from .security import authenticated, child_access
from .visual_reference_models import UnitVisualPosition, UnitVisualSnapshot
from .visual_references import projection

router = APIRouter(tags=["Leseposition"])


class Position(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    explanation_kind: Literal["intro", "question"]
    question_id: str | None = Field(default=None, min_length=1, max_length=60)
    explanation_step_id: str = Field(min_length=1, max_length=32, pattern=r"^[A-Za-z0-9_-]+$")
    graphic_index: int = Field(default=0, ge=0, le=5)
    graphic_phase: str = Field(default="initial", pattern=r"^(initial|fraction-(circle|bar)-(whole|denominator|numerator)|scene-[0-7]|science-[0-9]{1,2})$")

    lab_view: ForceLabView | SentenceLabView | None = None


class PositionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    source_signature: str = Field(pattern=r"^[a-f0-9]{64}$")
    revision: int = Field(ge=0, le=2147483646)
    position: Position


def stamp(db, unit):
    value = projection(db, unit)
    saved = db.get(UnitVisualSnapshot, unit.id)
    return saved.source_signature if saved and value["explanation_visual_status"] == "ready" else None


def checked(db, unit, user, value):
    """Validate an already disclosed step, including the actual finite phase."""
    data = unit_data(db, unit, include_answers=user.role == "parent")
    if value.explanation_kind == "intro":
        if value.question_id is not None:
            raise HTTPException(422, "Die Leseposition gehört zu einer Aufgabe.")
        steps = data["explanation_steps"]
    else:
        question = next((q for q in data["questions"] if q["id"] == value.question_id), None)
        steps = question.get("explanation_steps", []) if question else []
    step = next((row for row in steps if row["id"] == value.explanation_step_id), None)
    if step is None:
        raise HTTPException(409, "Dieser Erklärungsschritt ist noch nicht geöffnet oder wurde geändert.")
    blocks = step.get("presentation", {}).get("blocks", [])
    if value.graphic_index >= len(blocks):
        raise HTTPException(422, "Diese Grafik gehört nicht zum Erklärungsschritt.")
    block, phase = blocks[value.graphic_index], value.graphic_phase
    valid = phase == "initial"
    if phase.startswith("fraction-"):
        valid = block.get("kind") == "fraction"
    elif phase.startswith("scene-"):
        index = int(phase[6:])
        valid = ((block.get("kind") == "scene" and index < len((block.get("scene") or {}).get("steps", [])))
                 or (block.get("kind") in ("process_graph", "process_cycle") and index < len(block.get("labels", []))))
    elif phase.startswith("science-"):
        index, kind = int(phase[8:]), block.get("kind")
        valid = ((kind == "function_graph" and index <= 80)
                 or (kind == "data_plot" and index < len(block.get("numbers", [])) // 2)
                 or (kind == "logic_table" and index < (2 if block.get("variant") == "not_gate" else 4)))
    if not valid:
        raise HTTPException(422, "Diese Darstellung ist für die Grafik nicht verfügbar.")
    result = value.model_dump()
    if value.lab_view is not None:
        if phase != "initial":
            raise HTTPException(422, "Laboransicht und fremde Grafikphase können nicht kombiniert werden.")
        try:
            result["lab_view"] = checked_view(value.lab_view, block)
        except ValueError:
            raise HTTPException(422, "Diese Laboransicht gehört nicht zum geöffneten Rezept.") from None
    else:
        result.pop("lab_view", None)
    return result


def response(db, unit, user):
    signature = stamp(db, unit)
    row = db.get(UnitVisualPosition, (unit.id, user.id))
    valid = bool(signature and row and row.source_signature == signature and row.updated >= now() - 30 * 86400)
    position = None
    if valid:
        try:
            position = checked(db, unit, user, Position.model_validate(row.position))
        except (HTTPException, ValueError):
            pass
    return {"source_signature": signature, "revision": row.revision if valid else 0, "position": position}


@router.get("/units/{unit_id}/visual-position")
def read_position(unit_id: str, actor: str = Header(default="", alias="X-Schulpilot-Account"), p=Depends(authenticated), db=Depends(get_db)):
    if actor != p.user.id:
        raise HTTPException(409, "Die Anmeldung wurde geändert. Bitte lade deine aktuelle Ansicht.")
    return response(db, get_unit(db, p, unit_id), p.user)


@router.put("/units/{unit_id}/visual-position")
def save_position(unit_id: str, value: PositionRequest, actor: str = Header(default="", alias="X-Schulpilot-Account"), p=Depends(authenticated), db=Depends(get_db)):
    if actor != p.user.id:
        raise HTTPException(409, "Die Anmeldung wurde geändert. Bitte lade deine aktuelle Ansicht.")
    session_id, user_id = p.session.id, p.user.id
    unit = get_unit(db, p, unit_id, lock=True)
    # Serialize all positions of this user as well as ordinary unit-child writes.
    from .db import User

    db.execute(update(Child).where(Child.id == unit.child_id).values(grade=Child.grade))
    db.execute(update(User).where(User.id == p.user.id).values(display_name=User.display_name))
    db.expire_all()
    from .db import Session

    session, user = db.get(Session, session_id), db.get(User, user_id)
    if not session or session.revoked or session.expires <= now() or session.seen < now() - 7 * 86400 or not user or user.disabled or not user.verified:
        raise HTTPException(401, "Bitte erneut anmelden.")
    child_access(db, p, unit.child_id)
    if stamp(db, unit) != value.source_signature:
        raise HTTPException(409, "Die Quelle der Erklärung wurde geändert. Lade den aktuellen Stand.")
    position = checked(db, unit, p.user, value.position)
    row = db.get(UnitVisualPosition, (unit.id, p.user.id))
    same = row and row.source_signature == value.source_signature and row.updated >= now() - 30 * 86400
    if value.revision != (row.revision if same else 0):
        raise HTTPException(409, "Die Leseposition wurde auf einem anderen Gerät geändert.")
    if row is None:
        row = UnitVisualPosition(unit_id=unit.id, user_id=p.user.id)
        db.add(row)
    row.source_signature, row.revision, row.position, row.updated = value.source_signature, value.revision + 1, position, int(now())
    db.flush()
    db.execute(delete(UnitVisualPosition).where(UnitVisualPosition.user_id == p.user.id, UnitVisualPosition.updated < now() - 30 * 86400))
    old = list(db.scalars(select(UnitVisualPosition).where(UnitVisualPosition.user_id == p.user.id, UnitVisualPosition.unit_id != unit.id)
                         .order_by(UnitVisualPosition.updated.desc(), UnitVisualPosition.unit_id).offset(7)))
    for item in old:
        db.delete(item)
    db.commit()
    return response(db, unit, p.user)


def export_user(db, user_id):
    return [{"unit_id": row.unit_id, "source_signature": row.source_signature, "revision": row.revision,
             "position": row.position, "updated": row.updated}
            for row in db.scalars(select(UnitVisualPosition).where(UnitVisualPosition.user_id == user_id,
                                  UnitVisualPosition.updated >= now() - 30 * 86400))]
