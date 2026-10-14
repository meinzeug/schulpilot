"""Release metadata regressions with synthetic bundles; no network or signing keys."""
import importlib.util
import json
import struct
import subprocess
import tempfile
import unittest
import urllib.error
import zipfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("google_readiness", Path(__file__).with_name("google_readiness.py"))
readiness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(readiness)


def synthetic_elf(*, alignment=16384, relro_end=16384, mismatch=False):
    ident = b"\x7fELF\x02\x01\x01" + bytes(9)
    header = struct.pack("<16sHHIQQQIHHHHHH", ident, 3, 183, 1, 0, 64, 0, 0, 64, 56, 2, 0, 0, 0)
    load = struct.pack("<IIQQQQQQ", 1, 5, 0, 1 if mismatch else 0, 0, 176, 176, alignment)
    relro = struct.pack("<IIQQQQQQ", 0x6474E552, 4, 0, 0, 0, 0, relro_end, 1)
    return header + load + relro


def manifest(*, api=36, package=readiness.PACKAGE, installer=False, version=11):
    permission = '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />' if installer else ""
    return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="' + package + '" android:versionCode="' + str(version) + '" android:versionName="0.1.0"><uses-sdk android:targetSdkVersion="' + str(api) + '" />' + permission + '</manifest>'


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "app").mkdir()
        (self.root / "app/pubspec.yaml").write_text("version: 0.1.0+11\n")
        directory = self.root / "store/de-DE"
        directory.mkdir(parents=True)
        for name, text in (("title", "SCHULPILOT"), ("short_description", "Gemeinsam lernen."), ("full_description", "Synthetischer Testtext.")):
            (directory / (name + ".txt")).write_text(text)
        self.aab = self.root / "selected-version.aab"
        with zipfile.ZipFile(self.aab, "w") as bundle:
            bundle.writestr("base/lib/arm64-v8a/libflutter.so", synthetic_elf())
        self.bundletool = self.root / "bundletool.jar"
        self.bundletool.write_bytes(b"synthetic tool; never executed")
        self.xml = manifest()
        self.config = '{"alignment":"PAGE_ALIGNMENT_16K"}'
        self.signature = "jar verified.\n"
        self.certificate = "Owner: CN=SCHULPILOT Upload\n"
        self.commands = []

    def fetch(self, url):
        return {"complete": True, "operator_data_approval": True} if url.endswith("legal") else {"available": True, "version_code": 11}

    def runner(self, command):
        self.commands.append(command)
        if command[0] == "jarsigner":
            output = self.signature
        elif command[0] == "keytool":
            output = self.certificate
        elif "manifest" in command:
            output = self.xml
        elif "config" in command:
            output = self.config
        else:
            output = "valid"
        return subprocess.CompletedProcess(command, 0, output, "")

    def report(self, **kwargs):
        options = {"aab_path": self.aab, "bundletool": self.bundletool, "fetch": self.fetch, "runner": self.runner}
        options.update(kwargs)
        with patch.object(readiness.shutil, "which", return_value="synthetic executable"):
            return readiness.build_report(self.root, **options)

    def test_valid_metadata_and_separate_runtime_status(self):
        report = self.report()
        self.assertTrue(report["local_preflight_passed"])
        self.assertTrue(report["bundletool_valid"])
        self.assertEqual(report["aab_artifact"]["path"], str(self.aab))
        self.assertEqual(report["native_libraries"]["runtime_16k_test"], "not_performed")
        self.assertFalse(report["play_upload_performed"])
        self.assertEqual(report["live_push_delivery"], "not_recorded")

    def test_missing_artifact_keeps_legacy_field_false(self):
        self.aab.unlink()
        report = self.report()
        self.assertFalse(report["aab_built"])
        self.assertIsNone(report["bundletool_valid"])
        self.assertIn("aab_missing", report["blockers"])

    def test_network_failure_still_returns_report(self):
        def unavailable(url):
            raise urllib.error.URLError("offline fixture")
        report = self.report(fetch=unavailable)
        self.assertIsNone(report["public_apk_available"])
        self.assertIn("legal_endpoint_unavailable_or_invalid", report["blockers"])
        self.assertIn("release_endpoint_unavailable_or_invalid", report["blockers"])

    def test_missing_store_text_becomes_blocker(self):
        (self.root / "store/de-DE/title.txt").unlink()
        report = self.report()
        self.assertFalse(report["store_texts_prepared"])
        self.assertIn("store_text_missing_or_unreadable_title", report["blockers"])

    def test_empty_or_overlong_text_is_not_prepared(self):
        (self.root / "store/de-DE/title.txt").write_text("x" * 31)
        (self.root / "store/de-DE/short_description.txt").write_text(" \n")
        report = self.report()
        self.assertIn("store_text_invalid_title", report["blockers"])
        self.assertIn("store_text_invalid_short_description", report["blockers"])

    def test_target_api_and_installer_permission_reject_direct_bundle(self):
        self.xml = manifest(api=35, installer=True)
        report = self.report()
        self.assertIn("bundle_target_api_below_36_or_unknown", report["blockers"])
        self.assertIn("play_bundle_has_direct_installer_permission", report["blockers"])

    def test_stale_version_and_wrong_package_fail(self):
        self.xml = manifest(package="example.other", version=10)
        report = self.report()
        self.assertIn("bundle_package_mismatch", report["blockers"])
        self.assertIn("bundle_source_version_mismatch_or_unknown", report["blockers"])

    def test_unknown_manifest_target_does_not_pass(self):
        self.xml = manifest(api="@integer/target")
        self.assertIn("bundle_target_api_below_36_or_unknown", self.report()["blockers"])

    def test_debuggable_manifest_does_not_pass(self):
        self.xml = manifest().replace("</manifest>", '<application android:debuggable="true" /></manifest>')
        self.assertIn("play_bundle_is_debuggable", self.report()["blockers"])

    def test_invalid_native_elf_class_is_not_silently_skipped(self):
        data = bytearray(synthetic_elf())
        data[4] = 0
        with self.assertRaises(ValueError):
            readiness.elf_alignment(data)

    def test_debug_certificate_is_blocked(self):
        self.certificate = "Owner: CN=Android Debug, O=Android, C=US\n"
        report = self.report()
        self.assertTrue(report["debug_certificate_detected"])
        self.assertIn("aab_signed_with_android_debug_certificate", report["blockers"])

    def test_jarsigner_exit_zero_for_unsigned_jar_does_not_pass(self):
        self.signature = "jar is unsigned.\n"
        report = self.report()
        self.assertFalse(report["aab_signature_valid"])
        self.assertIn("aab_signature_invalid_or_unsigned", report["blockers"])

    def test_signed_jar_with_unsigned_entries_does_not_pass(self):
        self.signature = "jar verified.\nThis jar contains unsigned entries.\n"
        self.assertFalse(self.report()["aab_signature_valid"])

    def test_16k_zip_does_not_hide_4k_native_library(self):
        with zipfile.ZipFile(self.aab, "w") as bundle:
            bundle.writestr("base/lib/arm64-v8a/libflutter.so", synthetic_elf(alignment=4096))
        report = self.report()
        self.assertTrue(report["bundle_requests_16k_zip_alignment"])
        self.assertFalse(report["native_libraries"]["elf64_alignment_16k"])
        self.assertIn("native_elf64_alignment_missing_or_invalid", report["blockers"])

    def test_bad_relro_and_inconsistent_load_offset_fail(self):
        self.assertFalse(readiness.elf_alignment(synthetic_elf(relro_end=4096))["relro_end_aligned_16k"])
        self.assertFalse(readiness.elf_alignment(synthetic_elf(mismatch=True))["load_segments_16k"])

    def test_4k_zip_blocks_even_when_native_elf_is_aligned(self):
        self.config = '{"alignment":"PAGE_ALIGNMENT_4K"}'
        report = self.report()
        self.assertTrue(report["native_libraries"]["elf64_alignment_16k"])
        self.assertIn("bundle_16k_zip_alignment_missing_or_unknown", report["blockers"])

    def test_corrupt_artifact_becomes_blocker(self):
        self.aab.write_bytes(b"not a zip")
        report = self.report()
        self.assertIn("aab_native_libraries_unreadable", report["blockers"])

    def test_bundletool_failure_never_claims_manifest_pass(self):
        def failed(command):
            if "validate" in command:
                return subprocess.CompletedProcess(command, 1, "", "invalid fixture")
            return self.runner(command)
        report = self.report(runner=failed)
        self.assertFalse(report["bundletool_valid"])
        self.assertIsNone(report["bundle_manifest"])
        self.assertIn("bundletool_validation_failed", report["blockers"])

    def test_missing_bundletool_is_not_success(self):
        report = self.report(bundletool=None)
        self.assertIsNone(report["bundletool_valid"])
        self.assertIn("bundletool_not_provided", report["blockers"])

    def test_strict_cli_writes_failure_report_and_returns_nonzero(self):
        output = self.root / "output.json"
        report = {"blockers": ["aab_missing"]}
        with patch.object(readiness, "build_report", return_value=report), patch("builtins.print"):
            self.assertEqual(readiness.main(["--strict", "--output", str(output)]), 1)
        self.assertEqual(json.loads(output.read_text()), report)


if __name__ == "__main__":
    unittest.main()
