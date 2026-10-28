"""Run directly as well as under pytest; uses a separate in-memory SQLite DB."""

import os

os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("DATA_DIR", "/tmp/schulpilot-private-qa-test")
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("MASTER_KEY", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")

from types import SimpleNamespace

import pytest
from schulpilot import private_qa_access as access
from schulpilot.db import Audit, Base, Child, Family, FamilyTrial, Material, Membership, User
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session


def test_private_qa_grant_is_scoped_and_idempotent():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    ids = [str(n) * 32 for n in range(1, 7)]
    request = {"family_id": ids[0], "parent_id": ids[1], "child_id": ids[2], "material_ids": ids[4:6]}
    previous_store, previous_now = access.store, access.now
    access.store = lambda _db: (SimpleNamespace(trial_enabled=False), 0)
    access.now = lambda: 1800000000
    try:
        with Session(engine) as db, db.begin():
            db.add_all([
                Family(id=ids[0], name="Regulärer KI-Test mit künstlichem Schulstoff", synthetic=False, commerce_required=True),
                User(id=ids[1], username="owner+schulpilot-normal-qa-0123456789ab@gmail.com", display_name="Test", password_hash="synthetic", role="parent", verified=True),
                User(id=ids[3], username="normal-child-0123456789ab", display_name="Test", password_hash="synthetic", role="child", verified=True),
                Child(id=ids[2], family_id=ids[0], user_id=ids[3], grade=6),
                Membership(family_id=ids[0], user_id=ids[1], permission="owner"),
                *[Material(id=mid, child_id=ids[2], title="Künstlich", purpose="notebook", synthetic=False, image_digest=digest)
                  for mid, digest in zip(ids[4:6], sorted(access.ARTIFICIAL_DIGESTS))],
            ])
        with Session(engine) as db, db.begin():
            family = db.get(Family, ids[0])
            family.synthetic = True
            with pytest.raises(ValueError, match="regulärer Testhaushalt"):
                access.grant(db, request)
            family.synthetic = False
            page = db.get(Material, ids[4])
            digest = page.image_digest
            page.image_digest = "0" * 64
            with pytest.raises(ValueError, match="künstlichen Fotos"):
                access.grant(db, request)
            page.image_digest = digest
            db.flush()
            result = access.grant(db, request)
            assert result["budget_usd"] == 15 and result["call_limit"] == 100
        with Session(engine) as db, db.begin():
            assert access.grant(db, request)["already_applied"] is True
            trial = db.get(FamilyTrial, ids[0])
            assert trial.ends - trial.starts == 30 * access.DAY
            assert trial.version == access.VERSION
            assert len(list(db.scalars(select(Audit)))) == 1
    finally:
        access.store, access.now = previous_store, previous_now
        engine.dispose()


if __name__ == "__main__":
    test_private_qa_grant_is_scoped_and_idempotent()
    print("Private artificial QA access guards and idempotence passed")
