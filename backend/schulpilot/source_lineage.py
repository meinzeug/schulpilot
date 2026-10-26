"""Literal source provenance and conservative, non-generative learning filters.

A readable/confirmed transcript is not a factual certificate. Original text is
never rewritten. Only a finite exact rational check makes a mathematical claim;
unknown notation remains unknown. All helpers are local and do not call AI.
"""

import ast
import copy
import hashlib
import io
import json
import re
from fractions import Fraction
from types import SimpleNamespace

from PIL import Image
from sqlalchemy import func, select

from .db import Job, LearningUnit, UnitSource, Usage
from .source_lineage_models import SourceImageReceipt, SourceInvalidation, SourceRevision
from .subject_content import SourceBlock

POLICY_VERSION = "literal-safety-2"
PREPROCESS_VERSION = "exif-rgb-max3200-jpeg95-1"
REASONS = {
    "exam_only": "Eine korrigierte Arbeit ist keine allgemeine Lernstoffquelle.",
    "unreadable": "Der Wortlaut ist nicht lesbar.",
    "unconfirmed": "Die Abschrift wurde noch nicht bestätigt.",
    "revision_changed": "Die Quellenfassung wurde geändert.",
    "reading_uncertain": "Mindestens ein Zeichen oder eine Lesestelle ist ungeklärt.",
    "student_work": "Die Schülerrechnung ist noch keine geprüfte fachliche Regel.",
    "visible_annotation": "Eine sichtbare Korrektur, Einfügung oder Streichung muss getrennt geprüft werden.",
    "false_equality": "Diese wörtliche rationale Gleichung ist rechnerisch falsch; sie bleibt im Original erhalten.",
    "unstructured_annotations": "Die Abschrift enthält nicht mehr zuordenbare Quellenmarkierungen.",
}


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    ).hexdigest()


