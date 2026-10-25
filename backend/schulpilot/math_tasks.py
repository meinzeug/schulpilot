"""Plan bounded source-backed number exercises before calling an AI provider.

These are deterministic exercise specifications, never replacement AI output.
The provider must still supply validated teaching explanations and hints.
"""

import hashlib
import math
import re
from fractions import Fraction

MAX_CANDIDATES = 256
COMPONENT_LABEL = "Zähler und Nenner benennen"
PHASE_TEXT = {
    "understand": "Neues Übungsbeispiel zum Verstehen",
    "detective": "Neues Übungsbeispiel zum Fehlerkorrigieren",
    "apply": "Neues Übungsbeispiel zum Anwenden",
    "recall": "Neues Übungsbeispiel zum Erinnern",
}


def _excerpt(content, match):
    start = max(content.rfind("\n", 0, match.start()) + 1, content.rfind(".", 0, match.start()) + 1)
    return content[max(start, match.start() - 100) : max(start, match.start() - 100) + 350].strip()


def unlike_quote(sources):
    """A taught unlike-denominator procedure, never a mere topic mention."""
    for source in sources:
        for match in re.finditer(r"[^.!?\n]+(?:[.!?\n]+|$)", source["content"]):
            clause = match.group().strip()
            if (len(clause) <= 350 and re.search(r"addier|addition", clause, re.I)
                    and re.search(r"ungleichnam", clause, re.I)
                    and re.search(r"gemeinsam\w*\s+nenner", clause, re.I)
                    and re.search(r"erweiter|gleichnamig\s+mach", clause, re.I)
                    and not re.search(r"\b(?:nicht|später|falsch|niemals)\b|erst\s+nächste", clause, re.I)):
                return clause
    return None


def _procedure_quote(sources, label):
    """Require a general rule in one clause, not nearby vocabulary/examples."""
    operation = {
        "Brüche addieren": r"\baddier(?:en|t|e|st)\b|\baddition\b",
        "Brüche kürzen": r"\bkürz(?:en|t|e|ung)\b",
        "Brüche erweitern": r"\berweiter(?:n|t|e|st|ung)\b",
    }[label]
    for material in sources:
        content = material["content"]
        if not re.search(operation, content, re.I):
            continue
        # A general sentence elsewhere must not override an explicit lesson
        # restriction. Fixed-factor/intermediate-only sources stay unsupported.
        restricted = (
            r"\b(?:nur|ausschließlich|lediglich)\b[^.!?\n]{0,90}"
            r"(?:\d|\b(?:faktor|teiler|eins|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|elf|zwölf)\b)"
            r"|\b(?:vollständig\s+noch\s+nicht|noch\s+nicht\s+vollständig)\b"
            r"|\bandere\s+(?:faktoren|teiler)\b[^.!?\n]{0,60}\bnicht\b"
            r"|\berst\s+(?:nächste\w*|später|kommende\w*)\b"
        )
        if re.search(restricted, content, re.I):
            return None
    if label == "Brüche erweitern":
        # A short workbook imperative states the same general operation as
        # multiplying both parts. Preserve its literal OCR line breaks. This
        # does not authorize addition or a rule that merely mentions expansion.
        for material in sources:
            match = re.search(
                r"\bErweitere\s+Zähler\s+und\s+Nenner\s+mit\s+(?:derselben|der\s+gleichen)\s+(?:ganzen\s+)?Zahl\b(?:[.!]|(?=\s*(?:\n\s*\n|$)))",
                material["content"], re.I,
            )
            if match and len(match[0]) <= 350:
                start = max(0, material["content"].rfind(".", 0, match.start()) + 1,
                            material["content"].rfind("!", 0, match.start()) + 1,
                            material["content"].rfind("?", 0, match.start()) + 1)
                prefix = material["content"][start:match.start()]
                if not re.search(r"\b(?:nicht|niemals|keinesfalls|falsch\w*|morgen|später)\b", prefix, re.I):
                    return match[0]
    for material in sources:
        for match in re.finditer(r"[^.!?;\r\n]+(?:[.!?;\r\n]+|$)", material["content"]):
            quote = match.group().strip()
            lower = quote.casefold()
            if (
                len(quote) > 350
                or not re.search(operation, lower)
                or re.search(r"\b(?:nicht|niemals|keinesfalls)\b", lower)
            ):
                continue
            if label == "Brüche addieren":
                same = re.search(r"\bgleich(?:em|en|e|er)?\s+nenner(?:n)?\b", lower)
                numerator_addition = re.search(
                    r"\bzähler\s+(?:(?:werden|wird|zusammen|miteinander)\s+){0,3}addier(?:en|t|e|st)\b"
                    r"|\baddier(?:en|t|e|st)\s+(?:(?:du|man|wir|die|nur|beide|alle)\s+){0,5}zähler\b",
                    lower,
                )
                if same and numerator_addition:
                    return quote
                continue
            both = ("zähler" in lower and "nenner" in lower) or bool(re.search(r"\bbeide\b", lower))
            if not both:
                continue
            if label == "Brüche kürzen":
                verb = re.search(
                    r"\b(?:teilen|teilt|teile|teilst|geteilt|dividieren|dividiert|dividiere|dividierst)\b", lower
                )
                general = re.search(
                    r"\bdurch\s+(?:(?:dieselbe|die\s+gleiche|eine\s+gemeinsame)\s+(?:ganze\s+)?zahl"
                    r"|(?:denselben|den\s+gleichen)\s+teiler)\b",
                    lower,
                )
            else:
                verb = re.search(r"\b(?:multiplizieren|multipliziert|multipliziere|multiplizierst)\b", lower)
                general = re.search(
                    r"\bmit\s+(?:(?:derselben|der\s+gleichen|einer\s+gemeinsamen)\s+(?:ganzen\s+)?zahl"
                    r"|(?:demselben|dem\s+gleichen)\s+faktor)\b",
                    lower,
                )
            if verb and general:
                return quote
    return None


