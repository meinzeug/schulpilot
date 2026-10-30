"""Small complete outputs per persisted package part; never trim responses.

Only new server-planned parts use these bounds. Original source text, quotes,
answers, saved units and provider limits retain their existing contracts.
"""

import copy
import json
import re

from .graphic_schema import bind_coherent_graphics as _bind_graphic_branches

REVISION = "package-part-output-1"
GRAPHIC_SCHEMA_REVISION = "package-part-graphics-4"
_REPEATED_WORD = re.compile(r"(?<!\w)([^\W\d_]{2,40})(?:[\s,;]+\1){5,}(?!\w)", re.IGNORECASE)
_SOLUTION_VISUAL_IN_PROMPT = re.compile(r"\b(?:lösungs|antwort)(?:grafik|bild|darstellung|szene)\b", re.IGNORECASE)
_MODEL_INSTRUCTIONS = re.compile(
    r"\[\s*(?:the\s+)?(?:prompt|question|answer|options?)(?:['’]s)?\b"
    r"|\[\s*(?:full\s+)?source\s+(?:sentence|text)\b"
    r"|\b(?:actually|instead),?\s+(?:options?|the\s+(?:question|answer|prompt))\b"
    r"|\b(?:but|the)\s+(?:problem\s+)?prompt\s+(?:requires|should|needs)\b"
    r"|\bkeep\s*:\s*"
    r"|(?<![A-Za-z])oops\s+bad\s+character\s+need\s+fix\b", re.IGNORECASE,
)
_HIDDEN_DIRECTION = re.compile(r"[\u061c\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069]")


def enabled(payload):
    return payload.get("package_partition") is not None


def bind_schema(schema, payload=None, *, question_count=2):
    if type(question_count) is not int or not 2 <= question_count <= 5:
        raise ValueError("Ungültiger Umfang der kompakten Lernrunde.")
    def walk(node):
        if not isinstance(node, dict):
            return
        props = node.get("properties", {})
        if "questions" in props:
            props["questions"].update(minItems=question_count, maxItems=question_count)
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
    if payload is not None:
        _bind_references(schema, payload)
        from .package_decimal_addition import bind_schema as bind_decimal_addition

        binding = bind_decimal_addition(schema, payload)
        if binding is not None:
            return binding
        from .package_prepared_graphics import bind_schema as bind_prepared_graphics

        binding = bind_prepared_graphics(schema, payload)
        if binding is not None:
            return binding
        from .package_prepared_scenes import bind_schema as bind_source_graphics

        return bind_source_graphics(schema, payload)
    return None