def _number(expression):
    """Bounded rational arithmetic, no eval/names/calls/comparison guessing."""
    expression = expression.strip().replace("−", "-").replace("·", "*").replace("×", "*")
    for old, new in ((r"\cdot", "*"), (r"\times", "*"), (r"\(", ""), (r"\)", ""), (r"\[", ""), (r"\]", "")):
        expression = expression.replace(old, new)
    expression = expression.strip("$").strip()
    expression = re.sub(r"\\(?:d?frac)\{([+-]?\d{1,9})\}\{([+-]?\d{1,9})\}", r"(\1/\2)", expression)
    if not expression or len(expression) > 160 or not re.fullmatch(r"[0-9 .,+*/()\-]+", expression):
        raise ValueError("not bounded arithmetic")
    expression = expression.replace(",", ".")
    tree = ast.parse(expression, mode="eval")
    if len(list(ast.walk(tree))) > 40:
        raise ValueError("too many nodes")

    def value(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            result = Fraction(ast.get_source_segment(expression, node))
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            result = (-1 if isinstance(node.op, ast.USub) else 1) * value(node.operand)
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            left, right = value(node.left), value(node.right)
            if isinstance(node.op, ast.Add):
                result = left + right
            elif isinstance(node.op, ast.Sub):
                result = left - right
            elif isinstance(node.op, ast.Mult):
                result = left * right
            else:
                result = left / right
        else:
            raise ValueError("unknown expression")
        if max(abs(result.numerator), result.denominator) > 10**18:
            raise ValueError("unbounded result")
        return result

    return value(tree.body)


def false_equality(text):
    """Only self-contained numeric equations; never repair or infer variables."""
    for line in text.splitlines():
        terms = line.strip().split("=")
        if not 2 <= len(terms) <= 8:
            continue
        try:
            values = [_number(term) for term in terms]
        except (ValueError, SyntaxError, ZeroDivisionError, OverflowError):
            continue
        if any(left != right for left, right in zip(values, values[1:])):
            return True
    return False


def literal_blocks(material):
    try:
        blocks = [
            SourceBlock.model_validate(value).model_dump(exclude_none=True)
            for value in (material.source_blocks or [])[:80]
        ]
    except (ValueError, TypeError):
        return []
    return blocks if "\n\n".join(block["text"] for block in blocks) == material.content else []


def block_data(material):
    result = []
    for index, block in enumerate(literal_blocks(material)):
        block_id = digest([material.id, material.revision, index, block])[:32]
        result.append(
            {
                **block,
                "block_id": block_id,
                "block_index": index,
                "annotations": [
                    {**mark, "annotation_id": digest([block_id, i, mark])[:32]}
                    for i, mark in enumerate(block.get("annotations", []))
                ],
            }
        )
    return result


def learning_source(db, material, revision=None):
    """Read-only projection: exact eligible block text + explicit exclusions.

    Legacy unmarked text is 'not_assessed', never 'correct'. A missing structured
    reading of a page with warnings cannot silently become learning groundtruth.
    ``db`` is accepted for common callsites; no writes/backfill occur on GET.
    """
    mid, current = material.id, material.revision
    result = {
        "material_id": mid,
        "revision": current,
        "content": "",
        "source_blocks": [],
        "source_refs": [],
        "exclusions": [],
        "factual_status": "not_assessed",
        "policy_version": POLICY_VERSION,
    }
    reason = (
        "exam_only"
        if material.purpose == "exam"
        else "revision_changed"
        if revision is not None and revision != current
        else "unconfirmed"
        if not material.confirmed
        else "unreadable"
        if material.legibility == "unreadable"
        else None
    )
    blocks = literal_blocks(material)
    has_reading_warning = bool(material.uncertainties or any(b.get("reading_uncertainties") for b in blocks))
    reading_confirmed = False
    if has_reading_warning and db is not None and material.confirmed and getattr(material, "confirmation_digest", None):
        confirmation = db.scalar(select(SourceRevision).where(
            SourceRevision.material_id == material.id, SourceRevision.revision == material.revision,
            SourceRevision.cause == "confirmation").order_by(SourceRevision.sequence.desc()).limit(1))
        reading_confirmed = bool(confirmation and confirmation.snapshot == source_snapshot(material)
            and confirmation.receipt.get("reading_resolution") == "explicit_user_confirmation"
            and confirmation.receipt.get("confirmed_literal_digest") == digest(source_snapshot(material)))
    result["reading_status"] = "explicitly_confirmed" if reading_confirmed else "unresolved" if has_reading_warning else "not_reported"
    raw_marks = any(
        isinstance(block, dict)
        and (
            block.get("annotations")
            or block.get("reading_uncertainties")
            or block.get("literal_role") in ("student_work", "annotation")
        )
        for block in material.source_blocks or []
    )
    if not blocks and raw_marks:
        reason = reason or "unstructured_annotations"
    if not blocks and material.content.strip():
        blocks = [
            {
                "kind": "paragraph",
                "text": material.content,
                "literal_role": "unknown",
                "annotations": [],
                "reading_uncertainties": [],
            }
        ]
    for index, block in enumerate(blocks):
        block_id = digest([mid, current, index, block])[:32]
        item = {**block, "block_id": block_id}
        item["annotations"] = [
            {**mark, "annotation_id": digest([block_id, i, mark])[:32]}
            for i, mark in enumerate(block.get("annotations", []))
        ]
        blocked = reason
        if not blocked and not reading_confirmed and (
            block.get("reading_uncertainties")
            or (material.uncertainties and not any(b.get("reading_uncertainties") for b in blocks))
        ):
            blocked = "reading_uncertain"
        if not blocked and false_equality(block["text"]):
            blocked = "false_equality"
        if not blocked and block.get("literal_role") == "student_work":
            blocked = "student_work"
        if not blocked and (
            block.get("literal_role") == "annotation"
            or any(
                mark["kind"] in ("crossout", "insertion", "correction", "comment", "unknown")
                for mark in block.get("annotations", [])
            )
        ):
            blocked = "visible_annotation"
        if blocked:
            result["exclusions"].append({"block_id": block_id, "reason": blocked, "message": REASONS[blocked]})
        else:
            result["source_blocks"].append(item)
            result["source_refs"].append({"material_id": mid, "revision": current, "block_id": block_id})
    result["content"] = "\n\n".join(block["text"] for block in result["source_blocks"])
    if result["exclusions"]:
        result["factual_status"] = "partly_excluded" if result["content"] else "blocked"
    if not blocks and reason:
        result["factual_status"] = "blocked"
        result["exclusions"].append({"block_id": None, "reason": reason, "message": REASONS[reason]})
    return result


def usable_source(db, material, revision=None):
    return bool(material is not None and learning_source(db, material, revision)["content"].strip())


def source_snapshot(material):
    return {
        key: copy.deepcopy(getattr(material, key))
        for key in (
            "subject",
            "topic",
            "content",
            "source_blocks",
            "uncertainties",
            "homework",
            "legibility",
            "confirmed",
            "purpose",
            "image_digest",
        )
    }


def extraction_receipt(db, job, config, image_bytes, result=None):
    from .extraction import OCR_SYSTEM, TranscriptionOutput
    from .material_review import CHECK_SYSTEM

    prompt = CHECK_SYSTEM if job.payload.get("material_check") else OCR_SYSTEM

    width = height = None
    if image_bytes:
        with Image.open(io.BytesIO(image_bytes)) as image:
            width, height = image.size
    usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
    origin = (
        db.get(SourceImageReceipt, (job.payload or {}).get("material_id"))
        if (job.payload or {}).get("material_id")
        else None
    )
    telemetry = getattr(result, "telemetry", None) or {}
    # Whitelist operational scalars: never arbitrary upstream JSON/reasoning.
    metrics = {
        key: telemetry[key]
        for key in ("upstream", "actual_model", "latency_ms", "reasoning_tokens", "cached_tokens", "attempt")
        if key in telemetry and isinstance(telemetry[key], (str, int, type(None)))
    }
    return {
        "version": 1,
        "job_id": job.id,
        "usage_id": usage.id if usage else None,
        "image_digest": hashlib.sha256(image_bytes).hexdigest() if image_bytes else None,
        "width": width,
        "height": height,
        "coordinate_space": "stored_normalized_image_0_1000",
        "preprocessing_version": origin.normalization_version if origin else "historical_unknown",
        "upload_geometry": origin.geometry if origin else None,
        "client_preprocessing": "not_reported",
        "base_prompt_digest": hashlib.sha256(prompt.encode()).hexdigest(),
        "base_schema_digest": digest(TranscriptionOutput.model_json_schema()),
        "provider": config["provider"],
        "model": config["model"],
        "effective_request": getattr(result, "request_receipt", None) or {"status": "not_reported"},
        "configured_max_output_tokens": config.get("max_output_tokens"),
        "metrics": metrics,
        "factual_validation": "finite_exact_rationals_only",
        "policy_version": POLICY_VERSION,
    }


def save_snapshot(db, material, cause, receipt=None, *, allow_empty=False):
    """Immutable (including unconfirmed retry snapshots); caller owns transaction."""
    if not allow_empty and (not material.content or not material.content.strip()):
        return None
    snapshot = source_snapshot(material)
    latest = db.scalar(
        select(SourceRevision)
        .where(SourceRevision.material_id == material.id, SourceRevision.revision == material.revision)
        .order_by(SourceRevision.sequence.desc())
        .limit(1)
    )
    if receipt is None and latest is not None and latest.snapshot == snapshot:
        return latest
    fingerprint = digest({"literal": snapshot, "receipt": receipt or {"origin": "legacy_or_manual"}})
    existing = db.scalar(
        select(SourceRevision).where(
            SourceRevision.material_id == material.id,
            SourceRevision.revision == material.revision,
            SourceRevision.digest == fingerprint,
        )
    )
    if existing:
        return existing
    row = SourceRevision(
        material_id=material.id,
        child_id=material.child_id,
        revision=material.revision,
        sequence=(
            db.scalar(select(func.max(SourceRevision.sequence)).where(SourceRevision.material_id == material.id)) or 0
        )
        + 1,
        digest=fingerprint,
        cause=cause,
        snapshot=snapshot,
        receipt=copy.deepcopy(receipt) or {"version": 1, "origin": "legacy_or_manual", "factual_validation": "not_assessed"},
    )
    db.add(row)
    db.flush()
    return row


def snapshot_data(row):
    return {
        "id": row.id,
        "material_id": row.material_id,
        "revision": row.revision,
        "sequence": row.sequence,
        "digest": row.digest,
        "cause": row.cause,
        "created": row.created,
        "literal": row.snapshot,
        "receipt": row.receipt,
    }


def invalidate_dependents(db, material, previous_revision):
    """Keep attempts/unit text; add a review receipt rather than deleting work."""
    rows = list(
        db.scalars(
            select(LearningUnit).where(
                LearningUnit.child_id == material.child_id,
                (LearningUnit.material_id == material.id)
                | LearningUnit.id.in_(select(UnitSource.unit_id).where(UnitSource.material_id == material.id)),
            )
        )
    )
    for unit in rows:
        if not db.scalar(
            select(SourceInvalidation.id).where(
                SourceInvalidation.unit_id == unit.id,
                SourceInvalidation.material_id == material.id,
                SourceInvalidation.current_revision == material.revision,
            )
        ):
            ref = db.get(UnitSource, (unit.id, material.id))
            db.add(
                SourceInvalidation(
                    material_id=material.id,
                    child_id=material.child_id,
                    unit_id=unit.id,
                    source_revision=ref.revision if ref else previous_revision,
                    current_revision=material.revision,
                    reason="source_revised",
                )
            )


def unit_source_status(db, unit):
    rows = list(
        db.scalars(
            select(SourceInvalidation).where(
                SourceInvalidation.unit_id == unit.id, SourceInvalidation.child_id == unit.child_id
            )
        )
    )
    return {
        "needs_source_review": bool(rows),
        "changed_sources": [
            {
                "material_id": row.material_id,
                "source_revision": row.source_revision,
                "current_revision": row.current_revision,
                "reason": row.reason,
            }
            for row in rows
        ],
    }


def export_sources(db, child_id):
    from .db import Material

    return {
        "source_image_receipts": [
            {
                "material_id": row.material_id,
                "image_digest": row.image_digest,
                "geometry": row.geometry,
                "normalization_version": row.normalization_version,
                "created": row.created,
            }
            for row in db.scalars(select(SourceImageReceipt).join(Material).where(Material.child_id == child_id))
        ],
        "source_revisions": [
            snapshot_data(row)
            for row in db.scalars(
                select(SourceRevision)
                .where(SourceRevision.child_id == child_id)
                .order_by(SourceRevision.material_id, SourceRevision.sequence)
            )
        ],
        "source_invalidations": [
            {
                key: getattr(row, key)
                for key in ("unit_id", "material_id", "source_revision", "current_revision", "reason", "created")
            }
            for row in db.scalars(select(SourceInvalidation).where(SourceInvalidation.child_id == child_id))
        ],
    }


def crop_snapshot(row):
    return SimpleNamespace(content=row.snapshot["content"], source_blocks=row.snapshot["source_blocks"])


def purge_diagnostic_outputs(db, material_ids):
    """Call before material deletion; only our bounded private diagnostic files."""
    from .config import settings
    from .source_evaluation import WORK_ID
    from .source_lineage_models import SourceEvaluationCase, SourceEvaluationGrant

    directory = settings.data_dir / "operator-diagnostics" / WORK_ID
    selected = set(material_ids)
    for row in db.scalars(select(SourceEvaluationCase).where(SourceEvaluationCase.material_id.in_(selected))):
        (directory / (row.id + ".json")).unlink(missing_ok=True)
        if row.job_id and (job := db.get(Job, row.job_id)):
            job.payload = {"operator_evaluation": row.id, "diagnostic_only": True, "source_removed": True}
            if job.status == "operator_held":
                job.status = "failed"
                job.error = "Die Diagnosequelle wurde entfernt. Kein automatischer Wiederholungsaufruf."
    for grant in db.scalars(select(SourceEvaluationGrant)):
        remaining = [source for source in grant.sources if source["material_id"] not in selected]
        if remaining != grant.sources:
            if remaining:
                grant.sources = remaining
            else:
                db.delete(grant)


def expire_diagnostic_outputs(db, cutoff):
    from .config import settings
    from .source_evaluation import WORK_ID
    from .source_lineage_models import SourceEvaluationCase, SourceEvaluationGrant

    directory = settings.data_dir / "operator-diagnostics" / WORK_ID
    for row in db.scalars(select(SourceEvaluationCase).where(SourceEvaluationCase.created < cutoff)):
        (directory / (row.id + ".json")).unlink(missing_ok=True)
    # A grant is authority only, never a financial receipt. Charges/holds remain.
    for row in db.scalars(select(SourceEvaluationGrant).where(SourceEvaluationGrant.expires < cutoff)):
        db.delete(row)
