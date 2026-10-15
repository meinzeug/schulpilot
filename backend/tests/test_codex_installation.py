"""Only the two public operator policy values may reach the rootless worker."""

import importlib.util
import json
import runpy
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("codex_installation", ROOT / "deploy/install_codex.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


@pytest.mark.parametrize("configuration, expected", [
    ("CODEX_AUTH_MODE=account\nMASTER_KEY=DO-NOT-PASS\n", {"auth_mode": "account", "web_search": False}),
    ("CODEX_AUTH_MODE=api_key\n", {"auth_mode": "api_key", "web_search": True}),
    ("CODEX_AUTH_MODE=account\nCODEX_WEB_SEARCH=true\n", {"auth_mode": "account", "web_search": True}),
    ("CODEX_AUTH_MODE=api_key\nCODEX_WEB_SEARCH=false\n", {"auth_mode": "api_key", "web_search": False}),
])
def test_installer_reads_only_explicit_nonsecret_policy(tmp_path, configuration, expected):
    environment = tmp_path / "environment"
    environment.write_text(configuration)
    policy = installer.worker_policy(environment)
    assert policy == expected and "DO-NOT-PASS" not in json.dumps(policy)


@pytest.mark.parametrize("configuration", ["CODEX_AUTH_MODE=other", "CODEX_WEB_SEARCH=yes"])
def test_installer_rejects_invalid_operator_policy(tmp_path, configuration):
    environment = tmp_path / "environment"
    environment.write_text(configuration)
    with pytest.raises(SystemExit, match="Invalid local Codex search policy"):
        installer.worker_policy(environment)


def test_container_launcher_does_not_inherit_app_secrets_or_mount_policy(tmp_path):
    recorded = []

    class Launched(Exception):
        pass

    def read_text(path, *args, **kwargs):
        if str(path) == "/opt/schulpilot-codex/image-id":
            return "sha256:" + "a" * 64
        if str(path) == "/opt/schulpilot-codex/search-policy.json":
            return '{"auth_mode":"account","web_search":false}'
        raise AssertionError("Unexpected file read")

    def execute(binary, arguments):
        recorded.append(arguments)
        raise Launched()

    with patch.object(Path, "read_text", read_text), patch("os.execv", execute), pytest.raises(Launched):
        runpy.run_path(str(ROOT / "workers/codex/run.py"))
    args = recorded[0]
    assert "--env=CODEX_AUTH_MODE=account" in args and "--env=CODEX_WEB_SEARCH=false" in args
    assert not any("MASTER_KEY" in argument or "environment" in argument for argument in args)
    assert sum(argument.startswith("--mount=") for argument in args) == 2
