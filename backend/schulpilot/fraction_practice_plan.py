"""Finite new mixed-number questions from actual prepared source literals.

No new input number is invented and no model answer is repaired. Full private
history becomes only candidate-value exclusions, never learner answer data.
"""
import copy
import hashlib
import json
import re
import unicodedata
from fractions import Fraction

REVISION = "fraction-practice-plan-1"
ERROR = "Hier sind keine zwei neuen Umwandlungsaufgaben aus den bestätigten Originalbrüchen mehr verfügbar. Wähle eine andere bestätigte Heftseite zum Weiterlernen. Es wurde keine KI-Anfrage gesendet."
INVALID = "Der feste Umwandlungsauftrag ist nicht vollständig an Quellen und Lernziele gebunden. Es wurde keine KI-Anfrage gesendet."
CURRENT_ERROR = "Eine Umwandlungsaufgabe wurde inzwischen bereits verwendet. Die neue Runde wurde nicht übernommen. Deine bisherigen Antworten bleiben gespeichert. Wähle eine andere bestätigte Heftseite zum Weiterlernen."
_LITERAL = re.compile(r"(?<![\w/.,+−-])([0-9]{1,3})\s*(?:/|durch)\s*([1-9][0-9]{0,2})(?![\w/]|[.,][0-9])", re.I)
_LATEX = re.compile(r"\\(?:d?frac)\s*\{\s*([0-9]{1,3})\s*\}\s*\{\s*([1-9][0-9]{0,2})\s*\}")


def _value(pair):
    return str(Fraction(*pair))


def _bases(candidates):
    result = []
    seen = set()
    for candidate in candidates:
        proof = candidate.get("proof")
        if not proof or candidate.get("disclosure") != "solution" or not proof.get("remainder"):
            continue
        key = _value(proof["input"])
        if key not in seen:
            result.append(candidate)
            seen.add(key)
    return result


def _pool_digest(candidates):
    rows = [{key: candidate["proof"][key] for key in ("input", "source_digest", "reference_digest")}
            for candidate in _bases(candidates)]
    return hashlib.sha256(json.dumps(rows, ensure_ascii=False, sort_keys=True,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def history(candidates, prompts):
    """Compact complete source-pool exclusions; no private prompt is returned."""
    pool = {_value(candidate["proof"]["input"]) for candidate in _bases(candidates)}
    used = set()
    unknown = False
    for prompt in prompts:
        if not isinstance(prompt, str):
            raise ValueError(INVALID)
        text = unicodedata.normalize("NFC", prompt)
        pairs = [tuple(map(int, m.groups())) for pattern in (_LITERAL, _LATEX) for m in pattern.finditer(text)]
        used.update(_value(pair) for pair in pairs if _value(pair) in pool)
        if re.search(r"gemischt\w*\s+zahl|unecht\w*\s+br(?:ü|ue)ch", text, re.I) and not pairs:
            unknown = True  # Do not guess which old conversion a worded prompt tested.
    return {"version": 1, "revision": REVISION, "pool_digest": _pool_digest(candidates),
        "used_values": sorted(used), "unknown_conversion": unknown}


def plan(candidates, tasks, exclusion):
    if (not isinstance(tasks, list) or len(tasks) != 2 or any(not isinstance(t, dict) for t in tasks)
            or len({t.get("id") for t in tasks}) != 2
            or any(t.get("id") not in ("q1", "q2")
                   or t.get("learning_goal_id") not in ("g1", "g2", "g3", "g4") for t in tasks)
            or not isinstance(exclusion, dict) or set(exclusion) != {"version", "revision", "pool_digest", "used_values", "unknown_conversion"}
            or type(exclusion.get("version")) is not int or exclusion["version"] != 1
            or exclusion.get("revision") != REVISION or type(exclusion.get("unknown_conversion")) is not bool
            or not isinstance(exclusion.get("used_values"), list)
            or any(not isinstance(value, str) for value in exclusion["used_values"])
            or exclusion.get("pool_digest") != _pool_digest(candidates)):
        raise ValueError(INVALID)
    available = [candidate for candidate in _bases(candidates)
                 if _value(candidate["proof"]["input"]) not in exclusion["used_values"]]
    if exclusion["unknown_conversion"] or len(available) < 2:
        raise ValueError(ERROR)
    result = []
    for task, original in zip(tasks, available[:2], strict=True):
        candidate = copy.deepcopy(original)
        n, d = candidate["proof"]["input"]
        whole, remainder = candidate["proof"]["whole"], candidate["proof"]["remainder"]
        candidate["question_core"] = {"id": task["id"], "learning_goal_id": task["learning_goal_id"], "type": "short",
            "prompt": f"Schreibe {n}/{d} als gemischte Zahl.", "answer": f"{whole} {remainder}/{d}",
            "options": [], "accepted": []}
        candidate["planned_practice"] = REVISION
        result.append(candidate)
    return result
