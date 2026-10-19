# Praxistest Build 42/43 – Arbeits- und Abnahmeprotokoll

Ausgangspunkt: `main b1c3d35`, produktiver Code `9131cce`, App `1.9.0+43`.
Auftrag: aktueller Desktop-Praxistest vom 19.10.2026, acht Aufgaben, zehn
Prüfungen, drei Runden. Antworten des Testers sind keine Fähigkeitsdiagnose.
Die drei historischen HTML-Dateien liegen in Downloads und wurden lokal
eingelesen; historische Zuordnungen stehen in TEST_REPORT_REVIEW.md und
FACHTEST_2026_10_19.md. Keine echten Kinderantworten zu Testzwecken geändert.

| ID | Beobachtung / aktueller Befund | Ursache / Änderung | Abnahme / Stand |
|---|---|---|---|
| P01 hoch | `Swimming pool` falsch, `swimming pool` richtig. Im aktuellen Regelpfad bestätigt. | Zielbezogene englische Anfangsbuchstabenregel; ausdrückliche Großschreibziele bleiben strikt. NFC, Whitespace und freigegebene Varianten erhalten. Konkrete Großschreibungsdimension und passender Hinweis. | Sprachmatrix bestanden: Englisch/Deutsch/Französisch, Varianten, Apostrophe, Akzente und absichtlich falsche Wörter. Alte Attempts bleiben erhalten. |
| P02 hoch | Bruchnotation funktioniert bereits. Lange Erklärungen und fehlende Biologiegraphik sind im bisherigen Renderer nachvollziehbar. | Kleinere Textschritte; drei bewusst gesteuerte Bruchbalkenschritte. Bestehende versionierte Fachdaten um endliche Wurzel-/Bestäubungsschemata ergänzen, solution bleibt vor Antwort/Hilfe verborgen. | Schmale/200%-Renderer- und Offenlegungstests in Arbeit. Keine vollständige Fachabdeckung behauptet. |
| P03 hoch | Hilfedialog lädt bisher Rundenprosa, kombiniert aber Grafik der aktuellen Frage. Codefehler bestätigt, unabhängig vom unbekannten ursprünglichen Zustand. | Optionaler validierter Aufgabenbezug am bestehenden Erklärendpunkt; aktuelle Aufgabe und Zahlen liefern. Legacy-Endpunkt bleibt bedienbar. | API-Matching bestanden: `1/3+1/6` statt fremdem Beispiel; Hilfe verändert die zweite Frage nicht. |
| P04 hoch | Generische Falschantwort bei falsch addierten Nennern bestätigt. | Deterministische Fehlererkennung mit geprüftem Lösungsschlüssel und unterschiedlichen Folgetipps. Keine Ähnlichkeitsakzeptanz. | `3/9` bei `1/3+1/6`, unterschiedliche Tipps, `6/16=3/8` sowie Inhalts-/Formtrennung bestanden. |
| P05 mittel | Vorgeschichte der Originalrunde unbekannt; widersprüchliche Beschriftung ist kein Nachweis falscher Speicherung. | Gespeicherte support_reasons in Kinder-/Elternrückblick zeigen; weitere Versuche, Hinweise, Erklärung, Vorlage und STT getrennt. Keine nachträgliche Umwertung. | Synthetische Gründe, Elternlesen ohne Aktivitäten und Verlauf prüfen. Originalrunde ohne konkrete ID nicht geprüft. |
| P06 hoch | Aktueller Code enthält bereits einen internen Dialog; `about:blank`-Ursache noch nicht reproduziert. Vorschaufehler blieb bisher ein stummes Symbol. | Authentifizierte NotebookPhoto-Ansicht mit Retry/Zoom/Zurück wiederverwenden; lokale Entwürfe sichtbar vorsehen. Gespeichert/vorgemerkt/frei gemeinsam anzeigen. Zuschnitt/Drehen vor Upload existiert bereits. | 21+3 Seiten, gespeicherte Entwürfe, Retry und Kontowechsel im Widget/Browser prüfen. |
| P07 mittel | Fachtexte und Satzanleitung bei Buchstabenhilfe bestätigt. | Vertraute Wörter, Einzelentscheidung, zurückgestellte Importpaare persistent im vorhandenen Importmodell. Sichtbarer Baustein-Rückschritt; Quelle bleibt erhalten. | Teilbestätigung, Wiederholung und spätere Bestätigung sowie Buchstabenhilfe prüfen. |
| P08 mittel | Startseitenhilfe öffnet bisher sofort Elternnachricht. Fehlende Meldungsarten bestätigt. | Erst Erklärung/Aufgabe/Technik/Eltern wählen. Empfängergruppe und Nachricht vor Versand sichtbar. Neue Meldungsarten mit geprüftem Fragebezug. | Ohne Auswahl kein Versand; Rechte und Fokus/Touch prüfen. |
| P09 mittel | Wiederholungen können eigenständige Runden mit gleicher Thematik sein. Keine Historie löschen. | Opt-in-Leseprojektion gruppiert vor Pagination; alle ursprünglichen Runden/Termine bleiben erreichbar. Pflichtaufträge und begonnene Runden separat. Mengen/Datum verständlicher. | Gruppierung, stable Paging, Leere-/Einzahlfälle prüfen. |
| P10 hoch | Uhr bereits in +43 als Klartext behoben. Ursprünglicher unlesbarer Serverbody nicht reproduziert. | 204 ohne JSON korrekt behandeln; unterbrochene/ungültige Antworten mit Wiederaufnahmepfad melden. Keine automatische POST-Wiederholung. Technischen Tagesfehler im Kinderbereich übersetzen. | Idempotenz/Pendingfeedback/Netzfehler/Resume/Zeitregressionen. |
| P11 | Desktopbericht ist keine native Audio-/Smartphone-/Screenreaderabnahme. | Gezielte Widget-, Semantik-, Tastatur-, TTS-Steuerungs- und Emulatorprüfungen. | Noch auszuführen; physisches Gerät ist bisher nicht verbunden (`adb devices` leer). |
| P12 kritisch | Nachgereichter Eltern-PDF-Upload liefert500. Mit eigener künstlicher249.521-Byte-PDF öffentlich reproduziert. Journald meldet zweimal ProgrammingError. | Seit `aefbe4a` irrtümliche `GradeImport.source_blocks`-ORM-Spalte, die Migration0022 nur an materials anlegt. Produktionsmetadaten bestätigen das Fehlen bei grade_imports. Unbenutzte ORM-Spalte entfernt; kein ALTER/DROP und keine Notenänderung. | 55 Noten-/PDF-/Migrationsregressionen bestanden, einschließlich aller ORM-Spalten gegen Alembic head und Upload über234KB. Öffentlicher Wiederholungstest nach Deployment folgt. |

