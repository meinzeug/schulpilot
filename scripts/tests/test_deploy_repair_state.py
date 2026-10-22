"""Exercise real deploy heredocs through ssh's argv-to-shell boundary, offline."""

import base64
import configparser
import itertools
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "scripts/deploy.sh").read_text()
NAMES = ("schulpilot-repair.service", "schulpilot-repair-dispatcher.service")
RELEASE = "20261022T185914Z-dab103c"
CAPTURE = re.search(r'repair_state_encoded="\$\(ssh dorfspy python3 - <<\'PY\'\n(.*?)\nPY\n\)"', SCRIPT, re.S).group(1)
RESTART = re.search(r'ssh dorfspy python3 - "\$release" "\$repair_state_encoded" <<\'PY\'\n(.*?)\nPY', SCRIPT, re.S).group(1)


class DeployRepairStateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="deploy-state-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / "app"
        self.release = self.app / "releases" / RELEASE
        (self.release / "deploy").mkdir(parents=True)
        (self.app / "current").symlink_to(self.release, target_is_directory=True)
        self.units = self.root / "units"
        self.units.mkdir()
        for name in NAMES:
            (self.units / name).write_text("old-unit")
            (self.release / "deploy" / name).write_text("new-unit")
        self.events = self.root / "events.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        systemctl = self.bin / "systemctl"
        systemctl.write_text(
            "#!/usr/bin/python3\nimport json,os,sys\n"
            "with open(os.environ['TEST_EVENTS'],'a') as output: output.write(json.dumps(sys.argv[1:])+'\\n')\n"
            "if sys.argv[1]=='is-active': sys.exit(0 if json.loads(os.environ['TEST_ACTIVE']).get(sys.argv[-1]) else 3)\n"
        )
        systemctl.chmod(0o755)

    def run_remote(self, snippet, arguments=(), active=None):
        # OpenSSH joins argv with spaces before the login shell interprets it.
        # Only synthetic paths are redirected; the production transport and
        # validation heredocs execute unchanged. systemctl is a local recorder.
        source = snippet.replace("/opt/schulpilot", str(self.app)).replace("/etc/systemd/system", str(self.units))
        environment = {"PATH": str(self.bin) + ":/usr/bin:/bin", "HOME": str(self.root),
                       "TEST_EVENTS": str(self.events), "TEST_ACTIVE": json.dumps(active or {})}
        return subprocess.run(["/bin/sh", "-c", " ".join([sys.executable, "-", *arguments])], input=source,
                              capture_output=True, text=True, env=environment, timeout=10)

    def recorded(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    @staticmethod
    def encoded(value):
        return base64.b64encode(json.dumps(value, separators=(",", ":")).encode()).decode("ascii")

    def test_all_active_selections_survive_real_remote_shell(self):
        for flags in itertools.product((False, True), repeat=2):
            with self.subTest(flags=flags):
                state = dict(zip(NAMES, flags))
                captured = self.run_remote(CAPTURE, active=state)
                self.assertEqual(captured.returncode, 0, captured.stderr)
                encoded = captured.stdout.strip()
                self.assertRegex(encoded, r"^[A-Za-z0-9+/]+={0,2}$")
                self.assertEqual(json.loads(base64.b64decode(encoded, validate=True)), state)
                self.assertEqual(self.recorded(), [["is-active", "--quiet", name] for name in NAMES]
                                 + [["stop", *reversed(NAMES)]])
                self.events.unlink()
                restarted = self.run_remote(RESTART, (RELEASE, encoded))
                self.assertEqual(restarted.returncode, 0, restarted.stderr)
                self.assertEqual(self.recorded(), [["daemon-reload"], *[["start", name] for name in NAMES if state[name]]])
                self.events.unlink()

    def test_missing_units_are_not_installed_or_started(self):
        for unit in self.units.iterdir():
            unit.unlink()
        captured = self.run_remote(CAPTURE, active=dict.fromkeys(NAMES, True))
        self.assertEqual(captured.returncode, 0, captured.stderr)
        self.assertEqual(json.loads(base64.b64decode(captured.stdout)), dict.fromkeys(NAMES, False))
        restarted = self.run_remote(RESTART, (RELEASE, captured.stdout.strip()))
        self.assertEqual(restarted.returncode, 0, restarted.stderr)
        self.assertEqual(self.recorded(), [])
        self.assertEqual(list(self.units.iterdir()), [])

    def test_raw_json_reproduces_ssh_quote_loss(self):
        state = json.dumps(dict.fromkeys(NAMES, True), separators=(",", ":"))
        result = self.run_remote("import json,sys; print(json.dumps(sys.argv[2]))", (RELEASE, state))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(json.loads(result.stdout), state)

    def test_invalid_transport_or_flags_fail_before_any_service_mutation(self):
        valid = dict.fromkeys(NAMES, True)
        invalid = ["!", "A" * 516, self.encoded([]), self.encoded({}),
                   self.encoded({**valid, "unexpected.service": True}),
                   self.encoded({**valid, NAMES[0]: 1}), self.encoded({**valid, NAMES[0]: "true"}),
                   base64.b64encode(b"not-json").decode(), self.encoded(valid) + "!"]
        for encoded in invalid:
            with self.subTest(encoded=encoded[:24]):
                result = self.run_remote(RESTART, (RELEASE, encoded))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid service state", result.stderr)
                self.assertEqual(self.recorded(), [])
                self.assertTrue(all((self.units / name).read_text() == "old-unit" for name in NAMES))

    def test_empty_state_is_rejected_before_mutation(self):
        result = self.run_remote(RESTART, (RELEASE, ""))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid service state", result.stderr)
        self.assertEqual(self.recorded(), [])

    def test_other_active_release_keeps_services_stopped(self):
        result = self.run_remote(RESTART, ("20261022T000000Z-aaaaaaa", self.encoded(dict.fromkeys(NAMES, True))))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("active source differs", result.stderr)
        self.assertEqual(self.recorded(), [])

    def test_dispatcher_service_has_same_package_root_as_learning_worker(self):
        units = []
        for name in ("schulpilot-repair-dispatcher.service", "schulpilot-worker.service"):
            config = configparser.ConfigParser(interpolation=None)
            config.read(ROOT / "deploy" / name)
            units.append(config["Service"])
        self.assertEqual(units[0]["WorkingDirectory"], "/opt/schulpilot/current/backend")
        self.assertEqual(units[0]["WorkingDirectory"], units[1]["WorkingDirectory"])
        self.assertEqual(units[0]["ExecStart"],
                         "/opt/schulpilot/current/venv/bin/python -m schulpilot.operator_repair")

    def test_real_module_entrypoint_resolves_without_database_or_network(self):
        # Only this guard directory is on PYTHONPATH, never the backend. The real
        # -m lookup must therefore succeed through the service WorkingDirectory.
        # Stop at main's first instruction, before any lease/DB/worker operation.
        guard = self.root / "guard"
        guard.mkdir()
        (guard / "sitecustomize.py").write_text(
            "import socket,sqlite3,sys\n"
            "def forbidden(*args,**kwargs): raise RuntimeError('Probe must not connect')\n"
            "socket.socket.connect=forbidden\nsqlite3.connect=forbidden\n"
            "def trace(frame,event,arg):\n"
            "    if event=='call' and frame.f_code.co_name=='main' and frame.f_globals.get('__name__')=='__main__':\n"
            "        if not frame.f_code.co_filename.endswith('/backend/schulpilot/operator_repair.py'):\n"
            "            raise RuntimeError('Unexpected entrypoint')\n"
            "        print('dispatcher_imported_before_any_connection')\n"
            "        raise SystemExit(0)\n"
            "sys.setprofile(trace)\n"
        )
        environment = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "PYTHONPATH": str(guard),
                       "DATABASE_URL": "sqlite:///:memory:", "DATA_DIR": str(self.root / "private-test-data"),
                       "MASTER_KEY": base64.urlsafe_b64encode(bytes(32)).decode(), "ENVIRONMENT": "test"}
        command = [sys.executable, "-m", "schulpilot.operator_repair"]
        result = subprocess.run(command, cwd=ROOT / "backend", env=environment,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "dispatcher_imported_before_any_connection")
        old_location = subprocess.run(command, cwd=ROOT, env=environment,
                                      capture_output=True, text=True, timeout=20)
        self.assertNotEqual(old_location.returncode, 0)
        self.assertIn("No module named 'schulpilot'", old_location.stderr)


if __name__ == "__main__":
    unittest.main()
