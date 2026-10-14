# Projektstand · 14.10.2026 · Version 0.1.0+6

Funktionsfähiger technischer Pilot: https://schulpilot.dorfspy.de . Web und API wurden über die öffentliche HTTPS-Adresse geprüft. Keine Produktionsreife oder Play-Veröffentlichung behauptet; konkrete externe Voraussetzungen stehen unten.

## Implementierter Ausbau

- Nach-der-Schule-Assistent mit Mehrfachauswahl, lokalem Drehen/Zuschneiden, Sortierung und Hinweisen zu kleinen, detailarmen oder identischen Bildern. Bis 24 Seiten pro Tag.
- Begrenzte lokale Upload-Warteschlange, Wiederaufnahme nach Netzfehlern und serverseitige Idempotenz. Keine automatische KI-Wiederholung. Fotos 24 Stunden fortsetzbar, Bereinigung beim nächsten App-/Assistentenstart; Abmeldung löscht sie lokal.
- Tagespakete am selben Tag ergänzbar. Neue Paketversionen erhalten ältere Einheiten und Antworten; bereits verarbeitete Quellenrevisionen werden erkannt. Ergänzungen lassen sich ohne KI-Aufruf für später speichern. Paginierte Tageshistorie und Direktlinks.
- Gespeicherte Einführung vor den Übungen und letzte Aufgabe zum Erinnern. Verwendete Hinweise, Antworten und tatsächliche Aktivitäten bleiben im Elternbereich nachvollziehbar; keine Beherrschung aus einem einzelnen Erfolg abgeleitet.
- Eltern können gespeicherten Stoff mit frühestem Lernbeginn einplanen. Zusammengehörige bestätigte Seiten werden später gemeinsam verwendet. Lernpausen und spätere Starttermine werden im Backend berücksichtigt.
- Vollständig unleserliche Vorlagen erhalten einen eigenen validierten Zustand und müssen ersetzt werden. Kein Erfinden von Unterrichtsstoff oder Hausaufgaben.
- Acht feste künstliche Qualitätsvorlagen, begrenztes Free-Modell-Prüfprogramm, getrennte technische Prüfung der geschützten Providerroute und protokollierte Betreiberfreigabe.
- Authentifiziertes Löschjournal mit transaktionaler Outbox, Wiederherstellungsabgleich, verschlüsselte Offsite-Programme, wöchentliche isolierte Restore-Probe und unabhängige Betriebsprüfungen. Einzelne Verbrauchsmetadaten 90 Tage, Adminaudit 180 Tage, Monatskontingente aktueller plus zwölf vorherige Monate, Löschjournal 35 Tage, Backups 14 Tage.
- CI-Konfiguration mit vollständigen Action-Commit-Pins, vorbereitete deutsche Storetexte/Review-Notizen, dynamische Betreiberangaben und Google-Build-Vorprüfung. Keine Signier-/Deploy-/Provider-Schlüssel in CI.
- E-Mail-Link-Korrektur: Der Flutter-Router erhält `#token=…` beim Start und übergibt den Code an das richtige Formular. Bestätigung, Einladung und Wiederherstellung funktionieren auch nach Neuladen. Neue oder beschädigte Links verwenden keinen alten Code weiter. Geheimnisse bleiben außerhalb von HTTP-Anfragen und Zugriffslogs.

Bestehende Funktionen erhalten: echte Elternregistrierung/Verifikation/Wiederherstellung über eingerichtetes Gmail-SMTP, unabhängige Kinderzugänge, berechtigte Familieneinladungen, Rollen-/Familientrennung im Backend, widerrufbare Sitzungen, Admin-CLI mit TOTP, vier interaktive Aufgabenarten, Elternübersicht/-planung, Hinweise/Familienhilfe, aktive Zeit als Näherung, Wiederholungen, Kontingente/atomare Kostenreservierungen/Notfallstopp, private Materialien, Export und Löschung. Android-/Web-Push ist vorbereitet und bleibt ohne Firebase-Konfiguration ausdrücklich nicht verfügbar.

## Tatsächlich geprüft

