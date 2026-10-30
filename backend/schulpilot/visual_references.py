"""Source-bound own visual recipes. No model calls, links or mastery writes."""
import hashlib
import json
import re
from pathlib import Path

from sqlalchemy import or_, select

from .subject_content import PROFILES, public_presentation, validate_question
from .visual_reference_models import UnitVisualSnapshot, VisualReference
from .visual_reference_schemas import ExplanationStep

BUNDLE = Path(__file__).with_name("reference") / "visual-v1.json"
ORIGINAL_COMPARISONS = frozenset({"language.forms.original_comparison", "german.original_examples.comparison"})
REASONS = {"no_confirmed_source", "subject_unresolved", "no_reference", "missing_steps", "invalid_graphic", "source_changed"}
RULES = """\nVERBINDLICHE ERKLÄRSCHRITTE: visual_context enthält tatsächlich vorhandene, versionierte eigene Darstellungsrezepte.
Erzeuge für die Einführung 1–3 explanation_steps, für jede Frage 1–2 explanation_steps. Jeder Schritt benötigt einen fachlich passenden sichtbaren Graphic-Block, dieselben belegten Zahlen/Einheiten und einen erlaubten reference.id/version.
Schritte besitzen stabile kurze IDs, text, competence_id(null ohne ausdrücklich erlaubte Kompetenz), disclosure, presentation, reference und source_refs aus visual_context.sources.ref.
Einführungen verwenden given, Frageerklärungen solution oder passende hint1/2/3. Text und ALLE Grafikblöcke müssen dieselbe disclosure haben; keine ungesehenen Lösungen in gegebenen Blöcken.
Text ist keine grafische Ersatzdarstellung. Keine dekorativen Wortkästen, erfundenen Bilder, freier Code, SVG/HTML oder automatisch gestartete Medien.
Eine scene erklärt mindestens zwei belegte Phasen und verändert tatsächlich Hervorhebung oder Beziehungen; eine unbewegte Wortliste genügt nicht. Jede scene braucht mindestens einen Pfeil in mindestens einem Schritt. Für jeden Pfeil muss derselbe Schrittbeleg die beiden exakten Objektbeschriftungen unmittelbar als „Beschriftung A → Beschriftung B“ oder „Beschriftung A -> Beschriftung B“ enthalten. Fließtext, ungefähre Bedeutung und Pfeile aus anderen Belegen genügen nicht. Ohne solchen Originalpfeil eine andere passende Referenz wählen. Titel, Alternativtexte und alle Objektbeschriftungen müssen wortgetreu in den gewählten Grafik- oder Schrittbelegen stehen. Alle bestehenden Quellen-/Pfeil-/Antwortprüfungen bleiben verbindlich.
Wähle Quellen derselben Fach-/Paketgruppe. Quellenref ist nur die mitgelieferte p1,p2,... oder r1,r2,...; r bezeichnet ausdrücklich eigenes kuratiertes Zusatzwissen, niemals eine fotografierte Quelle; keine IDs, URLs oder internen Quellenfelder im Erklärungstext.
Bestehende explanation/hints und Antworten bleiben konsistent; neue Schritttexte dürfen keine andere Zahl/Einheit oder widersprechende Aussage einführen. Kein weiteres KI-Gespräch anfordern.
Bei kind fraction muss jeder im Schritttext genannte Bruch auch als eigener fraction-Block mit genau diesem Zähler und Nenner im selben Schritt sichtbar sein. Ein gleichwertiger Bruch ersetzt den geschriebenen Bruch nicht. Wenn mehrere Brüche nicht als eigene Blöcke darstellbar sind, formuliere einen kleineren Schritt mit nur dem dargestellten Bruch.
Bei kind triangle müssen im Schritttext genannte g- und h-Werte den Blockparametern entsprechen; bei kind reflection müssen genannte Winkel zur dargestellten Spiegelung passen. Texte und Grafik nie unabhängig voneinander wählen.
"""


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def seed(db):
    """Idempotent immutable recipe versions; safe on SQLite and PostgreSQL."""
    from sqlalchemy.dialects.postgresql import insert as pg_insert
    from sqlalchemy.dialects.sqlite import insert as sqlite_insert

    from .learning_labs import references as lab_references

    rows = [*json.loads(BUNDLE.read_text())["references"], *lab_references()]
    insert = pg_insert if db.bind.dialect.name == "postgresql" else sqlite_insert
    for recipe in rows:
        key = recipe["id"], recipe["version"]
        encoded = digest(recipe)
        db.execute(insert(VisualReference).values(id=key[0], version=key[1], digest=encoded, recipe=recipe)
                   .on_conflict_do_nothing(index_elements=["id", "version"]))
        saved = db.get(VisualReference, key)
        if saved.digest != encoded or digest(saved.recipe) != encoded:
            raise ValueError("Eine Grafikreferenz wurde ohne neue Version geändert.")
    return rows


