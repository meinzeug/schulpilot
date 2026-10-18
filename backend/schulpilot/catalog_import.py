"""Repeatable import of public navigation metadata, never provider media/cookies."""

import argparse
import csv
import gzip
import hashlib
import json
from collections import Counter
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlsplit

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from .catalog_models import (
    CatalogContent,
    CatalogLevel,
    CatalogMembership,
    CatalogPlacement,
    CatalogProvenance,
    CatalogRefresh,
    CatalogSnapshot,
    CatalogState,
    CatalogTopic,
)
from .db import DB, SubjectProvider, now
from .subject_registry import seed_connection

BUNDLE = Path(__file__).with_name("reference") / "sofatutor-20261018.json.gz"
MAX_BYTES = 64 * 1024 * 1024
REVIEW = BUNDLE.with_name("sofatutor-20261018-review.json.gz")


class CatalogError(ValueError):
    pass


def fingerprint(value):
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def catalog_url(value):
    """Exact HTTPS hosts, including query parameters; never a suffix comparison."""
    if not isinstance(value, str) or len(value) > 3000 or any(ord(c) < 33 for c in value):
        raise CatalogError("Ungültiger Kataloglink.")
    try:
        parsed = urlsplit(value)
        if (
            parsed.scheme != "https"
            or parsed.hostname not in ("sofatutor.com", "www.sofatutor.com")
            or parsed.username
            or parsed.password
            or parsed.port not in (None, 443)
            or "\\" in value
            or parsed.fragment
        ):
            raise CatalogError("Ungültiger Kataloglink.")
    except ValueError:
        raise CatalogError("Ungültiger Kataloglink.") from None
    # The retained catalog needs only navigation, never authentication material.
    from urllib.parse import parse_qsl

    if any(
        k.casefold() in ("token", "access_token", "password", "authorization", "code")
        for k, _ in parse_qsl(parsed.query)
    ):
        raise CatalogError("Zugangsdaten sind keine Katalogmetadaten.")
    return value


def read_catalog(path=BUNDLE):
    path = Path(path)
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as file:
        raw = file.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise CatalogError("Katalog überschreitet die Importgrenze.")
    try:
        data = json.loads(raw)
    except (UnicodeError, ValueError):
        raise CatalogError("Katalog enthält kein gültiges JSON.") from None
    return data, hashlib.sha256(raw).hexdigest()


@lru_cache(maxsize=8)
def source_review(snapshot_id):
    with gzip.open(REVIEW, "rb") as file:
        raw = file.read(12 * 1024 * 1024)
    review = json.loads(raw)
    if review["catalog_sha256"] != snapshot_id:
        return {}
    validation = review["validation"]
    return {
        "counts": validation["counts"],
        "scope": validation["scope"],
        "issue_counts_by_code": validation.get("issue_counts_by_code", {}),
        "complete": validation["complete"],
        "authenticated_curated_complete": validation["authenticated_curated_complete"],
        "review_sha256": hashlib.sha256(raw).hexdigest(),
        "review_file": REVIEW.name,
    }


def _unique(rows, key="id"):
    result = {}
    for row in rows:
        value = row.get(key)
        if not isinstance(value, str) or not 1 <= len(value) <= 240 or value in result:
            raise CatalogError("Katalog-IDs fehlen oder sind doppelt.")
        result[value] = row
    return result


def placement_id(row):
    return fingerprint([row.get(k) for k in ("topic_id", "grade_id", "area", "content_page_id", "entry_url")])


