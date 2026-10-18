# Fuxnoten-PDFimport

## Ablauf

Eltern öffnen **Noten & Lernschwerpunkte → PDF importieren**, wählen die
Fuxnoten-Notenübersicht des aktuellen Schuljahres und prüfen die Vorschau für
das ausgewählte Kind. Neue Noten sind vorausgewählt. Bereits zugeordnete
Noten bleiben erhalten. Mögliche Überschneidungen mit manuellen Einträgen
und geänderte Quellwerte müssen ausdrücklich geklärt werden. Erst **Auswahl
übernehmen** speichert Noten. Keine zusätzliche KI und keine automatischen
Lernaufträge; die bestehende ausschaltbare Notengewichtung verwendet danach
die gespeicherten Einträge innerhalb unveränderter Lernzeitziele.

Die gelieferte A1-PDF besitzt zwei Halbjahre mit jeweils zwei Klassenarbeits-
und fünfzehn sonstigen Notenspalten. Die sichtbaren Ø-/Gesamtnoten sind keine
zusätzlichen Einzelnoten. Einzelne Bewertungsdaten, konkrete Prüfungsarten
innerhalb „sonstige Leistungen“ und Gewichtungen stehen nicht darin:

- Datum bleibt `NULL`, Schuljahr und Halbjahr erhalten.
- Sonstige Leistung bleibt `other`, nicht automatisch „mündlich“ oder „Test“.
- Gewicht1 ist ein sichtbarer Vorschlag; pro Gruppe1–5 vor Import einstellbar.
- Keine regionale Halbjahresgrenze erraten. Der Schuljahreswechsel am1.August
  ist die dokumentierte Kalenderkonvention; die PDF-Jahresangabe muss passen.
- Bis fünf datierte Noten pro Fach aus90Tagen und undatierte Einzelnoten des
  aktuellen Schuljahres informieren die bestehende Planpriorität. Sobald
  undatierte Werte enthalten sind, wird kein zeitlicher Trend behauptet.

## Erkennung und Grenzen

`grade_pdf.py` verwendet pypdf6.21.1 ausschließlich lokal, ohne OCR oder
PDF-Ausführung. Erlaubt sind unverschlüsselte PDFs bis6MB/sechs Seiten mit
vollständig erkanntem Fuxnoten-Spaltenraster und eindeutigen Fachzeilen.
Noten1–6 und explizite Dezimalwerte werden gelesen, keine Umdeutung von
Plus-/Minuszeichen. Unbekannte Strukturen, unzuordenbare Zeilen oder
mehrdeutige Zellen brechen den Import ab; keine teilweise stille Übernahme.
Reine Bildscans werden ausdrücklich abgewiesen.

Ein eigener Unterprozess erhält keine Betriebsumgebung oder Schlüssel,
höchstens512MB und8CPU-Sekunden; die API begrenzt zusätzlich auf12Sekunden.
Dateiname, PDF-Personenkopf und Roh-PDF werden nicht gespeichert. Gespeichert
werden nur bestätigbare Notenzeilen und der Dateihash. Fehlermeldungen enthalten
keine Parserauszüge. Android verwendet die Systemdateiauswahl ohne neue
allgemeine Speicherberechtigung; Web den Browser-Dateidialog.

## Identität und Wiederholung

Eine Quellenposition wird durch Anbieter/Parserfassung, Kind, Schuljahr,
Fachschlüssel, Halbjahr, Leistungsgruppe und Spaltennummer identifiziert.
Ein weiterer identischer Upload erzeugt deshalb keine weitere Note. Gleicher
Uploadschlüssel mit anderer PDF:409. Ein erneut bestätigter Import mit exakt
derselben Auswahl liest das gespeicherte Ergebnis; andere Auswahl:409.

