# Elternsimulation am 19.10.2026

Getrennte echte Chrome-/Playwright-Sitzung auf der öffentlichen HTTPS-App. Genau eine dafür erzeugte künstliche Demo-Familie; keine echten Familien, Nachrichten, Push-Zustimmungen, Käufe oder externen KI-Aufrufe. Die Zugangsdaten liegen ausschließlich in einer ignorierten 0600-Datei. Die finale Bereinigung wird mit dem Kinderagenten und dem Hauptagenten koordiniert.

## Geprüfter Stand

Live 1.10.0+47, Quellkennung `30d032315afe49d7c5367888c2d2c155db981389`. Die Baseline mit 20 Prüfschritten und der anschließende Elternnachtest mit 30 Prüfschritten waren erfolgreich. Beide hatten keine Browser-Laufzeitfehler und keine fehlgeschlagenen authentifizierten GETs. Der anonyme 401 beim initialen Sitzungscheck vor dem Login ist erwartbar.

| Prüfung | Tatsächlich beobachtetes Ergebnis |
| --- | --- |
| Normale Elternanmeldung über sichtbare Formularfelder | Erfolgreich; ausschließlich Mitgliedschaften der eigenen Kunstfamilie |
| Familien- und Kinderüberblick, 1440 px und 390 px | Nutzbar, keine beobachtete Flutter-Layoutausnahme |
| Kurzer Elternbericht | Gelungenes, App-Fortsetzung und konkrete Elternhandlung getrennt vorhanden |
| Register Heftseiten, Bibliothek und eigene Quellendetails | Durch echte Buttons geöffnet; kein KI-Auftrag |
| Fächerfortschritt und Wortschatz | Eigene Detailseiten erreichbar; kein vorbereiteter externer Kurs behauptet |
| Noten-PDF | Echter Dateidialog, synthetisches A1-PDF mit 249.521 Bytes; drei Einzelnoten in Vorschau |
| PDF-Vorschau ohne Bestätigung schließen | Weiterhin null gespeicherte Noten; Vorschau ist kein Importabschluss |
| PDF nach der Kinderrunde ausdrücklich übernehmen | Drei neue Noten gespeichert; nach Reload erhalten |
| Dieselbe PDF erneut auswählen und bestätigen | Drei bestehende Noten erkannt, null neue angelegt |
| Lernvorgaben öffnen und abbrechen | Mindestziele, Runde, Pause und Tage sichtbar; keine Änderung |
| Mindestziele ausdrücklich ändern | 25 Minuten täglich / 125 wöchentlich gespeichert und nach Reload sichtbar |
| Tatsächliche Kinderzeit beim Zielwechsel | Die gespeicherten 27 Sekunden bleiben 27 Sekunden; Ziele erzeugen keine Zeit |
| Elternfortschritt nach der Kinderrunde | Vier Aufgaben, fünf Versuche, drei alleine und eine mit Hilfe korrekt gelöst |
| Kanonischer Datenabgleich | Familienzähler, Fachfortschritt und gespeicherte Attempts stimmen überein |
| Nur Eltern lesen die fertige Runde | Null neue Antworten, null neue Kindersekunden, keine Anwendungswrites |
| Glocke tatsächlich anklicken | Öffnet die Benachrichtigungsseite; kein Push-Opt-in erteilt |
| Nachrichten und Verlauf | Lesbar ohne Versand, Kinderantwort, Heartbeat oder KI-Auftrag |
| Kosten-/Aufrufkontrolle der Kunstfamilie | `calls_used=0`, leere Usage-Liste, Reservierung 0 |
| Tastatur | Zehn Tab-Schritte mit aktivem DOM-Fokus; Fokusdarstellung und vollständige Tastaturfolge nicht umfassend abgenommen |
| Normales Abmelden über die Oberfläche | Führt zur Anmeldeseite |

## Gemeinsamer Rollencheckpoint während der Runde

Der Kinderagent hatte zwei Antworten gespeichert und einen noch nicht abgesendeten Bruchentwurf serverseitig gesichert. Er schloss und meldete seinen Browser ab, damit keine gleichzeitigen Heartbeats den Vergleich verfälschen.

