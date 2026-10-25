"""Small complete outputs per persisted package part; never trim responses.

Only new server-planned parts use these bounds. Original source text, quotes,
answers, saved units and provider limits retain their existing contracts.
"""

import copy
import json

REVISION = "package-part-output-1"
GRAPHIC_SCHEMA_REVISION = "package-part-graphics-1"


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
    _bind_graphic_branches(schema)


def _nonnull(field):
    if field.get("type") == "null":
        return None
    if "anyOf" not in field:
        return copy.deepcopy(field)
    branches = [copy.deepcopy(branch) for branch in field["anyOf"] if branch.get("type") != "null"]
    return branches[0] if len(branches) == 1 else {"anyOf": branches} if branches else None


def _bind_graphic_branches(schema):
    """Mirror static Graphic.coherent constraints, only for this NEW request.

    Keep the full strict base properties for catalogue introspection. Every
    anyOf branch is itself a complete strict object; the codec can discriminate
    it by kind without allOf/conditionals or inventing missing source values.
    Cross-field arithmetic, literal evidence and disclosure remain canonical.
    """
    graphic = schema.get("$defs", {}).get("Graphic")
    if not graphic:
        return
    props = graphic["properties"]
    allowed = props["kind"]["enum"]
    branches = {}
    numeric = {"fraction", "triangle", "reflection", "notes", "bar_chart", "place_values", "money",
               "timeline", "function_graph", "data_plot", "technical_drawing"}
    labelled = {"forms", "sentence", "speech", "picture_words", "plant", "water_cycle", "perspectives",
                "statements", "flowchart", "movement", "pattern", "layers", "mindmap", "flashcard",
                "traditions", "senses", "seasons", "fairplay", "money"}
    variants = {"position": ["above", "below", "beside"], "gears": ["clockwise", "counterclockwise"],
        "circuit": ["open", "closed"], "particles": ["solid", "liquid", "gas"],
        "colour_wheel": ["RYB", "RGB"], "forces": ["pull", "push"], "notes": ["quarters"],
        "timeline": ["centuries", "calendar"], "function_graph": ["polynomial2"],
        "data_plot": ["scatter", "polyline"], "cell": ["plant_cell", "animal_cell"],
        "molecule": ["water", "carbon_dioxide", "methane", "ethanol"],
        "logic_table": ["and_gate", "or_gate", "not_gate"], "circuit_network": ["series", "parallel"],
        "technical_drawing": ["center_hole"],
        "function_curve": ["sine", "cosine", "exponential", "logarithm", "square_root", "reciprocal", "cubic", "absolute"]}
    science = {"function_graph", "data_plot", "cell", "molecule", "logic_table", "circuit_network",
               "technical_drawing", "function_curve", "process_graph", "process_cycle"}
    for kind in allowed:
        branch = copy.deepcopy(graphic)
        branch.pop("anyOf", None)
        fields = branch["properties"]
        fields["kind"] = {"type": "string", "enum": [kind]}
        for name in ("scene", "text_probe", "lab"):
            fields[name] = {"type": "null"}
        if kind not in numeric:
            fields["numbers"].update(minItems=0, maxItems=0)
        if kind != "sentence":
            fields["marks"].update(minItems=0, maxItems=0)
        if kind in ("scene", "text_probe", "lab"):
            selected = _nonnull(props[kind])
            if selected is None:
                continue  # The previously applied client capability is final.
            fields[kind] = selected
            fields["labels"]["minItems"] = max(1, fields["labels"].get("minItems", 0))
            fields["connections"].update(minItems=0, maxItems=0)
            for name in ("unit", "variant"):
                fields[name] = {"type": "string", "enum": [""]}
            if kind == "text_probe":
                fields["disclosure"]["enum"] = [stage for stage in fields["disclosure"]["enum"] if stage != "given"]
        else:
            if kind in labelled:
                fields["labels"]["minItems"] = max(1, fields["labels"].get("minItems", 0))
            if kind in variants:
                fields["variant"] = {"type": "string", "enum": variants[kind]}
            # Numeric cardinality/type is structural. Relations between values
            # (n<=d, ordered dates, one amount/category) are NOT guessed here.
            sizes = {"fraction": (2, 2), "triangle": (2, 2), "reflection": (1, 1), "notes": (1, 6),
                "bar_chart": (1, 16), "place_values": (1, 8), "money": (1, 16),
                "function_graph": (3, 3), "data_plot": (4, 16), "technical_drawing": (3, 3)}
            if kind in sizes:
                minimum, maximum = sizes[kind]
                fields["numbers"].update(minItems=minimum, maxItems=maximum)
            if kind == "fraction":
                fields["numbers"]["items"] = {"type": "number", "minimum": 0, "maximum": 24, "multipleOf": 1}
            elif kind == "place_values":
                fields["numbers"]["items"] = {"type": "number", "minimum": 0, "maximum": 1, "multipleOf": 1}
            elif kind == "notes":
                fields["numbers"]["items"] = {"anyOf": [{"type": "number", "minimum": value, "maximum": value} for value in (1, 2, 4)]}
            elif kind in ("triangle", "technical_drawing"):
                fields["numbers"]["items"]["exclusiveMinimum"] = 0
            elif kind == "bar_chart":
                fields["numbers"]["items"]["minimum"] = 0
            elif kind == "reflection":
                fields["numbers"]["items"].update(exclusiveMinimum=0, exclusiveMaximum=90)
            elif kind == "function_graph":
                fields["numbers"]["items"].update(minimum=-100, maximum=100)
            units = {"triangle": ["cm", "m"], "reflection": ["°"], "notes": ["Schläge"],
                     "money": ["€"], "technical_drawing": ["mm", "cm"]}
            if kind in units:
                fields["unit"] = {"type": "string", "enum": units[kind]}
            if kind == "position":
                fields["labels"].update(minItems=0, maxItems=0)
            label_sizes = {"layers": (3, 3), "plant": (4, 4), "flowchart": (5, 5), "gears": (2, 5),
                "picture_words": (1, 5), "senses": (1, 5), "pattern": (1, 10), "mindmap": (2, 16),
                "function_graph": (2, 2), "function_curve": (2, 2), "data_plot": (2, 2),
                "logic_table": (2, 3), "circuit_network": (2, 2), "process_graph": (2, 8), "process_cycle": (2, 8),
                "technical_drawing": (0, 0)}
            if kind in label_sizes:
                minimum, maximum = label_sizes[kind]
                fields["labels"].update(minItems=minimum, maxItems=maximum)
            if kind in science:
                if kind not in ("process_graph", "process_cycle"):
                    fields["connections"].update(minItems=0, maxItems=0)
                else:
                    fields["connections"]["minItems"] = 1
                    fields["labels"]["items"]["maxLength"] = 60
                    fields["variant"] = {"type": "string", "enum": [""]}
                if kind != "technical_drawing":
                    fields["unit"] = {"type": "string", "enum": [""]}
                if kind == "logic_table":
                    fields["disclosure"]["enum"] = [stage for stage in fields["disclosure"]["enum"] if stage != "given"]
        # Share otherwise identical parameter families; no global per-kind
        # catalogue expansion and no branch can cross the selected profile.
        shape = copy.deepcopy(branch)
        shape["properties"]["kind"].pop("enum")
        key = json.dumps(shape, sort_keys=True, separators=(",", ":"))
        if key in branches:
            branches[key]["properties"]["kind"]["enum"].append(kind)
        else:
            branches[key] = branch
    if not branches:
        raise ValueError("Für diesen Teilauftrag ist keine passende Grafik freigegeben.")
    graphic["anyOf"] = list(branches.values())


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


