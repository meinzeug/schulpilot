"""Inspected artificial audit pages. Only immutable hashes enter paid probes."""

import hashlib
import io
from zipfile import ZipFile

from PIL import Image, ImageFilter

from .config import settings

# Canonical reference text was read from the images, not inferred from OCR.
PAGES = {
    "MAT01": ("Mathematik", "Brüche addieren", "cc44de744bdf873bfb8fc9f1c3aa2efa0e80db0ac3a1dc02dea01a7652701ae8",
        ["Zähler oben, Nenner unten.", "Gleiche Nenner: Zähler addieren, Nenner beibehalten.", "1/5 + 2/5 = 3/5.", "Verschiedene Nenner: erst auf einen gemeinsamen Nenner erweitern.", "1/2 + 1/4 = 2/4 + 1/4 = 3/4."]),
    "MAT02": ("Mathematik", "Fläche eines Dreiecks", "2ee53f316d727b1186fbf360ec01064044f0ae57ccf55807b71254bcbda44338",
        ["g ist die Grundseite.", "h ist die senkrechte Höhe.", "A = g · h / 2.", "Beispiel: g = 4 cm, h = 3 cm, A = 6 cm²."]),
    "BIO01": ("Biologie", "Aufbau einer Blütenpflanze", "b9aa3b44f95d8a308d1853f3cd5c4561f5aa256d060dc33302064c695d5de978",
        ["Die Wurzel nimmt Wasser und Mineralstoffe auf.", "Der Stängel trägt die Pflanze und leitet Wasser.", "Die Blätter stellen mit Licht Nährstoffe her.", "Die Blüte dient der Fortpflanzung."]),
    "BIO02": ("Biologie", "Eine einfache Nahrungskette", "4e75381a1bf685f881116b6956c71f2cd528a1964180fee6f7a737722fedc00f",
        ["Gras → Kaninchen → Fuchs.", "Der Pfeil zeigt vom Futter zum Fresser.", "Das Kaninchen frisst Gras.", "Der Fuchs frisst das Kaninchen.", "Pflanzen sind Erzeuger, Tiere sind Verbraucher."]),
    "DEU01": ("Deutsch", "Subjekt und Prädikat", "97dd24bc304e3291ec569014d5059fe5fe50b9116687b669d4e3145d2cca9b85",
        ["Das Subjekt sagt, wer oder was etwas tut.", "Die Frage lautet: Wer oder was?", "Das Prädikat sagt, was geschieht. Es enthält das Verb.", "Der Hund bellt. Der Hund = Subjekt, bellt = Prädikat.", "Die Kinder spielen. Die Kinder = Subjekt, spielen = Prädikat."]),
    "DEU02": ("Deutsch", "Wörtliche Rede", "ce2b8636b9b6e4c6ebf7f581091ee479b8b83eb6e902aca4b60c60a3f297cbbc",
        ["Gesprochene Wörter stehen in Anführungszeichen.", "Ein vorangestellter Begleitsatz endet mit einem Doppelpunkt.", "Mia sagt: „Ich komme gleich.“", "Ben fragt: „Wo ist mein Buch?“"]),
    "ENG01": ("Englisch", "Simple Past: irregular verbs", "8b1d2331cf9be25b0c08cfb6d98708278a5275daebd294ac150a125de0ceeebb",
        ["Simple Past: abgeschlossene Vergangenheit.", "go → went", "see → saw", "buy → bought", "Beispiele: Yesterday I went to the park. She saw a dog. We bought a book.", "Zeitstrahl: yesterday: past actions (went, saw, bought); now."]),
    "ENG02": ("Englisch", "Present Progressive", "79d02b4715a1a2e36770a728254b1a629af3380ea1cc8fa0102548be5594199c",
        ["Form: am / is / are + Verb mit -ing.", "Für Handlungen, die gerade stattfinden.", "I am reading now.", "She is playing now.", "They are swimming now.", "swim → swimming: zwei m."]),
    "GEO01": ("Geographie", "Himmelsrichtungen", "28d780cd9dbf471ed498d83322d0aea899f3fd5c5ad2134286e6e3301beaf594",
        ["Norden liegt auf der Kompassrose oben.", "Osten rechts, Süden unten, Westen links.", "Die Sonne geht ungefähr im Osten auf und im Westen unter."]),
    "GEO02": ("Geographie", "Der Wasserkreislauf", "278c284146a9cdc26aecac0c797b3835147ed0b267320392d6cad14073858910",
        ["Sonnenwärme lässt Wasser verdunsten.", "Wasserdampf kondensiert zu kleinen Tröpfchen.", "Es entstehen Wolken.", "Niederschlag fällt zurück zur Erde.", "Wasser sammelt sich und fließt zurück.", "Verdunstung → Kondensation → Niederschlag → Abfluss."]),
}


def cases():
    return {"audit-" + key.lower() + "-v1": {"subject": value[0], "topic": value[1], "grade": 6,
        "lines": value[3], "anchors": [line.split()[0].strip('.,:') for line in value[3][:3]],
        "homework": False, "audit_page": key} for key, value in PAGES.items()}


def prepare(archive):
    folder = settings.data_dir / "synthetic_reference"
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    with ZipFile(archive) as package:
        for key, (_, _, expected, _) in PAGES.items():
            name = next(n for n in package.namelist() if n.startswith("Bilder/" + key + "_") and n.endswith(".png"))
            if package.getinfo(name).file_size > 4_000_000:
                raise ValueError("oversized reference image")
            raw = package.read(name)
            if hashlib.sha256(raw).hexdigest() != expected:
                raise ValueError("reference image hash mismatch")
            target = folder / (key + ".png")
            target.write_bytes(raw)
            target.chmod(0o600)


def image(page):
    raw = (settings.data_dir / "synthetic_reference" / (page + ".png")).read_bytes()
    if hashlib.sha256(raw).hexdigest() != PAGES[page][2]:
        raise ValueError("reference image hash mismatch")
    with Image.open(io.BytesIO(raw)) as source:
        value = source.convert("RGB")
        value.thumbnail((1120, 1600))
        if page.endswith("02"):
            value = value.filter(ImageFilter.GaussianBlur(.65))
        stream = io.BytesIO()
        value.save(stream, format="JPEG", quality=85)
        return stream.getvalue()
