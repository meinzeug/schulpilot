# Betreutes Weiterlernen

Nach einer abgeschlossenen Einheit endet der Lernweg nicht beim Ergebnisbildschirm. Das Backend speichert die letzte Antwort zuerst und bereitet danach genau einen KI-Rückblick vor. Der dauerhafte Worker verwendet die bestätigten Quellen, Aufgaben, tatsächlichen Antworten, Fehlversuche und genutzten Hilfen. Keine Namen, Familienkennungen oder Zugangsdaten gehören in diesen Lernprompt.

Die Gesamtzusammenfassung, der nächste Lernschritt und Fortschrittskriterien werden serverseitig aus gespeicherten Beobachtungen berechnet. Die KI erklärt schwierige Schritte und bespricht jede beantwortete Aufgabe. Bei Bedarf entsteht auf ausdrückliche Aktion eine getrennt reservierte Anschlussrunde mit zwei neuen Aufgaben. Sie kann keine Beherrschung erklären oder verbindliche Elternziele verändern. Bekannte richtige/falsche Bewertungen bleiben maßgeblich. Ihre zusätzliche Einschätzung einer offenen Kurzantwort ist ausdrücklich gekennzeichnet und ändert deren ursprüngliche Bewertung nicht.

## Lernfolge

1. **Lernen und üben:** Erklärung lesen, Aufgaben bearbeiten, Hinweise oder Familienhilfe nutzen.
2. **Rückblick:** Gespeicherte Antworten werden kontrolliert. Fehler, Hilfen und unklare Bewertungen bestimmen den weiteren Schwerpunkt.
3. **Gezielt nachlernen:** Eine passende Erklärung und zwei neue Aufgaben greifen die schwierigen Ziele auf. Korrekte Aufgaben aus dem ersten Paket werden nicht einfach als neue Probe wiederholt.
4. **Selbstständig abrufen:** Neue Aufgaben ohne vorgeschaltete Lösungserklärung. Hinweise bleiben erreichbar; wer sie oder die Erklärung nutzt, wird als unterstützt erfasst.
5. **Später wiederholen:** Weitere Abrufproben an späteren passenden Lerntagen. Ausgelassene Tage vervielfachen den Umfang nicht.

Zwei aufeinanderfolgende Runden mit Unterstützungsbedarf oder offenen Bewertungen führen zur Empfehlung, gemeinsam mit den Eltern weiterzulernen. Das Eltern-Dashboard zeigt den Anlass. Ein persönlicher Hilfewunsch wird nur auf ausdrückliche Aktion des Kindes versendet.

Lerntage, Fach-Lerntage, Urlaubs-/Krankheitspausen, Tages-/Wochenzeit und schon eingeplante Einheiten begrenzen die Fortsetzung. Höchstens drei Runden einer Lernfolge pro Tag. Tatsächlich erfasste Aktivität und Pausen gelten auch über Einheitengrenzen. Fehlende Zeit erzeugt einen gespeicherten späteren Vorschlag statt weiterer Pflichtaufgaben.

## Lernziele und Beobachtungen

Jede Lernfolge führt konkrete Ziele mit einem wörtlichen Beleg aus dem bestätigten Material. Bei erkennbaren Bruchregeln werden Benennen von Zähler/Nenner, Addieren, Kürzen und Erweitern getrennt vorbereitet. Bei anderen Inhalten schlägt die KI bis zu vier prüfbare Ziele vor; unbelegte oder zu allgemeine Vorschläge werden abgelehnt. Ein Zielvorschlag ist keine Behauptung, sämtliche Unterrichtsinhalte oder jede mögliche Fähigkeit erkannt zu haben. Eltern können zusätzliche Ziele als Lernauftrag einplanen.

Bereits gespeicherte Ziele bleiben unverändert. Jede neue Aufgabe gehört zu einem Ziel. Die Rückmeldung zu einer bereits zugeordneten Aufgabe erhält ihre Ziel-ID aus der gespeicherten Aufgabe. Bei vollständig bekannten Zuordnungen enthält das Modell-Rückmeldungsschema keine erneute Zielauswahl. Initiale und ältere Fragen ohne gespeicherte Zuordnung werden weiterhin gegen die bestätigten Lernziele geprüft. Erkennbare Bruchoperationen werden zusätzlich fest auf die passende Zuordnung geprüft. Neu vorbereitete Fragen dürfen keine bereits gestellte Frage derselben Lernfolge wiederholen. Quellenrevisionen und Elternvorgaben werden vor und nach dem KI-Aufruf geprüft; geänderte Quellen oder Ziele verhindern die Übernahme veralteter Ergebnisse.