Die PDF liefert keine unabhängigen Prüfungs-IDs. Eine gleiche Zahl allein ist
deshalb kein sicherer Dublettenbeweis. Manuelle Einträge mit passendem Fach,
Wert, System, Gruppe und Schuljahr werden als mögliche Zuordnung angeboten.
Ein manueller Eintrag darf höchstens eine Quellposition belegen. Zwei echte
gleiche Noten bleiben zwei Noten. Falls eine Spalte später einen anderen Wert
enthält, muss der Elternteil Aktualisieren oder Behalten auswählen. Kein
stilles Überschreiben eigener Themen, Notizen, Termine oder Lernziele.

Manuelle Korrektur bleibt bei unverändertem Quellwert bestehen. Ein gelöschter
Eintrag und bewusst ausgelassene Positionen werden nicht automatisch neu
angelegt. Fehlende Positionen eines späteren PDFs löschen keine vorhandenen
Noten. Geänderte Noten/Zuordnungen seit der Vorschau sperren die Bestätigung:
Vorschau ausdrücklich neu laden, nochmals entscheiden. Child-Sperre,
Notensperren in ID-Reihenfolge und eindeutige Constraints serialisieren
Parallelität. Eine verlorene Antwort darf bewusst mit derselben Operation
wiederholt werden, ohne doppelte Noten.

## Rechte, Daten und Migration

Nur berechtigte Eltern mit Verwaltungsrecht importieren/bestätigen. Eltern
mit Leserecht dürfen die eigene Familienvorschau lesen. Kinder, Betriebsadmins
und fremde Familien sind gesperrt. Sitzung und Familienrecht werden nach
dem PDF-Parsing erneut geprüft. Familienzuordnung stammt ausschließlich aus
der vorhandenen Sitzung und dem berechtigten Kind.

Alembic0017 folgt0016. Vorhandene Noten und Datumswerte bleiben erhalten.
Neue Tabellen: `grade_imports`, `grade_source_slots`; zusätzliche optionale
`school_year_start`/`semester` an `school_grades`, `assessed_on` darf bei belegtem
Halbjahr fehlen. Constraint `ck_grade_known_period` verhindert völlig unbekannte
Zeiträume. Ältere Clients lesen bestehende Einträge weiter; das Bearbeiten
undatierter PDF-Noten benötigt `grade-pdf-v1`, damit kein Defaultdatum erfunden
wird. Normale alte datierte Noten bleiben bearbeitbar.

Export enthält Noten, Importbelege und Quellenpositionen. Kinder-/Familien-
löschung entfernt sie über bestehende Fremdschlüssel/Löschjournalwege.
Unbestätigte Vorschauen nach sieben Tagen, Noten/angewendete Importbelege und
Zuordnungen nach365Tagen entfernen. Bestehende Backups höchstens14Tage und
Löschjournal bei Wiederherstellung abgleichen.

## Einrichtung, Prüfung und Rückweg

Normales Deployment installiert die aktualisierten fixierten Locks und führt
`python -m alembic -c backend/alembic.ini upgrade head` mit Dienstumgebung aus.
Kein eigener Dienst und kein externer Provider nötig. Lokale Prüfungen:

```bash
TMPDIR=/dev/shm .venv/bin/python scripts/test_postgres.py backend/tests/test_grade_pdf_imports.py backend/tests/test_grade_migration.py backend/tests/test_grades.py backend/tests/test_integrity.py
cd app
~/.local/share/schulpilot-flutter/bin/flutter test --no-pub test/grade_pdf_test.dart test/progress_grades_test.dart
```

Die PostgreSQL-Migrationsprüfung legt ausschließlich im isolierten `_test`-
Cluster ein temporäres Schema an, übernimmt eine datierte Altnote, importiert
eine undatierte Note und prüft den Schutz gegen einen Datenverlust beim
Downgrade. Produktion niemals als Testdatenbank verwenden.

Vor Aktivierung die normale Sicherung prüfen. Bei Rückweg das additive Schema
erhalten und Vorwärtskorrektur bevorzugen; alte Clients kennen den Importbutton
nicht. Datenbank-Downgrade auf0016 wird bei undatierten Noten abgewiesen, statt
Bewertungsdaten zu erfinden oder Noten zu löschen. Tatsächlich aktivierter
Release, vollständige Test-/Buildzahlen und Web-/native Abnahme: STATUS/Handoff.
