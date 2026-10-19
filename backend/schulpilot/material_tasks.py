"""Literal task candidates are proposals, never automatic binding homework."""

import hashlib
import json
import re
import unicodedata
from datetime import datetime
from difflib import SequenceMatcher
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import select

from .db import Assignment, Material, SchoolDay
from .schemas import Preferences

HEADING = re.compile(r"^(?:probeaufgabe|beispiel|übung|hausaufgaben?|(?:lern)?auftrag|aufgabe(?:\s+\d+[a-z]?)?|\d{1,3}[.)]|[a-z][.)])\s*:?$", re.I)


def canonical(text):
    return " ".join(unicodedata.normalize("NFKC", text).casefold().split())


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def preview(content, notes, decisions=None):
    selected = {row["key"]: row for row in decisions or []}
    lines = [line.strip() for note in notes for line in note.splitlines() if line.strip()]
    candidates, index = {}, 0
    while index < len(lines):
        line = lines[index]
        index += 1
        if HEADING.fullmatch(line):
            if index >= len(lines) or HEADING.fullmatch(lines[index]):
                continue  # a heading is never an actionable task
            line += " " + lines[index]
            index += 1
        # Keep numbering and concrete expressions. Only a generic header can
        # be ignored for duplicate identity, never distinct exercise numbers.
        identity = re.sub(r"^(?:probeaufgabe|beispiel|übung|hausaufgaben?|auftrag)\s*:\s*", "", canonical(line))
        if not identity or len(identity) < 3:
            continue
        source_match = canonical(line) in canonical(content)
        classification = ("example" if re.match(r"(?:probeaufgabe|beispiel|übung)\b", line, re.I)
                          else "homework" if source_match and re.match(r"(?:hausaufgaben?|lernauftrag)\b", line, re.I)
                          else "unclear")
        key = fingerprint(identity)[:24]
        if key in selected:
            classification = selected[key]["classification"]
        candidates.setdefault(key, {"key": key, "text": line, "classification": classification,
                                    "source_text_found": source_match, "identity": identity})
    return list(candidates.values())


def source_day(db, material, child):
    day = db.get(SchoolDay, material.school_day_id) if material.school_day_id else None
    return day.school_date if day else datetime.fromtimestamp(material.created, ZoneInfo(Preferences(**child.preferences).timezone)).date().isoformat()


def apply_decisions(db, material, child, decisions, *, source_changed=False):
    candidates = {row["key"]: row for row in preview(material.content, material.homework)}
    if len({row.key for row in decisions}) != len(decisions) or any(row.key not in candidates for row in decisions):
        raise HTTPException(409, "Die Aufgaben wurden geändert. Bitte die aktuelle Vorschau prüfen.")
    # A correction never deletes a task or detaches its existing learning units.
    if source_changed:
        for assignment in db.scalars(select(Assignment).where(Assignment.child_id == child.id, Assignment.material_id == material.id)):
            if assignment.source_key or assignment.kind == "homework":
                assignment.source_status = "needs_review"
                assignment.revision += 1
    added = duplicates = 0
    for decision in decisions:
        row = candidates[decision.key]
        key = fingerprint([child.id, source_day(db, material, child), row["identity"],
                           decision.due.isoformat() if decision.due else None])
        assignment = db.scalar(select(Assignment).where(Assignment.source_key == key, Assignment.child_id == child.id))
        if decision.classification != "homework":
            if assignment and assignment.material_id == material.id:
                assignment.mandatory = False
                assignment.source_status = "dismissed"
                assignment.revision += 1
            continue
        source = {"id": material.id, "revision": material.revision}
        if assignment is None:
            assignment = Assignment(child_id=child.id, material_id=material.id, kind="homework", origin_kind="homework",
                                    subject=material.subject, topic=material.topic, note=row["text"], source_key=key,
                                    source_revisions=[source], source_status="confirmed", mandatory=True,
                                    due=decision.due.isoformat() if decision.due else None)
            db.add(assignment)
            added += 1
        else:
            refs = [r for r in assignment.source_revisions if r["id"] != material.id]
            assignment.source_revisions = [*refs, source]
            assignment.source_status = "confirmed"
            # Explicitly selecting a dismissed proposal as homework restores
            # its obligation; it must not silently stay an optional example.
            if not assignment.mandatory and assignment.material_id == material.id:
                assignment.mandatory = True
                assignment.revision += 1
            duplicates += 1
    return {"added": added, "duplicates": duplicates, "unplanned": sum(row.classification != "homework" for row in decisions)}


def duplicate_sources(db, material):
    """Warn about near-identical text; never merge a different photo by guess."""
    text = canonical(material.content)
    if len(text) < 40:
        return []
    result = []
    others = db.scalars(select(Material).where(Material.child_id == material.child_id,
                                              Material.id != material.id, Material.created >= material.created - 86400)
                         .order_by(Material.created.desc(), Material.id).limit(40))
    for other in others:
        candidate = canonical(other.content)
        similar = (candidate and abs(len(candidate) - len(text)) <= max(10, len(text) * .03)
                   and SequenceMatcher(None, text[:2000], candidate[:2000]).ratio() >= .97)
        if candidate and (candidate == text or similar):
            result.append({"id": other.id, "title": other.topic or other.title, "same_text": candidate == text})
    return result[:3]