def candidates(db, subject, text="", *, package_prepared=False):
    if subject not in PROFILES:
        return []
    result = []
    for row in db.scalars(select(VisualReference).where(or_(VisualReference.recipe["scope"].as_string().is_(None), VisualReference.recipe["scope"].as_string() != "exploration_only")).order_by(VisualReference.id, VisualReference.version)):
        recipe = row.recipe
        if row.id in ("math.fraction.wholes_remainder", "math.fraction.expansion", "math.multiples.common"):
            continue  # Only the dedicated Unit proof binder may offer this recipe.
        # AI exploration templates are NEVER a vetted source-bound recipe.
        if recipe.get("scope") == "exploration_only":
            continue
        if subject not in recipe["subjects"] and "*" not in recipe["subjects"]:
            continue
        if recipe["kind"] not in PROFILES[subject]:
            continue
        if row.id == "biology.plant.structure":
            # This fixed picture has four fixed organ positions, not arbitrary
            # plant-related labels. Offer it only when all four are evidenced.
            if not all(re.search(r"(?<!\w)" + term + r"(?!\w)", text, re.I)
                       for term in (r"blüte", r"blatt", r"st[äe]ngel", r"wurzel")):
                continue
        if row.id == "biology.photosynthesis.exchange":
            if not package_prepared:
                continue  # This version requires the package's prepared-ID binder.
            from .package_prepared_photosynthesis import bases

            if next(bases(text), None) is None:
                continue
        if row.id == "geography.atlantic.between":
            if not package_prepared:
                continue
            from .package_prepared_geography import bases

            if next(bases(text), None) is None:
                continue
        score = sum(term.casefold() in text.casefold() for term in recipe["terms"])
        # Universal source-relation scenes remain available for every profile;
        # their mandatory relation/phase validation prevents a fake word grid.
        if recipe["terms"] and not score:
            continue
        result.append({"id": row.id, "version": row.version, "digest": row.digest,
                       "kind": recipe["kind"], "purpose": recipe["purpose"],
                       "interaction": recipe["interaction"], "subject": subject, "score": score,
                       **{key: recipe[key] for key in ("variant", "lab_recipe_id") if recipe.get(key)}})
    return sorted(result, key=lambda row: (-row["score"], row["id"]))[:8]


