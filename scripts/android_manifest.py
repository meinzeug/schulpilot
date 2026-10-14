"""Verify the public APK against the release policy before deployment."""

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify_metadata(metadata, certificates, policy, version, code):
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata)
    minimum = re.search(r"sdkVersion:'([0-9]+)'", metadata)
    signers = set(re.findall(r"certificate SHA-256 digest: ([a-fA-F0-9]{64})", certificates))
    if not package or package[1] != policy["application_id"] or not minimum:
        raise ValueError("Unexpected APK package or missing Android version")
    if "application-debuggable" in metadata:
        raise ValueError("Debuggable APK cannot be deployed")
    if {value.lower() for value in signers} != {policy["android_signer_sha256"]}:
        raise ValueError("APK signer differs from the public release policy")
    if package[3] != version or int(package[2]) != code:
        raise ValueError("APK version differs from the current source; rebuild before deployment")
    if policy["channel"] != "stable" or version.startswith("0.") or "-" in version:
        raise ValueError("Only stable releases can be deployed")
    return {
        "application_id": package[1],
        "version_code": int(package[2]),
        "version": package[3],
        "min_android": {24: "7.0"}.get(int(minimum[1]), str(minimum[1])),
        "channel": "stable",
    }


def main():
    apk = ROOT / "artifacts/schulpilot-android.apk"
    sdk = Path(os.getenv("ANDROID_SDK_ROOT", str(Path.home() / "android-sdk")))
    tools = sdk / "build-tools/36.0.0"
    certificates = subprocess.check_output([str(tools / "apksigner"), "verify", "--print-certs", str(apk)], text=True)
    subprocess.run([str(tools / "zipalign"), "-c", "-P", "16", "4", str(apk)], check=True)
    metadata = subprocess.check_output([str(tools / "aapt"), "dump", "badging", str(apk)], text=True)
    version = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)$", (ROOT / "app/pubspec.yaml").read_text(), re.M)
    if not version or f'__version__ = "{version[1]}"' not in (ROOT / "backend/schulpilot/__init__.py").read_text():
        raise SystemExit("App and backend version must match")
    data = verify_metadata(metadata, certificates, json.loads((ROOT / "release-policy.json").read_text()), version[1], int(version[2]))
    data.update(size_bytes=apk.stat().st_size, sha256=hashlib.file_digest(apk.open("rb"), "sha256").hexdigest())
    (ROOT / "artifacts/android-release.json").write_text(json.dumps(data) + "\n")
    print(json.dumps(data))


if __name__ == "__main__":
    main()
