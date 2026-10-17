# SCHULPILOT

Eigenständige Lernplattform mit Flutter für Android/Web und einer eigenen FastAPI-API. Persistente Familien, getrennte Kinderzugänge, bestätigter Schulstoff, strukturierte Aufgaben und nachvollziehbare Elternansichten. Für diese Installation ist der ausdrücklich beauftragte Codex-CLI-Provider mit eigener isolierter Serveranmeldung ausgewählt; der jeweilige tatsächliche Abnahmestand steht in [STATUS.md](docs/STATUS.md). [Konfiguration und Datenregeln](docs/AI_STANDARD.md), [Betreiberfreigabe](docs/APPROVALS.md).

Die Android-App startet eine `FlutterActivity` und rendert die Dart-Oberfläche auf dem Gerät. Sie ist keine Website in einer WebView. Web und Android teilen Lernansichten und Theme; Android ergänzt Kamera, sichere Sitzungsablage und den nativen Updater. Die Oberfläche wird für kleine Touchscreens und breite Webfenster angepasst.

Web: https://schulpilot.dorfspy.de · API: `/api` · Android: `artifacts/schulpilot-android.apk` (signierter regulärer Release, absichtlich nicht in Git). Versions- und Freigabestand: [Produktionsbetrieb](docs/PRODUCTION.md).

## Ausprobieren

Der Kinderbereich enthält den geführten **„Nach der Schule“-Assistenten**: mehrere Heftseiten aufnehmen, jede Erkennung bestätigen und daraus ein gemeinsames, zeitlich begrenztes Tagespaket mit Erklärungen und interaktiven Übungen erstellen. Mehrfachauswahl, Drehen, Sortieren, begrenzte lokale Upload-Warteschlange, ergänzbare Paketversionen und eine Tageshistorie sind implementiert. Der Lernweg beginnt mit der Erklärung. [Ablauf, Grenzen und Tests](docs/AFTER_SCHOOL.md). Reguläre Kinder verwenden eigene Zugänge und den normalen Fotoimport. Die zusätzlich verfügbare synthetische Demo ist ausdrücklich getrennt.

Nach jeder abgeschlossenen Einheit folgt ein gespeicherter KI-Rückblick auf die tatsächlichen Antworten. Schulpilot bereitet gezieltes Nachlernen, neue selbstständige Abrufproben und spätere Wiederholungen vor. Fortschritt zählt je Lernziel; tägliche/wöchentliche Mindestlernzeit wird aus aktiven Sekunden gemessen. Vor dem Mindestziel geht es weiter, danach bleibt zusätzliches Lernen freiwillig. Pausen sind Empfehlungen; KI-Kontingente gelten weiterhin. [Betreutes Weiterlernen](docs/COACHING.md).

**Jede Übung zählt:** Kind und Eltern sehen alle beantworteten Aufgaben, weitere Versuche und genutzte Hilfe auch in begonnenen oder freiwilligen Runden. Fach → Thema → einzelne Runden bleiben nachvollziehbar; spätere Prüftage sind eine zusätzliche Beobachtung. Eltern verwalten Schulnoten und können daraus fachliche Schwerpunkte im bestehenden Zeitplan sowie bestätigte Lernaufträge ableiten. Die KI erhält nur eine abgeleitete Unterstützungsstrategie, keine automatisch übertragenen Noteneinträge. [Lernmodell, Forschung, Berechnung und Grenzen](docs/LEARNING_MODEL.md).

Die Kinderstartseite behält heutige Fotos, die begrenzte Lernportion und den Status abgegebener Seiten im Blick. Ein Siebentagevorschlag verteilt bekannte Etappen innerhalb der Elternvorgaben; er ist keine tägliche Pflicht, den ganzen Hefter abzuarbeiten. [Täglicher Ablauf](docs/DAILY_ROUTINE.md). **Hefte** öffnet eine eigene Bibliothek mit Suche, Fach-/Datumsfiltern und begrenzten Seiten. **Lernen** trennt offene Runden, spätere Aufträge und abgeschlossene Einheiten. Rückblick und gespeicherte Antworten sind einzelne Ansichten; Eltern nutzen dieselben berechtigten Sammlungen. [Bibliothek und Lernraum](docs/LIBRARY.md).