def with_visual_context(db, child, payload, sources, *, groups=None):
    """Called only inside the existing explicit UNIT/PACKAGE reservation."""
    from .source_lineage import learning_source

    bindings = []
    group_map = {mid: group["id"] for group in groups or [] for mid in group["material_ids"]}
    for index, material in enumerate(sources[:24]):
        if material.child_id != child.id or material.purpose == "exam":
            continue
        safe = learning_source(db, material, revision=material.revision)
        if not safe["content"].strip():
            continue
        bindings.append({"ref": f"p{index + 1}", "material_id": material.id, "revision": material.revision,
                         "subject": material.subject, "topic": material.topic,
                         "group_id": group_map.get(material.id), "content": safe["content"],
                         "source_refs": safe.get("source_refs", []), "factual_status": safe["factual_status"]})
    if sources and (not bindings or (groups and any(not any(row["group_id"] == group["id"] for row in bindings) for group in groups))):
        raise ValueError("Die ausgewählten Seiten enthalten keinen ausreichend lesbaren, als Lehrgrundlage freigegebenen Inhalt für jedes Thema. Bitte prüfe die markierten Quellen.")
    value = dict(payload)
    # A single central content projection is shared with factual/graphic checks.
    if groups:
        value["materials"] = [{"subject": row["subject"], "topic": row["topic"],
                               "group_id": row["group_id"], "content": row["content"], "uncertainties": []}
                              for row in bindings]
    elif value.get("material") is not None and sources:
        value["material"] = {**value["material"], "content": "\n\n".join(row["content"] for row in bindings)}
    if not groups and value.get("materials") is not None:
        value["materials"] = [{"subject": row["subject"], "topic": row["topic"], "content": row["content"], "uncertainties": []}
                              for row in bindings]
    subjects = list(dict.fromkeys(row["subject"] for row in bindings))
    references = [row for subject in subjects for row in candidates(db, subject,
                  "\n".join(item["topic"] + "\n" + item["content"] for item in bindings if item["subject"] == subject),
                  package_prepared=(payload.get("function") == "package" and type(payload.get("package_partition")) is int)
                  or (payload.get("review") is True and payload.get("practice_kind") in ("repair", "check")
                      and payload.get("required_subject") == "Biologie")
                  or (payload.get("function") == "unit" and bool(payload.get("notebook_practice"))
                      and payload.get("required_subject") == "Biologie"))]
    if not payload.get("labs_enabled"):
        references = [row for row in references if row["kind"] != "lab"]
    lab_sources = []
    if payload.get("labs_enabled"):
        from .learning_labs import resolve as resolve_lab

        for subject in subjects:
            group_ids = list(dict.fromkeys(row.get("group_id") for row in bindings if row["subject"] == subject))
            for group_id in group_ids:
                text = "\n".join(row["topic"] + "\n" + row["content"] for row in bindings
                    if row["subject"] == subject and row.get("group_id") == group_id)
                for candidate in references:
                    if candidate["subject"] != subject or candidate["kind"] != "lab":
                        continue
                    recipe = db.get(VisualReference, (candidate["id"], candidate["version"])).recipe
                    actual = resolve_lab(recipe["lab_recipe_id"], 1)
                    if not any(term.casefold() in text.casefold() for term in actual["terms"]):
                        continue
                    lab_sources.append({"ref": f"r{len(lab_sources) + 1}", "source_type": "curated_lab",
                        "reference_id": actual["id"], "version": actual["version"], "digest": actual["digest"],
                        "subject": subject, "group_id": group_id, "content": actual["content"],
                        "factual_status": "own_curated_lab_example", "source_refs": []})
    reason = "no_confirmed_source" if not bindings else "subject_unresolved" if not any(s in PROFILES for s in subjects) else "no_reference" if not references else None
    from .curriculum import planning_context

    curriculum = planning_context(db, child, subjects)
    if curriculum is not None:
        value["curriculum_context"] = curriculum
    value["visual_context"] = {"version": 1, "required": reason is None, "reason": reason,
                               "references": references, "sources": [*bindings, *lab_sources],
                               **({"curriculum_binding": {key: curriculum[key] for key in ("revision", "state_code", "school_form_id", "grade", "profile_signature")}} if curriculum is not None else {})}
    from .unit_fraction_compositions import add_reference

    value = add_reference(db, value)
    from .study_fraction_expansions import add_reference as add_expansion_reference

    value = add_expansion_reference(db, value)
    from .notebook_fraction_expansions import add_reference as add_notebook_expansion

    value = add_notebook_expansion(db, value)
    from .coach_fraction_expansions import add_reference as add_coach_expansion

    value = add_coach_expansion(db, value)
    from .unit_multiples_common import add_reference as add_multiples_reference

    return add_multiples_reference(db, value)



