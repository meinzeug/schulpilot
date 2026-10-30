"""Read-only protection for a proven artifact in older generated rounds.

Keep original snapshots and attempts. This narrow check is not a retrospective
semantic review and never repairs or regenerates content on GET.
"""
import re

_CORRECTION = re.compile(r"(?<![A-Za-z])oops\s+bad\s+character\s+need\s+fix\b", re.I)
MESSAGE = "Diese ältere Runde enthält einen Fehler. Öffne deine Heftseite und starte dort eine neue Übung. Deine bisherigen Antworten bleiben gespeichert."


def issue(unit):
    if unit.status == "completed":
        return None
    for item in [{"explanation": unit.explanation}, *unit.questions]:
        texts = [item.get(key) for key in ("prompt", "explanation")]
        texts.extend(item.get("hints") or [])
        texts.extend(step.get("text") for step in item.get("explanation_steps") or [] if isinstance(step, dict))
        if any(isinstance(text, str) and _CORRECTION.search(text) for text in texts):
            return {"code": "generated_correction_artifact", "message": MESSAGE}
    return None
