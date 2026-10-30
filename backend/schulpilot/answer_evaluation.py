"""Versioned, conservative subject rules. Model opinions are not verdicts.

Content and a requested representation are separate dimensions. Only a
recognised mathematical question or an explicit closed concept is expanded;
unknown prose stays uncertain rather than being accepted by similarity.
"""

import re
import unicodedata
from fractions import Fraction
from math import gcd, lcm

from .checks import expanded_fraction, fraction_instruction, fraction_parts, fraction_result

VERSION = "subject_rules_v7"
FRACTION_COMPONENT_VERSION = "fraction_components_v1"
FRACTION_MEANING_VERSION = "fraction_meaning_v1"
FRACTION_COMPARISON_VERSION = "fraction_comparison_v1"
LCM_VERSION = "lcm_numeric_v1"
CIRCUIT_VERSION = "circuit_interruption_v1"


def fraction_addition_hint(question, answer):
    """Recognize a denominator-sum mistake, without showing the full solution."""
    if question.get("language") or re.search(r"zähler|nenner|faktor|teiler", question["prompt"], re.I):
        return []
    expression = re.search(r"(\d{1,3})\s*/\s*([1-9]\d{0,2})\s*\+\s*(\d{1,3})\s*/\s*([1-9]\d{0,2})", question["prompt"])
    supplied, key = fraction_parts(answer), fraction_parts(question["answer"])
    if not expression or not supplied or not key:
        return []
    a, b, c, d = map(int, expression.groups())
    total = Fraction(a, b) + Fraction(c, d)
    if total != Fraction(*key) or total == Fraction(*supplied) or supplied[1] != b + d:
        return []
    denominator = b * d // gcd(b, d)
    return [
        f"Der Nenner {b + d} entsteht aus {b} + {d}. Beim Addieren zählst du die Nenner nicht zusammen. Teile beide Ganzen zuerst gleich ein.",
        f"Beide Brüche brauchen gleich große Teile. Überlege, wie du beide mit dem Nenner {denominator} schreiben kannst.",
        "Erweitere jeden Bruch: Multipliziere seinen Zähler und Nenner mit derselben Zahl. Danach addierst du nur die Zähler.",
    ]


def normalized(value):
    return " ".join(unicodedata.normalize("NFKC", value).casefold().strip().replace(",", ".").split())


def result(outcome, reason, *, content=None, form=None, method=VERSION):
    return {"version": 2, "outcome": outcome, "reason": reason, "method": method,
            "dimensions": {"content": content or outcome, "form": form or "not_requested"}}


def circuit_interruption(question, answer):
    """Recognize a few exact formulations only for the verified source task."""
    key = question.get("answer")
    raw_prompt = question.get("prompt")
    if (question.get("type") != "short" or question.get("language") or not isinstance(key, str)
            or not isinstance(raw_prompt, str) or not isinstance(answer, str) or normalized(key) != "unterbricht"):
        return None
    prompt = normalized(raw_prompt)
    if not re.fullmatch(r"bei geöffnetem schalter:\s*was bewirkt dieser im stromkreis\?", prompt):
        return None
    from .package_prepared_circuit import REFERENCE, validate
    from .subject_content import Graphic

    verified = False
    for step in question.get("explanation_steps") or []:
        if not isinstance(step, dict) or step.get("reference") != {"id": REFERENCE, "version": 1}:
            continue
        presentation = step.get("presentation")
        if not isinstance(presentation, dict) or not isinstance(presentation.get("blocks"), list):
            continue
        for value in presentation["blocks"]:
            try:
                block = Graphic.model_validate(value)
                if block.kind == "circuit" and block.variant == "open":
                    validate(block, [block.source_excerpt])
                    verified = True
            except (ValueError, TypeError):
                continue
    if not verified:
        return None
    value = normalized(answer).rstrip(".! ")
    if re.fullmatch(r"(?:(?:er|der schalter) )?unterbricht den stromkreis|der stromkreis wird unterbrochen", value):
        return result("correct", "Dein Satz beschreibt richtig, dass der Schalter den Stromkreis unterbricht.",
                      method=CIRCUIT_VERSION)
    return None  # Negation, extra claims and unknown wording remain uncertain.


