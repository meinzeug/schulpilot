"""Server-owned synthetic fixtures. No caller supplied text reaches a provider.

This is a separate live AI test path, not consent to process real children's
data. The image is generated from constants and never contains account data.
"""

import io

from PIL import Image, ImageDraw, ImageFont

FIXTURE_ID = "fractions-v1"
DAY_FIXTURE_IDS = ("fractions-day-1-v1", "fractions-day-2-v1")
PACKAGE_FIXTURE_ID = "fractions-day-package-v1"
LIVE_FIXTURE_IDS = (FIXTURE_ID, *DAY_FIXTURE_IDS)
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
    if fixture_id not in LIVE_FIXTURE_IDS:
        raise ValueError("Unknown server-owned fixture")
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


def trusted_payload(function, fixture_id=FIXTURE_ID):
    if fixture_id not in (*LIVE_FIXTURE_IDS, PACKAGE_FIXTURE_ID):
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
