"""Original synthetic A1 grade-grid PDF, shared by integration and device QA."""

import io

from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject


def pdf(year, entries=None, *, corrupt_header=False, encrypted=False, bad_subject=False):
    entries = (
        entries
        if entries is not None
        else [
            ("Mathematik", 1, "other", 1, "4"),
            ("Mathematik", 1, "other", 2, "3"),
            ("Englisch", 1, "classwork", 1, "2"),
        ]
    )
    writer = PdfWriter()
    page = writer.add_blank_page(width=2384, height=1684)
    page[NameObject("/Resources")] = DictionaryObject(
        {
            NameObject("/Font"): DictionaryObject(
                {
                    NameObject("/F1"): DictionaryObject(
                        {
                            NameObject("/Type"): NameObject("/Font"),
                            NameObject("/Subtype"): NameObject("/Type1"),
                            NameObject("/BaseFont"): NameObject("/Helvetica"),
                            NameObject("/Encoding"): NameObject("/WinAnsiEncoding"),
                        }
                    )
                }
            )
        }
    )
    commands = []

    def text(value, x, y):
        encoded = value.encode("cp1252").hex()
        commands.append(f"BT /F1 14 Tf 1 0 0 1 {x} {y} Tm <{encoded}> Tj ET")

    text("Fuxnoten Notenübersicht", 50, 1500)
    text("Unterrichtseinheit", 50, 1430)
    columns = {}
    x = 300
    for half in (1, 2):
        text(f"{half}. Halbjahr", x, 1455)
        for kind, count, label in (("classwork", 2, "Klassenarbeiten"), ("other", 15, "sonstige Leistungen")):
            text(label, x, 1430)
            for slot in range(1, count + 1):
                text(str(slot) if not (corrupt_header and half == 2 and slot == 15) else "16", x, 1400)
                columns[(half, kind, slot)] = x
                x += 40
            text("Ø", x, 1400)
            # Deliberately plausible grade averages must never become evidence.
            for row in range(2):
                text("3,5", x, 1370 - row * 30)
            x += 40
        text("Ø1", x, 1400)
        x += 40
    subjects = list(dict.fromkeys(r[0] for r in entries))
    for index, subject in enumerate(subjects):
        text(subject if not bad_subject else "Unlesbar\ngeteilt", 50, 1370 - index * 30)
    for subject, half, kind, slot, value in entries:
        text(value, columns[half, kind, slot], 1370 - subjects.index(subject) * 30)
    text(f"Schuljahr: {year} / 1. HJ", 1000, 40)
    stream = DecodedStreamObject()
    stream.set_data("\n".join(commands).encode())
    page[NameObject("/Contents")] = writer._add_object(stream)
    if encrypted:
        writer.encrypt("SYNTHETIC-ONLY")
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()