def fraction_comparison(question, answer):
    """Evaluate only the fixed, two-option source-comparison template."""
    if question.get("type") != "short" or question.get("language"):
        return None
    prompt = " ".join(unicodedata.normalize("NFC", question.get("prompt", "")).casefold().split())
    match = re.fullmatch(
        r"welcher bruch ist grösser: (\d{1,2})/([1-9]\d?) oder (\d{1,2})/([1-9]\d?)\? gib den grösseren bruch an\.",
        prompt,
    )
    if not match:
        return None
    a, b, c, d = map(int, match.groups())
    left, right = (a, b), (c, d)
    if not (0 < a < b <= 24 and 0 < c < d <= 24) or Fraction(*left) == Fraction(*right):
        return result("uncertain", "Dieser Vergleich muss noch geprüft werden.", method=FRACTION_COMPARISON_VERSION)
    expected = left if Fraction(*left) > Fraction(*right) else right
    if fraction_parts(question.get("answer", "")) != expected:
        return result("uncertain", "Die gespeicherte Lösung dieses Vergleichs muss noch geprüft werden.",
                      method=FRACTION_COMPARISON_VERSION)
    supplied = fraction_parts(answer)
    if supplied not in (left, right):
        return result("uncertain", "Schreibe einen der beiden Brüche als Antwort auf.", method=FRACTION_COMPARISON_VERSION)
    return result("correct" if supplied == expected else "incorrect",
                  "Du hast den größeren Bruch gefunden." if supplied == expected else
                  "Schau dir beide Anteile noch einmal an. Welcher ist größer?", method=FRACTION_COMPARISON_VERSION)



def fraction_component(question, answer):
    """One complete explicit component question, never the whole fraction value.

    NFC preserves superscript/mixed-number notation instead of silently turning
    it into decimal digits. Unknown clauses, multiple fractions and operations
    do not match. A stored key is independently checked before exact aliases.
    """
    if question["type"] not in ("short", "gap", "choice") or question.get("language"):
        return None
    prompt = " ".join(unicodedata.normalize("NFC", question["prompt"]).casefold().split())
    plain = r"[0-9]{1,4}\s*/\s*[1-9][0-9]{0,3}"
    tex = r"\\(?:frac|dfrac)\s*\{\s*[0-9]{1,4}\s*\}\s*\{\s*[1-9][0-9]{0,3}\s*\}"
    bare = rf"(?:{plain}|{tex})"
    visible = rf"(?P<fraction>{bare}|\\\(\s*{bare}\s*\\\)|\\\[\s*{bare}\s*\\\]|\$\s*{bare}\s*\$)"
    part = r"(?P<component>zähler|nenner)"
    prefix = r"(?:(?:übung|aufgabe|neue aufgabe|selbst erstellte übung):\s*)?"
    relation = r"(?:des bruch(?:s|es)|von(?: dem bruch)?|im bruch)"
    forms = (
        rf"(?:beim|im) bruch\s+{visible}\s*:\s*welche zahl ist der {part}[?.!]",
        rf"(?:wie lautet|wie heißt|was ist|welche zahl ist) der {part}\s+{relation}\s+{visible}[?.!]",
        rf"welcher {part} steht im bruch\s+{visible}[?.!]",
        rf"(?:nenne|bestimme) den {part}\s+{relation}\s+{visible}[.!]?",
        rf"gib den {part}\s+{relation}\s+{visible}\s+an[.!]?",
    )
    match = next((m for form in forms if (m := re.fullmatch(prefix + form, prompt))), None)
    if match is None:
        return None
    numerator, denominator = map(int, re.findall(r"[0-9]+", match["fraction"]))
    expected = numerator if match["component"] == "zähler" else denominator

    def numeric(value):
        if not isinstance(value, str):
            return None
        value = unicodedata.normalize("NFC", value).strip()
        # An explicit option label is not a guessed letter or index.
        if question["type"] == "choice" and value in question.get("options", []):
            value = re.sub(r"^(?:\([A-H]\)|[A-H][).:])\s*", "", value, flags=re.I)
        if not re.fullmatch(r"[+−-]?[0-9]{1,9}(?:[.,][0-9]{1,6})?", value):
            return None
        return Fraction(value.replace(",", ".").replace("−", "-"))

    key, supplied = numeric(question["answer"]), numeric(answer)
    if key is None or key != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur gefragten Zahl im Bruch. Die Aufgabe muss geklärt werden.",
                      method=FRACTION_COMPONENT_VERSION)
    if supplied is None:
        return None
    return result("correct" if supplied == expected else "incorrect",
                  "Du hast die gefragte Zahl im Bruch richtig benannt." if supplied == expected else
                  "Der Zähler steht über dem Bruchstrich, der Nenner darunter. Schau noch einmal auf die gefragte Zahl.",
                  method=FRACTION_COMPONENT_VERSION)


