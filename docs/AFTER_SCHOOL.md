# Nach der Schule

Im eigenen Kinderzugang „Nach der Schule starten“ öffnen. Der Assistent speichert pro Kind und lokalem Datum genau einen Schultag. Direktlink: `/after-school/<eigene-Kind-ID>`. Ein Neustart oder zweites Gerät öffnet die gespeicherten Seiten und den aktuellen Schritt.

1. **Seiten sammeln:** Heftseiten nacheinander fotografieren oder aus der Galerie hinzufügen. Vor dem Upload persönliche Angaben lokal abschneiden. Gespeicherte Fotos erscheinen mit Vorschau und Seitennummer. Unbestätigte Seiten lassen sich entfernen und neu aufnehmen. Maximal 24 Seiten pro Tag, Einzelbild maximal 10 MB/16 Megapixel vor serverseitiger Verkleinerung.
2. **Stoff prüfen:** Nach „Alle Seiten sind da“ alle Bilder nacheinander erkennen lassen. Der dauerhafte Worker verarbeitet jede Seite mit einem kontingentierten KI-Aufruf. Fach, Thema, Text, Unsicherheiten und ausdrücklich notierte Hausaufgaben werden je Seite geprüft. Ein Abbruch erhält erkannte Seiten; laufende Aufträge werden angezeigt und nicht erneut gestartet. Noch nicht verarbeitete Seiten lassen sich danach fortsetzen.
3. **Lernen und festigen:** Erst vollständig bestätigte Seiten erlauben die Paket-Erstellung. Zusammengehörige Seiten werden nach Fach gebündelt und gemeinsam an den Aufgabenprovider übergeben. Eine strukturierte Antwort enthält höchstens drei kurze Einheiten mit Erklärung und je zwei bis fünf Aufgaben. Je Einheit etwa acht Minuten, bei kürzerer verfügbarer Zeit mindestens fünf; Elternvorgaben begrenzen die Auswahl zusätzlich. Der Paketaufruf reserviert einen weiteren KI-Aufruf. Fehler erzeugen keine Ersatzübungen oder versteckten Wiederholungen.

Bereits eingeplante verbindliche Eltern-/Hausaufgabenaufträge behalten ihre Zeit. Schwerpunkte, Fach-Lerntage, Lernpausen und Tages-/Wochenumfang begrenzen das Paket. Nicht passende Themen bleiben sichtbar gespeichert. Sie werden weder als gelernt markiert noch täglich zu einem Pflichtberg addiert. Ein Foto belegt nur den gezeigten Ausschnitt; erzeugte Übungen behaupten keine vollständige Hausaufgabenerledigung. Bestätigter Text ist auf insgesamt 60.000 Zeichen begrenzt.

Das Paket öffnet die bestehenden interaktiven Aufgaben. Spätere Wiederholungen übernehmen ebenfalls alle noch verfügbaren bestätigten Quellseiten, nicht nur das erste Foto. Antworten, Hinweise, ungefähre Aktivität und Wiederholungen verwenden dieselbe Speicherung wie andere Einheiten. Die Elternübersicht verlinkt das heutige Paket; alle Heftseiten bleiben erreichbar. Quellenrevisionen und eine Prüfsumme der Elternplanung werden vor/nach dem KI-Aufruf verglichen. Änderungen verwerfen die veraltete Ausgabe vollständig. Kinder-/Familienrechte werden bei jedem API-Zugriff geprüft. Ein fertiges Paket bleibt erhalten; weitere Materialien lassen sich anschließend einzeln importieren.

## Daten und Betrieb

Migration `0004` ergänzt `school_days`, Seitenzuordnungen, Zeitangaben für Einheiten sowie `unit_sources`. Quellenverknüpfungen enthalten IDs/Revisionen, keine zusätzlichen Fotokopien. Export/Löschung umfassen die neuen Datensätze; der 365-Tage-Job bereinigt Schultage. Ein kompatibler Code-Rollback kann zusätzliche Tabellen/Spalten stehen lassen. Vor Migration sichern; ältere Release-Migrationen beim Code-Rollback nicht erneut ausführen.

Android verwendet den Kamera-/Galerie-Picker. Nach systembedingter Beendigung während der Aufnahme wird `retrieveLostData` beim Start geprüft. Wiederaufnahme nur für das zuvor im sicheren Gerätespeicher vermerkte und weiterhin angemeldete Kind. Vor dem Upload Foto erneut prüfen. Keine automatischen Foto-Uploads; Abmelden verwirft die Wiederaufnahme.

## Freigabe und Tests

Echte Kinderfotos bleiben bis zu dokumentierten Datenschutz-/Minderjährigenfreigaben serverseitig gesperrt. Der synthetische Testraum bietet zwei unterschiedliche serverseitig erzeugte Bruchrechnungsseiten. Erkennung und Paket-Erstellung verwenden echte kostenlose OpenRouter-Aufrufe. Der Adapter ersetzt sämtliche freien Aufrufdaten durch feste Testinhalte; Demo-Markierungen erlauben keine externen privaten Eingaben.

- Backend: `backend/tests/test_school_day.py` prüft mehrere Fächer/Seiten, Wiederaufnahme, Bestätigung, Quellen, Elternzeit, Antworten/Hinweise, Export/Löschung, Geschwisterschutz, Datenschutzsperre, Parallelität und atomaren Abbruch bei geänderten Quellen/Vorgaben oder ungültiger Ausgabe.
- Flutter: `app/test/school_day_test.dart` prüft seitenweise Bestätigung auf 390/1280 Pixeln und Wiederaufnahme laufender Aufträge ohne erneuten POST.
- Öffentlicher KI-Test: `.venv/bin/python scripts/public_school_day_smoke.py` (drei mitgezählte kostenlose Aufrufe, ausschließlich feste Testbilder/-texte).
- API-/Browsertest: zunächst obigen Befehl mit `--keep-for-browser`, dann `cd qa && node school_day.mjs`. Private ignorierte Fortsetzungsdatei unter `artifacts/` und eigene Testfamilie werden nach erfolgreichem Browsertest gelöscht.
