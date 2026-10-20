"""Local, explicitly scoped operator cleanup; never a public/admin content API.

Preview counts/digest contain no content. Apply locks Unit before Child, checks
exact state again, journals removals and retains provider/accounting history.
"""

import argparse
import hashlib
import json

from sqlalchemy import select

from .db import (
    DB,
    Assignment,
    Child,
    Job,
    LanguageProject,
    LearningUnit,
    Material,
    SchoolDay,
    UnitSource,
    VocabularyItem,
)
from .material_actions import ensure_idle, lock_units
from .security import audit
from .unit_erasure import counts, references, remove, snapshot, word_source_revisions


def selection(db, child_id, *, include_manual_assignments=False, include_manual_vocabulary=False):
    from .study_path import source_backed_blocks

    child = db.get(Child, child_id)
    if child is None:
        raise ValueError("Kind nicht gefunden.")
    material_ids = set(db.scalars(select(Material.id).where(Material.child_id == child_id)))
    units = list(db.scalars(select(LearningUnit).where(LearningUnit.child_id == child_id).order_by(LearningUnit.id)))
    assignments = list(db.scalars(select(Assignment).where(Assignment.child_id == child_id).order_by(Assignment.id)))
    protected = {u.id for u in units if u.material_id in material_ids}
    protected.update(db.scalars(select(UnitSource.unit_id).join(LearningUnit).where(
        LearningUnit.child_id == child_id, UnitSource.material_id.in_(material_ids))))
    words = {word.id: word for word in db.scalars(select(VocabularyItem).where(
        VocabularyItem.child_id == child_id, VocabularyItem.confirmed.is_(True)))}
    word_sources = word_source_revisions(db, child_id)
    for unit in units:
        word_refs = [q["language"] for q in unit.questions
                     if isinstance(q, dict) and isinstance(q.get("language"), dict)
                     and q["language"].get("vocabulary_item_id")]
        word_ids = {ref["vocabulary_item_id"] for ref in word_refs}
        if word_ids and word_ids <= words.keys():
            sources = set().union(*(word_sources.get((ref["vocabulary_item_id"],
                ref.get("vocabulary_revision", words[ref["vocabulary_item_id"]].revision)), set()) for ref in word_refs))
            if sources & material_ids or not sources and not include_manual_vocabulary:
                protected.add(unit.id)
    for project in db.scalars(select(LanguageProject).where(LanguageProject.child_id == child_id)):
        sources = {source.get("id") for source in project.source_revisions}
        word_ids = {item.get("id") for item in project.item_revisions}
        if sources & material_ids or not sources and word_ids and word_ids <= words.keys() and not include_manual_vocabulary:
            protected.add(project.unit_id)
    def inherit_sources():
        while True:
            added = {u.id for u in units if any(parent in protected for parent in (u.review_of, u.followup_of, u.learning_root_id))} - protected
            if not added:
                break
            protected.update(added)

    inherit_sources()
    assignment_ids = []
    for assignment in assignments:
        sources = {source.get("id") for source in assignment.source_revisions}
        if assignment.material_id in material_ids or sources & material_ids or any(
                u.assignment_id == assignment.id and u.id in protected for u in units):
            continue
        if sources or include_manual_assignments:
            assignment_ids.append(assignment.id)
        else:
            protected.update(u.id for u in units if u.assignment_id == assignment.id)
    inherit_sources()
    unit_ids = sorted(u.id for u in units if u.id not in protected)
    plans = []
    for day in db.scalars(select(SchoolDay).where(SchoolDay.child_id == child_id).order_by(SchoolDay.id)):
        blocks = (day.learning_plan or {}).get("blocks", [])
        retained = source_backed_blocks(db, day)
        if retained != blocks:
            plans.append({"id": day.id, "revision": day.revision, "plan": day.learning_plan,
                          "retained": retained, "preparation": day.preparation,
                          "removed": len(blocks) - len(retained)})
    values = [{c.name: getattr(a, c.name) for c in Assignment.__table__.columns}
              for a in assignments if a.id in assignment_ids]
    digest = hashlib.sha256(json.dumps({"child": child_id, "units": snapshot(db, unit_ids),
        "assignments": values, "manual_assignments": include_manual_assignments,
        "manual_vocabulary": include_manual_vocabulary, "plans": plans}, sort_keys=True).encode()).hexdigest()
    return {"unit_ids": unit_ids, "assignment_ids": sorted(assignment_ids), "plan_ids": [p["id"] for p in plans], "digest": digest,
            **counts(db, unit_ids), "assignment_count": len(assignment_ids),
            "planned_stage_count": sum(p["removed"] for p in plans)}


def erase_assignments(db, child_id, ids, *, journal=True):
    from .erasure import request

    rows = list(db.scalars(select(Assignment).where(Assignment.child_id == child_id, Assignment.id.in_(ids))))
    selected = {row.id for row in rows}
    for job in db.scalars(select(Job).where(Job.child_id == child_id)):
        if references(job.payload, selected) or references(job.result, selected):
            job.payload, job.result, job.error = {}, {"deleted": True}, None
    for row in rows:
        if journal:
            request(db, "assignment", row.id)
        db.delete(row)
    return len(rows)


def apply(db, child_id, expected_digest, **options):
    # Same global order as notebook deletion and answer/tutor mutations.
    lock_units(db, child_id, [])
    child = db.scalar(select(Child).where(Child.id == child_id).with_for_update())
    if child is None:
        raise ValueError("Kind nicht gefunden.")
    list(db.scalars(select(Assignment).where(Assignment.child_id == child_id).order_by(Assignment.id).with_for_update()))
    list(db.scalars(select(SchoolDay).where(SchoolDay.child_id == child_id).order_by(SchoolDay.id).with_for_update()))
    db.expire_all()
    ensure_idle(db, child_id)
    selected = selection(db, child_id, **options)
    if selected["digest"] != expected_digest:
        raise ValueError("Der Bestand wurde verändert. Bitte neu prüfen; nichts wurde gelöscht.")
    remove(db, child, selected["unit_ids"])
    erase_assignments(db, child_id, selected["assignment_ids"])
    from .school_preparation import sources_removed

    for day_id in selected["plan_ids"]:
        day = db.get(SchoolDay, day_id)
        day.revision += 1
        sources_removed(db, day)
    audit(db, "local-operator", "operator.source_orphans_removed", child_id)
    return {k: selected[k] for k in ("unit_count", "answer_count", "assignment_count", "planned_stage_count")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--child-id", required=True)
    parser.add_argument("--include-manual-assignments", action="store_true")
    parser.add_argument("--include-manual-vocabulary", action="store_true")
    parser.add_argument("--apply-digest")
    args = parser.parse_args()
    options = {"include_manual_assignments": args.include_manual_assignments,
               "include_manual_vocabulary": args.include_manual_vocabulary}
    with DB.begin() as db:
        result = apply(db, args.child_id, args.apply_digest, **options) if args.apply_digest else selection(db, args.child_id, **options)
        if not args.apply_digest:
            audit(db, "local-operator", "operator.source_orphans_inspected", args.child_id)
    if args.apply_digest:
        from .erasure import flush_journal
        flush_journal()
    print(json.dumps({k: v for k, v in result.items() if not k.endswith("_ids")}))


if __name__ == "__main__":
    main()
