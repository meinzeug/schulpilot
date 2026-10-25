import hashlib
import io
import re

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from PIL import Image, ImageFilter, ImageOps, ImageStat, UnidentifiedImageError
from sqlalchemy import or_, select, update

from . import schemas as s
from .config import runtime_settings, settings
from .db import Assignment, Child, Family, Job, LearningUnit, Material, ProviderConfig, UnitSource, get_db, uid
from .fixtures import FIXTURE_ID, LIVE_FIXTURE_IDS, worksheet
from .learning import material_data as learning_material_data
from .learning import record
from .providers import ProviderError, config_for_function, external_allowed, reserve
from .security import authenticated, child_access, rate_limit

router = APIRouter(tags=["Materialien und KI-Aufträge"])
Image.MAX_IMAGE_PIXELS = 16_000_000


def material_data(material):
    value = learning_material_data(material)
    if material.purpose == "exam":
        value.update(vocabulary_preview=None, task_preview=[], confirmed_tasks=[], supports_task_confirmation=False)
    return value


@router.post("/children/{child_id}/materials/synthetic-fixture", status_code=201)
def synthetic_fixture(child_id: str, p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    if not db.get(Family, child.family_id).synthetic:
        raise HTTPException(403, "Der externe KI-Test ist ausschließlich im synthetischen Testraum verfügbar.")
    try:
        external_allowed(config_for_function(db.get(ProviderConfig, 1), "extract"), image=True, synthetic_fixture=True)
    except ProviderError as error:
        raise HTTPException(503, str(error)) from None
    rate_limit(db, "fixture:" + p.user.id, 3, 3600)
    directory = settings.data_dir / "uploads"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = uid() + ".jpg"
    destination = directory / path
    destination.write_bytes(worksheet())
    destination.chmod(0o600)
    material = Material(
        child_id=child.id, title="Synthetisches KI-Testblatt: Brüche", path=path, synthetic=True, fixture_id=FIXTURE_ID
    )
    db.add(material)
    record(db, child.id, "material_uploaded", {"synthetic_fixture": FIXTURE_ID})
    try:
        db.commit()
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return material_data(material)


@router.post("/children/{child_id}/materials", status_code=201)
def upload(
    child_id: str,
    file: UploadFile = File(...),
    school_day_id: str | None = None,
    purpose: str = "notebook",
    idempotency_key: str | None = Header(None),
    p=Depends(authenticated),
    db=Depends(get_db),
    exam_id: str | None = None,
    exam_revision: int | None = None,
):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    if purpose not in ("notebook", "homework", "exam") or (purpose in ("homework", "exam") and school_day_id):
        raise HTTPException(422, "Bitte einen gültigen Fotobereich wählen.")
    if purpose == "exam":
        from .exam_review import access

        if not exam_id or type(exam_revision) is not int or exam_revision < 1:
            raise HTTPException(422, "Bitte das Foto einer aktuellen schriftlichen Arbeit zuordnen.")
        exam, owner = access(db, p, exam_id, write=True)
        if owner.id != child.id:
            raise HTTPException(404, "Arbeit nicht gefunden.")
    elif exam_id is not None or exam_revision is not None:
        raise HTTPException(422, "Diese Fotozuordnung gehört zu einer schriftlichen Arbeit.")
    if purpose in ("homework", "exam") and not isinstance(idempotency_key, str):
        raise HTTPException(422, "Für dieses Foto wird ein Upload-Schlüssel benötigt.")
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(
            403,
            "Der synthetische Testraum verwendet nur das mitgelieferte Beispiel. Bitte hier keine echten Kinderfotos hochladen.",
        )
    site = runtime_settings(db)
    if not (site.real_data_approved and site.privacy_evidence):
        raise HTTPException(503, "Materialimport echter Daten ist bis zur dokumentierten Datenschutzfreigabe gesperrt.")
    if idempotency_key is not None and not re.fullmatch(r"[A-Za-z0-9_-]{16,80}", idempotency_key):
        raise HTTPException(422, "Bitte einen gültigen Upload-Schlüssel verwenden.")
    raw = file.file.read(10 * 1024 * 1024 + 1)
    if len(raw) > 10 * 1024 * 1024:
        raise HTTPException(413, "Das Bild darf höchstens 10 MB groß sein.")
    try:
        with Image.open(io.BytesIO(raw)) as source:
            if source.format not in ("JPEG", "PNG", "WEBP"):
                raise ValueError("format")
            if source.width * source.height > Image.MAX_IMAGE_PIXELS:
                raise ValueError("dimensions")
            upload_geometry = {"input_width": source.width, "input_height": source.height, "input_bytes": len(raw)}
            image = ImageOps.exif_transpose(source).convert("RGB")
            image.thumbnail((3200, 3200))
            warnings = []
            if min(image.size) < 600:
                warnings.append("Das Foto ist klein. Bitte prüfen, ob der Text gut lesbar ist.")
            probe = image.copy()
            probe.thumbnail((320, 320))
            probe = probe.convert("L").filter(ImageFilter.FIND_EDGES)
            if (
                min(probe.size) > 4
                and ImageStat.Stat(probe.crop((2, 2, probe.width - 2, probe.height - 2))).var[0] < 70
            ):
                warnings.append(
                    "Das Foto enthält wenig erkennbare Details und könnte unscharf oder leer sein. Bitte prüfen."
                )
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=95)  # EXIF/GPS/XMP are discarded.
            upload_geometry.update(width=image.width, height=image.height, output_bytes=len(output.getvalue()), orientation="baked")
    except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            422, "Bitte ein gültiges JPEG-, PNG- oder WebP-Bild mit höchstens 16 Megapixeln wählen."
        ) from None
    if len(output.getvalue()) > 10 * 1024 * 1024:
        raise HTTPException(413, "Der bereinigte Fotoexport überschreitet10 MB. Bitte einen kleineren gut lesbaren Ausschnitt abgeben.")
    digest = hashlib.sha256(output.getvalue()).hexdigest()
    # One lock per child also serializes replay checks, day state and file ownership.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    if idempotency_key:
        existing = db.scalar(
            select(Material).where(Material.child_id == child.id, Material.upload_key == idempotency_key)
        )
        if existing:
            if existing.image_digest != digest or existing.school_day_id != school_day_id or existing.purpose != purpose:
                raise HTTPException(409, "Dieser Upload-Schlüssel gehört bereits zu einem anderen Foto.")
            if purpose == "exam":
                from .exam_review import validate_upload

                validate_upload(db, p, child, exam_id, exam_revision, existing=existing)
            return material_data(existing)
    if purpose == "exam":
        from .exam_review import validate_upload

        validate_upload(db, p, child, exam_id, exam_revision)
    rate_limit(db, "upload:" + p.user.id, 30, 3600, commit=False)
    page_number = None
    if school_day_id:
        from .school_day import append_page

        _, page_number = append_page(db, p, child, school_day_id)
    duplicate = db.scalar(
        select(Material.id).where(
            Material.child_id == child.id, Material.school_day_id == school_day_id, Material.image_digest == digest
        )
    )
    if duplicate:
        warnings.append(
            "Ein identisches Foto ist bereits gespeichert. Bitte prüfen und eine doppelte Seite gegebenenfalls entfernen."
        )
    directory = settings.data_dir / "uploads"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = uid() + ".jpg"
    destination = directory / path
    destination.write_bytes(output.getvalue())
    destination.chmod(0o600)
    material = Material(
        purpose=purpose,
        child_id=child.id,
        school_day_id=school_day_id,
        page_number=page_number,
        upload_key=idempotency_key,
        image_digest=digest,
        quality_warnings=warnings,
        title=f"Heftseite {page_number}" if page_number else "Unterrichtsmaterial",
        path=path,
        synthetic=False,
    )
    try:
        db.add(material)
        db.flush()
        from .source_lineage import PREPROCESS_VERSION
        from .source_lineage_models import SourceImageReceipt

        db.add(SourceImageReceipt(material_id=material.id, image_digest=digest, geometry=upload_geometry,
                                  normalization_version=PREPROCESS_VERSION))
        if purpose == "exam":
            from .exam_review import attach_uploaded

            db.flush()
            attach_uploaded(db, p, child, material, exam_id, exam_revision)
        record(db, child.id, "material_uploaded")
        db.commit()
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return material_data(material)


