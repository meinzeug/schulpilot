"""Durable DB queue. At most one provider attempt; abandoned jobs never replay."""

import logging
import signal
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import delete, select, update

from . import schemas as s
from .config import settings
from .db import (
    DB,
    Activity,
    Assignment,
    Audit,
    Child,
    Family,
    Job,
    LearningUnit,
    Material,
    Message,
    OperatorJob,
    ProviderConfig,
    RateBucket,
    SchoolDay,
    ServiceState,
    Session,
    Token,
    UnitSource,
    Usage,
    UsageBucket,
    init_db,
    now,
)
from .families import remove_family, unlink_uploads
from .fixtures import FIXTURE_ID, LIVE_FIXTURE_IDS, PACKAGE_FIXTURE_ID
from .learning import record
from .notifications import deliver_one
from .notifications import prepare as prepare_notifications
from .providers import ProviderError, config_for_function, request_provider, settle
from .synthetic import sample_unit

log = logging.getLogger("schulpilot.worker")
running = True


def unit_sources(db, job):
    sources = []
    for snapshot in job.payload.get("sources", []):
        material = db.get(Material, snapshot["id"])
        if (
            not material
            or material.child_id != job.child_id
            or not material.confirmed
            or material.revision != snapshot["revision"]
        ):
            raise ProviderError("Eine Quelle der Wiederholung wurde geändert oder gelöscht. Bitte neu vorbereiten.")
        sources.append(material)
    return sources


def claim(db):
    query = select(Job).where(Job.status == "queued").order_by(Job.created).limit(1)
    if db.bind.dialect.name == "postgresql":
        query = query.with_for_update(skip_locked=True)
    job = db.scalar(query)
    if not job:
        return None
    result = db.execute(
        update(Job)
        .where(Job.id == job.id, Job.status == "queued")
        .values(status="running", started=int(now()), attempts=Job.attempts + 1)
    )
    if not result.rowcount:
        db.rollback()
        return None
    db.commit()
    return job.id