## Fortsetzung

- Implementiert: Kernänderungen P01–P10; keine Schema-Migration, keine neuen
  Provideraufrufe und keine Änderung an Kontingenten oder echten Familien.
- Bestanden:268 isolierte PostgreSQL-Regressionen und323 Fluttertests;
  zusätzlich39 Fluttertests nach genauerer Unterstützungsdarstellung. Analyse und
  Ruff ohne Befund. Neun neue Renderer-/Interaktionstests nach visueller Korrektur
  erneut bestanden. Bekannte Starlette/httpx-Warnung, keine Paketmigration.
- Laufend: PDF-/Migrationsregression und signierter Release44. Danach öffentliche
  Browser-/Android-Emulatorabnahme nur in der eigenen künstlichen Familie und
  abschließender PDF-Wiederholungstest. Ergebnisse nicht vorwegnehmen.

## Fachdarstellungen

Die zusätzlichen lokalen Schemata sind erklärende App-Bausteine, keine neuen
Fotoinhalte oder automatisch aktivierten Kurse. Sie erscheinen nur bei passenden
gespeicherten Fachbelegen und nur nach absichtlicher Hilfe/abgeschlossener Antwort.
Bestäubung (Pollen auf Narbe) und Befruchtung (Verschmelzung männlicher Keimzelle
mit Eizelle) bleiben getrennte Schritte. Quellen: [RHS Wasseraufnahme](https://www.rhs.org.uk/advice/understanding-plants/how-plants-absorb-water),
[RHS Lehrplan: Bestäubung und Befruchtung](https://www.rhs.org.uk/education-learning/pdf/qualifications/level-2/q-qao-qualification-specification-level-2-popg.pdf).
Keine fremden Abbildungen oder Kursinhalte übernommen.
