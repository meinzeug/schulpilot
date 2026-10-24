"""Shared, read-only filtered source context for existing paid learning paths."""
import unicodedata

from .db import Material
from .source_lineage import learning_source


class UnusableSources(ValueError):
    def __init__(self):
        super().__init__("Die ausgewählten Seiten enthalten nur ungeklärte Lesestellen, Schülerantworten oder Korrekturen. Bitte zuerst das Original fachlich prüfen; daraus wurden keine neuen Aufgaben erzeugt.")


def project(db, materials):
    values = [learning_source(db, material) for material in materials]
    if materials and not any(value["content"].strip() for value in values):
        raise UnusableSources()
    return values


def policy(value):
    return {"version": value["policy_version"], "factual_status": value["factual_status"],
            "excluded_reasons": sorted({row["reason"] for row in value["exclusions"]})}


def exact_quote(quote, texts):
    # Typography/whitespace only: CO/Co, minus and nmid/mid remain distinct.
    def normalized(value):
        return " ".join(unicodedata.normalize("NFC", value).split())

    return bool(quote.strip()) and any(normalized(quote) in normalized(text) for text in texts)


def citations_current(db, child_id, refs, citations):
    pages = {}
    aliases = {}
    for ref in refs:
        material = db.get(Material, ref["id"])
        if not material or material.child_id != child_id or material.revision != ref["revision"] or not material.confirmed:
            return False
        value = learning_source(db, material)
        if not value["content"].strip():
            return False
        pages[ref["ref"]] = value["content"]
        aliases[material.id] = ref["ref"]
    for citation in citations:
        if citation.get("foundation_id"):
            continue  # Existing curated, separately versioned foundation proof.
        # Homework's existing checked response uses owned material_id rather
        # than a provider alias; resolve only against this exact source set.
        alias = citation.get("ref") or aliases.get(citation.get("material_id"))
        if alias not in pages or not exact_quote(citation.get("quote", ""), [pages[alias]]):
            return False
    return True


def current_values(db, child_id, refs):
    """Selected current sources for AI; legacy local word histories stay readable."""
    from fastapi import HTTPException

    materials = []
    for ref in refs:
        material = db.get(Material, ref["id"])
        if (not material or material.child_id != child_id or not material.confirmed
                or material.revision != ref["revision"] or material.purpose == "exam"):
            raise HTTPException(409, "Die bestätigte Quellenfassung wurde geändert. Bitte die Auswahl neu prüfen.")
        materials.append(material)
    try:
        return project(db, materials)
    except UnusableSources as error:
        raise HTTPException(409, str(error)) from None


def failure_billing(result, error, *, provider_requested):
    """Only a proven pre-function failure releases an unused reservation."""
    receipt = result or getattr(error, "billing_result", None)
    if receipt is None and not provider_requested:
        from .providers import Result

        return Result({}, 0, 0, 0, cost_source="cancelled")
    return receipt