def fraction_meaning(question, answer):
    """Check the exact curated parts-of-a-whole probe from its visible counts.

    Unknown formulations and prose remain uncertain. Validate the stored key
    against the independently parsed question before judging any response.
    """
    if question.get("type") != "short" or question.get("language"):
        return None
    prompt = " ".join(unicodedata.normalize("NFC", question.get("prompt", "")).casefold().split())
    match = re.fullmatch(
        r"ein ganzes ist in ([1-9][0-9]{0,3}) gleich grosse teile geteilt\. "
        r"([1-9][0-9]{0,3}) teil(?:e)? (?:ist|sind) ausgewählt\. "
        r"welchen bruch beschreibt das\? schreibe zähler/nenner\.", prompt,
    )
    if not match:
        return None
    denominator, numerator = map(int, match.groups())
    if numerator > denominator:
        return result("uncertain", "Die Angaben zur Einteilung passen nicht zusammen. Die Aufgabe muss geklärt werden.",
                      method=FRACTION_MEANING_VERSION)
    expected = (numerator, denominator)
    if fraction_parts(question.get("answer", "")) != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zu den Teilen. Die Aufgabe muss geklärt werden.",
                      method=FRACTION_MEANING_VERSION)
    if not re.fullmatch(r"\s*-?[0-9]{1,9}\s*/\s*[1-9][0-9]{0,8}\s*", answer):
        return None
    supplied = fraction_parts(answer)
    equal = Fraction(*supplied) == Fraction(*expected)
    return result("correct" if equal else "incorrect",
                  "Der Bruch beschreibt den ausgewählten Anteil." if equal else
                  "Unten steht, in wie viele Teile das Ganze geteilt ist. Oben stehen die ausgewählten Teile.",
                  method=FRACTION_MEANING_VERSION)


def lcm_short_answer(question, answer):
    """Verify one explicit two-integer kgV question before exact aliases.

    Only the complete numeric short-answer form is recognised. NFC preserves
    unsupported superscripts and full-width digits; neither prose nor answer
    variants can override the independently computed smallest common multiple.
    """
    if question.get("type") != "short" or question.get("language"):
        return None
    prompt = " ".join(unicodedata.normalize("NFC", question["prompt"]).casefold().split())
    positive = r"[1-9][0-9]{0,3}"
    match = re.fullmatch(
        rf"was ist das kleinste gemeinsame vielfache(?: \(kgv\))? von ({positive}) und ({positive})\?",
        prompt,
    )
    if match is None:
        return None
    expected = lcm(int(match[1]), int(match[2]))

    def numeric(value):
        if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,9}", value.strip()):
            return None
        return int(value.strip())

    key = numeric(question.get("answer"))
    if key is None or key != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zum kleinsten gemeinsamen Vielfachen. Die Aufgabe muss geklärt werden.",
                      method=LCM_VERSION)
    supplied = numeric(answer)
    if supplied is None:
        return result("uncertain", "Gib eine einzelne ganze Zahl als kleinstes gemeinsames Vielfaches ein.",
                      method=LCM_VERSION)
    return result("correct" if supplied == expected else "incorrect",
                  "Deine Zahl ist das kleinste gemeinsame Vielfache." if supplied == expected else
                  "Suche die kleinste positive Zahl, die ein Vielfaches von beiden Zahlen ist.",
                  method=LCM_VERSION)


