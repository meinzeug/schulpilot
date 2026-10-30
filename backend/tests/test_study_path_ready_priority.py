"""Available own rounds should not hide behind optional ungenerated work."""
import copy

import pytest
from schulpilot import learning
from schulpilot.db import DB, Attempt, Job, LearningUnit, Material, SchoolDay, UnitSource
from schulpilot.study_path import ensure_plan
from schulpilot.synthetic import sample_unit
from sqlalchemy import func, select
from test_study_path import create, path
from test_study_path import study as study


@pytest.mark.parametrize("mandatory", [False, True])
@pytest.mark.parametrize("status", ["not_started", "active", "paused"])
def test_next_day_action_prefers_eligible_saved_work_but_preserves_parent_duties(study, monkeypatch, mandatory, status):
    create(study)
    with DB.begin() as db:
        day = db.get(SchoolDay, study["day_id"])
        material = Material(child_id=day.child_id, school_day_id=day.id, page_number=6,
                            subject="Geschichte", topic="Quellen", title="Künstliche Geschichte-Seite",
                            content="Sachquellen sind Gegenstände aus früherer Zeit.", status="confirmed", confirmed=True)
        db.add(material)
        db.flush()
        unit = LearningUnit(child_id=day.child_id, school_day_id=day.id, material_id=material.id,
                            **(sample_unit() | {"subject": "Geschichte", "topic": "Quellen"}),
                            status=status, estimated_minutes=8, provider="synthetic-fixture")
        db.add(unit)
        db.flush()
        db.add(UnitSource(unit_id=unit.id, material_id=material.id, revision=material.revision))
        db.flush()
        plan = copy.deepcopy(ensure_plan(db, day))
        ready = next(b for b in plan["blocks"] if b.get("unit_id") == unit.id)
        planned = next(b for b in plan["blocks"] if not b.get("unit_id"))
        unit_id = unit.id
    offered = {"today": [], "voluntary": [
        {"kind": "study_path", "id": study["day_id"], "block_id": planned["id"], "status": "planned", "mandatory": mandatory},
        {"kind": "unit", "id": unit_id, "status": status, "mandatory": False},
    ]}
    monkeypatch.setattr(learning, "plan", lambda *args, **kwargs: copy.deepcopy(offered))
    for _ in range(2):
        data = study["client"].get(path(study)).json()
        assert data["next_block_id"] == (planned["id"] if mandatory else ready["id"])
        assert data["can_continue"] is True
    # A round not offered by the existing planner (e.g. future/prerequisite)
    # must not be elevated merely because its unit has already been saved.
    offered["voluntary"] = offered["voluntary"][:1]
    assert study["client"].get(path(study)).json()["next_block_id"] == planned["id"]
    with DB() as db:
        assert db.get(SchoolDay, study["day_id"]).learning_plan == plan
        assert db.get(LearningUnit, unit_id).status == status
        assert db.scalar(select(func.count()).select_from(Job)) == 0
        assert db.scalar(select(func.count()).select_from(Attempt)) == 0