def with_foundation_context(db, payload):
    """Attach only server-curated rules and the server's fixed probe example."""
    from .competences import resolve_reference
    from .subject_registry import resolve

    entry = payload.get("learning_entry")
    context = payload.get("visual_context")
    if not entry or not context:
        return payload
    value = {**context, "sources": list(context["sources"]), "references": list(context["references"])}
    references = {row["reference_id"]: row for row in entry.get("references", [])}
    index = max([int(row["ref"][1:]) for row in value["sources"] if row["ref"].startswith("r")] or [0])
    for plan in entry.get("units", []):
        subject = resolve(db, plan["subject"])
        for probe in plan.get("probes", []):
            selected = references.get(probe.get("reference_id"))
            actual = resolve_reference(selected["reference_id"], selected["version"], selected["digest"]) if selected else None
            if not actual or not subject or subject.key != actual["subject_key"]:
                raise ValueError("Die eigene Grundlagenregel gehört nicht zum freigegebenen Fach.")
            index += 1
            # These core values are selected and validated server-side by
            # learning_entry, not taken from the model's answer or a pupil's work.
            example = probe["prompt"] + "\nGeprüfte Antwort des eigenen Grundlagenbeispiels: " + probe["answer"]
            value["sources"].append({"ref": f"r{index}", "source_type": "curated_foundation",
                "reference_id": actual["reference_id"], "version": actual["version"], "digest": actual["digest"],
                "example_question_id": probe["id"], "example_digest": digest({key: probe[key] for key in ("id","type","prompt","answer","options","accepted")}), "subject": plan["subject"], "group_id": plan["group_id"],
                "content": actual["content"] + "\n" + example,
                "factual_status": "curated_rule_and_server_example", "source_refs": []})
            for recipe in candidates(db, plan["subject"], actual["content"]):
                if recipe["kind"] == "lab" and not payload.get("labs_enabled"):
                    continue
                if recipe not in value["references"]:
                    value["references"].append(recipe)
    value["required"] = bool(value["sources"] and value["references"])
    return {**payload, "visual_context": value}

def bind_schema(schema, payload):
    context = payload.get("visual_context")
    if not context or not context["required"]:
        return
    definitions = schema.get("$defs", {})
    for node in [schema, *definitions.values()]:
        props = node.get("properties", {})
        if "explanation_steps" not in props:
            continue
        field = props["explanation_steps"]
        array = next((item for item in field.get("anyOf", []) if item.get("type") == "array"), field)
        props["explanation_steps"] = {**array, "minItems": 1, "maxItems": 1 if payload.get("visual_only") else 2 if "prompt" in props else 3}
        node["required"] = list(dict.fromkeys([*node.get("required", []), "explanation_steps"]))
    choice = definitions.get("VisualReferenceChoice", {}).get("properties", {})
    if choice:
        choice["id"]["enum"] = list(dict.fromkeys(row["id"] for row in context["references"]))
        choice["version"]["enum"] = sorted({row["version"] for row in context["references"]})
    step = definitions.get("ExplanationStep", {}).get("properties", {})
    if step:
        step["source_refs"]["items"]["enum"] = [row["ref"] for row in context["sources"]]
        allowed_competences = [row["id"] for row in context.get("competences", [])]
        step["competence_id"] = {"anyOf": [{"type": "string", "enum": allowed_competences}, {"type": "null"}]} if allowed_competences else {"type": "null"}


