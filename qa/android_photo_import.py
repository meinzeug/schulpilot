"""Real API-36 gallery import; prepare/run only against our dedicated QA family.

Run AFTER deploying and updating the existing emulator APK, never via adb install:
    .venv/bin/python qa/android_photo_import.py

Only emulator-5580 / de.dorfspy.schulpilot and the two artificial JPEGs generated
by scripts/prepare_normal_ai_smoke.py are eligible. The regular QA family's
private JSON gains a separate child under ``android_photo_import``. Leave that
child/materials for the operator's existing whole-QA-family cleanup.

The API-36 image_picker_android implementation uses the system Photo Picker.
We open its SchulpilotQA album, require exactly our two indexed images, select
both and confirm two actual crop dialogs. We NEVER press Weiter or start OCR.
If the system picker presents different accessibility labels, stop explicitly
and leave the picker/screenshot for interactive inspection; never guess photos.

Official references checked 2026-10-14:
https://developer.android.com/training/data-storage/shared/photo-picker
https://developer.android.com/training/data-storage/shared/media
https://developer.android.com/reference/android/content/Intent#ACTION_MEDIA_SCANNER_SCAN_FILE
The documented scan-file broadcast is deprecated since API 29. It is used only
to index these ADB-created emulator fixtures; success is verified in MediaStore.
No undocumented media-provider call or broad storage permission is used.
"""

import argparse
import hashlib
import io
import json
import os
import re
import secrets
import shlex
import sys
import tempfile
import time
from pathlib import Path

import httpx
from android_smoke import ARTIFACTS, BASE, HEADERS, PACKAGE, adb, check, login, nodes, press, screenshot, tap_node, wait
from PIL import Image

PRIVATE = ARTIFACTS / ".school-day-qa-account.json"
KEY = "android_photo_import"
ALBUM = "SchulpilotQA"
RELATIVE = "Pictures/SchulpilotQA/"
DEVICE_DIR = "/sdcard/Pictures/SchulpilotQA"
FILENAMES = ("normal-school-page-1.jpg", "normal-school-page-2.jpg")
PHASE = "preflight"


class QaError(RuntimeError):
    """Only explicit, content-free errors may be included in the result."""


def read_private():
    if not PRIVATE.is_file() or PRIVATE.is_symlink():
        raise QaError("Prepare the regular QA family first; the private account file is missing or unsafe.")
    PRIVATE.chmod(0o600)
    data = json.loads(PRIVATE.read_text())
    address = data.get("credentials", {}).get("parent_username", "")
    if data.get("normal_account") is not True or not re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", address):
        raise QaError("Only the regular family created by prepare_normal_ai_smoke.py may be used.")
    if not data.get("verified") or not data.get("user", {}).get("id") or not data.get("child_id"):
        raise QaError("The dedicated regular QA parent and original child must be fully prepared.")
    return data


def save_probe(probe):
    # Merge the latest private file: do not discard browser QA continuation data.
    data = read_private()
    data[KEY] = probe
    with tempfile.NamedTemporaryFile(mode="w", dir=ARTIFACTS, prefix=".native-photo-", delete=False) as output:
        temporary = Path(output.name)
        os.fchmod(output.fileno(), 0o600)
        json.dump(data, output)
        output.write("\n")
    temporary.replace(PRIVATE)


