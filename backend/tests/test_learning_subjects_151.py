"""Subject-first browsing and uniform topic choice, entirely artificial data."""

from datetime import timedelta

import pytest
from conftest import create_child
from schulpilot import library
from schulpilot.db import DB, Activity, Assignment, Attempt, Child, Job, LearningUnit, Usage, now
from schulpilot.learning import local_day
from schulpilot.subject_registry import resolve
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select, update


def unit(db, child_id, topic, *, subject="Mathematik", subject_id=None, status="not_started"):
    value = LearningUnit(child_id=child_id, subject=subject, subject_id=subject_id, topic=topic,
        explanation="Nur künstlicher privater Erklärungstext.", questions=sample_unit()["questions"],
        provider="synthetic", synthetic=True, estimated_minutes=5, status=status,
        completed=int(now()) if status == "completed" else None)
    db.add(value)
    db.flush()
    if subject_id:
        # Historical identity with an unchanged old display label.
        db.execute(update(LearningUnit).where(LearningUnit.id == value.id).values(subject_id=subject_id))
    return value.id


def sid(title):
    with DB() as db:
        return resolve(db, title).id


def get(api, child, suffix="", **params):
    response = api.get(f"/api/children/{child['id']}/learning{suffix}", params=params)
    assert response.status_code == 200, response.text
    return response.json()


def test_subject_counts_merge_aliases_and_history_without_private_bodies(api, household):
    _, child = household
    math = sid("Mathematik")
    with DB.begin() as db:
        unit(db, child["id"], "Brüche", subject="Mathe")
        unit(db, child["id"], " BRÜCHE ", status="paused")
        unit(db, child["id"], "Geometrie", subject="Alte Beschriftung", subject_id=math, status="completed")
        unit(db, child["id"], "Satzglieder", subject="Deutsch")
    data = get(api, child, "/subjects")
    row = next(row for row in data["items"] if row["id"] == math)
    assert row["topic_count"] == 2
    assert row["ready_count"] == 2 and row["completed_count"] == 1
    assert "Erklärungstext" not in str(data) and "questions" not in str(data)
    assert get(api, child, subject_id=math, section="completed")["total"] == 1


def test_topics_are_grouped_before_paging_and_saved_rounds_stay_reachable(api, household):
    _, child = household
    with DB.begin() as db:
        old = unit(db, child["id"], "Brüche")
        active = unit(db, child["id"], " BRÜCHE ", status="paused")
        for number in range(26):
            unit(db, child["id"], f"Thema {number:02}")
        unit(db, child["id"], "Satzglieder", subject="Deutsch")
    first = get(api, child, subject_id=sid("Mathematik"), topic_view=True)
    assert first["total"] == 27 and first["pages"] == 2
    grouped = next(item for item in first["items"] if item["topic_key"] == library.topic_key("Brüche"))
    assert grouped["group_count"] == 2 and len(grouped["entries"]) == 1
    assert grouped["entries"][0]["id"] == active
    second = get(api, child, subject_id=sid("Mathematik"), topic_view=True, page=2)
    assert len(second["items"]) == 7
    assert not {row["topic_key"] for row in first["items"]} & {row["topic_key"] for row in second["items"]}
    rounds = get(api, child, subject_id=sid("Mathematik"), topic=grouped["topic_key"])
    assert {row["id"] for row in rounds["items"]} == {old, active}


def test_random_choice_includes_all_topics_and_does_not_weight_duplicate_rounds(api, household, monkeypatch):
    _, child = household
    with DB.begin() as db:
        for number in range(31):
            unit(db, child["id"], f"Thema {number:02}")
        for _ in range(9):
            unit(db, child["id"], "Thema 00")
        unit(db, child["id"], "Fremdes Fach", subject="Deutsch")
    choices = []

    def choose(values):
        choices.extend(values)
        return values[-1]

    monkeypatch.setattr(library.secrets, "choice", choose)
    data = get(api, child, f"/subjects/{sid('Mathematik')}/random")
    assert len(choices) == 31
    assert sorted(map(len, choices)) == [1] * 30 + [10]
    assert data["item"]["topic"] == "Thema 30"
    with DB() as db:
        for model in (Job, Usage, Attempt, Activity):
            assert db.scalar(select(func.count()).select_from(model)) == 0
        assert db.scalar(select(func.count()).select_from(LearningUnit).where(LearningUnit.status != "not_started")) == 0