def _meaningful(block, recipe, *, sources=None, question=None):
    if block.kind != recipe["kind"] or (recipe.get("variant") and block.variant != recipe["variant"]):
        raise ValueError("Grafik passt nicht zur gewählten Referenz.")
    if block.kind == "lab" and block.lab.recipe_id != recipe.get("lab_recipe_id"):
        raise ValueError("Laborparameter passen nicht zur gewählten Referenz.")
    if block.kind == "timeline" and block.variant == "calendar":
        labels = [" ".join(label.split()) for label in block.labels]
        quote = " ".join(block.source_excerpt.split())
        positions = [quote.find(label) for label in labels]
        if (len(labels) < 2 or len(set(labels)) != len(labels)
                or any(position < 0 for position in positions) or positions != sorted(positions)):
            raise ValueError("Die Zeitachse benötigt mindestens zwei verschiedene, in Reihenfolge belegte Zeitpunkte.")
    if recipe.get("id") == "biology.photosynthesis.exchange":
        from .package_prepared_photosynthesis import validate

        validate(block, sources)
        return
    if recipe.get("id") == "geography.atlantic.between":
        from .package_prepared_geography import validate

        validate(block, sources)
        return
    if recipe.get("id") in ORIGINAL_COMPARISONS or recipe.get("id") == "german.word_formation.parts":
        labels = [" ".join(label.split()) for label in block.labels]
        quote = " ".join(block.source_excerpt.split())
        if (not 2 <= len(labels) <= 4 or len(set(labels)) != len(labels)
                or any(len(label) > 160 for label in labels) or block.numbers or block.connections or block.marks or block.unit):
            raise ValueError("Der Originalvergleich benötigt zwei bis vier unterschiedliche kurze Originalausdrücke ohne Zusatzparameter.")
        if any(not re.search(r"(?<!\w)" + re.escape(label) + r"(?!\w)", quote) for label in labels):
            raise ValueError("Jeder Vergleichsausdruck muss vollständig und wortgetreu im Originalbeleg stehen.")
        if sources is not None and not any(quote in " ".join(source.split()) for source in sources):
            raise ValueError("Der Originalvergleich benötigt einen bestätigten Originalbeleg statt eines erzeugten Aufgabenbeispiels.")
        if recipe.get("id") == "german.word_formation.parts":
            from .package_prepared_scenes import word_part_bases

            originals = [base for base, _ in word_part_bases(block.source_excerpt)]
            if not originals or block.labels != originals[0]["labels"] or block.title != originals[0]["title"]:
                raise ValueError("Die Wortbausteine benötigen eine unveränderte sichtbare Plusfolge im Originalbeleg.")
        if question is not None:
            prompt = " ".join(question.get("prompt", "").split())
            if not any(re.search(r"(?<!\w)" + re.escape(label) + r"(?!\w)", prompt) for label in labels):
                raise ValueError("Die Frage muss mindestens einen vollständigen Originalausdruck ihres Vergleichs nennen.")
    if recipe.get("id") in ("general.original_evidence.focused_list", "general.original_evidence.focused_sentences"):
        from .package_prepared_focus import validate_focus

        validate_focus(block, sources=sources, question=question,
                       sentences=recipe["id"] == "general.original_evidence.focused_sentences")
        return  # Only this immutable recipe permits a noncausal reading focus.
    if block.kind == "scene":
        scene = block.scene
        if scene is None or len(scene.steps) < 2 or not any(step.edges for step in scene.steps):
            raise ValueError("Die Lernszene braucht belegte Beziehungen und mindestens zwei Phasen.")
        states = {digest({"highlight": step.highlight, "edges": [edge.model_dump() for edge in step.edges]}) for step in scene.steps}
        if len(states) < 2:
            raise ValueError("Unveränderte Wortkästen sind keine fachliche Phasenvisualisierung.")