def _bind_references(schema, payload, *, unit_subject=None):
    """Bind the chosen immutable recipe and disclosure to the SAME step.

    Only a new planned request is affected. Full strict objects, ordinary refs
    and nested anyOf are understood by all existing adapters and the codec.
    Canonical source/numeric/answer checks still validate the decoded response.
    """
    from .visual_references import ORIGINAL_COMPARISONS

    context = payload.get("visual_context") or {}
    if (not enabled(payload) and unit_subject is None) or not context.get("required"):
        return
    definitions = schema.get("$defs", {})
    templates = {key: copy.deepcopy(definitions[key]) for key in
                 ("ExplanationStep", "Presentation", "VisualReferenceChoice", "Graphic")}
    registered = {}

    def resolved(node):
        if "$ref" in node:
            return copy.deepcopy(definitions[node["$ref"].rsplit("/", 1)[-1]])
        return copy.deepcopy(node)

    def register(node):
        key = json.dumps(node, sort_keys=True, separators=(",", ":"))
        if key not in registered:
            name = "PartExplanation" + str(len(registered) + 1)
            while name in definitions:
                name += "x"
            definitions[name] = node
            registered[key] = {"$ref": "#/$defs/" + name}
        return copy.deepcopy(registered[key])

    def graphic_for(reference, stage):
        kind = reference.get("kind")
        original = next((branch for branch in templates["Graphic"].get("anyOf", [])
                         if kind in branch["properties"]["kind"].get("enum", [])), None)
        if original is None or stage not in original["properties"]["disclosure"].get("enum", []):
            return None
        graphic = copy.deepcopy(original)
        fields = graphic["properties"]
        fields["kind"] = {"type": "string", "enum": [kind]}
        fields["disclosure"] = {"type": "string", "enum": [stage]}
        variant = reference.get("variant")
        if variant:
            if "enum" in fields["variant"] and variant not in fields["variant"]["enum"]:
                return None
            if variant in ("roots", "pollination") and stage != "solution":
                return None
            fields["variant"] = {"type": "string", "enum": [variant]}
        if reference.get("id") in ORIGINAL_COMPARISONS:
            # The original-language comparison has one finite parameter
            # family. Do not invite irrelevant marks, numbers or relations.
            fields["labels"].update(minItems=2, maxItems=4)
            for name in ("numbers", "connections", "marks"):
                fields[name].update(minItems=0, maxItems=0)
            fields["unit"] = {"type": "string", "enum": [""]}
        if kind == "lab":
            recipe = reference.get("lab_recipe_id")
            if not recipe:
                return None
            lab = resolved(fields["lab"])
            if recipe not in lab["properties"]["recipe_id"].get("enum", []):
                return None
            lab["properties"]["recipe_id"] = {"type": "string", "enum": [recipe]}
            # These are the two existing finite LabV1 parameter families, not
            # client/model supplied programs or inferred physical values.
            family = {"physics.force_motion": "ForceParameters", "german.sentence_shift": "SentenceParameters"}.get(recipe)
            if family is None:
                return None
            lab["properties"]["parameters"] = {"$ref": "#/$defs/" + family}
            fields["lab"] = register(lab)
        return register(graphic)

    def steps_for(subject, group, *, introduction):
        sources = [row["ref"] for row in context.get("sources", [])
                   if row.get("subject") == subject and row.get("group_id") == group]
        if not sources:
            raise ValueError("Der Teilauftrag hat keine passende Fach-/Gruppenquelle für Erklärschritte.")
        competences = [row["id"] for row in context.get("competences", []) if row.get("subject") == subject]
        branches = []
        group_sources = [row.get("content", "") for row in context.get("sources", [])
                         if row.get("subject") == subject and row.get("group_id") == group]
        original_comparison = any(row.get("subject") == subject
            and row.get("id") in ORIGINAL_COMPARISONS for row in context.get("references", []))
        for reference in context.get("references", []):
            if reference.get("subject") != subject:
                continue
            if subject != "Mathematik":
                from .package_prepared_scenes import reference_supported

                if not reference_supported(reference, group_sources):
                    continue
            if (original_comparison and reference.get("id") == "general.source_relation.phases"
                    and not any(re.search(r"→|->", source) for source in group_sources)):
                # This old recipe requires a literal directed source edge.
                # Offer the applicable comparison instead of an impossible
                # arrow recipe; canonical relation validation stays intact.
                continue
            for stage in (("given",) if introduction else ("hint1", "hint2", "hint3", "solution")):
                graphic = graphic_for(reference, stage)
                if graphic is None:
                    continue
                presentation = copy.deepcopy(templates["Presentation"])
                presentation["properties"]["blocks"]["items"] = graphic
                choice = copy.deepcopy(templates["VisualReferenceChoice"])
                choice["properties"]["id"]["enum"] = [reference["id"]]
                choice["properties"]["version"]["enum"] = [reference["version"]]
                step = copy.deepcopy(templates["ExplanationStep"])
                fields = step["properties"]
                fields["reference"] = register(choice)
                fields["disclosure"] = {"type": "string", "enum": [stage]}
                fields["presentation"] = register(presentation)
                fields["source_refs"]["items"]["enum"] = list(dict.fromkeys(sources))
                fields["competence_id"] = ({"anyOf": [{"type": "string", "enum": competences}, {"type": "null"}]}
                                           if competences else {"type": "null"})
                branch = register(step)
                if branch not in branches:
                    branches.append(branch)
        if not branches:
            raise ValueError("Der Teilauftrag hat keine passende Referenz/Grafik für seine Aufdeckstufe.")
        return {"type": "array", "minItems": 1, "maxItems": 1,
                "items": branches[0] if len(branches) == 1 else {"anyOf": branches}}

    groups = {(row["subject"], row["id"]) for row in payload.get("selected_groups", [])}

    def bind_questions(node, subject, group):
        node = resolved(node)
        if "anyOf" in node:
            node["anyOf"] = [bind_questions(branch, subject, group) for branch in node["anyOf"]]
        elif "explanation_steps" in node.get("properties", {}):
            node["properties"]["explanation_steps"] = steps_for(subject, group, introduction=False)
            if unit_subject is not None:
                # A second independent panel would bypass the reference/stage
                # contract. New ordinary units use their bound explanation.
                node["properties"]["presentation"] = {"type": "null"}
        return node

    def bind_units(node):
        node = resolved(node)
        if "anyOf" in node:
            node["anyOf"] = [bind_units(branch) for branch in node["anyOf"]]
            return node
        fields = node.get("properties", {})
        subjects, ids = fields.get("subject", {}).get("enum", []), fields.get("group_id", {}).get("enum", [])
        matches = [(subject, group) for subject, group in groups
                   if (not subjects or subject in subjects) and (not ids or group in ids)]
        if len(matches) != 1:
            raise ValueError("Die Erklärgrafik benötigt das eindeutig geplante Fach und die Paketgruppe.")
        subject, group = matches[0]
        fields["subject"]["enum"], fields["group_id"]["enum"] = [subject], [group]
        fields["explanation_steps"] = steps_for(subject, group, introduction=True)
        fields["questions"]["items"] = bind_questions(fields["questions"]["items"], subject, group)
        return node

    if unit_subject is not None:
        fields = schema["properties"]
        subjects = fields["subject"].get("enum", [])
        if subjects and unit_subject not in subjects:
            raise ValueError("Die Erklärgrafik gehört nicht zum gebundenen Fach.")
        fields["subject"]["enum"] = [unit_subject]
        fields["explanation_steps"] = steps_for(unit_subject, None, introduction=True)
        fields["questions"]["items"] = bind_questions(fields["questions"]["items"], unit_subject, None)
        return

    units = schema.get("properties", {}).get("units")
    if units is None:
        raise ValueError("Der Grafikvertrag benötigt einen geplanten Paketauftrag.")
    units["items"] = bind_units(units["items"])


