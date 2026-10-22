# Vorwissen aus gespeicherten Lernbelegen

Schulpilot speichert die ursprünglichen Antworten in `Attempt`, Aufgaben und
Quellenstände in `LearningUnit`/`UnitSource`, bestätigte Lernzielzuordnungen im
vorhandenen Coachingbericht und den Arbeitszustand in `LearningMemory`.
Die neue Schulbuddy-Anbindung verwendet diese Bestände. Es gibt keine zweite
vom Chat frei geschriebene Kompetenzdatei und keine Modell-Prozentwerte.

## Tatsächlicher Datenweg

1. `learning_controller.source_state(db, unit)` prüft die konkrete gespeicherte
   Materialrevision und Elternzielrevision. Eine heutige Heftseite ersetzt
   nicht nachträglich die damalige Quellenfassung.
2. `learning_knowledge.catalogue` liest belegte Lernziele. Modellzuordnungen
   behalten `origin` und `status`; Quellenprüfung ist keine Lehrkraftprüfung.
3. `learning_knowledge.evidence` wertet tatsächlich gespeicherte Versuche aus.
   Eine Aufgabe zählt einmal, ihre Versuche zusätzlich. Der letzte Versuch
   entscheidet über das aktuelle Aufgabenergebnis. Bei gleichem Zeitstempel
   gilt die gespeicherte Versuchsnummer vor der zufälligen Datensatz-ID.
4. Selbstständig bedeutet richtig im ersten Versuch ohne erfasste Hilfe.
   Richtig nach Hilfe oder erneutem Versuch bleibt ein unterstützter Erfolg.
   Falsch und unklar werden getrennt gespeichert. Alte Quellenbelege bleiben
   historische Übung, ohne Sicherheit für eine korrigierte Fassung zu behaupten.
   Offene kreative Beiträge und Selbstreflexion mit `open_learning_v1` stehen
   separat als eigene Beiträge. Sie sind weder Bewertungsfehler noch geprüfte
   Erfolge, entwerten frühere Abrufnachweise nicht und verschieben keinen
   Wiederholungsanker. Der Zeitpunkt einer bewertbaren Beobachtung bleibt vom
   letzten beliebigen Beitrag unterscheidbar.
5. Unterschiedliche erfolgreiche spätere Abrufaufgaben liefern datierte
   Prüfnachweise. Die bestehende Produktregel benötigt mindestens drei Tage
   über mindestens sieben Tage. Sie ist keine allgemeingültige wissenschaftliche
   Schwelle. Datum, Umfang und Wiedervorlage bleiben sichtbar.
6. `learning_knowledge.buddy_context` liefert nach Rechteprüfung höchstens zwölf
   relevante Ziele mit Belegzahlen, Prüfdaten, Status und vorhandenen geprüften
   Voraussetzungskanten. Ohne passenden Quellenkontext gibt es nur begrenzte
   tatsächliche Fachbeobachtungen. Eigene Antworten, private Schulnoten,
   Namen und ungeprüfte Eingaben fehlen im Modellkontext.

Folgeübungen erben die belegte Lernzielzuordnung der vorhandenen Lernkette auch
dann, wenn ihr eigener neuer Abschlussbericht noch fehlt. Diese zuvor mögliche
Auswertungslücke wurde korrigiert. Fachlich unterschiedliche Ziele oder
Quellfassungen werden nicht anhand ähnlicher Wörter zusammengelegt.

## Sichtbare und verwendbare Einschätzung

`GET /api/units/{id}/learning-session/knowledge` liefert dieselben Quellenziele,
Beleggruppen und Voraussetzungen für berechtigtes Kind und Familie.
`knowledge_sheet.dart` zeigt sie über „Vorwissen & Lernziele“ im Aufgabenraum
und im Eltern-Einblick. Lesen, Aktualisieren und Aufklappen erzeugen keine KI,
Aufgabe, Lernzeit oder neue Bewertung.

Der Schulbuddy erhält diese Fakten im ausdrücklich reservierten Chat-Auftrag.
Er soll belegtes Vorwissen berücksichtigen und fehlende Nachweise als unbekannt
behandeln. Eine Nachfrage oder Selbstauskunft im Chat bleibt ungeprüft. Ein
neuer Kompetenznachweis entsteht erst durch eine regulär bewertete Aufgabe;
erfolgreiche fachliche Hilfe zählt bei passenden offenen Kinderaufgaben als
Unterstützung. Frühere Antworten werden dadurch nicht umgeschrieben.

Die Voraussetzungskanten sind derzeit ausdrücklich kuratierte Beziehungen
zwischen tatsächlich vorhandenen Quellenzielen, insbesondere Bruchregeln.
Dies ist kein vollständiger Lehrplan für alle Fächer und Klassen. Fehlende
Zuordnungen bleiben sichtbar offen. Der normale Fach-/Themenlernstand enthält
weiterhin alle beantworteten Aufgaben, auch ohne feingranulare Zielzuordnung.

## Prüffälle

`backend/tests/test_buddy_knowledge.py` prüft Quellenbindung, fehlende und
veraltete Belege, selbstständige gegenüber unterstützten Ergebnissen,
zeitgleiche Versuche, Folgeübungen ohne neuen Bericht sowie Datenminimierung.
Zwei ergänzte Fälle prüfen drei sichere Prüftage mit anschließender Reflexion
und eine alleinige Reflexion ohne erfundenen Kompetenz- oder Fehlernachweis.
`backend/tests/test_learning_knowledge.py` enthält den durchgängigen künstlichen
Bruchfall und spätere neue Abrufaufgaben. `app/test/knowledge_sheet_test.dart`
prüft Kategorien, Voraussetzungen, ehrliche Leer-/Quellenzustände, reine GETs
und den Kontowechsel während einer ausstehenden Antwort.

Der erste isolierte gemeinsame PostgreSQL-Lauf dieser beiden Wissensdateien
bestand mit neun Fällen. Der spätere gemeinsame Wort-/Wissensblock bestand mit
44 Fällen; überlappende Läufe werden nicht addiert. Die vier neuen Widgetfälle
sind grün. Das sind synthetische Funktionsnachweise, keine Aussage über den
tatsächlichen Wissensstand eines bestimmten Kindes oder garantierte Lernwirkung.
