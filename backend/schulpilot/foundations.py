"""Small reviewed supplements. No network lookup, course or private source.

These German paraphrases are our own versioned instructional text. They are
never presented as photographed material or as a verbatim NOAA quotation.
"""

import re

VERSION = "foundations-2026-10-19.1"
WHALE = {
    "ref": "k1",
    "id": "whale-mammal-v1",
    "version": VERSION,
    "label": "Ergänzendes Grundwissen · Meeressäugetiere",
    "reference_title": "NOAA Education: Marine mammals",
    "reference_url": "https://www.noaa.gov/education/resource-collections/marine-life/marine-mammals",
    "content": ("Wale sind Säugetiere. Sie atmen Luft mit Lungen und müssen dafür an die Wasseroberfläche kommen. "
                "Waljunge bekommen Milch von ihrer Mutter. Der Lebensraum Wasser allein entscheidet nicht über die Tierklasse. "
                "Atmung und das Säugen der Jungen helfen bei der Einordnung."),
}


def for_question(question, sources):
    biology = any(source.get("subject", "").casefold() in ("biologie", "sachunterricht") for source in sources)
    if biology and re.search(r"\b(?:wal|wale|walen|wals|walfisch|walfische)\b", question, re.I):
        return [dict(WHALE)]
    return []