def validate(data):
    """Reject oversized generated prose/steps, with all semantic guards intact."""
    units = data.get("units", [])
    if len(units) != 1:
        raise ValueError("Ein Lernpaketteil benötigt genau ein Fach.")
    for unit in units:
        if len(unit["questions"]) != 2 or len(unit["explanation"]) > 900:
            raise ValueError("Der Lernpaketteil überschreitet den begrenzten Umfang.")
        generated_texts = [unit["explanation"]]
        for item in [unit, *unit["questions"]]:
            generated_texts.extend(step["text"] for step in (item.get("explanation_steps") or []))
        if any(_MODEL_INSTRUCTIONS.search(text) or _HIDDEN_DIRECTION.search(text) for text in generated_texts):
            raise ValueError("Eine Aufgabe enthält interne Anweisungen statt eines verständlichen Fragetexts.")
        for question in unit["questions"]:
            if any(_MODEL_INSTRUCTIONS.search(text) or _HIDDEN_DIRECTION.search(text)
                   for text in (question["prompt"], question["explanation"], *question["hints"])):
                raise ValueError("Eine Aufgabe enthält interne Anweisungen statt eines verständlichen Fragetexts.")
            if any(_REPEATED_WORD.search(text) for text in (question["prompt"], question["explanation"], *question["hints"])):
                raise ValueError("Eine Aufgabe enthält eine stark wiederholte Formulierung.")
            if _SOLUTION_VISUAL_IN_PROMPT.search(question["prompt"]):
                raise ValueError("Eine Aufgabenstellung verweist auf eine Lösungsgrafik.")
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
Die Frage steht für sich und verweist nie auf eine Lösungsgrafik oder spätere Lösungsdarstellung.
Schreibe ausschließlich den fertigen Text für das Kind. Keine internen Überlegungen,
Arbeitsanweisungen, Platzhalter oder nachträglich angehängten Prüfvermerke ausgeben.
Nenne die gesuchte Antwort nicht vorab in der Frage; notwendige Angaben und Beispiele bleiben erhalten.
Keine fehlenden Daten erfinden, keine Originalquelle oder Antwort zum Einpassen verkürzen.
Dies ist weder der gesamte Lernstoff noch ein Nachweis für bereits beherrschte Fähigkeiten.
"""


RULES += """
package-part-graphics-4: reference.id/version gehört zu genau DEM gebundenen Grafiktyp,
seiner freigegebenen Variante und gegebenenfalls seinem Laborrezept. Quellen nur aus demselben
Fach und derselben Gruppe. Einführung given, Fragen Hinweis/Lösung; Text und Grafik dieselbe Stufe.
kind bestimmt die PARAMETERFAMILIE; die Feldnamen können im Wire Aliase haben.
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
