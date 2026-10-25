"""Today offers only source-current unpublished stages; saved work stays private."""

import copy
from datetime import timedelta

import pytest
from schulpilot import study_path
from schulpilot.db import (
    DB,
    Activity,
    Assignment,
    Attempt,
    Child,
    Job,
    LearningUnit,
    Mastery,
    Material,
    SchoolDay,
    UnitSource,
    Usage,
    now,
)
from schulpilot.learning import local_day, plan
from sqlalchemy import func, select
from test_study_path import create, path
from test_study_path import study as study_fixture


@pytest.fixture
def study(api, household):
    yield from study_fixture.__wrapped__(api, household)


def offers(value):
    return [*value["today"], *value["later"], *value["voluntary"],
            *[item for day in value["week"] for item in day["items"]]]


def snapshot(study):
    with DB() as db:
        return {"plan": copy.deepcopy(db.get(SchoolDay, study["day_id"]).learning_plan),
                "counts": [db.scalar(select(func.count()).select_from(model)) for model in
                           (Job, Usage, LearningUnit, Activity, Attempt, Mastery)],
                "attempts": [(a.id, copy.deepcopy(a.answer), a.outcome, a.assisted) for a in db.scalars(select(Attempt))]}


@pytest.mark.parametrize("change", ["revision", "unconfirmed", "same_revision_content", "missing_fingerprint"])
def test_other_source_changes_remove_unsaved_starts_without_get_mutation(study, monkeypatch, change):
    original = create(study)
    assert original["can_continue"] is True
    with DB.begin() as db:
        # The first offered block keeps its own current confirmed page.
        source = db.get(Material, study["materials"][-1])
        if change == "revision":
            source.revision += 1
        elif change == "unconfirmed":
            source.confirmed, source.status = False, "review"
        elif change == "same_revision_content":
            source.content += " Die Erde ist ein Planet."
        else:
            day = db.get(SchoolDay, study["day_id"])
            day.learning_plan = {key: value for key, value in day.learning_plan.items() if key != "source_hash"}
    monkeypatch.setattr(study_path, "request_provider", lambda *a, **kw: pytest.fail("GET cannot start AI"))
    before = snapshot(study)
    result = study["client"].get("/api/child/home?compact=true")
    assert result.status_code == 200, result.text
    value = result.json()["plan"]
    assert not any(item["kind"] == "study_path" and item["id"] == study["day_id"] for item in offers(value))
    assert value["blocked_study_paths"] == [{"day_id": study["day_id"], "date": value["date"], "reason_code": "source_changed"}]
    assert value["daily_goal_met"] is False and value["goal_required"] is True
    current = study["client"].get(path(study))
    assert current.status_code == 200 and current.json()["stale"] is True and current.json()["can_continue"] is False
    assert snapshot(study) == before


def test_unchanged_day_remains_offered_and_freshness_is_read_once_per_plan(study, monkeypatch):
    create(study)
    calls = []
    real = study_path.plan_sources_current

    def check(db, day):
        calls.append(day.id)
        return real(db, day)

    monkeypatch.setattr(study_path, "plan_sources_current", check)
    before = snapshot(study)
    with DB() as db:
        value = plan(db, db.get(Child, study["child"]["id"]))
    assert calls == [study["day_id"]]
    assert value["blocked_study_paths"] == []
    assert any(item["kind"] == "study_path" and item["id"] == study["day_id"] for item in value["voluntary"])
    assert value["can_continue_voluntarily"] is True
    assert snapshot(study) == before


def saved_unit(study, *, completed=False):
    with DB.begin() as db:
        page = db.get(Material, study["materials"][0])
        unit = LearningUnit(child_id=page.child_id, school_day_id=page.school_day_id, material_id=page.id,
            subject=page.subject, topic="Gespeicherte künstliche Runde", explanation="Die Sonne ist ein Stern.",
            questions=[{"id": f"q{i}", "type": "short", "prompt": f"Künstliche Frage {i}: Was ist die Sonne?",
                        "answer": "Ein Stern", "options": [], "accepted": [], "hints": [],
                        "explanation": "Die Sonne ist ein Stern."} for i in (1, 2)],
            provider="synthetic", model="own-fixture", status="completed" if completed else "active",
            completed=int(now()) - 8 * 86400 if completed else None, active_seconds=17)
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=page.id, revision=page.revision))
        db.add(Attempt(unit_id=unit.id, question_id="q1", answer="Ein Stern", outcome="correct", assisted=False))
        if not completed:
            day = db.get(SchoolDay, study["day_id"])
            value = copy.deepcopy(day.learning_plan)
            value["blocks"][0]["unit_id"] = unit.id
            day.learning_plan = value
        return unit.id


