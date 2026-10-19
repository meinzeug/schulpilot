"""Progressive help for the saved error. No extra model call or fuzzy success."""

from .answer_evaluation import normalized


def match_parts(question, answer):
    if question["type"] != "match":
        return []
    given = answer.split(";")
    expected = question["answer"].split(";")
    return [{"label": pair.split("|")[0],
             "outcome": "correct" if i < len(given) and i < len(expected) and normalized(given[i]) == normalized(expected[i]) else "incorrect"}
            for i, pair in enumerate(question["options"])]


def next_hint(question, previous_answer, shown):
    parts = match_parts(question, previous_answer or "") if previous_answer is not None else []
    wrong = next((i for i, part in enumerate(parts) if part["outcome"] != "correct"), None)
    candidates = []
    if wrong is not None:
        part = parts[wrong]
        right = question["answer"].split(";")[wrong]
        successes = sum(p["outcome"] == "correct" for p in parts)
        candidates.append(f"{successes} von {len(parts)} Zuordnungen stimmen. Schau noch einmal auf „{part['label']}“. Die anderen Paare kannst du lassen.")
        if "säugetier" in normalized(right):
            candidates.append(f"Zusatzwissen für „{part['label']}“: Überlege, womit die Mutter ihre Jungen ernährt. Die Tierklasse hat damit zu tun.")
            candidates.append("Zusatzwissen: Säugetiere ernähren ihre Jungen mit Milch. Nutze dieses Merkmal für die noch offene Zuordnung.")
        else:
            candidates.extend(h for h in question["hints"] if part['label'].casefold() in h.casefold())
            candidates.append(f"Vergleiche das Körpermerkmal von „{part['label']}“ mit den Klassen in deiner Erklärung.")
    if question.get("language") and previous_answer:
        meta = question["language"]
        expected = question["answer"]
        if meta.get("skill") == "spelling" and len(expected) == len(previous_answer) + 1:
            for i, character in enumerate(expected):
                if normalized(expected[:i] + expected[i+1:]) == normalized(previous_answer):
                    candidates.append(f"Prüfe die Schreibung: An Stelle {i+1} fehlt noch ein „{character}“. Ergänze es in deiner Antwort.")
                    break
    if wrong is None:
        candidates.extend(question["hints"])
    candidates.extend(["Gemeinsamer Schritt: " + question["explanation"][:600],
                       "Lies den erklärten Schritt und probiere die Aufgabe noch einmal. Deine bisherigen Antworten bleiben gespeichert."])
    return next((value for value in candidates if value not in shown), None)