def arithmetic(question, answer):
    if question["type"] not in ("short", "gap"):
        return None
    prompt = question["prompt"]
    instruction = fraction_instruction(prompt)
    expression = re.search(
        r"(?<![\d/])(\d{1,4})\s*/\s*([1-9]\d{0,3})\s*([+−-])\s*"
        r"(\d{1,4})\s*/\s*([1-9]\d{0,3})(?![\d/])", prompt)
    # Part questions and a numerator gap ask for a number, not the value of
    # the entire fraction. Leave their established exact evaluation intact.
    if re.search(r"\b(?:zähler|nenner|teiler|divisor|faktor)\b", prompt, re.I) and not instruction:
        if not re.search(r"\b(?:als\s+bruch\s+mit\s+(?:dem\s+)?nenner)\b", prompt, re.I):
            return None
    if re.search(r"(?:_{2,}|□|\?+)\s*/|/\s*(?:_{2,}|□|\?+)", prompt):
        return None
    calculation = re.search(r"berechne|rechne|ergibt|ergebnis|summe|addiere|subtrahiere|wie viel", prompt, re.I)
    equation_gap = re.search(r"=\s*(?:_{2,}|□|\?+)\s*[.!?]?\s*$", prompt)
    if not instruction and not (expression and (calculation or equation_gap)):
        return None
    key, supplied = fraction_parts(question["answer"]), fraction_parts(answer)
    if key is None or supplied is None:
        return None
    expected = Fraction(*key)
    if expression:
        a, b, op, c, d = expression.groups()
        computed = Fraction(int(a), int(b)) + (1 if op == "+" else -1) * Fraction(int(c), int(d))
        if computed != expected:
            return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur Rechnung. Die Aufgabe muss geklärt werden.")
    if Fraction(*supplied) != expected:
        return result("incorrect", "Die beiden Brüche haben noch nicht denselben Wert.")
    try:
        fraction_result(prompt, answer, [], question_type=question["type"])
        if expression and re.search(r"\b(?:kürze\s+(?:das\s+ergebnis\s+)?vollständig|vollständig\s+gekürzt|vollständig\s+kürzen)\b", prompt, re.I) and supplied != (expected.numerator, expected.denominator):
            raise ValueError("fully reduced result")
        denominator = re.search(r"\b(?:als\s+)?bruch\s+mit\s+(?:dem\s+)?nenner\s+(\d{1,4})\b", prompt, re.I)
        if denominator and supplied[1] != int(denominator[1]):
            raise ValueError("requested denominator")
    except ValueError:
        return result("incorrect", "Der Wert stimmt. Die Aufgabe verlangt noch eine bestimmte Bruchdarstellung.",
                      content="correct", form="incorrect")
    equivalent = supplied != key
    return result("correct", (f"Das stimmt: {answer.strip()} ist genauso viel wie {question['answer']}."
                              if equivalent else "Wert und verlangte Darstellung stimmen."),
                  form="correct" if instruction or denominator or re.search(r"vollständig", prompt, re.I) else "not_requested")


def elementary_arithmetic(question, answer):
    """A complete two-number question, exact rationals, no general text eval.

    Both operands, operation and the entire question must be recognised. Never
    extract a convenient subexpression from a word problem, rounded result,
    numerator question or equation. Check the stored key before accepting it.
    """
    if question["type"] not in ("short", "gap", "choice"):
        return None
    prompt = " ".join(question["prompt"].casefold().split())
    match = re.fullmatch(
        r"(?:(?:selbst erstellte übung|übung|aufgabe|neue aufgabe):\s*)?"
        r"(?:wie viel ist|berechne|rechne)\s+(.+?)\s*[?.!]"
        r"(?:\s*gib nur (?:das ergebnis|die zahl) ein[.!]?)?", prompt)
    if not match:
        return None
    term = match[1]
    for left, right in ((r"\(", r"\)"), (r"\[", r"\]"), ("$", "$")):
        if term.startswith(left) and term.endswith(right):
            term = term[len(left):-len(right)].strip()
            break
    number = r"[+−-]?\d{1,9}(?:[.,]\d{1,6})?"
    expression = re.fullmatch(rf"({number})\s*(\+|−|-|×|·|\*|:|/|\\cdot|\\times|\\div)\s*({number})", term)
    if not expression:
        return None
    a, operator, b = expression.groups()
    first, second = (Fraction(s.replace(",", ".").replace("−", "-")) for s in (a, b))
    if operator in (":", "/", r"\div") and second == 0:
        return result("uncertain", "Durch null darfst du nicht teilen. Die Aufgabe muss geklärt werden.")
    expected = (first + second if operator == "+" else first - second if operator in ("-", "−")
                else first * second if operator in ("×", "·", "*", r"\cdot", r"\times") else first / second)

    def numeric(text):
        clean = text.strip().replace(",", ".").replace("−", "-")
        if not re.fullmatch(rf"{number}(?:\s*/\s*[1-9]\d{{0,8}})?", clean):
            return None
        parts = clean.replace(" ", "").split("/")
        return Fraction(parts[0]) / Fraction(parts[1]) if len(parts) == 2 else Fraction(parts[0])

    key, supplied = numeric(question["answer"]), numeric(answer)
    if key is None or key != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zum Rechenterm. Die Aufgabe muss geklärt werden.")
    if supplied is None:
        return None
    return result("correct" if supplied == expected else "incorrect",
        "Dein Ergebnis passt zum Rechenterm." if supplied == expected else "Prüfe die Rechenzeichen und rechne die beiden Zahlen noch einmal nach.")


