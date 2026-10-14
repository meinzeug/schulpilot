# Betrieb

## Bestehender Server

`ssh dorfspy`, `91.99.217.84`, Ubuntu 24.04, vorhandenes Caddy 2.6.2 und PostgreSQL 16. Andere Anwendungen bleiben unverändert. Projektbenutzer `schulpilot`, Datenbank/Rolle `schulpilot` mit lokaler Peer-Authentifizierung, API ausschließlich `127.0.0.1:3240`. Datenbank und Caddy-Verwaltungsport bleiben lokal. Keine kostenpflichtigen Ressourcen bestellt.

`/opt/schulpilot/releases/<id>` enthält Backend, eigenes Virtualenv, Flutter-Web und Deploymentdateien. `/opt/schulpilot/current` ist ein atomar ersetzter Zeiger, `/opt/schulpilot/previous` der Rückweg. Daten unter `/var/lib/schulpilot`, Secrets in `/etc/schulpilot/environment` (root:schulpilot, 0640), Sicherungsschlüssel `/etc/schulpilot/backup.key` (0600). Entwicklungs-, Hetzner-, SSH- und GitHub-Zugänge werden nicht übertragen. Der Hetzner-Schlüssel bleibt ausschließlich auf dem Entwicklungsrechner.

## Deployment

Nach Tests und Web-Build aus dem Repository: `bash scripts/deploy.sh`. Das Script legt ausschließlich Projektressourcen an, lädt einen eigenen Release hoch, installiert exakt `requirements.lock`, sichert Caddy, prüft die ergänzte Konfiguration, migriert die Projektdatenbank, aktiviert API/Worker und lädt Caddy neu. Healthcheck lokal und anschließend über HTTPS. Die erstmalige Zertifikatsausstellung darf mit begrenzten GET-Wiederholungen abgewartet werden. Änderungen am Datenbankschema benötigen vorab ein Backup und eine zum Rückweg passende Migration; ein Code-Rollback ersetzt keine Datenrücksicherung.

Die Caddy-Hauptdatei erhält lediglich `import /etc/caddy/schulpilot.caddy`. Das Fragment übernimmt `/api` einschließlich Unterpfaden; alle anderen Direktlinks fallen auf Flutter `index.html` zurück. Statische Ressourcen kommen vom eigenen Server, ohne externes Flutter-CDN. Let’s Encrypt wird über Caddy ACME HTTP-01 bezogen und automatisch erneuert; HTTP leitet per 308 auf HTTPS. Die bestehende Caddy-Version bleibt erhalten.

Dienste: `schulpilot-api.service`, `schulpilot-worker.service`, `schulpilot-backup.timer`. Automatischer Start und Neustart bei Ausfall; unprivilegierte API/Worker, schreibgeschützter Anwendungscode, geschütztes Home, minimale Fähigkeiten, getrennte Speicherlimits. Keine vollständigen Anfragen/Antworten in Zugriffslogs. `systemctl status`, `/api/health` und `journalctl -u schulpilot-api -u schulpilot-worker` dienen der Diagnose. Ein eigener Prozess-Watchdog und eine unabhängige HTTPS-Prüfung auf dem zweiten Host sind vorbereitet; Einrichtung und tatsächlicher Prüfstand stehen unten beziehungsweise in STATUS.md.

## Rückweg