def validate(data, csv_path=None):
    if not isinstance(data, dict):
        raise CatalogError("Katalogstruktur fehlt.")

    def check_public(value):
        if isinstance(value, dict):
            if {str(k).lower() for k in value} & {
                "password",
                "access_token",
                "refresh_token",
                "api_key",
                "private_key",
                "client_secret",
                "authorization",
                "cookie",
                "cookies",
                "session_cookie",
            }:
                raise CatalogError("Private Zugangsdaten gehören nicht in den Katalog.")
            for item in value.values():
                check_public(item)
        elif isinstance(value, list):
            for item in value:
                check_public(item)

    check_public(data)
    meta = data.get("metadata", {})
    if (
        meta.get("provider") != "sofatutor"
        or meta.get("schema_version") != "1.5"
        or meta.get("contains_media") is not False
    ):
        raise CatalogError("Nur der bestätigte Sofatutor-Metadatenstandard1.5 wird unterstützt.")
    for name in (
        "subjects",
        "grades",
        "topics",
        "topic_placements",
        "videos",
        "topic_videos",
        "sources",
        "public_topic_documents",
        "public_topic_links",
        "content_metadata_sources",
        "sitemap_content_pages",
    ):
        if not isinstance(data.get(name), list) or any(not isinstance(r, dict) for r in data[name]):
            raise CatalogError("Katalogtabelle fehlt oder ist ungültig.")
    subjects, levels, topics, contents = (_unique(data[n]) for n in ("subjects", "grades", "topics", "videos"))
    for rows in (subjects, levels, topics, contents):
        if any(len(key) > 100 for key in rows):
            raise CatalogError("Katalog-ID überschreitet die Schema-Grenze.")
    for row in subjects.values():
        catalog_url(row["url"])
    for row in levels.values():
        if row.get("subject_id") not in subjects or row.get("level_type") not in ("klasse", "lernjahr", "vorschule"):
            raise CatalogError("Unbekanntes Fach oder ungültige Stufenart.")
        number = row.get("level_number")
        if row["level_type"] != "vorschule" and (type(number) is not int or not 1 <= number <= 20):
            raise CatalogError("Ungültige Stufe.")
        catalog_url(row["url"])
    for row in topics.values():
        if row.get("subject_id") not in subjects:
            raise CatalogError("Thema ohne bekanntes Fach.")
        catalog_url(row["entry_url"])
    placements = {}
    for row in data["topic_placements"]:
        if row.get("topic_id") not in topics or row.get("grade_id") not in levels:
            raise CatalogError("Platzierung verweist auf fehlende Inhalte.")
        if topics[row["topic_id"]]["subject_id"] != levels[row["grade_id"]]["subject_id"]:
            raise CatalogError("Stufe und Thema gehören nicht zum selben Fach.")
        key = placement_id(row)
        if key in placements:
            raise CatalogError("Doppelte Themenplatzierung.")
        placements[key] = row
        catalog_url(row["entry_url"])
    for row in contents.values():
        if row.get("content_type") not in ("video", "learning_text") or type(row.get("title_verified")) is not bool:
            raise CatalogError("Ungeprüfter Inhaltstyp.")
        if not isinstance(row.get("title"), str) or not row["title"].strip():
            raise CatalogError("Inhalt ohne Titel.")
        catalog_url(row["url"])
    memberships, curated_counts = set(), Counter()
    for row in data["topic_videos"]:
        pair = row.get("topic_id"), row.get("video_id")
        if pair[0] not in topics or pair[1] not in contents or pair in memberships:
            raise CatalogError("Fehlende oder doppelte Inhaltszuordnung.")
        memberships.add(pair)
        if type(row.get("curated_class_membership_verified")) is not bool:
            raise CatalogError("Expliziter Klassenprüfstatus fehlt.")
        if row["curated_class_membership_verified"]:
            curated_counts[pair[0]] += 1
        catalog_url(row["url"])
    for row in topics.values():
        if row.get("curated_list_empty_verified") is True and curated_counts[row["id"]]:
            raise CatalogError("Bestätigte leere Hauptliste enthält kuratierte Einträge.")
    for row in data["public_topic_links"]:
        if row.get("topic_id") not in topics or row.get("video_id") not in contents:
            raise CatalogError("Öffentlicher Verweis ohne Katalogziel.")
        catalog_url(row["url"])
    # Scope/status fields remain intact in provenance. They never upgrade a
    # public link into a curated class relation.
    for name in ("sources", "public_topic_documents", "content_metadata_sources", "sitemap_content_pages"):
        for row in data[name]:
            for key in ("url", "request_url", "final_url", "canonical_url", "source_url"):
                if row.get(key):
                    catalog_url(row[key])
    expected_csv = Counter()
    by_topic = {}
    for row in data["topic_videos"]:
        if row["curated_class_membership_verified"] and contents[row["video_id"]]["content_type"] == "video":
            by_topic.setdefault(row["topic_id"], []).append(row)
    for row in placements.values():
        topic, level = topics[row["topic_id"]], levels[row["grade_id"]]
        for membership in by_topic.get(row["topic_id"], []):
            expected_csv[
                (
                    subjects[topic["subject_id"]]["title"],
                    level["level_type"],
                    level["title"],
                    row["area"],
                    topic["title"],
                    contents[membership["video_id"]]["title"],
                    membership["url"],
                    row["entry_url"],
                )
            ] += 1
    if csv_path:
        with Path(csv_path).open(encoding="utf-8-sig", newline="") as file:
            actual = Counter()
            for row in csv.DictReader(file):
                if (
                    row.get("membership_scope") != "authenticated_curated"
                    or row.get("curated_class_membership_verified") != "True"
                ):
                    raise CatalogError("CSV enthält keine bestätigte Klassenbeziehung.")
                actual[
                    tuple(
                        row.get(k)
                        for k in (
                            "subject",
                            "level_type",
                            "level_label",
                            "area",
                            "topic_title",
                            "video_title",
                            "video_url",
                            "topic_url",
                        )
                    )
                ] += 1
        if actual != expected_csv:
            raise CatalogError("CSV-Beziehungen stimmen nicht mit dem normalisierten Katalog überein.")
    return {
        "subjects": len(subjects),
        "levels": len(levels),
        "active_levels": len({r["grade_id"] for r in placements.values()}),
        "topics": len(topics),
        "placements": len(placements),
        "contents": len(contents),
        "content_types": dict(Counter(r["content_type"] for r in contents.values())),
        "memberships": len(memberships),
        "curated_memberships": sum(curated_counts.values()),
        "empty_curated_topics": sum(r.get("curated_list_empty_verified") is True for r in topics.values()),
        "csv_video_relations": sum(expected_csv.values()),
        "csv_compared": bool(csv_path),
        "provenance": {
            n: len(data[n])
            for n in (
                "sources",
                "public_topic_documents",
                "public_topic_links",
                "content_metadata_sources",
                "sitemap_content_pages",
            )
        },
    }


