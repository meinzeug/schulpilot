"""Small complete outputs per persisted package part; never trim responses.

Only new server-planned parts use these bounds. Original source text, quotes,
answers, saved units and provider limits retain their existing contracts.
"""

REVISION = "package-part-output-1"


def enabled(payload):
    return payload.get("package_partition") is not None


def bind_schema(schema):
    def walk(node):
        if not isinstance(node, dict):
            return
        props = node.get("properties", {})
        if "questions" in props:
            props["questions"].update(minItems=2, maxItems=2)
            props["explanation"]["maxLength"] = 900
        if "prompt" in props and "hints" in props:
            props["prompt"]["maxLength"] = 300
            props["hints"]["maxItems"] = 2
            props["hints"]["items"]["maxLength"] = 180
            props["explanation"]["maxLength"] = 400
            # All explanatory graphics live in the one step, with its explicit
            # reference and disclosure. Do not request a second duplicate panel.
            props["presentation"] = {"type": "null"}
        if "explanation_steps" in props:
            field = props["explanation_steps"]
            for array in field.get("anyOf", [field]):
                if array.get("type") == "array":
                    array.update(minItems=1, maxItems=1)
        if "competence_id" in props and "source_refs" in props and "presentation" in props:
            props["text"]["maxLength"] = 350
        if "blocks" in props and "evidence_kind" in props:
            props["blocks"].update(minItems=1, maxItems=1)
        if "objects" in props and "layout" in props and "steps" in props:
            props["objects"]["maxItems"] = 4
            props["steps"].update(minItems=2, maxItems=2)
        if "placements" in props and "caption" in props:
            props["placements"]["maxItems"] = 4
            props["highlight"]["maxItems"] = 4
            props["edges"]["maxItems"] = 4
            props["caption"]["maxLength"] = 160
        for key in ("properties", "$defs"):
            for child in node.get(key, {}).values():
                walk(child)
        for key in ("items", "additionalProperties"):
            walk(node.get(key))
        for key in ("anyOf", "oneOf", "allOf"):
            for child in node.get(key, []):
                walk(child)

    walk(schema)


def validate(data):
    """Reject oversized generated prose/steps, with all semantic guards intact."""
    units = data.get("units", [])
    if len(units) != 1:
        raise ValueError("Ein Lernpaketteil benötigt genau ein Fach.")
    for unit in units:
        if len(unit["questions"]) != 2 or len(unit["explanation"]) > 900:
            raise ValueError("Der Lernpaketteil überschreitet den begrenzten Umfang.")
        for question in unit["questions"]:
            if (len(question["prompt"]) > 300 or len(question["explanation"]) > 400
                    or question.get("presentation") is not None or len(question["hints"]) > 2
                    or any(len(hint) > 180 for hint in question["hints"])):
                raise ValueError("Die Aufgabe überschreitet den begrenzten Ausgabeumfang.")
        for item in [unit, *unit["questions"]]:
            steps = item.get("explanation_steps")
            if steps is None:
                continue  # Existing required-visual validation remains authoritative.
            if len(steps) != 1:
                raise ValueError("Ein Erklärabschnitt benötigt genau einen vollständigen Grafikschritt.")
            for step in steps:
                blocks = step["presentation"]["blocks"]
                if len(step["text"]) > 350 or len(blocks) != 1:
                    raise ValueError("Der Grafikschritt überschreitet den begrenzten Umfang.")
                for block in blocks:
                    scene = block.get("scene")
                    if scene is not None and (len(scene["objects"]) > 4 or len(scene["steps"]) != 2 or any(
                            len(phase["placements"]) > 4 or len(phase["highlight"]) > 4
                            or len(phase["edges"]) > 4 or len(phase["caption"]) > 160
                            for phase in scene["steps"])):
                        raise ValueError("Die Lernszene benötigt zwei überschaubare vollständige Phasen.")


RULES = """
PERSISTENTER LERNPAKETTEIL: Dies ist EIN kleiner Teil eines größeren gespeicherten Lernplans.
Erzeuge genau eine Einheit zum übergebenen Fach und genau zwei vollständige Aufgaben.
Andere Teile werden separat erzeugt; keine weiteren Heftseiten oder Themen hinzuerfinden.
Eine kurze Einführung (höchstens900 Zeichen), je Aufgabe eine klare Frage (höchstens300),
ein bis zwei kurze Hinweise (je höchstens180) und eine Erklärung (höchstens400).
Je Einführung und Frage genau EIN fachlich sinnvoller Erklärschritt mit EINER passenden Grafik;
Schritttext höchstens350 Zeichen. Die beiden Aufgaben dürfen weiterhin verschiedene Ziele prüfen.
Falls eine Lernszene passt: höchstens vier Objekte und genau zwei tatsächlich unterschiedliche,
belegte Phasen mit sinnvollen Beziehungen. Keine ausführliche Präsentation mit vielen Folien.
Alle Aufgaben, Hinweise, Lösungen, Zahlen, Einheiten und wörtlichen Belege bleiben vollständig
und müssen sämtliche Quellen-, Fach-, Offenlegungs- und Grafikregeln erfüllen.
Keine fehlenden Daten erfinden, keine Originalquelle oder Antwort zum Einpassen verkürzen.
Dies ist weder der gesamte Lernstoff noch ein Nachweis für bereits beherrschte Fähigkeiten.
"""
