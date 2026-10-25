"""Only fake engines/settings; never connect to a mismatched database."""
from types import SimpleNamespace

import pytest
from conftest import clean_database, require_test_database
from sqlalchemy.engine import make_url

EXPECTED = "postgresql+psycopg://synthetic_user:PRIVATE_PASSWORD@localhost/dedicated_test?host=/run/postgresql"


def test_equal_sqlalchemy_urls_and_test_settings_are_allowed_without_connecting():
    engine = SimpleNamespace(url=make_url(EXPECTED))
    assert require_test_database(engine, SimpleNamespace(environment="test"), make_url(EXPECTED)) is None


@pytest.mark.parametrize("url,environment", [
    ("sqlite:////PRIVATE_OLD_DATABASE.sqlite", "test"),
    (EXPECTED.replace("dedicated_test", "PRIVATE_OTHER_DATABASE"), "test"),
    (EXPECTED.replace("PRIVATE_PASSWORD", "PRIVATE_OTHER_PASSWORD"), "test"),
    (EXPECTED, "development"),
    (EXPECTED, "production"),
    ("PRIVATE_MALFORMED_URL", "test"),
])
def test_cached_or_mismatched_application_state_is_refused_without_exposing_urls(url, environment):
    with pytest.raises(RuntimeError) as caught:
        require_test_database(SimpleNamespace(url=url), SimpleNamespace(environment=environment), EXPECTED)
    assert str(caught.value) == "Destructive test setup requires the dedicated test database and test settings."
    assert "PRIVATE" not in str(caught.value)


@pytest.mark.parametrize("wrong_engine,environment", [(True, "test"), (False, "development")])
def test_real_fixture_refuses_before_drop_all_or_init_db(monkeypatch, wrong_engine, environment):
    import conftest

    calls = []
    monkeypatch.setattr(conftest, "_EXPECTED_TEST_DATABASE_URL", EXPECTED)
    monkeypatch.setattr(conftest, "engine", SimpleNamespace(url=make_url(
        "sqlite:////PRIVATE_UNTOUCHABLE.sqlite" if wrong_engine else EXPECTED)))
    monkeypatch.setattr(conftest, "settings", SimpleNamespace(environment=environment))
    monkeypatch.setattr(conftest.Base.metadata, "drop_all", lambda *args: calls.append("drop"))
    monkeypatch.setattr(conftest, "init_db", lambda: calls.append("init"))
    generator = clean_database.__wrapped__()
    with pytest.raises(RuntimeError, match="dedicated test database"):
        next(generator)
    assert calls == []
