"""A signed APK must still match our production identity and source version."""

import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("android_manifest", Path(__file__).resolve().parents[2] / "scripts/android_manifest.py")
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)
POLICY = {"application_id": "de.dorfspy.schulpilot", "channel": "stable", "android_signer_sha256": "a" * 64}
METADATA = "package: name='de.dorfspy.schulpilot' versionCode='14' versionName='1.0.0'\nsdkVersion:'24'\n"
CERTIFICATE = "Signer #1 certificate SHA-256 digest: " + "a" * 64


@pytest.mark.parametrize(
    ("metadata", "certificate", "error"),
    [
        (METADATA + "application-debuggable\n", CERTIFICATE, "Debuggable"),
        (METADATA, "Signer #1 certificate SHA-256 digest: " + "b" * 64, "signer"),
        (METADATA.replace("versionCode='14'", "versionCode='13'"), CERTIFICATE, "rebuild"),
    ],
)
def test_refuse_unsafe_or_stale_public_release(metadata, certificate, error):
    with pytest.raises(ValueError, match=error):
        manifest.verify_metadata(metadata, certificate, POLICY, "1.0.0", 14)
