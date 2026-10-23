"""Server-owned synthetic fixtures. No caller supplied text reaches a provider.

This is a separate live AI test path, not consent to process real children's
data. The image is generated from constants and never contains account data.
"""

import io

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from .audit_fixtures import cases
from .audit_fixtures import image as audit_image
from .evaluation_corpus import CASES as ORIGINAL_CASES

SCENE_FIXTURE_ID = "learning-scene-flow-v1"
SCENE_CASE = {
    "subject": "Geographie", "topic": "Wasserkreislauf", "grade": 5,
    "lines": [
        "Wasserkreislauf.",
        "Wasser → Wasserdampf.",
        "Wasserdampf → Wolke.",
        "Wolke → Wasser.",
        "Wasser verdunstet. Wasserdampf kondensiert in der Wolke.",
        "Wasser fällt als Niederschlag zurück.",
        "Wasser = flüssig.",
        "Wasserdampf = gasförmig.",
    ],
}
CASES = ORIGINAL_CASES | cases() | {SCENE_FIXTURE_ID: SCENE_CASE}

FIXTURE_ID = "fractions-v1"
DAY_FIXTURE_IDS = ("fractions-day-1-v1", "fractions-day-2-v1")
PACKAGE_FIXTURE_ID = "fractions-day-package-v1"
LIVE_FIXTURE_IDS = (FIXTURE_ID, *DAY_FIXTURE_IDS, *ORIGINAL_CASES, SCENE_FIXTURE_ID)
AUDIT_FIXTURE_IDS = tuple(cases())
CONTENT = (
    "Ein Bruch beschreibt Teile eines Ganzen. Der Nenner steht unter dem Bruchstrich "
    "und gibt an, in wie viele gleich große Teile das Ganze geteilt wird. "
    "Der Zähler steht über dem Bruchstrich und zählt die ausgewählten Teile. "
    "Bei gleichem Nenner werden die Zähler addiert: 1/4 + 2/4 = 3/4."
)


SECOND_PAGE_CONTENT = (
    "Beim Kürzen teilt man Zähler und Nenner durch dieselbe Zahl. "
    "Beispiel: 2/4 = 1/2. Beim Erweitern multipliziert man Zähler und Nenner "
    "mit derselben Zahl. Beispiel: 1/2 = 3/6. Der Wert des Bruchs bleibt gleich."
)


