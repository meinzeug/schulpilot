"""Finite, source-bound scientific models, never arbitrary drawing coordinates."""

import math
import re

KINDS = (
    "function_graph",
    "data_plot",
    "cell",
    "molecule",
    "logic_table",
    "circuit_network",
    "technical_drawing",
    "function_curve",
    "process_graph",
    "process_cycle",
)
CELL_LABELS = {
    "animal_cell": ["Zellmembran", "Zellkern", "Cytoplasma"],
    "plant_cell": ["Zellwand", "Zellmembran", "Zellkern", "Cytoplasma", "Vakuole", "Chloroplast"],
}
MOLECULES = {
    "water": ("H-O-H", ["H", "O", "H"]),
    "carbon_dioxide": ("O=C=O", ["O", "C", "O"]),
    "methane": ("H-C(H)(H)-H", ["C", "H", "H", "H", "H"]),
    "ethanol": ("CH3-CH2-OH", ["C", "C", "O", "H", "H", "H", "H", "H", "H"]),
}


def polynomial(text):
    """Only an explicitly written real polynomial of degree at most two."""
    text = text.replace("−", "-").replace("²", "^2").replace("^{2}", "^2").replace(r"\cdot", "*")
    for line in text.splitlines():
        match = re.search(r"(?:f\s*\(\s*x\s*\)|y)\s*=\s*(.+)", line)
        if not match:
            continue
        expression = match[1].strip().removesuffix(r"\)").removesuffix(r"\]").strip().rstrip(".")
        expression = re.sub(r"\s+", "", expression).replace(",", ".")
        if not re.fullmatch(r"[+\-0-9.x^*]+", expression):
            continue
        terms = re.findall(r"[+\-]?[^+\-]+", expression)
        coefficients = [0.0, 0.0, 0.0]
        for term in terms:
            m = re.fullmatch(r"([+\-]?)(?:(\d+(?:\.\d+)?)\*?)?(x(?:\^2)?)?", term)
            if not m or not (m[2] or m[3]):
                break
            value = float(m[2] or 1) * (-1 if m[1] == "-" else 1)
            degree = 2 if m[3] == "x^2" else 1 if m[3] else 0
            coefficients[2 - degree] += value
        else:
            if any(coefficients[:2]) and all(math.isfinite(v) and abs(v) <= 100 for v in coefficients):
                return coefficients
    return None


CURVES = {
    "sine": "sin(x)",
    "cosine": "cos(x)",
    "exponential": "e^x",
    "logarithm": "ln(x)",
    "square_root": "sqrt(x)",
    "reciprocal": "1/x",
    "cubic": "x^3",
    "absolute": "|x|",
}


def standard_curve(text):
    for line in text.splitlines():
        match = re.search(r"(?:f\s*\(\s*x\s*\)|y)\s*=\s*(.+)", line)
        if not match:
            continue
        expression = match[1].strip().removesuffix(r"\)").removesuffix(r"\]").strip().rstrip(".")
        expression = re.sub(r"\s+", "", expression).replace("³", "^3").replace("^{3}", "^3").replace("^{x}", "^x")
        expression = expression.replace(r"\frac{1}{x}", "1/x").replace(r"\sqrt{x}", "sqrt(x)")
        expression = (
            expression.replace(r"\sin", "sin")
            .replace(r"\cos", "cos")
            .replace(r"\ln", "ln")
            .replace(r"\left", "")
            .replace(r"\right", "")
        )
        for variant, canonical in CURVES.items():
            if expression == canonical:
                return variant
    return None


def chemical_notation(text):
    # Formatting-only normalization. A sum formula never becomes a bond graph.
    text = re.sub(r"\\mathrm\{([A-Za-z0-9]+)\}", r"\1", text)
    text = re.sub(r"_\{([0-9]+)\}", r"\1", text)
    text = re.sub(r"_([0-9])", r"\1", text)
    return text.replace("–", "-").replace("−", "-").replace("₃", "3").replace("₂", "2").replace("₄", "4")


def has_literal_arrow(source, start, end, *, ignore_case=False):
    """Match whole source labels, allowing formatting whitespace and ASCII arrows."""
    if ignore_case:
        source, start, end = (value.casefold() for value in (source, start, end))
    normalized = " ".join(source.split()).replace("->", "→")
    left = re.escape(" ".join(start.split()))
    right = re.escape(" ".join(end.split()))
    return bool(re.search(r"(?<!\w)" + left + r"\s*→\s*" + right + r"(?!\w)", normalized))