def process(job_id):
    with DB() as db:
        candidate = db.get(Job, job_id)
        is_coaching = candidate and candidate.kind == "coach"
    if is_coaching:
        from .coaching import process as process_coaching

        process_coaching(job_id)
        return
    result = None
    try:
        with DB() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            child = db.get(Child, job.child_id)
            family = db.get(Family, child.family_id)
            if family.expires and family.expires < now():
                raise ProviderError("Synthetischer Testraum abgelaufen.")
            material = db.get(Material, job.payload["material_id"]) if job.payload.get("material_id") else None
            assignment = db.get(Assignment, job.payload["assignment_id"]) if job.payload.get("assignment_id") else None
            if job.payload.get("material_id") and (
                not material or material.revision != job.payload.get("material_revision")
            ):
                raise ProviderError(
                    "Das Material wurde seit Auftragserstellung geändert oder gelöscht. Bitte neu vorbereiten."
                )
            if job.payload.get("assignment_id") and (
                not assignment or assignment.revision != job.payload.get("assignment_revision")
            ):
                raise ProviderError(
                    "Der Elternauftrag wurde inzwischen geändert oder gelöscht. Bitte den aktuellen Plan öffnen."
                )
            if job.kind == "unit" and ((material and not material.confirmed) or (not material and not assignment)):
                raise ProviderError("Bestätigtes Material oder Elternauftrag ist nicht mehr vorhanden.")
            if job.kind == "package":
                from .school_day import validate_package_sources

                _, source_pages = validate_package_sources(db, job)
            elif job.kind == "unit":
                source_pages = unit_sources(db, job)
            config = config_for_function(db.get(ProviderConfig, 1), job.kind)
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage and (
                usage.provider != config.provider
                or usage.model != config.model
                or usage.config_revision != config.revision
            ):
                raise ProviderError(
                    "Die Providerkonfiguration wurde seit Auftragserstellung geändert. Bitte neuen Auftrag anlegen."
                )
            preferences = s.Preferences(**child.preferences).model_dump(mode="json")
            feedback = [
                e.detail.get("kind")
                for e in db.scalars(
                    select(Activity)
                    .where(Activity.child_id == child.id, Activity.kind == "feedback")
                    .order_by(Activity.created.desc())
                    .limit(3)
                )
            ]
            previous = [
                {"topic": u.topic, "status": u.status}
                for u in db.scalars(
                    select(LearningUnit)
                    .where(LearningUnit.child_id == child.id)
                    .order_by(LearningUnit.created.desc())
                    .limit(5)
                )
            ]
            difficulties = [
                {"question_id": a.detail.get("question_id"), "outcome": a.detail.get("outcome")}
                for a in db.scalars(
                    select(Activity)
                    .where(Activity.child_id == child.id, Activity.kind == "answer")
                    .order_by(Activity.created.desc())
                    .limit(12)
                )
            ]
            payload = {
                "function": job.kind,
                "grade": child.grade,
                "material": {"subject": material.subject, "topic": material.topic, "content": material.content}
                if material and job.kind != "extract"
                else None,
                "goal": {
                    "subject": assignment.subject,
                    "topic": assignment.topic,
                    "note": assignment.note,
                    "mandatory": assignment.mandatory,
                    "due": assignment.due,
                }
                if assignment
                else None,
                "preferences": preferences,
                "feedback": feedback,
                "recent_units": previous,
                "recent_outcomes": difficulties,
                "review": bool(job.payload.get("review_of")),
            }
            if job.kind == "package":
                payload["material"] = None
                payload["materials"] = [
                    {
                        "page_number": m.page_number,
                        "group_id": g["id"],
                        "subject": m.subject,
                        "topic": m.topic,
                        "content": m.content,
                    }
                    for g in job.payload["groups"]
                    for m in source_pages
                    if m.id in g["material_ids"]
                ]
                payload["selected_groups"] = [
                    {"id": g["id"], "subject": g["subject"], "estimated_minutes": g["estimated_minutes"]}
                    for g in job.payload["groups"]
                ]
            elif job.kind == "unit" and source_pages:
                payload["material"]["content"] = "\n\n".join(
                    f"Heftseite {m.page_number or i + 1}:\n{m.content}" for i, m in enumerate(source_pages)
                )
            if job.kind == "unit" and job.payload.get("review_of"):
                from .coaching import focus_ids, goals_for, root_and_units

                previous_unit = db.get(LearningUnit, job.payload["review_of"])
                if not previous_unit or previous_unit.child_id != child.id:
                    raise ProviderError("Die ursprüngliche Lernfolge ist nicht mehr vorhanden.")
                _, chain = root_and_units(db, previous_unit)
                payload.update(
                    required_subject=previous_unit.subject,
                    required_topic=previous_unit.topic,
                    previous_prompts=[q["prompt"] for u in chain for q in u.questions][-80:],
                    learning_goals=goals_for(db, previous_unit),
                    focus_goal_ids=focus_ids(db, previous_unit, "check"),
                )
            image_bytes = (
                (settings.data_dir / "uploads" / material.path).read_bytes()
                if job.kind == "extract" and material and material.path
                else None
            )
            synthetic = bool(material and material.synthetic)
            fixture = bool(synthetic and material.fixture_id in LIVE_FIXTURE_IDS and family.synthetic)
            fixture_value = (True if material.fixture_id == FIXTURE_ID else material.fixture_id) if fixture else False
            if fixture and job.kind == "package":
                fixture_value = PACKAGE_FIXTURE_ID
            variant = len(previous)
            config_values = {c.name: getattr(config, c.name) for c in ProviderConfig.__table__.columns}
            function = job.kind
            if not synthetic or fixture:
                from .commerce import usage_terms

                usage_terms(db, family, enforce=True)
            # Release the DB transaction before the bounded external request.
            db.rollback()
        if synthetic and not fixture:
            data = sample_unit(variant, feedback[0] if feedback else "normal")
            if payload["review"]:
                from .coaching import synthetic_report

                with DB() as db:
                    data = synthetic_report(db, db.get(LearningUnit, job.payload["review_of"]), "check")["next_unit"]
        else:
            result = request_provider(
                ProviderConfig(**config_values), function, payload, image_bytes, synthetic_fixture=fixture_value
            )
            data = result.data
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "running":
                return
            if not db.execute(update(Child).where(Child.id == job.child_id).values(grade=Child.grade)).rowcount:
                return
            material = db.get(Material, job.payload["material_id"]) if job.payload.get("material_id") else None
            assignment = db.get(Assignment, job.payload["assignment_id"]) if job.payload.get("assignment_id") else None
            if job.payload.get("material_id") and (
                not material or material.revision != job.payload.get("material_revision")
            ):
                raise ProviderError(
                    "Das Material wurde während der Verarbeitung geändert. Ausgabe wurde nicht übernommen."
                )
            if job.payload.get("assignment_id") and (
                not assignment or assignment.revision != job.payload.get("assignment_revision")
            ):
                raise ProviderError(
                    "Das Elternziel wurde während der Verarbeitung geändert. Ausgabe wurde nicht übernommen."
                )
            if job.kind == "package":
                from .school_day import save_package

                save_package(
                    db, job, data, synthetic=synthetic, provider=config_values["provider"], model=config_values["model"]
                )
            elif job.kind == "extract":
                if not material or material.confirmed:
                    raise ProviderError("Material wurde zwischenzeitlich entfernt oder bereits bestätigt.")
                data = s.ExtractionOutput.model_validate(data).model_dump()
                for key in ("subject", "topic", "content", "uncertainties", "homework", "legibility"):
                    setattr(material, key, data[key])
                material.status = "unreadable" if data["legibility"] == "unreadable" else "review"
                material.extraction_provider = config_values["provider"]
                material.extraction_model = config_values["model"]
                job.result = {"material_id": material.id}
                record(db, job.child_id, "material_extracted", {"uncertainty_count": len(data["uncertainties"])})
            else:
                source_pages = unit_sources(db, job)
                if not source_pages and material:
                    source_pages = [material]
                if job.payload.get("review_of"):
                    from .coaching import validate_new_round

                    validate_new_round(db, db.get(LearningUnit, job.payload["review_of"]), data)
                goal = (
                    db.get(Assignment, job.payload.get("assignment_id")) if job.payload.get("assignment_id") else None
                )
                if goal and data["subject"].casefold() != goal.subject.casefold():
                    raise ProviderError(
                        "Die erzeugte Einheit weicht vom verbindlichen Fach ab. Bitte den Auftrag präzisieren."
                    )
                unit = LearningUnit(
                    child_id=job.child_id,
                    material_id=material.id if material else None,
                    assignment_id=job.payload.get("assignment_id"),
                    goal_revision=job.payload.get("assignment_revision"),
                    review_of=job.payload.get("review_of"),
                    learning_root_id=job.payload.get("learning_root_id"),
                    round_kind="spaced_review" if job.payload.get("review_of") else "learning",
                    not_before=job.payload.get("not_before"),
                    introduction_seen=bool(job.payload.get("review_of")),
                    subject=data["subject"],
                    topic=data["topic"],
                    explanation=data["explanation"],
                    questions=data["questions"],
                    synthetic=synthetic,
                    provider="synthetic" if synthetic and not fixture else config_values["provider"],
                    model="fixed-fractions-v1" if synthetic and not fixture else config_values["model"],
                )
                db.add(unit)
                db.flush()
                for source in source_pages:
                    db.add(UnitSource(unit_id=unit.id, material_id=source.id, revision=source.revision))
                job.result = {"unit_id": unit.id}
                record(
                    db,
                    job.child_id,
                    "unit_created",
                    {"subject": unit.subject, "topic": unit.topic, "synthetic": synthetic},
                    unit.id,
                )
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, result)
            job.status = "completed"
            job.finished = int(now())
    except Exception as exc:
        # Do not log provider bodies, prompts, photos, answers or credentials.
        message = (
            str(exc)
            if isinstance(exc, (ProviderError, HTTPException))
            else "Verarbeitung fehlgeschlagen. Der Betreiber kann den technischen Fehlercode prüfen."
        )
        if isinstance(exc, HTTPException):
            message = str(exc.detail)
        with DB.begin() as db:
            job = db.get(Job, job_id)
            if job:
                job.status = "failed"
                job.error = message[:500]
                job.finished = int(now())
                usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
                if usage:
                    settle(db, usage, result, failed=True)
        log.warning("job_failed id=%s type=%s", job_id, type(exc).__name__)


