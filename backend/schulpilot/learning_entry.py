"""A finite entry plan inside the existing requested round, never another call.

The server selects reviewed prerequisites and question identities. The model
only supplies the existing teaching fields. Attempts remain the only evidence.
"""

import copy
import hashlib

from sqlalchemy import select

from . import competences
from .competence_models import CompetenceSource, QuestionCompetence
from .db import LearningMemory, LearningUnit, Material

CORE = ("id", "type", "prompt", "answer", "options", "accepted")
LABELS = {"Brüche erweitern": "math.fractions.expand", "Brüche kürzen": "math.fractions.reduce",
    "Zähler und Nenner benennen": "math.fractions.components", "Gleichwertige Brüche erkennen": "math.fractions.equivalence"}
RULES = """
learning_entry ist der verbindliche serverseitige Einstieg, keine Modell-Diagnose.
Alle vorgegebenen Frage-IDs und festen Kernfelder unverändert übernehmen. Die
kurze Voraussetzungskontrolle gehört zur selben begrenzten Runde, kein Zusatztest.
Nur Hinweise/Erklärung/zulässige Darstellung ergänzen. references sind ausdrücklich
kuratierte Zusatzregeln, niemals als Heftfoto oder Lehrerbewertung ausgeben.
Beobachtungen sind gespeicherte Originalversuche, kein Erfolgsversprechen.
"""


def verified_math_identity(question, goals):
    from .coaching import fraction_task_goal, fraction_task_signature
    from .schemas import Question

    signature = fraction_task_signature(question["prompt"])
    if not signature or signature[0] not in ("expand", "reduce", "add"):
        return None
    try:
        Question.model_validate({key: value for key, value in question.items() if key in Question.model_fields})
    except ValueError:
        return None
    goal = fraction_task_goal(question["prompt"], goals)
    label = next((item["label"] for item in goals if item["id"] == goal), None)
    if signature[0] == "add" and label == "Brüche addieren":
        return "math.fractions.add_same" if signature[1][0][1] == signature[1][1][1] else "math.fractions.add_unlike"
    return LABELS.get(label)


def _proof(db, child_id, ids):
    return [{key: row[key] for key in ("id", "status", "confidence", "tasks", "independent", "supported",
        "needs_practice", "uncertain", "evidence_total", "evidence_refs", "last_independent_success", "last_difficulty")}
        for row in competences.evidence(db, child_id, ids)]


def _known(row):
    # Reuse the existing dated-recall assessment, not one correct first attempt.
    # A due review keeps its evidence; scheduling it is a separate existing path.
    return bool(row and row["confidence"] == "repeated_recall"
        and row["status"] in ("repeated_independent", "review_due"))


