"""Actual additive0031↔0032 preserves accounts and cascades only avatar metadata."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import UserAvatar, engine
from sqlalchemy import create_engine, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_avatar_migration_preserves_users_and_round_trips(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires isolated PostgreSQL runner")
        schema = "avatar_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        tested, url = engine, os.environ["TEST_DATABASE_URL"]
    else:
        url = "sqlite:///" + str(tmp_path / "avatars.sqlite")
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
        else:
            con.execute(text("PRAGMA foreign_keys=ON"))

    def migrate(target, direction="upgrade"):
        result = subprocess.run([*command, direction, target], env=env, capture_output=True, timeout=60)
        assert result.returncode == 0, result.stderr.decode(errors="replace")[-2000:]

    try:
        migrate("0031")
        with tested.begin() as con:
            scope(con)
            con.execute(
                text(
                    "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('synthetic-user','synthetic','Synthetic profile','preserved-hash','parent',true,false,1)"
                )
            )
        migrate("0032")
        with tested.begin() as con:
            scope(con)
            assert {c["name"] for c in inspect(con).get_columns("user_avatars", schema=schema)} == {
                c.name for c in UserAvatar.__table__.columns
            }
            assert con.scalar(text("SELECT count(*) FROM user_avatars")) == 0
            assert con.scalar(text("SELECT password_hash FROM users WHERE id='synthetic-user'")) == "preserved-hash"
            con.execute(
                text(
                    "INSERT INTO user_avatars(user_id,revision,image_digest,updated,request_key,request_digest) VALUES('synthetic-user','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',NULL,2,'synthetic-request','digest')"
                )
            )
            con.execute(text("DELETE FROM users WHERE id='synthetic-user'"))
            assert con.scalar(text("SELECT count(*) FROM user_avatars")) == 0
            con.execute(
                text(
                    "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('synthetic-user','synthetic','Synthetic profile','preserved-hash','parent',true,false,1)"
                )
            )
        migrate("0031", "downgrade")
        with tested.begin() as con:
            scope(con)
            assert "user_avatars" not in inspect(con).get_table_names(schema=schema)
            assert con.scalar(text("SELECT password_hash FROM users WHERE id='synthetic-user'")) == "preserved-hash"
            assert "order_withdrawals" in inspect(con).get_table_names(schema=schema)
        migrate("0032")
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
