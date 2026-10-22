"""Actual0030↔0031 on SQLite/PostgreSQL preserves existing prepaid records."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from schulpilot.order_withdrawal_models import OrderWithdrawal, PublicWithdrawal
from sqlalchemy import create_engine, inspect, text


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_additive_withdrawal_migration_preserves_paid_order_and_cascades_only_new_rows(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires isolated PostgreSQL runner")
        schema = "withdrawal_migration_" + uuid.uuid4().hex
        with engine.begin() as con:
            con.execute(text(f'CREATE SCHEMA "{schema}"'))
        tested, url = engine, os.environ["TEST_DATABASE_URL"]
    else:
        url = "sqlite:///" + str(tmp_path / "withdrawals.sqlite")
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
        result = subprocess.run([*command, direction, target], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors="replace")[-2000:]

    try:
        migrate("0030")
        with tested.begin() as con:
            scope(con)
            con.execute(text("INSERT INTO bank_orders(id,idempotency,payment_reference,status,amount_cents,offer,seller,bank,terms,terms_version,early_start,created,mail_status) VALUES('o','synthetic-order','SYNTHETIC-REF','paid',990,'{}','{}','{}','Preserved saved terms','2026-10-14.1',true,1,'accepted')"))
        migrate("0031")
        with tested.begin() as con:
            scope(con)
            for model in (OrderWithdrawal, PublicWithdrawal):
                assert {c["name"] for c in inspect(con).get_columns(model.__tablename__, schema=schema)} == {
                    c.name for c in model.__table__.columns}
                assert con.scalar(text("SELECT count(*) FROM " + model.__tablename__)) == 0
            assert con.scalar(text("SELECT terms FROM bank_orders WHERE id='o'")) == "Preserved saved terms"
            assert con.scalar(text("SELECT payment_method FROM bank_orders WHERE id='o'")) == "bank_transfer"
            con.execute(text("INSERT INTO order_withdrawals(id,order_id,received,effective_received,verified,hold_payment,status,encrypted_declaration,request_digest,idempotency,mail_status) VALUES('w','o',2,2,true,true,'received_verified','SYNTHETIC-ENCRYPTED','digest','synthetic-key','accepted')"))
            con.execute(text("DELETE FROM bank_orders WHERE id='o'"))
            assert con.scalar(text("SELECT count(*) FROM order_withdrawals")) == 0
            con.execute(text("INSERT INTO bank_orders(id,idempotency,payment_reference,status,amount_cents,offer,seller,bank,terms,terms_version,early_start,created,mail_status) VALUES('o','synthetic-order','SYNTHETIC-REF','paid',990,'{}','{}','{}','Preserved saved terms','2026-10-14.1',true,1,'accepted')"))
        migrate("0030", "downgrade")
        with tested.begin() as con:
            scope(con)
            assert con.scalar(text("SELECT status FROM bank_orders WHERE id='o'")) == "paid"
            assert con.scalar(text("SELECT amount_cents FROM bank_orders WHERE id='o'")) == 990
            assert con.scalar(text("SELECT terms FROM bank_orders WHERE id='o'")) == "Preserved saved terms"
            assert "payment_attempts" in inspect(con).get_table_names(schema=schema)
        migrate("0031")
    finally:
        if schema:
            with engine.begin() as con:
                con.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