RULES += """
package-part-graphics-1: kind bestimmt die PARAMETERFAMILIE; die Feldnamen können im Wire Aliase haben.
scene: scene vollständig; text_probe=null,lab=null; labels enthält eine Textalternative;
numbers=[],connections=[],marks=[],unit='',variant=''. Zwei belegte unterschiedliche Phasen,
2–4 benannte Objekte, mindestens eine belegte Beziehung; Platznummern sind lokale Schemaplätze.
text_probe: nur echte Originalreihenfolgen, text_probe vollständig; scene=null,lab=null;
sonstige Parameter wie scene leer; nur Hinweis/Lösung, niemals given.
lab: nur das freigegebene eigene Rezept mit vollständigen begrenzten Parametern; scene=null,
text_probe=null und sonst wie scene leer. Kein freies Labor/keine eigene Formel erfinden.
Alle anderen kinds: scene=null,text_probe=null,lab=null. numbers ausschließlich beim ausdrücklich
numerischen Fachmodell, sonst []. Beispiel fraction: numbers=[Zähler,Nenner] als ganze Zahlen,
0<=Zähler<=Nenner<=24 und Nenner>0; keine Prozent-/Balkenwerte, keine erfundenen Brüche.
triangle genau [Grundseite,Höhe] und cm/m; reflection ein Winkel zum Lot in °; jeder Wert muss
wie bisher belegt/geprüft sein. Für andere Modelle die tatsächlichen Typ-/Einheiten-/Varianten-
vorgaben des gewählten Fachrezepts verwenden. Nie scene/text_probe/lab-Daten kombinieren.
Wähle nur einen wirklich passenden angebotenen Typ; fehlende Belege nicht durch Ersatzinhalt auffüllen.
"""