def validate(block, question, sources):
    kind, n, labels, variant = block.kind, block.numbers, block.labels, block.variant
    if any(e.start == e.end or max(e.start, e.end) >= len(labels) for e in block.connections):
        raise ValueError("Prozesskante ohne gültige verschiedene Knoten.")
    quote = block.source_excerpt
    if (
        (block.connections and kind not in ("process_graph", "process_cycle"))
        or block.marks
        or (kind != "technical_drawing" and block.unit)
    ):
        raise ValueError("Dieses Fachmodell hat keine freien Verbindungen, Markierungen oder Zusatzmaße.")
    if kind == "function_curve":
        if n or labels != ["x", "y"] or standard_curve(quote) != variant:
            raise ValueError("Standardkurve passt nicht zur ausdrücklich notierten Funktion.")
    elif kind in ("process_graph", "process_cycle"):
        if (
            n
            or variant
            or not 2 <= len(labels) <= 8
            or len(set(labels)) != len(labels)
            or any(len(v) > 60 for v in labels)
        ):
            raise ValueError("Prozessmodell braucht zwei bis acht kurze eindeutige Knoten.")
        if not block.connections or any(
            e.relation not in ("next", "branch")
            or not has_literal_arrow(quote, labels[e.start], labels[e.end])
            for e in block.connections
        ):
            raise ValueError("Jede Prozessrichtung muss ausdrücklich im Beleg stehen.")
        edges = {(e.start, e.end) for e in block.connections}
        if kind == "process_cycle":
            if edges != {(i, (i + 1) % len(labels)) for i in range(len(labels))}:
                raise ValueError("Kreislauf braucht die ausdrücklich geschlossene Quellenfolge.")
        else:
            remaining = set(range(len(labels)))
            for _ in labels:
                roots = {i for i in remaining if not any(b == i and a in remaining for a, b in edges)}
                if not roots:
                    break
                remaining -= roots
            connected = {0}
            for _ in labels:
                connected |= {b for a, b in edges if a in connected} | {a for a, b in edges if b in connected}
            if remaining or connected != set(range(len(labels))):
                raise ValueError("Prozessgraph braucht verbundene Knoten ohne verdeckten Kreis.")
    elif kind == "function_graph":
        if variant != "polynomial2" or len(n) != 3 or not any(n[:2]) or any(abs(v) > 100 for v in n):
            raise ValueError("Funktionsgraph braucht drei begrenzte Koeffizienten a,b,c mit a oder b ungleich0.")
        if polynomial(quote) != n or labels != ["x", "y"]:
            raise ValueError("Funktionsgraph passt nicht zum ausdrücklich belegten Polynom.")
    elif kind == "data_plot":
        if variant not in ("scatter", "polyline") or len(n) < 4 or len(n) % 2 or len(labels) != 2:
            raise ValueError("Datenplot braucht zwei Achsentitel und zwei bis acht belegte Zahlenpaare.")
        pairs = re.findall(r"\(\s*(-?\d+(?:[.,]\d+)?)\s*;\s*(-?\d+(?:[.,]\d+)?)\s*\)", quote.replace("−", "-"))
        if not pairs:
            rows = [line.strip().strip("|").split("|") for line in quote.splitlines() if "|" in line]
            if rows and [v.strip() for v in rows[0]] == labels:
                for row in rows[1:]:
                    cells = [v.strip().replace("−", "-") for v in row]
                    if len(cells) == 2 and all(re.fullmatch(r":?-+:?", v) for v in cells):
                        continue
                    if len(cells) != 2 or not all(re.fullmatch(r"-?\d+(?:[.,]\d+)?", v) for v in cells):
                        raise ValueError("Datentabelle enthält keine eindeutigen Zahlenpaare.")
                    pairs.append(cells)
        if [float(v.replace(",", ".")) for pair in pairs for v in pair] != n:
            raise ValueError("Datenpunkte müssen als geordnete Paare (x;y) im Beleg stehen.")
        if variant == "polyline" and any(a >= b for a, b in zip(n[::2], n[2::2])):
            raise ValueError("Verbundene Messpunkte brauchen streng aufsteigende x-Werte.")
    elif kind == "cell":
        name = "Pflanzenzelle" if variant == "plant_cell" else "Tierzelle"
        if variant not in CELL_LABELS or labels != CELL_LABELS[variant] or name.casefold() not in quote.casefold():
            raise ValueError("Zellmodell und feste Beschriftungspositionen passen nicht zum Beleg.")
    elif kind == "molecule":
        normalized = chemical_notation(quote)
        if variant not in MOLECULES or MOLECULES[variant][0] not in normalized or labels != MOLECULES[variant][1]:
            raise ValueError("Bindungsschema braucht seine belegte Strukturformel, nicht nur eine Summenformel.")
    elif kind == "logic_table":
        marker = {"and_gate": "A AND B", "or_gate": "A OR B", "not_gate": "NOT A"}.get(variant)
        expected = ["A", "Y"] if variant == "not_gate" else ["A", "B", "Y"]
        if not marker or marker not in quote or labels != expected or block.disclosure == "given":
            raise ValueError("Abgeleitete Logiktafel nur als geöffnete Hilfe oder Lösung mit belegter Operation.")
    elif kind == "circuit_network":
        marker = {"series": "R1 und R2 in Reihe", "parallel": "R1 und R2 parallel"}.get(variant)
        if not marker or marker not in quote or labels != ["R1", "R2"]:
            raise ValueError("Schaltung braucht die ausdrücklich belegte Verbindung der beiden Widerstände.")
    elif kind == "technical_drawing":
        if (
            variant != "center_hole"
            or len(n) != 3
            or not 0 < n[2] < min(n[:2])
            or block.unit not in ("mm", "cm")
            or labels
        ):
            raise ValueError("Platte braucht positive Breite/Höhe und eine kleinere mittige Bohrung mit Längeneinheit.")
        if "mittige Bohrung" not in quote:
            raise ValueError("Bohrungsposition ist nicht belegt.")
    # A fixed scientific model adds relationships, not just question numbers.
    # Its evidence must belong to confirmed material. New mathematical data may
    # instead be given by an explicitly written exercise (same existing rule).
    if kind not in ("function_graph", "function_curve", "data_plot", "technical_drawing") and not any(
        " ".join(quote.casefold().split()) in " ".join(s.casefold().split()) for s in sources
    ):
        raise ValueError("Fachmodell braucht bestätigten Quellenstoff, keine erfundene Aufgabenbehauptung.")