def upsert(db, model, values, keys):
    if not values:
        return
    table = model.__table__
    dialect_insert = sqlite_insert if db.bind.dialect.name == "sqlite" else pg_insert
    for start in range(0, len(values), 300):
        statement = dialect_insert(table).values(values[start : start + 300])
        db.execute(
            statement.on_conflict_do_update(
                index_elements=keys,
                set_={c.name: getattr(statement.excluded, c.name) for c in table.columns if c.name not in keys},
            )
        )


def import_catalog(db, data, snapshot_id=None, csv_path=None):
    report = validate(data, csv_path)
    snapshot_id = snapshot_id or fingerprint(data)
    review = source_review(snapshot_id)
    report |= {
        "source_errors": review.get("counts", {}).get("errors"),
        "source_warnings": review.get("counts", {}).get("warnings"),
    }
    if db.bind.dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(1397769025)"))
    seed_connection(db.connection())
    subject_ids = dict(
        db.execute(
            select(SubjectProvider.external_id, SubjectProvider.subject_id).where(
                SubjectProvider.provider == "sofatutor"
            )
        ).all()
    )
    if any(r["id"] not in subject_ids for r in data["subjects"]):
        raise CatalogError("Referenzfach fehlt im versionierten Fachstamm; Seed bewusst aktualisieren.")
    state = db.get(CatalogState, "sofatutor")
    if state and state.snapshot_id == snapshot_id:
        db.get(CatalogSnapshot, snapshot_id).last_import = int(now())
        return report | {"snapshot_id": snapshot_id, "repeated": True}
    stamp = int(now())
    previous_snapshot = db.get(CatalogSnapshot, snapshot_id)
    if previous_snapshot:
        previous_snapshot.last_import = stamp
        db.flush()
    else:
        upsert(
            db,
            CatalogSnapshot,
            [
                {
                    "id": snapshot_id,
                    "provider": "sofatutor",
                    "schema_version": "1.5",
                    "metadata_json": data["metadata"]
                    | {"coverage": data.get("coverage", {}), "source_validation": review},
                    "report": report,
                    "created": stamp,
                    "last_import": stamp,
                }
            ],
            ["id"],
        )
    placement_counts = Counter(r["grade_id"] for r in data["topic_placements"])
    upsert(
        db,
        CatalogLevel,
        [
            {
                "id": r["id"],
                "subject_id": subject_ids[r["subject_id"]],
                "title": r["title"],
                "level_type": r["level_type"],
                "level_number": r.get("level_number"),
                "has_topics": bool(placement_counts[r["id"]]),
                "data": r,
                "snapshot_id": snapshot_id,
            }
            for r in data["grades"]
        ],
        ["id"],
    )
    areas = {}
    for row in data["topic_placements"]:
        areas.setdefault(row["topic_id"], set()).add(row["area"])
    breadcrumbs = {}
    for row in data["public_topic_documents"]:
        if row.get("requested_topic_match") is True:
            breadcrumbs.setdefault(row["topic_id"], set()).update(b["title"] for b in row.get("breadcrumbs", []))
    upsert(
        db,
        CatalogTopic,
        [
            {
                "id": r["id"],
                "subject_id": subject_ids[r["subject_id"]],
                "title": r["title"],
                "entry_url": r["entry_url"],
                "search_text": "\n".join(
                    [r["title"], *sorted(areas.get(r["id"], [])), *sorted(breadcrumbs.get(r["id"], []))]
                ),
                "empty_curated": r.get("curated_list_empty_verified") is True,
                "data": r,
                "snapshot_id": snapshot_id,
            }
            for r in data["topics"]
        ],
        ["id"],
    )
    upsert(
        db,
        CatalogPlacement,
        [
            {
                "id": placement_id(r),
                "topic_id": r["topic_id"],
                "level_id": r["grade_id"],
                "area": r["area"],
                "entry_url": r["entry_url"],
                "data": r,
                "snapshot_id": snapshot_id,
            }
            for r in data["topic_placements"]
        ],
        ["id"],
    )
    upsert(
        db,
        CatalogContent,
        [
            {
                "id": r["id"],
                "title": r["title"],
                "url": r["url"],
                "content_type": r["content_type"],
                "title_verified": r["title_verified"],
                "data": r,
                "snapshot_id": snapshot_id,
            }
            for r in data["videos"]
        ],
        ["id"],
    )
    general_links = {}
    for row in data["public_topic_links"]:
        if row.get("membership_verified") is True:
            general_links.setdefault((row["topic_id"], row["video_id"]), row["url"])
    upsert(
        db,
        CatalogMembership,
        [
            {
                "topic_id": r["topic_id"],
                "content_id": r["video_id"],
                "url": r["url"],
                "curated": r["curated_class_membership_verified"],
                "position": r.get("position"),
                "data": r,
                "snapshot_id": snapshot_id,
            }
            | {
                "general_verified": (r["topic_id"], r["video_id"]) in general_links,
                "general_url": general_links.get((r["topic_id"], r["video_id"])),
            }
            for r in data["topic_videos"]
        ],
        ["topic_id", "content_id"],
    )
    for kind in (
        "sources",
        "public_topic_documents",
        "public_topic_links",
        "content_metadata_sources",
        "sitemap_content_pages",
    ):
        values = []
        for row in data[kind]:
            key = row.get("id") or row.get("file") or fingerprint(row["url"])
            values.append({"kind": kind, "key": key, "data": row, "snapshot_id": snapshot_id})
        if len({v["key"] for v in values}) != len(values):
            raise CatalogError("Doppelte Herkunftskennung.")
        upsert(db, CatalogProvenance, values, ["kind", "key"])
    upsert(db, CatalogState, [{"provider": "sofatutor", "snapshot_id": snapshot_id}], ["provider"])
    if state:
        db.expire(state)
    # Each snapshot has exactly one local backfill. Reimports preserve feedback,
    # confirmed selections, activities and old provider identities.
    refresh_id = fingerprint([snapshot_id, "tips-v1"])
    if not db.get(CatalogRefresh, refresh_id):
        db.add(CatalogRefresh(id=refresh_id, snapshot_id=snapshot_id))
    from .security import audit

    audit(db, "system", "catalog.import", snapshot_id)
    return report | {"snapshot_id": snapshot_id, "repeated": False}


