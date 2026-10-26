"""Literal notebook reading for chat, separate from grading ground truth.

Call only after ordinary child/source authorization. A marked pupil example is
still readable text. Its marks and uncertainty must travel with it rather than
silently making the whole page disappear from an explanatory conversation.
"""

from .source_lineage import literal_blocks

VERSION = "schulbuddy-notebook-reading-1"


def is_page(scope, material):
    return material.purpose == "notebook" and scope.get("material_id") == material.id and not any(
        scope.get(key) for key in ("unit_id", "day_id", "exam_id", "learning_asset_instance_id")
    )


def projection(material, safe):
    if material.purpose != "notebook" or not material.confirmed or not material.content.strip():
        raise ValueError("Literal chat reading requires the current confirmed notebook page")
    blocks = literal_blocks(material)
    return {
        "version": VERSION,
        "content": material.content,
        "evidence_kind": "notebook_literal_reading",
        "authoritative_solution": False,
        "legibility": material.legibility,
        "uncertainties": list(material.uncertainties or []),
        "literal_blocks": blocks,
        "learning_exclusions": [
            {"reason": item["reason"], "message": item["message"]} for item in safe["exclusions"]
        ],
        "notice": (
            "Gespeicherte wörtliche Abschrift mit dokumentierten Markierungen, keine geprüfte Musterlösung. "
            "Eine Sperre für bewertete Aufgaben ist kein Leseverbot. Lesbare Teile erklären; "
            "unsichere oder korrigierte Stellen konkret benennen und nicht als richtig bestätigen. "
            "Bildbereiche und Farben stammen aus der Abschrift; das Modell erhält keine Originalpixel."
        ),
    }