„Gefestigt“ setzt für **jedes** aufgeführte Ziel mindestens drei selbstständige Prüftage über mindestens sieben Kalendertage voraus. Nur neue Abrufproben zählen, jeweils beim ersten Versuch richtig und ohne zusätzliche Hilfe. Mehrere richtige Runden am selben Tag erzeugen keinen zusätzlichen Prüftag. Offene Bewertungen zählen nicht als sicher richtig; Rückschritte setzen die Beobachtungsfolge des betroffenen Ziels zurück. Ein einzelner Erfolg, ein KI-Lob oder bloßes Öffnen der App genügt nicht.

Weitere Wiederholungen bleiben auch nach diesem Zustand vorgesehen. Die Kriterien sind transparente Produktregeln, keine Garantie vollständiger Beherrschung des gesamten Schulstoffs. Fortschritt, Quellenbelege, Rückblicke und konkrete nächste Termine sind für Kind und berechtigte Eltern einsehbar.

## Fehler, Kosten und Datenschutz

Ein automatischer Aufruf je abgeschlossener Einheit; höchstens ein weiterer ausdrücklich angeforderter Versuch bei Fehlern. Beide werden atomar reserviert und mitgezählt. Keine automatischen Anbieterwechsel oder Inferenzschleifen. Providerfehler oder ausgeschöpfte Kontingente verlieren keine Antwort und erzeugen keinen vorgetäuschten Rückblick.

Der OpenRouter-Free-Standard bleibt auf das konfigurierte Modell und den konkreten Upstream mit Preisgrenze 0 und gesperrter Datensammlung begrenzt. Serverseitig bekannte Ziele werden nicht erneut vom Modell erzeugt; die Modellantwort bleibt auf Erklärungen, Einzelrückmeldungen und neue Aufgaben beschränkt. Die feste synthetische Demo hat eine ausdrücklich lokale Begleitung ohne externen KI-Aufruf. Der reguläre Konto-Test verwendet dagegen neue künstliche Fotos und tatsächliche KI-Aufrufe.

Migration `0007` ergänzt Lernfolgenbezüge, Rundentyp, frühesten Abruftermin und Elternzielrevision sowie `unit_coaching`. Rückblicke werden mit der zugehörigen Einheit gelöscht, exportiert und in der Wiederherstellungsprobe überprüft. Private Inhalte bleiben höchstens 365 Tage; verschlüsselte Backups höchstens 14 Tage. Keine zusätzlichen externen Dienste oder Abhängigkeiten erforderlich.

## Prüfungen

- Backend: `backend/tests/test_coaching.py`, Quellen-/Migrationsregressionen in `test_school_day.py` und `test_integrity.py`.
- Flutter: `app/test/coaching_test.dart` prüft Wiederaufnahme ohne erneuten POST, Navigation in die neue Runde, offene KI-Bewertung und schmale Ansicht.
- Regulärer öffentlicher Ablauf: `scripts/prepare_normal_ai_smoke.py`, danach `cd qa && node school_day.mjs --keep-for-native`. Zwei künstliche Fotos, erstes Paket, echter KI-Rückblick, Nachlernen, Abrufprobe und Elternansicht. Zugangsdaten bleiben vorübergehend ausschließlich in der privaten ignorierten QA-Datei.
- Android: anschließend `.venv/bin/python qa/android_school_day.py` auf dem eigenen Emulator; Aufräumen der eigenen Familie mit `.venv/bin/python scripts/prepare_normal_ai_smoke.py --cleanup`.

Tatsächlich ausgeführte Ergebnisse stehen in [STATUS.md](STATUS.md).


## Getrennte Stufen ab 1.1.0

Neue Rückblicke verwenden `defer_practice`: `next_unit` ist im Provider-Schema und nach dem Parsen ausschließlich null. Systemtext enthält keine widersprechenden Generatoranweisungen, unbenutzte Aufgabendefinitionen werden entfernt. Der Rückblick bleibt bereit, auch wenn später neue Aufgaben nicht erstellt werden können. POST `/units/{id}/practice` reserviert den eigenen dauerhaften Auftrag; höchstens zwei bewusste Versuche, keine automatische Wiederholung. Jobstatus/-fehler sind am Rückblick sichtbar. Anbieter- und Modellherkunft des ursprünglichen Berichts bleiben erhalten; reine Übungsvorbereitung zählt nicht als zweiter Rückblick.

Bei alten Einstiegsaufgaben ohne Lernziel-ID verwendet die Schwerpunktwahl ihre geprüfte Zuordnung aus dem Rückblick, ohne die alte Aufgabe oder Antwort umzuschreiben. Elternzeit, Pflichtaufträge, Quellen, Freigaben, Tarif und Anbieterstand werden erneut geprüft. Die Antwortansicht zeigt Rückmeldung bis zur bewussten Fortsetzung, scrollt zur neuen Frage und bietet Vorlesen sowie Fragen zu den eigenen bestätigten Seiten.