def _catalog(materials, subject, topic):
    from .coaching import source_goals

    sources = [
        material
        for material in materials
        if isinstance(material, dict)
        and material.get("confirmed") is not False
        and isinstance(material.get("content"), str)
        and material["content"].strip()
    ]
    goals = source_goals(sources, subject, topic)
    catalog = {}
    for goal in goals:
        label = goal["label"]
        if label == COMPONENT_LABEL:
            components, positions = {}, {}
            for component, pattern in (
                ("numerator", r"\bzähler\s*(?:zählt|steht|:)"),
                ("denominator", r"\bnenner\s*(?:sagt|gibt|steht|:)"),
            ):
                for source_index, material in enumerate(sources):
                    match = re.search(pattern, material["content"], re.I)
                    if match:
                        components[component] = _excerpt(material["content"], match)
                        positions[component] = source_index, match.start()
                        break
            if components:
                catalog[label] = {
                    component: components[component] for component in sorted(components, key=positions.get)
                }
        elif label in ("Brüche addieren", "Brüche kürzen", "Brüche erweitern"):
            unlike = unlike_quote(sources) if label == "Brüche addieren" else None
            if unlike:
                catalog[label] = {"add_unlike": unlike}
                continue
            quote = _procedure_quote(sources, label)
            if quote:
                operation = {"Brüche addieren": "add", "Brüche kürzen": "reduce", "Brüche erweitern": "expand"}[label]
                catalog[label] = {operation: quote}
    return catalog


def _numbers(operation):
    """Finite small proper fractions; no negatives or mixed-number arithmetic."""
    if operation == "add_unlike":
        yield from ((1, 3, 1, 6), (1, 4, 1, 8), (2, 5, 1, 10), (1, 6, 1, 3), (1, 3, 1, 12), (1, 4, 1, 6))
    elif operation == "add":
        for denominator in range(3, 13):
            for first in range(1, denominator - 1):
                for second in range(first, denominator - first):
                    yield first, denominator, second
    elif operation in ("numerator", "denominator"):
        for denominator in range(2, 13):
            for numerator in range(1, denominator):
                yield numerator, denominator
    else:
        for denominator in range(2, 13):
            for numerator in range(1, denominator):
                if operation == "reduce" and math.gcd(numerator, denominator) != 1:
                    continue
                for factor in range(2, 5):
                    if denominator * factor > 36:
                        continue
                    if operation == "reduce":
                        yield numerator * factor, denominator * factor
                    elif operation == "expand":
                        yield numerator, denominator, factor


