"""Compact new analysis requests; saved reports retain their original contract.

These bounds apply before and after one provider call. They never shorten a
literal question, old answer, teacher annotation or citation. Source validation,
revision guards, billing and explicit append requests remain with their owners.
"""

SUMMARY_CHARS = 320
PROPOSAL_CHARS = 240
MAX_SOURCES = 2
MAX_UNCERTAINTIES = 2
UNCERTAINTY_CHARS = 160


def task_limit(max_output_tokens):
    """A ceiling, not an exact count or a promise to fit arbitrary long text."""
    if type(max_output_tokens) is not int or not 1 <= max_output_tokens <= 8000:
        raise ValueError("Ungültige Ausgabebegrenzung für die Arbeitsbesprechung.")
    return 4 if max_output_tokens >= 8000 else 2


def bind_schema(schema, max_output_tokens):
    """Bind only the private request schema, never the saved response model."""
    limit = task_limit(max_output_tokens)
    try:
        fields = schema["properties"]
        task = schema["$defs"]["ReviewTask"]["properties"]
        fields["tasks"]["maxItems"] = limit
        fields["summary"]["maxLength"] = SUMMARY_CHARS
        task["ai_proposal"]["maxLength"] = PROPOSAL_CHARS
        task["sources"]["maxItems"] = MAX_SOURCES
        for uncertainty in (fields["uncertainties"], task["uncertainties"]):
            uncertainty["maxItems"] = MAX_UNCERTAINTIES
            uncertainty["items"]["maxLength"] = UNCERTAINTY_CHARS
    except (KeyError, TypeError) as error:
        raise ValueError("Das kompakte Ausgabeschema der Arbeitsbesprechung fehlt.") from error
    return schema


def rules(max_output_tokens):
    limit = task_limit(max_output_tokens)
    return (
        "\nKOMPAKTER AUFGABENAUSZUG: "
        f"Gib höchstens {limit} neue, vollständig zuordenbare Aufgaben aus; dies ist eine Obergrenze, keine Pflichtzahl. "
        "Wenn eine lange Originalaufgabe mit Antwort und Markierungen viel Platz benötigt, wähle nur eine Aufgabe. "
        f"summary höchstens {SUMMARY_CHARS} Zeichen, ai_proposal je Aufgabe höchstens {PROPOSAL_CHARS} Zeichen. "
        "Keine ausführliche Musterlösung; nur ein kurzer, ausdrücklich vorläufiger Lernhinweis. "
        f"Je Aufgabe höchstens {MAX_SOURCES} notwendige wörtliche Belege, möglichst nur einen. "
        "Übernimm question, original_answer, teacher_feedback und score_label weiterhin vollständig und wörtlich; "
        "niemals kürzen, umformulieren oder mit Auslassungszeichen passend machen. "
        "Zitate bleiben wörtliche Ausschnitte der erlaubten Quelle. Keine Quelle ergänzen oder erfinden. "
        "SAMMELAUFGABEN: Unabhängig lesbare Teilzeilen, etwa nummerierte Verblücken unter einem gemeinsamen Auftrag, "
        "dürfen jeweils eine eigene Aufgabe sein. question ist dann genau die WÖRTLICHE vollständige Teilzeile, "
        "einschließlich ihrer sichtbaren Nummer und Vorgaben. Die gemeinsame Überschrift bleibt Kontext oder ein "
        "zusätzlicher wörtlicher Beleg; hänge sie nicht an question an und erfinde daraus keine neue Frage. "
        "Lasse nur die selbst unleserliche oder nicht sicher zuordenbare Teilzeile aus. Unklare Nachbarzeilen "
        "machen unabhängig lesbare Zeilen nicht automatisch unbrauchbar und sind kein Grund, den ganzen "
        "Sammelauftrag als eine einzige unleserliche Aufgabe zu überspringen. Die Obergrenze bleibt unverändert; "
        "wähle nur einen kleinen belegten Auszug, ohne eine Mindestzahl an Aufgaben zu erzwingen. "
        "original_answer bleibt die tatsächlich sichtbare alte Antwort; keine Lücke ergänzen, keine Verbform "
        "korrigieren oder aus Aufgabenstellung beziehungsweise Musterwissen neu berechnen. "
        "teacher_feedback nur übernehmen, wenn die Quelle die Annotation ausdrücklich einer Lehrkraft zuordnet. "
        "Ohne solchen Rollenbeleg bleibt teacher_feedback leer und die unklare Zuordnung erscheint in uncertainties. "
        "Farbe, Handschrift oder Randposition allein sind kein Rollenbeleg. Sichtbare Punkte nur wörtlich "
        "übernehmen; keine Bewertung oder Punktzahl selbst berechnen. "
        f"Global und je Aufgabe höchstens {MAX_UNCERTAINTIES} kurze Unsicherheitshinweise mit je höchstens "
        f"{UNCERTAINTY_CHARS} Zeichen; Unsicherheit nicht verschweigen. "
        "Lässt sich eine Aufgabe nicht vollständig und sicher zuordnen, lasse diese Aufgabe aus und benenne das offen. "
        "Falls keine passende Aufgabe bleibt, tasks=[] mit Unsicherheitshinweis. "
        "Frühere gespeicherte Aufgaben nicht wiederholen. Ein weiterer Auszug wird später ausdrücklich angefordert; "
        "keine automatische Fortsetzung, keinen automatischen Wiederholungsversuch und keine Vollständigkeit behaupten."
    )


def _uncertainties(value):
    return (isinstance(value, list) and len(value) <= MAX_UNCERTAINTIES
            and all(isinstance(text, str) and len(text) <= UNCERTAINTY_CHARS for text in value))


def validate_bounds(data, max_output_tokens):
    """Fail closed on newly generated verbosity. Do not repair or truncate it.

    The caller must still run ExamReviewOutput and the existing exact source
    checks. Old saved reports deliberately never pass through this function.
    """
    limit = task_limit(max_output_tokens)
    valid = isinstance(data, dict)
    if valid:
        tasks, summary = data.get("tasks"), data.get("summary")
        valid = (isinstance(tasks, list) and len(tasks) <= limit
                 and isinstance(summary, str) and len(summary) <= SUMMARY_CHARS
                 and _uncertainties(data.get("uncertainties")))
    if valid:
        for task in tasks:
            if not isinstance(task, dict):
                valid = False
                break
            proposal, sources = task.get("ai_proposal"), task.get("sources")
            if (not isinstance(proposal, str) or len(proposal) > PROPOSAL_CHARS
                    or not isinstance(sources, list) or not 1 <= len(sources) <= MAX_SOURCES
                    or not _uncertainties(task.get("uncertainties"))):
                valid = False
                break
    if not valid:
        raise ValueError("Der neue Aufgaben-Auszug überschreitet den kompakten Ausgaberahmen. Die Originale bleiben erhalten.")
    return data