def worksheet(fixture_id=FIXTURE_ID):
    if fixture_id not in (*LIVE_FIXTURE_IDS, *AUDIT_FIXTURE_IDS):
        raise ValueError("Unknown server-owned fixture")
    if fixture_id in CASES:
        if CASES[fixture_id].get("audit_page"):
            return audit_image(CASES[fixture_id]["audit_page"])
        return evaluation_worksheet(CASES[fixture_id])
    image = Image.new("RGB", (1120, 760), "white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 27)
        title = ImageFont.truetype("DejaVuSans.ttf", 35)
    except OSError:
        font = ImageFont.load_default(size=27)
        title = ImageFont.load_default(size=35)
    draw.text((55, 40), "SYNTHETISCHES TESTBLATT - KEINE KINDERDATEN", fill="#175b51", font=font)
    draw.text((55, 105), "Mathematik: Brüche (Klasse 6)", fill="black", font=title)
    lines = [
        "Ein Bruch beschreibt Teile eines Ganzen.",
        "Nenner: unten; Anzahl der gleich großen Teile.",
        "Zähler: oben; Anzahl der ausgewählten Teile.",
        "Bei gleichem Nenner werden die Zähler addiert:",
        "1/4 + 2/4 = 3/4",
        "Keine Hausaufgaben auf diesem Testblatt notiert.",
    ]
    if fixture_id == DAY_FIXTURE_IDS[1]:
        lines = [
            "Seite 2: Brüche kürzen und erweitern",
            "Kürzen: Zähler und Nenner durch dieselbe Zahl teilen.",
            "2/4 = 1/2",
            "Erweitern: Beide mit derselben Zahl multiplizieren.",
            "1/2 = 3/6. Der Wert des Bruchs bleibt gleich.",
            "Keine Hausaufgaben auf diesem Testblatt notiert.",
        ]
    for i, line in enumerate(lines):
        draw.text((55, 195 + i * 61), line, fill="black", font=font)
    for i in range(4):
        draw.rectangle(
            (55 + 95 * i, 608, 150 + 95 * i, 697), fill="#91c9ba" if i < 3 else "white", outline="black", width=3
        )
    draw.text((480, 635), "Drei von vier Teilen = 3/4", fill="black", font=font)
    output = io.BytesIO()
    image.save(output, "JPEG", quality=90)
    return output.getvalue()


def evaluation_worksheet(case):
    image = Image.new("RGB", (1120, 760), "white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("DejaVuSans-Oblique.ttf" if case.get("slanted") else "DejaVuSans.ttf", 25)
    except OSError:
        font = ImageFont.load_default(size=25)
    draw.text((35, 30), "SYNTHETISCHER QUALITÄTSTEST · KEINE KINDERDATEN", font=font, fill="#175b51")
    if not case.get("unreadable"):
        draw.text((35, 100), f"{case['subject']} · {case['topic']} · Klasse {case['grade']}", font=font, fill="black")
    for i, line in enumerate(case["lines"]):
        draw.text((35, 180 + i * 60), line, font=font, fill="black")
    if case.get("unreadable"):
        for i in range(6):
            draw.rectangle((35, 180 + i * 60, 950, 220 + i * 60), fill="#999999")
    if case.get("blur"):
        image = image.filter(ImageFilter.GaussianBlur(case["blur"]))
    output = io.BytesIO()
    image.save(output, "JPEG", quality=85)
    return output.getvalue()


def trusted_payload(function, fixture_id=FIXTURE_ID):
    if fixture_id not in (*LIVE_FIXTURE_IDS, *AUDIT_FIXTURE_IDS, PACKAGE_FIXTURE_ID):
        raise ValueError("Unknown server-owned fixture")
    result = {
        "function": function,
        "synthetic_fixture": FIXTURE_ID,
        "grade": 6,
        "material": None if function == "extract" else {"subject": "Mathematik", "topic": "Brüche", "content": CONTENT},
        "goal": None,
        "preferences": {"session_minutes": 10},
        "feedback": [],
        "recent_units": [],
        "recent_outcomes": [],
        "review": False,
    }
    if fixture_id in CASES:
        case = CASES[fixture_id]
        result["synthetic_fixture"] = fixture_id
        result["grade"] = case["grade"]
        result["material"] = None if function == "extract" else {
            "subject": case["subject"], "topic": case["topic"], "content": "\n".join(case["lines"]),
        }
        if fixture_id == SCENE_FIXTURE_ID and function == "unit":
            result["required_subject"] = case["subject"]
            result["required_topic"] = case["topic"]
            result["scene_request"] = {"kind": "scene", "disclosure": "hint1", "steps": 3, "matching_pairs": 2}
        return result
    if fixture_id in DAY_FIXTURE_IDS:
        result["material"] = (
            None
            if function == "extract"
            else {"subject": "Mathematik", "topic": "Brüche", "content": CONTENT + " " + SECOND_PAGE_CONTENT}
        )
    if function == "package":
        result["material"] = None
        result["materials"] = [
            {"page_number": 1, "group_id": "g1", "subject": "Mathematik", "topic": "Brüche", "content": CONTENT},
            {
                "page_number": 2,
                "group_id": "g1",
                "subject": "Mathematik",
                "topic": "Brüche kürzen und erweitern",
                "content": SECOND_PAGE_CONTENT,
            },
        ]
        result["selected_groups"] = [{"id": "g1", "subject": "Mathematik", "estimated_minutes": 8}]
    return result
