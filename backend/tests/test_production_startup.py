"""Production startup must reject the wrong database or migration release."""

from dataclasses import replace
from pathlib import Path

import pytest
from alembic.config import Config
from alembic.script import ScriptDirectory
from schulpilot import db as database
from schulpilot import installation, security
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def startup_database(tmp_path, monkeypatch):
    engine = create_engine("sqlite:///" + str(tmp_path / "startup.sqlite"))
    initializations = []
    monkeypatch.setattr(database, "engine", engine)
    monkeypatch.setattr(database, "DB", sessionmaker(engine))
    monkeypatch.setattr(database, "settings", replace(database.settings, environment="production"))
    monkeypatch.setattr(security, "insert_ignore", lambda *args, **kwargs: initializations.append("provider"))
    monkeypatch.setattr(installation, "initialize", lambda: initializations.append("installation"))
    yield engine, initializations
    engine.dispose()


def release_heads():
    config = Config()
    config.set_main_option("script_location", str(Path(__file__).resolve().parents[1] / "migrations"))
    return set(ScriptDirectory.from_config(config).get_heads(consider_depends_on=True))


def migration_marker(engine, revisions):
    with engine.begin() as connection:
        connection.execute(text("CREATE TABLE alembic_version (version_num VARCHAR(32) PRIMARY KEY)"))
        for revision in revisions:
            connection.execute(text("INSERT INTO alembic_version (version_num) VALUES (:revision)"),
                               {"revision": revision})


def pretend_postgresql(engine, monkeypatch):
    # Only the declared dialect name is substituted. Connections, marker rows,
    # reflection and SELECT execution use this test's real temporary SQLite DB.
    monkeypatch.setattr(engine.dialect, "name", "postgresql")


def test_production_rejects_sqlite_before_connecting_or_initializing(startup_database, monkeypatch):
    engine, initializations = startup_database
    migration_marker(engine, release_heads())

    def unexpected_connection():
        pytest.fail("Production SQLite rejection must happen before connecting")

    monkeypatch.setattr(engine, "connect", unexpected_connection)
    with pytest.raises(RuntimeError, match="Production requires PostgreSQL"):
        database.init_db()
    assert initializations == []


def test_production_rejects_missing_migration_marker(startup_database, monkeypatch):
    engine, initializations = startup_database
    pretend_postgresql(engine, monkeypatch)
    with pytest.raises(RuntimeError, match="migrations must be applied"):
        database.init_db()
    assert initializations == []
    assert inspect(engine).get_table_names() == []


@pytest.mark.parametrize("revisions", [[], ["0001"], ["9999_future"]], ids=["empty", "stale", "future"])
def test_production_rejects_marker_that_does_not_match_release(startup_database, monkeypatch, revisions):
    engine, initializations = startup_database
    migration_marker(engine, revisions)
    pretend_postgresql(engine, monkeypatch)
    with pytest.raises(RuntimeError, match="migrations must match the current release"):
        database.init_db()
    assert initializations == []
    assert inspect(engine).get_table_names() == ["alembic_version"]


def test_production_accepts_current_release_without_creating_schema(startup_database, monkeypatch):
    engine, initializations = startup_database
    migration_marker(engine, release_heads())
    pretend_postgresql(engine, monkeypatch)
    database.init_db()
    assert initializations == ["provider", "installation"]
    assert inspect(engine).get_table_names() == ["alembic_version"]


def test_production_rejects_extra_marker_even_with_current_release_present(startup_database, monkeypatch):
    engine, initializations = startup_database
    migration_marker(engine, release_heads() | {"9999_future"})
    pretend_postgresql(engine, monkeypatch)
    with pytest.raises(RuntimeError, match="migrations must match the current release"):
        database.init_db()
    assert initializations == []


@pytest.mark.parametrize("revisions, accepted", [(["left_head"], False),
                                                (["left_head", "right_head"], True)])
def test_production_requires_all_release_heads(startup_database, monkeypatch, revisions, accepted):
    engine, initializations = startup_database
    migration_marker(engine, revisions)
    pretend_postgresql(engine, monkeypatch)

    class BranchedRelease:
        def get_heads(self, *, consider_depends_on):
            assert consider_depends_on is True
            return ["left_head", "right_head"]

    def branched_release(config):
        assert config.get_main_option("script_location") == str(
            Path(database.__file__).resolve().parent.parent / "migrations")
        return BranchedRelease()

    monkeypatch.setattr(ScriptDirectory, "from_config", branched_release)
    if accepted:
        database.init_db()
        assert initializations == ["provider", "installation"]
    else:
        with pytest.raises(RuntimeError, match="migrations must match the current release"):
            database.init_db()
        assert initializations == []


def test_production_rejects_release_without_migration_heads(startup_database, monkeypatch):
    engine, initializations = startup_database
    pretend_postgresql(engine, monkeypatch)
    monkeypatch.setattr(ScriptDirectory, "get_heads", lambda self, **kwargs: [])
    with pytest.raises(RuntimeError, match="migration scripts with a current head"):
        database.init_db()
    assert initializations == []


def test_production_accepts_effective_head_after_dependency_branch_upgrade(startup_database, monkeypatch, tmp_path):
    engine, initializations = startup_database
    versions = tmp_path / "migrations" / "versions"
    versions.mkdir(parents=True)
    (versions / "base.py").write_text('revision = "base"\ndown_revision = None\n')
    (versions / "dependency.py").write_text('revision = "dependency"\ndown_revision = "base"\n')
    (versions / "dependent.py").write_text(
        'revision = "dependent"\ndown_revision = "base"\ndepends_on = "dependency"\n')
    scripts = ScriptDirectory(str(versions.parent))
    assert set(scripts.get_heads()) == {"dependency", "dependent"}
    assert scripts.get_heads(consider_depends_on=True) == ["dependent"]
    migration_marker(engine, ["dependent"])
    pretend_postgresql(engine, monkeypatch)
    monkeypatch.setattr(ScriptDirectory, "from_config", lambda config: scripts)
    database.init_db()
    assert initializations == ["provider", "installation"]


def test_nonproduction_still_initializes_sqlite_without_migration_marker(startup_database, monkeypatch):
    engine, initializations = startup_database
    monkeypatch.setattr(database, "settings", replace(database.settings, environment="test"))
    database.init_db()
    assert initializations == ["provider", "installation"]
    tables = set(inspect(engine).get_table_names())
    assert "families" in tables
    assert "users" in tables
    assert "alembic_version" not in tables
