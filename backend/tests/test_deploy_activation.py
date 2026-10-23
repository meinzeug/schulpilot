"""Run the real activation script against temporary files and offline OS mocks."""

import builtins
import runpy
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SCRIPT = Path(__file__).parents[2] / "deploy/activate.py"
WRITERS = ["schulpilot-api", "schulpilot-worker"]


class Activation:
    def __init__(self, root, failure=None, *, changed_schema=False):
        self.root, self.failure, self.changed_schema = root, failure, changed_schema
        self.commands, self.schema_reads, self.restarts = [], 0, []
        self.base = root / "opt/schulpilot"
        self.old = self.base / "releases/old98"
        self.new = self.base / "releases/new99"
        for release in (self.old, self.new):
            for name, content in {
                "web/index.html": "synthetic web",
                "backend/requirements.lock": "synthetic requirements",
                "venv/bin/pip": "synthetic existing venv",
                "deploy/Caddyfile.schulpilot": "old fragment" if release == self.old else "new fragment",
                "deploy/schulpilot-api.service": "synthetic service",
            }.items():
                path = release / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
        self.current = self.base / "current"
        self.current.symlink_to(self.old)
        self.prior = self.base / "previous"
        self.prior.symlink_to(self.base / "releases/older97")
        self.caddy = root / "etc/caddy/Caddyfile"
        self.caddy.parent.mkdir(parents=True)
        self.caddy.write_text("import /etc/caddy/schulpilot.caddy\n")
        self.fragment = self.caddy.parent / "schulpilot.caddy"
        self.fragment.write_text("old fragment")
        environment = root / "etc/schulpilot/environment"
        environment.parent.mkdir(parents=True)
        environment.write_text("DATABASE_URL=synthetic-no-connection\n")
        (root / "etc/systemd/system").mkdir(parents=True)

    def path(self, *parts):
        path = Path(*parts)
        if str(path).startswith(("/opt/schulpilot", "/etc/")):
            return self.root / str(path).lstrip("/")
        return path

    def run(self, command, **kwargs):
        command = list(map(str, command))
        self.commands.append(command)
        if command[0] == "runuser" and "-c" in command:
            self.schema_reads += 1
            schema = "0032" if self.changed_schema and self.schema_reads > 1 else "0031"
            return subprocess.CompletedProcess(command, 0, stdout=schema + "\n")
        if command[:3] == ["systemctl", "show", "schulpilot-backup.service"]:
            return subprocess.CompletedProcess(command, 0, stdout="success\n")
        if command == ["systemctl", "restart", *WRITERS]:
            self.restarts.append((self.current.resolve(), kwargs.get("check")))
        failed = (
            (self.failure == "validate" and command[:2] == ["caddy", "validate"])
            or (self.failure == "enable" and command[:2] == ["systemctl", "enable"])
            or (self.failure == "migration" and "schulpilot.migrate" in command)
            or (self.failure == "restart" and command == ["systemctl", "restart", *WRITERS] and kwargs.get("check"))
            or (self.failure == "timer" and command[:3] == ["systemctl", "start", "schulpilot-backup.timer"])
            or (self.failure == "caddy" and command == ["systemctl", "reload", "caddy"] and kwargs.get("check"))
        )
        if failed:
            raise subprocess.CalledProcessError(1, command)
        return subprocess.CompletedProcess(command, 0, stdout="")

    def health(self, *_args, **_kwargs):
        self.commands.append(["health"])
        if self.failure == "health":
            raise OSError("synthetic health unavailable")
        return SimpleNamespace(__enter__=lambda self: self, __exit__=lambda *_: None, status=200)

    def execute(self, monkeypatch, rollback_compatible=False):
        real_import = builtins.__import__

        class Health:
            def __enter__(self):
                return SimpleNamespace(status=200)
            def __exit__(self, *_):
                return None

        def urlopen(*args, **kwargs):
            self.health(*args, **kwargs)
            return Health()

        replacements = {
            "pathlib": SimpleNamespace(Path=self.path),
            "subprocess": SimpleNamespace(run=self.run),
            "time": SimpleNamespace(sleep=lambda _: None),
            "urllib.request": SimpleNamespace(request=SimpleNamespace(urlopen=urlopen)),
        }

        def imports(name, globals=None, locals=None, fromlist=(), level=0):
            return replacements.get(name) or real_import(name, globals, locals, fromlist, level)

        monkeypatch.setattr(sys, "argv", [str(SCRIPT), "new99", *(["--rollback-compatible"] if rollback_compatible else [])])
        return runpy.run_path(str(SCRIPT), init_globals={"__builtins__": {**vars(builtins), "__import__": imports}})


