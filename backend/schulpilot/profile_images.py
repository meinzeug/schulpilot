"""Own-account profile photos: bounded local decoding and private revisioned files."""

import hashlib
import io
import os
import re
import stat

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import Response
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select, update

from .config import settings
from .db import Session, User, UserAvatar, get_db, now, uid
from .security import audit, authenticated, rate_limit

router = APIRouter(prefix="/auth/me/avatar", tags=["Accounts"])
MAX_UPLOAD = 5 * 1024 * 1024
MAX_PIXELS = 8_000_000
MAX_STORED = 1024 * 1024
REVISION = re.compile(r"[a-f0-9]{32}")


def expected_owner(x_schulpilot_account: str | None = Header(None), p=Depends(authenticated)):
    # A browser cookie can change in another tab while this tab still displays
    # the previous account. This is an assertion, never a target user lookup.
    if x_schulpilot_account != p.user.id:
        raise HTTPException(409, "Das angemeldete Konto hat sich geändert. Bitte das Konto neu laden.")
    return p


def metadata(db, user_id):
    row = db.get(UserAvatar, user_id)
    present = bool(row and row.image_digest)
    return {
        "has_avatar": present,
        "avatar_revision": row.revision if row else None,
        "avatar_url": f"/auth/me/avatar?revision={row.revision}" if present else None,
        "avatar_updated_at": row.updated if row else None,
    }


def export_metadata(db, user_id):
    # The own-account HTTP URL would refer to the exporter, not an exported child.
    return {key: value for key, value in metadata(db, user_id).items() if key != "avatar_url"}


def filename(user_id, revision):
    # No caller-controlled filename, family ID or arbitrary path is accepted.
    if not isinstance(revision, str) or not REVISION.fullmatch(revision):
        raise ValueError("Invalid avatar revision")
    owner = hashlib.sha256(user_id.encode()).hexdigest()
    return f"avatar-{owner}-{revision}.jpg"


def stored_path(user_id, revision):
    return settings.data_dir / "uploads" / filename(user_id, revision)


