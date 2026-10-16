import hashlib
import io
import re

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, ImageFilter, ImageOps, ImageStat, UnidentifiedImageError
from sqlalchemy import select, update

from . import schemas as s
from .config import runtime_settings, settings
from .db import Assignment, Child, Family, Job, LearningUnit, Material, ProviderConfig, UnitSource, get_db, uid
from .fixtures import FIXTURE_ID, LIVE_FIXTURE_IDS, worksheet
from .learning import material_data, record
from .providers import ProviderError, config_for_function, external_allowed, reserve
from .security import authenticated, child_access, rate_limit

router = APIRouter(tags=["Materialien und KI-Aufträge"])
Image.MAX_IMAGE_PIXELS = 16_000_000


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
    idempotency_key: str | None = Header(None),
    p=Depends(authenticated),
    db=Depends(get_db),
):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
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
            image = ImageOps.exif_transpose(source).convert("RGB")
            image.thumbnail((1600, 1600))
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
            image.save(output, format="JPEG", quality=88)  # EXIF/GPS/XMP are discarded.
    except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            422, "Bitte ein gültiges JPEG-, PNG- oder WebP-Bild mit höchstens 16 Megapixeln wählen."
        ) from None
    digest = hashlib.sha256(output.getvalue()).hexdigest()
    # One lock per child also serializes replay checks, day state and file ownership.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    if idempotency_key:
        existing = db.scalar(
            select(Material).where(Material.child_id == child.id, Material.upload_key == idempotency_key)
        )
        if existing:
            if existing.image_digest != digest or existing.school_day_id != school_day_id:
                raise HTTPException(409, "Dieser Upload-Schlüssel gehört bereits zu einem anderen Foto.")
            return material_data(existing)
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
    db.add(material)
    record(db, child.id, "material_uploaded")
    try:
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
    material, _ = get_material(db, p, material_id)
    return material_data(material)


@router.put("/materials/{material_id}/confirm")
def confirm(material_id: str, data: s.MaterialConfirm, p=Depends(authenticated), db=Depends(get_db)):
    material, _ = get_material(db, p, material_id, True)
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
    for key in ("subject", "topic", "content", "homework"):
        setattr(material, key, getattr(data, key))
    material.uncertainties = []
    material.revision += 1
    material.confirmed = True
    material.status = "confirmed"
    # Only explicitly confirmed notes become homework; generated exercises are separate.
    db.execute(
        __import__("sqlalchemy")
        .delete(Assignment)
        .where(Assignment.material_id == material.id, Assignment.kind == "homework")
    )
    for note in data.homework:
        db.add(
            Assignment(
                child_id=material.child_id,
                material_id=material.id,
                kind="homework",
                subject=material.subject,
                topic=material.topic,
                note=note,
                mandatory=True,
            )
        )
    record(
        db,
        material.child_id,
        "material_confirmed",
        {"subject": material.subject, "topic": material.topic, "homework_count": len(data.homework)},
    )
    db.commit()
    return material_data(material)


@router.delete("/materials/{material_id}")
def delete_material(material_id: str, p=Depends(authenticated), db=Depends(get_db)):
    material, child = get_material(db, p, material_id)
    if p.user.role == "child" and material.school_day_id and not material.confirmed:
        # The same day/source/preparation checks apply from either UI entry.
        from .school_day import remove_page

        return remove_page(material.school_day_id, material.id, p=p, db=db)
    if p.user.role == "child" and material.confirmed:
        raise HTTPException(403, "Bestätigte Materialien werden durch deine Eltern gelöscht.")
    child_access(db, p, child.id, write=p.user.role == "parent")
    # Material deletion sets LearningUnit.material_id to null through its FK.
    # Answers and tutor help lock units before Child: keep that order rather
    # than holding Child while waiting for an in-flight answer's unit lock.
    lock_material_units(db, child.id, material_id)
    material, _ = get_material(db, p, material_id, True)
    if p.user.role == "child":
        if material.confirmed:
            raise HTTPException(403, "Bestätigte Materialien werden durch deine Eltern gelöscht.")
        if material.school_day_id:
            raise HTTPException(409, "Die Seite wurde inzwischen geändert. Bitte neu laden.")
        if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
            raise HTTPException(409, "Eine Verarbeitung läuft noch. Bitte kurz warten und aktualisieren.")
    path = material.path
    from .erasure import flush_journal, request
    from .tutor import purge_source_turns

    purge_source_turns(db, [material.id], child_id=material.child_id)
    request(db, "material", material.id)
    db.delete(material)
    db.commit()
    if path:
        (settings.data_dir / "uploads" / path).unlink(missing_ok=True)
    flush_journal()
    return {
        "message": "Material und Bild gelöscht. Bereits erzeugte private Übungen bleiben bis zur Löschung des Lernverlaufs erhalten."
    }


def lock_material_units(db, child_id, material_id):
    """Keep material deletion in the same Unit -> Child lock order as answers."""
    list(
        db.scalars(
            select(LearningUnit)
            .where(LearningUnit.child_id == child_id, LearningUnit.material_id == material_id)
            .order_by(LearningUnit.id)
            .with_for_update()
        )
    )


def enqueue(db, p, child, kind, payload, idempotency):
    if not idempotency or len(idempotency) > 80:
        raise HTTPException(422, "Ein eindeutiger Idempotency-Key (max. 80 Zeichen) ist erforderlich.")
    key = p.user.id + ":" + idempotency
    # Use the same lock order as the multi-page wizard and its worker.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    payload = dict(payload)
    if payload.get("material_id"):
        payload["material_revision"] = db.get(Material, payload["material_id"]).revision
    if payload.get("assignment_id"):
        payload["assignment_revision"] = db.get(Assignment, payload["assignment_id"]).revision
    existing = db.scalar(select(Job).where(Job.idempotency == key))
    if existing:
        if existing.child_id != child.id or existing.kind != kind or existing.payload != payload:
            raise HTTPException(409, "Dieser Anfrageschlüssel wurde bereits für einen anderen Auftrag verwendet.")
        return {"id": existing.id, "status": existing.status}
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
):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    material_id = data.material_id
    review_sources = []
    if data.assignment_id:
        assignment = db.get(Assignment, data.assignment_id)
        if not assignment or assignment.child_id != child.id:
            raise HTTPException(404, "Lernauftrag nicht gefunden.")
        from .learning import local_day

        if assignment.scheduled_for and assignment.scheduled_for > local_day(child).isoformat():
            raise HTTPException(
                409, f"Dieser Lernauftrag beginnt am {assignment.scheduled_for}. Deine Eltern können ihn neu planen."
            )
        if assignment.material_id:
            material_id = assignment.material_id
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
    payload = {"material_id": material_id, "assignment_id": data.assignment_id, "review_of": data.review_of}
    if data.review_of:
        from .coaching import progress

        payload["learning_root_id"] = previous.learning_root_id or previous.id
        payload["not_before"] = progress(db, previous)["next_review"]
        # Continue the original binding goal; the child cannot replace it.
        payload["assignment_id"] = previous.assignment_id
    if review_sources:
        payload["sources"] = review_sources
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
        "status": job.status,
        "result": job.result,
        "error": job.error,
        "attempts": job.attempts,
    }