@pytest.mark.parametrize("rollback_compatible", [False, True])
@pytest.mark.parametrize("failure", ["validate", "enable"])
def test_failure_before_new_writers_keeps_schema_safe_old_release(tmp_path, monkeypatch, capsys, rollback_compatible, failure):
    activation = Activation(tmp_path, failure)
    with pytest.raises(subprocess.CalledProcessError):
        activation.execute(monkeypatch, rollback_compatible)
    assert activation.current.resolve() == activation.old
    assert activation.restarts == [(activation.old, False)]
    assert activation.fragment.read_text() == "old fragment"
    assert "incompatible JSON" not in capsys.readouterr().err


@pytest.mark.parametrize("changed_schema", [False, True])
def test_migration_failure_before_new_writers_only_rolls_back_unchanged_schema(tmp_path, monkeypatch, capsys, changed_schema):
    activation = Activation(tmp_path, "migration", changed_schema=changed_schema)
    with pytest.raises(subprocess.CalledProcessError):
        activation.execute(monkeypatch)
    assert activation.schema_reads == 2
    if changed_schema:
        assert activation.current.resolve() == activation.new
        assert activation.restarts == []
        assert ["systemctl", "stop", *WRITERS] in activation.commands
        assert "Schema changed" in capsys.readouterr().err
    else:
        assert activation.current.resolve() == activation.old
        assert activation.restarts == [(activation.old, False)]


@pytest.mark.parametrize("rollback_compatible", [False, True])
@pytest.mark.parametrize("failure", ["restart", "timer", "health", "caddy"])
def test_possible_new_writer_always_stops_and_retains_new_reader(tmp_path, monkeypatch, capsys, rollback_compatible, failure):
    activation = Activation(tmp_path, failure)
    expected = RuntimeError if failure == "health" else subprocess.CalledProcessError
    with pytest.raises(expected):
        activation.execute(monkeypatch, rollback_compatible)
    assert activation.current.resolve() == activation.new
    assert activation.restarts == [(activation.new, True)]  # Partial restart may already have written.
    assert activation.schema_reads == (0 if rollback_compatible else 1)  # Never read revision after possible writes.
    stop = ["systemctl", "stop", *WRITERS]
    failure_index = (max(i for i, cmd in enumerate(activation.commands) if cmd == ["health"])
                     if failure == "health" else next(i for i, cmd in enumerate(activation.commands)
                     if (cmd == ["systemctl", "restart", *WRITERS] if failure == "restart"
                         else cmd[:3] == ["systemctl", "start", "schulpilot-backup.timer"] if failure == "timer"
                         else cmd == ["systemctl", "reload", "caddy"])))
    assert activation.commands[failure_index + 1] == stop
    assert activation.fragment.read_text() == "old fragment"
    assert activation.prior.readlink() == activation.base / "releases/older97"
    message = capsys.readouterr().err
    assert "current release retained" in message and "compatible forward fix" in message
    assert "--rollback-compatible are not sufficient" in message


@pytest.mark.parametrize("rollback_compatible", [False, True])
def test_success_activates_new_release_and_preserves_previous_pointer(tmp_path, monkeypatch, capsys, rollback_compatible):
    activation = Activation(tmp_path)
    activation.execute(monkeypatch, rollback_compatible)
    assert activation.current.resolve() == activation.new and activation.prior.resolve() == activation.old
    assert activation.restarts == [(activation.new, True)]
    assert activation.fragment.read_text() == "new fragment"
    assert activation.schema_reads == (0 if rollback_compatible else 1)
    assert activation.commands[-1] == ["systemctl", "reload", "caddy"]
    assert "SCHULPILOT activated: new99" in capsys.readouterr().out