Aktiven und vorherigen Release prüfen: `readlink -f /opt/schulpilot/current` / `readlink -f /opt/schulpilot/previous`.

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/activate.py <vorherige-release-id> --rollback-compatible'
```

Das verwendet denselben Aktivierungsweg, überspringt beim ausdrücklich bestätigten kompatiblen Code-Rollback jedoch die Migration aus dem alten Release. Nur verwenden, wenn das aktuelle Schema mit dem alten Code kompatibel ist. Bei automatischem Aktivierungsfehler werden Caddy und vorhandener Release wiederhergestellt. Migration 0002 ergänzt kompatible Spalten mit Serverdefaults; ein Rückweg auf 0001-Code lässt diese Spalten stehen. Für spätere inkompatible Migrationen Wartungsfenster und expliziten Datenrückweg planen. Caddy-Sicherungen liegen unter `/etc/caddy/Caddyfile.before-schulpilot-<zeit>`; keine Sicherung einer fremden Anwendung blind zurückspielen.

## Sicherungen und Wiederherstellung

Täglich ca. 02:40 UTC mit bis zu fünf Minuten Zufallsverzögerung: PostgreSQL-Custom-Dump plus private Uploads, authentifiziert mit AES-256-GCM verschlüsselt, nur root-lesbar unter `/var/backups/schulpilot`, Rotation nach 14 Tagen. `systemctl start schulpilot-backup.service` löst eine Sicherung aus. Erfolgreiche One-shot-Dienste stehen anschließend regulär auf `inactive (dead)`; `Result=success` und `ExecMainStatus=0` prüfen.

```bash
/opt/schulpilot/current/venv/bin/python decrypt_backup.py \
  /var/backups/schulpilot/<backup>.tar.enc \
  --key-file /etc/schulpilot/backup.key --output /geschuetzter-pfad/restore.tar
