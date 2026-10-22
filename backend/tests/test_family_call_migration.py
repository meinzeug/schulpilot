"""Upgrade existing accounts/devices/answers without changing their contents."""
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from alembic.config import Config
from alembic.script import ScriptDirectory
from schulpilot.db import engine
from sqlalchemy import create_engine, event, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_family_call_migration_preserves_accounts_answers_and_push_opt_in(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires the isolated PostgreSQL runner.")
        schema = "call_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        url, tested = os.environ["TEST_DATABASE_URL"], engine
    else:
        url = "sqlite:///" + str(tmp_path / "call-migration.sqlite")
        tested = create_engine(url)

        @event.listens_for(tested, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")

    env = {**os.environ, "DATABASE_URL": url, "ENVIRONMENT": "test"}
    if schema:
        env["PGOPTIONS"] = f"-c search_path={schema}"
    command = [sys.executable, "-m", "alembic", "-c", str(Path(__file__).resolve().parents[1] / "alembic.ini")]
    expected_head = ScriptDirectory.from_config(Config(command[-1])).get_current_head()

    def scoped(con):
        if schema:
            con.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    try:
        subprocess.run([*command, "upgrade", "0025"], env=env, capture_output=True, check=True)
        with tested.begin() as con:
            scoped(con)
            for statement in [
                "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan) VALUES('f','Synthetic',true,1,4,100,2000000,'Pilot')",
                "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('u','synthetic','Synthetic','SYNTHETIC-HASH','child',true,false,1)",
                "INSERT INTO children(id,family_id,user_id,grade,subjects,school_type,region,preferences) VALUES('c','f','u',6,'[]','','','{}')",
                "INSERT INTO sessions(id,user_id,token_hash,device,created,seen,expires,revoked) VALUES('s','u','SYNTHETIC-TOKEN-HASH','Synthetic',1,1,2000000000,false)",
                "INSERT INTO push_devices(id,user_id,session_id,token_hash,encrypted_token,platform,timezone,quiet_start,quiet_end,reminders,help_requests,summaries,updated) VALUES('p','u','s','SYNTHETIC-FCM-HASH','SYNTHETIC-ENCRYPTED-TOKEN','android','Europe/Berlin',20,8,true,true,false,1)",
                "INSERT INTO learning_units(id,child_id,subject,topic,explanation,questions,status,synthetic,provider,created,active_seconds) VALUES('unit','c','Mathematik','Rechnen','Synthetic','[]','active',true,'synthetic',1,0)",
                "INSERT INTO attempts(id,unit_id,question_id,answer,outcome,assisted,created) VALUES('attempt','unit','q1','\"synthetic\"','correct',false,1)",
            ]:
                con.execute(text(statement))
        subprocess.run([*command, "upgrade", "head"], env=env, capture_output=True, check=True)
        with tested.begin() as con:
            scoped(con)
            assert con.scalar(text("SELECT version_num FROM alembic_version")) == expected_head
            record = con.execute(text("SELECT family_calls,call_binding,help_requests,encrypted_token FROM push_devices WHERE id='p'")).first()
            assert tuple(record) == (False, None, True, "SYNTHETIC-ENCRYPTED-TOKEN")
            answer, assisted = con.execute(text("SELECT answer,assisted FROM attempts WHERE id='attempt'")).first()
            assert (json.loads(answer) if dialect == "sqlite" else answer) == "synthetic" and not bool(assisted)
            assert con.scalar(text("SELECT count(*) FROM family_calls")) == 0
            assert not bool(con.scalar(text("SELECT revoked FROM sessions WHERE id='s'")))
        # The backwards schema path must also leave pre-existing accounts,
        # answers and push credentials unchanged. Production rollbacks keep the
        # additive schema; no real call history is discarded by deployment.
        subprocess.run([*command, "downgrade", "0025"], env=env, capture_output=True, check=True)
        with tested.begin() as con:
            scoped(con)
            assert con.scalar(text("SELECT encrypted_token FROM push_devices WHERE id='p'")) == "SYNTHETIC-ENCRYPTED-TOKEN"
            assert con.scalar(text("SELECT outcome FROM attempts WHERE id='attempt'")) == "correct"
            assert con.scalar(text("SELECT count(*) FROM sessions")) == 1
        subprocess.run([*command, "upgrade", "head"], env=env, capture_output=True, check=True)
        with tested.begin() as con:
            scoped(con)
            assert con.scalar(text("SELECT version_num FROM alembic_version")) == expected_head
            assert not bool(con.scalar(text("SELECT family_calls FROM push_devices WHERE id='p'")))
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
