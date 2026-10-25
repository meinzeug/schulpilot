"""Closed, content-free Pydantic diagnostics; never changes provider billing.

Known local validator messages are matched exactly in memory to public tags.
No message, input, context, model title or arbitrary error type is retained.
This is diagnostic metadata only, never a repair or an acceptance decision.
"""
from pydantic import ValidationError

_FIELDS = frozenset("""
units questions id type prompt options answer accepted hints explanation group_id subject topic content
uncertainties homework legibility explanation_steps competence_id disclosure presentation version evidence_kind
blocks kind title source_excerpt labels numbers connections marks unit variant scene text_probe lab
objects layout steps transition_ms caption placements object_id slot highlight edges start end label shape tone
index role segments text variants order parameters mass_kg acceleration_m_s2 example_id recipe_id recipe_version
reference source_refs field_group fields answer_ui value position
""".split())
_REASONS = {
    "Value error, Lernszene benötigt Szenendaten und Textalternative, keine fachfremden Grafikparameter.": "scene_parameters",
    "Value error, Szenendaten gehören ausschließlich zu kind scene.": "scene_kind",
    "Value error, Bruchmodell braucht Zähler und positiven Nenner bis24.": "fraction_bounds",
    "Value error, Textproben benötigen eine geöffnete Hilfe/Lösung und ausschließlich Textprobenparameter.": "text_probe_parameters",
    "Value error, Textprobendaten gehören ausschließlich zu kind text_probe.": "text_probe_parameters",
    "Value error, Eigenes Lernlabor benötigt ausschließlich Rezeptparameter und eine Textalternative.": "lab_parameters",
    "Value error, Labordaten gehören ausschließlich zu kind lab.": "lab_parameters",
    "Value error, Parameter gehören nicht zum gewählten eigenen Laborrezept.": "lab_parameters",
}


def _location(value):
    if not isinstance(value, (tuple, list)):
        return "field"
    parts = [str(item) if type(item) is int and 0 <= item <= 99999 else item
             if isinstance(item, str) and item in _FIELDS else "field" for item in value[:16]]
    while len(".".join(parts)) > 200:
        parts.pop()
    return ".".join(parts) or "field"


def annotate(result, error):
    """Add <=3 closed diagnostics and return the identical Result, or None.

    Optional billing results remain optional. Malformed/non-Pydantic errors or
    non-dict pre-existing telemetry are left untouched; diagnosis must not mask
    the actual exception or alter a financial receipt.
    """
    if result is None or not isinstance(error, ValidationError):
        return result
    telemetry = result.telemetry
    if telemetry is not None and not isinstance(telemetry, dict):
        return result
    entries = error.errors(include_input=False, include_context=False, include_url=False)
    diagnostics = [{"location": _location(item.get("loc")),
                    "reason": _REASONS.get(item.get("msg"), "schema_validation")} for item in entries[:3]]
    result.telemetry = {**(telemetry or {}), "validation": {"version": 1, "errors": diagnostics}}
    return result
