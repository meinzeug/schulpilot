# Projektstand · 14.10.2026 · Version 0.1.0

Funktionsfähiger technischer Pilot mit eigenem Backend und Flutter-Clients. Öffentliche Adresse: https://schulpilot.dorfspy.de . Für echte Kinderdaten und einen kommerziellen Echtbetrieb weiterhin gesperrt; keine Produktionsreife behauptet.

## Implementiert

- Echte Elternregistrierung, E-Mail-Verifikation, Wiederherstellung und adressgebundene Einladungen über eingerichtetes Gmail-SMTP; tatsächlicher E-Mail-Eingang geprüft. Fehlender/gestörter Versand wird ausdrücklich als Fehler gemeldet. Argon2id, sichere widerrufbare Web-/Android-Sitzungen, getrennte Kinderzugänge ohne Kinder-E-Mail, Rücksetzen ohne Passwortoffenlegung.
- Serverseitige Rollen-/Familientrennung, mehrere Kinder, Leserechte oder Verwaltung für eingeladene Eltern, Sitzungs-/Rechteentzug. Lokaler Erstadmin mit TOTP, Wiederverwendungsschutz und protokollierten Betriebszugriffen; keine Adminansicht privater Kinderinhalte.
- Privater Bildimport mit lokalem Zuschneiden und serverseitiger Metadatenentfernung; serverseitige OpenAI-/OpenRouter-Erkennung und strukturierte Generierung implementiert. Bestätigung unsicherer Stellen und gesonderte notierte Hausaufgaben. Die feste Demo bleibt ohne externe KI; ein gesonderter Testpfad verwendet ein künstliches Bild und feste Texte für echte kostenlose OpenRouter-Aufrufe. Freie Nutzereingaben gelangen nicht in diesen Testpfad.
- Durchgängiges Lernen mit vier Flutter-Aufgabenkomponenten, Erklärungen, Hinweisen, Pause/Fortsetzung, Rückmeldungen und Familienhilfe. Antworten/Unterstützung werden tatsächlich gespeichert. Unsichere freie Antworten werden weder automatisch falsch noch als Verständnisproblem gewertet.
- Familienübersicht und Kinderdetail mit Tages-/Wochenüberblick, Aufgaben/Antworten/Hinweisen/Erklärungen, Aktivitätsverlauf, ungefährer aktiver Lernzeit, offenen Zielen, Prüfungsterminen und späteren Wiederholungen. Ein einzelner Erfolg schließt weder Beherrschung noch ein verbindliches Elternziel automatisch ab.
- Lerntage einschließlich Fach-Lerntagen, Zeitziele, Pausen, Schwerpunkte, konkrete Wiederholungsziele, Aufträge/Termine, Ruhezeiten und In-App-Erinnerungen. Begrenzte Tagespläne, Konflikthinweise und Lernpausen ohne anwachsenden Nachholberg. Quellenrevisionen schützen vor inzwischen geänderten Zielen.
- Austauschbare Provider, verschlüsselte Schlüssel, explizite Modell-/Upstreambindung, atomare Familien-/Unternehmenskontingente, mitgezählte Fehlversuche, unbekannte Kosten mit voller Reservierung, Notfallstopp. Die explizit nach Funktion ausgewählten kostenlosen OpenRouter-Modelle wurden live getestet; tatsächliche Modelle werden gespeichert/angezeigt, eindeutig prüfbare Bruchlösungen zusätzlich deterministisch validiert. Codex-Adapter samt isoliertem Ein-Aufruf-Gateway vorhanden, experimentell und deaktiviert.
- Export/Löschung, 24-Stunden-Testfamilien, Aufbewahrungsjobs. PostgreSQL, Alembic-Migrationen, persistente Daten, systemd, bestehendes Caddy, Let’s Encrypt und geprüfte öffentliche DNS-Auflösung. Verschlüsselte tägliche Sicherungen und dokumentierter kompatibler Code-Rollback.

