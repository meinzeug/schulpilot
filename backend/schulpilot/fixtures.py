"""Server-owned synthetic fixtures. No caller supplied text reaches a provider.

This is a separate live AI test path, not consent to process real children's
data. The image is generated from constants and never contains account data.
"""

import io

from PIL import Image, ImageDraw, ImageFont

FIXTURE_ID = "fractions-v1"
CONTENT = (
    "Ein Bruch beschreibt Teile eines Ganzen. Der Nenner steht unter dem Bruchstrich "
    "und gibt an, in wie viele gleich große Teile das Ganze geteilt wird. "
    "Der Zähler steht über dem Bruchstrich und zählt die ausgewählten Teile. "
    "Bei gleichem Nenner werden die Zähler addiert: 1/4 + 2/4 = 3/4."
)


def worksheet():
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


def trusted_payload(function):
    return {
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
