"""Read actual APK metadata/signature and publish only a public release manifest."""

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
apk = root / "artifacts/schulpilot-0.1.0-test.apk"
sdk = Path(os.getenv("ANDROID_SDK_ROOT", str(Path.home() / "android-sdk")))
tools = sdk / "build-tools/36.0.0"
subprocess.run([str(tools / "apksigner"), "verify", str(apk)], check=True)
metadata = subprocess.check_output([str(tools / "aapt"), "dump", "badging", str(apk)], text=True)
package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata)
minimum = re.search(r"sdkVersion:'([0-9]+)'", metadata)
if not package or package[1] != "de.dorfspy.schulpilot" or not minimum:
    raise SystemExit("Unexpected APK metadata")
digest = hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()
data = {
    "application_id": package[1],
    "version_code": int(package[2]),
    "version": package[3],
    "min_android": {24: "7.0"}.get(int(minimum[1]), str(minimum[1])),
    "size_bytes": apk.stat().st_size,
    "sha256": digest,
    "channel": "test",
}
(root / "artifacts/android-release.json").write_text(json.dumps(data) + "\n")
print(json.dumps(data))
