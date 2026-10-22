# Technische Fehler und kontrollierte Reparaturvorschläge

Stand: Implementierung vom 22.10.2026; Produktionsfreigabe und die Abnahme des separaten Reparaturworkers erfolgen in der gemeinsamen Releaseprüfung.

## Daten und Rechte

`operator_incidents.py` bietet ausschließlich Administratoren technische Metadaten. Eltern und Kinder erhalten keinen Zugriff. Auch der Administrator erhält darüber keine Lerninhalte.

`GET /api/admin/operator-incidents` gruppiert vorhandene fehlgeschlagene Lernaufträge anhand freigegebener Auftragsarten und Fehlercodes bereits in der Datenbank. Es werden weder Job-/Kind-/Familienkennungen noch Inhalte, Fragen, Antworten, Fotos, Prompts, Fehlertexte oder Providerantworten geladen oder ausgegeben. Unbekannte historische Fehler bleiben ausdrücklich `unknown`; deren Quellstand und Ausnahme werden nicht nachträglich erfunden. Die Projektion schreibt keine Ereignisse und startet keine KI.

Neue unerwartete API-Fehler werden über `record_api_failure(error)` nach technischen Kategorien zusammengezählt: Code, statische Codefunktion, Ausnahmekategorie aus einer Whitelist, Veröffentlichungsstand, erste/letzte Beobachtung, Häufigkeit und zufällige Tracekennung. Kein Exceptiontext, Frame-Locals, Request, URL oder Nutzer wird übernommen. Die API ruft dies außerhalb des Async-Eventloops auf. Fehler der Aufzeichnung verdecken niemals die ursprüngliche kontrollierte Fehlerantwort.

Die Detailansicht zeigt einen SHA256-gebundenen Metadatensnapshot. Fehlermetadaten und abgeschlossene Reparaturaufträge werden 30 Tage aufbewahrt. Die bestehende Wartung bereinigt höchstens 100 alte Reparaturaufträge je Durchgang; nur geprüfte Patchpfade im eigenen Verzeichnis werden zur Dateibereinigung zurückgegeben.

## Bewusster Reparaturauftrag

1. Der Administrator öffnet einen Fehler und fordert ausdrücklich einen Vorschlag an.
2. Die API prüft den Katalog des **separaten** Reparaturworkers. Der ausdrücklich beauftragte Eintrag `gpt-6.1-sol` mit `max` muss im tatsächlichen Katalog bestätigt sein; dessen Fingerprint wird gespeichert. Es gibt keinen Ersatz über den Lernworker.
3. Nach der sichtbaren Bestätigung sendet die Oberfläche einen Idempotenzschlüssel, den Snapshotdigest und den aktuellen vollständigen Quellcommit.
4. Die API prüft Administrator und genau dessen auslösende Sitzung erneut. Veraltete Fehler- oder Quellstände werden mit409 abgewiesen. Gleiche Schlüssel beziehungsweise bereits aktive gleiche Snapshots erzeugen keinen zweiten Auftrag.
5. Neue bewusste Aufträge sind global auf zwei je Tag und fünf je Stunde begrenzt. Ein eindeutiger Ausführungsslot begrenzt den separaten Dispatcher auf einen laufenden Auftrag. Die globale Kostenreservierung und die getrennten Ausführungsgrenzen werden durch den separaten Dispatcher geprüft; es wird kein Kinderhaushalt für Reparaturen angelegt oder belastet. Unbekannte Kontokosten dürfen nicht als kostenlos gelten.
6. Das Ergebnis ist ausschließlich ein Patchartefakt. Die Anwendung führt dieses weder aus noch spielt sie es ein. Ein Klick auf Freigeben vermerkt nur die menschliche Prüfung.

Die Persistenz enthält die explizite Adminsitzungsreferenz, sodass der Dispatcher Widerruf vor und nach der Ausführung prüfen kann. Der Lernworker erhält keine zusätzlichen Host-, SSH-, Git- oder Deploymentrechte.

## Patchprüfung

`GET /api/admin/operator-incidents/repairs/{id}/patch` liefert nur eine UTF8-Patchdatei bis512KiB aus dem eigenen Verzeichnis `DATA_DIR/operator-repairs/{id}.patch`. Pfad, Dateiname, Symlinkfreiheit, gespeicherte Größe und SHA256 müssen passen. Unbekannte oder veränderte Dateien führen zu409. Der interne Dateipfad und die auslösende Adminsitzung werden nicht an den Client ausgegeben.

`POST .../{id}/review` verlangt zusätzlich die aktuelle Auftragsrevision und den unveränderten Artefakthash. Freigabe und Ablehnung werden auditierbar gespeichert; beide verändern keinen Anwendungscode. Ein generierter Modellbericht zählt niemals als ausgeführter Test. Die Oberfläche zeigt nur separat vom isolierten Worker bestätigte Testzähler; ansonsten steht ausdrücklich, dass kein unabhängiger Prüflauf nachgewiesen ist.

## Entscheidungsfehler nach beantworteten Aufgaben

`instructional_decisions.schema_refs()` begrenzt das private Ausgabeschema anhand derselben gespeicherten Fakten wie der abschließende Validator. Abgeschlossene Fragen sind keine zulässigen Übungs-/Hinweisziele. Eine neue Verständnisprüfung muss unversucht sein und darf keine bereits gezeigte Lösung verwenden. Fehlende Ressourcen werden nicht als Empfehlungsaktion angeboten. Verzweigungen auf Index0 werden bereits vom Schema ausgeschlossen; spätere gültige Zielindizes und alle IDs werden weiterhin abschließend geprüft.

`DecisionPlanError` speichert ausschließlich die neutralen Kategorien `decision_shape`, `decision_refs`, `decision_closed`, `decision_not_new` oder `decision_flow`. Keine Modellantwort wird repariert, umetikettiert oder automatisch erneut angefordert. Antworten, bestehende Hilfen, Verbrauch und frühere fehlgeschlagene Aufträge bleiben erhalten.

Der konkret freigegebene Diagnosezugriff vom22.10. wurde für genau den benannten Haushalt auditierbar durchgeführt. Dort passte der Kontext unverändert zum historischen fehlgeschlagenen Entscheidungsauftrag; vier von fünf Fragen waren bereits geschlossen. Die frühere Modellausgabe wurde absichtlich nicht gespeichert. Deshalb ist die genaue damals verworfene Auswahl **nicht nachweisbar**. Der Fix schließt die belegte allgemeine Schemalücke und verbessert künftige Diagnosen; er behauptet keinen nachträglich bewiesenen Modellfehler und erzeugt keinen neuen Auftrag für das Kind.

## Abnahmegrenzen

Die gezielten Prüfungen verwenden ausschließlich synthetische Konten, Metadaten, Antworten und Patches. Direkte Tests des separaten echten CLI-Runners, dessen globaler Reservierung und dessen Isolation gehören zu dessen eigenem Abnahmeprotokoll. Ein verfügbares Modell im Katalog allein beweist keine erfolgreiche Reparatur.