def maintenance():
    paths = []
    with DB.begin() as db:
        from .commerce import maintenance as commerce_maintenance

        commerce_maintenance(db)
        stale = list(db.scalars(select(Job).where(Job.status == "running", Job.started < int(now()) - 240)))
        for job in stale:
            job.status = "failed"
            job.error = "Worker wurde unterbrochen. Kein automatischer Wiederholungsversuch; mögliche Kosten bleiben reserviert."
            job.finished = int(now())
            usage = db.scalar(select(Usage).where(Usage.job_id == job.id))
            if usage:
                settle(db, usage, failed=True)
        for operation in db.scalars(
            select(OperatorJob).where(OperatorJob.status == "running", OperatorJob.started < int(now()) - 600)
        ):
            operation.status, operation.finished, operation.error = (
                "failed",
                int(now()),
                "Prüfung wurde unterbrochen. Keine automatische Wiederholung.",
            )
        db.execute(delete(OperatorJob).where(OperatorJob.created < int(now()) - 90 * 86400))
        for family in list(db.scalars(select(Family).where(Family.expires.is_not(None), Family.expires < int(now())))):
            # Demo owner users are not attached to other families.
            from .db import Membership, User

            owners = list(db.scalars(select(Membership.user_id).where(Membership.family_id == family.id)))
            paths.extend(remove_family(db, family))
            db.flush()
            for user_id in owners:
                if not db.scalar(select(Membership.id).where(Membership.user_id == user_id)):
                    db.execute(delete(User).where(User.id == user_id))
        db.execute(delete(Session).where(Session.expires < int(now()) - 7 * 86400))
        db.execute(delete(Token).where(Token.expires < int(now()) - 7 * 86400))
        db.execute(delete(RateBucket).where(RateBucket.expires < int(now())))
        # Operational metadata, not invoices or private learning content.
        db.execute(delete(Usage).where(Usage.created < int(now()) - 90 * 86400))
        db.execute(delete(Audit).where(Audit.created < int(now()) - 180 * 86400))
        current_month = datetime.now(timezone.utc)
        oldest_period = f"{current_month.year - 1:04d}-{current_month.month:02d}"
        for bucket in db.scalars(select(UsageBucket)):
            period = bucket.id.rsplit(":", 1)[-1]
            if len(period) == 7 and period[4] == "-" and period.replace("-", "").isdigit() and period < oldest_period:
                db.delete(bucket)
        # Private learning records: 365 days; activities/answers disappear together.
        db.execute(delete(LearningUnit).where(LearningUnit.created < int(now()) - 365 * 86400))
        db.execute(delete(Activity).where(Activity.created < int(now()) - 365 * 86400))
        db.execute(delete(Message).where(Message.created < int(now()) - 365 * 86400))
        db.execute(delete(SchoolDay).where(SchoolDay.created < int(now()) - 365 * 86400))
        db.execute(delete(Job).where(Job.created < int(now()) - 30 * 86400, Job.status.in_(["failed", "completed"])))
        # Also remove interrupted export files. Uploads have independent DB
        # ownership; unfinished writes are never served from the webroot.
        exports = settings.data_dir / "exports"
        if exports.is_dir():
            for file in exports.glob("family-*.zip"):
                if file.stat().st_mtime < now() - 3600:
                    file.unlink(missing_ok=True)
        for m in list(db.scalars(select(Material).where(Material.created < int(now()) - 365 * 86400))):
            if m.path:
                paths.append(m.path)
            db.delete(m)
        # Bundled, in-app reminders only; no sensitive lock-screen messages.
        for child in db.scalars(select(Child)):
            prefs = s.Preferences(**child.preferences)
            if not prefs.reminders:
                continue
            current = datetime.now(ZoneInfo(prefs.timezone))
            if (
                (prefs.quiet_start <= current.hour or current.hour < prefs.quiet_end)
                if prefs.quiet_start > prefs.quiet_end
                else (prefs.quiet_start <= current.hour < prefs.quiet_end)
            ):
                continue
            if current.weekday() not in prefs.weekdays or (prefs.pause_until and current.date() <= prefs.pause_until):
                continue
            start = current.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
            if not db.scalar(
                select(Message.id).where(
                    Message.child_id == child.id, Message.kind == "reminder", Message.created >= start
                )
            ):
                db.add(
                    Message(
                        child_id=child.id,
                        sender_id=None,
                        kind="reminder",
                        body="Dein Lernplan ist bereit. Öffne ihn, wenn es für dich passt.",
                    )
                )
    unlink_uploads(paths)
    from .erasure import flush_journal, prune_journal, prune_orphan_images

    flush_journal()
    with DB() as db:
        prune_orphan_images(db)
        state = db.get(ServiceState, "erasure_compaction")
        compact = not state or now() - state.updated > 86400
    if compact:
        prune_journal()
        with DB.begin() as db:
            state = db.get(ServiceState, "erasure_compaction")
            if state:
                state.updated = int(now())
            else:
                db.add(ServiceState(name="erasure_compaction", updated=int(now())))
    with DB.begin() as db:
        prepare_notifications(db)


def stop(*_):
    global running
    running = False


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    init_db()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    last_maintenance = 0
    last_heartbeat = 0
    while running:
        try:
            if now() - last_heartbeat > 10:
                with DB.begin() as db:
                    state = db.get(ServiceState, "worker")
                    if state:
                        state.updated = int(now())
                    else:
                        db.add(ServiceState(name="worker", updated=int(now())))
                last_heartbeat = now()
            from .operator_probe import work_one

            if work_one(lambda: running):
                continue
            deliver_one(DB)
            if now() - last_maintenance > 60:
                maintenance()
                last_maintenance = now()
            with DB() as db:
                job_id = claim(db)
            if job_id:
                process(job_id)
            else:
                time.sleep(1)
        except Exception as exc:
            log.error("worker_error type=%s", type(exc).__name__)
            time.sleep(3)


if __name__ == "__main__":
    main()
