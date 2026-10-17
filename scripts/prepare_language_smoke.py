"""Own artificial vocabulary page; reuse the normal verified QA household.

No credentials are printed. --cleanup uses the existing scoped account erasure.
This prepares a fixture only; it does not upload or invoke a model.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"


def main():
    if sys.argv[1:] == ["--cleanup"]:
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/prepare_normal_ai_smoke.py"), "--cleanup"], cwd=ROOT
        ).returncode
    if sys.argv[1:]:
        raise SystemExit("Only --cleanup is supported")
    if not PRIVATE.exists():
        subprocess.run([sys.executable, str(ROOT / "scripts/prepare_normal_ai_smoke.py")], cwd=ROOT, check=True)
    data = json.loads(PRIVATE.read_text())
    if (
        not data.get("normal_account")
        or not data.get("verified")
        or not re.search(
            r"\+schulpilot-normal-qa-[a-f0-9]{12}@", data.get("credentials", {}).get("parent_username", "")
        )
    ):
        raise SystemExit("Only the existing script's own verified artificial household is allowed")
    font = ImageFont.truetype("DejaVuSans.ttf", 40)
    heading = ImageFont.truetype("DejaVuSans-Bold.ttf", 48)
    if data.get("language_qa", {}).get("material_id"):
        print(json.dumps({"existing_owned_source_preserved": True}))
        return 0
    image = Image.new("RGB", (1400, 1700), "white")
    draw = ImageDraw.Draw(image)
    draw.text((70, 70), "Englisch · Meine Vokabelseite", font=heading, fill="black")
    for index, pair in enumerate(["apple = Apfel", "school = Schule", "dog = Hund", "book = Buch", "friend = Freund"]):
        draw.text((80, 230 + index * 150), pair, font=font, fill="black")
    for index, line in enumerate(["Simple Present", "he, she, it: -s am Verb", "He goes to school.", "I go to school."]):
        draw.text((80, 1080 + index * 105), line, font=font, fill="black")
    path = ROOT / "artifacts/language-school-page.jpg"
    image.save(path, "JPEG", quality=92)
    path.chmod(0o600)
    data.setdefault("language_qa", {})["image"] = str(path)
    PRIVATE.write_text(json.dumps(data) + "\n")
    PRIVATE.chmod(0o600)
    print(
        json.dumps(
            {
                "own_verified_regular_household": True,
                "artificial_vocabulary_page_ready": True,
                "provider_calls_by_this_preparation": 0,
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
