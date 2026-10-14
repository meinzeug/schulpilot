"""Read-only local Google release preflight; never creates cloud resources."""

import argparse
import json
import subprocess
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundletool", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/google-readiness.json"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with urllib.request.urlopen("https://schulpilot.dorfspy.de/api/legal", timeout=20) as response:
        legal = json.load(response)
    with urllib.request.urlopen("https://schulpilot.dorfspy.de/api/app-release", timeout=20) as response:
        release = json.load(response)
    report = {
        "package": "de.dorfspy.schulpilot",
        "operator_details_complete": legal["complete"],
        "operator_data_approval": legal["operator_data_approval"],
        "public_apk_available": release.get("available", False),
        "public_version_code": release.get("version_code"),
        "aab_built": (root / "artifacts/schulpilot-play.aab").is_file(),
        "store_texts_prepared": all(
            (root / ("store/de-DE/" + name + ".txt")).is_file()
            for name in ("title", "short_description", "full_description")
        ),
        "play_upload_performed": False,
        "physical_device_test": "not_recorded",
        "live_push_delivery": "see_separate_delivery_observation_reports",
    }
    if args.bundletool and report["aab_built"]:
        result = subprocess.run(
            [
                "java",
                "-jar",
                str(args.bundletool),
                "validate",
                "--bundle=" + str(root / "artifacts/schulpilot-play.aab"),
            ],
            capture_output=True,
            timeout=60,
        )
        report["bundletool_valid"] = result.returncode == 0
    for name, limit in (("title", 30), ("short_description", 80), ("full_description", 4000)):
        if len((root / ("store/de-DE/" + name + ".txt")).read_text().strip()) > limit:
            raise SystemExit("Store text exceeds character limit: " + name)
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