Für den regulären Betrieb ein Elternkonto registrieren, die E-Mail bestätigen und im Familienbereich einen Kinderzugang mit eigenem Benutzernamen und sicherem Passwort anlegen. Das Kind meldet sich damit direkt im Web oder in der APK an und öffnet „Nach der Schule starten“. Eltern erhalten die gespeicherten Aufgaben, Antworten und genutzten Hinweise im eigenen Dashboard.

Der optionale Beispiel-Lernraum legt eine eigene isolierte Testfamilie für 24 Stunden an. Die einmalig angezeigten Eltern- und Kinderzugänge funktionieren auch auf einem zweiten Gerät. Den Beispielstoff bestätigen, eine Einheit vorbereiten und mit dem Kinderzugang lernen. Eltern sehen anschließend tatsächliche Aufgaben, Antworten, Hinweise und Aktivitäten. Die feste Demo führt **keine Fotoerkennung und keinen externen KI-Aufruf** aus; freie Foto-Uploads sind darin gesperrt. Der zusätzliche ausdrücklich gestartete Live-KI-Testpfad bleibt davon getrennt.

## Lokal starten

Versionen: Flutter **3.47.7**, Dart **3.13.5**, Python **3.12**. Flutter-Revision und alle direkten/transitiven Paketstände sind fixiert: [toolchain.json](toolchain.json), `app/pubspec.lock`, `backend/requirements.lock`, `backend/requirements-dev.lock`, `qa/package-lock.json`.

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements-dev.lock
cd app
flutter pub get --enforce-lockfile
flutter build web --release --no-web-resources-cdn --csp
cd ..
bash scripts/run-local.sh
```

Dann http://localhost:8080 öffnen. Bei einer leeren Installation erscheint zuerst der [Einrichtungsassistent](docs/INSTALLATION.md). API und Flutter liegen unter demselben Ursprung; direkte Weblinks funktionieren. SQLite/WAL dient lokal und in Tests, PostgreSQL im Betrieb. `.env.example` dokumentiert die lokale Grundkonfiguration. Eine `.env` wird nicht automatisch ausgeführt oder geladen; Umgebungsvariablen passend über einen lokalen Prozessmanager setzen. Einen `MASTER_KEY` nur außerhalb von Git generieren und sicher verwahren. Im Assistenten beziehungsweise Adminbereich gespeicherte Betriebswerte überschreiben die entsprechenden Umgebungsdefaults verschlüsselt in der Datenbank.

## Tests und Builds

```bash
PYTHONPATH=backend .venv/bin/pytest -q
.venv/bin/ruff check backend deploy scripts workers
cd app
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --csp
flutter build apk --flavor direct --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
```

`bash scripts/build_release.sh` baut Web, Direct-APK und Play-AAB mit fixierter Toolchain und dem eigenen **Upload-Schlüssel außerhalb von Git**. Release-Builds verwenden niemals einen Debugschlüssel als Ersatz. Vor Deployment prüfen wir tatsächliche Signatur, Paket, Versionscode, Versionsname, fehlendes Debug-Flag und 16-KB-Zipausrichtung gegen `release-policy.json` und die Quellversion. Ein veraltetes oder anders signiertes APK wird abgewiesen. Das Web zeigt die reguläre APK vor und nach Login; `/api/app-release` veröffentlicht ihre tatsächlichen Metadaten mit Kanal `stable`. [Google Play und Push](docs/GOOGLE_PLAY_PUSH.md).

Für den Ausbau des Einrichtungsassistenten und der Passwort-Administration nachgewiesen: **152 Backendtests in PostgreSQL**, zusätzlich **33 gezielte SQLite-Tests** einschließlich Migration und Datenerhalt. Der endgültige Web-/Android-Buildstand und die öffentlichen Abnahmen stehen getrennt in [STATUS.md](docs/STATUS.md).

Öffentlicher synthetischer API-Test: `.venv/bin/python scripts/public_smoke.py`. Echte kostenlose KI mit ausschließlich serverseitigen Testinhalten: `.venv/bin/python scripts/public_live_ai_smoke.py` (zwei mitgezählte Anfragen, Freigabe erforderlich). Browser: `cd qa && npm ci --ignore-scripts && node smoke.mjs`; vorhandenes Chrome wird verwendet, alternativ `CHROME_PATH` setzen. Der Browsertest verwendet vorübergehend eine private Datei unter `artifacts/`, um einen unterbrochenen Test fortzusetzen; sie wird nach erfolgreichem Test gelöscht. Keine echten Kinderdaten verwenden.

## Einrichtung und Administration

Neue Installationen führen durch Adminzugang, Mailversand, Betreiberangaben, KI-Provider und Kontingente sowie optionale Push-Einstellungen. Der Betreiber öffnet die Einrichtung mit dem lokal gespeicherten Installationscode; ein Besucher kann die Installation nicht übernehmen. Nach Abschluss bleibt dieser Zugang dauerhaft geschlossen. [Einrichtung und lokale Wiederherstellung](docs/INSTALLATION.md).

Bestehende Installationen und die lokale Wiederherstellung verwenden weiterhin:

```bash
ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin'
```

Interaktiv eigenen Benutzernamen und starkes Passwort einrichten. Die Anmeldung erfolgt ausdrücklich ohne TOTP. Es gibt kein Standardpasswort und kein öffentliches Rollenwahlfeld. Wiederherstellung über denselben lokalen Prozess mit `reset-admin`; für autorisierte Automation ist `--password-stdin --username <name>` vorgesehen. Administratoren erhalten über die API keinen privaten Kinderinhaltszugriff.

## Betrieb und Freigaben

- [Deployment, Sicherung und Rückweg](docs/OPERATIONS.md)
- [Architektur, Rechte und Daten](docs/ARCHITECTURE.md)
- [KI-Anbieter, Datenschutzfreigaben und Codex-Isolation](docs/PROVIDERS.md)
- [Geprüfte Quellen und Versionsstände](docs/SOURCES.md)
- [Projektstand und offene Voraussetzungen](docs/STATUS.md)

Gmail-SMTP ist serverseitig eingerichtet. Registrierung, Verifikation, Einladung und Wiederherstellung wurden über HTTPS mit tatsächlichem Eingang im autorisierten Testpostfach geprüft. Die Zugangsdaten wurden ausschließlich aus dem ausdrücklich freigegebenen Merchagent-Mailtresor übernommen; Merchagent wurde nicht verändert.

Der Betreiber hat am 15.10.2026 den dauerhaften Wechsel auf **Codex CLI mit `--search`** beauftragt. Der getrennte Rootless-Worker verwendet eine eigene Serveranmeldung; neue KI-Verarbeitung bleibt bis zur Anmeldung und dem erfolgreichen künstlichen Bild-/Aufgaben-/Pakettest gesperrt. Einrichtung und Grenzen: [CODEX.md](docs/CODEX.md). Der bisherige OpenRouter-Free-Betrieb ist in [AI_STANDARD.md](docs/AI_STANDARD.md) dokumentiert und bleibt als ausdrücklich wählbarer Adapter vorhanden; es gibt keinen automatischen Rückwechsel. Tatsächliche Prüfungen stehen in [STATUS.md](docs/STATUS.md). Die separate feste Demo bleibt ohne KI nutzbar.


Download-Verifikation im echten Browser: `cd qa && node download.mjs`. Android-Gerätetest: `.venv/bin/python qa/android_smoke.py` gegen den eigens angelegten Emulator `emulator-5580` / AVD `schulpilot-qa-api36`, API 36. Das Skript löscht ausschließlich die Daten dieser Testinstallation, prüft eigene Eltern-/Kinderzugänge, Neustart, Hinweis/Antwort und Widerruf. Es verwendet eine private temporäre Datei unter `artifacts/` zur Fortsetzung; nach Erfolg wird die Testfamilie samt Datei gelöscht. Kein Test gegen ein fremdes Gerät oder echte Kinderdaten.

Der optionale [Google-Elternzugang](docs/GOOGLE_LOGIN.md) verwendet OpenID Connect über unsere eigene API, keine Firebase Authentication. Kinder bleiben unabhängig mit eigenem Benutzernamen und Passwort angemeldet. Firebase ist ausschließlich für freiwilliges Push mit zusätzlicher Elternfreigabe zuständig. Der konkrete aktuelle Abnahme- und Bereitstellungsstand steht in [STATUS.md](docs/STATUS.md).