def get_material(db, p, material_id, write=False):
    material = db.get(Material, material_id)
    if not material:
        raise HTTPException(404, "Material nicht gefunden.")
    child = child_access(db, p, material.child_id, write=write and p.user.role == "parent")
    if write:
        db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
        material = db.get(Material, material_id, populate_existing=True)
        if not material:
            raise HTTPException(404, "Material nicht gefunden.")
    return material, child


@router.get("/materials/{material_id}/image")
def image(material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    material, _ = get_material(db, p, material_id)
    if not material.path:
        raise HTTPException(404, "Dieses synthetische Beispiel hat keinen Foto-Upload.")
    path = settings.data_dir / "uploads" / material.path
    if not path.is_file():
        raise HTTPException(404, "Bild nicht mehr vorhanden.")
    return FileResponse(
        path, media_type="image/jpeg", headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
    )


@router.get("/materials/{material_id}")
def material_view(material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .material_tasks import duplicate_sources

    material, _ = get_material(db, p, material_id)
    extraction = db.scalar(select(Job).where(Job.child_id == material.child_id, Job.kind == "extract",
        Job.payload["material_id"].as_string() == material.id).order_by(Job.created.desc(), Job.id.desc()).limit(1))
    linked_exam = None
    if material.purpose == "exam":
        from .exam_review_models import ExamReviewPage
        linked_exam = db.scalar(select(ExamReviewPage.exam_id).where(ExamReviewPage.material_id == material.id))
    from .source_lineage import block_data, learning_source

    return material_data(material) | {"source_learning": learning_source(db, material), "source_block_refs": block_data(material), "supports_source_history": True} | ({"exam_id": linked_exam} if material.purpose == "exam" else {}) | {"duplicate_candidates": duplicate_sources(db, material),
        "has_image": bool(material.path), "fixed_example": bool(material.fixture_id),
        "processing_job": ({"id": extraction.id, "kind": extraction.kind, "status": extraction.status,
                            "error": extraction.error, "error_code": extraction.error_code} if extraction else None)}


@router.get("/materials/{material_id}/revisions")
def source_history(material_id: str, offset: int = 0, p=Depends(authenticated), db=Depends(get_db)):
    from .source_lineage_models import SourceRevision
    material, _ = get_material(db, p, material_id)
    if not 0 <= offset <= 100000:
        raise HTTPException(422, "Bitte eine gültige Quellenposition verwenden.")
    rows = list(db.scalars(select(SourceRevision).where(SourceRevision.material_id == material.id,
        SourceRevision.child_id == material.child_id).order_by(SourceRevision.sequence.desc()).offset(offset).limit(21)))
    return {"items": [{"id": row.id, "revision": row.revision, "sequence": row.sequence, "digest": row.digest,
        "cause": row.cause, "created": row.created} for row in rows[:20]],
        "next_offset": offset + 20 if len(rows) > 20 else None}


@router.get("/materials/{material_id}/revisions/{snapshot_id}")
def source_history_item(material_id: str, snapshot_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .source_lineage import snapshot_data
    from .source_lineage_models import SourceRevision
    material, _ = get_material(db, p, material_id)
    row = db.get(SourceRevision, snapshot_id)
    if not row or row.material_id != material.id or row.child_id != material.child_id:
        raise HTTPException(404, "Quellenfassung nicht gefunden.")
    return snapshot_data(row)


@router.get("/materials/{material_id}/figures/{block_index}")
@router.get("/materials/{material_id}/regions/{block_index}")
def source_figure(material_id: str, block_index: int, revision: int,
                  p=Depends(authenticated), db=Depends(get_db)):
    material, _ = get_material(db, p, material_id)
    if material.revision != revision:
        raise HTTPException(409, "Die Heftseite wurde geändert. Bitte die aktuelle Seite öffnen.")
    blocks = material_data(material)["source_blocks"]
    if not 0 <= block_index < min(len(blocks), 80) or not material.path:
        raise HTTPException(404, "Die Abbildung ist nicht mehr verfügbar.")
    region = blocks[block_index].get("image_region")
    if not region:
        raise HTTPException(404, "Diesen Abschnitt findest du im vollständigen Heftfoto.")
    path = settings.data_dir / "uploads" / material.path
    if not path.is_file():
        raise HTTPException(404, "Das Heftfoto ist nicht mehr verfügbar.")
    try:
        with Image.open(path) as original:
            # A small margin protects labels against approximate OCR bounds.
            bounds = (max(0, region["left"] - 12), max(0, region["top"] - 12),
                      min(1000, region["right"] + 12), min(1000, region["bottom"] + 12))
            box = (bounds[0] * original.width // 1000, bounds[1] * original.height // 1000,
                   (bounds[2] * original.width + 999) // 1000, (bounds[3] * original.height + 999) // 1000)
            crop = original.crop(box).convert("RGB")
            crop.thumbnail((1600, 2000))
            output = io.BytesIO()
            crop.save(output, format="JPEG", quality=92)
    except (OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(422, "Bitte die Abbildung im vollständigen Heftfoto ansehen.") from None
    # Derived on demand from authenticated original pixels; no disk copy,
    # provider call, progress write, or public image cache.
    return Response(output.getvalue(), media_type="image/jpeg",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})


@router.get("/materials/{material_id}/source-blocks/{block_id}/image")
def source_block_image(material_id: str, block_id: str, revision: int,
                       p=Depends(authenticated), db=Depends(get_db)):
    from .source_lineage import block_data
    material, _ = get_material(db, p, material_id)
    if material.revision != revision:
        raise HTTPException(409, "Die Quellenfassung wurde geändert. Bitte die aktuelle Seite öffnen.")
    block = next((row for row in block_data(material) if row["block_id"] == block_id), None)
    if not block:
        raise HTTPException(404, "Quellenabschnitt nicht gefunden.")
    return source_figure(material_id, block["block_index"], revision, p, db)


@router.post("/materials/{material_id}/task-preview")
def task_preview(material_id: str, data: s.MaterialConfirm, p=Depends(authenticated), db=Depends(get_db)):
    from .material_tasks import duplicate_sources, preview

    material, _ = get_material(db, p, material_id)
    if data.revision is not None and data.revision != material.revision:
        raise HTTPException(409, "Die Seite wurde geändert. Bitte die aktuelle Seite neu laden.")
    if material.purpose == "exam":
        return {"items": [], "duplicates": []}
    return {"items": preview(data.content, data.homework, material.task_decisions), "duplicates": duplicate_sources(db, material)}


@router.put("/materials/{material_id}/confirm")
def confirm(material_id: str, data: s.MaterialConfirm, p=Depends(authenticated), db=Depends(get_db)):
    from . import material_tasks, material_vocabulary

    material, child = get_material(db, p, material_id)
    child_access(db, p, child.id, write=p.user.role == "parent")
    lock_material_units(db, child.id, material_id)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    material = db.get(Material, material_id, populate_existing=True)
    if not material:
        raise HTTPException(404, "Heftseite nicht mehr vorhanden.")
    if material.purpose == "exam" and (data.task_decisions or data.vocabulary):
        raise HTTPException(422, "Aus einer korrigierten Arbeit werden keine Hausaufgaben oder Wörter übernommen.")
    confirmation_digest = material_tasks.fingerprint(data.model_dump(mode="json", exclude={"revision"}))
    if (material.confirmed and material.confirmation_digest == confirmation_digest
            and all(getattr(data, key) == getattr(material, key) for key in ("subject", "topic", "content", "homework"))):
        from .source_lineage import digest as source_digest
        from .source_lineage import save_snapshot, source_snapshot

        # An explicit replay can record the already supplied reading consent
        # for a legacy page; it never changes text, revision or assessments.
        from .source_lineage_models import SourceRevision

        current = source_snapshot(material)
        existing_confirmation = db.scalar(select(SourceRevision).where(
            SourceRevision.material_id == material.id, SourceRevision.revision == material.revision,
            SourceRevision.cause == "confirmation").order_by(SourceRevision.sequence.desc()).limit(1))
        if not (existing_confirmation and existing_confirmation.snapshot == current
                and existing_confirmation.receipt.get("reading_resolution") == "explicit_user_confirmation"
                and existing_confirmation.receipt.get("confirmed_literal_digest") == source_digest(current)):
            save_snapshot(db, material, "confirmation", {"version": 1,
                "origin": "explicit_transcript_confirmation", "factual_validation": "not_assessed",
                "reading_resolution": "explicit_user_confirmation", "confirmed_literal_digest": source_digest(current)})
            db.commit()
        return material_data(material)
    if data.revision is not None and data.revision != material.revision:
        # A lost response can be replayed without another source/item revision.
        if (data.vocabulary and data.vocabulary.revision == data.revision and material.confirmed
                and material.revision == data.revision + 1
                and all(getattr(data, k) == getattr(material, k) for k in ("subject", "topic", "content", "homework"))):
            word_data = data.vocabulary.model_copy(update={"revision": material.revision})
            result = material_vocabulary.transfer(db, p, child, material, word_data)
            db.commit()
            return material_data(material) | {"vocabulary_transfer": result}
        raise HTTPException(409, "Diese Heftseite wurde inzwischen geändert. Bitte die aktuelle Seite neu laden.")
    if data.vocabulary and data.vocabulary.revision != material.revision:
        raise HTTPException(409, "Die Wortpaare gehören zu einer anderen Seitenrevision.")
    if p.user.role == "child" and material.confirmed:
        raise HTTPException(
            403,
            "Bereits bestätigten Lernstoff und notierte Hausaufgaben passen deine Eltern an. Du kannst eine Änderung im Familienbereich vorschlagen.",
        )
    if material.status not in ("review", "confirmed"):
        raise HTTPException(409, "Bitte zuerst die Materialerkennung abschließen.")
    if material.fixture_id:
        if any(getattr(data, k) != getattr(material, k) for k in ("subject", "topic", "content", "homework")):
            raise HTTPException(
                422,
                "Das feste KI-Testblatt erlaubt keine freien Texteingaben. Bitte den erkannten Beispielstoff bestätigen oder den Test abbrechen.",
            )
    elif material.synthetic:
        from .synthetic import CONTENT

        if data.subject != "Mathematik" or data.topic != "Brüche" or data.content != CONTENT or data.homework:
            raise HTTPException(
                422,
                "Das synthetische Beispiel hat einen festen Beispieltext ohne notierte Hausaufgaben. Freie Eingaben sind hier nicht als KI-Demo auswertbar.",
            )
    from .source_lineage import invalidate_dependents, save_snapshot

    previous_revision = material.revision
    before_source = save_snapshot(db, material, "before_confirmation")
    source_changed = material.confirmed and any(getattr(data, k) != getattr(material, k) for k in ("subject", "topic", "content", "homework"))
    if data.content != material.content:
        # A corrected text invalidates advisory OCR roles; never reuse stale classification.
        material.source_blocks = []
    for key in ("subject", "topic", "content", "homework"):
        setattr(material, key, getattr(data, key))
    # Transcription confirmation is not a subject-quality certificate. Keep
    # unresolved OCR warnings in sources and subsequent generator payloads.
    material.revision += 1
    material.confirmed = True
    material.confirmation_digest = confirmation_digest
    material.status = "confirmed"
    from .source_lineage import digest as source_digest
    from .source_lineage import source_snapshot

    save_snapshot(db, material, "confirmation", {"version": 1, "origin": "explicit_transcript_confirmation",
        "previous_snapshot_id": before_source.id if before_source else None,
        "factual_validation": "not_assessed", "reading_resolution": "explicit_user_confirmation",
        "confirmed_literal_digest": source_digest(source_snapshot(material))})
    if source_changed:
        invalidate_dependents(db, material, previous_revision)
    if source_changed:
        from .learning_controller import observe

        db.flush()
        units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child.id,
            (LearningUnit.material_id == material.id) | LearningUnit.id.in_(
                select(UnitSource.unit_id).where(UnitSource.material_id == material.id))).order_by(LearningUnit.id)))
        for unit in units:
            observe(db, unit, "material_revised", "source:" + material.id + ":" + str(material.revision),
                ["material:" + material.id + ":" + str(material.revision)])
    tasks = ({"added": 0, "duplicates": 0, "unplanned": 0} if material.purpose == "exam" else
             material_tasks.apply_decisions(db, material, child, data.task_decisions, source_changed=source_changed))
    material.task_decisions = [row.model_dump(mode="json") for row in data.task_decisions]
    record(
        db,
        material.child_id,
        "material_confirmed",
        {"subject": material.subject, "topic": material.topic, "homework_count": len(data.homework)},
    )
    words = None
    if data.vocabulary and (data.vocabulary.selections is not None or material_vocabulary.preview(material.subject, material.topic, material.content, material.source_blocks)):
        words = material_vocabulary.transfer(db, p, child, material,
            data.vocabulary.model_copy(update={"revision": material.revision}))
    db.commit()
    return material_data(material) | {"task_transfer": tasks} | ({"vocabulary_transfer": words} if words is not None else {})


@router.get("/materials/{material_id}/vocabulary")
def material_words_status(material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    from .material_vocabulary import source_status

    material, _ = get_material(db, p, material_id)
    if material.purpose == "exam":
        return {"confirmed_words": 0, "review_words": 0, "unpaired_lines": 0, "imports": []}
    return source_status(db, material)


@router.post("/materials/{material_id}/vocabulary-preview")
def material_words_preview(material_id: str, data: s.MaterialVocabularyPreview,
                           p=Depends(authenticated), db=Depends(get_db)):
    from .material_vocabulary import preview

    material, _ = get_material(db, p, material_id)
    return {"preview": None if material.purpose == "exam" else preview(data.subject, data.topic, data.content)}


@router.post("/materials/{material_id}/vocabulary")
def material_words(material_id: str, data: s.MaterialWords, p=Depends(authenticated), db=Depends(get_db)):
    from .material_vocabulary import transfer

    material, child = get_material(db, p, material_id, True)
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    material = db.get(Material, material_id, populate_existing=True)
    if not material:
        raise HTTPException(404, "Heftseite nicht mehr vorhanden.")
    if material.purpose == "exam":
        raise HTTPException(409, "Die alte Antwort aus einer Arbeit ist keine bestätigte Vokabelquelle.")
    result = transfer(db, p, child, material, data)
    db.commit()
    return result


@router.delete("/materials/{material_id}")
def delete_material(material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    material, child = get_material(db, p, material_id)
    if p.user.role == "child" and material.school_day_id and not material.confirmed:
        # The same day/source/preparation checks apply from either UI entry.
        from .school_day import remove_page

        return remove_page(material.school_day_id, material.id, p=p, db=db)
    child_access(db, p, child.id, write=p.user.role == "parent")
    # Older clients promise that answers survive. Require the new counted
    # preview/confirmation whenever removal also affects saved learning rounds.
    from .material_actions import delete_rows, ensure_idle, remove_files, snapshot
    from .unit_erasure import linked_ids

    original_snapshot = snapshot([material])
    lock_material_units(db, child.id, material_id)
    material, child = get_material(db, p, material_id, True)
    if snapshot([material]) != original_snapshot:
        raise HTTPException(409, "Die Seite wurde inzwischen geändert. Bitte neu laden und erneut auswählen.")
    ensure_idle(db, child.id)
    if linked_ids(db, child.id, [material_id]):
        raise HTTPException(409, "Diese Seite hat verknüpfte Übungen. Bitte die App aktualisieren und die Löschvorschau in deinen Heften verwenden.")
    paths = delete_rows(db, child, [material])
    db.commit()
    remove_files(paths)
    return {"message": "Heftseite und Foto gelöscht."}


def lock_material_units(db, child_id, material_id):
    """Keep material deletion in the same Unit -> Child lock order as answers."""
    list(
        db.scalars(
            select(LearningUnit)
            .where(LearningUnit.child_id == child_id,
                   or_(LearningUnit.material_id == material_id, LearningUnit.id.in_(
                       select(UnitSource.unit_id).where(UnitSource.material_id == material_id))))
            .order_by(LearningUnit.id)
            .with_for_update()
        )
    )


def enqueue(db, p, child, kind, payload, idempotency, *, commit=True):
    if kind in ("unit", "package") and "labs-v1" in getattr(p.session, "request_capabilities", ()):
        payload = {**payload, "labs_enabled": True}
    if not idempotency or len(idempotency) > 80:
        raise HTTPException(422, "Ein eindeutiger Idempotency-Key (max. 80 Zeichen) ist erforderlich.")
    key = p.user.id + ":" + idempotency
    # Use the same lock order as the multi-page wizard and its worker.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    payload = dict(payload)
    if payload.get("notebook_practice"):
        from .notebook_practice import guard

        guard(db, child, payload)
    if payload.get("material_id"):
        payload["material_revision"] = db.get(Material, payload["material_id"]).revision
    if payload.get("assignment_id"):
        payload["assignment_revision"] = db.get(Assignment, payload["assignment_id"]).revision
    existing = db.scalar(select(Job).where(Job.idempotency == key))
    if existing:
        comparable = {k: v for k, v in existing.payload.items() if k not in ("controller_guard", "learning_entry_enabled", "labs_enabled")}
        payload_comparable = {k: v for k, v in payload.items() if k not in ("learning_entry_enabled", "labs_enabled")}
        if existing.child_id != child.id or existing.kind != kind or comparable != payload_comparable:
            raise HTTPException(409, "Dieser Anfrageschlüssel wurde bereits für einen anderen Auftrag verwendet.")
        return {"id": existing.id, "status": existing.status}
    if kind in ("unit", "package"):
        from .source_lineage import usable_source

        source_ids = [row["id"] for row in payload.get("sources", [])] or ([payload["material_id"]] if payload.get("material_id") else [])
        source_pages = [db.get(Material, identifier, populate_existing=True) for identifier in source_ids]
        if source_pages and not any(material and material.child_id == child.id and usable_source(db, material) for material in source_pages):
            raise HTTPException(409, "Die gewählten Heftseiten enthalten noch keine verwendbare Lehrgrundlage. Bitte unsichere oder fehlerhafte Stellen zuerst prüfen.")
    rate_limit(db, "job:" + p.user.id, 30, 60, commit=False)
    # Atomically limit each child to one pending paid operation.
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Für dieses Kind wird bereits ein Auftrag verarbeitet.")
    job = Job(id=uid(), child_id=child.id, kind=kind, payload=payload, idempotency=key)
    db.add(job)
    db.flush()
    material = db.get(Material, payload.get("material_id")) if payload.get("material_id") else None
    synthetic = bool(material and material.synthetic)
    if synthetic and not material.fixture_id:
        if kind == "extract":
            raise HTTPException(
                409, "Das Beispiel wurde bereits synthetisch vorbereitet. Es wurde keine Bilderkennung ausgeführt."
            )
    else:
        family = db.get(Family, child.family_id)
        reserve(
            db,
            family,
            child.id,
            job.id,
            kind,
            synthetic_fixture=bool(material and material.fixture_id in LIVE_FIXTURE_IDS and family.synthetic),
        )
    if commit:
        db.commit()
    return {"id": job.id, "status": job.status}


@router.post("/materials/{material_id}/extract", status_code=202)
def extract(
    material_id: str,
    idempotency: str = Header(alias="Idempotency-Key", default=""),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    material, child = get_material(db, p, material_id, True)
    if material.purpose == "exam":
        raise HTTPException(409, "Bitte Arbeitsfotos über die gemeinsame Fotoabgabe lesen lassen.")
    if material.confirmed:
        raise HTTPException(409, "Bestätigtes Material wird nicht erneut überschrieben.")
    return enqueue(db, p, child, "extract", {"material_id": material.id}, idempotency)


@router.post("/children/{child_id}/units", status_code=202)
def create_unit(
    child_id: str,
    data: s.UnitCreate,
    idempotency: str = Header(alias="Idempotency-Key", default=""),
    p=Depends(authenticated),
    db=Depends(get_db),
    capabilities: str | None = Header(None, alias="X-Schulpilot-Capabilities"),
    account: str = Header(default="", alias="X-Schulpilot-Account"),
):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    if data.notebook_sources is not None and account != p.user.id:
        raise HTTPException(409, "Der angemeldete Zugang wurde geändert. Bitte neu laden.")
    material_id = data.material_id
    review_sources = []
    notebook_selection = None
    if data.notebook_sources is not None:
        from .notebook_practice import selection

        notebook_selection = selection(db, child, material_id,
            [ref.model_dump() for ref in data.notebook_sources], data.question_count)
        review_sources = notebook_selection["sources"]
    if data.assignment_id:
        assignment = db.get(Assignment, data.assignment_id)
        if not assignment or assignment.child_id != child.id:
            raise HTTPException(404, "Lernauftrag nicht gefunden.")
        if assignment.source_status != "confirmed":
            raise HTTPException(409, "Bitte den Auftrag nach der Quellenänderung zuerst prüfen.")
        from .learning import local_day

        if assignment.scheduled_for and assignment.scheduled_for > local_day(child).isoformat():
            raise HTTPException(
                409, f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
            )
        if assignment.material_id:
            material_id = assignment.material_id
        if assignment.source_revisions:
            for ref in assignment.source_revisions:
                source = db.get(Material, ref["id"])
                if not source or source.child_id != child.id or not source.confirmed or source.revision != ref["revision"]:
                    raise HTTPException(409, "Die Auftragsquellen wurden geändert. Bitte das Lernziel zuerst prüfen.")
            review_sources = assignment.source_revisions
    if data.review_of:
        previous = db.get(LearningUnit, data.review_of)
        if not previous or previous.child_id != child.id or previous.status != "completed":
            raise HTTPException(404, "Abgeschlossene Lerneinheit nicht gefunden.")
        from .coaching import root_and_units

        if any(u.status != "completed" for u in root_and_units(db, previous)[1]):
            raise HTTPException(409, "Für diese Lernfolge steht bereits eine Runde bereit. Bitte dort fortsetzen.")
        material_id = previous.material_id
        for source_id in db.scalars(
            select(UnitSource.material_id)
            .join(Material, Material.id == UnitSource.material_id)
            .where(UnitSource.unit_id == previous.id)
            .order_by(Material.page_number, Material.id)
        ):
            source = db.get(Material, source_id)
            if not source or source.child_id != child.id or not source.confirmed:
                raise HTTPException(409, "Bitte die Quellen der Wiederholung zuerst gemeinsam prüfen.")
            review_sources.append({"id": source.id, "revision": source.revision})
        if sum(len(db.get(Material, source["id"]).content) for source in review_sources) > 60_000:
            raise HTTPException(422, "Die Quellen sind für eine gemeinsame Wiederholung zu umfangreich.")
    if material_id:
        material = db.get(Material, material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Material nicht gefunden.")
        if material.purpose == "exam":
            raise HTTPException(409, "Für neue Übungen bitte bestätigte Heftseiten aus der Arbeitsbesprechung auswählen.")
        if not material.confirmed:
            raise HTTPException(409, "Bitte den erkannten Stoff und unsichere Stellen zuerst bestätigen.")
        if material.fixture_id and data.assignment_id:
            raise HTTPException(
                422,
                "Der feste KI-Test verarbeitet keine frei eingegebenen Elternaufträge. Bitte die Testeinheit ohne zusätzlichen Auftrag starten.",
            )
        if material.synthetic and data.assignment_id:
            assignment = db.get(Assignment, data.assignment_id)
            if assignment.subject != "Mathematik" or "br" not in assignment.topic.lower():
                raise HTTPException(
                    422,
                    "Die synthetische Übungsquelle unterstützt nur Brüche. Für andere Themen ist ein freigegebener KI-Anbieter erforderlich.",
                )
        if material.school_day_id and not review_sources:
            review_sources = [
                {"id": m.id, "revision": m.revision}
                for m in db.scalars(
                    select(Material)
                    .where(
                        Material.child_id == child.id,
                        Material.school_day_id == material.school_day_id,
                        Material.confirmed.is_(True),
                    )
                    .order_by(Material.page_number, Material.id)
                )
                if m.subject.casefold() == material.subject.casefold()
            ]
            if sum(len(db.get(Material, source["id"]).content) for source in review_sources) > 60_000:
                raise HTTPException(422, "Die zusammengehörigen Seiten sind für eine Einheit zu umfangreich.")
    elif not data.assignment_id:
        raise HTTPException(422, "Bitte bestätigtes Material oder einen Elternauftrag auswählen.")
    payload = {"material_id": material_id, "assignment_id": data.assignment_id, "review_of": data.review_of,
        "learning_entry_enabled": isinstance(capabilities, str) and "learning-entry-v1" in capabilities.split(",")}
    if data.review_of:
        from .coaching import progress

        payload["learning_root_id"] = previous.learning_root_id or previous.id
        payload["not_before"] = progress(db, previous)["next_review"]
        # Continue the original binding goal; the child cannot replace it.
        payload["assignment_id"] = previous.assignment_id
    if review_sources:
        payload["sources"] = review_sources
    if notebook_selection:
        payload["notebook_practice"] = notebook_selection["notebook_practice"]
    return enqueue(db, p, child, "unit", payload, idempotency)


@router.get("/jobs/{job_id}")
def job_view(job_id: str, p=Depends(authenticated), db=Depends(get_db)):
    job = db.get(Job, job_id)
    if not job:
        raise HTTPException(404, "Auftrag nicht gefunden.")
    child_access(db, p, job.child_id)
    return {
        "id": job.id,
        "kind": job.kind,
        "material_id": job.payload.get("material_id") if job.kind == "extract" else None,
        "status": job.status,
        "result": job.result,
        "error": job.error,
        "error_code": job.error_code,
        "attempts": job.attempts,
    }


# Explicit notebook operations share the existing authenticated material API.
from . import material_actions  # noqa: E402

router.add_api_route("/children/{child_id}/materials/delete-preview", material_actions.delete_preview, methods=["POST"])
router.add_api_route("/children/{child_id}/materials/bulk-delete", material_actions.bulk_delete, methods=["POST"])
router.add_api_route("/materials/{material_id}/reprocess", material_actions.reprocess, methods=["POST"], status_code=202)
