# Betrieb

## Bestehender Server

`ssh dorfspy`, `91.99.217.84`, Ubuntu 24.04, vorhandenes Caddy 2.6.2 und PostgreSQL 16. Andere Anwendungen bleiben unverändert. Projektbenutzer `schulpilot`, Datenbank/Rolle `schulpilot` mit lokaler Peer-Authentifizierung, API ausschließlich `127.0.0.1:3240`. Datenbank und Caddy-Verwaltungsport bleiben lokal. Keine kostenpflichtigen Ressourcen bestellt.

`/opt/schulpilot/releases/<id>` enthält Backend, eigenes Virtualenv, Flutter-Web und Deploymentdateien. `/opt/schulpilot/current` ist ein atomar ersetzter Zeiger, `/opt/schulpilot/previous` der Rückweg. Daten unter `/var/lib/schulpilot`, Secrets in `/etc/schulpilot/environment` (root:schulpilot, 0640), Sicherungsschlüssel `/etc/schulpilot/backup.key` (0600). Entwicklungs-, Hetzner-, SSH- und GitHub-Zugänge werden nicht übertragen. Der Hetzner-Schlüssel bleibt ausschließlich auf dem Entwicklungsrechner.

## Deployment

Nach Tests und Web-Build aus dem Repository: `bash scripts/deploy.sh`. Das Script legt ausschließlich Projektressourcen an, lädt einen eigenen Release hoch, installiert exakt `requirements.lock`, sichert Caddy, prüft die ergänzte Konfiguration, migriert die Projektdatenbank, aktiviert API/Worker und lädt Caddy neu. Healthcheck lokal und anschließend über HTTPS. Die erstmalige Zertifikatsausstellung darf mit begrenzten GET-Wiederholungen abgewartet werden. Änderungen am Datenbankschema benötigen vorab ein Backup und eine zum Rückweg passende Migration; ein Code-Rollback ersetzt keine Datenrücksicherung.

Die Caddy-Hauptdatei erhält lediglich `import /etc/caddy/schulpilot.caddy`. Das Fragment übernimmt `/api` einschließlich Unterpfaden; alle anderen Direktlinks fallen auf Flutter `index.html` zurück. Statische Ressourcen kommen vom eigenen Server, ohne externes Flutter-CDN. Let’s Encrypt wird über Caddy ACME HTTP-01 bezogen und automatisch erneuert; HTTP leitet per 308 auf HTTPS. Die bestehende Caddy-Version bleibt erhalten.

Dienste: `schulpilot-api.service`, `schulpilot-worker.service`, `schulpilot-backup.timer`. Automatischer Start und Neustart bei Ausfall; unprivilegierte API/Worker, schreibgeschützter Anwendungscode, geschütztes Home, minimale Fähigkeiten, getrennte Speicherlimits. Keine vollständigen Anfragen/Antworten in Zugriffslogs. `systemctl status`, `/api/health` und `journalctl -u schulpilot-api -u schulpilot-worker` dienen der Diagnose. Ein externer Alarmdienst ist noch nicht angebunden.

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

Geprüft wurden Verschlüsselung/Entschlüsselung sowie `pg_restore` in `schulpilot_restore_test`. Sicherungen liegen derzeit auf demselben Server. Separates Offsite-Ziel, Löschabgleich und regelmäßiger Wiederherstellungstest sind vor Echtbetrieb erforderlich. Lokale Wiederherstellungsgeheimnisse wurden außerhalb des Repositorys unter `~/.local/share/schulpilot-recovery/` mit 0600 gesichert; sicher und getrennt vom Backup verwahren.

## DNS

Autoritative Server: hydrogen.ns.hetzner.com, oxygen.ns.hetzner.com, helium.ns.hetzner.de. Zuständig war die Hetzner-Cloud-API `api.hetzner.cloud/v1`, Zone `dorfspy.de` (Primary). Ein eigener A-RRset `schulpilot` fehlte trotz bereits passender öffentlicher Auflösung. Angelegt wurde ausschließlich `schulpilot/A` → `91.99.217.84`, TTL 300. Kein CNAME-Konflikt, keine Nameserver- oder sonstigen DNS-Änderungen. Autoritativer Server und öffentlicher Resolver wurden nachher geprüft.
