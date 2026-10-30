"""Schema-only structural graphic constraints; canonical validators stay final.

A request can choose only parameter families supported by its actual profile.
This never alters generated content, answers, source quotes or stored outputs.
"""
import copy
import json

RULES = """\nGRAFIKPARAMETER: fraction.numbers=[n,d] sind genau zwei ganze Zahlen mit 0 <= n <= d <= 24 und d>=1.
Der Teilkreis/Teilbalken zeigt n von d gleich großen Teilen, niemals einen unechten Bruch wie7/4 als7von4Teilen.
Für unechte Brüche keine unzulässige Teilfläche erfinden. Verwende nur eine tatsächlich passende vorhandene Darstellung
mit belegten Parametern; ändere weder Aufgabe noch Musterantwort, um eine Grafik passend zu machen.
scene/text_probe/lab enthalten ausschließlich ihre eigenen Parameter; alle anderen Spezialfelder bleiben null.
"""

def _nonnull(field):
    if field.get("type") == "null":
        return None
    if "anyOf" not in field:
        return copy.deepcopy(field)
    branches = [copy.deepcopy(branch) for branch in field["anyOf"] if branch.get("type") != "null"]
    return branches[0] if len(branches) == 1 else {"anyOf": branches} if branches else None


def bind_coherent_graphics(schema):
    """Mirror static Graphic.coherent constraints for a NEW generation request.

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
    labelled = {"forms", "sentence", "speech", "picture_words", "plant", "heart_pump", "water_cycle", "perspectives",
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
                # Endliche Paare binden die Relation n<=d; unabhängige
                # Zahlenbereiche erlauben fälschlich z.B. sieben von vier Teilen.
                fields["numbers"]["enum"] = [[n, d] for d in range(1, 25) for n in range(d + 1)]
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
            label_sizes = {"layers": (3, 3), "plant": (4, 4), "heart_pump": (3, 3), "flowchart": (5, 5), "gears": (2, 5),
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
