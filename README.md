# SCHULPILOT

Eigenständige Lernplattform mit Flutter für Android/Web und einer eigenen FastAPI-API. Persistente Familien, getrennte Kinderzugänge, bestätigter Schulstoff, strukturierte Aufgaben und nachvollziehbare Elternansichten. **Technischer Pilot, derzeit ausschließlich für synthetische Tests freigegeben.**

Web: https://schulpilot.dorfspy.de · API: `/api` · Test-APK: `artifacts/schulpilot-0.1.0-test.apk` (lokal, absichtlich nicht in Git).

## Ausprobieren

„Synthetisch ausprobieren“ legt eine eigene isolierte Testfamilie für 24 Stunden an. Die einmalig angezeigten Eltern- und Kinderzugänge funktionieren auch auf einem zweiten Gerät. Den Beispielstoff bestätigen, eine Einheit vorbereiten und mit dem Kinderzugang lernen. Eltern sehen anschließend tatsächliche Aufgaben, Antworten, Hinweise und Aktivitäten. Die Demo führt **keine Fotoerkennung und keinen externen KI-Aufruf** aus; freie Foto-Uploads sind darin gesperrt.

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

Dann http://localhost:8080 öffnen. API und Flutter liegen unter demselben Ursprung; direkte Weblinks funktionieren. SQLite/WAL dient lokal und in Tests, PostgreSQL im Betrieb. `.env.example` dokumentiert die Konfiguration; Einstellungen werden aus der Prozessumgebung gelesen. Eine lokale `.env` wird nicht automatisch ausgeführt oder geladen. Vorhandene Umgebungsvariablen passend über einen lokalen Prozessmanager setzen. Einen `MASTER_KEY` nur außerhalb von Git generieren und sicher verwahren.

## Tests und Builds

```bash
PYTHONPATH=backend .venv/bin/pytest -q
.venv/bin/ruff check backend deploy scripts workers
cd app
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --csp
flutter build apk --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
```

Die öffentliche Test-APK und das AAB verwenden einen eigenen **Upload-Schlüssel außerhalb von Git**. Einrichtung und Store-Voraussetzungen: [Google Play und Push](docs/GOOGLE_PLAY_PUSH.md). Ein tatsächlicher Test auf einem physischen Android-Gerät steht aus. Die APK ist auf der Startseite und nach Web-Login herunterladbar; `/api/app-release` liefert die aus dem echten APK berechneten Metadaten.

Öffentlicher synthetischer API-Test: `.venv/bin/python scripts/public_smoke.py`. Browser: `cd qa && npm ci --ignore-scripts && node smoke.mjs`; vorhandenes Chrome wird verwendet, alternativ `CHROME_PATH` setzen. Der Browsertest verwendet vorübergehend eine private Datei unter `artifacts/`, um einen unterbrochenen Test fortzusetzen; sie wird nach erfolgreichem Test gelöscht. Keine echten Kinderdaten verwenden.

## Sicherer Erstadmin

```bash
ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin'
```

Interaktiv eigenen Benutzernamen, starkes Passwort und TOTP einrichten und den aktuellen Authenticator-Code bestätigen. Es gibt keinen Standardadmin und kein öffentliches Rollenwahlfeld. Wiederherstellung nur über denselben lokalen Prozess mit `reset-admin`. Administratoren erhalten über die API keinen privaten Kinderinhaltszugriff.

## Betrieb und Freigaben

- [Deployment, Sicherung und Rückweg](docs/OPERATIONS.md)
- [Architektur, Rechte und Daten](docs/ARCHITECTURE.md)
- [KI-Anbieter, Datenschutzfreigaben und Codex-Isolation](docs/PROVIDERS.md)
- [Geprüfte Quellen und Versionsstände](docs/SOURCES.md)
- [Projektstand und offene Voraussetzungen](docs/STATUS.md)

Gmail-SMTP ist serverseitig eingerichtet. Registrierung, Verifikation, Einladung und Wiederherstellung wurden über HTTPS mit tatsächlichem Eingang im autorisierten Testpostfach geprüft. Die Zugangsdaten wurden ausschließlich aus dem ausdrücklich freigegebenen Merchagent-Mailtresor übernommen; Merchagent wurde nicht verändert.

Kostenlose OpenRouter-Bild- und Schemaaufrufe wurden tatsächlich mit festen synthetischen Inhalten getestet. Im Testraum führt „Material fotografieren / importieren“ zum gesonderten KI-Testblatt. Die normale feste Demo bleibt ohne KI nutzbar. Freie Kinderdaten sind weiterhin serverseitig gesperrt. OpenAI und der experimentelle Codex-Worker benötigen eigene Betriebsfreigaben; Codex ist nicht auf dem App-Server aktiviert.
