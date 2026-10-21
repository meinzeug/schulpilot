# Eltern- und Kinderprüfung · Version1.17.3+73

Erneute Prüfung der gemeinsamen Flutter-App und des bestehenden Backends am
21.10.2026. Drei Agenten prüften Elternplanung, Hausaufgaben und Lernnachweise;
Integration und Browserbedienung erfolgten im Hauptauftrag. Keine neuen Pakete,
Providerprompts, Dienste, Budgets oder Freigaben.

## Gefundene Fehler und Verhalten

| Ausgangslage | Korrektur | Nachweis |
| --- | --- | --- |
| Alte offene Runde hinter mehr als zehn neueren Runden | Offene aktuelle Auftragsrunde unabhängig von der begrenzten Verlaufsvorschau suchen | `test_parent_plan_audit.py` |
| Älterer KI-Kurzplan hinter mehr als zwanzig Runden ohne Plan | Gespeicherten Plan vor der Begrenzung filtern | derselbe gefüllte Fall |
| Thema lässt sich in neuer Planung nicht erledigen | Ausdrücklicher Abschluss mit optionaler CAS-Revision; Antworten bleiben, keine Beherrschungsbehauptung | Eltern-API, Widget und Browser |
| Anderer Kindername bleibt während Nachladen sichtbar | Vorherigen Namen beim Kinderwechsel sofort entfernen | Eltern-Widget |
| Lernkompass unter Detailroute stoppt dauerhaft | Reine GET-Aktualisierung bei Rückkehr; überdeckte Route pollt nicht | Kompass-Widget |
| Alte Antwort ohne UnitSource erhält heutige Quellenrevision | Historische Übung erhalten, aktuelle Kompetenzbelege nur mit expliziter gültiger Quellenrevision | `test_learning_knowledge.py` |
| Aufgabenanalyse fällt aus vierzig Gesprächsschritten heraus | Aktuelle Übersicht zusätzlich laden, ohne KI-Auftrag | Hausaufgaben-API mit über hundert Schritten |
| Hinweis-/Analysecache fällt aus hundert Kandidaten heraus | Begrenzte gezielte Abfragen nach aktueller Quelle/Analyse/Aufgabe | Wiederholung ohne zusätzliche Jobs/Usage |
| Neue Auswahl oder Häkchen gehen bei laufendem Save verloren | Unveränderliche Zustandsbilder seriell mit aktueller CAS-Revision speichern | Widget mit verzögertem PUT und Verlassen |
| Alte Analysehilfe oder Häkchen nach Quellenkorrektur sichtbar | Aktuelle Quellenrevision und Analyse-ID vor Darstellung prüfen | API-/Widgetfälle |
| Hausaufgabenkamera hat keine Android-Wiederherstellung | Bestehenden Plattformrückgabepfad an Konto, Kind und Zweck binden; bewusster Zuschnitt, kein automatischer Upload | Kamera- und Crop-Regressionen |
| Kontowechsel kann wiedergefundene RAM-Fotos erhalten | Fotos/Zweck/Marker auch in `AppState.accept` löschen | eigener Kontowechselfall |
| Kontowechsel während Fotoabgabe kann neue lokale Eigentümer-ID übernehmen | Stabilen Kontoinhaber und Generation nach asynchronen Schritten erneut prüfen | Galerie- und Kamera-Regressionsfälle |
| SQLite-Installation scheitert an separatem ALTER-Fremdschlüssel | Nullbare Referenz direkt an neuer Spalte anlegen; keine Tabellenkopie, PostgreSQL-Pfad unverändert | Befülltes Upgrade/Downgrade/Upgrade beider Dialekte |

Nützliche kleine Ergänzung: tatsächlicher Stand „x von y selbst abgehakt“ und
ausdrückliche Aktion „Nächste offene Aufgabe“. Kein automatischer Aufgabenwechsel,
KI-Aufruf oder Kompetenznachweis durch ein Häkchen.

## Browser und Daten

Bestehender produktiver Kinderzugang nur lesend: Heute/Kurzplan, Lernen,
Wörter, Hefte und Hausaufgaben. Keine künstlichen Antworten im echten Profil.
Schreibende Bedienproben ausschließlich im isolierten lokalen Eltern-/Kinderkonto
mit künstlichen Daten und gespeicherten künstlichen Antworten aus der vorherigen
Abnahme. Kein lokaler Worker oder Providerzugang. Diese Probe ist keine neue
KI-Generierung und kein neuer Produktionsupload.

Tatsächlich bedient: Anmeldung/Kontowechsel, zweites Hausaufgabenthema auswählen,
eigenen Entwurf schreiben und abhaken, Reload mit erhaltener Auswahl/Eingabe,
mobile Navigation/Konto/Versionsanzeige, Eltern-Thema bestätigen und anschließend
unter abgeschlossenen Themen wiederfinden. 390px und Desktop, hell und dunkel.
Screenshots liegen lokal unter `artifacts/review73/`; ausschließlich künstliche
Inhalte. Keine neue physische Android-Kamera-, vollständige WCAG- oder
Lernwirkungsabnahme. Ein wiedergefundenes Heftfoto wird vor Übernahme weiterhin
bewusst im geöffneten Schultag geprüft; historische Tageszuordnung wird durch
den Zweckmarker allein nicht rekonstruiert.

## Prüfungen

133 gemeinsame Backendfälle auf isoliertem PostgreSQL16 bestanden, einschließlich
beider befüllter Migrationswege. Der zusätzliche ursprüngliche SQLite-Replay
0001→head bestand im separaten Migrationslauf. 1035Fluttertests bei Integration
bestanden; danach ergänzte Kamera-/Kontowechsel- und Import-Race-Fälle werden in
gezielten Abschlussläufen geprüft. Keine Addition überlappender Läufe.
Konkrete abschließende Zahlen, signierte Builds und Produktionsstand in STATUS.md.

Keine neuen OpenRouter-Aufrufe für diese Reparaturen. Echte frühere KI-Prüfungen
und deren Verbrauch bleiben separat in HOMEWORK.md/PARENT_LEARNING.md erhalten.

Die Prüfung ist keine Behauptung, dass jede mögliche Kombination aller
Appfunktionen fehlerfrei sei. Weiterführende Produktideen: Hausaufgaben mit
ausdrücklich bestätigtem Fälligkeitsdatum und gezielte Rückmeldung des Kindes,
welche Erklärung geholfen hat. Beides sollte ohne automatische KI-Aufrufe beim
Lesen oder zusätzliche Pflicht-Aufgabenberge gestaltet werden.