def test_saved_answered_open_unit_stays_available_when_other_day_source_changes(study):
    create(study)
    unit_id = saved_unit(study)
    with DB.begin() as db:
        db.get(Material, study["materials"][-1]).confirmed = False
    before = snapshot(study)
    response = study["client"].get("/api/child/home?compact=true")
    assert response.status_code == 200, response.text
    value = response.json()["plan"]
    assert any(item["kind"] == "unit" and item["id"] == unit_id for item in value["today"])
    assert any(item["kind"] == "unit" and item["id"] == unit_id for item in value["voluntary"])
    assert not any(item["kind"] == "study_path" for item in offers(value))
    assert value["blocked_study_paths"][0]["day_id"] == study["day_id"]
    assert snapshot(study) == before


def test_other_confirmed_notebook_and_current_day_stay_voluntarily_available(study):
    create(study)
    with DB.begin() as db:
        child = db.get(Child, study["child"]["id"])
        db.get(Material, study["materials"][-1]).revision += 1
        page = Material(child_id=child.id, title="Künstliche andere Heftseite", subject="Deutsch", topic="Künstlicher anderer Heftstoff",
                        content="Ein Satz beginnt mit einem großen Buchstaben.", confirmed=True, status="confirmed")
        db.add(page)
        day = SchoolDay(child_id=child.id, school_date=(local_day(child) - timedelta(days=1)).isoformat(), stage="ready")
        db.add(day)
        db.flush()
        other = Material(child_id=child.id, school_day_id=day.id, title="Künstliche aktuelle Tagesseite", subject="Sachunterricht", topic="Künstlicher aktueller Tagesstoff",
                         content="Der Mond umkreist die Erde.", confirmed=True, status="confirmed")
        db.add(other)
        db.flush()
        study_path.ensure_plan(db, day)
        page_id, day_id = page.id, day.id
    response = study["client"].get("/api/child/home?compact=true")
    assert response.status_code == 200, response.text
    value = response.json()["plan"]
    assert any(item["kind"] == "material" and item["id"] == page_id for item in value["voluntary"])
    assert any(item["kind"] == "study_path" and item["id"] == day_id for item in value["voluntary"])
    assert value["can_continue_voluntarily"] is True
    assert {item["day_id"] for item in value["blocked_study_paths"]} == {study["day_id"]}


def test_parent_review_and_minimum_time_facts_remain_independent_of_stale_stages(study):
    create(study)
    unit_id = saved_unit(study, completed=True)
    with DB.begin() as db:
        child = db.get(Child, study["child"]["id"])
        day = local_day(child).isoformat()
        assignment = Assignment(child_id=child.id, kind="parent", subject="Deutsch", topic="Künstlicher Elternauftrag",
                                mandatory=True, source_status="confirmed", scheduled_for=day)
        db.add(assignment)
        db.add(Mastery(child_id=child.id, subject="Sachunterricht", topic="Gespeicherte künstliche Runde", next_review=day, last_practiced=day))
        db.flush()
        before = plan(db, child, learning_paths=[])
        db.get(Material, study["materials"][-1]).revision += 1
        after = plan(db, child, learning_paths=[])
        assert any(item["kind"] == "assignment" and item["id"] == assignment.id and item["mandatory"] for item in after["today"])
        assert any(item["kind"] == "review" and item["id"] == unit_id for item in after["voluntary"])
        for key in ("daily_active_seconds", "weekly_active_seconds", "daily_goal_met", "weekly_goal_met",
                    "goal_required", "completed_today", "daily_remaining_minutes", "weekly_remaining_minutes"):
            assert after[key] == before[key]
