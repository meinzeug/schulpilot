"""Exercise the additive 0042 DDL on isolated old-schema SQLite/PostgreSQL."""

import importlib.util
import uuid
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from schulpilot.db import Base, engine
from sqlalchemy import create_engine, event, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_admin_receipts_migration_is_additive_reversible_and_keeps_minimal_delete_receipt(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires the isolated PostgreSQL runner.")
        tested = engine
        schema = "admin_migration_" + uuid.uuid4().hex
        with tested.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    else:
        tested = create_engine("sqlite:///" + str(tmp_path / "admin.sqlite"))

        @event.listens_for(tested, "connect")
        def foreign_keys(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")

    path = Path(__file__).resolve().parents[1] / "migrations" / "versions" / "0042_admin_users.py"
    spec = importlib.util.spec_from_file_location("admin_users_migration", path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    assert migration.revision == "0042" and migration.down_revision == "0041"
    try:
        with tested.begin() as connection:
            if schema:
                connection.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            old_tables = [
                table
                for table in Base.metadata.sorted_tables
                if table.name not in ("admin_user_operations", "admin_user_versions")
            ]
            Base.metadata.create_all(connection, tables=old_tables)
            connection.execute(
                text(
                    "INSERT INTO users(id,username,display_name,password_hash,role,verified,disabled,created) VALUES('operator','operator','Synthetic operator','PRIVATEHASH','admin',true,false,1),('target','target','Synthetic target','PRIVATEHASH','parent',true,false,1)"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO sessions(id,user_id,token_hash,device,created,seen,expires,revoked) VALUES('session','operator','synthetic-session-hash','Synthetic',1,1,2,false)"
                )
            )
            migration.op = Operations(MigrationContext.configure(connection))
            for iteration in range(2):
                migration.upgrade()
                tables = set(inspect(connection).get_table_names(schema=schema))
                assert {"admin_user_versions", "admin_user_operations"} <= tables
                assert connection.scalar(text("SELECT display_name FROM users WHERE id='target'")) == "Synthetic target"
                assert (
                    connection.scalar(text("SELECT token_hash FROM sessions WHERE id='session'"))
                    == "synthetic-session-hash"
                )
                if iteration == 0:
                    migration.downgrade()
                    assert "admin_user_operations" not in inspect(connection).get_table_names(schema=schema)
            connection.execute(text("INSERT INTO admin_user_versions(user_id,revision) VALUES('target',7)"))
            connection.execute(
                text(
                    "INSERT INTO admin_user_operations(id,actor_id,session_id,target_id,request_key,action,request_digest,result,created,expires) VALUES('receipt','operator','session','target','synthetic-operation-key','delete','synthetic-digest','{}',1,2)"
                )
            )
            connection.execute(text("DELETE FROM users WHERE id='target'"))
            assert connection.scalar(text("SELECT count(*) FROM admin_user_versions")) == 0
            assert connection.scalar(text("SELECT target_id FROM admin_user_operations WHERE id='receipt'")) == "target"
            connection.execute(text("DELETE FROM users WHERE id='operator'"))
            assert connection.scalar(text("SELECT count(*) FROM admin_user_operations")) == 0
            assert connection.scalar(text("SELECT count(*) FROM sessions")) == 0
    finally:
        if schema:
            with tested.begin() as connection:
                connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
