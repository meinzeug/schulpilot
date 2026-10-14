import io

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select, update

from . import schemas as s
from .config import settings
from .db import Assignment, Child, Family, Job, LearningUnit, Material, get_db, uid
from .learning import material_data, record
from .providers import reserve
from .security import authenticated, child_access, rate_limit

router = APIRouter(tags=["Materialien und KI-Aufträge"])
Image.MAX_IMAGE_PIXELS = 16_000_000


@router.post("/children/{child_id}/materials", status_code=201)
def upload(child_id: str, file: UploadFile = File(...), p=Depends(authenticated), db=Depends(get_db)):
    child = child_access(db, p, child_id, write=p.user.role == "parent")
    family = db.get(Family, child.family_id)
    if family.synthetic:
        raise HTTPException(
            403,
            "Der synthetische Testraum verwendet nur das mitgelieferte Beispiel. Bitte hier keine echten Kinderfotos hochladen.",
        )
    if not settings.real_data_approved:
        raise HTTPException(503, "Materialimport echter Daten ist bis zur dokumentierten Datenschutzfreigabe gesperrt.")
    rate_limit(db, "upload:" + p.user.id, 10, 3600)
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
            output = io.BytesIO()
            image.save(output, format="JPEG", quality=88)  # EXIF/GPS/XMP are discarded.
    except (UnidentifiedImageError, ValueError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            422, "Bitte ein gültiges JPEG-, PNG- oder WebP-Bild mit höchstens 16 Megapixeln wählen."
        ) from None
    directory = settings.data_dir / "uploads"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = uid() + ".jpg"
    destination = directory / path
    destination.write_bytes(output.getvalue())
    destination.chmod(0o600)
    material = Material(child_id=child.id, title="Unterrichtsmaterial", path=path, synthetic=False)
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
    if material.status not in ("review", "confirmed"):
        raise HTTPException(409, "Bitte zuerst die Materialerkennung abschließen.")
    if material.synthetic:
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
    material, _ = get_material(db, p, material_id, True)
    if p.user.role != "parent":
        raise HTTPException(403, "Materialien werden durch Eltern gelöscht.")
    path = material.path
    db.delete(material)
    db.commit()
    if path:
        (settings.data_dir / "uploads" / path).unlink(missing_ok=True)
    return {
        "message": "Material und Bild gelöscht. Bereits erzeugte private Übungen bleiben bis zur Löschung des Lernverlaufs erhalten."
    }


def enqueue(db, p, child, kind, payload, idempotency):
    if not idempotency or len(idempotency) > 80:
        raise HTTPException(422, "Ein eindeutiger Idempotency-Key (max. 80 Zeichen) ist erforderlich.")
    key = p.user.id + ":" + idempotency
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
    rate_limit(db, "job:" + p.user.id, 10, 60)
    # Atomically limit each child to one pending paid operation.
    db.execute(update(Child).where(Child.id == child.id).values(grade=Child.grade))
    if db.scalar(select(Job.id).where(Job.child_id == child.id, Job.status.in_(["queued", "running"]))):
        raise HTTPException(409, "Für dieses Kind wird bereits ein Auftrag verarbeitet.")
    job = Job(id=uid(), child_id=child.id, kind=kind, payload=payload, idempotency=key)
    db.add(job)
    db.flush()
    material = db.get(Material, payload.get("material_id")) if payload.get("material_id") else None
    synthetic = bool(material and material.synthetic)
    if synthetic:
        if kind == "extract":
            raise HTTPException(
                409, "Das Beispiel wurde bereits synthetisch vorbereitet. Es wurde keine Bilderkennung ausgeführt."
            )
    else:
        family = db.get(Family, child.family_id)
        reserve(db, family, child.id, job.id, kind)
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
    if data.assignment_id:
        assignment = db.get(Assignment, data.assignment_id)
        if not assignment or assignment.child_id != child.id:
            raise HTTPException(404, "Lernauftrag nicht gefunden.")
        if assignment.material_id:
            material_id = assignment.material_id
    if data.review_of:
        previous = db.get(LearningUnit, data.review_of)
        if not previous or previous.child_id != child.id or previous.status != "completed":
            raise HTTPException(404, "Abgeschlossene Lerneinheit nicht gefunden.")
        material_id = previous.material_id
    if material_id:
        material = db.get(Material, material_id)
        if not material or material.child_id != child.id:
            raise HTTPException(404, "Material nicht gefunden.")
        if not material.confirmed:
            raise HTTPException(409, "Bitte den erkannten Stoff und unsichere Stellen zuerst bestätigen.")
        if material.synthetic and data.assignment_id:
            assignment = db.get(Assignment, data.assignment_id)
            if assignment.subject != "Mathematik" or "br" not in assignment.topic.lower():
                raise HTTPException(
                    422,
                    "Die synthetische Übungsquelle unterstützt nur Brüche. Für andere Themen ist ein freigegebener KI-Anbieter erforderlich.",
                )
    elif not data.assignment_id:
        raise HTTPException(422, "Bitte bestätigtes Material oder einen Elternauftrag auswählen.")
    payload = {"material_id": material_id, "assignment_id": data.assignment_id, "review_of": data.review_of}
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