def test_random_keeps_started_work_within_the_chosen_topic(api, household, monkeypatch):
    _, child = household
    with DB.begin() as db:
        unit(db, child["id"], "Brüche")
        paused = unit(db, child["id"], "Brüche", status="paused")
    monkeypatch.setattr(library.secrets, "choice", lambda rows: rows[0])
    assert get(api, child, f"/subjects/{sid('Mathematik')}/random")["item"]["id"] == paused


def test_completed_topics_are_bounded_before_pagination_and_keep_all_rounds(api, household):
    _, child = household
    with DB.begin() as db:
        for number in range(47):
            unit(db, child["id"], f"Thema {number % 4}", status="completed")
    data = get(api, child, subject_id=sid("Mathematik"), section="completed", topic_view=True, page_size=2)
    assert data["total"] == 4 and data["pages"] == 2
    assert len(data["items"]) == 2
    assert all(len(row["entries"]) == 1 for row in data["items"])
    chosen = data["items"][0]
    details = get(api, child, subject_id=sid("Mathematik"), topic=chosen["topic_key"], section="completed")
    assert details["total"] == chosen["group_count"] == 12
    assert all(row["status"] == "completed" for row in details["items"])


def test_future_assignments_and_completed_rounds_are_not_random_start_candidates(api, household):
    _, child = household
    with DB.begin() as db:
        unit(db, child["id"], "Alte Runde", status="completed")
        profile = db.get(Child, child["id"])
        db.add(Assignment(child_id=child["id"], kind="parent", subject="Mathematik", topic="Zukünftiger Auftrag",
            mandatory=True, scheduled_for=(local_day(profile) + timedelta(days=2)).isoformat()))
    data = get(api, child, subject_id=sid("Mathematik"))
    assert data["random_available"] is False
    assert api.get(f"/api/children/{child['id']}/learning/subjects/{sid('Mathematik')}/random").status_code == 409
    assert get(api, child, subject_id=sid("Mathematik"), section="later")["total"] == 1


def test_pending_preparation_disables_only_new_random_start_not_saved_round_access(api, household):
    _, child = household
    with DB.begin() as db:
        identifier = unit(db, child["id"], "Brüche")
        job = Job(child_id=child["id"], kind="unit", payload={}, status="queued", idempotency="artificial-151")
        db.add(job)
        db.flush()
        job_id = job.id
    data = get(api, child, subject_id=sid("Mathematik"), topic_view=True)
    assert data["learning_preparation"] == {"id": job_id, "status": "queued"}
    assert data["items"][0]["entries"][0]["id"] == identifier
    assert api.get(f"/api/children/{child['id']}/learning/subjects/{sid('Mathematik')}/random").status_code == 409


def test_empty_subjects_and_unknown_subject_filters_have_clear_results(api, household):
    _, child = household
    assert get(api, child, subject_id=sid("Mathematik"))["total"] == 0
    assert api.get(f"/api/children/{child['id']}/learning?subject_id={'f'*32}").status_code == 404
    assert api.get(f"/api/children/{child['id']}/learning?topic_view=true").status_code == 422
    assert api.get(f"/api/children/{child['id']}/learning?topic=invalid").status_code == 422


@pytest.mark.parametrize("suffix", ["/subjects", "/subjects/{math}/random", "?subject_id={math}&topic_view=true"])
def test_child_cannot_read_sibling_subjects_or_choose_a_sibling_round(api, household, suffix):
    user, child = household
    sibling = create_child(api, user, "artificial-sibling-151")
    reply = api.post("/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"})
    assert reply.status_code == 200
    api.headers["Authorization"] = "Bearer " + reply.json()["token"]
    path = suffix.format(math=sid("Mathematik"))
    assert api.get(f"/api/children/{sibling['id']}/learning{path}").status_code == 404
    assert api.get(f"/api/children/{child['id']}/learning/subjects").status_code == 200