def prepare_child(parent, data):
    credentials = data["credentials"]
    response = check(
        parent.post(
            "/auth/login",
            json={
                "username": credentials["parent_username"],
                "password": credentials["parent_password"],
                "device": "Private native photo QA",
            },
        )
    )
    parent.headers["Authorization"] = "Bearer " + response["token"]
    user = response["user"]
    families = user.get("families", [])
    if user.get("id") != data["user"]["id"] or user.get("role") != "parent" or len(families) != 1:
        raise QaError("Authenticated parent does not match the dedicated single-family QA account.")
    family = check(parent.get("/families/" + families[0]["id"]))
    if family.get("synthetic") is not False or family.get("permission") != "owner":
        raise QaError("A regular QA-family owner is required; no permissions or limits will be changed.")
    if not any(child["id"] == data["child_id"] for child in family["children"]):
        raise QaError("The original prepared child does not belong to this authenticated QA family.")
    probe = data.get(KEY)
    if probe is None:
        probe = {
            "family_id": family["id"],
            "parent_id": user["id"],
            "username": "normal-photo-child-" + secrets.token_hex(6),
            "password": secrets.token_urlsafe(28),
        }
        save_probe(probe)  # Preserve credentials before a possibly interrupted create request.
    if probe.get("family_id") != family["id"] or probe.get("parent_id") != user["id"]:
        raise QaError("The saved native-photo child belongs to another test scope.")
    if not re.fullmatch(r"normal-photo-child-[a-f0-9]{12}", probe.get("username", "")):
        raise QaError("The separate photo-test username is invalid.")
    if not re.fullmatch(r"[A-Za-z0-9_-]{20,128}", probe.get("password", "")):
        raise QaError("The saved photo-test password is not safe for the native input helper.")
    existing = [child for child in family["children"] if child["username"] == probe["username"]]
    if existing:
        child = existing[0]
        if probe.get("child_id") and probe["child_id"] != child["id"]:
            raise QaError("Stored photo-test child ID does not match its family membership.")
    else:
        if probe.get("child_id"):
            raise QaError("The previous photo-test child no longer exists; inspect private QA state before rerunning.")
        if len(family["children"]) >= family["child_limit"]:
            raise QaError("This own QA family has no spare child slot; no subscription limit was changed.")
        child = check(
            parent.post(
                "/families/" + family["id"] + "/children",
                json={
                    "display_name": "Künstlicher Foto-Test",
                    "username": probe["username"],
                    "password": probe["password"],
                    "grade": 6,
                    "subjects": ["Mathematik"],
                },
            ),
            201,
        )
    if child["id"] == data["child_id"]:
        raise QaError("The photo test must never reuse the existing AI-test child.")
    probe["child_id"] = child["id"]
    save_probe(probe)
    return probe


def media_names():
    where = shlex.quote("relative_path='" + RELATIVE + "'")
    command = (
        "content query --uri content://media/external/images/media --projection _id:_display_name:relative_path --where "
        + where
    )
    output = adb("shell", command).decode(errors="replace")
    if "Error" in output or "Exception" in output:
        raise QaError("The emulator's MediaStore query could not verify the dedicated photo album.")
    return re.findall(r"(?:^|[ ,])_display_name=([^,\r\n]+)", output)


def index_artificial_photos():
    existing = media_names()
    if set(existing) - set(FILENAMES):
        raise QaError("The dedicated emulator album contains unexpected files; no images were touched.")
    hashes = []
    for name in FILENAMES:
        source = ARTIFACTS / name
        if not source.is_file() or source.is_symlink() or source.stat().st_size > 10 * 1024 * 1024:
            raise QaError("The two original artificial JPEG fixtures are missing or unsafe.")
        with Image.open(source) as image:
            if image.format != "JPEG" or image.size != (1400, 900) or image.getexif():
                raise QaError("Native import requires the metadata-free JPEGs produced by prepare_normal_ai_smoke.py.")
        hashes.append(hashlib.sha256(source.read_bytes()).hexdigest())
    if len(set(hashes)) != 2:
        raise QaError("The two artificial source pages must be different images.")
    adb("shell", "mkdir", "-p", DEVICE_DIR)
    for name in FILENAMES:
        adb("push", str(ARTIFACTS / name), DEVICE_DIR + "/" + name)
        adb(
            "shell",
            "am",
            "broadcast",
            "--receiver-foreground",
            "-a",
            "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d",
            "file://" + DEVICE_DIR + "/" + name,
        )
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        indexed = media_names()
        if len(indexed) == 2 and set(indexed) == set(FILENAMES):
            return
        if set(indexed) - set(FILENAMES):
            raise QaError("Unexpected MediaStore images in the own album; selection was not attempted.")
        time.sleep(1)
    raise QaError(
        "API36 did not index both fixtures. Inspect the deprecated scan broadcast/MediaStore; do not select arbitrary recent photos."
    )


def labels(node):
    return " ".join([node.get("text", ""), node.get("content-desc", "")]).strip()


def system_picker(node):
    package = node.get("package", "")
    return "providers.media" in package or "photopicker" in package


def find_system_label(pattern):
    matches = [node for node in nodes() if system_picker(node) and re.search(pattern, labels(node), re.IGNORECASE)]
    clickable = [node for node in matches if node.get("clickable") == "true"]
    return (clickable or matches)[-1] if matches else None


