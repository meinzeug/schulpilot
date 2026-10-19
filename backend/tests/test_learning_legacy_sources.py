"""Old units without source snapshots remain readable without inventing one."""

import pytest
from schulpilot.db import DB, LearningUnit, Material, UnitSource
from schulpilot.learning import unit_source_texts
from sqlalchemy import delete
from test_coaching import normal_unit as _normal_unit


@pytest.fixture
def normal_unit(api, household):
    yield from _normal_unit.__wrapped__(api, household)


@pytest.mark.parametrize("source_changed", [False, True])
def test_legacy_unit_without_source_snapshot_stays_readable(normal_unit, api, source_changed):
    client, unit_id, material_id, *_ = normal_unit
    with DB.begin() as db:
        db.execute(delete(UnitSource).where(UnitSource.unit_id == unit_id))
        material = db.get(Material, material_id)
        if source_changed:
            material.revision += 1
            material.content = "Korrigierter künstlicher Stoff ohne belegte alte Revision."
        db.flush()
        assert unit_source_texts(db, db.get(LearningUnit, unit_id)) == []

    child_view = client.get(f"/api/units/{unit_id}")
    parent_view = api.get(f"/api/units/{unit_id}")
    assert child_view.status_code == 200, child_view.text
    assert parent_view.status_code == 200, parent_view.text
    assert child_view.json()["questions"]
    assert all("answer" not in question for question in child_view.json()["questions"])
    assert all("answer" in question for question in parent_view.json()["questions"])
    with DB() as db:
        assert db.get(UnitSource, (unit_id, material_id)) is None
        assert db.get(Material, material_id).revision == (2 if source_changed else 1)


def test_source_texts_only_use_explicit_matching_revision(normal_unit):
    _, unit_id, material_id, *_ = normal_unit
    with DB.begin() as db:
        unit = db.get(LearningUnit, unit_id)
        material = db.get(Material, material_id)
        assert unit_source_texts(db, unit) == [material.content]
        material.revision += 1
        db.flush()
        assert unit_source_texts(db, unit) == []