def rectangle_area(question, answer):
    """Check a bounded, explicit rectangle problem, not arbitrary word problems.

    The prompt supplies the output unit, so a bare number is sufficient unless
    writing the unit is itself explicitly requested. Verify the stored key
    against the given sides before accepting any answer or answer variant.
    """
    if question["type"] not in ("short", "gap"):
        return None
    number = r"\d{1,6}(?:[.,]\d{1,6})?"
    length = rf"({number})\s*(mm|cm|dm|km|m)"
    area = r"(mm|cm|dm|km|m)(?:²|\^2|2)"
    prompt = " ".join(question["prompt"].lower().split())
    match = re.fullmatch(
        rf"(?:(?:übung|aufgabe|neues übungsbeispiel):\s*)?(?:ein|das) rechteck ist "
        rf"{length}\s+lang\s+und\s+{length}\s+breit[.!]\s*"
        rf"(?:wie groß ist (?:seine|die) fläche|berechne (?:seine|die) fläche)"
        rf"(?:\s+in\s+{area})?[?.!]?"
        r"(?:\s*(?:gib (?:das ergebnis|die antwort) mit (?:der )?einheit an|nenne zahl und einheit)[.!]?)?",
        prompt,
    )
    if not match or match[2] != match[4]:
        return None
    first, second = (Fraction(match[i].replace(",", ".")) for i in (1, 3))
    if first <= 0 or second <= 0:
        return None
    expected = first * second
    unit = match[5] or match[2]
    # Mixed output units are deliberately left to an explicit conversion task.
    if unit != match[2]:
        return None

    def quantity(text):
        value = re.fullmatch(rf"\s*({number})(?:\s*{area})?\s*", text)
        return (Fraction(value[1].replace(",", ".")), value[2]) if value else None

    key, supplied = quantity(question["answer"]), quantity(answer)
    if not key or key[0] != expected or (key[1] and key[1] != unit):
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur Rechteckfläche. Die Aufgabe muss geklärt werden.")
    if not supplied:
        return None
    if supplied[0] != expected:
        return result("incorrect", "Multipliziere die Länge mit der Breite. Prüfe noch einmal dein Ergebnis.")
    if supplied[1] and supplied[1] != unit:
        return result("incorrect", "Der Zahlenwert stimmt. Prüfe die verlangte Flächeneinheit.", content="correct", form="incorrect")
    if re.search(r"mit (?:der )?einheit|zahl und einheit", prompt) and not supplied[1]:
        return result("incorrect", "Der Zahlenwert stimmt. Ergänze noch die ausdrücklich verlangte Flächeneinheit.", content="correct", form="incorrect")
    return result("correct", "Die Fläche stimmt: Länge mal Breite ergibt den gesuchten Flächeninhalt.")


def triangle_area(question, answer):
    from .subject_content import legacy_presentation

    if not re.search(r"fläch", question["prompt"], re.I) or not (p := legacy_presentation(question)):
        return None
    block = p["blocks"][0]
    if block["kind"] != "triangle":
        return None
    g, h = (Fraction(str(n)) for n in block["numbers"])
    expected = g * h / 2
    def quantity(text):
        match = re.fullmatch(r"\s*(\d+(?:[.,]\d+)?)(?:\s*(cm|m)(?:²|\^2|2))?\s*", text)
        return (Fraction(match[1].replace(",", ".")), match[2]) if match else None
    key, supplied = quantity(question["answer"]), quantity(answer)
    if not key or key[0] != expected:
        return result("uncertain", "Die gespeicherte Musterlösung passt nicht zur Dreiecksfläche. Die Prüfung ist offen.")
    if not supplied:
        return None
    if supplied[0] == g * h:
        return result("incorrect", "Grundseite mal Höhe ergibt die Rechteckfläche. Das Dreieck ist die Hälfte davon. Welcher Schritt fehlt noch?")
    if supplied[0] != expected:
        return result("incorrect", "Prüfe erst Grundseite mal senkrechte Höhe. Danach halbierst du das Ergebnis.")
    if supplied[1] and supplied[1] != block["unit"]:
        return result("incorrect", "Der Zahlenwert stimmt; prüfe die Flächeneinheit.", content="correct", form="incorrect")
    if re.search(r"mit\s+(?:der\s+)?einheit|zahl\s+und\s+einheit", question["prompt"], re.I) and not supplied[1]:
        return result("incorrect", "Der Zahlenwert stimmt. Ergänze noch die verlangte Flächeneinheit.", content="correct", form="incorrect")
    return result("correct", "Du hast Grundseite und senkrechte Höhe multipliziert und das Ergebnis halbiert.")


