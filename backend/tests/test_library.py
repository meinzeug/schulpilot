"""Artificial large reading lists, private scope and read-only pagination."""

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from conftest import HEADERS, create_child, register
from fastapi.testclient import TestClient
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Material,
    Membership,
    SchoolDay,
    Usage,
    User,
    now,
)
from schulpilot.learning import local_day
from schulpilot.main import app
from schulpilot.security import password_hash
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select


def add_pages(db, child_id, count):
    for number in range(count):
        db.add(
            Material(
                id=f"{number:032x}",
                child_id=child_id,
                title=f"Künstliche Notiz {number:04}",
                topic=f"Thema {number:04}",
                subject=["Mathematik", "Deutsch", "Englisch"][number % 3],
                content="Privater künstlicher Quelltext, gehört nicht in die Listenansicht. " * 60,
                confirmed=number % 2 == 0,
                status="confirmed" if number % 2 == 0 else "review",
                synthetic=True,
                created=1700000000 + number,
            )
        )


def list_pages(api, child_id, **params):
    reply = api.get(f"/api/children/{child_id}/materials", params=params)
    assert reply.status_code == 200, reply.text
    return reply.json()


def test_all_1205_pages_can_be_read_without_duplicates_or_private_bodies(api, household):
    _, child = household
    with DB.begin() as db:
        add_pages(db, child["id"], 1205)
    seen = []
    for page in range(1, 26):
        data = list_pages(api, child["id"], page=page, page_size=50)
        assert data["total"] == 1205 and data["pages"] == 25 and data["page"] == page
        assert len(data["items"]) == (5 if page == 25 else 50)
        assert sum(s["count"] for s in data["subjects"]) == 1205
        for item in data["items"]:
            assert not {"content", "path", "homework", "uncertainties", "extraction_model"} & item.keys()
        seen.extend(item["id"] for item in data["items"])
    assert len(set(seen)) == len(seen) == 1205
    last = list_pages(api, child["id"], page=1000000, page_size=50)
    assert last["page"] == 25 and last["items"][-1]["id"] in seen
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_subject_status_search_and_stable_creation_sort_combine(api, household):
    _, child = household
    with DB.begin() as db:
        add_pages(db, child["id"], 90)
    data = list_pages(
        api, child["id"], q="THEMA 00", subject="Deutsch", status="confirmed", sort="oldest", page_size=50
    )
    assert data["total"] == 15
    assert [item["created"] for item in data["items"]] == sorted(item["created"] for item in data["items"])
    assert all(item["subject"] == "Deutsch" and item["confirmed"] for item in data["items"])
    assert {s["value"] for s in data["subjects"]} == {"Mathematik", "Deutsch", "Englisch"}
    reverse = list_pages(api, child["id"], subject="Deutsch", status="confirmed", sort="newest", page_size=50)
    assert [item["id"] for item in data["items"]] == [item["id"] for item in reverse["items"]][::-1]


@pytest.mark.parametrize("query", ["KÜRZEN", "kürzen", "STRASSE", "MATHEMATIK"])
def test_german_casefold_searches_the_saved_source_without_returning_it(api, household, query):
    _, child = household
    with DB.begin() as db:
        db.add(
            Material(
                child_id=child["id"],
                title="Künstliche Notiz",
                topic="Ein Beispiel",
                content="Kürzen auf der Straße.",
                subject="Mathematik",
            )
        )
    data = list_pages(api, child["id"], q=query)
    assert data["total"] == 1 and "content" not in data["items"][0]


def test_search_wildcards_are_literal_and_unknown_subject_is_filterable(api, household):
    _, child = household
    with DB.begin() as db:
        add_pages(db, child["id"], 12)
        db.add(Material(child_id=child["id"], title=r"Notiz 7%_\Probe", subject="   ", content="Künstlicher Text"))
    data = list_pages(api, child["id"], q=r"7%_\Probe", subject="")
    assert data["total"] == 1
    assert list_pages(api, child["id"], q="%' OR 1=1 --")["total"] == 0


def test_date_range_uses_school_date_and_local_upload_day(api, household):
    _, child = household
    zone = ZoneInfo("Europe/Berlin")
    start = int(datetime(2026, 10, 5, tzinfo=zone).timestamp())
    with DB.begin() as db:
        profile = db.get(Child, child["id"])
        profile.preferences = {**profile.preferences, "timezone": "Europe/Berlin"}
        day = SchoolDay(child_id=child["id"], school_date="2026-10-05")
        db.add(day)
        db.flush()
        db.add_all(
            [
                Material(
                    child_id=child["id"], title="Unterricht vom Montag", school_day_id=day.id, created=start + 86400 * 3
                ),
                Material(child_id=child["id"], title="Standalone vom Montag", created=start),
                Material(child_id=child["id"], title="Vor Montag", created=start - 1),
                Material(child_id=child["id"], title="Nach Montag", created=start + 86400),
            ]
        )
    data = list_pages(api, child["id"], since="2026-10-05", until="2026-10-05")
    assert data["total"] == 2 and {item["title"] for item in data["items"]} == {
        "Unterricht vom Montag",
        "Standalone vom Montag",
    }
    assert api.get(f"/api/children/{child['id']}/materials?since=2026-10-06&until=2026-10-05").status_code == 422


