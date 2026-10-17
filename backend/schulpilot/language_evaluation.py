"""Exact, target-specific evaluation. Never fuzzy-match different words."""

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
    correct = canonical(answer, policy) in {canonical(value, policy) for value in candidates}
    outcome = "correct" if correct else "incorrect" if policy.closed_answers else "uncertain"
    reason = ("Bestätigte Antwortvariante erfüllt das Lernziel." if correct else
              "Antwort entspricht keiner für dieses Lernziel bestätigten Variante." if outcome == "incorrect" else
              "Freier Satz: keine verlässliche vollständige Regelbewertung vorhanden.")
    return {"version": 1, "outcome": outcome, "reason": reason, "criterion": policy.criterion,
            "dimensions": {policy.criterion: outcome}, "method": "language_rule_v1"}
