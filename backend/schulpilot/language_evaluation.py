"""Exact, target-specific evaluation. Never fuzzy-match different words."""

import re
import unicodedata

from .language_tasks import LanguageTask


def canonical(text, policy):
    value = " ".join(unicodedata.normalize("NFC", text).split())
    if policy.apostrophe_equivalent:
        value = value.replace("’", "'").replace("‘", "'")
    if not policy.case_sensitive:
        value = value.casefold()
    if policy.terminal_punctuation_optional:
        value = value.rstrip(".!?")
    return value


def evaluate(question, answer):
    task = LanguageTask.model_validate(question["language"])
    policy = task.evaluation_policy
    candidates = [question["answer"], *question.get("accepted", [])]
    supplied = canonical(answer, policy)
    allowed = {canonical(value, policy) for value in candidates}
    # A word entered in isolation may begin like a sentence. Only English
    # lower-case common words get this exception; proper names, German nouns,
    # internal capitals, accents and explicitly tested case remain exact.
    optional = policy.sentence_initial_optional
    if optional is None:
        optional = (task.answer_locale in ("en-GB", "en-US") and task.skill in ("spelling", "recall")
                    and not re.search(r"groß|klein|capital|case-sensitive", question.get("prompt", ""), re.I))
    if policy.case_sensitive and optional and task.answer_locale in ("en-GB", "en-US"):
        allowed |= {v[0].upper() + v[1:] for v in tuple(allowed) if v and 'a' <= v[0] <= 'z' and v == v.lower()}
    correct = supplied in allowed
    outcome = "correct" if correct else "incorrect" if policy.closed_answers else "uncertain"
    reason = ("Richtig – das ist die gesuchte Antwort." if correct else
              "Prüfe noch einmal das gesuchte Wort und den Zusammenhang." if outcome == "incorrect" else
              "Dein Satz ist gespeichert. Die automatische Prüfung kann ihn noch nicht sicher beurteilen.")
    dimensions = {policy.criterion: outcome}
    if task.skill == "spelling":
        dimensions.update(spelling=outcome, meaning="not_separately_tested")
        if correct:
            reason = "Das gesuchte Wort und die Schreibweise stimmen."
        elif policy.case_sensitive and any(len(supplied) == len(value) and supplied.casefold() == value.casefold() for value in allowed):
            expected = next(value for value in candidates if len(canonical(value, policy)) == len(supplied)
                            and canonical(value, policy).casefold() == supplied.casefold())
            expected = canonical(expected, policy)
            position = next(i for i, (a, b) in enumerate(zip(supplied, expected)) if a != b)
            letter = expected[position]
            reason = f"Das Wort stimmt. Schreibe es hier {'mit' if position == 0 else 'an Stelle ' + str(position + 1) + ' mit'} {'kleinem' if letter.islower() else 'großem'} {letter}."
            dimensions.update(spelling="correct", capitalization="incorrect")
        else:
            reason = "Prüfe die Buchstaben noch einmal. Unter Hilfe bekommst du einen Hinweis zu deiner Antwort."
    return {"version": 1, "outcome": outcome, "reason": reason, "criterion": policy.criterion,
            "dimensions": dimensions, "method": "language_rule_v2"}