def bounds(node):
    values = [int(value) for value in re.findall(r"\d+", node.get("bounds", ""))]
    return values if len(values) == 4 else [0, 0, 0, 0]


def photo_tiles():
    candidates = []
    for node in nodes():
        x1, y1, x2, y2 = bounds(node)
        width, height = x2 - x1, y2 - y1
        resource = node.get("resource-id", "").lower()
        if not system_picker(node) or min(width, height) < 120 or not 0.65 < width / max(height, 1) < 1.55:
            continue
        is_photo = "thumbnail" in resource or re.search(r"\b(photo|foto|image|bild)\b", labels(node), re.IGNORECASE)
        if not is_photo:
            continue
        center = ((x1 + x2) // 2, (y1 + y2) // 2)
        if any(abs(center[0] - previous[0]) < 30 and abs(center[1] - previous[1]) < 30 for previous, _ in candidates):
            continue
        candidates.append((center, node))
    return [node for _, node in sorted(candidates, key=lambda item: (item[0][1], item[0][0]))]


def choose_two_in_system_picker():
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        album = find_system_label(r"\bSchulpilotQA\b")
        if album:
            tap_node(album)
            break
        tab = find_system_label(r"\b(Albums|Alben|Collections|Sammlungen)\b")
        if tab:
            tap_node(tab)
        time.sleep(0.6)
    else:
        raise QaError(
            "Expected Android system-picker Albums/Collections → SchulpilotQA. Picker layout may require interactive inspection; no photos were guessed."
        )
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        tiles = photo_tiles()
        if len(tiles) == 2:
            break
        time.sleep(0.5)
    else:
        raise QaError(
            "SchulpilotQA must expose exactly two accessible image thumbnails. Inspect android-photo-import-debug.png and adjust only this test driver."
        )
    for tile in tiles:
        tap_node(tile)
    time.sleep(0.5)
    current = nodes()
    count_visible = any(
        re.search(
            r"(?:\b2\s*(?:selected|ausgewählt|photos|Fotos)|(?:Add|Hinzufügen|Auswählen|Select|Done|Fertig)\s*\(?2\)?)",
            labels(node),
            re.IGNORECASE,
        )
        for node in current
        if system_picker(node)
    )
    checked = sum(node.get("checked") == "true" for node in current if system_picker(node))
    if not count_visible and checked != 2:
        raise QaError("The system picker did not confirm exactly two selected photos; no result was submitted.")
    screenshot("android-photo-import-picker.png")
    confirm = find_system_label(r"^(?:Add|Hinzufügen|Auswählen|Select|Done|Fertig)(?:\b|\s|\()")
    if not confirm:
        raise QaError("Expected the system picker's Add(2)/Done confirmation. Selection remains open for inspection.")
    tap_node(confirm)


def verify_uploads(parent, probe):
    overview = check(parent.get("/children/" + probe["child_id"] + "/overview"))
    materials = overview["materials"]
    if len(materials) != 2 or overview["units"]:
        raise QaError(
            "Expected exactly two normally uploaded materials and no learning units for this photo-test child."
        )
    if any(
        item.get("synthetic") is not False
        or item.get("fixture_id") is not None
        or item.get("status") != "uploaded"
        or item.get("confirmed")
        for item in materials
    ):
        raise QaError("The photo test must stop after normal uploads, before OCR or confirmation.")
    day_ids = {item.get("school_day_id") for item in materials}
    if len(day_ids) != 1 or None in day_ids:
        raise QaError("Both native photos must belong to the same persisted school day.")
    day_id = next(iter(day_ids))
    day = check(parent.get("/school-days/" + day_id))
    if day["child_id"] != probe["child_id"] or day["stage"] != "collecting" or day.get("active_job"):
        raise QaError("The photo-test day must remain collecting without any active AI job.")
    image_hashes = []
    for material in materials:
        response = parent.get("/materials/" + material["id"] + "/image")
        if response.status_code != 200:
            raise QaError("The entitled parent could not reopen a native private upload.")
        with Image.open(io.BytesIO(response.content)) as image:
            if image.format != "JPEG" or image.getexif():
                raise QaError("A persisted native image still contains unnecessary metadata.")
        image_hashes.append(hashlib.sha256(response.content).hexdigest())
    if len(set(image_hashes)) != 2:
        raise QaError("The persisted native uploads must show two different artificial pages.")
    return day_id, [item["id"] for item in materials]


def main():
    global PHASE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-version-code", type=int, default=11)
    args = parser.parse_args()
    data = read_private()
    if adb("get-state").strip() != b"device" or adb("shell", "getprop", "ro.build.version.sdk").strip() != b"36":
        raise QaError("Only the dedicated running API36 emulator-5580 is supported.")
    package_info = adb("shell", "dumpsys", "package", PACKAGE).decode(errors="replace")
    version = re.search(r"\bversionCode=(\d+)", package_info)
    if not version or int(version[1]) != args.expected_version_code:
        raise QaError(
            "The expected APK must already be installed through the update test; this driver never installs APKs."
        )
    with httpx.Client(base_url=BASE, headers=HEADERS, timeout=30, follow_redirects=False) as parent:
        release = check(parent.get("/app-release"))
        if release.get("version_code") != args.expected_version_code:
            raise QaError("Public APK and installed test APK differ; finish the updater/deployment test first.")
        PHASE = "prepare-own-child"
        probe = prepare_child(parent, data)
        before = check(parent.get("/children/" + probe["child_id"] + "/overview"))
        if before["materials"] or before["units"]:
            raise QaError(
                "This photo-test child already has data. Inspect/clean only that known child before rerunning; no duplicate uploads were made."
            )
        usage_before = check(parent.get("/families/" + probe["family_id"] + "/usage"))
        if any(record["child_id"] == probe["child_id"] for record in usage_before["records"]):
            raise QaError("The dedicated photo-test child already has AI usage; a fresh child is required.")
        PHASE = "index-fixtures"
        index_artificial_photos()
        PHASE = "native-login"
        adb("shell", "pm", "clear", PACKAGE)
        adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
        wait("Anmelden")
        if not any(node.get("class") == "android.widget.EditText" for node in nodes()):
            press("Anmelden")
        login(probe["username"], probe["password"])
        press("Heftfotos")
        PHASE = "system-picker"
        press("Fotos auswählen", scroll=True)
        choose_two_in_system_picker()
        PHASE = "native-crop"
        for index in range(1, 3):
            wait("Zuschnitt übernehmen", seconds=35)
            screenshot(f"android-photo-import-crop-{index}.png")
            press("Zuschnitt übernehmen")
            probe["ui_crops_confirmed"] = index
            save_probe(probe)
            time.sleep(1)
        PHASE = "verify-persisted-photos"
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            overview = check(parent.get("/children/" + probe["child_id"] + "/overview"))
            if len(overview["materials"]) == 2:
                break
            time.sleep(1)
        else:
            raise QaError("The two native crop results were not both persisted. Do not press Weiter or start OCR.")
        day_id, material_ids = verify_uploads(parent, probe)
        usage_after = check(parent.get("/families/" + probe["family_id"] + "/usage"))
        if usage_after["calls_used"] != usage_before["calls_used"] or any(
            record["child_id"] == probe["child_id"] for record in usage_after["records"]
        ):
            raise QaError(
                "Family AI usage changed during the photo-only test. Do not report zero; inspect concurrent QA activity."
            )
        screenshot("android-photo-import-uploaded.png")
        probe.update(
            {
                "school_day_id": day_id,
                "material_ids": material_ids,
                "version_code": args.expected_version_code,
                "verified_photo_only": True,
                "new_ai_calls": 0,
            }
        )
        save_probe(probe)
    print(
        json.dumps(
            {
                "native_android_photo_import": True,
                "android_api": 36,
                "version_code": args.expected_version_code,
                "regular_separate_child": True,
                "actual_system_picker_images": 2,
                "native_crop_confirmations": 2,
                "persisted_private_materials": 2,
                "unnecessary_image_metadata_removed": True,
                "new_ai_calls": 0,
                "ocr_started": False,
                "screenshot": "artifacts/android-photo-import-uploaded.png",
            }
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never print subprocess commands (ADB can contain the synthetic login),
        # HTTP bodies, private account data, answers, tokens or a traceback.
        if PHASE in {"system-picker", "native-crop", "verify-persisted-photos"}:
            try:
                screenshot("android-photo-import-debug.png")
            except Exception:
                pass
        message = (
            str(error)
            if isinstance(error, QaError)
            else "Native photo QA stopped; sensitive exception details suppressed."
        )
        print(json.dumps({"native_android_photo_import": False, "phase": PHASE, "error": message}), file=sys.stderr)
        raise SystemExit(1) from None