- Vollständiger PostgreSQL-Lauf: **77 Tests bestanden** auf separater Testdatenbank. Einschließlich Rollen-/Familientrennung, Kontingenten unter Parallelität, Tagespaket-Ergänzungen, späterem Elternauftrag, Löschjournal und verwaisten Fotos.
- SQLite: vollständiger Lauf mit 76 Tests bestanden; danach sechs gezielte Betriebs-/Aufbewahrungstests einschließlich des neuen Fotobereinigungsfalls bestanden. Umgekehrte Löschjournal-Reihenfolge und Erhalt des Startdatums bei älteren Clients gesondert geprüft.
- Flutter: vollständige Analyse ohne Befunde und **19 Tests bestanden**, darunter die vier neuen E-Mail-Link-Regressionen und Einführung → Übungen → erneutes Öffnen.
- Web-Release, signierte APK und AAB **0.1.0+6** gebaut. APK-Signatur, 16-KB-ZIP-Ausrichtung, acht 64-Bit-ELF-Bibliotheken und AAB mit offiziellem bundletool 1.18.3 geprüft. `jarsigner` bestätigt die AAB-Signatur mit den bekannten Hinweisen zum eigenen Zertifikat/AGP-Manifest.
- Acht künstliche Vorlagen vorbereitet, 13 ausdrückliche Live-Inferenzversuche durchgeführt. Zwölf strukturell angenommen, einer verworfen; dabei zwölfmal gemeldete Kosten 0 und einmal unbekannte Kosten. Fachliche/grammatische Grenzen offen dokumentiert: [QUALITY.md](QUALITY.md).
- Geschützte Route beider konfigurierter Free-Endpunkte ausdrücklich mit künstlichen Daten geprüft: jeweils HTTP 404. [APPROVALS.md](APPROVALS.md).
- Öffentliche API-/Browsertests: getrennte Eltern-/Kinderzugänge, vier Aufgabenarten, gespeicherte Antworten/Hinweise, Elternverlauf, Planung, Export, Widerruf und Löschung. Mehrseitiges Tagespaket mit drei echten kostenlosen KI-Aufrufen erzeugt; beide Quellen erhalten. Browserprüfung des Assistenten einschließlich Direktlink, 390-Pixel-Ansicht, Hilfe/Antwort und Elternansicht ohne Laufzeitfehler bestanden.
- Android-Emulator API 36: Eltern-/Kinderlogin, sichere Sitzungswiederaufnahme, Hilfe/Antwort, Widerruf und Löschen sowie Tagesassistent mit zwei gespeicherten Seiten auf APK 5 bestanden. APK 6 anschließend als signiertes Update installiert, Versionscode und nativen Start geprüft. Kein physischer Kameratest behauptet.
- Echte Gmail-Zustellung und Browserformulare auf öffentlicher Version 6: **Bestätigung, Einladung und Passwortzurücksetzung automatisch vorgefüllt, neu geladen und erfolgreich abgesendet**. Einmalverwendung, begrenzte Einladungsrechte und Sitzungswiderruf nach Passwortwechsel ebenfalls geprüft. Eigene Testkonten anschließend bereinigt.
- Tatsächliche APK-Browserdownloads vor/nach Login auf Version 5 mit Prüfsummenvergleich bestanden; Download vor Login auf Version 6 ebenfalls mit aktuellem Manifest abgeglichen. Eine zusätzliche Demo-Anlage für den erneuten Downloadtest wurde korrekt mit HTTP 429 begrenzt. Öffentlicher Download und Release-Manifest liefern Version 6.
- Begrenzter Parallelitätstest: 48 Abrufe mit vier Clients, 48-mal HTTP 200; p50 65,24 ms, p95 98,81 ms, Maximum 104,46 ms. Rollenprüfung 403, fremdes Kind 404, anonym 401, zu großer Chunked-Body 413. Keine Aussage zur maximalen Betriebskapazität.
- Isolierte PostgreSQL-Wiederherstellung aus tatsächlich verschlüsseltem Backup: Schema 0005, 20 signierte Löschjournal-Einträge geprüft, nachträglich gelöschte Testfamilie einschließlich drei Materialdatensätzen und zwei Fotos entfernt. Alte Sitzungen/Tokens widerrufen, KI-Notfallstopp gesetzt, temporäre Datenbank wieder entfernt; produktive Datenbank nicht überschrieben.
- Root-Timer und unabhängige User-Timer für Sicherung, Restore, Offsite und HTTPS-Prüfung aktiviert. Verschlüsselte Offsite-Kopien mit Größen-/SHA-Abgleich und Rückmeldung an den Server tatsächlich gezogen. Neutraler Operator-TEST-Alarm über Gmail STARTTLS zugestellt und per Read-only-IMAP bestätigt.
- Quellcode und tatsächliche Release-Artefakte gegen die autorisierten Projektgeheimnisse geprüft: kein Treffer. Kein Force-Push und keine fremden Änderungen übernommen.