RULES = r"""
Zusätzliche lokale Fachmodelle nur bei passendem graphic_kind und wörtlichem Beleg:
function_graph: variant polynomial2, numbers=[a,b,c] für ausdrücklich notiertes y=ax²+bx+c oder f(x)=..., |Koeffizient|<=100; labels=[x,y]. Keine freie Funktion und keine Pixelkoordinaten.
data_plot: variant scatter oder polyline, numbers=[x1,y1,x2,y2,...], 2–8 Paare exakt in source_excerpt als (x;y) oder zweispaltige Zahlentabelle mit Achsentiteln in der Kopfzeile; labels sind zwei belegte Achsentitel. Polyline nur bei aufsteigenden x.
cell: plant_cell mit labels [Zellwand,Zellmembran,Zellkern,Cytoplasma,Vakuole,Chloroplast] oder animal_cell mit [Zellmembran,Zellkern,Cytoplasma]; alle Begriffe einschließlich Pflanzenzelle/Tierzelle im bestätigten Stoff. Vereinfachtes Modell.
molecule: water/H-O-H/[H,O,H], carbon_dioxide/O=C=O/[O,C,O], methane/H-C(H)(H)-H/[C,H,H,H,H] oder ethanol/CH3-CH2-OH/[C,C,O,H,H,H,H,H,H]. Strukturformel muss genau im bestätigten Beleg stehen; keine Geometrie aus Summenformeln ableiten.
logic_table: and_gate mit A AND B, or_gate mit A OR B, not_gate mit NOT A im bestätigten Beleg; labels [A,B,Y] oder [A,Y]. Vollständige Tabelle ausschließlich hint/solution.
circuit_network: series bei belegtem 'R1 und R2 in Reihe' oder parallel bei 'R1 und R2 parallel'; labels [R1,R2], keine Zahlen.
technical_drawing: center_hole, numbers=[Breite,Höhe,Bohrungsdurchmesser], unit mm oder cm, labels=[]; Maße und 'mittige Bohrung' müssen belegt sein. Alle anderen neuen Modelle numbers=[], connections=[], unit=''.
"""

RULES += """
function_curve: nur exakt belegte Standardfunktion f(x)=sin(x),cos(x),e^x,ln(x),sqrt(x),1/x,x^3 oder |x|; variant sine,cosine,exponential,logarithm,square_root,reciprocal,cubic,absolute. labels=[x,y], numbers=[]. Keine freie Formelinterpretation.
process_graph: 2–8 eindeutige labels (bis60Zeichen) und gerichtete connections next/branch; jede Kante muss wörtlich als LabelA→LabelB im bestätigten source_excerpt stehen; keine Kreise. process_cycle: ausdrücklich geschlossene Folge in label-Reihenfolge mit letzter→erster Kante. Keine neuen Beziehungen aus bloßen Wortlisten ableiten. variant='', numbers=[], unit=''.
"""


def rules_for(allowed):
    selected = [line for line in RULES.splitlines() if line.split(":", 1)[0] in allowed]
    return (
        (
            "\nLokale Fachmodelle brauchen belegte Daten, keine Pixelkoordinaten. "
            "Ohne ausdrücklich genannte Parameter numbers=[], connections=[], unit=''.\n" + "\n".join(selected)
        )
        if selected
        else ""
    )