def validate_steps(db, steps, subject, context, *, question=None, group_id=None, introduction=False):
    if not steps:
        raise ValueError("Jeder neue Erklärabschnitt benötigt passende Grafikschritte.")
    if len(steps) > (3 if introduction else 2):
        raise ValueError("Zu viele Erklärschritte.")
    allowed = {(row["id"], row["version"], row["subject"]) for row in context.get("references", [])}
    refs = {row["ref"]: row for row in context.get("sources", []) if row["subject"] == subject and row.get("group_id") == group_id}
    seen, checked = set(), []
    for raw in steps:
        step = ExplanationStep.model_validate(raw)
        if step.id in seen:
            raise ValueError("Doppelte Erklärungsschritt-ID.")
        seen.add(step.id)
        from .source_lineage import false_equality

        if false_equality(step.text):
            raise ValueError("Der Erklärtext enthält eine falsche rationale Gleichung.")
        if step.competence_id is not None and not any(row["id"] == step.competence_id and row["subject"] == subject for row in context.get("competences", [])):
            raise ValueError("Erklärschritt verwendet keine freigegebene Kompetenz-ID.")
        if introduction and step.disclosure != "given":
            raise ValueError("Einführungen dürfen keine versteckte Aufgabenlösung enthalten.")
        if not introduction and step.disclosure == "given":
            raise ValueError("Frageerklärungen öffnen erst über Hinweis oder Lösung.")
        if not set(step.source_refs) <= refs.keys():
            raise ValueError("Erklärung verweist auf fremde oder veraltete Quellen.")
        key = step.reference.id, step.reference.version
        if (*key, subject) not in allowed:
            raise ValueError("Referenz gehört nicht zum freigegebenen Fach und Auftrag.")
        stored = db.get(VisualReference, key)
        if stored is None:
            raise ValueError("Die gewählte Referenzversion existiert nicht.")
        texts = [refs[ref]["content"] for ref in step.source_refs]
        # The generated prose never serves as new source evidence for its graphic.
        fake = question or {"prompt": "", "type": "short", "answer": "", "accepted": []}
        if stored.id == "math.fraction.expansion":
            from .study_fraction_expansions import validate_question_step

            if introduction or not any(r.get("id") == stored.id and r.get("version") == stored.version
                    and r.get("digest") == stored.digest == digest(stored.recipe) for r in context.get("references", [])):
                raise ValueError("Ungültiger vorabgeprüfter Erweiterungsbeweis.")
            if step.id.startswith("cf_"):
                from .coach_fraction_expansions import validate_question_step as validate_coach_expansion

                validate_coach_expansion(step, context, question)
            else:
                validate_question_step(step, context, question)
            checked.append(step.model_dump())
            continue
        if stored.id == "math.fraction.wholes_remainder":
            from .unit_fraction_compositions import compile_candidates, validate_step

            if not any(r.get("id") == stored.id and r.get("version") == stored.version
                    and r.get("digest") == stored.digest == digest(stored.recipe) for r in context.get("references", [])):
                raise ValueError("Ungültige vorabgeprüfte Ganzes-Rest-Komposition.")
            validate_step(step, compile_candidates(context), introduction=introduction, question=question)
            checked.append(step.model_dump())
            continue
        if stored.id == "math.multiples.common":
            from .unit_multiples_common import validate_step as validate_multiples_step

            if subject != "Mathematik" or group_id is not None:
                raise ValueError("Ungültiger vorabgeprüfter kgV-Beweis.")
            validate_multiples_step(step, context, None if introduction else question)
            checked.append(step.model_dump())
            continue
        validate_question(step.presentation.model_dump(), fake, texts, PROFILES.get(subject, ()), structured=True, subject=subject)
        for block in step.presentation.blocks:
            _meaningful(block, stored.recipe, sources=texts, question=question)
            # All explicitly repeated graphic values must agree with the same
            # step's literal source-bound parameter data. Prose may explain it.
            if block.kind == "reflection":
                from fractions import Fraction

                angle = Fraction(str(block.numbers[0]))
                allowed_angles = {angle, 90 - angle, 2 * angle, 180 - 2 * angle, Fraction(0), Fraction(90), Fraction(180)}
                mentions = re.findall(r"(?<![\d.])(\d+(?:[.,]\d+)?)\s*(?:Grad|°)", step.text, re.I)
                if any(Fraction(value.replace(",", ".")) not in allowed_angles for value in mentions):
                    raise ValueError("Erklärtext und Spiegelgrafik verwenden verschiedene Winkel.")
            if block.kind == "triangle":
                for name, number in zip(("g", "h"), block.numbers, strict=True):
                    mentions = re.findall(rf"\b{name}\s*=\s*(\d+(?:[.,]\d+)?)", step.text)
                    if any(float(value.replace(",", ".")) != number for value in mentions):
                        raise ValueError("Erklärtext und Dreieckgrafik verwenden verschiedene Grundseiten oder Höhen.")
            if block.kind == "fraction":
                fractions = re.findall(r"(?<!\d)(\d+)\s*/\s*([1-9]\d*)(?!\d)", step.text)
                fractions += re.findall(r"\\(?:d?frac)\{(\d+)\}\{([1-9]\d*)\}", step.text)
                fractions += re.findall(r"(?<!\d)(\d+)\s+(?:von|aus)\s+([1-9]\d*)(?!\d)", step.text)
                allowed_pairs = {(str(int(b.numbers[0])), str(int(b.numbers[1]))) for b in step.presentation.blocks if b.kind == "fraction"}
                if any(pair not in allowed_pairs for pair in fractions):
                    raise ValueError("Erklärtext und Bruchgrafik verwenden verschiedene Brüche.")
        checked.append(step.model_dump())
    return checked


def validate_output(db, data, payload):
    context = payload.get("visual_context")
    if not context:
        return
    if not context.get("required"):
        if any(unit.get("explanation_steps") or any(q.get("explanation_steps") for q in unit.get("questions", [])) for unit in data.get("units") or [data]):
            raise ValueError("Erklärgrafiken ohne freigegebene Referenz und Quelle sind nicht zulässig.")
        return
    for unit in data.get("units") or [data]:
        subject, group = unit["subject"], unit.get("group_id")
        validate_steps(db, unit.get("explanation_steps"), subject, context, group_id=group, introduction=True)
        for question in unit.get("questions", []):
            validate_steps(db, question.get("explanation_steps"), subject, context, question=question, group_id=group)



