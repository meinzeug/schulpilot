"""A local text comparison of complete, literally source-attested word orders."""

import re
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .learning_scenes import safe_text

Identifier = Annotated[str, Field(min_length=1, max_length=48, pattern=r"^[A-Za-z0-9_-]+$")]


class TextSegment(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    id: Identifier
    text: str = Field(min_length=1, max_length=160)

    @model_validator(mode="after")
    def plain(self):
        safe_text(self.text)
        return self


class TextVariant(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    id: Identifier
    order: list[Identifier] = Field(min_length=2, max_length=8)
    source_excerpt: str = Field(min_length=3, max_length=500)


class TextProbeV1(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: Literal[1]
    segments: list[TextSegment] = Field(min_length=2, max_length=8)
    variants: list[TextVariant] = Field(min_length=2, max_length=4)

    @field_validator("version", mode="before")
    @classmethod
    def exact_version(cls, value):
        if type(value) is not int:
            raise ValueError("Textprobenversion muss die ganze Zahl1 sein.")
        return value

    @model_validator(mode="after")
    def complete_orders(self):
        ids = {segment.id for segment in self.segments}
        if len(ids) != len(self.segments) or len({variant.id for variant in self.variants}) != len(self.variants):
            raise ValueError("Textproben brauchen eindeutige Gruppen- und Varianten-IDs.")
        if len({tuple(variant.order) for variant in self.variants}) != len(self.variants):
            raise ValueError("Textproben vergleichen verschiedene belegte Reihenfolgen.")
        for variant in self.variants:
            if len(variant.order) != len(ids) or set(variant.order) != ids:
                raise ValueError("Jede Textprobe enthält alle Textgruppen genau einmal.")
        texts = {segment.id: segment.text for segment in self.segments}
        if len({" ".join(texts[key] for key in variant.order) for variant in self.variants}) != len(self.variants):
            raise ValueError("Die Textproben müssen verschiedene vollständige Texte zeigen.")
        return self


def normalized(value):
    return " ".join(value.split())


def validate(block, sources):
    probe = block.text_probe
    segments = {segment.id: segment.text for segment in probe.segments}
    for variant in probe.variants:
        quote = normalized(variant.source_excerpt)
        if not any(quote in normalized(source) for source in sources):
            raise ValueError("Textreihenfolge ohne einzelnen wörtlichen Originalbeleg.")
        text = normalized(" ".join(segments[key] for key in variant.order))
        pattern = r"(?<!\w)" + re.escape(text) + r"(?!\w)"
        if not re.search(pattern, quote) or not any(
            quote in normalized(source) and re.search(pattern, normalized(source)) for source in sources
        ):
            raise ValueError("Vollständige Textreihenfolge fehlt im wörtlichen Beleg.")
    safe_text(block.title)
    texts = [*block.labels]
    if block.title not in ("Textprobe", "Textvergleich", "Textgruppen"):
        texts.append(block.title)
    for label in texts:
        safe_text(label)
        pattern = r"(?<!\w)" + re.escape(normalized(label)) + r"(?!\w)"
        if not any(re.search(pattern, normalized(source)) for source in sources):
            raise ValueError("Textprobenbeschriftung ohne Originalbeleg; keine eigenen Grammatikurteile.")


def public_probe(probe):
    value = probe.model_dump()
    for variant in value["variants"]:
        variant.pop("source_excerpt")
    return value


RULES = """\nTEXTVERGLEICH kind=text_probe nur für zwei bis vier ausdrücklich im Originalstoff vorhandene Wort-/Textreihenfolgen.
text_probe={version:1,segments:[{id,text}],variants:[{id,order,source_excerpt}]};2bis8stabile Textgruppen, jede Variante enthält ALLE Gruppen genau einmal.
Jeder vollständig durch Leerzeichen zusammengesetzte Text muss wörtlich im eigenen source_excerpt EINER Originalquelle stehen.
Keine erfundenen falschen Gegenbeispiele, Grammatikurteile, frei umstellbaren Wörter oder richtige/falsche Markierung; die Lupe ändert nur die Ansicht.
Nur hint1/hint2/hint3/solution, nie given. title ist Textprobe/Textvergleich/Textgruppen oder ein wörtlicher Originalausdruck; labels ausschließlich Originalausdrücke, kein Urteil aus einem selbst erzeugten Prompt. Alle anderen Grafikparameter leer.
"""