def _task(operation, numbers, phase):
    numerator, denominator = numbers[:2]
    prefix = PHASE_TEXT[phase]
    if operation == "add_unlike":
        second, other_denominator = numbers[2:]
        common = math.lcm(denominator, other_denominator)
        prompt = f"Berechne {numerator}/{denominator} + {second}/{other_denominator}. "
        total = numerator * (common // denominator) + second * (common // other_denominator)
        answer = f"{total}/{common}"
        help_text = "Erweitere zuerst auf dieselbe Einteilung und addiere danach die Zähler."
        ending = f" Gib das Ergebnis als Bruch mit dem Nenner {common} an."
    elif operation == "add":
        second = numbers[2]
        prompt = f"Berechne {numerator}/{denominator} + {second}/{denominator}. "
        answer = f"{numerator + second}/{denominator}"
        help_text = {
            "understand": "Überlege zuerst, warum die Einteilung gleich bleibt.",
            "detective": "Die Behauptung 'Die Nenner werden mitaddiert' ist falsch. Korrigiere diesen Fehler.",
            "apply": "So viel Liter Wasser füllst du nacheinander in eine Flasche. Wie viel ist es zusammen?",
            "recall": "Rechne ohne vorgerechnetes Beispiel.",
        }[phase]
        # Same-denominator addition must not silently require a reduction
        # procedure that may be absent from the confirmed material.
        ending = f" Gib das Ergebnis als Bruch mit dem Nenner {denominator} an."
    elif operation == "reduce":
        result = Fraction(numerator, denominator)
        prompt = f"Kürze den Bruch {numerator}/{denominator} vollständig. "
        answer = f"{result.numerator}/{result.denominator}"
        help_text = {
            "understand": "Überlege, welche gemeinsame Zahl beide Zahlen teilt.",
            "detective": "Nur die obere Zahl zu teilen ist falsch. Korrigiere diesen Fehler.",
            "apply": "Eine Mengenangabe auf einem Messbecher soll mit kleineren Zahlen beschrieben werden.",
            "recall": "Finde selbst den größten gemeinsamen Teiler.",
        }[phase]
        ending = " Gib den fertigen Bruch an."
    elif operation == "expand":
        factor = numbers[2]
        prompt = f"Erweitere den Bruch {numerator}/{denominator} mit dem Faktor {factor}. "
        answer = f"{numerator * factor}/{denominator * factor}"
        help_text = {
            "understand": "Überlege, warum beide Zahlen mit derselben Zahl multipliziert werden.",
            "detective": "Nur die untere Zahl zu multiplizieren ist falsch. Korrigiere diesen Fehler.",
            "apply": "Du unterteilst die Stücke auf einer Bruchkarte feiner. Die Menge bleibt gleich.",
            "recall": "Wende die angegebene Zahl auf beide Zahlen des Bruchs an.",
        }[phase]
        ending = " Gib den fertigen Bruch an."
    else:
        component = "Zähler" if operation == "numerator" else "Nenner"
        answer = str(numerator if operation == "numerator" else denominator)
        prompt = f"Wie lautet der {component} des Bruchs {numerator}/{denominator}? "
        position = "unter" if operation == "numerator" else "über"
        help_text = {
            "understand": "Achte auf die Position der gesuchten Zahl.",
            "detective": f"Die Behauptung 'Der {component} steht {position} dem Bruchstrich' ist falsch. Korrigiere sie.",
            "apply": "Du liest diese Bruchangabe auf einer Mengenkarte. Nenne die gesuchte Zahl.",
            "recall": "Nenne die gesuchte Zahl ohne Erklärung zu ihrer Position.",
        }[phase]
        ending = ""
    return prompt + prefix + ": " + help_text + ending, answer


def fraction_tasks(materials, subject, topic, previous_prompts, phase, count, seed, *, required_labels=None, excluded_prompts=(), expansion_denominator_limit=None):
    """Return exact source-backed task specifications, or [] for unknown skills.

    Callers supply already authorized, confirmed source snapshots. Explicitly
    unconfirmed snapshots are ignored. All requested labels must be supported.
    """
    from .coaching import fraction_task_goal, fraction_task_signature, normalized_prompt
    from .providers import ProviderError

    if type(count) is not int or not 1 <= count <= 5 or phase not in PHASE_TEXT:
        raise ProviderError("Die Vorgaben für die mathematische Lernetappe sind ungültig.")
    if expansion_denominator_limit is not None and (
            type(expansion_denominator_limit) is not int or not 1 <= expansion_denominator_limit <= 24):
        raise ProviderError("Die Vorgaben für die mathematische Lernetappe sind ungültig.")
    catalog = _catalog(materials, subject, topic)
    if not catalog:
        return []
    if required_labels is not None:
        if len(required_labels) != count:
            raise ProviderError("Die Lernzielvorgaben passen nicht zum geplanten Aufgabenumfang.")
        if any(label not in catalog for label in required_labels):
            return []
        labels = list(required_labels)
    else:
        goals = [{"id": f"g{index + 1}", "label": label} for index, label in enumerate(catalog)]
        labels_by_id = {goal["id"]: goal["label"] for goal in goals}
        counts = dict.fromkeys(catalog, 0)
        for prompt in previous_prompts:
            label = labels_by_id.get(fraction_task_goal(prompt, goals))
            if label:
                counts[label] += 1
        labels = []
        for _ in range(count):
            # dict order preserves source order when practice counts tie.
            label = min(counts, key=counts.get)
            labels.append(label)
            counts[label] += 1
    # Exclusions prevent a known example without pretending it was practiced;
    # goal balancing above still uses only the supplied practice history.
    forbidden = [*previous_prompts, *excluded_prompts]
    used_prompts = {normalized_prompt(prompt) for prompt in forbidden}
    used_signatures = {fraction_task_signature(prompt) for prompt in forbidden} - {None}
    component_counts = {"numerator": 0, "denominator": 0}
    for prompt in previous_prompts:
        signature = fraction_task_signature(prompt)
        if signature and signature[0] == "component":
            component = {"zähler": "numerator", "nenner": "denominator"}.get(signature[1])
            if component:
                component_counts[component] += 1
    tasks = []
    for index, label in enumerate(labels):
        available = list(catalog[label])
        operation = min(available, key=lambda kind: component_counts.get(kind, 0))
        if operation in component_counts:
            component_counts[operation] += 1
        candidates = [numbers for numbers in _numbers(operation)
            if operation != "expand" or expansion_denominator_limit is None
            or numbers[1] * numbers[2] <= expansion_denominator_limit][:MAX_CANDIDATES]
        candidates.sort(key=lambda numbers: hashlib.sha256(f"{seed}|{phase}|{operation}|{numbers}".encode()).digest())
        for numbers in candidates:
            prompt, answer = _task(operation, numbers, phase)
            signature = fraction_task_signature(prompt)
            normalized = normalized_prompt(prompt)
            if signature is None or signature in used_signatures or normalized in used_prompts:
                continue
            tasks.append(
                {
                    "id": f"q{index + 1}",
                    "type": "short",
                    "prompt": prompt,
                    "answer": answer,
                    "options": [],
                    "accepted": [],
                    "source_excerpt": catalog[label][operation],
                }
            )
            used_prompts.add(normalized)
            used_signatures.add(signature)
            break
        else:
            raise ProviderError("Für diese Bruchverfahren sind keine neuen kleinen Zahlenaufgaben mehr verfügbar.")
    return tasks
