# Projektstand · 14.10.2026 · Version 0.1.0+5

Funktionsfähiger technischer Pilot: https://schulpilot.dorfspy.de . Dieser Ausbau wird gerade öffentlich abgenommen; keine Produktionsreife oder Play-Veröffentlichung behauptet.

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

Bestehende Funktionen erhalten: echte Elternregistrierung/Verifikation/Wiederherstellung über eingerichtetes Gmail-SMTP, unabhängige Kinderzugänge, berechtigte Familieneinladungen, Rollen-/Familientrennung im Backend, widerrufbare Sitzungen, Admin-CLI mit TOTP, vier interaktive Aufgabenarten, Elternübersicht/-planung, Hinweise/Familienhilfe, aktive Zeit als Näherung, Wiederholungen, Kontingente/atomare Kostenreservierungen/Notfallstopp, private Materialien, Export und Löschung. Android-/Web-Push ist vorbereitet und bleibt ohne Firebase-Konfiguration ausdrücklich nicht verfügbar.

## Tatsächlich geprüft vor der öffentlichen Abnahme dieses Ausbaus

- Vollständiger PostgreSQL-Lauf: 76 Tests bestanden auf separater Testdatenbank. Nach dem letzten kleinen Löschabgleich-Fix zusätzlich gezielter SQLite-Test mit absichtlich umgekehrter Journalreihenfolge bestanden.
- SQLite: vollständiger Lauf mit 74 Tests bestanden; neue Streamgrößen-, Migrations-, Aufbewahrungs- und Wiederherstellungsprüfungen zusätzlich bestanden.
- Flutter: vollständige Analyse ohne Befunde und 14 Tests bestanden; zusätzlicher Widgettest für Einführung → Übungen → erneutes Öffnen ebenfalls bestanden.
- Web-Release, signierte APK und AAB 0.1.0+5 gebaut. APK-Signatur, 16-KB-ZIP-Ausrichtung, acht 64-Bit-ELF-Bibliotheken und AAB mit offiziellem bundletool 1.18.3 geprüft. `jarsigner` bestätigt die AAB-Signatur mit den bekannten Hinweisen zum eigenen Zertifikat/AGP-Manifest.
- Acht künstliche Vorlagen vorbereitet, 13 ausdrückliche Live-Inferenzversuche durchgeführt. Zwölf strukturell angenommen, einer verworfen; dabei zwölfmal gemeldete Kosten 0 und einmal unbekannte Kosten. Fachliche/grammatische Grenzen offen dokumentiert: [QUALITY.md](QUALITY.md).
- Geschützte Route beider konfigurierter Free-Endpunkte ausdrücklich mit künstlichen Daten geprüft: jeweils HTTP 404. [APPROVALS.md](APPROVALS.md).
- Repository und tatsächliche APK/AAB gegen die autorisierten Projektgeheimnisse geprüft: kein Treffer. Kein Force-Push und keine fremden Änderungen übernommen.

Öffentliche Endabnahme, aktivierte Timer und Wiederherstellung des neuen Schemas werden nach tatsächlicher Durchführung hier ergänzt.

## Konkrete verbleibende Voraussetzungen

1. **Technisch geeigneter KI-Endpunkt für echte Inhalte.** Die Anbieter-/Datenschutzfreigabe wurde ausdrücklich erteilt. Die aktuellen kostenlosen Endpunkte akzeptieren die vorgesehene Data-Collection-Deny-/ZDR-Route nicht. Kein stiller Wechsel zu einem anderen oder bezahlten Anbieter.
2. **Firebase-/Play-Projektzugänge.** Projektkennungen, VAPID, eigenes FCM-Dienstkonto und berechtigter Play-Console-Zugang fehlen. Keine tatsächliche Push-Zustellung, kein Console-Upload und keine Storefreigabe behauptet.
3. **Verbindliche Betreiber-/Supportangaben.** Name, ladungsfähige Anschrift und Supportadresse fehlen noch. Konfiguration und Anzeige sind vorbereitet; keine Angaben erfunden.
4. **Physische Geräte und begleiteter Familientest.** Emulator-/Browserprüfungen ersetzen weder Kamera-/Speicher-/Netztests auf einem echten Telefon noch pädagogische Abnahme. Echte Handschrift bleibt gesondert zu prüfen.
5. **Zahlungsbetrieb.** Tarifberechtigungen und Kostenlimits bestehen; Checkout, verbindliche Preise und Zahlungsanbieter-Konto fehlen. Keine Käufe, Rechnungen oder erfolgreiche Zahlungen vorgetäuscht. Android enthält keine Kaufaufforderung; Play-Zahlungsregeln vor einer späteren Integration beachten.
6. **Codex experimentell.** Kein aktiver Lernworker mit Entwicklungsrechten; isolierte Laufzeit und separate Authentifizierung weiterhin erforderlich.

## Dateien und sicherer Zugang

APK: `artifacts/schulpilot-0.1.0-test.apk`, AAB: `artifacts/schulpilot-0.1.0-upload.aab`, jeweils lokal und absichtlich nicht versioniert. APK 0.1.0+5: 60.254.748 Bytes, SHA-256 `a3b82f37e573da8dbcaeed913f598d7e094d782f03b00896a19e96ab1de33ba3`. Der öffentliche Download wird mit demselben APK vor und nach Web-Login verlinkt.

Erstadmin ohne Standardpasswort: `ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin'`; eigenes Passwort und TOTP interaktiv bestätigen. Technische Einrichtung: [OPERATIONS.md](OPERATIONS.md), [GOOGLE_PLAY_PUSH.md](GOOGLE_PLAY_PUSH.md), [AFTER_SCHOOL.md](AFTER_SCHOOL.md).
