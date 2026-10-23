"""Source-bound multi-field answers over the existing single-attempt string wire."""

import json
import re
import unicodedata
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Identifier = Annotated[str, Field(min_length=1, max_length=48, pattern=r"^[A-Za-z0-9_-]+$")]


def normalized(value):
    return " ".join(unicodedata.normalize("NFC", value).split())


def canonical(fields):
    return json.dumps({"version": 1, "fields": fields}, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


class GroupedField(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    id: Identifier
    label: str = Field(min_length=1, max_length=160)
    kind: Literal["text", "select"]
    options: list[Annotated[str, Field(min_length=1, max_length=160)]] = Field(max_length=6)
    answer: str = Field(min_length=1, max_length=160)
    source_excerpt: str = Field(min_length=3, max_length=500)

    @model_validator(mode="after")
    def coherent(self):
        for value in (self.label, self.answer, self.source_excerpt, *self.options):
            if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
                raise ValueError("Feldtexte benötigen gültige Unicode-Zeichen.")
        if self.kind == "text" and self.options:
            raise ValueError("Freies Gruppenfeld hat keine Auswahloptionen.")
        if self.kind == "select" and (not 2 <= len(self.options) <= 6 or self.answer not in self.options):
            raise ValueError("Auswahlfeld benötigt zwei bis sechs Optionen und eine vorhandene Antwort.")
        if len({normalized(option) for option in self.options}) != len(self.options):
            raise ValueError("Mehrdeutige Auswahloptionen im Gruppenfeld.")
        return self


class FieldGroup(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: Literal[1]
    fields: list[GroupedField] = Field(min_length=2, max_length=4)

    @field_validator("version", mode="before")
    @classmethod
    def exact_version(cls, value):
        if type(value) is not int:
            raise ValueError("Feldversion muss die ganze Zahl1 sein.")
        return value

    @model_validator(mode="after")
    def unique_fields(self):
        if len({field.id for field in self.fields}) != len(self.fields):
            raise ValueError("Gruppenfelder brauchen eindeutige IDs.")
        if len(canonical({field.id: field.answer for field in self.fields})) > 600:
            raise ValueError("Die gemeinsame Musterantwort überschreitet das bestehende Antwortlimit.")
        return self



def requires_math_contract(prompt, group):
    """Do not bypass existing arithmetic/form checks with a literal field key."""
    from .checks import expanded_fraction, fraction_instruction

    group = FieldGroup.model_validate(group) if isinstance(group, dict) else group
    for text in [prompt, *[field.label for field in group.fields]]:
        if fraction_instruction(text) or expanded_fraction(text):
            return True
        command = unicodedata.normalize("NFC", text).casefold()
        if re.search(r"\b(?:berechne|rechne|errechne|addiere|subtrahiere|multipliziere|dividiere)\b", command):
            return True
        if re.search(r"\bwas\s+ist\b", command) and re.search(r"\d\s*[+−*/×·:-]\s*\d", command):
            return True
        if re.search(r"\d", command) and (
            re.search(r"\b(?:wie\s+viel|ergibt|ergebnis|summe|differenz|produkt|quotient|kürz\w*|erweiter\w*)\b", command)
            or re.search(r"=\s*(?:_{2,}|□|\?+)", command)
        ):
            return True
    return False


def _object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("Doppelte JSON-Schlüssel in der Feldantwort.")
        value[key] = item
    return value


def parse_answer(group, answer, *, partial=False):
    group = FieldGroup.model_validate(group) if isinstance(group, dict) else group
    if partial and not answer.strip():
        return {field.id: "" for field in group.fields}
    try:
        value = json.loads(answer, object_pairs_hook=_object)
    except (json.JSONDecodeError, TypeError, RecursionError):
        raise ValueError("Bitte die Felder als gemeinsame gültige Antwort senden.") from None
    if (not isinstance(value, dict) or set(value) != {"version", "fields"}
            or type(value["version"]) is not int or value["version"] != 1 or not isinstance(value["fields"], dict)):
        raise ValueError("Ungültige Version oder Struktur der Feldantwort.")
    expected = {field.id for field in group.fields}
    fields = value["fields"]
    if not set(fields) <= expected or (not partial and set(fields) != expected):
        raise ValueError("Die Feldantwort gehört nicht zu dieser Aufgabe.")
    if any(not isinstance(item, str) or len(item) > 160
           or any(0xD800 <= ord(character) <= 0xDFFF for character in item) for item in fields.values()):
        raise ValueError("Feldwerte sind Texte mit höchstens160Zeichen.")
    result = {field.id: fields.get(field.id, "") for field in group.fields}
    for field in group.fields:
        item = result[field.id]
        if not partial and not item.strip():
            raise ValueError("Bitte jedes Feld vor dem gemeinsamen Prüfen ausfüllen.")
        if field.kind == "select" and item and item not in field.options:
            raise ValueError("Bitte eine vorhandene Feldoption auswählen.")
    return result


def validate_question(question, sources):
    if question.get("type") != "grouped":
        return
    group = FieldGroup.model_validate(question["field_group"])
    if requires_math_contract(question["prompt"], group):
        raise ValueError("Rechen- und Bruchdarstellungsaufgaben benötigen ein bestehendes geprüftes Einzelantwortformat.")
    for field in group.fields:
        quote = normalized(field.source_excerpt)
        original = [normalized(source) for source in sources if quote in normalized(source)]
        if not original:
            raise ValueError("Gruppenfeld ohne einzelnen wörtlichen Originalbeleg.")
        label, answer = map(lambda item: re.escape(normalized(item)), (field.label, field.answer))
        pattern = r"(?<!\w)" + label + r"\s*(?:=|:|→|->)\s*" + answer + r"(?!\w)"
        if not re.search(pattern, quote) or not any(re.search(pattern, source) for source in original):
            raise ValueError("Feldlösung ist nicht ausdrücklich mit ihrer Beschriftung belegt.")
        for option in field.options:
            token = re.escape(normalized(option))
            if not any(re.search(r"(?<!\w)" + token + r"(?!\w)", source) for source in original):
                raise ValueError("Feldoption fehlt im zugehörigen bestätigten Material.")


def public_group(value):
    group = FieldGroup.model_validate(value)
    return {"version": 1, "fields": [field.model_dump(exclude={"answer", "source_excerpt"}) for field in group.fields]}


def evaluate(question, answer):
    group = FieldGroup.model_validate(question["field_group"])
    if requires_math_contract(question["prompt"], group):
        return {"version": 2, "outcome": "uncertain", "method": "unsupported_grouped_math_v1",
                "reason": "Diese Rechenaufgabe benötigt eine geprüfte Einzelantwort. Die Bewertung bleibt ungeklärt.",
                "parts": [{"id": field.id, "outcome": "uncertain"} for field in group.fields],
                "dimensions": {"content": "uncertain", "form": "not_requested"}}
    values = parse_answer(group, answer)
    parts = []
    for field in group.fields:
        outcome = ("correct" if normalized(values[field.id]) == normalized(field.answer)
                   else "incorrect" if field.kind == "select" else "uncertain")
        parts.append({"id": field.id, "outcome": outcome})
    outcome = ("incorrect" if any(part["outcome"] == "incorrect" for part in parts)
               else "uncertain" if any(part["outcome"] == "uncertain" for part in parts) else "correct")
    return {"version": 2, "outcome": outcome, "parts": parts, "method": "grouped_fields_v1",
            "reason": ("Alle Felder entsprechen den geprüften Belegen." if outcome == "correct"
                       else "Deine Feldantworten sind gespeichert. Offene Formulierungen bleiben ungeklärt."
                       if outcome == "uncertain" else "Mindestens eine Auswahl passt noch nicht zum belegten Zusammenhang."),
            "dimensions": {"content": outcome, "form": "not_requested"}}


RULES = """\nMEHRFELDAUFGABE type=grouped nur wenn question_types dies ausdrücklich zulässt:
field_group={version:1,fields:[{id,label,kind,options,answer,source_excerpt}]} mit2bis4stabilen Feldern.
kind=text hat options=[], kind=select hat2bis6verschiedene vorhandene Optionen. Optionen/Antworten je höchstens160Zeichen.
Jede Feldlösung braucht im Originalmaterial ausdrücklich label=answer oder label:answer oder label→answer, vollständig in EINEM wörtlichen source_excerpt.
Belege und Bewertung sind NFC-normalisiert, aber groß-/kleinschreibungsgetreu; CO/Co, X/x und Hochzahlen sind verschieden. Keine selbst erfundenen Grammatikurteile oder Rechenergebnisse; ohne ausdrücklichen Feldbeleg einen vorhandenen anderen Aufgabentyp wählen.
Äußere options/accepted=[]; äußere answer ist ein JSON-STRING {"version":1,"fields":{"id":"Wert"}}, exakt alle IDs, insgesamt höchstens600Zeichen.
Erkannte Rechen- und Bruchdarstellungsaufgaben einschließlich berechne/rechne/Kürzen/Erweitern bleiben im bestehenden geprüften Einzelantwortformat, nie grouped.
Alle Felder werden gemeinsam bewusst geprüft, ein Versuch; unbekannte freie Formulierungen bleiben offen. Keine korrekten Feldwerte in given-Grafiken zeigen.
"""
