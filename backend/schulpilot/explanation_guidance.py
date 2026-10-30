"""Readable, source-bound teaching within the existing single generation.

This controls newly generated prose only. It never rewrites a saved lesson,
source quote, answer, renderer label, disclosure, schema limit or grade profile.
"""

REVISION = "explanation-guidance-1"
_FUNCTIONS = frozenset({"unit", "package", "unit_visuals"})

RULES = """
VERSTÄNDLICH ERKLÄREN: Schreibe für das Kind, nicht als fachliche Regieanweisung.
Der tatsächlich sichtbare explanation_steps.text muss für sich verständlich sein; ein langer
explanation-Absatz ersetzt ihn nicht. Kurze Absätze und einfache Sätze statt einer Pflichtliste:
Mach zuerst greifbar, worum es geht und wozu das hilft, möglichst an einer belegten Alltagssituation.
Erkläre ein benötigtes neues Fachwort beim ersten Vorkommen mit gewöhnlichen Wörtern; setze
keine unerklärten Voraussetzungen voraus. Nutze ein konkretes zulässiges Beispiel in kleinen
Schritten: Was schaue ich an, was ändere/vergleiche ich, warum? Sage ausdrücklich, was die Grafik
zeigt und worauf das Kind darin achten soll. Schließe passend mit einem kurzen Merksatz.
Keine fünf starren Überschriften, bloßen Arbeitsaufträge oder doppelte Erklärungstexte. Bei nur
einem erlaubten Introstep passen die wichtigen Zusammenhänge in diesen vorhandenen Schritt;
Schrittzahl, Zeichen-/Aufgaben-/Tokenlimits bleiben unverändert. Feste serverseitige Texte,
Fragekerne und vorbereitete Grafik-IDs haben Vorrang und werden niemals umformuliert.

ERKLÄRUNG UND AUFGABEN: Plane sie zusammen. Bereite jede tatsächlich geprüfte Regel verständlich
vor, nicht nur eine andere Regel desselben Themas. Ein neues Verfahren darf nicht überraschend
in der nächsten Frage auftauchen. Halte die Einheit dafür thematisch zusammen; die gezielte
Frageerklärung bleibt erreichbar. Vorgesehene Vorwissens-/Abrufproben behalten ihren Ablauf.
Keine Lösung, richtige Option oder verdeckte Antwort einer noch offenen Aufgabe in given oder
im vorweg sichtbaren Beispiel nennen. Beispiele nur aus bestätigten Quellen, ausdrücklich
freigegebenen kuratierten Grundlagen oder bereits serverseitig geplanten Rechenbeispielen;
keine zusätzliche Fachregel, Übersetzung, Unterrichtsthematik oder erfundene Quellenbehauptung.
Grafikzitate, Objekt-/Originalbeschriftungen und Referenzen bleiben wörtlich und belegt. Eine
verständliche Erläuterung steht im Erklärungstext, nicht als umgeschriebenes Quellenlabel.
Sprich zum Kind über den Stoff. Keine internen Begriffe wie Grafiktyp, Schema,
Referenz-ID, Freigabe oder technische Gründe für fehlende Darstellungen erwähnen.

SELBSTVERSTÄNDLICHE FRAGEN: Gib nötigen kurzen Kontext im Prompt oder in einer erlaubten
gegebenen Darstellung mit. Das Kind muss die Frage ohne ein unsichtbares altes Arbeitsblatt
verstehen können. Frage nach dem fachlichen Zusammenhang, nicht danach, welche alte Antwort
auf dem Blatt als wahr/falsch/richtig markiert wurde. Alte Schülerantworten oder Lehrermarkierungen
sind keine Lösungsvorlage. Echter Abruf bestätigter Begriffe bleibt erlaubt. Ein Fehlerdetektivfall
darf einen klar als Übungsfehler gekennzeichneten neuen Satz prüfen, aber fachlich begründet
statt durch Ablesen einer früheren Markierung. Keine fehlenden Tatsachen zum Kontext hinzuerfinden.
"""


def rules(function, payload):
    if function not in _FUNCTIONS:
        return ""
    grade = payload.get("grade")
    if type(grade) is int and 1 <= grade <= 13:
        level = f"Konfigurierte Klassenstufe: {grade}."
        if grade <= 4:
            level += " Besonders kurze, konkrete Sätze; ein Gedankenschritt nach dem anderen."
        elif grade <= 7:
            level += " Auch ohne Fachvorwissen verständlich; Fachwörter sofort einfach erklären."
        else:
            level += " Fachlich präzise, aber neue Begriffe und Zwischenschritte weiterhin erklären."
    else:
        level = "Klassenstufe nicht angegeben: klar und voraussetzungsarm erklären; keine Stufe aus Alter oder Material erraten."
    return "\n" + REVISION + ": " + level + RULES