def _probe(competence, seed, previous, ordinal):
    template = competence["probe"]
    for offset in range(256):
        value = int(hashlib.sha256((seed + ":" + str(offset)).encode()).hexdigest()[:12], 16)
        denominator = 3 + value % 10
        numerator = 1 + (value // 10) % (denominator - 1)
        if template == "fraction_meaning":
            prompt = f"Ein Ganzes ist in {denominator} gleich große Teile geteilt. {numerator} Teile sind ausgewählt. Welchen Bruch beschreibt das? Schreibe Zähler/Nenner."
            answer = f"{numerator}/{denominator}"
        elif template == "fraction_components":
            prompt = f"Beim Bruch {numerator}/{denominator}: Welche Zahl ist der Nenner?"
            answer = str(denominator)
        elif template == "fraction_equivalence":
            prompt = f"Erweitere {numerator}/{denominator} mit 2. Welcher Bruch entsteht? Schreibe Zähler/Nenner."
            answer = f"{2 * numerator}/{2 * denominator}"
        else:
            return None
        if competences.normalized(prompt) not in previous:
            return {"id": "prior_" + ordinal, "type": "short", "prompt": prompt, "answer": answer,
                "options": [], "accepted": [], "competence_id": competence["id"],
                "visual_example": {"numerator": numerator, "denominator": denominator, "factor": 2,
                    "text": "Servergeprüftes Beispiel: " + prompt + " Ergebnis: " + answer + "."},
                "reference_id": competence["id"], "role": "prior_check"}
    return None


def _closure(rows, targets):
    ordered = []
    def visit(key):
        for parent in rows[key]["prerequisites"]:
            visit(parent)
        if key not in ordered:
            ordered.append(key)
    for key in targets:
        visit(key)
    return ordered


def with_learning_entry(db, child, payload, sources, *, groups=None, enabled=False):
    if not enabled:
        return payload
    if not sources and isinstance(payload.get("goal"), dict):
        return payload  # Existing explicit parent goal, no invented photo proof.
    if any(material.child_id != child.id for material in sources):
        raise ValueError("Der Lernstoff gehört zu einem anderen Kinderzugang.")
    sources = [material for material in sources if competences.source_ref(db, material) is not None]
    refs = [competences.source_ref(db, material) for material in sources]
    if not refs or any(value is None or material.child_id != child.id for material, value in zip(sources, refs, strict=True)):
        raise ValueError("Der Lernstoff ist für den Einstieg nicht aktuell verwendbar.")
    protected = any(payload.get(key) for key in ("review", "study_block", "homework_practice", "exam_preparation", "exam_review_practice"))
    rows = competences.catalogue()
    selections = payload.get("selected_groups") or [{"id": None,
        "subject": payload.get("required_subject") or sources[0].subject}]
    previous = {competences.normalized(q["prompt"]) for unit in db.scalars(select(LearningUnit).where(
        LearningUnit.child_id == child.id)) for q in unit.questions}
    units, allowed, references = [], {}, {}
    for group in selections:
        group_sources = sources
        if group["id"] is not None and groups:
            ids = {identifier for item in groups if item["id"] == group["id"] for identifier in item["material_ids"]}
            group_sources = [material for material in sources if material.id in ids]
        targets = competences.matches(db, group_sources, group["subject"])
        # A taught target can mention its prerequisite vocabulary. Keep the
        # most specific matched goals, instead of retesting every mentioned word.
        parents = {identifier for item in targets for identifier in _closure(rows, [item["id"]]) if identifier != item["id"]}
        targets = [item for item in targets if item["id"] not in parents]
        selected = _closure(rows, [item["id"] for item in targets])
        observations = _proof(db, child.id, selected)
        by_id = {item["id"]: item for item in observations}
        reuse = bool(targets and all(_known(by_id.get(item["id"])) for item in targets))
        prefix = hashlib.sha256(str(group["id"]).encode()).hexdigest()[:8]
        probes = []
        if not protected and not reuse:
            for identifier in selected:
                if rows[identifier].get("probe") and not _known(by_id.get(identifier)):
                    value = _probe(rows[identifier], child.id + str(refs) + identifier, previous, prefix + "_" + str(len(probes) + 1))
                    if value:
                        probes.append(value)
                        references[identifier] = competences.resolve_reference(identifier, competences.VERSION)
                    if len(probes) >= (2 if group["id"] is not None else 3):
                        break
        for identifier in selected:
            allowed[identifier] = {"id": identifier, "subject": group["subject"]}
        units.append({"group_id": group["id"], "subject": group["subject"], "prefix": prefix,
            "source_refs": [competences.source_ref(db, material) for material in group_sources],
            "targets": targets, "competence_ids": selected, "evidence": observations, "probes": probes,
            "entry_mode": "existing_contract" if protected else "reuse_evidence" if reuse else "prerequisite_probe" if probes else "source_probe"})
    entry = {"version": 1, "catalog_version": competences.VERSION, "source_refs": refs,
        "source_signature": competences.fingerprint(refs), "units": units, "references": list(references.values())}
    result = {**payload, "learning_entry": entry}
    if isinstance(payload.get("visual_context"), dict):
        result["visual_context"] = {**payload["visual_context"], "competences": list(allowed.values())}
    return result


def _specs(plan, count):
    probes = plan["probes"][:count]
    if plan["entry_mode"] == "source_probe":
        probes = [{"id": "prior_" + plan["prefix"] + "_" + str(index + 1), "role": "prior_check"}
            for index in range(min(2, count))]
    return [*probes, *[{"id": "main_" + plan["prefix"] + "_" + str(index + 1), "role": "practice"}
        for index in range(count - len(probes))]]


def _branches(schema, definition):
    if "$ref" in definition:
        return _branches(schema, schema["$defs"][definition["$ref"].rsplit("/", 1)[-1]])
    return [branch for item in definition.get("anyOf", [definition]) for branch in
        (_branches(schema, item) if item is not definition else [item])]


def bind_entry_schema(schema, payload):
    entry = payload.get("learning_entry")
    if not entry:
        return
    plans = {item["group_id"]: item for item in entry["units"]}
    units = schema["properties"].get("units", {}).get("items", {}).get("anyOf", [schema])
    for definition in units:
        group = definition.get("properties", {}).get("group_id", {}).get("enum", [None])[0]
        plan = plans.get(group)
        if not plan or plan["entry_mode"] == "existing_contract":
            continue
        definition["properties"]["subject"]["enum"] = [plan["subject"]]
        questions = definition["properties"]["questions"]
        count = questions.get("maxItems", 4) if group is not None else min(5, max(4, len(plan["probes"]) + 2))
        questions.update(minItems=count, maxItems=count)
        formats = _branches(schema, questions["items"])
        branches = []
        for spec in _specs(plan, count):
            for original in formats:
                properties = original.get("properties", {})
                types = properties.get("type", {}).get("enum", [])
                if spec.get("type") and spec["type"] not in types:
                    continue
                if spec["role"] == "prior_check" and not (set(types) & {"short", "choice"}):
                    continue
                branch = copy.deepcopy(original)
                props = branch["properties"]
                props["id"]["enum"] = [spec["id"]]
                if spec.get("type"):
                    for key in ("type", "prompt", "answer"):
                        props[key]["enum"] = [spec[key]]
                    props["options"]["maxItems"] = props["accepted"]["maxItems"] = 0
                branches.append(branch)
        if not branches:
            raise ValueError("Das Aufgabenformat passt nicht zum begrenzten Lernstart.")
        questions["items"] = {"anyOf": branches}


def validate_entry_output(payload, data):
    entry = payload.get("learning_entry")
    if not entry:
        return
    plans = {item["group_id"]: item for item in entry["units"]}
    for unit in data.get("units") or [data]:
        plan = plans.get(unit.get("group_id"))
        if not plan or plan["entry_mode"] == "existing_contract":
            continue
        questions = unit["questions"]
        count = len(questions)
        if unit["subject"] != plan["subject"] or (unit.get("group_id") is None
                and count != min(5, max(4, len(plan["probes"]) + 2))):
            raise ValueError("Fach oder Umfang des Lernstarts wurde verändert.")
        expected = _specs(plan, count)
        if not 2 <= count <= 5 or {q["id"] for q in questions} != {q["id"] for q in expected}:
            raise ValueError("Der begrenzte Lernstart wurde nicht vollständig übernommen.")
        by_id = {q["id"]: q for q in questions}
        for spec in expected:
            question = by_id[spec["id"]]
            if spec.get("type") and any(question[key] != spec[key] for key in CORE):
                raise ValueError("Eine geprüfte Voraussetzung wurde verändert.")
            if spec["role"] == "prior_check" and question["type"] not in ("choice", "short"):
                raise ValueError("Die kurze Lernprobe benötigt ein einzelnes Antwortformat.")
        unit["questions"] = [by_id[spec["id"]] for spec in expected]


def guard_entry_context(db, child, payload, sources):
    entry = payload.get("learning_entry")
    if not entry:
        return
    current = []
    for reference in entry["source_refs"]:
        material = db.get(Material, reference["material_id"], populate_existing=True)
        current.append(competences.source_ref(db, material) if material and material.child_id == child.id else None)
    if current != entry["source_refs"] or entry["catalog_version"] != competences.VERSION:
        raise ValueError("Die Quellenfassung des Lernstarts wurde geändert.")
    for plan in entry["units"]:
        if _proof(db, child.id, plan["competence_ids"]) != plan["evidence"]:
            raise ValueError("Neue Antwortbelege haben den Lernstart geändert. Bitte neu auswählen.")
    if any(not competences.resolve_reference(item["reference_id"], item["version"], item["digest"])
           for item in entry["references"]):
        raise ValueError("Die freigegebene Grundlagenregel wurde geändert.")


def remember_generated(db, unit, payload, *, group_id=None):
    entry = payload.get("learning_entry")
    if not entry:
        return
    plan = next((item for item in entry["units"] if item["group_id"] == group_id), None)
    if not plan:
        return
    specs = _specs(plan, len(unit.questions)) if plan["entry_mode"] != "existing_contract" else []
    by_id = {spec["id"]: spec for spec in specs}
    for target in plan["targets"]:
        ref = target["source_ref"]
        key = (ref["material_id"], ref["revision"], target["id"], competences.VERSION)
        if not db.get(CompetenceSource, key):
            db.add(CompetenceSource(material_id=ref["material_id"], source_revision=ref["revision"],
                competence_id=target["id"], catalog_version=competences.VERSION, child_id=unit.child_id,
                excerpt=target["source_excerpt"]))
    from .coaching import source_goals
    sources = [db.get(Material, ref["material_id"]) for ref in plan["source_refs"]]
    goals = source_goals([{"content": competences.source_value(db, source)["content"]} for source in sources], unit.subject, unit.topic)
    for question in unit.questions:
        spec = by_id.get(question["id"], {})
        identifier = spec.get("competence_id")
        if not identifier:
            identifier = verified_math_identity(question, goals)
        if identifier not in plan["competence_ids"]:
            continue
        key = (unit.id, question["id"])
        if not db.get(QuestionCompetence, key):
            db.add(QuestionCompetence(unit_id=unit.id, question_id=question["id"], child_id=unit.child_id,
                competence_id=identifier, catalog_version=competences.VERSION,
                role="prior_check" if spec.get("role") == "prior_check" else "recall" if unit.round_kind in ("check", "spaced_review", "study_recall") else "practice",
                question_digest=competences.question_digest(question), source_refs=plan["source_refs"],
                reference_ids=[spec["reference_id"]] if spec.get("reference_id") else []))
    from .learning_controller import source_state
    memory = db.get(LearningMemory, unit.id)
    if not memory:
        memory = LearningMemory(unit_id=unit.id, child_id=unit.child_id, source_signature=source_state(db, unit)[0],
            working={}, decision={}, revision=0, plan_revision=0)
        db.add(memory)
    # No private answers, generated hints or drafts are copied into the plan.
    memory.working = {**memory.working, "entry_plan": {"version": 1, "catalog_version": entry["catalog_version"],
        "source_refs": plan["source_refs"], "source_signature": competences.fingerprint(plan["source_refs"]),
        "entry_mode": plan["entry_mode"], "competence_ids": plan["competence_ids"],
        "questions": [{"id": spec["id"], "role": spec["role"], "competence_id": spec.get("competence_id")} for spec in specs]}}


def public_path(db, unit, facts=None):
    memory = db.get(LearningMemory, unit.id)
    plan = (memory.working or {}).get("entry_plan") if memory else None
    if not plan:
        return None
    if facts is None:
        from .learning_controller import facts as unit_facts
        facts = unit_facts(db, unit)
    attempts = facts["by_question"]
    def closed(identifier):
        values = attempts.get(identifier, [])
        return bool(values and (values[-1].outcome in ("correct", "uncertain") or len(values) >= 3))
    prior = [item["id"] for item in plan["questions"] if item["role"] == "prior_check"]
    main = [q["id"] for q in unit.questions if q["id"] not in prior]
    shown = any(item.kind == "explanation" for item in facts["activities"])
    proof = _proof(db, unit.child_id, plan["competence_ids"])
    by_id = {row["id"]: row for row in proof}
    steps = []
    for identifier, title, kind, questions, complete in (
        ("prior_check", "Erst selbst probieren", "prior_check", prior, bool(prior) and all(closed(q) for q in prior)),
        ("explanation", "Zusammenhang verstehen", "explanation", [], shown),
        ("practice", "Selbst anwenden", "practice", main, bool(main) and all(closed(q) for q in main)),
        ("review", "Antworten einordnen", "review", [], unit.status == "completed")):
        if kind == "prior_check" and not prior:
            continue
        competence_id = next((item["competence_id"] for item in plan["questions"] if item["id"] in questions and item.get("competence_id")), None)
        evidence = by_id.get(competence_id, {})
        steps.append({"id": identifier, "title": title, "kind": kind, "question_ids": questions,
            "competence_id": competence_id, "status": "completed" if complete else "available",
            "evidence": {"attempt_refs": evidence.get("evidence_refs", []), "status": evidence.get("status", "unknown"),
                "confidence": evidence.get("confidence", "unverified")}})
    current = next((item for item in steps if item["status"] != "completed"), None)
    if current:
        current["status"] = "current"
    return {"version": 1, "catalog_version": plan["catalog_version"], "source_signature": plan["source_signature"],
        "entry_mode": plan["entry_mode"], "steps": steps, "current_step_id": current["id"] if current else None,
        "prerequisites": competences.prerequisite_graph(plan["competence_ids"]),
        "competences": proof, "notice": "Lernschritte sind keine Beherrschungsbewertung. Nur eigene gespeicherte Antworten liefern Belege."}


def entry_action(db, unit, facts):
    path = public_path(db, unit, facts)
    if not path or unit.status != "active":
        return None
    prior = next((step for step in path["steps"] if step["kind"] == "prior_check"), None)
    if prior and prior["status"] == "completed" and path["current_step_id"] == "explanation" and facts["question"]:
        return {"kind": "explain", "phase": "understand", "reason_code": "entry_probe_followup",
            "title": "Jetzt den Zusammenhang ansehen", "reason": "Deine eigenen Antworten sind gespeichert. Schau dir jetzt die Erklärung für die nächste Anwendung an.",
            "expected_result": "Eine Erklärung ansehen, danach selbst weiterüben.", "on_success": "practice", "on_error": "hint"}
    return None
