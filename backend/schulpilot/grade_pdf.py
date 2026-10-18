"""Local Fuxnoten grid reader. No OCR, network, PDF execution or personal headers."""

import io
import re
from decimal import Decimal

from pypdf import PdfReader


class GradePDFError(ValueError):
    """Only our fixed messages may leave the isolated reader."""


def extract(raw):
    reader = PdfReader(io.BytesIO(raw), strict=True)
    if reader.is_encrypted or not 1 <= len(reader.pages) <= 6:
        raise GradePDFError("Bitte eine unverschlüsselte Fuxnoten-Notenübersicht verwenden.")
    result, years = [], set()
    for page in reader.pages:
        fragments = []

        def visit(text, cm, tm, font, size):
            text = text.strip()
            if text:
                fragments.append((text, tm[4] * cm[0] + tm[5] * cm[2] + cm[4], tm[4] * cm[1] + tm[5] * cm[3] + cm[5]))

        text = page.extract_text(visitor_text=visit)
        if len(text) > 180000 or "Schuljahr:" not in text or "Klassenarbeiten" not in text:
            raise GradePDFError("Diese PDF enthält keine unterstützte Fuxnoten-Tabelle.")
        for match in re.finditer(r"Schuljahr:\s*(20\d{2})(?:\s*/\s*((?:20)?\d{2}))?", text):
            start, end = int(match[1]), match[2]
            if end and int(end) not in (start + 1, (start + 1) % 100):
                raise GradePDFError("Das Schuljahr ist nicht eindeutig.")
            years.add(start)
        candidates = [f for f in fragments if f[0] == "15"]
        if not candidates:
            raise GradePDFError("Die Notenspalten wurden nicht sicher erkannt.")
        header_y = max(f[2] for f in candidates)
        header = sorted((f for f in fragments if abs(f[2] - header_y) < 2), key=lambda f: f[1])
        numeric = [f for f in header if re.fullmatch(r"[1-9]|1[0-5]", f[0])]
        expected = [str(n) for _ in range(2) for group in (range(1, 3), range(1, 16)) for n in group]
        if [f[0] for f in numeric] != expected:
            raise GradePDFError("Die Spaltenanordnung ist unbekannt. Es wurden keine Noten übernommen.")
        step = min(b[1] - a[1] for a, b in zip(numeric, numeric[1:]))
        tolerance = step * 0.30
        rows = sorted(
            (
                f
                for f in fragments
                if f[2] < header_y - 5 and f[1] < numeric[0][1] - step and f[0] and not f[0][0].isdigit()
            ),
            key=lambda f: -f[2],
        )
        # Footer/header/controls are never subjects. A subject row must be inside
        # the grid and precede the first footer label.
        footer = max((f[2] for f in fragments if "Schuljahr:" in f[0]), default=-1)
        rows = [
            f for f in rows if f[2] > footer + 20 and re.fullmatch(r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß .()/-]{0,79}", f[0])
        ]
        if not rows:
            raise GradePDFError("Keine Fächer erkannt.")
        for value, x, y in fragments:
            if not footer + 20 < y < header_y - 5:
                continue
            if min(abs(f[1] - x) for f in numeric) <= tolerance and not any(abs(f[2] - y) <= 3 for f in rows):
                raise GradePDFError("Eine Notenzeile konnte keinem Fach zugeordnet werden. Bitte die PDF prüfen.")
        for subject, _, y in rows:
            used = set()
            for value, x, cy in fragments:
                if abs(cy - y) > 3:
                    continue
                nearest = min(range(len(numeric)), key=lambda i: abs(numeric[i][1] - x))
                if abs(numeric[nearest][1] - x) > tolerance:
                    continue  # Averages have their own nonnumeric columns.
                if (
                    not re.fullmatch(r"[1-6](?:[,.][0-9]{1,2})?", value)
                    or not 1 <= Decimal(value.replace(",", ".")) <= 6
                ):
                    raise GradePDFError("Ein Notenfeld ist nicht eindeutig. Bitte die Tabelle prüfen.")
                if nearest in used:
                    raise GradePDFError("Mehrere Werte in einem Notenfeld.")
                used.add(nearest)
                half, pos = divmod(nearest, 17)
                result.append(
                    {
                        "subject": subject,
                        "semester": half + 1,
                        "kind": "classwork" if pos < 2 else "other",
                        "slot": pos + 1 if pos < 2 else pos - 1,
                        "value": format(Decimal(value.replace(",", ".")).normalize(), "f"),
                    }
                )
    if len(years) != 1 or len(result) > 1200:
        raise GradePDFError("Schuljahr oder Umfang sind nicht eindeutig.")
    return {"school_year_start": years.pop(), "entries": result}


def isolated_extract(raw):
    """Bound untrusted PDF decompression in a secret-free child process."""
    import json
    import os
    import subprocess
    import sys
    from pathlib import Path

    if not raw.startswith(b"%PDF-") or not 0 < len(raw) <= 6 * 1024 * 1024:
        raise ValueError("Bitte eine PDF bis 6 MB auswählen.")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "schulpilot.grade_pdf"],
            input=raw,
            capture_output=True,
            timeout=12,
            check=False,
            env={"PATH": os.defpath, "PYTHONPATH": str(Path(__file__).resolve().parents[1])},
        )
        if result.returncode or len(result.stdout) > 1024 * 1024:
            raise ValueError("PDF nicht lesbar.")
        data = json.loads(result.stdout)
        if "error" in data:
            raise ValueError(data["error"])
        return data
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        raise ValueError(
            "Die PDF konnte nicht sicher gelesen werden. Bitte erneut als Fuxnoten-PDF exportieren."
        ) from None


if __name__ == "__main__":
    import json
    import logging
    import resource
    import sys

    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024, 512 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CPU, (8, 8))
    logging.disable(logging.CRITICAL)
    try:
        parsed = extract(sys.stdin.buffer.read(6 * 1024 * 1024 + 1))
        sys.stdout.write(json.dumps(parsed, ensure_ascii=False))
    except GradePDFError as error:
        sys.stdout.write(json.dumps({"error": str(error)}))
    except Exception:
        sys.stdout.write(json.dumps({"error": "Diese PDF lässt sich nicht als Fuxnoten-Übersicht lesen."}))