def image_bytes(user_id, row):
    if not row or not row.image_digest:
        return None
    try:
        descriptor = os.open(stored_path(user_id, row.revision), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    with os.fdopen(descriptor, "rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            return None
        data = source.read(MAX_STORED + 1)
    if len(data) > MAX_STORED or hashlib.sha256(data).hexdigest() != row.image_digest:
        return None
    return data


def normalize(raw):
    if not raw or len(raw) > MAX_UPLOAD:
        raise HTTPException(413 if raw else 422, "Bitte ein JPEG-, PNG- oder WebP-Bild bis 5 MB wählen.")
    try:
        with Image.open(io.BytesIO(raw)) as source:
            if source.format not in ("JPEG", "PNG", "WEBP") or source.width * source.height > MAX_PIXELS:
                raise ValueError("Unsupported image")
            if source.width < 1 or source.height < 1 or getattr(source, "n_frames", 1) != 1:
                raise ValueError("Only one image is allowed")
            oriented = ImageOps.exif_transpose(source)
            oriented.thumbnail((512, 512), Image.Resampling.LANCZOS)
            # New pixels and a fresh encoder drop EXIF, GPS, comments and ICC.
            rgba = oriented.convert("RGBA")
            output_image = Image.new("RGB", rgba.size, (16, 30, 36))
            output_image.paste(rgba, mask=rgba.getchannel("A"))
            output = io.BytesIO()
            output_image.save(output, "JPEG", quality=88, optimize=True)
            result = output.getvalue()
            if len(result) > MAX_STORED:
                raise ValueError("Image remains too large")
            return result
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(
            422, "Bitte ein gültiges einzelnes JPEG-, PNG- oder WebP-Bild bis 8 Megapixel wählen."
        ) from None


def mutation_headers(if_match, key):
    if if_match is None:
        raise HTTPException(428, "Bitte das aktuelle Profilfoto zuerst neu laden.")
    expected = if_match.strip()
    if expected.startswith('"') or expected.endswith('"'):
        if len(expected) < 2 or not (expected.startswith('"') and expected.endswith('"')):
            raise HTTPException(422, "Profilfoto-Revision ist ungültig.")
        expected = expected[1:-1]
    if expected != "none" and not REVISION.fullmatch(expected):
        raise HTTPException(422, "Profilfoto-Revision ist ungültig.")
    if not key or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", key):
        raise HTTPException(422, "Ein gültiger Upload-Schlüssel wird benötigt.")
    return None if expected == "none" else expected


def lock_owner(db, user_id):
    # A write lock also serializes on SQLite, where FOR UPDATE is ignored.
    result = db.execute(
        update(User).where(User.id == user_id).values(disabled=User.disabled),
        execution_options={"synchronize_session": False},
    )
    if result.rowcount != 1:
        raise HTTPException(401, "Bitte erneut anmelden.")


def deletion_paths(db, user_id):
    """Collect the current file under the same lock as an upload before user deletion."""
    lock_owner(db, user_id)
    row = db.scalar(select(UserAvatar).where(UserAvatar.user_id == user_id).execution_options(populate_existing=True))
    return [filename(user_id, row.revision)] if row and row.image_digest else []


def live_owner(db, user_id, session_id):
    lock_owner(db, user_id)
    user = db.get(User, user_id, populate_existing=True)
    session = db.scalar(
        select(Session).where(Session.id == session_id).with_for_update().execution_options(populate_existing=True)
    )
    if (
        not user
        or user.disabled
        or not user.verified
        or not session
        or session.user_id != user_id
        or session.revoked
        or session.expires <= int(now())
        or int(now()) - session.seen > 7 * 86400
    ):
        db.rollback()
        raise HTTPException(401, "Bitte erneut anmelden.")


def mutate(db, user_id, session_id, expected, key, data):
    # Do not retain the dependency's read snapshot across image decoding.
    db.rollback()
    live_owner(db, user_id, session_id)
    row = db.scalar(select(UserAvatar).where(UserAvatar.user_id == user_id).execution_options(populate_existing=True))
    request_digest = hashlib.sha256(b"put\0" + data if data is not None else b"delete").hexdigest()
    if row and row.request_key == key:
        if row.request_digest != request_digest:
            raise HTTPException(409, "Dieser Upload-Schlüssel gehört zu einer anderen Profilfotoänderung.")
        return metadata(db, user_id)
    if (row.revision if row else None) != expected:
        raise HTTPException(409, "Das Profilfoto wurde inzwischen geändert. Bitte neu laden.")
    old_path = stored_path(user_id, row.revision) if row and row.image_digest else None
    revision = uid()
    destination = None
    try:
        if data is not None:
            directory = settings.data_dir / "uploads"
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            candidate = stored_path(user_id, revision)
            descriptor = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            destination = candidate
            with os.fdopen(descriptor, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
        if row is None:
            row = UserAvatar(user_id=user_id)
            db.add(row)
        row.revision = revision
        row.image_digest = hashlib.sha256(data).hexdigest() if data is not None else None
        row.updated = int(now())
        row.request_key, row.request_digest = key, request_digest
        audit(db, user_id, "account.avatar_upload" if data is not None else "account.avatar_delete", user_id)
        db.commit()
    except BaseException:
        db.rollback()
        if destination:
            destination.unlink(missing_ok=True)
        raise
    if old_path:
        old_path.unlink(missing_ok=True)
    return metadata(db, user_id)


@router.put("")
def upload_avatar(
    file: UploadFile = File(...),
    if_match: str | None = Header(None),
    idempotency_key: str | None = Header(None),
    p=Depends(expected_owner),
    db=Depends(get_db),
):
    expected = mutation_headers(if_match, idempotency_key)
    user_id, session_id = p.user.id, p.session.id
    rate_limit(db, "profile-photo:" + user_id, 20, 3600)
    data = normalize(file.file.read(MAX_UPLOAD + 1))
    return mutate(db, user_id, session_id, expected, idempotency_key, data)


@router.delete("")
def delete_avatar(
    if_match: str | None = Header(None),
    idempotency_key: str | None = Header(None),
    p=Depends(expected_owner),
    db=Depends(get_db),
):
    expected = mutation_headers(if_match, idempotency_key)
    user_id, session_id = p.user.id, p.session.id
    rate_limit(db, "profile-photo:" + user_id, 20, 3600)
    return mutate(db, user_id, session_id, expected, idempotency_key, None)


@router.get("")
def get_avatar(revision: str, p=Depends(expected_owner), db=Depends(get_db)):
    if not REVISION.fullmatch(revision):
        raise HTTPException(422, "Profilfoto-Revision ist ungültig.")
    row = db.get(UserAvatar, p.user.id)
    if not row or row.revision != revision:
        raise HTTPException(404, "Profilfoto nicht gefunden.")
    data = image_bytes(p.user.id, row)
    if data is None:
        raise HTTPException(404, "Profilfoto nicht gefunden.")
    return Response(
        data, media_type="image/jpeg", headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
    )


def add_to_export(db, user_id, archive, name):
    row = db.get(UserAvatar, user_id)
    data = image_bytes(user_id, row)
    if data is not None:
        archive.writestr(name, data)
