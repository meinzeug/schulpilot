"""Source-bound, declarative learning scenes rendered locally by the app.

Slots describe schematic layout, never measurements or executable model code.
Each complete scene belongs to one existing disclosure stage. Quotes remain
private; no client receives later hint/solution frames before that stage opens.
"""

import re
import unicodedata
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Identifier = Annotated[str, Field(min_length=1, max_length=48, pattern=r"^[A-Za-z0-9_-]+$")]
_UNSAFE = re.compile(
    r"https?://|www\.|(?:data|javascript):|<[^>]+>|```|__import__|\b(?:eval|exec)\s*\(|\bfunction\s*\(|=>",
    re.I,
)


def safe_text(value):
    if _UNSAFE.search(value):
        raise ValueError("Lernszenen enthalten nur Beschriftungen, keine Links, Markup oder ausführbaren Code.")
    return value


class ScenePart(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


class SceneObject(ScenePart):
    id: Identifier
    label: str = Field(min_length=1, max_length=160)
    shape: Literal["box", "circle", "triangle", "diamond"]
    tone: Literal["neutral", "accent", "secondary"]

    @model_validator(mode="after")
    def text_only(self):
        safe_text(self.label)
        return self


class ScenePlacement(ScenePart):
    object_id: Identifier
    slot: int = Field(ge=0, le=11, strict=True)


class SceneEdge(ScenePart):
    start: Identifier
    end: Identifier
    label: str = Field(max_length=80)

    @model_validator(mode="after")
    def directed_text(self):
        if self.start == self.end:
            raise ValueError("Szenenpfeile verbinden verschiedene Objekte.")
        safe_text(self.label)
        return self


class SceneStep(ScenePart):
    caption: str = Field(min_length=1, max_length=500)
    source_excerpt: str = Field(min_length=3, max_length=500)
    placements: list[ScenePlacement] = Field(min_length=1, max_length=12)
    highlight: list[Identifier] = Field(max_length=12)
    edges: list[SceneEdge] = Field(max_length=24)

    @model_validator(mode="after")
    def unique_references(self):
        safe_text(self.caption)
        ids = [p.object_id for p in self.placements]
        if len(set(ids)) != len(ids) or len({p.slot for p in self.placements}) != len(ids):
            raise ValueError("Szenenobjekte und Plätze dürfen pro Schritt nicht doppelt vorkommen.")
        if len(set(self.highlight)) != len(self.highlight):
            raise ValueError("Doppelte Hervorhebung in der Lernszene.")
        if len({(e.start, e.end) for e in self.edges}) != len(self.edges):
            raise ValueError("Doppelte Pfeile in der Lernszene.")
        return self


class SceneV1(ScenePart):
    version: Literal[1]
    layout: Literal["grid", "row", "cycle"]
    objects: list[SceneObject] = Field(min_length=1, max_length=12)
    steps: list[SceneStep] = Field(min_length=1, max_length=8)
    transition_ms: int = Field(ge=0, le=800, strict=True)

    @field_validator("version", mode="before")
    @classmethod
    def integer_version(cls, value):
        if type(value) is not int:
            raise ValueError("Szenenversion muss die ganze Zahl1 sein.")
        return value

    @model_validator(mode="after")
    def complete_steps(self):
        ids = {obj.id for obj in self.objects}
        if len(ids) != len(self.objects):
            raise ValueError("Szenenobjekte benötigen eindeutige IDs.")
        for step in self.steps:
            if {p.object_id for p in step.placements} != ids:
                raise ValueError("Jeder Szenenschritt platziert alle Objekte genau einmal.")
            if not set(step.highlight) <= ids or any(e.start not in ids or e.end not in ids for e in step.edges):
                raise ValueError("Szenenschritt verweist auf ein unbekanntes Objekt.")
        return self


def _contains(text, value):
    return " ".join(value.casefold().split()) in " ".join(text.casefold().split())


def _mentions(text, value):
    normalized = " ".join(text.casefold().split())
    token = " ".join(value.casefold().split())
    return bool(token and re.search(r"(?<!\w)" + re.escape(token) + r"(?!\w)", normalized))


def display_texts(block):
    """Every public text in every frame, including the old client's fallback."""
    scene = block.scene
    return [block.title, *block.labels, *[obj.id for obj in scene.objects], *[obj.label for obj in scene.objects],
            *[step.caption for step in scene.steps], *[edge.label for step in scene.steps for edge in step.edges]]


def validate(block, question, sources):
    """Bind labels/steps/relations to literal confirmed source evidence.

    Prompt values can illustrate an explicitly given example. A factual arrow
    needs a confirmed A→B (or A->B) source, not a relationship invented in the
    generated prompt. Slots/timing are display parameters and are not facts.
    """
    scene = block.scene
    prompt = question.get("prompt", "")
    evidence = [*sources, prompt]
    scene_quotes = [block.source_excerpt, *[step.source_excerpt for step in scene.steps]]
    quoted = "\n".join([*scene_quotes, prompt])
    for value in [block.title, *block.labels, *[obj.label for obj in scene.objects]]:
        safe_text(value)
        if not _mentions(quoted, value):
            raise ValueError("Szenenbeschriftung fehlt im wörtlichen Beleg.")
    labels = {obj.id: obj.label for obj in scene.objects}
    for step in scene.steps:
        if not any(_contains(text, step.source_excerpt) for text in evidence):
            raise ValueError("Szenenschritt ohne wörtlichen Quellenbeleg.")
        if not _mentions(step.source_excerpt, step.caption):
            raise ValueError("Die Szenenbeschreibung muss im Schrittbeleg stehen.")
        relation_source = " ".join(step.source_excerpt.casefold().split()).replace("->", "→")
        for edge in step.edges:
            if not any(_contains(text, step.source_excerpt) for text in sources):
                raise ValueError("Szenenpfeile brauchen bestätigten Quellenstoff.")
            start = re.escape(" ".join(labels[edge.start].casefold().split()))
            end = re.escape(" ".join(labels[edge.end].casefold().split()))
            relation = r"(?<!\w)" + start + r"\s*→\s*" + end + r"(?!\w)"
            if not re.search(relation, relation_source):
                raise ValueError("Szenenpfeil hat keine belegte Richtung zwischen seinen Beschriftungen.")
            if edge.label and not _mentions(step.source_excerpt, edge.label):
                raise ValueError("Pfeilbeschriftung fehlt im Schrittbeleg.")
    if block.disclosure == "given":
        if question.get("type") == "match":
            # Even an unlabelled slot arrangement can disclose the private
            # pair/order. The answer UI is independent; explanatory scenes for
            # matching therefore open only through the existing help stages.
            raise ValueError("Eine gegebene Lernszene darf kein richtiges Zuordnungspaar räumlich vorwegnehmen.")
        texts = display_texts(block)
        for answer in [question.get("answer", ""), *question.get("accepted", [])]:
            if answer and not _mentions(prompt, answer) and any(_mentions(text, answer) for text in texts):
                raise ValueError("Gegebene Lernszene verrät die Antwort in einem ihrer Schritte.")


def public_scene(scene):
    """Projection is called only after the whole block's disclosure is allowed."""
    value = scene.model_dump()
    for step in value["steps"]:
        step.pop("source_excerpt")
    return value


def validate_matching(question, sources):
    """Validate new bounded matching tasks, never reinterpret saved attempts.

    A pair needs an explicit, literal association in its own confirmed source.
    Merely finding both words somewhere on a page cannot prove the mapping.
    """
    if question.get("type") != "match":
        return
    options = question.get("options", [])
    if not 2 <= len(options) <= 4 or question.get("accepted"):
        raise ValueError("Neue Zuordnungen benötigen zwei bis vier belegte Paare ohne Antwortvarianten.")

    def normalized(value):
        return " ".join(unicodedata.normalize("NFKC", value).casefold().split())

    source_texts = [normalized(text) for text in sources]
    prompt = normalized(question.get("prompt", ""))
    right_values, left_values = [], []
    for pair in options:
        if pair.count("|") != 1:
            raise ValueError("Zuordnung braucht eindeutig getrennte Begriffspaare.")
        left, right = pair.split("|")
        if not left or not right or left != left.strip() or right != right.strip() or ";" in pair:
            raise ValueError("Zuordnung enthält leere oder mehrdeutige Antwortteile.")
        left_values.append(left)
        right_values.append(right)
        pattern = (r"(?<!\w)" + re.escape(normalized(left)) + r"\s*(?:=|:|→|->|\|)\s*"
                   + re.escape(normalized(right)) + r"(?!\w)")
        if not any(re.search(pattern, text) for text in source_texts):
            raise ValueError("Zuordnungspaar ist nicht wörtlich im bestätigten Quellenstoff belegt.")
        if re.search(pattern, prompt):
            raise ValueError("Die Aufgabe darf die richtige Zuordnung nicht bereits im Prompt verraten.")
    if (len({normalized(v) for v in left_values}) != len(left_values)
        or len({normalized(v).replace(',', '.') for v in right_values}) != len(right_values)
        or question.get("answer") != ";".join(right_values)):
        raise ValueError("Zuordnung ist nicht eindeutig oder verändert die belegte Antwortreihenfolge.")


MATCH_RULES = """\nKleine Zuordnung (type match) ist erlaubt, wenn sie das konkrete Lernziel sinnvoll prüft.
Nur zwei bis vier eindeutige Paare und accepted=[]; jedes Paar steht im eigenen bestätigten Stoff wörtlich als
links = rechts, links: rechts, links → rechts, links -> rechts oder links | rechts. Bloßes Vorkommen beider Wörter genügt nicht.
options bleibt links|rechts, answer sind die rechten Werte in linker Originalreihenfolge mit Semikolon verbunden.
Keine Semikolons innerhalb eines Begriffes, keine unbelegten Paare oder ergänzten Sortierfolgen. Richtige Paarung nicht im Prompt verraten.
Keine zusätzliche Aufgabe oder Modellanfrage: Zuordnung nutzt einen der vorhandenen Aufgabenplätze; sonst choice/short verwenden.
"""


RULES = """\nscene: individuelle, neu zusammengesetzte lokale Vektorszene für den konkreten bestätigten Stoff.
Graphic.kind=scene, scene.version=1; bestehende labels als nichtleere Textalternative derselben Offenlegungsstufe.
numbers/connections/marks leer, unit/variant leer. Andere Grafiktypen haben scene=null.
scene.layout grid/row/cycle; 1bis12 objects mit eindeutiger id, belegtem label, shape box/circle/triangle/diamond und tone neutral/accent/secondary.
1bis8 steps, jeder mit wörtlichem source_excerpt und darin wörtlich enthaltener caption; alle Objekte exakt einmal platzieren,
eindeutige slots0bis11, highlight enthält nur vorhandene IDs; edges sind gerichtete Pfeile start/end/label (leer erlaubt), höchstens24.
Pfeile nur für ausdrücklich im bestätigten Stoff belegte LabelA→LabelB oder LabelA->LabelB, niemals aus erfundenem Prompt ableiten.
Titel, Objektlabels, Textalternative und Pfeiltexte sind wörtlich belegt. Positionen sind schematisch, keine Messwerte oder fachlichen Geometrien.
transition_ms0bis800; lokale Übergänge erklären nur die belegten Schritte, keine erfundene Simulation oder Messung.
Keine URLs, HTML/SVG, Skripte, freien Koordinaten, Pfade, Ausdrücke, ausführbarer Code oder neue Modellaufrufe.
Die GESAMTE Szene einschließlich aller Schritte/Objekte/Alternativtexte hat genau die disclosure des Blocks.
In given keine spätere Lösung, richtigen Paare oder Antwort in einem späteren Animationsschritt verstecken.
Bei type match öffnen erklärende scene-Blöcke erst ab hint1/hint2/hint3/solution; keine gegebene richtige räumliche Anordnung.
Für fachlich gemessene Geometrie, Funktionen, Schaltungen oder Molekülbindungen weiterhin das passende geprüfte Fachmodell verwenden;
eine Szene ist eine belegte schematische Erklärung, kein Ersatz für dessen mathematische Prüfung.
"""
