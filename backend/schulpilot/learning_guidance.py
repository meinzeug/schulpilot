"""Choose instructional support from saved evidence, without exporting grades."""

from .grades import priorities, subject_key
from .learning_progress import read_ledger


def strategies(db, child):
    emphasis = priorities(db, child)
    result = {key: "guided_example" for key in emphasis}
    seen = {}
    for row in read_ledger(db, child.id):
        key = subject_key(row["subject"])
        if seen.get(key, 0) >= 2:
            continue
        seen[key] = seen.get(key, 0) + 1
        if row["assisted_tasks"] or row["needs_practice_tasks"] or row["uncertain_tasks"]:
            result[key] = "guided_example"
        else:
            result.setdefault(key, "practice_and_retrieval")
    return result