def source_binding(value, *, question_source_bound=False):
    if value.get("source_type") == "curated_lab":
        return {"source_kind": "curated_lab", "reference_id": value["reference_id"],
            "version": value["version"], "digest": value["digest"], "label": "Eigenes kuratiertes Laborbeispiel",
            "_question_source_bound": question_source_bound}
    if value.get("source_type") == "curated_foundation":
        return {"source_kind": "curated_foundation", "reference_id": value["reference_id"],
                "version": value["version"], "digest": value["digest"],
                "example_question_id": value["example_question_id"], "label": "Eigenes kuratiertes Zusatzwissen",
                "_example_digest": value.get("example_digest"), "_question_source_bound": question_source_bound}
    return {"material_id": value["material_id"], "revision": value["revision"],
            "block_ids": [ref["block_id"] for ref in value.get("source_refs", []) if ref.get("block_id")],
            "_content_digest": digest(value["content"]), "_question_source_bound": question_source_bound}

def _hydrate(steps, context):
    sources = {row["ref"]: row for row in context.get("sources", [])}
    result = []
    for raw in steps or []:
        step = dict(raw)
        reference = next(row for row in context["references"] if row["id"] == step["reference"]["id"] and row["version"] == step["reference"]["version"])
        step["reference"] = {**step["reference"], "digest": reference["digest"], "parameter_digest": digest(public_presentation(step["presentation"], closed=True, hints=3))}
        step["source_refs"] = [source_binding(sources[ref]) for ref in step["source_refs"]]
        result.append(step)
    return result


def remember(db, unit, data, payload):
    context = payload.get("visual_context")
    if context is None:
        return
    guard_context(db, unit.child_id, context)
    signature = digest([[row.get("material_id") or row.get("reference_id"), row.get("revision") or row.get("version"), row["content"]] for row in context["sources"]])
    reason, steps, question_steps = context.get("reason"), [], {}
    if context.get("required"):
        try:
            validate_output(db, data, payload)
            steps = _hydrate(data.get("explanation_steps"), context)
            question_steps = {question["id"]: _hydrate(question.get("explanation_steps"), context) for question in unit.questions}
        except ValueError:
            reason = "missing_steps" if not data.get("explanation_steps") else "invalid_graphic"
    if not steps:
        unit.questions = [{key: value for key, value in question.items() if key != "explanation_steps"} for question in unit.questions]
    row = UnitVisualSnapshot(unit_id=unit.id, source_signature=signature, status="ready" if steps else "incomplete",
                            reason=reason, steps=steps, question_steps=question_steps, source_bindings=[source_binding(ref, question_source_bound=True) for ref in context["sources"]], receipts=[{"reference": step["reference"], "source_refs": step["source_refs"]} for step in steps],
                            notice="" if steps else "Die fachliche Grafik ist noch nicht vollständig vorbereitet. Der gespeicherte Text bleibt lesbar.")
    db.add(row)


def public_steps(steps, *, closed=False, hints=0):
    allowed = {"given", *[f"hint{i}" for i in range(1, min(3, hints) + 1)]} | ({"solution"} if closed else set())
    return [{k: v for k, v in step.items() if k not in {"presentation"}} |
            {"source_refs": [{k: v for k, v in ref.items() if not k.startswith("_")} for ref in step.get("source_refs", []) if isinstance(ref, dict)],
             "presentation": public_presentation(step["presentation"], closed=closed, hints=hints)}
            for step in steps or [] if step.get("disclosure") in allowed]



def _binding_current(db, unit, ref):
    from .competences import resolve_reference
    from .db import Material
    from .source_lineage import learning_source, usable_source

    if ref.get("source_kind") == "curated_lab":
        from .learning_labs import resolve as resolve_lab

        actual = resolve_lab(ref.get("reference_id"), ref.get("version"), ref.get("digest"))
        return actual is not None and unit.subject in actual["subjects"]
    if ref.get("source_kind") == "curated_foundation":
        question = next((q for q in unit.questions if q["id"] == ref["example_question_id"]), None)
        return bool(resolve_reference(ref["reference_id"], ref["version"], ref["digest"]) is not None and question
            and (not ref.get("_example_digest") or ref["_example_digest"] == digest({key: question[key]
                for key in ("id","type","prompt","answer","options","accepted")})))
    material = db.get(Material, ref["material_id"])
    if material is None or material.child_id != unit.child_id or not usable_source(db, material, revision=ref["revision"]):
        return False
    safe = learning_source(db, material, revision=ref["revision"])
    ids = {item["block_id"] for item in safe.get("source_refs", []) if item.get("block_id")}
    return (set(ref.get("block_ids", [])) <= ids and
        (not ref.get("_content_digest") or ref["_content_digest"] == digest(safe["content"])))