Danach las die normale Elternsession sowohl die Unit- als auch die Learning-Session-API und öffnete die echte Elternansicht der laufenden Einheit. Der ungesendete Entwurf fehlte in beiden Elternprojektionen. Die zwei Antwortversuche blieben erhalten. Die Elternansicht war schreibgeschützt und erzeugte weder weitere Antworten noch Lernzeit oder andere Anwendungswrites. Erst danach setzte der Kinderagent fort.

## Befunde und Testgrenzen

| ID | Status | Befund / Abnahme |
| --- | --- | --- |
| P-UI-01 | Bestätigte kleine Textschwäche, Hauptagent informiert | Fachfortschritt zeigt bei einer Runde „5 Versuche · 1 Runden“. Zahlen und Einstufung sind korrekt; Singulartext in `practice_evidence.dart` verbessern. Noch keine Nachprüfung einer Korrektur durch diesen Agenten. |
| P-UI-02 | Codeverdacht, nicht live bestätigt | Der Elternüberblick verwendet den Wiederholungstermin stellenweise ohne `friendlyDate`. Der Hauptagent kennt die Stelle; daraus wurde kein bestätigter Laufzeitfehler abgeleitet. |
| P-A11Y-01 | Konkrete Prüflücke | Chrome-CDP `Emulation.setEmulatedOSTextScale(scale:2)` vergrößerte das geprüfte Flutter-Label nicht: 36 px vor und nach dem Wechsel, Faktor 1. Damit ist eine 200-%-Textabnahme im Browser nicht nachgewiesen. CSS-Zoom oder DPR wurden nicht als Ersatzbeleg verwendet. |

Die ersten unterbrochenen QA-Versuche betrafen ausschließlich die Automatisierung: Flutter-ChoiceChips besitzen Checkbox-Semantik, und ein Dialogfuß liegt tiefer als eine zunächst zu strenge Sichtbarkeitsgrenze des Testhelpers. Nach Korrektur der Selektoren und Grenze wurde die vollständige Baseline erfolgreich wiederholt. Daraus wurde kein Produktfehler abgeleitet.

Dies ist keine Prüfung mit einem echten Elternteil oder Kind und kein Nachweis pädagogischer Wirksamkeit. Physisches Android-Gerät, Mikrofon/Ton, tatsächliche Screenreader-Ausgabe, Google-OAuth-Verknüpfung, Push-Zustellung und externe KI-Generierung werden durch diese Elternsimulation nicht geprüft. Native- und Widgetprüfungen anderer Agenten sind separate Belege.

## Reproduktion und Übergabe

`python qa/role_parent_prepare.py` erstellt oder übernimmt exakt die geschützte eigene Testfixture und erzeugt das synthetische PDF lokal. `node qa/role_parent_simulation.mjs` führt die Baseline aus. Der Nachtest verwendet `--after-child` und verlangt die abgeschlossene Runde aus der getrennten geschützten Kinderfortsetzung. Während des isolierten Zeitvergleichs muss die Kinderansicht inaktiv bleiben. Die Skripte lesen keine fremden Konten und ändern keine Systemeinstellungen.

Der Nachtest setzt die Ziele bewusst auf 25/125 und importiert ausschließlich das eigene synthetische PDF. Eine erneute Ausführung erkennt bereits importierte Noten. Die Fixture-PDF wird lokal mit `backend/tests/pdf_fixture.py` und 240 KiB begrenztem synthetischem Padding erzeugt; es ist keine echte Notenübersicht.

Nach der koordinierten Abnahme entfernt `python qa/role_parent_prepare.py --cleanup` ausschließlich diese eigene künstliche Familie über die normale authentifizierte Account-API. Vor dem Löschen werden ihre synthetischen Mitgliedschaften erneut geprüft. Der Agent hat diese Bereinigung noch nicht eigenständig ausgelöst.

Bereinigte Berichte liegen ignoriert und geschützt unter:

- `artifacts/role-parent-result.json`
- `artifacts/role-parent-after-child-result.json`
- `artifacts/role-parent-draft-privacy-result.json`
- `artifacts/role-parent-text-scale-result.json`

Sie enthalten keine Zugangsdaten oder Tokens. Screenshots bleiben ebenfalls ignoriert und geschützt. Neue QA-Dateien wurden mit Ruff beziehungsweise `node --check` geprüft; es wurden durch den Elternagenten keine App-/Backenddateien geändert und keine Commits erstellt.
