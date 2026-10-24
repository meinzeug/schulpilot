"""Resolve a finite UI selection from saved, actually disclosed graphics only."""

from fractions import Fraction

from fastapi import HTTPException
from sqlalchemy import select

from .db import Activity, Attempt


def _unavailable():
    raise HTTPException(409, "Dieser Erklärschritt ist nicht mehr geöffnet. Bitte die aktuelle Erklärung wählen.")


def _phase(block, phase):
    kind = block["kind"]
    if phase == "initial":
        return {"phase": "initial"}
    if phase.startswith("fraction-"):
        if kind != "fraction" or len(block.get("numbers", [])) != 2:
            raise HTTPException(422, "Die gewählte Ansicht gehört nicht zu dieser Grafik.")
        _, representation, focus = phase.split("-")
        numerator, denominator = block["numbers"]
        return {
            "phase": phase,
            "representation": representation,
            "focus": focus,
            "numerator": numerator,
            "denominator": denominator,
        }
    if phase.startswith("scene-"):
        index = int(phase.split("-")[1])
        if kind == "scene":
            scene = block.get("scene") or {}
            steps = scene.get("steps", [])
            if index >= len(steps):
                raise HTTPException(422, "Diese Phase ist in der gespeicherten Szene nicht vorhanden.")
            step = steps[index]
            labels = {obj["id"]: obj["label"] for obj in scene.get("objects", [])}
            return {
                "phase": phase,
                "step_index": index,
                "caption": step["caption"],
                "highlighted_labels": [labels[value] for value in step.get("highlight", [])],
                "connections": [
                    {"start": labels[edge["start"]], "end": labels[edge["end"]], "label": edge["label"]}
                    for edge in step.get("edges", [])
                ],
            }
        if kind in ("process_graph", "process_cycle") and index < len(block.get("labels", [])):
            return {"phase": phase, "step_index": index, "highlighted_labels": [block["labels"][index]]}
        raise HTTPException(422, "Diese Grafik besitzt die gewählte Szene nicht.")
    if phase.startswith("science-"):
        index = int(phase.split("-")[1])
        numbers, variant = block.get("numbers", []), block.get("variant", "")
        if kind == "function_graph" and variant == "polynomial2" and len(numbers) == 3 and index <= 80:
            x = Fraction(index - 40, 10)
            a, b, c = [Fraction(str(number)) for number in numbers]
            y = a * x * x + b * x + c
            return {"phase": phase, "point_index": index, "x": float(x), "y": float(y), "derived_locally": True}
        if kind == "data_plot" and len(numbers) % 2 == 0 and index < len(numbers) // 2:
            return {"phase": phase, "point_index": index, "x": numbers[2 * index], "y": numbers[2 * index + 1]}
        if kind == "logic_table" and variant in ("and_gate", "or_gate", "not_gate"):
            if variant == "not_gate" and index <= 1:
                return {"phase": phase, "inputs": {"A": index}, "Y": 1 - index}
            if variant != "not_gate" and index <= 3:
                a, b = index // 2, index % 2
                return {"phase": phase, "inputs": {"A": a, "B": b}, "Y": a & b if variant == "and_gate" else a | b}
        raise HTTPException(422, "Der gewählte Messpunkt oder Logikzustand ist nicht vorhanden.")
    raise HTTPException(422, "Die gewählte Grafikphase ist nicht gültig.")


def bind(db, p, scope, unit, payload):
    """No new disclosure, progress, answer, fetch or model request."""
    from . import coaching
    from .visual_references import projection, question_projection

    if not scope.explanation_step_id:
        return None
    if not unit:
        _unavailable()
    if scope.explanation_kind == "intro":
        allowed = p.user.role == "parent" or unit.round_kind not in coaching.CHECK_KINDS or unit.status == "completed"
        steps = projection(db, unit, show_introduction=allowed)["explanation_steps"]
    else:
        question_id = (payload.get("current_question") or {}).get("id")
        question = next((row for row in unit.questions if row["id"] == question_id), None)
        if question is None or question_id != scope.question_id:
            _unavailable()
        attempts = list(
            db.scalars(select(Attempt).where(Attempt.unit_id == unit.id, Attempt.question_id == question_id))
        )
        hints = list(
            db.scalars(
                select(Activity).where(
                    Activity.unit_id == unit.id,
                    Activity.kind == "hint",
                    Activity.detail["question_id"].as_string() == question_id,
                )
            )
        )
        closed = (
            p.user.role == "parent"
            or unit.status == "completed"
            or len(attempts) >= 3
            or any(row.outcome in ("correct", "uncertain") for row in attempts)
        )
        steps = question_projection(db, unit, question, closed=closed, hints=len(hints))
    step = next((row for row in steps if row["id"] == scope.explanation_step_id), None)
    if step is None:
        _unavailable()
    resolved = {
        "kind": scope.explanation_kind,
        "step_id": step["id"],
        "text": step["text"],
        "disclosure": step["disclosure"],
        "reference": {
            key: value
            for key, value in step.get("reference", {}).items()
            if key in ("id", "version", "parameter_digest", "digest")
        },
    }
    if scope.graphic_index is not None:
        blocks = (step.get("presentation") or {}).get("blocks", [])
        if not 0 <= scope.graphic_index < len(blocks):
            raise HTTPException(409, "Die gewählte Grafik gehört nicht mehr zu diesem Erklärschritt.")
        block = blocks[scope.graphic_index]
        # Only the public saved projection, never model quotes/hidden blocks.
        resolved["graphic"] = {
            key: block[key]
            for key in ("kind", "title", "labels", "numbers", "unit", "variant", "description")
            if key in block
        }
        resolved["graphic_index"] = scope.graphic_index
        resolved["graphic_state"] = _phase(block, scope.graphic_phase or "initial")
    payload["current_explanation"] = resolved
    return resolved
