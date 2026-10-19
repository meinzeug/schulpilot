"""Own synthetic documents only, using the regular verified-family helper.

Run once before qa/report_review.mjs. No credentials are printed. Existing
checkpoints must be resumed/explicitly cleaned, never replaced by another family.
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
if PRIVATE.exists():
    raise SystemExit("Resume the existing owned fixture; no replacement performed")
subprocess.run([sys.executable, "scripts/prepare_normal_ai_smoke.py"], cwd=ROOT, check=True)
account = json.loads(PRIVATE.read_text())
font = ImageFont.truetype("DejaVuSans.ttf", 32)
head = ImageFont.truetype("DejaVuSans.ttf", 39)
math = [
    "Mathematik - Brüche addieren",
    "Brüche brauchen zuerst einen gemeinsamen Nenner.",
    "Dann die Zähler addieren. Der Nenner bleibt gleich.",
    "Beispiel: 1/4 + 1/8 = 2/8 + 1/8 = 3/8.",
    "Probeaufgabe:",
    "1/3 + 1/6 = ?",
    "Hausaufgabe: Berechne 2/5 + 1/10.",
]
bio = [
    "Biologie - Tierklassen",
    "Wirbeltiere besitzen eine Wirbelsäule.",
    "Säugetiere: Mensch, Hund.",
    "Vögel: Amsel. Fische: Karpfen.",
    "Amphibien: Frosch. Reptilien: Eidechse.",
    "Wirbellose Tiere haben keine Wirbelsäule.",
    "Beispiel: Regenwurm und Schnecke sind wirbellos.",
]
paths = []
for index, lines in enumerate([math, math, bio], 1):
    image = Image.new("RGB", (1500, 1150), "white")
    draw = ImageDraw.Draw(image)
    draw.text((50, 40), "KÜNSTLICHER APP-TEST - KEINE KINDERDATEN", font=head, fill="#14243D")
    for line_no, line in enumerate(lines):
        draw.text((50, 140 + line_no * 105), line, font=font, fill="black")
    # Two different photo encodings of the same test page exercise text-level
    # duplicate warnings without merely repeating an identical file hash.
    path = ROOT / f"artifacts/report-review-source-{index}.jpg"
    image.save(path, "JPEG", quality=89 + index)
    path.chmod(0o600)
    paths.append(str(path))
account["image_paths"] = paths
PRIVATE.write_text(json.dumps(account) + "\n")
PRIVATE.chmod(0o600)
print('{"owned_artificial_sources":3,"same_text_photo_variants":2,"personal_data":false}')