Zusätzlich: freiwilliges gerätebezogenes FCM-Push für Android/Web mit verschlüsselten Tokens, aktueller Sitzungs-/Familienprüfung, Ruhezeiten, Tagesbündeln, neutralen Texten und begrenzter TTL. Ohne Firebase-Projekt/Dienstkonto/Freigabe ausdrücklich gesperrt. Eigenes Upload-Signing und AAB-Build; APK-Download vor und nach Login.

## Tatsächlich geprüft

| Prüfung | Ergebnis |
| --- | --- |
| Backend mit SQLite | Gesamtlauf mit 49 Tests bestanden; zusätzlicher Rechte-Test ebenfalls bestanden (50 Testfälle) |
| Backend auf separater PostgreSQL-Testdatenbank des Zielservers | Gesamtlauf mit 50 Tests bestanden, einschließlich neuer Fixture-/Push-Sicherheitsfälle |
| Flutter-Analyse | Keine Befunde |
| Fluttertests | 5 bestanden, einschließlich Kinderstart auf 390 und 1280 Pixel |
| Flutter-Web Release | Erfolgreich gebaut, Ressourcen vom eigenen Server |
| Android Release-Test-APK / AAB | Version 0.1.0+2 mit eigenem externem Upload-Schlüssel gebaut; APK/JAR-Signatur und AAB mit offiziellem bundletool 1.18.3 geprüft; 64-Bit-ELF-Ladesegmente mindestens 16 KB ausgerichtet |
| Öffentliche HTTPS-API | Materialbestätigung, verbindlicher Elternplan, persistenter Job, Idempotenz, eigener Kinderlogin, Rollenprüfung, alle vier Aufgabenarten, Hinweise, Pause, Elternverlauf, Export, Sitzungswiderruf und Löschung bestanden |
| Echter Browser | Getrennte Eltern-/Kinderkontexte, sichere Cookies, Materialfluss, alle vier interaktiven Aufgaben, Elternverlauf und mobile Ansicht geprüft; keine JavaScript-Laufzeitfehler |
| Sicherung | Aktuelle AES-GCM-Sicherung authentifiziert; Schema 0003 in getrennte PostgreSQL-Testdatenbank wiederhergestellt und Testkopie anschließend entfernt |
| Kompatibler Rückweg | Öffentlich alte Releasekennung ea75f6c und anschließend wieder b847272 mit gesunder API geprüft |
| APK-Download | Zwei echte Browser-Downloads: Startseite ohne Login und Eltern-Dashboard; Dateigröße und SHA-256 stimmen mit lokalem APK überein |
| Echter KI-Ablauf über HTTPS | Künstliches Bild → Erkennung → Bestätigung → validierte Einheit → Kinderantworten/Hinweis → Elternverlauf → Löschung; zwei Aufrufe, gemeldete Kosten 0 Mikro-USD |
| Android-Emulator API 36 | Installierte signierte APK: Elternlogin, geschützte Sitzung nach Prozess-Neustart, eigener Kinderlogin, tatsächlicher Hinweis/Antwort, serverseitiger Widerruf, Testfamilienlöschung bestanden |
| DNS / TLS | Eigener Hetzner-A-Eintrag und autoritative/öffentliche Auflösung geprüft; Let’s-Encrypt-Zertifikat und HTTP-308-Weiterleitung geprüft |

Die Testbibliothek meldet einen bekannten Starlette-Hinweis zur künftigen Testclient-Umstellung von `httpx`. Tests bestehen mit den fixierten Versionen. Echte kostenlose Bild-/Schemaaufrufe und tatsächliche Gmail-Zustellung wurden inzwischen geprüft. FCM-Zustellung und ein physisches Android-Gerät wurden **nicht** als erfolgreich behauptet. Die FCM-HTTP-/Rechte-/Ruhezeitprüfung verwendet ausdrücklich Mock-Transport, kein vorgetäuschtes Live-Ergebnis. Frühe Aktivierungsfehler durch fehlendes Python-Venv-Paket, Caddy-Issuer-Syntax und Systempfad wurden behoben; bestehende Anwendungen blieben erreichbar.

