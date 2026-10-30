"""Finite own teaching labs. No code, assets, coordinates or assessment."""

import hashlib
import json
import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class LabStrict(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    @model_validator(mode="before")
    @classmethod
    def integer_versions(cls, value):
        if isinstance(value, dict) and any(key in value and type(value[key]) is not int for key in ("version", "recipe_version")):
            raise ValueError("Laborversionen benötigen ganze Versionsnummern.")
        return value


class ForceParameters(LabStrict):
    mass_kg: float = Field(ge=0.5, le=10, strict=True)
    acceleration_m_s2: float = Field(ge=0, le=4, strict=True)


class SentenceParameters(LabStrict):
    example_id: Literal["mira_reads"]


class LabV1(LabStrict):
    version: Literal[1]
    recipe_id: Literal["physics.force_motion", "german.sentence_shift"]
    recipe_version: Literal[1]
    parameters: ForceParameters | SentenceParameters

    @model_validator(mode="after")
    def matches_recipe(self):
        if ((self.recipe_id == "physics.force_motion") != isinstance(self.parameters, ForceParameters)):
            raise ValueError("Parameter gehören nicht zum gewählten eigenen Laborrezept.")
        return self


RECIPES = {
    "physics.force_motion": {
        "subjects": ["Physik", "Technik"], "terms": ["Kraft", "Newton", "Beschleunigung", "Masse"],
        "purpose": "Eigenes kuratiertes Modell: konstante Beschleunigung aus der Ruhe; F=m·a und s=0,5·a·t².",
        "interaction": "Lokal bewusst starten/pausieren, Masse und Beschleunigung erkunden und auf gespeicherte Werte zurücksetzen; keine Messung oder Bewertung.",
        "content": "Eigenes kuratiertes Modell: geradlinige Bewegung aus der Ruhe mit konstanter Beschleunigung. Masse m = 2 kg; Beschleunigung a = 1 m/s². Kraft F = m · a. Strecke s = 0,5 · a · t². Laufzeit t = 2 s.",
    },
    "german.sentence_shift": {
        "subjects": ["Deutsch", "Deutsch als Zweitsprache"], "terms": ["Satzglied", "Umstellprobe", "Satzbau", "Prädikat"],
        "purpose": "Eigenes kuratiertes Satzbeispiel und vier ausdrücklich erlaubte Umstellungen vergleichen.",
        "interaction": "Feste Satzgruppen tippen, per Tastatur oder Drag umstellen; Lupe und Reset, keine allgemeine Grammatikbewertung.",
        "content": "Eigenes kuratiertes Beispiel: Mira liest am Morgen ein Buch. Satzglieder: Mira | liest | am Morgen | ein Buch. In diesem Aussagesatz steht das finite Verb liest an zweiter Satzgliedposition. am Morgen bleibt eine zusammengehörige Gruppe.",
        "groups": ["Mira", "liest", "am Morgen", "ein Buch"],
        "orders": [[0, 1, 2, 3], [2, 1, 0, 3], [3, 1, 0, 2], [0, 1, 3, 2]],
    },
}
RULES = """\nEIGENE LERNLABORE: kind lab ist nur mit labs_enabled und passendem freigegebenem Laborrezept verfügbar.
Nur physics.force_motion/version1 (mass_kg0.5..10,acceleration_m_s20..4) und german.sentence_shift/version1(example_id=mira_reads) existieren.
Einheiten/Anfangsruhe/konstanteBeschleunigung/Laufzeit2s sowie die vier deutschen Umstellungen sind serverkuratiert; keine eigenen Formeln, Gruppen, Koordinaten, URLs oder Modellprogramme ergänzen.
Für dieses eigene Zusatzbeispiel die passende gelieferte r-Quelle nennen; niemals als fotografierten Hefttext ausgeben. Andere physikalische Startwerte brauchen die exakten belegten m/a-Werte mit Einheiten.
Labgrafiken gehören in eine geöffnete Hilfe/Lösung oder einen servergeprüften strukturierten Erklärschritt. Keine unstrukturierte gegebene Fragegrafik, keine vorweggenommene Schülerantwort und keine Leistungsbehauptung durch Spielen.
"""


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def resolve(recipe_id, version=1, expected_digest=None):
    if version != 1 or recipe_id not in RECIPES:
        return None
    value = {"id": recipe_id, "version": version, **RECIPES[recipe_id]}
    encoded = digest(value)
    return {**value, "digest": encoded} if expected_digest in (None, encoded) else None


def references():
    return [{"id": "lab." + key, "version": 1, "kind": "lab", "lab_recipe_id": key,
        "subjects": value["subjects"], "terms": value["terms"], "purpose": value["purpose"],
        "interaction": value["interaction"]} for key, value in RECIPES.items()]


def validate(block, question, sources, *, structured=False, subject=None):
    from .subject_content import canonical_profile

    subject = canonical_profile(subject)
    lab = block.lab
    if lab is None or resolve(lab.recipe_id, lab.recipe_version) is None:
        raise ValueError("Unbekanntes Laborrezept.")
    if subject is not None and subject not in RECIPES[lab.recipe_id]["subjects"]:
        raise ValueError("Dieses eigene Laborrezept gehört nicht zum ausgewählten Fach.")
    if resolve(lab.recipe_id)["content"] not in sources:
        raise ValueError("Ein eigenes Lernlabor braucht seine echte, ausdrücklich kuratierte Modellgrundlage.")
    if block.disclosure == "given" and not structured:
        raise ValueError("Eigenes Labor erst in geöffneter Hilfe/Lösung oder geprüftem Erklärschritt.")
    if lab.recipe_id == "physics.force_motion":
        quote = block.source_excerpt.replace("−", "-").replace("²", "^2")
        def number(value):
            return re.escape(format(value, ".12g")).replace(r"\.", "[.,]")
        m = number(lab.parameters.mass_kg)
        a = number(lab.parameters.acceleration_m_s2)
        if (not re.search(r"\bm\s*=\s*" + m + r"\s*kg\b", quote) or
                not re.search(r"\ba\s*=\s*" + a + r"\s*m\s*/\s*s\^2\b", quote)):
            raise ValueError("Masse/Beschleunigung mit Einheiten fehlen im exakten Laborbeleg.")


def context_sources(payload, subject, group_id=None):
    if not payload.get("labs_enabled"):
        return []
    result = []
    for row in (payload.get("visual_context") or {}).get("sources", []):
        if row.get("source_type") != "curated_lab" or row.get("subject") != subject or row.get("group_id") != group_id:
            continue
        actual = resolve(row.get("reference_id"), row.get("version"), row.get("digest"))
        if actual is None or row.get("content") != actual["content"] or subject not in actual["subjects"]:
            raise ValueError("Eigene Laborgrundlage wurde geändert oder gehört zu einem anderen Fach.")
        result.append(actual["content"])
    return result


def contains(value):
    if isinstance(value, dict):
        return value.get("kind") == "lab" or any(contains(item) for item in value.values())
    if isinstance(value, list):
        return any(contains(item) for item in value)
    return False


class ForceLabView(ForceParameters):
    version: Literal[1]
    recipe_id: Literal["physics.force_motion"]
    recipe_version: Literal[1]
    time_ms: int = Field(ge=0, le=2000, multiple_of=50, strict=True)


class SentenceLabView(LabStrict):
    version: Literal[1]
    recipe_id: Literal["german.sentence_shift"]
    recipe_version: Literal[1]
    order_id: Literal["mira_time_book", "time_mira_book", "book_mira_time", "mira_book_time"]
    selected_group: Literal["mira", "verb", "morning", "book"]
    split_example: bool = Field(strict=True)


def checked_view(value, block):
    from fractions import Fraction

    if block.get("kind") != "lab":
        raise ValueError("Eine Laboransicht benötigt das zugehörige bereits geöffnete Lernlabor.")
    lab = LabV1.model_validate(block.get("lab"))
    if hasattr(value, "model_dump"):
        value = value.model_dump()
    view = (ForceLabView if lab.recipe_id == "physics.force_motion" else SentenceLabView).model_validate(value)
    if view.recipe_id != lab.recipe_id or view.recipe_version != lab.recipe_version:
        raise ValueError("Die Ansicht gehört zu einer anderen Laborrezeptfassung.")
    if isinstance(view, ForceLabView):
        for name, multiplier in (("mass_kg", 2), ("acceleration_m_s2", 4)):
            selected = Fraction(str(getattr(view, name)))
            original = Fraction(str(getattr(lab.parameters, name)))
            if selected != original and (selected * multiplier).denominator != 1:
                raise ValueError("Die lokale Laboransicht liegt außerhalb der endlichen Erkundungsschritte.")
    return view.model_dump()


def parse_view(value):
    if not isinstance(value, str) or len(value) > 512:
        raise ValueError("Laboransichten brauchen einen begrenzten JSON-Vertrag.")
    def unique(pairs):
        result = {}
        for key, item in pairs:
            if key in result:
                raise ValueError("Doppelte Laboransichtsschlüssel.")
            result[key] = item
        return result
    result = json.loads(value, object_pairs_hook=unique)
    if not isinstance(result, dict):
        raise ValueError("Eine Laboransicht ist ein JSON-Objekt.")
    return result


def view_facts(value, block):
    view = checked_view(value, block)
    if view["recipe_id"] == "physics.force_motion":
        t, m, a = view["time_ms"] / 1000, view["mass_kg"], view["acceleration_m_s2"]
        facts = {"force_n": round(m * a, 6), "distance_m": round(0.5 * a * t * t, 6),
            "velocity_m_s": round(a * t, 6), "model": "geradlinig, aus Ruhe, konstante Beschleunigung"}
    else:
        recipe = RECIPES[view["recipe_id"]]
        order = ["mira_time_book", "time_mira_book", "book_mira_time", "mira_book_time"].index(view["order_id"])
        groups = [recipe["groups"][i] for i in recipe["orders"][order]]
        facts = {"groups_in_order": groups, "selected_group": {"mira": "Mira", "verb": "liest", "morning": "am Morgen", "book": "ein Buch"}[view["selected_group"]],
            "split_example": ["am", "Morgen"] if view["split_example"] else None,
            "scope": "Nur dieses eigene kuratierte Aussagesatzbeispiel, keine allgemeine Grammatikbewertung"}
    return {"phase": "lab", "lab_view": view, "derived_locally": True, "unassessed_exploration": True, **facts}
