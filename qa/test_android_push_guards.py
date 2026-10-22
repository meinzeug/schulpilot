"""Local-only guards; no emulator, account login or Firebase calls."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import android_push
import android_push_background


class AndroidPushGuardsTest(unittest.TestCase):
    def test_credentials_accept_old_and_explicit_synthetic_wrapped_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.json"
            credentials = {"child_username": "synthetic_child", "child_password": "synthetic_only"}
            for fixture in (credentials, {"synthetic_only": True, "credentials": credentials}):
                android_push.safe_write(path, fixture)
                self.assertEqual(android_push.load_credentials(path), credentials)
            android_push.safe_write(path, {"synthetic_only": False, "credentials": credentials})
            with self.assertRaises(android_push.PushQaError):
                android_push.load_credentials(path)
            android_push.safe_write(path, credentials)
            os.chmod(path, 0o644)
            with self.assertRaises(android_push.PushQaError):
                android_push.load_credentials(path)

    def test_send_claim_survives_missing_summary_after_interruption(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "summary.json"
            with patch.object(android_push, "CHECKPOINT", checkpoint):
                self.assertEqual(android_push.mark_send(84), 1)
                checkpoint.unlink()  # Simulated crash before the summary write.
                with self.assertRaisesRegex(android_push.PushQaError, "already_reserved"):
                    android_push.mark_send(84)

    def test_normal_send_limit_is_two_and_cannot_be_reset_by_new_instance(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "summary.json"
            with patch.object(android_push, "CHECKPOINT", checkpoint):
                self.assertEqual(android_push.mark_send(84), 1)
                self.assertEqual(android_push.mark_send(84), 2)
                with self.assertRaisesRegex(android_push.PushQaError, "two_send_intents"):
                    android_push.mark_send(84)
                claims = list(Path(directory).glob(".android-push-*-send-*.json"))
                self.assertEqual(len(claims), 2)
                self.assertTrue(all(path.stat().st_mode & 0o777 == 0o600 for path in claims))

    def test_background_claim_survives_missing_legacy_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "artifacts").mkdir()
            with patch.object(android_push_background, "ROOT", root):
                android_push_background.reserve_one(84)
                (root / "artifacts/.android-push-background-84-checkpoint.json").unlink()
                with self.assertRaisesRegex(android_push.PushQaError, "already_reserved"):
                    android_push_background.reserve_one(84)

    def test_cold_process_requires_pid_absence_without_force_stop(self):
        gone = type("Result", (), {"returncode": 1, "stdout": b""})()
        with patch.object(android_push_background, "adb") as adb, patch.object(
            android_push_background.subprocess, "run", return_value=gone
        ) as run:
            android_push_background.stop_cached_process()
            adb.assert_called_once_with("shell", "am", "kill", android_push_background.PACKAGE)
            self.assertIn("pidof", run.call_args.args[0])

    def test_unreadable_device_state_does_not_allow_cold_send(self):
        error = type("Result", (), {"returncode": 2, "stdout": b""})()
        with patch.object(android_push_background, "adb"), patch.object(
            android_push_background.subprocess, "run", return_value=error
        ):
            with self.assertRaisesRegex(android_push.PushQaError, "no_message_sent"):
                android_push_background.stop_cached_process()


if __name__ == "__main__":
    unittest.main()
