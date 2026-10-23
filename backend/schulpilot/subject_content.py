"""Version 1, source-bound vector instructions. No markup, assets or executable code.

Private disclosure stages/quotes remain in question snapshots. Public projection
never contains a future hint/solution, including its alternative description.
"""

import math
import re
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from . import learning_scenes, science_graphics

KINDS = (
    "fraction",
    "triangle",
    "sentence",
    "speech",
    "forms",
    "timeline",
    "picture_words",
    "plant",
    "food_chain",
    "compass",
    "position",
    "water_cycle",
    "perspectives",
    "reflection",
    "circuit",
    "particles",
    "filtration",
    "bar_chart",
    "statements",
    "flowchart",
    "place_values",
    "movement",
    "pattern",
    "colour_wheel",
    "layers",
    "mindmap",
    "flashcard",
    "notes",
    "keyboard",
    "traditions",
    "senses",
    "seasons",
    "fairplay",
    "gears",
    "forces",
    "money",
    *science_graphics.KINDS,
    "scene",
)

# The same profiles constrain generation and document the curriculum's limits.
PROFILES = {
    "Mathematik": ("fraction", "triangle"),
    "Deutsch": ("sentence", "speech"),
    "Englisch": ("forms", "timeline", "picture_words"),
    "Französisch": ("forms", "picture_words"),
    "Spanisch": ("forms", "picture_words"),
    "Latein": ("forms", "picture_words"),
    "Deutsch als Zweitsprache": ("forms", "picture_words", "sentence", "position"),
    "Biologie": ("plant", "food_chain", "forms"),
    "Geographie": ("compass", "water_cycle"),
    "Geschichte": ("timeline", "statements"),
    "Physik": ("reflection", "circuit"),
    "Chemie": ("particles", "filtration"),
    "Ethik": ("perspectives", "statements"),
    "Gemeinschaftskunde": ("bar_chart", "statements"),
    "Informatik": ("flowchart", "place_values"),
    "Kreativität und Bewegung": ("movement", "pattern"),
    "Kunst": ("colour_wheel", "layers"),
    "Lerntechniken": ("flashcard", "mindmap"),
    "Musik": ("notes", "keyboard"),
    "Religion": ("traditions", "perspectives"),
    "Sachunterricht": ("senses", "seasons"),
    "Sport": ("movement", "fairplay"),
    "Technik": ("gears", "forces"),
    "Wirtschaft": ("money", "statements"),
}
for _subject, _kinds in {
    "Mathematik": ("function_graph", "data_plot"),
    "Biologie": ("cell", "data_plot"),
    "Physik": ("function_graph", "data_plot", "circuit_network"),
    "Chemie": ("molecule", "data_plot"),
    "Technik": ("technical_drawing", "circuit_network", "logic_table", "function_graph", "data_plot"),
    "Informatik": ("logic_table", "data_plot"),
}.items():
    PROFILES[_subject] = (*PROFILES[_subject], *_kinds)

for _subject in PROFILES:
    PROFILES[_subject] = (*PROFILES[_subject], "process_graph", "process_cycle", "scene")
for _subject in ("Mathematik", "Physik", "Technik"):
    PROFILES[_subject] = (*PROFILES[_subject], "function_curve")
PICTURE_WORDS = {
    "rouge",
    "rot",
    "bleu",
    "blau",
    "vert",
    "grün",
    "jaune",
    "gelb",
    "sonne",
    "sol",
    "soleil",
    "sun",
    "mond",
    "moon",
    "luna",
    "lune",
    "haus",
    "house",
    "maison",
    "casa",
    "buch",
    "book",
    "livre",
    "libro",
    "katze",
    "cat",
    "chat",
    "gato",
    "tisch",
    "table",
    "mesa",
}