Reproduzierbare Prüfscripte liegen unter `scripts/`, Browser-/Androidprüfungen unter `qa/`; lokale Berichte und künstliche Screenshots unter dem ignorierten `artifacts/`. Zugangsdaten und Signierschlüssel werden nicht versioniert.

## Konkrete verbleibende Voraussetzungen

1. **Technisch geeigneter KI-Endpunkt für echte Inhalte.** Die Anbieter-/Datenschutzfreigabe wurde ausdrücklich erteilt. Die aktuellen kostenlosen Endpunkte akzeptieren die vorgesehene Data-Collection-Deny-/ZDR-Route nicht. Kein stiller Wechsel zu einem anderen oder bezahlten Anbieter.
2. **Firebase-/Play-Projektzugänge.** Projektkennungen, VAPID, eigenes FCM-Dienstkonto und berechtigter Play-Console-Zugang fehlen. Keine tatsächliche Push-Zustellung, kein Console-Upload und keine Storefreigabe behauptet.
3. **Verbindliche Betreiber-/Supportangaben.** Name, ladungsfähige Anschrift und Supportadresse fehlen noch. Konfiguration und Anzeige sind vorbereitet; keine Angaben erfunden.
4. **Physische Geräte und begleiteter Familientest.** Emulator-/Browserprüfungen ersetzen weder Kamera-/Speicher-/Netztests auf einem echten Telefon noch pädagogische Abnahme. Echte Handschrift bleibt gesondert zu prüfen.
5. **Zahlungsbetrieb.** Tarifberechtigungen und Kostenlimits bestehen; Checkout, verbindliche Preise und Zahlungsanbieter-Konto fehlen. Keine Käufe, Rechnungen oder erfolgreiche Zahlungen vorgetäuscht. Android enthält keine Kaufaufforderung; Play-Zahlungsregeln vor einer späteren Integration beachten.
6. **Codex experimentell.** Kein aktiver Lernworker mit Entwicklungsrechten; isolierte Laufzeit und separate Authentifizierung weiterhin erforderlich.
7. **GitHub Actions gesperrt.** Push nach `main` funktioniert. GitHub startet die CI-Jobs wegen einer Abrechnungssperre des Kontos nicht (Run 38549619683, beide Jobs ohne Schritte). Originalmeldung: „The job was not started because your account is locked due to a billing issue.“ Die oben aufgeführten Tests wurden lokal beziehungsweise auf der separaten Server-Testdatenbank ausgeführt.

## Dateien und sicherer Zugang

APK: `artifacts/schulpilot-0.1.0-test.apk`, AAB: `artifacts/schulpilot-0.1.0-upload.aab`, jeweils lokal und absichtlich nicht versioniert. APK 0.1.0+6: 60.254.748 Bytes, SHA-256 `42bac74adfd1a7d75720d6bd7a84ff42bb0a2a3674f23b640b6823cac8f4bc65`. Download: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk . Startseite und Dashboard verlinken dieselbe Release-Datei.

Erstadmin ohne Standardpasswort: `ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin'`; eigenes Passwort und TOTP interaktiv bestätigen. Technische Einrichtung: [OPERATIONS.md](OPERATIONS.md), [GOOGLE_PLAY_PUSH.md](GOOGLE_PLAY_PUSH.md), [AFTER_SCHOOL.md](AFTER_SCHOOL.md).