APK: `artifacts/schulpilot-0.1.0-test.apk` auf dem Entwicklungsrechner, absichtlich nicht versioniert. Eigenes Upload-Signing unter `~/.local/share/schulpilot-signing/`, außerhalb von Git. AAB: `artifacts/schulpilot-0.1.0-upload.aab`. Öffentliche `/api/health`-Antworten zeigen für die abschließenden Releases die konkrete Commitkennung. Eigene Änderungen werden auf den vorhandenen Branch `main` gepusht; maßgeblich sind Git-Verlauf und öffentliche Versionskennung.

## Offene Voraussetzungen

1. Freigegebenes Firebase-Projekt, öffentliche App-/VAPID-Kennungen, FCM-Dienstkonto und dokumentierte Minderjährigen-/Datenschutzprüfung für tatsächliche Push-Zustellung. Integration ist implementiert; kein echter Firebase-Zustelltest ohne Zugang.
2. Play-Console-Zugang, vollständige Betreiber-/Support-/Impressums-/Datenschutzangaben, Families-/Data-Safety-/Inhaltsbewertung und interne Geräteabnahme. Signiertes AAB gebaut und validiert; kein Play-Upload und keine Veröffentlichung behauptet. [Einrichtung](GOOGLE_PLAY_PUSH.md).
3. Datenschutz-/Minderjährigenprüfung einschließlich Verträgen, Rechtsgrundlage, erforderlicher ZDR-/Bildfreigaben, Region/Kontoeinstellungen, Inhalts-/Sicherheitsprüfung. Ohne Nachweise bleibt echte externe Verarbeitung gesperrt; die kostenlosen synthetischen Tests ändern das nicht.
4. Codex-Containerlaufzeit, verifiziertes CLI-Binary, getrennte Authentifizierung, Socket-/Netzwerkisolation und kommerzielle Nutzungsfreigabe prüfen. Experimenteller Worker nicht auf dem App-Server installiert/aktiviert und nicht live getestet.
5. Offsite-Sicherungsziel und belastbarer Löschabgleich bei Wiederherstellungen; externer Alarmdienst, Last-/Abuse-Tests und abschließende Aufbewahrungsprüfung der Betriebs-/Verbrauchsprotokolle vor Echtbetrieb.
6. Physisches Android-Gerät sowie breitere pädagogische Qualitätsabnahme zusätzlich zum festen synthetischen Test. Ein vollständiger Zahlungscheckout ist im beauftragten ersten Stand nicht Voraussetzung und wurde nicht implementiert.

Abschließende öffentliche Prüfungen des bereitgestellten Anwendungscodes durchgeführt. Reproduzierbar: `scripts/public_smoke.py`, `scripts/public_live_ai_smoke.py`, `qa/smoke.mjs`, `qa/download.mjs`, `qa/android_smoke.py`. Testkonten wurden gelöscht. API/Worker und vorhandene Merchagent-/Artist-/Buddy-/Caddy-Dienste sind aktiv; öffentliche DorfSpy-/Artist-/Buddy-Adressen liefern HTTP 200. API-Port 3240 bindet ausschließlich an 127.0.0.1.

Öffentliche APK: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk . Version 0.1.0+2, 59.631.320 Bytes, SHA-256 `00f1c757622a7a4fb461c95d2289870c75b670b7f0e43b27db9eb478ae5be32b`. APK-Signatur, `zipalign -P 16`, ELF-Ausrichtung und finales AAB mit offiziellem bundletool geprüft. Physische Geräte- und tatsächliche Firebase-/Play-Console-Prüfung bleiben offen.
