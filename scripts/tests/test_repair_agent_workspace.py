"""Offline launcher regression, no model, database, network or real credentials."""

import importlib.util
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


source = load("source_policy", ROOT / "backend/schulpilot/repair_source.py")
sys.modules["source_policy"] = source
agent = load("repair_workspace_agent", ROOT / "workers/repair/agent.py")


class RepairAgentWorkspaceTest(unittest.TestCase):
    def test_synthetic_instruction_matches_its_existing_patch_boundary(self):
        prompt = agent.repair_prompt('{"code":"synthetic_repair"}', "decision-closed-v1")
        self.assertIn("Only edit backend/schulpilot/instructional_decisions.py.", prompt)
        self.assertIn("Do not add or change tests or any other file.", prompt)
        self.assertNotIn("add matching tests", prompt)

    def test_regular_incident_can_still_add_a_regression_test(self):
        self.assertIn("add matching tests", agent.repair_prompt('{"code":"decision_closed"}'))

    def test_unknown_trusted_fixture_is_rejected_before_cli(self):
        with self.assertRaisesRegex(ValueError, "synthetic_fixture"):
            agent.repair_prompt("{}", "other-fixture")

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="repair-workspace-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.baseline = self.root / "baseline"
        self.mount = self.root / "workspace"
        self.baseline.mkdir()
        self.mount.mkdir()
        (self.baseline / "backend/schulpilot").mkdir(parents=True)
        self.contents = b"synthetic_value = 1\n"
        (self.baseline / "backend/schulpilot/example.py").write_bytes(self.contents)

    def test_copy_uses_owned_child_without_changing_mount_metadata(self):
        copystat = shutil.copystat

        def root_owned_mount(before, after, **kwargs):
            if Path(after) == self.mount:
                raise PermissionError(1, "Operation not permitted")
            return copystat(before, after, **kwargs)

        with patch.object(agent.shutil, "copystat", side_effect=root_owned_mount):
            with self.assertRaisesRegex(shutil.Error, "Operation not permitted"):
                shutil.copytree(self.baseline, self.mount, dirs_exist_ok=True)
            workspace = agent.prepare_workspace(self.baseline, self.mount)
        self.assertEqual(workspace, self.mount / "source")
        self.assertEqual((workspace / "backend/schulpilot/example.py").read_bytes(), self.contents)
        self.assertEqual((self.baseline / "backend/schulpilot/example.py").read_bytes(), self.contents)

    def test_existing_candidate_is_never_reused(self):
        (self.mount / "source").mkdir()
        with self.assertRaises(FileExistsError):
            agent.prepare_workspace(self.baseline, self.mount)

    def test_cli_and_archive_use_same_inner_workspace(self):
        workspace = agent.prepare_workspace(self.baseline, self.mount)
        home = self.root / "codex-home"
        incident = self.root / "incident.json"
        incident.write_text('{"code":"synthetic_repair"}')
        job = self.root / "job.json"
        job.write_text('{"seconds":1,"source_commit":"' + "a" * 40 + '"}')
        token = self.root / "dummy-token"
        token.write_text("synthetic-dummy")
        mapped = {"/tmp/codex-home": home, "/incident/incident.json": incident,
                  "/incident/job.json": job, "/proxy/token": token}
        output = SimpleNamespace(buffer=io.BytesIO())
        server = SimpleNamespace(server_port=1234, serve_forever=lambda: None, shutdown=lambda: None)
        with patch.object(agent, "runtime_guards"), patch.object(agent, "prepare_workspace", return_value=workspace), \
                patch.object(agent, "Path", side_effect=lambda value: Path(mapped.get(str(value), value))), \
                patch.object(agent, "ThreadingHTTPServer", return_value=server), \
                patch.object(agent.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
                patch.object(agent.sys, "stdout", output), patch.object(agent.sys, "argv", ["agent.py"]):
            agent.main()
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("-C") + 1], str(workspace))
        self.assertEqual(run.call_args.kwargs["cwd"], workspace)
        self.assertEqual(source.read_archive(output.buffer.getvalue(), "a" * 40),
                         {"backend/schulpilot/example.py": self.contents})

    def test_guards_run_before_workspace_preparation(self):
        with patch.object(agent, "runtime_guards", side_effect=ValueError("outer_container_guard")), \
                patch.object(agent, "prepare_workspace") as prepare:
            with self.assertRaisesRegex(ValueError, "outer_container_guard"):
                agent.main()
        prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
