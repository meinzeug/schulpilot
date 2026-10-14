# Projektstand · 14.10.2026 · Version 0.1.0

Funktionsfähiger technischer Pilot mit eigenem Backend und Flutter-Clients. Öffentliche Adresse: https://schulpilot.dorfspy.de . Für echte Kinderdaten und einen kommerziellen Echtbetrieb weiterhin gesperrt; keine Produktionsreife behauptet.

## Implementiert

- Echte Elternregistrierung, E-Mail-Verifikation, Wiederherstellung und adressgebundene Einladungen; fehlender SMTP-Versand wird ausdrücklich als 503 gemeldet. Argon2id, sichere widerrufbare Web-/Android-Sitzungen, getrennte Kinderzugänge ohne Kinder-E-Mail, Rücksetzen ohne Passwortoffenlegung.
- Serverseitige Rollen-/Familientrennung, mehrere Kinder, Leserechte oder Verwaltung für eingeladene Eltern, Sitzungs-/Rechteentzug. Lokaler Erstadmin mit TOTP, Wiederverwendungsschutz und protokollierten Betriebszugriffen; keine Adminansicht privater Kinderinhalte.
- Privater Bildimport mit lokalem Zuschneiden und serverseitiger Metadatenentfernung; serverseitige OpenAI-/OpenRouter-Erkennung und strukturierte Generierung vorbereitet. Bestätigung unsicherer Stellen und gesonderte notierte Hausaufgaben. In der öffentlichen Demo ausschließlich festes synthetisches Material, keine echte OCR oder externe KI.
- Durchgängiges Lernen mit vier Flutter-Aufgabenkomponenten, Erklärungen, Hinweisen, Pause/Fortsetzung, Rückmeldungen und Familienhilfe. Antworten/Unterstützung werden tatsächlich gespeichert. Unsichere freie Antworten werden weder automatisch falsch noch als Verständnisproblem gewertet.
- Familienübersicht und Kinderdetail mit Tages-/Wochenüberblick, Aufgaben/Antworten/Hinweisen/Erklärungen, Aktivitätsverlauf, ungefährer aktiver Lernzeit, offenen Zielen, Prüfungsterminen und späteren Wiederholungen. Ein einzelner Erfolg schließt weder Beherrschung noch ein verbindliches Elternziel automatisch ab.
- Lerntage einschließlich Fach-Lerntagen, Zeitziele, Pausen, Schwerpunkte, konkrete Wiederholungsziele, Aufträge/Termine, Ruhezeiten und In-App-Erinnerungen. Begrenzte Tagespläne, Konflikthinweise und Lernpausen ohne anwachsenden Nachholberg. Quellenrevisionen schützen vor inzwischen geänderten Zielen.
- Austauschbare Provider, verschlüsselte Schlüssel, explizite Modell-/Upstreambindung, atomare Familien-/Unternehmenskontingente, mitgezählte Fehlversuche, unbekannte Kosten mit voller Reservierung, Notfallstopp. Codex-Adapter samt isoliertem Ein-Aufruf-Gateway vorhanden, experimentell und deaktiviert.
- Export/Löschung, 24-Stunden-Testfamilien, Aufbewahrungsjobs. PostgreSQL, Alembic-Migrationen, persistente Daten, systemd, bestehendes Caddy, Let’s Encrypt und geprüfte öffentliche DNS-Auflösung. Verschlüsselte tägliche Sicherungen und dokumentierter kompatibler Code-Rollback.

## Tatsächlich geprüft

