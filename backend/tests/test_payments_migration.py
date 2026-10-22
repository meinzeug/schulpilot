"""Actual 0029↔0030 migration preserves historical bank orders and trials."""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from schulpilot.db import engine
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError


@pytest.mark.parametrize("dialect", ["sqlite", "postgresql"])
def test_payment_migration_preserves_old_orders_and_has_exact_money_constraints(tmp_path, dialect):
    schema = None
    if dialect == "postgresql":
        if engine.dialect.name != "postgresql":
            pytest.skip("Requires isolated PostgreSQL")
        schema = "payment_migration_" + uuid.uuid4().hex
        with engine.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        tested, url = engine, os.environ["TEST_DATABASE_URL"]
    else:
        url = "sqlite:///" + str(tmp_path / "payments.sqlite")
        tested = create_engine(url)
    env = {**os.environ, "DATABASE_URL": url, "ENVIRONMENT": "test"}
    if schema:
        env["PGOPTIONS"] = f"-c search_path={schema}"
    else:
        env.pop("PGOPTIONS", None)
    command = [sys.executable, "-m", "alembic", "-c", str(Path(__file__).resolve().parents[1] / "alembic.ini")]

    def scope(connection):
        if schema:
            connection.execute(text(f'SET LOCAL search_path TO "{schema}"'))

    def migrate(target, direction="upgrade"):
        result = subprocess.run([*command, direction, target], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors="replace")[-2000:]

    try:
        migrate("0029")
        with tested.begin() as connection:
            scope(connection)
            connection.execute(
                text(
                    "INSERT INTO families(id,name,synthetic,created,child_limit,call_limit,budget_micros,plan,commerce_required) VALUES('f','Synthetic',false,1,1,300,5000000,'Saved Start',true)"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO bank_orders(id,family_id,idempotency,payment_reference,status,amount_cents,offer,seller,bank,terms,terms_version,early_start,created,starts,ends,mail_status) VALUES('o','f','synthetic-order','SYNTHETIC-REF','paid',990,'{}','{}','{}','Historical terms','2026-10-14.1',true,1,2,2000000000,'accepted')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO family_trials(family_id,created,starts,ends,child_limit,call_limit,budget_micros,version) VALUES('f',100,100,2592100,1,100,2000000,'verified-family-trial-1')"
                )
            )
        migrate("0030")
        with tested.begin() as connection:
            scope(connection)
            row = connection.execute(
                text(
                    "SELECT terms,terms_version,amount_cents,payment_method,currency,request_digest FROM bank_orders WHERE id='o'"
                )
            ).one()
            assert tuple(row) == ("Historical terms", "2026-10-14.1", 990, "bank_transfer", "EUR", None)
            assert connection.scalar(text("SELECT ends FROM family_trials WHERE family_id='f'")) == 2592100
            assert {
                "payment_attempts",
                "payment_configuration",
                "payment_configuration_revisions",
                "payment_events",
                "payment_refunds",
            }.issubset(inspect(connection).get_table_names(schema=schema))
            for amount, refunded, currency, environment in (
                (0, 0, "EUR", "sandbox"),
                (990, 991, "EUR", "sandbox"),
                (990, 0, "USD", "sandbox"),
                (990, 0, "EUR", "unknown"),
            ):
                with pytest.raises(IntegrityError), connection.begin_nested():
                    connection.execute(
                        text(
                            "INSERT INTO payment_attempts(id,order_id,environment,merchant_id,config_revision,method,amount_cents,currency,status,create_request_id,capture_request_id,refunded_cents,created,updated) VALUES('p','o',:environment,'SYNTHETIC',1,'paypal',:amount,:currency,'capture_pending','SYNTHETIC-CREATE','SYNTHETIC-CAPTURE',:refunded,1,1)"
                        ),
                        {"environment": environment, "amount": amount, "currency": currency, "refunded": refunded},
                    )
        migrate("0029", "downgrade")
        with tested.begin() as connection:
            scope(connection)
            assert connection.scalar(text("SELECT terms FROM bank_orders WHERE id='o'")) == "Historical terms"
            assert connection.scalar(text("SELECT ends FROM family_trials WHERE family_id='f'")) == 2592100
        migrate("0030")
    finally:
        if schema:
            with engine.begin() as connection:
                connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        else:
            tested.dispose()
