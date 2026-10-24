"""0034→0038 on isolated databases, using artificial historical rows only."""

import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import MetaData, Table, create_engine, event, inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

NEW_TABLES = {
    "source_revisions": {"material_id", "child_id", "revision", "sequence", "snapshot", "receipt"},
    "source_invalidations": {"material_id", "child_id", "unit_id", "source_revision", "current_revision"},
    "source_image_receipts": {"material_id", "image_digest", "geometry", "normalization_version"},
    "source_evaluation_budgets": {"id", "limit_micros"},
    "source_evaluation_grants": {"work_id", "operator_id", "family_id", "sources", "expires"},
    "source_evaluation_cases": {"work_id", "grant_id", "material_id", "job_id", "reserved_micros", "charged_micros"},
    "visual_reference_versions": {"id", "version", "digest", "recipe"},
    "unit_visual_snapshots": {"unit_id", "source_signature", "steps", "question_steps", "source_bindings"},
    "unit_visual_positions": {"unit_id", "user_id", "revision", "position", "source_signature"},
    "competence_definitions": {"id", "version", "subject_key", "label", "data"},
    "competence_sources": {"material_id", "source_revision", "competence_id", "catalog_version", "child_id"},
    "question_competences": {"unit_id", "question_id", "competence_id", "catalog_version", "source_refs"},
    "child_cost_controls": {"child_id", "revision", "daily_limit_eur_micros", "monthly_limit_eur_micros"},
    "child_cost_control_changes": {"child_id", "actor_id", "revision", "policy", "request_key"},
    "usage_cost_balances": {"usage_id", "child_id", "held_eur_micros", "accounted_eur_micros", "fx_snapshot"},
}