def closed_concept(question, answer):
    """Small audited phrase rules, not a general semantic grader."""
    expected = normalized(question["answer"])
    value = " ".join(unicodedata.normalize("NFKC", answer).casefold().split()).rstrip(".! ")
    # An answer wrapper may contain exactly the key, no added factual claim.
    if len(expected.split()) <= 4 and any(value == prefix + expected for prefix in (
        "die antwort ist ", "das ist ", "es ist ", "der begriff ist ")):
        return result("correct", "Deine Formulierung nennt den gesuchten Begriff.")
    prompt = normalized(question["prompt"])
    if not re.search(r"wirbelsäule|wirbellos", prompt):
        return None
    if not re.fullmatch(r"(?:die |den |zu den )?wirbellosen?(?: tiere[ns]?)?", expected):
        return None
    # This precise positive classification accepts inflection and an optional
    # matching reason. Negation, contradictory additions and other sentences
    # intentionally fail the full match and remain open.
    phrase = (r"(?:(?:es|das tier) (?:gehört|zählt) zu den |(?:es|das tier) ist (?:ein )?|(?:zu den |den |die ))?"
              r"wirbellosen?(?:[rs] tier| tieren| tiere)?"
              r"(?:,? (?:weil|da) (?:es|das tier) keine wirbelsäule (?:hat|besitzt))?")
    if re.fullmatch(phrase, value):
        return result("correct", "Du ordnest das Tier richtig als wirbellos ein.")
    return None


def evaluate(question, answer):
    if (question.get("presentation") or {}).get("evidence_kind") in ("reflection", "creative", "self_report", "movement"):
        return result("uncertain", "Deine Idee ist gespeichert. Gefühle, kreative Ideen oder körperliche Ausführung werden hier nicht als richtig oder falsch gemessen.", method="open_learning_v1")
    if question.get("type") == "grouped":
        from .grouped_questions import evaluate as evaluate_group

        return evaluate_group(question, answer)
    if checked := rectangle_area(question, answer):
        return checked
    if checked := triangle_area(question, answer):
        return checked
    if question.get("language"):
        from .language_evaluation import evaluate as language_evaluate

        return language_evaluate(question, answer)
    if checked := circuit_interruption(question, answer):
        return checked
    if checked := lcm_short_answer(question, answer):
        return checked
    if checked := fraction_comparison(question, answer):
        return checked
    if checked := fraction_component(question, answer):
        return checked
    if checked := fraction_meaning(question, answer):
        return checked
    if hints := fraction_addition_hint(question, answer):
        return result("incorrect", hints[0])
    form = expanded_fraction(question["prompt"]) if question["type"] in ("choice", "gap", "short") else None
    if form and (supplied := fraction_parts(answer)) is not None:
        value_ok = Fraction(*supplied) == Fraction(*form)
        return result("correct" if supplied == form else "incorrect",
                      "Die verlangte Erweiterung stimmt." if supplied == form else "Multipliziere beide Zahlen mit dem verlangten Faktor.",
                      content="correct" if value_ok else "incorrect", form="correct" if supplied == form else "incorrect")
    if checked := arithmetic(question, answer):
        return checked
    if checked := elementary_arithmetic(question, answer):
        return checked
    if normalized(answer) in {normalized(v) for v in [question["answer"], *question.get("accepted", [])]}:
        return result("correct", "Deine Antwort entspricht einer geprüften Lösung.")
    if question["type"] == "short":
        if checked := closed_concept(question, answer):
            return checked
        return result("uncertain", "Deine Antwort ist gespeichert. Du kannst die Prüfung öffnen oder den gesuchten Begriff präzisieren.")
    return result("incorrect", "Die Antwort passt noch nicht zur Aufgabe.")