@pytest.mark.parametrize(
    "params",
    [
        {"page": 0},
        {"page_size": 0},
        {"page_size": 51},
        {"sort": "sql"},
        {"status": "everything"},
        {"since": "not-a-date"},
        {"q": "x" * 121},
    ],
)
def test_invalid_filters_are_rejected(api, household, params):
    _, child = household
    assert api.get(f"/api/children/{child['id']}/materials", params=params).status_code == 422


def test_library_scopes_children_parents_revocation_and_admins(api, household, mailbox):
    parent, child = household
    sibling = create_child(api, parent, "other-child")
    with DB.begin() as db:
        add_pages(db, child["id"], 6)
        db.add(Material(child_id=sibling["id"], title="Anderes Kind", subject="Geheimfach"))
    with TestClient(app, headers=HEADERS) as client:
        login = client.post(
            "/api/auth/login", json={"username": "test-child", "password": "secure-child-pass-123"}
        ).json()
        client.headers["Authorization"] = "Bearer " + login["token"]
        assert list_pages(client, child["id"])["total"] == 6
        for endpoint in ("materials", "learning"):
            assert client.get(f"/api/children/{sibling['id']}/{endpoint}").status_code == 404
        assert "Geheimfach" not in str(list_pages(client, child["id"])["subjects"])
        assert client.post("/api/auth/logout").status_code == 200
        assert client.get(f"/api/children/{child['id']}/materials").status_code == 401
    with TestClient(app, headers=HEADERS) as other:
        stranger = register(other, mailbox, "another@example.org")
        assert other.get(f"/api/children/{child['id']}/materials").status_code == 404
        with DB.begin() as db:
            db.add(Membership(user_id=stranger["id"], family_id=parent["families"][0]["id"], permission="view"))
        assert list_pages(other, child["id"])["total"] == 6
        with DB.begin() as db:
            db.delete(
                db.scalar(
                    select(Membership).where(
                        Membership.user_id == stranger["id"], Membership.family_id == parent["families"][0]["id"]
                    )
                )
            )
        assert other.get(f"/api/children/{child['id']}/materials").status_code == 404
    with DB.begin() as db:
        admin = User(
            username="library-admin",
            display_name="Testadmin",
            role="admin",
            verified=True,
            password_hash=password_hash("synthetic-admin-password"),
        )
        db.add(admin)
    with TestClient(app, headers=HEADERS) as client:
        login = client.post(
            "/api/auth/login", json={"username": "library-admin", "password": "synthetic-admin-password"}
        ).json()
        client.headers["Authorization"] = "Bearer " + login["token"]
        assert client.get(f"/api/children/{child['id']}/materials").status_code == 403
        assert client.get(f"/api/children/{child['id']}/learning").status_code == 403


def test_compact_home_has_counts_and_small_previews_but_legacy_view_is_preserved(api, household):
    _, child = household
    with DB.begin() as db:
        add_pages(db, child["id"], 120)
    data = api.get(f"/api/children/{child['id']}/overview?compact=true").json()
    assert data["material_count"] == 120 and len(data["materials"]) <= 24
    assert len(data["plan"]["today"]) <= 3 and len(data["plan"]["later"]) <= 1
    assert all("content" not in item for item in data["materials"])
    assert all("questions" not in item for item in data["units"])
    legacy = api.get(f"/api/children/{child['id']}/overview").json()
    assert len(legacy["materials"]) == 120 and all("content" in item for item in legacy["materials"])


def test_learning_archive_paginates_summaries_without_keys_answers_or_new_jobs(api, household):
    _, child = household
    with DB.begin() as db:
        for index in range(45):
            unit = LearningUnit(
                child_id=child["id"],
                subject=["Mathematik", "Englisch"][index % 2],
                topic=f"Runde {index}",
                explanation="Künstlicher Lerntext",
                questions=sample_unit()["questions"],
                provider="synthetic",
                synthetic=True,
                status="completed",
                completed=int(now()) - index,
            )
            db.add(unit)
            db.flush()
            db.add_all(
                [
                    Attempt(unit_id=unit.id, question_id="sum", answer="Privat", outcome="incorrect", assisted=False),
                    Attempt(unit_id=unit.id, question_id="sum", answer="Privat", outcome="correct", assisted=False),
                    Attempt(
                        unit_id=unit.id, question_id="reduce", answer="Privat", outcome="incorrect", assisted=False
                    ),
                ]
            )
    results = []
    for page in range(1, 4):
        response = api.get(f"/api/children/{child['id']}/learning", params={"section": "completed", "page": page})
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["total"] == 45
        for item in data["items"]:
            assert item["question_count"] == 4 and item["closed_questions"] == 1 and item["attempted_questions"] == 2
            assert not {"questions", "answer", "explanation"} & item.keys()
        results.extend(item["id"] for item in data["items"])
    assert len(set(results)) == 45
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0