```

`scripts/decrypt_backup.py` prüft den Authentifizierungstag vollständig, bevor die fertige Archivdatei bereitsteht. In einem root-geschützten Verzeichnis entpacken. Zunächst in eine **getrennte Testdatenbank** mit `pg_restore --no-owner --no-acl` laden, Schema und Datensätze prüfen. Vor produktiver Rücksicherung API/Worker stoppen, aktuelle Daten sichern, Löschungen seit Backup abgleichen, dann gezielt Datenbank/Uploads zurückspielen. Kein automatisches Überschreiben der Produktion.

Geprüft wurden Verschlüsselung/Entschlüsselung sowie `pg_restore` in `schulpilot_restore_test`. Serverkopien bleiben lokal verschlüsselt. Zusätzlich unterstützt der unten beschriebene Pull auf den unabhängigen Entwicklungsrechner verschlüsselte Offsite-Kopien; der neue Wiederherstellungsweg gleicht das aktuelle authentifizierte Löschjournal ab. Lokale Wiederherstellungsgeheimnisse wurden außerhalb des Repositorys unter `~/.local/share/schulpilot-recovery/` mit 0600 gesichert; sicher und getrennt vom Backup verwahren.

## DNS

Autoritative Server: hydrogen.ns.hetzner.com, oxygen.ns.hetzner.com, helium.ns.hetzner.de. Zuständig war die Hetzner-Cloud-API `api.hetzner.cloud/v1`, Zone `dorfspy.de` (Primary). Ein eigener A-RRset `schulpilot` fehlte trotz bereits passender öffentlicher Auflösung. Angelegt wurde ausschließlich `schulpilot/A` → `91.99.217.84`, TTL 300. Kein CNAME-Konflikt, keine Nameserver- oder sonstigen DNS-Änderungen. Autoritativer Server und öffentlicher Resolver wurden nachher geprüft.


## APK, SMTP und kostenlose KI-Tests

Deployment erfordert nun neben dem fertigen Web-Build eine signierte APK unter `artifacts/schulpilot-0.1.0-test.apk`. Das Skript prüft die APK-Signatur und liest Paket/Version/Mindest-SDK mit dem fixierten Android Build Tools 36.0.0; SHA-256 und Größe stammen direkt aus der Datei. Nur APK und öffentliches Manifest werden ins Release kopiert, keine Signierdaten. Caddy liefert `/downloads/*` als Datei ohne SPA-Fallback aus.

Gmail-SMTP wurde nach ausdrücklichem Auftrag aus dem vorhandenen verschlüsselten Merchagent-Mailtresor in die separate geschützte SCHULPILOT-Umgebung übernommen. TLS-Zertifikate werden geprüft. Der Read-only-IMAP-Test suchte nur die zufälligen eigenen Testaliase und las mit BODY.PEEK; er änderte keine anderen Nachrichten oder Merchagent-Einstellungen. `scripts/mail_smoke.py` prüft echte Zustellung, Registrierung, Einladung, Wiederherstellung, Rechteentzug und Bereinigung. Zugangsdaten und Mail-Links werden nicht ausgegeben. Erfordert explizit autorisierte TEST_IMAP_USER/PASSWORD nur in der Prozessumgebung.

Für das gesonderte konstante KI-Testblatt sind `SYNTHETIC_AI_ENABLED=true` und `SYNTHETIC_AI_DAILY_LIMIT=40` gesetzt. Der lokale Operator-Import `deploy/admin.py configure-free-tests` liest den ausdrücklich freigegebenen OpenRouter-Schlüssel nur von stdin. Normale Kinderdaten bleiben durch REAL_DATA_APPROVED=false und nicht gesetzte Anbieterfreigabe gesperrt. Ein globaler Notfallstopp sperrt auch diese Testaufrufe.

Google-Play-/Push-Konfiguration: [GOOGLE_PLAY_PUSH.md](GOOGLE_PLAY_PUSH.md). Dienstkonten nie ins Web oder AAB einbetten. Nach Änderungen an geschützten Umgebungsdateien die private Wiederherstellungskopie aktualisieren und verschlüsselt außerhalb des Hosts sichern.


## Ausbau: Offsite, Löschabgleich und Betriebsprüfungen

Auf dem autorisierten unabhängigen Entwicklungsrechner:

```bash
python3 scripts/install_local_ops.py
systemctl --user start schulpilot-offsite.service
systemctl --user start schulpilot-watch-public.service
```

Die Installation kopiert ausschließlich die kleinen Betriebsprogramme nach `~/.local/share/schulpilot-operations/` und legt vier eigene User-Units an. Sie verändert keine fremden Timer. Linger muss für Betrieb ohne angemeldete Sitzung aktiv sein. Der Offsite-Pull nutzt den bereits autorisierten SSH-Alias `dorfspy`; diese SSH-Rechte werden nicht auf den App-Server oder an einen KI-Worker übertragen.

Ziel: `~/.local/share/schulpilot-offsite/`, 0700, Dateien 0600. Nur authentifiziert verschlüsselte Backups und ein gesondert verschlüsselter aktueller Löschjournal-Snapshot werden kopiert. Größe/SHA-256 der Backupdateien werden geprüft. Vorhandene beschädigte Dateien werden nicht still überschrieben. Aufbewahrung auch offsite höchstens 14 Tage. Alle 15 Minuten aktualisieren; der zweite Rechner muss dazu erreichbar und eingeschaltet sein. Das ist ein zweiter physischer Host, keine zusätzlich bestellte Cloudressource.

Der tägliche Datenstand hat einen Sicherungsabstand von ungefähr 24 Stunden. Das externe Löschjournal wird beim verfügbaren zweiten Host alle 15 Minuten aktualisiert. Bei Wiederherstellung ist das aktuellste erreichbare Journal zu verwenden; eine mögliche Lücke nach dem letzten erfolgreichen Abgleich muss vor erneuter Datenfreigabe geprüft werden. Keine automatische produktive Rücksicherung.

Löschanforderungen für Accounts, Familien, Kinder, Materialien und entzogene Mitgliedschaften werden mit der eigentlichen Änderung in einer DB-Outbox gespeichert. Nach Commit schreibt die App ein HMAC-authentifiziertes Journal außerhalb der Datenbank; der Worker veröffentlicht liegengebliebene Einträge erneut. Doppelte Journal-IDs sind unschädlich. Keine Namen oder Lernantworten im Journal; nur zufällige IDs, Bereich und Zeitpunkt. Aufbewahrung 35 Tage, damit alle erlaubten 14-Tage-Sicherungen abgedeckt sind. Der separate Master-Key zur Prüfung muss zusammen mit der geschützten Umgebung erhalten bleiben; eine Schlüsselrotation benötigt einen geplanten Journal-/Datenübergang.

Wiederherstellungsprobe:

```bash
ssh dorfspy 'systemctl start schulpilot-restore-check.service'
ssh dorfspy 'systemctl show schulpilot-restore-check.service -p Result -p ExecMainStatus'
```

Der Dienst authentifiziert die letzte Sicherung, entpackt nur in ein privates temporäres Verzeichnis, erstellt eine zufällig benannte separate PostgreSQL-Testdatenbank, migriert diese gegebenenfalls auf den aktuellen Stand und gleicht das aktuelle signierte Journal ab. Alte Sitzungen und Zugangstokens werden widerrufen; KI bleibt im rückgesicherten Teststand per Notfallstopp gesperrt. Entfernte Bildpfade werden auch aus der Testkopie gelöscht. Danach wird ausschließlich diese neu erstellte Testdatenbank entfernt. Die produktive DB wird nicht überschrieben. Automatische Wiederholung sonntags ca. 03:30 UTC. Geschützter letzter Bericht: `/var/backups/schulpilot-monitor/restore-check.json`.

`scripts/reconcile_restore.py` bietet denselben ID-Abgleich für eine ausdrücklich separat benannte Datenbank mit Suffix `_restore_test`; es akzeptiert keine produktive DB. Vor einer tatsächlichen Aktivierung zusätzlich Aufbewahrung, aktuelle Lösch-/Rechteänderungen, Zugangsgeheimnisse und den Verbrauch seit Backup prüfen. Alte Sitzungen, Einladungs-/Wiederherstellungstokens und ein alter Kostenstand dürfen nicht unbemerkt wieder gültig werden.

`schulpilot-monitor.timer` prüft alle fünf Minuten ausschließlich die eigenen Dienste, API, Worker-Lebenszeichen, festhängende Jobs, unveröffentlichte Löschanforderungen, Sicherungsalter, Wiederherstellungsprobe und freien Speicher. `/api/admin/operations` zeigt Inhalts-freie Summen, ausschließlich nach Admin-Anmeldung. Die unabhängige User-Unit `schulpilot-watch-public.timer` prüft öffentliches HTTPS und die Frische der Offsite-Kopie auch bei Ausfall des App-Hosts.

Optionale technische Alarmmails gehen über das bereits autorisierte SMTP an `OPERATIONS_ALERT_EMAIL`. Der Freigabe-Recorder verwendet dafür das eigene vorhandene Operatorpostfach, wenn noch kein Empfänger gesetzt ist. Keine Kindernamen, Themen oder Antworten in Alarmen. Meldungen werden gebündelt, bei derselben Störung höchstens alle sechs Stunden; ein SMTP-Fehler bleibt als Fehler sichtbar. `scripts/monitor_mail_smoke.py` sendet genau einen ausdrücklich als TEST gekennzeichneten Alarm an dasselbe autorisierte Gmail-Postfach und prüft ausschließlich dessen eindeutige Testnachricht per Read-only-IMAP.

Zusätzliche Datenfristen: einzelne Verbrauchsmetadaten 90 Tage, administrative Auditereignisse 180 Tage, Monatskontingente aktueller plus zwölf vorherige Monate. Das sind keine Rechnungen. Für einen späteren Zahlungsbetrieb sind Rechnungsaufbewahrung, Tarifpreise und Zahlungsanbieter gesondert einzurichten.

Vor einem Rückweg auf den Stand vor Migration 0005 echte Verarbeitung pausieren: alter Code kennt weder den getrennten technischen Routingblocker noch das neue Löschjournal. Zusatzspalten können bei einem kompatiblen Code-Rollback stehen bleiben; die neuen Watchdog-/Restore-Timer werden beim Aktivieren eines alten Releases angehalten. Kein Schema-Downgrade mit Datenverlust als gewöhnlichen Rückweg verwenden.
