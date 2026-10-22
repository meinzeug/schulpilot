"""PP032–039: bounded parent filters search full collections without learning writes."""
from datetime import timedelta

import pytest
from schulpilot.db import DB, Activity, Assignment, Attempt, Child, Job, LearningUnit, Material, Usage
from schulpilot.learning import local_day
from sqlalchemy import func, select
from test_tutor import notebook as _notebook


@pytest.fixture
def book(api, household):
    yield from _notebook.__wrapped__(api, household)


def counts():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model))
                     for model in (Activity, Assignment, Attempt, Job, LearningUnit, Usage))


def seed_topics(book):
    with DB.begin() as db:
        child = db.get(Child, book["child"]["id"])
        today = local_day(child)
        for index in range(24):
            db.add(Assignment(child_id=child.id, kind="parent", subject="Englisch",
                topic=f"Vokabelthema {index}", created=100 + index))
        wanted = Assignment(child_id=child.id, kind="parent", subject="Mathematik", topic="100%_Brüche",
            note="Zähler sicher lesen", material_id=book["material_id"], source_status="needs_review",
            mandatory=False, due=today.isoformat(), created=1)
        db.add(wanted)
        db.add_all([
            Assignment(child_id=child.id, kind="exam", subject="Biologie", topic="Zellen",
                due=(today + timedelta(days=2)).isoformat(), created=50),
            Assignment(child_id=child.id, kind="parent", subject="Physik", topic="Kräfte",
                due=(today - timedelta(days=2)).isoformat(), done=True, created=51),
        ])
        db.flush()
        return wanted.id


def seed_photos(book):
    with DB.begin() as db:
        for index in range(24):
            db.add(Material(child_id=book["child"]["id"], purpose="homework", subject="Englisch",
                topic=f"Wörter {index}", title="Arbeitsheft", created=100 + index))
        target = Material(child_id=book["child"]["id"], purpose="homework", subject="Mathematik",
            topic="Flächen", title="Seite 100%_B", created=1)
        db.add(target)
        db.flush()
        return target.id


@pytest.mark.parametrize("filters", [
    {"q": "100%_Brüche"}, {"q": " ZÄHLER "}, {"subject": "Mathematik"},
    {"source": "changed"}, {"source": "notebook"}, {"obligation": "voluntary"}, {"timing": "today"},
])
def test_pp034_038_assignment_filters_reach_an_old_item_beyond_first_page(api, book, filters):
    wanted = seed_topics(book)
    before = counts()
    endpoint = f"/api/children/{book['child']['id']}/learning-plan"
    assert wanted not in {a["id"] for a in api.get(endpoint).json()["topics"]}
    for _ in range(2):
        result = api.get(endpoint, params=filters)
        assert result.status_code == 200, result.text
        value = result.json()
        assert [a["id"] for a in value["topics"]] == [wanted]
        assert value["pagination"] == {"page": 1, "pages": 1, "total": 1}
        assert value["filters"][next(iter(filters))] == next(iter(filters.values())).strip()
        assert "Mathematik" in value["subjects"]
    assert counts() == before


@pytest.mark.parametrize("filters,subject", [
    ({"timing": "future"}, "Biologie"),
    ({"timing": "past", "include_completed": "true"}, "Physik"),
    ({"source": "manual", "subject": "Englisch"}, "Englisch"),
    ({"timing": "undated", "subject": "Englisch"}, "Englisch"),
    ({"obligation": "mandatory", "subject": "Biologie"}, "Biologie"),
])
def test_pp036_038_real_source_duty_and_date_filters_compose(api, book, filters, subject):
    seed_topics(book)
    value = api.get(f"/api/children/{book['child']['id']}/learning-plan", params=filters).json()
    assert value["topics"]
    assert {a["subject"] for a in value["topics"]} == {subject}
    assert len(value["topics"]) <= 20


@pytest.mark.parametrize("filters", [{"q": "100%_B"}, {"q": "fläch"}, {"subject": "Mathematik"}])
def test_pp032_033_homework_search_and_subject_reach_an_old_photo(api, book, filters):
    wanted = seed_photos(book)
    before = counts()
    endpoint = f"/api/children/{book['child']['id']}/homework-review"
    assert wanted not in {a["id"] for a in api.get(endpoint).json()["photos"]}
    for _ in range(2):
        result = api.get(endpoint, params=filters)
        assert result.status_code == 200, result.text
        value = result.json()
        assert [a["id"] for a in value["photos"]] == [wanted]
        assert value["total"] == 1 and value["next_cursor"] is None
        assert value["subjects"] == ["Englisch", "Mathematik"]
    assert counts() == before


def test_pp032_038_search_wildcards_are_literal_and_limits_are_bounded(api, book):
    seed_topics(book)
    seed_photos(book)
    prefix = f"/api/children/{book['child']['id']}"
    for route, items in [("learning-plan", "topics"), ("homework-review", "photos")]:
        assert len(api.get(f"{prefix}/{route}", params={"q": "%_"}).json()[items]) == 1
        assert api.get(f"{prefix}/{route}", params={"q": "no-match"}).json()[items] == []
        assert api.get(f"{prefix}/{route}", params={"q": "a" * 161}).status_code == 422
        assert api.get(f"{prefix}/{route}", params={"subject": "a" * 161}).status_code == 422
        assert book["client"].get(f"{prefix}/{route}", params={"q": "Zähler"}).status_code == 403
    for key in ["source", "obligation", "timing"]:
        assert api.get(f"{prefix}/learning-plan", params={key: "unknown"}).status_code == 422


def test_pp039_recent_rounds_have_their_real_total_without_changing_evidence(api, book):
    wanted = seed_topics(book)
    with DB.begin() as db:
        base = db.get(LearningUnit, book["unit_id"])
        for index in range(13):
            db.add(LearningUnit(child_id=base.child_id, assignment_id=wanted, subject="Mathematik",
                topic=f"Gespeicherte Runde {index}", explanation="Künstlich.", questions=[], provider="synthetic",
                status="completed", created=index + 200, completed=index + 201))
    before = counts()
    value = api.get(f"/api/children/{book['child']['id']}/learning-plan", params={"source": "changed"}).json()
    row = value["topics"][0]
    assert row["recent_unit_count"] == 13 and len(row["recent_units"]) == 10
    assert counts() == before


def test_pp051_deleting_a_stale_goal_never_removes_its_newer_revision_or_evidence(api, book):
    wanted = seed_topics(book)
    with DB.begin() as db:
        db.get(LearningUnit, book["unit_id"]).assignment_id = wanted
        db.get(Assignment, wanted).revision = 2
    endpoint = f"/api/children/{book['child']['id']}/assignments/{wanted}"
    before = counts()
    assert api.delete(endpoint + "?revision=1").status_code == 409
    assert book["client"].delete(endpoint + "?revision=2").status_code == 403
    assert counts() == before
    with DB() as db:
        assert db.get(Assignment, wanted).revision == 2
    assert api.delete(endpoint + "?revision=0").status_code == 422
    assert api.delete(endpoint + "?revision=2").status_code == 200
    with DB() as db:
        assert db.get(Assignment, wanted) is None
        assert db.get(LearningUnit, book["unit_id"]) is not None
        assert db.scalar(select(func.count()).select_from(Usage)) == before[-1]