class Bounded(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


class SourceImageRegion(Bounded):
    """A crop of original pixels, never a generated drawing or vector path."""
    left: int = Field(ge=0, le=1000, strict=True)
    top: int = Field(ge=0, le=1000, strict=True)
    right: int = Field(ge=0, le=1000, strict=True)
    bottom: int = Field(ge=0, le=1000, strict=True)

    @model_validator(mode="after")
    def nonempty(self):
        if self.right - self.left < 10 or self.bottom - self.top < 10:
            raise ValueError("Der Fotoausschnitt muss eine erkennbare Fläche umfassen.")
        return self


class SourceBlock(Bounded):
    kind: Literal["heading", "paragraph", "list", "formula", "table", "diagram_text", "code"]
    text: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(min_length=1, max_length=12000, pattern=r"\S")
    purpose: Literal["unknown", "translation", "inflection", "rule", "example", "diagram", "metadata"] = "unknown"
    image_region: SourceImageRegion | None = Field(default=None,
        description="Nur bei diagram_text: Bereich der sichtbaren Originalabbildung einschließlich Beschriftungen; Bildkoordinaten links/oben/rechts/unten von0bis1000, sonst null.")

    @model_validator(mode="after")
    def literal_figure(self):
        if self.image_region and self.kind != "diagram_text":
            raise ValueError("Ein Fotoausschnitt gehört ausschließlich zu einer sichtbaren Abbildung.")
        return self


class Connection(Bounded):
    start: int = Field(ge=0, le=15)
    end: int = Field(ge=0, le=15)
    relation: Literal["next", "food_to_eater", "branch", "connection"]


class SentenceMark(Bounded):
    index: int = Field(ge=0, le=15)
    role: Literal["subject", "predicate"]


class Graphic(Bounded):
    kind: Literal[
        "fraction",
        "triangle",
        "sentence",
        "speech",
        "forms",
        "timeline",
        "picture_words",
        "plant",
        "food_chain",
        "compass",
        "position",
        "water_cycle",
        "perspectives",
        "reflection",
        "circuit",
        "particles",
        "filtration",
        "bar_chart",
        "statements",
        "flowchart",
        "place_values",
        "movement",
        "pattern",
        "colour_wheel",
        "layers",
        "mindmap",
        "flashcard",
        "notes",
        "keyboard",
        "traditions",
        "senses",
        "seasons",
        "fairplay",
        "gears",
        "forces",
        "money",
        "function_graph", "data_plot", "cell", "molecule", "logic_table", "circuit_network", "technical_drawing", "function_curve", "process_graph", "process_cycle",
        "scene",
    ]
    title: str = Field(min_length=1, max_length=100)
    disclosure: Literal["given", "hint1", "hint2", "hint3", "solution"]
    source_excerpt: str = Field(
        min_length=3,
        max_length=500,
        description="Wörtlicher Beleg aus bestätigtem Stoff oder aus der Aufgabe für ausdrücklich gegebene Rechenzahlen.",
    )
    labels: list[Annotated[str, Field(min_length=1, max_length=160)]] = Field(max_length=16)
    numbers: list[Annotated[float, Field(ge=-10000, le=10000)]] = Field(max_length=16)
    connections: list[Connection] = Field(max_length=20)
    marks: list[SentenceMark] = Field(default_factory=list, max_length=8)
    unit: Literal["", "cm", "m", "cm²", "m²", "°", "€", "Schläge", "mm"]
    variant: Literal[
        "",
        "open",
        "closed",
        "solid",
        "liquid",
        "gas",
        "pull",
        "push",
        "RYB",
        "RGB",
        "centuries",
        "calendar",
        "quarters",
        "whole",
        "half",
        "quarter",
        "shape",
        "position",
        "classification",
        "above",
        "below",
        "beside",
        "clockwise",
        "counterclockwise",
        "roots",
        "pollination",
        "polynomial2", "scatter", "polyline", "plant_cell", "animal_cell",
        "water", "carbon_dioxide", "methane", "ethanol", "and_gate", "or_gate", "not_gate",
        "series", "parallel", "center_hole",
        "sine", "cosine", "exponential", "logarithm", "square_root", "reciprocal", "cubic", "absolute",
    ]

    scene: learning_scenes.SceneV1 | None = None

    @model_validator(mode="after")
    def coherent(self):
        n, labels = self.numbers, self.labels
        if self.kind == "scene":
            if self.scene is None or not labels or n or self.connections or self.marks or self.unit or self.variant:
                raise ValueError("Lernszene benötigt Szenendaten und Textalternative, keine fachfremden Grafikparameter.")
        elif self.scene is not None:
            raise ValueError("Szenendaten gehören ausschließlich zu kind scene.")
        if self.kind in science_graphics.KINDS:
            science_graphics.validate(self, {}, [self.source_excerpt])
        if self.variant in ("roots", "pollination") and self.disclosure != "solution":
            raise ValueError("Diese erklärenden Funktionsschemata dürfen keine Antwort vorwegnehmen.")
        if self.variant == "roots" and self.kind != "plant":
            raise ValueError("Wurzelfunktion benötigt das Pflanzenmodell.")
        if self.variant == "pollination" and (self.kind != "forms" or len(labels) != 2):
            raise ValueError("Bestäubung und Befruchtung sind zwei getrennte Erklärungsschritte.")
        if self.marks and (
            self.kind != "sentence" or self.disclosure == "given" or any(m.index >= len(labels) for m in self.marks)
        ):
            raise ValueError(
                "Satzmarkierungen nur an vorhandenen Bausteinen nach ausdrücklich geöffneter Hilfe oder Lösung."
            )
        numeric_kinds = {
            "fraction",
            "triangle",
            "reflection",
            "notes",
            "bar_chart",
            "place_values",
            "money",
            "timeline", "function_graph", "data_plot", "technical_drawing",
        }
        if n and self.kind not in numeric_kinds:
            raise ValueError("Dieser Grafiktyp hat keine Zahlenparameter.")
        if self.kind == "position" and (self.variant not in ("above", "below", "beside") or labels):
            raise ValueError(
                "Positionsmodell braucht eine eindeutige Lage des Balls am Tisch; keine umgedeuteten Beschriftungen."
            )
        if self.kind == "layers" and len(labels) != 3:
            raise ValueError("Bildebenen brauchen Vorder-, Mittel- und Hintergrund.")
        if self.kind == "pattern" and (
            len(labels) > 10 or any(v.casefold() not in ("kreis", "dreieck", "quadrat") for v in labels)
        ):
            raise ValueError("Dieses Formmuster unterstützt Kreis, Dreieck und Quadrat.")
        if self.kind == "notes" and len(n) > 6:
            raise ValueError("Höchstens sechs Notenwerte pro Skizze.")
        if self.kind == "picture_words" and len(labels) > 5:
            raise ValueError("Höchstens fünf Wortbilder pro Darstellung.")
        if self.kind == "picture_words" and any(
            re.sub(r"^(?:el|la|un|une|der|die|das)\s+", "", value.casefold()) not in PICTURE_WORDS for value in labels
        ):
            raise ValueError("Für dieses Wort ist noch kein passendes Bildsymbol vorhanden; verwende eine Wortliste.")
        if self.kind == "mindmap" and (
            len(labels) < 2
            or len(self.connections) != len(labels) - 1
            or {(e.start, e.end, e.relation) for e in self.connections}
            != {(0, i, "branch") for i in range(1, len(labels))}
        ):
            raise ValueError("Mindmap-Äste müssen eindeutig am Hauptthema hängen.")
        if self.kind == "flowchart" and len(labels) != 5:
            raise ValueError("Dieser erste Ablauf unterstützt Start, Eingabe, Verarbeitung, Ausgabe, Ende.")
        if self.kind == "gears" and self.variant not in ("clockwise", "counterclockwise"):
            raise ValueError("Die vorgegebene Drehrichtung des ersten Zahnrads fehlt.")
        if any(not math.isfinite(value) for value in n):
            raise ValueError("Nicht endliche Grafikzahl.")
        if any(edge.start == edge.end or max(edge.start, edge.end) >= len(labels) for edge in self.connections):
            raise ValueError("Grafikverbindung ohne verschiedene gültige Knoten.")
        if len({(e.start, e.end, e.relation) for e in self.connections}) != len(self.connections):
            raise ValueError("Doppelte Grafikverbindung.")
        if self.kind == "fraction" and not (
            len(n) == 2 and all(x == int(x) for x in n) and 0 <= n[0] <= n[1] <= 24 and n[1] > 0
        ):
            raise ValueError("Bruchmodell braucht Zähler und positiven Nenner bis24.")
        if self.kind == "triangle" and not (len(n) == 2 and all(x > 0 for x in n) and self.unit in ("cm", "m")):
            raise ValueError("Dreieck braucht Grundseite, senkrechte Höhe und Längeneinheit.")
        if self.kind == "reflection" and not (len(n) == 1 and 0 < n[0] < 90 and self.unit == "°"):
            raise ValueError("Reflexionswinkel wird zum Lot mit0<α<90 gemessen.")
        if self.kind == "circuit" and self.variant not in ("open", "closed"):
            raise ValueError("Schalterzustand fehlt.")
        if self.kind == "particles" and self.variant not in ("solid", "liquid", "gas"):
            raise ValueError("Teilchenzustand fehlt.")
        if self.kind == "colour_wheel" and self.variant not in ("RYB", "RGB"):
            raise ValueError("Farbmodell muss benannt werden.")
        if self.kind == "notes" and (
            self.variant != "quarters" or not n or any(x not in (1, 2, 4) for x in n) or self.unit != "Schläge"
        ):
            raise ValueError("Notenwerte nur in Viertelschlägen mit1/2/4.")
        if self.kind == "forces" and self.variant not in ("pull", "push"):
            raise ValueError("Zug oder Druck muss bestimmt sein.")
        if self.kind == "bar_chart" and (len(n) != len(labels) or not n or any(x < 0 for x in n)):
            raise ValueError("Balken brauchen je Kategorie einen nicht negativen Wert; Achse beginnt bei0.")
        if self.kind == "place_values" and (not n or len(n) > 8 or any(x not in (0, 1) for x in n)):
            raise ValueError("Binärtafel enthält ausschließlich0/1, höchstens8Stellen.")
        if self.kind == "timeline":
            if self.variant == "centuries" and (
                len(n) != 2 or n[0] < 1 or n[1] < n[0] or n[1] > 3000 or any(x != int(x) for x in n)
            ):
                raise ValueError(
                    "Jahrhundert-Zeitleiste braucht geordnete Grenzen von Jahr1 bis höchstens Jahr3000; es gibt kein Jahr0."
                )
            if self.variant not in ("centuries", "calendar"):
                raise ValueError("Zeitachsenart fehlt.")
        if self.kind == "food_chain" and (
            len(labels) < 2
            or len(self.connections) != len(labels) - 1
            or any((e.start, e.end, e.relation) != (i, i + 1, "food_to_eater") for i, e in enumerate(self.connections))
        ):
            raise ValueError("Nahrungspfeile zeigen ausschließlich von Nahrung zum Fresser.")
        if self.kind == "gears" and not 2 <= len(labels) <= 5:
            raise ValueError("Zwei bis fünf direkt gekoppelte Zahnräder erforderlich.")
        if (
            self.kind
            in (
                "forms",
                "sentence",
                "speech",
                "picture_words",
                "plant",
                "water_cycle",
                "perspectives",
                "statements",
                "flowchart",
                "movement",
                "pattern",
                "layers",
                "mindmap",
                "flashcard",
                "traditions",
                "senses",
                "seasons",
                "fairplay",
                "money",
            )
            and not labels
        ):
            raise ValueError("Beschriftungen fehlen.")
        if self.kind == "money" and (self.unit != "€" or len(n) != len(labels)):
            raise ValueError("Geldtabelle braucht zu jeder Zeile einen Euro-Betrag.")
        if self.kind == "keyboard" and labels and labels != ["C", "D", "E", "F", "G", "A", "H", "C"]:
            raise ValueError("Deutsche weiße Tasten heißen C D E F G A H C.")
        if self.kind == "plant" and len(labels) != 4:
            raise ValueError("Pflanzenmodell: Blüte, Blatt, Stängel und Wurzel in dieser Reihenfolge.")
        if self.kind == "senses" and len(labels) > 5:
            raise ValueError("Dieses Modell zeigt die fünf behandelten Sinne, keine vollständige Sinnesklassifikation.")
        return self


class Presentation(Bounded):
    version: Literal[1]
    evidence_kind: Literal["knowledge", "application", "reflection", "creative", "self_report", "movement"]
    blocks: list[Graphic] = Field(min_length=1, max_length=4)


RULES = """\nFachdarstellung presentation ist optional (sonst null), version1. Verwende nur bereitgestellte graphic_kinds.
Bei ausdrücklich belegtem Pflanzenaufbau plant verwenden. Wurzelaufnahme und Halt können mit variant roots erklärt werden.
Bestäubung und Befruchtung als zwei getrennte Schritte mit forms/variant pollination zeigen, nur mit wörtlich belegten Beschriftungen und disclosure solution.
Satzmarkierungen marks geben Bausteinindex und ausdrücklich belegte Subjekt-/Prädikatrolle an; nur hint/solution, nie als vorweggenommene Lösung.
Zahnrad-variant nennt die ausdrücklich vorgegebene Anfangsdrehrichtung clockwise/counterclockwise.
Keine SVG/HTML/Bilder oder freien Koordinaten; scene verwendet ausschließlich lokale Layoutplätze. Grafik nur wenn sie das konkrete Lernziel erklärt; keine Dekoration.
source_excerpt muss wörtlich im bestätigten Stoff stehen, bei neuen Rechenzahlen in der Aufgabenstellung.
labels und Zahlen ausschließlich aus diesem Beleg und ausdrücklich gegebenen Werten. Kein geheimes Ergebnis in einer gegebenen Grafik.
disclosure given ist vor der Antwort sichtbar; hint1/2/3 erst nach jeweiliger Hilfe, solution erst nach Abschluss der Aufgabe.
Vollständige Rückseiten, richtige Zuordnungspaare, Zielwort oder Rechenergebnis gehören in solution, nicht in given.
Bei type match erklärende Grafiken ausschließlich ab hint1/hint2/hint3/solution ergänzen, nie given.
Nahrungspfeile: Nahrung→Fresser. Reflexion: beide Winkel zum Lot, nicht zum Spiegel. Senkrechte Dreieckshöhe und rechte Winkel beachten.
Jahrhundert1=1–100, kein Jahr0. Schaltplan: Schalter offen trennt den Stromkreis; geschlossen verbindet.
Notenwerte werden in Viertelschlägen benannt, deutsche Klaviertasten C D E F G A H C. RYB und RGB unterscheiden.
Physische Ausführung, Gefühle, Glauben und kreative Ideen nicht als eindeutig richtige Kompetenz messen: evidence_kind passend setzen;
solche Reflexionsaufgaben ausschließlich freie Texteingabe, Bewertung offen. Historische/religiöse Schemata als vereinfachte Beispiele einordnen.
"""


def rules_for(subjects):
    allowed = {kind for subject in subjects for kind in PROFILES.get(subject, ())}
    return RULES + science_graphics.rules_for(allowed) + (learning_scenes.RULES if "scene" in allowed else "")


def generation_subjects(payload):
    """Use the requested scope first, otherwise the confirmed source's subject."""
    groups = payload.get("selected_groups") or []
    if groups:
        values = [group.get("subject") for group in groups]
    elif payload.get("required_subject"):
        values = [payload["required_subject"]]
    elif (payload.get("material") or {}).get("subject"):
        values = [payload["material"]["subject"]]
    elif (payload.get("goal") or {}).get("subject"):
        values = [payload["goal"]["subject"]]
    else:
        values = [material.get("subject") for material in payload.get("materials", [])]
    return list(dict.fromkeys(value for value in values if isinstance(value, str) and value))


def generation_context(subjects, *, schema=None, compact_matching=False):
    from .presentation_capabilities import context

    return context(subjects, PROFILES, schema=schema, compact_matching=compact_matching, symbol_words=PICTURE_WORDS)


def _contains(haystack, needle):
    return " ".join(needle.casefold().split()) in " ".join(haystack.casefold().split())


def validate_question(presentation, question, sources, allowed_kinds):
    if not presentation:
        return
    p = Presentation.model_validate(presentation)
    for block in p.blocks:
        if block.kind not in allowed_kinds:
            raise ValueError("Grafik gehört nicht zum ausgewählten Fachprofil.")
        if not any(_contains(text, block.source_excerpt) for text in [*sources, question["prompt"]]):
            raise ValueError("Grafik ohne wörtlichen Quellenbeleg.")
        if block.kind in science_graphics.KINDS:
            science_graphics.validate(block, question, sources)
        if block.kind == "scene":
            learning_scenes.validate(block, question, sources)
        # Numeric values are given data, not newly invented source facts.
        quoted = (block.source_excerpt + " " + question["prompt"]).replace("−", "-")
        values_to_check = block.numbers
        if block.kind in ("function_graph", "function_curve"):
            # Coefficients were checked against the complete parsed polynomial;
            # an implicit coefficient1 or0 need not appear as a literal digit.
            values_to_check = []
        elif block.kind == "place_values" and re.search(
            r"(?<!\d)" + "".join(str(int(n)) for n in block.numbers) + r"(?!\d)", quoted
        ):
            values_to_check = []
        for number in values_to_check:
            token = str(int(number)) if number == int(number) else str(number)
            if not re.search(r"(?<![\d])" + re.escape(token).replace(r"\.", "[.,]") + r"(?![\d])", quoted):
                raise ValueError("Grafikzahl fehlt im Beleg oder in der Aufgabe.")
        if block.kind not in ("function_graph", "function_curve") and any(not _contains(block.source_excerpt + " " + question["prompt"], label) for label in block.labels):
            raise ValueError("Grafikbeschriftung fehlt im wörtlichen Beleg.")
        if block.kind == "plant" and [v.casefold() for v in block.labels] not in (
            ["blüte", "blatt", "stängel", "wurzel"],
            ["blüte", "blatt", "stengel", "wurzel"],
        ):
            raise ValueError("Beschriftung passt nicht zur festen Pflanzenposition.")
        if block.kind == "seasons" and [v.casefold() for v in block.labels] != [
            "frühling",
            "sommer",
            "herbst",
            "winter",
        ]:
            raise ValueError("Jahreszeitenfolge ist falsch.")
        if block.kind == "water_cycle" and not (
            len(block.labels) == 4
            and all(
                root in label.casefold()
                for root, label in zip(("verdunst", "kondens", "niederschlag", "samml"), block.labels)
            )
        ):
            raise ValueError("Wasserkreislauf braucht Verdunstung, Kondensation, Niederschlag, Sammlung.")
        for mark in block.marks:
            term = "Subjekt" if mark.role == "subject" else "Prädikat"
            label = re.escape(block.labels[mark.index])
            if not re.search(
                r"(?:" + term + r"\s*[:=]\s*" + label + r"|" + label + r"\s+(?:ist|=)\s+(?:das\s+)?" + term + ")",
                block.source_excerpt,
                re.I,
            ):
                raise ValueError("Satzmarkierung hat keinen eindeutigen Rollenbeleg.")
        if block.kind == "position":
            position = {"above": "auf", "below": "unter", "beside": "neben"}[block.variant]
            if not re.search(r"Ball[^.!?]{0,50}\b" + position + r"\b[^.!?]{0,30}Tisch", quoted, re.I):
                raise ValueError("Die Lage des Balls ist nicht im Beleg beschrieben.")
        if block.kind == "gears":
            direction = "gegen den Uhrzeigersinn" if block.variant == "counterclockwise" else "im Uhrzeigersinn"
            if direction.casefold() not in quoted.casefold():
                raise ValueError("Absolute Zahnrad-Drehrichtung fehlt im Beleg oder in der gegebenen Aufgabe.")
        if block.kind == "food_chain":
            if not all(
                science_graphics.has_literal_arrow(block.source_excerpt, a, b, ignore_case=True)
                for a, b in zip(block.labels, block.labels[1:])
            ):
                raise ValueError("Nahrungskette ohne belegte Pfeilrichtung.")
        if block.disclosure == "given":
            if question.get("type") == "match":
                # A single label/value, arrow or layout can reveal one private
                # pair even when the complete semicolon answer is absent.
                # This validates new output; stored snapshots are not changed.
                raise ValueError("Gegebene Grafik darf kein richtiges Zuordnungspaar vorwegnehmen.")
            answer = question.get("answer", "").strip()
            caption = " ".join([block.title, *block.labels])
            if len(answer) > 2 and _contains(caption, answer) and not _contains(question["prompt"], answer):
                raise ValueError("Gegebene Grafik verrät die Antwort.")
        if p.evidence_kind in ("reflection", "creative", "self_report", "movement") and question["type"] != "short":
            raise ValueError("Offene Reflexion oder Bewegung wird nicht als eindeutige Auswahl geprüft.")


def validate_output(data, payload, *, bounded_matching=False):
    units = data.get("units") or ([data["next_unit"]] if data.get("next_unit") else [data])
    material_items = payload.get("materials") or [payload.get("material") or {}]
    material_items = [item for item in material_items if isinstance(item, dict)]
    for unit in units:
        subject = unit.get("subject") or payload.get("required_subject")
        group = unit.get("group_id")
        sources = [m.get("content", "") for m in material_items if group is None or m.get("group_id") == group]
        for question in unit.get("questions", []):
            validate_question(question.get("presentation"), question, sources, PROFILES.get(subject, ()))
            if bounded_matching:
                learning_scenes.validate_matching(question, sources)


def public_presentation(value, *, closed=False, hints=0):
    if not value:
        return None
    p = Presentation.model_validate(value)
    allowed = {"given"} | {f"hint{i}" for i in range(1, min(3, hints) + 1)} | ({"solution"} if closed else set())
    return {
        "version": 1,
        "evidence_kind": p.evidence_kind,
        "blocks": [
            {**{k: v for k, v in b.model_dump(exclude={"source_excerpt", "scene"}).items()},
             **({"scene": learning_scenes.public_scene(b.scene)} if b.scene is not None else {})}
            for b in p.blocks
            if b.disclosure in allowed
        ],
    }


def legacy_presentation(question, sources=None):
    """Finite legacy diagrams: given geometry or source-bound, gated biology explanation."""
    prompt = question["prompt"]
    if not re.search(r"Dreieck", prompt, re.I):
        explanation = question.get("explanation", "")
        context = prompt + "\n" + explanation
        evidence = "\n".join(sources or [])
        if (re.search(r"wurzel", context, re.I) and re.search(r"wasser|veranker|halt", context, re.I)
                and all(re.search(term, evidence, re.I) for term in (r"wurzel", r"wasser", r"veranker|halt"))):
            block = Graphic(kind="plant", title="Erklärschema: Die Wurzel", disclosure="solution",
                source_excerpt=explanation[:500], labels=["Blüte", "Blatt", "Stängel", "Wurzel"],
                numbers=[], connections=[], unit="", variant="roots")
        elif (re.search(r"bestäub|befrucht", context, re.I) and all(re.search(term, evidence, re.I)
                 for term in (r"bestäub", r"befrucht", r"pollen", r"narbe", r"eizelle"))):
            block = Graphic(kind="forms", title="Erklärschema: Von der Bestäubung zur Befruchtung", disclosure="solution",
                source_excerpt=explanation[:500], labels=["Bestäubung: Pollen gelangt auf die Narbe.",
                    "Befruchtung: Eine männliche Keimzelle verschmilzt mit der Eizelle."],
                numbers=[], connections=[Connection(start=0, end=1, relation="next")], unit="", variant="pollination")
        else:
            return None
        return Presentation(version=1, evidence_kind="knowledge", blocks=[block]).model_dump()
    base = re.search(r"\bg\s*=\s*(\d+(?:[.,]\d+)?)\s*(cm|m)\b", prompt)
    height = re.search(r"\bh\s*=\s*(\d+(?:[.,]\d+)?)\s*(cm|m)\b", prompt)
    if not base or not height or base[2] != height[2]:
        return None
    block = Graphic(
        kind="triangle",
        title="Grundseite und senkrechte Höhe",
        disclosure="given",
        source_excerpt=prompt[:500],
        labels=[],
        numbers=[float(base[1].replace(",", ".")), float(height[1].replace(",", "."))],
        connections=[],
        unit=base[2],
        variant="",
    )
    return Presentation(version=1, evidence_kind="application", blocks=[block]).model_dump()


def open_learning_unit(unit):
    return bool(unit.questions) and all(
        (q.get("presentation") or {}).get("evidence_kind") in ("reflection", "creative", "self_report", "movement")
        for q in unit.questions
    )


def bind_graphic_schema(schema, subjects):
    """Bind selected subject renderers and declarative scenes in the same private request."""
    allowed = sorted({kind for subject in subjects for kind in PROFILES.get(subject, ())})
    graphic = schema.get('$defs', {}).get('Graphic')
    if allowed and graphic:
        graphic['properties']['kind']['enum'] = allowed
    return schema
