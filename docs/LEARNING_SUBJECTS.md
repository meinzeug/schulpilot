# Lernen nach Fach und Thema

Ab Version1.37.0+151 verwendet Lernen die Fachliste im Stil von Hefte:
dieselben Fachpiktogramme, ruhigen Zeilen und optionalen Hefter-Bildkacheln.
„Meine Fächer“ zeigt Fächer mit vorhandenem Lernstoff, einschließlich früherer
Runden. „Alle Fächer“ erhält den vorhandenen zugänglichen Fachstamm. Suche,
Ansichtswechsel und Lernstand stehen im Dreipunktemenü.

## Ablauf

1. `/learn/{childId}` zeigt ausschließlich Fächer und Themenanzahlen.
2. `/learn/{childId}/subject/{subjectId}` zeigt die Themen des gewählten Fachs.
   Offen, Später und Erledigt bleiben getrennt. Wiederholte Runden eines Themas
   bilden eine Karte; die passendste vorhandene Runde ist direkt erreichbar.
3. „Alle Runden zu diesem Thema“ öffnet die begrenzte Rundenliste mit einem
   Themenhash und erhält den gewählten Reiter. Antworten werden erst in der
   berechtigten Detailansicht geladen.

Im Kinderzugang steht oben „Zufälliges Thema üben“. Die Auswahl erfolgt
gleichverteilt über **alle jetzt verfügbaren Themen des Fachs**, unabhängig von
der angezeigten Ergebnisseite und der Anzahl vorhandener Runden je Thema.
Innerhalb eines Themas haben begonnene Arbeit, verbindliche Aufträge und schon
gespeicherte Runden Vorrang. Zukünftige Elternaufträge und abgeschlossene Runden
werden nicht als sofort startbare neue Runde ausgegeben.

Eine gespeicherte Runde benutzt den bisherigen Startendpunkt. Neue Inhalte
verwenden die vorhandene reservierte Rundenvorbereitung; eine Lernweg-Etappe
verwendet den normalen idempotenten Etappen-POST. Anschließend folgt die
bestehende Statusseite. Die Aktion erzeugt keine automatische Folgerunde und
keinen Anbieterwechsel. Bei laufender Vorbereitung ist ein weiterer
Zufallsstart gesperrt; gespeicherte Runden und die Statusseite bleiben offen.
Eltern behalten die lesende Sicht auf die Runden; der Zufallsstart ist eine
Kinderaktion.

## Daten und Rechte

`library.learning_sections` verwendet den bestehenden individuellen Plan.
`GET /children/{childId}/learning/subjects` liefert Fachmetadaten und
zusammengefasste Themenzahlen. `GET .../learning/subjects/{subjectId}/random`
liefert nur die Auswahl: kein Auftrag, keine Reservierung, keine Aktivität.
Die bestehende Lernsammlung unterstützt zusätzlich `subject_id`, `topic`
und `topic_view`; alte Aufrufe behalten ihre bisherige Form und Paginierung.

Gespeicherte Fach-IDs haben Vorrang; historische Bezeichnungen werden über
den bestehenden Aliasstamm aufgelöst. Es werden keine neuen Fächer aus
Lerninhalten angelegt. Familien- und Kinderrechte werden auf jedem Endpunkt
serverseitig geprüft. Ungeklärte historische Fächer bleiben gesondert erreichbar.
Themenkarten werden vor der Paginierung gebündelt und enthalten höchstens
eine Rundenmetadatenvorschau. Vollständige Quellen, Erklärungen, Aufgaben und
Antworten gehören nicht in die Fachübersicht.

Ansicht und Filter leben ausschließlich im kontogebundenen Arbeitsspeicher.
Kontowechsel verwirft auch verspätete Antworten und Auswahlaktionen. Die
Fach-/Themenansicht übernimmt bestehende Live-Revisionen, ohne Seitenrefresh
oder automatische KI-Erzeugung. Keine Schema- oder Kostenkonfigurationsänderung.

Prüfungen: `test_learning_subjects_151.py` sowie
`learning_subjects_151_test.dart`, vorhandene Bibliotheks-, Sammlungs- und
Workspace-Regressionen. Konkreter Build-/Browser-/Auslieferungsstand in
[STATUS.md](STATUS.md).