def source_bindings_current(db, unit, *, require_question_binding=False):
    """A graphics-only legacy sidecar never certifies old answer generation."""
    row = db.get(UnitVisualSnapshot, unit.id)
    bindings = row.source_bindings if row else []
    return bool(bindings and all(_binding_current(db, unit, ref) and
        (not require_question_binding or ref.get("_question_source_bound") is True) for ref in bindings))

def projection(db, unit, *, show_introduction=True):
    from .db import Job

    job = db.scalar(select(Job).where(Job.child_id == unit.child_id, Job.kind == "unit_visuals",
        Job.payload["unit_id"].as_string() == unit.id).order_by(Job.created.desc(), Job.id.desc()).limit(1))
    preparation = {"visual_preparation": {"id": job.id, "status": job.status, "error": job.error} if job else None}
    row = db.get(UnitVisualSnapshot, unit.id)
    if row is None:
        return {**preparation, "explanation_steps": [], "explanation_visual_status": "legacy_text", "explanation_visual_reason": "missing_steps"}
    # Check the saved safe block identities and content, not just the existence
    # of some still-usable paragraph on the same material revision.
    valid = source_bindings_current(db, unit) and all(_binding_current(db, unit, ref)
        for step in [*row.steps, *[step for steps in row.question_steps.values() for step in steps]] for ref in step["source_refs"])
    return {**preparation, "explanation_steps": public_steps(row.steps) if show_introduction and valid else [],
            "explanation_visual_status": row.status if valid else "incomplete",
            "explanation_visual_reason": row.reason if valid else "source_changed"}


def guard_context(db, child_id, context):
    from .db import Child, Material
    from .source_lineage import learning_source

    if context.get("curriculum_binding") is not None:
        from .curriculum import guard_planning_context

        child = db.get(Child, child_id, populate_existing=True)
        if child is None:
            raise ValueError("Der Kinderzugang wurde geändert.")
        guard_planning_context(db, child, context["curriculum_binding"])
    for ref in context.get("sources", []):
        if ref.get("source_type") == "curated_lab":
            from .learning_labs import resolve as resolve_lab

            actual = resolve_lab(ref.get("reference_id"), ref.get("version"), ref.get("digest"))
            if actual is None or actual["content"] != ref.get("content") or ref.get("subject") not in actual["subjects"]:
                raise ValueError("Die eigene Laborgrundlage wurde geändert.")
            continue
        if ref.get("source_type") == "curated_foundation":
            from .competences import resolve_reference

            if resolve_reference(ref["reference_id"], ref["version"], ref["digest"]) is None:
                raise ValueError("Die eigene Grundlagenregel wurde geändert.")
            continue
        material = db.get(Material, ref["material_id"])
        if material is None or material.child_id != child_id or material.revision != ref["revision"]:
            raise ValueError("Die Grafikquelle wurde während der Vorbereitung geändert.")
        current = learning_source(db, material, revision=ref["revision"])
        if current["content"] != ref["content"] or not current["content"].strip():
            raise ValueError("Die Grafikquelle ist nicht mehr als Lehrgrundlage freigegeben.")


def export_child(db, child_id):
    from .db import LearningUnit

    return [{column.name: getattr(row, column.name) for column in UnitVisualSnapshot.__table__.columns}
            for row in db.scalars(select(UnitVisualSnapshot).join(LearningUnit).where(LearningUnit.child_id == child_id))]


def question_projection(db, unit, question, *, closed=False, hints=0):
    row = db.get(UnitVisualSnapshot, unit.id)
    if row is None or projection(db, unit)["explanation_visual_status"] != "ready":
        return []
    if not closed:
        from .db import Activity

        closed = db.scalar(select(Activity.id).where(Activity.unit_id == unit.id,
            Activity.kind == "explanation", Activity.detail["question_id"].as_string() == question["id"]).limit(1)) is not None
    return public_steps(row.question_steps.get(question["id"], []), closed=closed, hints=hints)
