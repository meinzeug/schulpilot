# Flächenantworten · 21.10.2026

Bei einer kurzen Rechteckaufgabe wurde eine richtige Zahl als unklar gespeichert,
weil die Musterlösung zusätzlich die bereits in der Frage genannte Flächeneinheit
enthielt. Der bisherige allgemeine Textvergleich erkannte diesen Unterschied nicht.

`answer_evaluation.rectangle_area` prüft jetzt eine ausdrücklich begrenzte Form
von Rechteckaufgaben mit Länge und Breite. Beide positiven Seiten müssen dieselbe
Längeneinheit verwenden; das Produkt wird mit `Fraction` exakt berechnet und mit
der gespeicherten Hauptlösung abgeglichen. Erst danach wird die Kinderantwort
geprüft. Beispiel ausschließlich künstlich: 7 cm × 4 cm, Antwort `28`, Musterlösung
`28 cm²`. Dezimalkomma/-punkt und `cm²`/`cm2`/`cm^2` sind gleichwertig.

Eine in der Frage vorgegebene Einheit muss nicht nochmals eingetippt werden.
Wenn das Schreiben der Einheit ausdrücklich verlangt wird, bleibt das eine
gesonderte Darstellungsanforderung. Die vorhandene Dreiecksprüfung verwendet
dieselbe Unterscheidung. Falsche Zahlen oder ausdrücklich falsche Einheiten
werden weiterhin nicht akzeptiert. Widersprüchliche Hauptlösungen bleiben unklar,
auch bei wörtlicher Übereinstimmung. Andere Textaufgaben, Umrechnungen und freie
Begründungen werden durch diese begrenzte Regel nicht semantisch geraten.

Regelversion: `subject_rules_v4`. Keine Modellanfrage, keine neuen Kosten und
keine Änderungen an Budget, Modellrouting, Aufgaben oder Quellen. Frühere
Antworten werden nicht beim Lesen automatisch neu bewertet. Eine beauftragte
Korrektur verwendet `assessments.recheck` mit `AttemptAssessment`-Historie und
erneuerter Lerncontroller-Projektion. Antwort, Zeitpunkt, Hilfen, Lernzeit und
Anzahl der Versuche bleiben erhalten. Der konkrete Diagnosezugriff und eine
gezielte Betreiberkorrektur werden separat im privaten Audit erfasst; private
Diagnosekopien bleiben außerhalb von Git und werden nach Abschluss entfernt.

Prüfungen: `backend/tests/test_rectangle_assessment.py` enthält künstliche
Werte-/Einheiten-/Musterlösungsfälle, neue Antworten im geführten Lernraum sowie
idempotente Nachprüfungen mit und ohne frühere Unterstützung. Bestehende
Bruchregeln, Rückmeldungen, Lerncontroller und Fortschrittsprojektionen gehören
zur zugehörigen Regression. Konkreter Abschlussstand im Kopf von `STATUS.md`.

Abnahme vor Release: 223 gezielte Backendfälle auf isoliertem PostgreSQL16
bestanden (`artifacts/math66-regressions.xml`), Ruff und Flutteranalyse sauber.
Der tatsächliche gemeldete Fall wurde zusätzlich lokal ohne Provider geprüft;
private Aufgabeninhalte sind nicht Teil dieser Dokumentation oder der Fixtures.
