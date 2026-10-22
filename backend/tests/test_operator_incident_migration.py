"""Exercise actual additive 0028 without rewriting previous learning rows."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_operator_schema_roundtrip_keeps_existing_accounts_and_failed_learning_jobs(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires isolated PostgreSQL runner")
        schema = "incident_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        tested, url = engine, os.environ["TEST_DATABASE_URL"]
    else:
        url = "sqlite:///" + str(tmp_path / "incidents.sqlite")
        tested = create_engine(url)
    env = {**os.environ, "DATABASE_URL": url, "ENVIRONMENT": "test"}
    if schema:
        env["PGOPTIONS"] = f"-c search_path={schema}"
    else:
        env.pop("PGOPTIONS", None)
    command = [sys.executable, "-m", "alembic", "-c", str(Path(__file__).resolve().parents[1] / "alembic.ini")]

    def scope(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    def migrate(target, mode="upgrade"):
        result = subprocess.run([*command, mode, target], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors="replace")[-2000:]

    try:
        migrate("0027")
        with tested.begin() as con:
            scope(con)
            for statement in [
                "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','Synthetic',true,1,4,100,2000000,'Pilot')",
                "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','child',true,false,1)",
                "INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}')",
                "INSERT INTO sessions(id,user_id,token_hash,device,created,seen,expires,revoked) VALUES('s','u','SYNTHETIC-TOKEN-HASH','Synthetic',1,1,2000000000,false)",
                "INSERT INTO jobs(id,child_id,kind,payload,status,error,error_code,attempts,created,idempotency) VALUES('j','c','decision','{}','failed','Saved controlled message','unknown',1,10,'synthetic-key')",
            ]:
                con.execute(text(statement))
        migrate("0028")
        with tested.begin() as con:
            scope(con)
            fields = {c["name"] for c in inspect(con).get_columns("operator_repair_requests", schema=schema)}
            assert {
                "requested_session_id",
                "test_summary",
                "execution_slot",
                "reserved_micros",
                "budget_bucket_ids",
                "cost_micros",
                "cost_source",
                "settlement_version",
            } <= fields
            assert con.scalar(text("SELECT error FROM jobs WHERE id='j'")) == "Saved controlled message"
            assert con.scalar(text("SELECT count(*) FROM operator_incidents")) == 0
            assert con.scalar(text("SELECT count(*) FROM operator_repair_requests")) == 0
        migrate("0027", "downgrade")
        with tested.begin() as con:
            scope(con)
            assert con.scalar(text("SELECT attempts FROM jobs WHERE id='j'")) == 1
            assert con.scalar(text("SELECT revoked FROM sessions WHERE id='s'")) in (False, 0)
            assert con.scalar(text("SELECT count(*) FROM users")) == 1
        migrate("0028")
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