def test_learning_room_preserves_plan_and_filters_future_parent_orders(api, household):
    _, child = household
    with DB.begin() as db:
        profile = db.get(Child, child["id"])
        profile.preferences = {**profile.preferences, "weekdays": list(range(7)), "daily_minutes": 30}
        future = (local_day(profile) + timedelta(days=2)).isoformat()
        for n in range(2):
            db.add(
                LearningUnit(
                    child_id=child["id"],
                    subject=["Mathematik", "Deutsch"][n],
                    topic=f"Neue Runde {n}",
                    explanation="Künstliche Erklärung",
                    questions=sample_unit()["questions"],
                    provider="synthetic",
                    synthetic=True,
                    estimated_minutes=5,
                )
            )
        db.add(
            Assignment(
                child_id=child["id"],
                kind="parent",
                subject="Englisch",
                topic="Unregelmäßige Verben",
                mandatory=True,
                scheduled_for=future,
            )
        )
    before = api.get(f"/api/children/{child['id']}/overview").json()["plan"]
    ready = api.get(f"/api/children/{child['id']}/learning?section=ready").json()
    assert ready["total"] == 2 and ready["sections"]["later"] == 1
    later = api.get(
        f"/api/children/{child['id']}/learning", params={"section": "later", "subject": "Englisch", "q": "VERBEN"}
    ).json()
    assert later["total"] == 1 and later["items"][0]["mandatory"] is True
    assert later["items"][0]["scheduled_for"] == future
    assert api.get(f"/api/children/{child['id']}/overview").json()["plan"] == before
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0


def test_learning_pause_keeps_rounds_voluntarily_ready_without_starting_them(api, household):
    _, child = household
    with DB.begin() as db:
        profile = db.get(Child, child["id"])
        profile.preferences = {
            **profile.preferences,
            "pause_until": (local_day(profile) + timedelta(days=2)).isoformat(),
        }
        db.add(
            LearningUnit(
                child_id=child["id"],
                subject="Mathematik",
                topic="Brüche",
                explanation="Künstlicher Text",
                questions=sample_unit()["questions"],
                provider="synthetic",
                synthetic=True,
            )
        )
    ready = api.get(f"/api/children/{child['id']}/learning?section=ready").json()
    later = api.get(f"/api/children/{child['id']}/learning?section=later").json()
    assert ready["paused"] is True and ready["total"] == 1
    assert ready["items"][0]["status"] == "not_started"
    assert later["total"] == 0
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_voluntary_learning_is_paginated_after_goals_and_preserves_future_release_dates(api, household):
    _, child = household
    with DB.begin() as db:
        profile = db.get(Child, child["id"])
        tomorrow = (local_day(profile) + timedelta(days=1)).isoformat()
        profile.preferences = {
            "weekdays": [],
            "daily_minutes": 5,
            "weekly_minutes": 5,
            "session_minutes": 5,
            "pause_until": tomorrow,
        }
        db.add(Activity(child_id=profile.id, kind="active_time", detail={"seconds": 3600}, created=int(now())))
        for index in range(45):
            db.add(
                LearningUnit(
                    child_id=profile.id,
                    **sample_unit(),
                    estimated_minutes=8,
                    created=int(now()) - index,
                    provider="synthetic-fixture",
                )
            )
        db.add(LearningUnit(child_id=profile.id, **sample_unit(), not_before=tomorrow, provider="synthetic-fixture"))
        assignment = Assignment(
            child_id=profile.id, kind="parent", subject="Deutsch", topic="Später", scheduled_for=tomorrow
        )
        db.add(assignment)
        db.flush()
        db.add(
            LearningUnit(
                child_id=profile.id, **sample_unit(), assignment_id=assignment.id, provider="synthetic-fixture"
            )
        )
    seen = []
    for page in range(1, 4):
        response = api.get(f"/api/children/{child['id']}/learning", params={"page": page, "page_size": 20})
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["total"] == 45 and data["pages"] == 3
        assert not data["daily_goal_met"] and not data["goal_required"]
        assert data["weekly_goal_met"]
        assert data["daily_active_seconds"] == data["weekly_active_seconds"] == 3600
        assert data["can_continue_voluntarily"] and data["optional_learning"]
        assert len(data["items"]) == (5 if page == 3 else 20)
        assert all("questions" not in item and "explanation" not in item for item in data["items"])
        seen.extend(item["id"] for item in data["items"])
    assert len(set(seen)) == len(seen) == 45
    later = api.get(f"/api/children/{child['id']}/learning?section=later").json()
    assert later["total"] == 2
    with DB() as db:
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Usage)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0


def test_removing_the_last_page_result_returns_to_a_valid_page(api, household):
    _, child = household
    with DB.begin() as db:
        add_pages(db, child["id"], 21)
    last = list_pages(api, child["id"], page=2, sort="oldest")
    assert len(last["items"]) == 1
    assert api.delete(f"/api/materials/{last['items'][0]['id']}").status_code == 200
    after = list_pages(api, child["id"], page=2, sort="oldest")
    assert after["total"] == 20 and after["page"] == after["pages"] == 1 and len(after["items"]) == 20