# Every new FK, including composite catalogue identities and financial SET NULL.
FK = {
    "source_revisions": [("material_id", "materials", "id", "CASCADE"), ("child_id", "children", "id", "CASCADE")],
    "source_invalidations": [("material_id", "materials", "id", "CASCADE"), ("child_id", "children", "id", "CASCADE"), ("unit_id", "learning_units", "id", "CASCADE")],
    "source_image_receipts": [("material_id", "materials", "id", "CASCADE")],
    "source_evaluation_grants": [("work_id", "source_evaluation_budgets", "id", "NO ACTION"), ("operator_id", "users", "id", "CASCADE"), ("family_id", "families", "id", "CASCADE")],
    "source_evaluation_cases": [("work_id", "source_evaluation_budgets", "id", "NO ACTION"), ("grant_id", "source_evaluation_grants", "id", "SET NULL"), ("material_id", "materials", "id", "SET NULL"), ("job_id", "jobs", "id", "SET NULL")],
    "unit_visual_snapshots": [("unit_id", "learning_units", "id", "CASCADE")],
    "unit_visual_positions": [("unit_id", "learning_units", "id", "CASCADE"), ("user_id", "users", "id", "CASCADE")],
    "competence_sources": [("material_id", "materials", "id", "CASCADE"), ("child_id", "children", "id", "CASCADE"), ("competence_id,catalog_version", "competence_definitions", "id,version", "NO ACTION")],
    "question_competences": [("unit_id", "learning_units", "id", "CASCADE"), ("child_id", "children", "id", "CASCADE"), ("competence_id,catalog_version", "competence_definitions", "id,version", "NO ACTION")],
    "child_cost_controls": [("child_id", "children", "id", "CASCADE")],
    "child_cost_control_changes": [("child_id", "children", "id", "CASCADE"), ("actor_id", "users", "id", "SET NULL")],
    "usage_cost_balances": [("usage_id", "usage", "id", "CASCADE"), ("child_id", "children", "id", "CASCADE")],
}


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_learning_pipeline_migration_retains_history_seeds_and_scoped_cascades(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires the isolated PostgreSQL runner.")
        schema = "learning107_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        url, tested = os.environ["TEST_DATABASE_URL"], engine
    else:
        url = "sqlite:///" + str(tmp_path / "learning107.sqlite")
        tested = create_engine(url)

        @event.listens_for(tested, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")

    env = {**os.environ, "DATABASE_URL": url, "ENVIRONMENT": "test"}
    if schema:
        env["PGOPTIONS"] = f"-c search_path={schema}"
    config = Path(__file__).resolve().parents[1] / "alembic.ini"
    command = [sys.executable, "-m", "alembic", "-c", str(config)]

    def migrate(direction, revision):
        result = subprocess.run([*command, direction, revision], env=env, capture_output=True, timeout=60)
        assert result.returncode == 0, result.stderr.decode(errors="replace")

    def scope(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    def table(con, name):
        return Table(name, MetaData(), autoload_with=con)

    def insert(con, table_name, **values):
        con.execute(table(con, table_name).insert().values(**values))

    def rows(con, name):
        source = table(con, name)
        values = [dict(row) for row in con.execute(select(source)).mappings()]
        return sorted(values, key=lambda row: json.dumps(row, sort_keys=True, default=str))

    def count(con, name):
        return con.scalar(text(f'SELECT count(*) FROM "{name}"'))

    def preserved(con):
        return {name: rows(con, name) for name in ("materials", "attempts", "users", "user_avatars", "usage")}

    def assert_structure(con):
        inspector = inspect(con)
        assert NEW_TABLES.keys() <= set(inspector.get_table_names(schema=schema))
        for name, required in NEW_TABLES.items():
            assert required <= {column["name"] for column in inspector.get_columns(name, schema=schema)}
            actual = {
                (",".join(fk["constrained_columns"]), fk["referred_table"], ",".join(fk["referred_columns"]),
                 fk["options"].get("ondelete", "NO ACTION").upper())
                for fk in inspector.get_foreign_keys(name, schema=schema)
            }
            assert actual == set(FK.get(name, [])), name
        nullable = {column["name"]: column["nullable"] for column in inspector.get_columns("source_evaluation_cases", schema=schema)}
        assert all(nullable[field] for field in ("grant_id", "material_id", "job_id"))
        assert not nullable["work_id"]
        for columns in ({"material_id", "revision", "digest"}, {"material_id", "sequence"}):
            assert columns in [set(constraint["column_names"]) for constraint in inspector.get_unique_constraints("source_revisions", schema=schema)]
        assert "ix_usage_child_created" in {index["name"] for index in inspector.get_indexes("usage", schema=schema)}

    def assert_seeds(con):
        from schulpilot.competences import VERSION, catalogue, seed_connection
        from schulpilot.visual_references import BUNDLE, digest, seed

        definitions = catalogue()
        # 0037 itself installs the versioned competence catalogue.
        assert {row["id"]: row["data"] for row in rows(con, "competence_definitions")} == definitions
        assert {row["version"] for row in rows(con, "competence_definitions")} == {VERSION}
        # 0036 creates the recipe table; production init_db explicitly performs
        # this immutable seed. Exercise that real seed without create_all.
        for _ in range(2):
            seed_connection(con)
            with Session(bind=con, join_transaction_mode="create_savepoint") as db:
                seed(db)
                db.commit()
        expected = json.loads(BUNDLE.read_text())["references"]
        assert {(row["id"], row["version"]): (row["digest"], row["recipe"]) for row in rows(con, "visual_reference_versions")} == {
            (row["id"], row["version"]): (digest(row), row) for row in expected
        }
        assert count(con, "competence_definitions") == len(definitions)
        return next(iter(definitions)), VERSION

    def add_pipeline_rows(con, competence_id, version):
        for mid, revision_id in (("m", "source"), ("m2", "source2")):
            insert(con, "source_revisions", id=revision_id, material_id=mid, child_id="c", revision=1, sequence=1,
                   digest="a" * 64, cause="extract", snapshot={"content": "Synthetic literal 1+1=3"}, receipt={"factual_validation": "not_assessed"}, created=2)
            insert(con, "source_invalidations", id="invalidation-" + mid, material_id=mid, child_id="c", unit_id="unit", source_revision=1, current_revision=2, reason="source_changed", created=2)
            insert(con, "source_image_receipts", material_id=mid, image_digest="b" * 64, geometry={"width": 300}, normalization_version="synthetic-1", created=2)
            insert(con, "competence_sources", material_id=mid, source_revision=1, competence_id=competence_id, catalog_version=version, child_id="c", excerpt="Synthetic literal")
        insert(con, "source_evaluation_budgets", id="work", limit_micros=250000)
        insert(con, "source_evaluation_grants", id="grant", work_id="work", operator_id="operator", family_id="f", sources=[{"id": "m", "revision": 1}], config_revision=1, policy_digest="c" * 64, expires=1000, created=2)
        insert(con, "source_evaluation_cases", id="case", work_id="work", grant_id="grant", material_id="m", job_id="job", tier="luna", status="completed", reserved_micros=150000, charged_micros=17, created=2)
        insert(con, "source_evaluation_cases", id="unknown-case", work_id="work", grant_id="grant", material_id="m2", job_id=None, tier="sol", status="dispatched", reserved_micros=150000, charged_micros=None, created=2)
        insert(con, "unit_visual_snapshots", unit_id="unit", source_signature="d" * 64, status="ready", reason=None, steps=[], question_steps={}, receipts=[], source_bindings=[{"material_id": "m", "revision": 1}], notice="", created=2)
        for user in ("u", "viewer"):
            insert(con, "unit_visual_positions", unit_id="unit", user_id=user, source_signature="d" * 64, revision=1, position={"step": 0}, updated=2)
        insert(con, "question_competences", unit_id="unit", question_id="q1", child_id="c", competence_id=competence_id, catalog_version=version, role="practice", question_digest="e" * 64, source_refs=[], reference_ids=[])
        insert(con, "child_cost_controls", child_id="c", revision=1, enabled=True, timezone="Europe/Berlin", daily_limit_eur_micros=2000000, monthly_limit_eur_micros=20000000, updated=2)
        insert(con, "child_cost_control_changes", id="change", child_id="c", actor_id="operator", request_key="synthetic-key", digest="f" * 64, revision=1, policy={"enabled": True}, created=2)
        for usage_id in ("usage", "usage2"):
            insert(con, "usage_cost_balances", usage_id=usage_id, child_id="c", created=2, provider_eur_micros=17, fee_known_eur_micros=3, fee_reserved_eur_micros=3, held_eur_micros=20, accounted_eur_micros=20, fee_state="known", fx_snapshot={"usd_eur": "1.0"}, fee_basis_usd_micros=17)

    try:
        migrate("upgrade", "0034")
        with tested.begin() as con:
            scope(con)
            insert(con, "families", id="f", name="Synthetic", synthetic=True, created=1, child_limit=4, call_limit=100, budget_micros=2000000, plan="Pilot")
            for user, role in (("u", "child"), ("operator", "admin"), ("viewer", "parent")):
                insert(con, "users", id=user, username="synthetic-" + user, display_name="Synthetic", password_hash="SYNTHETIC-HASH", role=role, verified=True, disabled=False, created=1)
            insert(con, "children", id="c", family_id="f", user_id="u", grade=6, subjects=[], school_type="", region="", preferences={})
            for mid in ("m", "m2"):
                insert(con, "materials", id=mid, child_id="c", title="Synthetic", status="confirmed", subject="Mathematik", topic="Brüche", content="1+1=3 – artificial original", uncertainties=[], homework=[], confirmed=True, synthetic=False, created=1)
            insert(con, "learning_units", id="unit", child_id="c", material_id="m", subject="Mathematik", topic="Brüche", explanation="Synthetic", questions=[{"id": "q1", "answer": "2/4"}], status="completed", synthetic=True, provider="synthetic", created=1, active_seconds=42)
            insert(con, "attempts", id="attempt", unit_id="unit", question_id="q1", answer="2/4", outcome="correct", assisted=False, created=1)
            insert(con, "user_avatars", user_id="u", revision="synthetic-old-avatar", image_digest="a" * 64, updated=1, request_key="synthetic-key", request_digest="synthetic-digest")
            insert(con, "jobs", id="job", child_id="c", kind="extract", payload={"material_id": "m"}, status="completed", attempts=1, created=1, idempotency="synthetic-job")
            for usage_id in ("usage", "usage2"):
                insert(con, "usage", id=usage_id, family_id="f", child_id="c", job_id="job", provider="synthetic", model="no-inference", config_revision=1, function="extract", status="completed", cost_micros=17, reserved_micros=150000, bucket_ids=[], created=1)
            historical = preserved(con)
        for iteration in range(2):
            migrate("upgrade", "0038")
            with tested.begin() as con:
                scope(con)
                assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0038"
                assert preserved(con) == historical
                assert_structure(con)
                competence_id, version = assert_seeds(con)
                assert all(count(con, name) == 0 for name in NEW_TABLES if name not in {"competence_definitions", "visual_reference_versions"})
                add_pipeline_rows(con, competence_id, version)
            if iteration == 0:
                migrate("downgrade", "0034")
                with tested.begin() as con:
                    scope(con)
                    assert con.scalar(text("SELECT version_num FROM alembic_version")) == "0034"
                    assert not (NEW_TABLES.keys() & set(inspect(con).get_table_names(schema=schema)))
                    assert preserved(con) == historical
                    assert "ix_usage_child_created" not in {index["name"] for index in inspect(con).get_indexes("usage", schema=schema)}

        with tested.begin() as con:
            scope(con)
            # The application rejects mutations of archived source/geometry
            # snapshots on the actually migrated tables (not create_all).
            from schulpilot.source_lineage_models import SourceImageReceipt, SourceRevision

            for model, key, field, replacement in ((SourceRevision, "source", "cause", "changed"),
                                                    (SourceImageReceipt, "m", "geometry", {"width": 1})):
                with Session(bind=con, join_transaction_mode="create_savepoint") as db:
                    row = db.get(model, key)
                    setattr(row, field, replacement)
                    with pytest.raises(ValueError, match="unveränderlich"):
                        db.flush()
                    db.rollback()
            assert all(row["cause"] == "extract" for row in rows(con, "source_revisions"))
            assert all(row["geometry"] == {"width": 300} for row in rows(con, "source_image_receipts"))
            # Failed foreign references must roll back only their savepoint.
            for name, values in [
                ("source_invalidations", dict(id="invalid", material_id="missing", child_id="c", unit_id="unit", source_revision=1, current_revision=2, reason="x", created=2)),
                ("unit_visual_positions", dict(unit_id="unit", user_id="missing", source_signature="a" * 64, revision=1, position={}, updated=2)),
                ("competence_sources", dict(material_id="m", source_revision=2, competence_id="missing", catalog_version=version, child_id="c", excerpt="Synthetic")),
                ("child_cost_controls", dict(child_id="missing", revision=1, enabled=True, timezone="UTC", updated=2)),
            ]:
                with pytest.raises(IntegrityError):
                    with con.begin_nested():
                        insert(con, name, **values)
            assert preserved(con) == historical
            # Deleting the original never deletes an old answer; only private
            # source-dependent rows cascade and diagnostic references null out.
            con.execute(text("DELETE FROM materials WHERE id='m'"))
            assert count(con, "source_revisions") == count(con, "source_image_receipts") == count(con, "source_invalidations") == count(con, "competence_sources") == 1
            assert count(con, "attempts") == 1 and count(con, "unit_visual_snapshots") == 1
            assert con.scalar(text("SELECT material_id FROM learning_units WHERE id='unit'")) is None
            assert con.scalar(text("SELECT material_id FROM source_evaluation_cases WHERE id='case'")) is None
            con.execute(text("DELETE FROM users WHERE id='viewer'"))
            assert count(con, "unit_visual_positions") == 1
            con.execute(text("DELETE FROM users WHERE id='operator'"))
            assert count(con, "source_evaluation_grants") == 0
            assert con.scalar(text("SELECT grant_id FROM source_evaluation_cases WHERE id='case'")) is None
            assert con.scalar(text("SELECT actor_id FROM child_cost_control_changes WHERE id='change'")) is None
            con.execute(text("DELETE FROM jobs WHERE id='job'"))
            assert con.scalar(text("SELECT job_id FROM source_evaluation_cases WHERE id='case'")) is None
            financial = next(row for row in rows(con, "source_evaluation_cases") if row["id"] == "case")
            assert (financial["reserved_micros"], financial["charged_micros"], financial["work_id"]) == (150000, 17, "work")
            con.execute(text("DELETE FROM learning_units WHERE id='unit'"))
            assert all(count(con, name) == 0 for name in ("attempts", "unit_visual_snapshots", "unit_visual_positions", "question_competences", "source_invalidations"))
            assert count(con, "source_revisions") == count(con, "competence_sources") == 1
            con.execute(text("DELETE FROM usage WHERE id='usage2'"))
            assert count(con, "usage_cost_balances") == 1 and count(con, "child_cost_controls") == 1
            con.execute(text("DELETE FROM children WHERE id='c'"))
            assert all(count(con, name) == 0 for name in ("materials", "source_revisions", "source_image_receipts", "competence_sources", "child_cost_controls", "child_cost_control_changes", "usage_cost_balances", "usage"))
            assert count(con, "user_avatars") == 1  # Still belongs to the user.
            cases = {row["id"]: row for row in rows(con, "source_evaluation_cases")}
            assert cases["case"] == financial
            unknown = cases["unknown-case"]
            assert (unknown["charged_micros"], unknown["reserved_micros"], unknown["status"]) == (None, 150000, "dispatched")
            assert all(unknown[field] is None for field in ("grant_id", "material_id", "job_id"))
            assert count(con, "source_evaluation_budgets") == 1
            with pytest.raises(IntegrityError):
                with con.begin_nested():
                    con.execute(text("DELETE FROM source_evaluation_budgets WHERE id='work'"))
            assert count(con, "visual_reference_versions") > 0 and count(con, "competence_definitions") > 0
            con.execute(text("DELETE FROM users WHERE id='u'"))
            assert count(con, "user_avatars") == 0
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