def ensure_bundled():
    data, snapshot = read_catalog()
    with DB.begin() as db:
        state = db.get(CatalogState, "sofatutor")
        if state and state.snapshot_id == snapshot:
            return
        import_catalog(db, data, snapshot)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=BUNDLE)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--rebuild-tips", action="store_true", help="Explicit local backfill, no AI request")
    args = parser.parse_args()
    if args.validate_only and args.rebuild_tips:
        parser.error("Eine reine Prüfung startet keinen Hintergrundlauf.")
    data, snapshot = read_catalog(args.catalog)
    if args.validate_only:
        review = source_review(snapshot)
        report = validate(data, args.csv) | {
            "snapshot_id": snapshot,
            "written": False,
            "source_errors": review.get("counts", {}).get("errors"),
            "source_warnings": review.get("counts", {}).get("warnings"),
        }
    else:
        with DB.begin() as db:
            report = import_catalog(db, data, snapshot, args.csv) | {"written": True}
            if args.rebuild_tips:
                row = db.get(CatalogRefresh, fingerprint([snapshot, "tips-v1"]))
                if row is None:
                    row = CatalogRefresh(id=fingerprint([snapshot, "tips-v1"]), snapshot_id=snapshot)
                    db.add(row)
                row.status, row.phase, row.cursor, row.processed = "queued", 0, "", 0
                row.error, row.lease, row.updated = None, None, int(now())
                report["tips_backfill_queued"] = True
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