| Prüfung | Ergebnis |
| --- | --- |
| Backend mit SQLite | 37 Tests bestanden |
| Backend auf separatem PostgreSQL-Testschema/-DB des Zielservers | 37 Tests bestanden |
| Flutter-Analyse | Keine Befunde |
| Fluttertests | 5 bestanden, einschließlich Kinderstart auf 390 und 1280 Pixel |
| Flutter-Web Release | Erfolgreich gebaut, Ressourcen vom eigenen Server |
| Android Release-Test-APK | Erfolgreich gebaut, APK-Signatur geprüft; nur Internet und interne Receiverberechtigung, keine breiten Speicherrechte |
| Öffentliche HTTPS-API | Materialbestätigung, verbindlicher Elternplan, persistenter Job, Idempotenz, eigener Kinderlogin, Rollenprüfung, alle vier Aufgabenarten, Hinweise, Pause, Elternverlauf, Export, Sitzungswiderruf und Löschung bestanden |
| Echter Browser | Getrennte Eltern-/Kinderkontexte, sichere Cookies, Materialfluss, alle vier interaktiven Aufgaben, Elternverlauf und mobile Ansicht geprüft; keine JavaScript-Laufzeitfehler |
| Sicherung | AES-GCM-Entschlüsselung authentifiziert; PostgreSQL-Dump in getrennte Testdatenbank wiederhergestellt |
| DNS / TLS | Eigener Hetzner-A-Eintrag und autoritative/öffentliche Auflösung geprüft; Let’s-Encrypt-Zertifikat und HTTP-308-Weiterleitung geprüft |

Die Testbibliothek meldet einen bekannten Starlette-Hinweis zur künftigen Testclient-Umstellung von `httpx`. Tests bestehen mit den fixierten Versionen. Externe KI-Aufrufe, reale E-Mail-Zustellung und ein physisches Android-Gerät wurden **nicht** erfolgreich getestet oder vorgetäuscht. Frühe Aktivierungsfehler durch fehlendes Python-Venv-Paket, Caddy-Issuer-Syntax und Systempfad wurden behoben; bestehende Anwendungen blieben erreichbar.

APK: `artifacts/schulpilot-0.1.0-test.apk` auf dem Entwicklungsrechner, absichtlich nicht versioniert. Debug-Testsignierung außerhalb von Git. Öffentliche `/api/health`-Antworten zeigen für die abschließenden Releases die konkrete Commitkennung. Eigene Änderungen werden auf den vorhandenen Branch `main` gepusht; maßgeblich sind Git-Verlauf und öffentliche Versionskennung.

## Offene Voraussetzungen

1. SMTP-Konto/Absender und tatsächliche Ende-zu-Ende-Zustellung einrichten. Bis dahin keine öffentliche echte Registrierung, Einladung oder Wiederherstellung.
2. Separate Betreiber-Providerkeys, konkrete dokumentierte Modelle/Preise und echte synthetische Bild-/Schematests. Keine Kundenkonten oder Entwicklungsauthentifizierung als Ersatz.
3. Datenschutz-/Minderjährigenprüfung einschließlich Verträgen, Rechtsgrundlage, erforderlicher ZDR-/Bildfreigaben, Region/Kontoeinstellungen, Inhalts-/Sicherheitsprüfung sowie Betreiber-/Kontakt-/Impressumsangaben. Ohne Nachweise bleibt echte Verarbeitung gesperrt.
4. Codex-Containerlaufzeit, verifiziertes CLI-Binary, getrennte Authentifizierung, Socket-/Netzwerkisolation und kommerzielle Nutzungsfreigabe prüfen. Der experimentelle Worker ist nicht auf dem App-Server installiert/aktiviert und nicht live getestet.
5. Offsite-Sicherungsziel und belastbarer Löschabgleich für Wiederherstellungen; externer Alarmdienst, Last-/Abuse-Tests und abschließende Aufbewahrungsprüfung der Betriebs-/Verbrauchsprotokolle vor Echtbetrieb.
6. Geräteprüfung der Android-App und verwaltete Produktionssignierung vor einer späteren Store-Veröffentlichung. Kein Play-Store-Upload erfolgt. Checkout, Push-Erinnerungen und fachliche Qualitätsabnahme zusätzlicher Lerninhalte sind weitere Ausbauschritte.
