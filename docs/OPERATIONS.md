# Betrieb

## Sprachwerkstatt-Korrektur · 18.10.2026

Aktiver Release 20261018T125246Z-8ada817, Produktcommit8ada817.
Belegfix und Ergänzung 1.4.4+34 erlauben eine ausdrückliche Wiederaufnahme aus einer frischen Kindersitzung.
Keine Migration: Schema bleibt 0016, ältere Clients bleiben bedienbar.
Vor Aktivierung regulär sichern und nur SCHULPILOT-Dienste erneuern.
Kompatibler Code-Rückweg auf `20261018T121428Z-9e53947`, zusätzliche Aufträge
erst kontrolliert abarbeiten; keine Datenrücksicherung und kein Schema-Downgrade.

Lokaler einmaliger Reparaturweg für ausdrücklich beauftragte Fehler steht in
LANGUAGE_LEARNING.md. Alte Job-/Verbrauchsbelege erhalten, normale Reservierung
und Worker verwenden. Kein ungeschützter Operatorendpunkt und kein automatischer Retry. Der normale
authentifizierte Kinder-POST verlangt eine neue bewusste Aktion; lokale
Reparatur und Kinderaktion zusammen höchstens ein Zusatzauftrag je Projekt.
Abgemeldete Sitzung niemals reaktivieren; nach normalem Login ursprünglichen
Projektlink öffnen und „Erneut vorbereiten“ wählen.
Abnahme: eigenes normales künstliches Konto vorbereiten mit
`scripts/prepare_language_smoke.py`; nach gesichertem Deployment
`node qa/workshop_exam.mjs --run --expected-commit <vollständiger Produktcommit>`,
danach `qa/android_workshop_exam.py` und `qa/workshop_exam_cleanup.py`.
Fehlgeschlagene KI-Aufträge nicht durch erneuten Skriptstart neu erzeugen.
Aktivierung und tatsächlich erzielte Ergebnisse in STATUS/Handoff nachlesen.

## Foto-Wortschatz 1.4.3+33

Aktiviert am 18.10.2026: `20261018T112557Z-48add35`. Sicherung erfolgreich,
Schema und sieben vorhandene Dienste tatsächlich geprüft. Öffentliche/nativ
beobachtete Abnahme und Grenzen stehen in STATUS/Handoff.

Keine Schemaänderung, Datenbank bleibt auf 0016. Verwendet vorhandene private
Wortschatztabellen und dieselben Quellen-/Export-/Löschwege. Wörtliche Übernahme
im Bestätigungsvorgang benötigt keine weitere KI-Reservierung; unklare Paare
bleiben offen. Bestehende manuelle und ausdrückliche KI-Importe bleiben erhalten.
Vor Aktivierung erfolgreiche Sicherung prüfen. Kompatibler Rückweg auf
`20261018T101528Z-505312c` ohne Schema-Downgrade; vorhandene Wörter/Antworten
erhalten. APKs werden nicht automatisch heruntergestuft. Im alten Backend
bleibt das neue Wörter-Menü bedienbar; das neue nachträgliche Übernehmen einer
Seite fehlt dort. Vorwärtskorrektur bevorzugen.

Abnahme nur mit dem eigenen regulären künstlichen Haushalt:
`scripts/prepare_language_smoke.py`, `node qa/material_words.mjs --run`,
nach tatsächlichem OTA `qa/android_material_words.py`, anschließend
`qa/material_words_cleanup.py --run`. Private Checkpoints in artifacts bleiben
0600 und außerhalb von Git. Fehlgeschlagene OCR-Aufträge nicht automatisch
wiederholen. Aktivierten Release und reale Ergebnisse in STATUS/Handoff prüfen.

## Designrelease 1.4.2+32

Gemeinsame Flutter-Gestaltung ohne Schemaänderung; Datenbank bleibt auf 0016.
Keine Provider-, Sitzungs-, Firebase- oder Familienänderung durch den Release.
Vor Aktivierung die reguläre Sicherung mit Result=success prüfen.
Vorheriger Code: `20261017T202938Z-dd6e30c`; mit `--rollback-compatible`
reaktivierbar, additive Tabelle 0016 erhalten. Keine Datenrücksicherung und kein
Schema-Downgrade für eine Gestaltungskorrektur. Installierte APKs werden nicht
automatisch heruntergestuft; eine Vorwärtskorrektur bevorzugen.
Aktivierung und tatsächliche Abnahme erst nach den Ergebnissen in STATUS/Handoff
als erfolgt behandeln. Detailregeln: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

## Benachrichtigungsrelease 1.4.1+31

Migration 0016 ergänzt ausschließlich private Lesemarkierungen in
`notification_reads`; keine bestehenden Quellen, Antworten, Noten, Lernzeiten,
Provider- oder Firebasefreigaben umschreiben. Vor Aktivierung wie bisher eine
erfolgreiche verschlüsselte Sicherung prüfen. Deployment baut keine zusätzliche
Infrastruktur. API und vorhandener Worker verwenden dieselbe Datenbank.

Rückweg auf `20261017T140346Z-58f2c8c`: Eigene laufende Aufträge kontrolliert
beenden, sichern und den vorherigen Release mit den bisherigen Werkzeugen
mit `--rollback-compatible` aktivieren. Tabelle 0016 erhalten; kein Datenbank-Downgrade und kein Restore über
neuere Familienverläufe. Alte Push-APIs und das feste neutrale `/app`-Payloadziel
bleiben kompatibel. Die neue Glocke/Lesemarker fehlen im alten Clientcode;
installierte Android-APKs werden nicht automatisch heruntergestuft.
Aktivierten Release und tatsächlich beobachtete Zustellung in STATUS/Handoff
nachlesen; In-App-, FCM-Annahme- und sichtbare Geräteprüfung getrennt halten.
Bedienung und Prüfwerkzeuge: [NOTIFICATIONS.md](NOTIFICATIONS.md).
Die neue APK 31 behält beim Backend-Rückweg ihre Glocke; der ältere Server kennt
die Übersicht nicht und zeigt dort einen Ladehinweis. Gerätefreigabe unter
Konto sowie die bisherigen Lernabläufe bleiben verfügbar. Deshalb eine
Vorwärtskorrektur bevorzugen. Dies ist ein dokumentierter Rückweg, kein in
dieser Sitzung ausgeführter produktiver Rollback.

## Aktiver Sprachrelease 1.4.0+30

Am 17.10.2026 aktiviert: `20261017T140346Z-58f2c8c`, Schema 0015.
Der tatsächlich geprüfte vorherige Zeiger ist `20261017T135240Z-74fa0fb`;
dieser kennt bereits 0015, die Sprachbewertung und beide neuen Auftragsarten.
Ein Code-Rückweg zwischen diesen beiden Releases ist ohne Schema-Downgrade
kompatibel; laufende Aufträge trotzdem kontrolliert beenden und sichern.
Installierte APKs werden nicht automatisch heruntergestuft. Für einen Rückweg
auf Code vor 0015 gelten ausdrücklich die strengeren Vorgaben unten.

Öffentliche Foto-/Sprachprüfung nur mit eigenem künstlichem Haushalt:
`scripts/prepare_language_smoke.py`, `qa/language_learning.mjs --run`, danach
eigene Emulatorprüfung `qa/android_language.py --run`. Der geschützte lokale
Kontodatensatz enthält auch Wiederaufnahme-IDs. Keine fehlgeschlagenen Aufträge
automatisch erneut erzeugen. Der einmalige Flag `--retry-failed-context` ist nur
eine bewusste Nachprüfung nach nachgewiesener Korrektur, keine Produkt-Automatik.
Nach erfolgreicher Web-/nativer Prüfung kontrolliert `qa/language_cleanup.py --run`
den privaten Export in Arbeitsspeicher, löscht ausschließlich den eigenen
Testhaushalt und prüft die alten Sitzungen. Alternativ erlaubt
`scripts/prepare_language_smoke.py --cleanup` die Bereinigung auch nach Abbruch.
Der aktuelle künstliche Haushalt wurde bereits gelöscht; keine Testzugänge
oder Exportdateien öffentlich bereitstellen. Ergebnisse in STATUS/Handoff.

## Migration 0014 und Rückweg

Release 1.3.0+28 ergänzt `school_grades` und `children.grade_planning_enabled`; keine vorhandenen Antworten, Lernzeiten, Quellen, Familien oder Providerdaten werden migriert/umgeschrieben. Die Standardfreigabe betrifft ausschließlich die neue optionale Notengewichtung. Bestehende Elternvorgaben bleiben unverändert; bereits vorbereitete Pakete ohne Noteneinträge behalten ihren bisherigen Planfingerprint. Noten werden über den normalen Familienexport gesichert und mit dem Kind gelöscht; der Wartungslauf hält dieselbe Höchstfrist von 365 Tagen wie für den Lernverlauf ein.

`scripts/deploy.sh` sichert die projektspezifische Proxykonfiguration und vor der Migration die Datenbank einschließlich drainender Worker. Bei einem Fehler nach erfolgter Migration nicht automatisch das Schema zurücksetzen. Kompatiblen Code-Rückweg mit dem gesicherten vorherigen Release und `--rollback-compatible` aktivieren; zusätzliche Spalte/Tabelle stehen lassen. Das vorherige Programm kann weiter mit vorhandenen Accounts und Antworten arbeiten, zeigt die neue Notenverwaltung jedoch nicht. Eine Schema-Rückstufung würde neue Noteneinträge löschen und gehört nicht zum gewöhnlichen Rollback. Keine produktive Rücksicherung ohne separate Wiederherstellungsprüfung und Löschjournalabgleich.

## Bestehender Server

`ssh dorfspy`, `91.99.217.84`, Ubuntu 24.04, vorhandenes Caddy 2.6.2 und PostgreSQL 16. Andere Anwendungen bleiben unverändert. Projektbenutzer `schulpilot`, Datenbank/Rolle `schulpilot` mit lokaler Peer-Authentifizierung, API ausschließlich `127.0.0.1:3240`. Datenbank und Caddy-Verwaltungsport bleiben lokal. Keine kostenpflichtigen Ressourcen bestellt.

`/opt/schulpilot/releases/<id>` enthält Backend, eigenes Virtualenv, Flutter-Web und Deploymentdateien. `/opt/schulpilot/current` ist ein atomar ersetzter Zeiger, `/opt/schulpilot/previous` verweist auf den vorherigen Code. Seine Verwendbarkeit hängt zusätzlich vom Datenbankschema ab. Daten unter `/var/lib/schulpilot`, lokale Grundgeheimnisse in `/etc/schulpilot/environment` (root:schulpilot, 0640), Sicherungsschlüssel `/etc/schulpilot/backup.key` (0600). Veränderbare SMTP-/Firebase-Betriebsgeheimnisse und Provider-Schlüssel können verschlüsselt in der Datenbank liegen; der Master-Key bleibt lokal und muss separat gesichert werden. Entwicklungs-, Hetzner-, SSH- und GitHub-Zugänge werden nicht übertragen. Der Hetzner-Schlüssel bleibt ausschließlich auf dem Entwicklungsrechner.

## Ersteinrichtung und Admin

Eine leere Datenbank öffnet beim ersten Webaufruf den einmaligen Einrichtungsassistenten. Er benötigt den lokal erzeugten Code aus `/var/lib/schulpilot/setup-code.txt`, richtet den Passwort-Admin ohne TOTP ein und speichert Betrieb, Mail, Provider, Grenzen und optionale Push-Konfiguration. Vorhandene Familien/Konten lassen diese Route geschlossen. Lokale Adminanlage/-wiederherstellung, Ablauf/Rotation des Codes und sichere stdin-Automation sind in [INSTALLATION.md](INSTALLATION.md) beschrieben. Providerprüfungen verwenden ausschließlich feste künstliche Inhalte und den vorhandenen unprivilegierten Worker.

## Deployment

Nach Tests und Web-Build aus dem Repository: `bash scripts/deploy.sh`. Das Script legt ausschließlich Projektressourcen an, lädt einen eigenen Release hoch, installiert exakt `requirements.lock`, sichert Caddy und prüft die ergänzte Konfiguration. Bei einer bestehenden Installation erstellt es vor Aktivierung eine neue Projektsicherung und kontrolliert den Diensterfolg. Eigene API und Worker werden vor der Migration angehalten; danach wird nochmals gesichert, damit während des Anhaltens fertiggestellte Antworten und Aufträge enthalten sind. Anschließend werden die Migration ausgeführt, beide Dienste aktiviert und Caddy neu geladen. Healthcheck lokal und anschließend über HTTPS. Die erstmalige Zertifikatsausstellung darf mit begrenzten GET-Wiederholungen abgewartet werden. Änderungen am Datenbankschema benötigen eine zum Rückweg passende Migration; ein Code-Rollback ersetzt keine Datenrücksicherung.

Die Caddy-Hauptdatei erhält lediglich `import /etc/caddy/schulpilot.caddy`. Das Fragment übernimmt `/api` einschließlich Unterpfaden; alle anderen Direktlinks fallen auf Flutter `index.html` zurück. Statische Ressourcen kommen vom eigenen Server, ohne externes Flutter-CDN. Let’s Encrypt wird über Caddy ACME HTTP-01 bezogen und automatisch erneuert; HTTP leitet per 308 auf HTTPS. Die bestehende Caddy-Version bleibt erhalten.

Dienste: `schulpilot-api.service`, `schulpilot-worker.service`, `schulpilot-backup.timer`. Automatischer Start und Neustart bei Ausfall; unprivilegierte API/Worker, schreibgeschützter Anwendungscode, geschütztes Home, minimale Fähigkeiten, getrennte Speicherlimits. Keine vollständigen Anfragen/Antworten in Zugriffslogs. `systemctl status`, `/api/health` und `journalctl -u schulpilot-api -u schulpilot-worker` dienen der Diagnose. Ein eigener Prozess-Watchdog und eine unabhängige HTTPS-Prüfung auf dem zweiten Host sind vorbereitet; Einrichtung und tatsächlicher Prüfstand stehen unten beziehungsweise in STATUS.md.

## Rückweg

Sprachrelease **0015 / 1.4.0** ergänzt Tabellen und kompatible Attempt-Spalten,
verändert aber die Bewertung neuer Sprachrunden. Vor jeder Aktivierung sichern
und nur SCHULPILOT anhalten/migrieren. Rückweg auf Code vor 0015 ist nach
Sprachbenutzung kein gewöhnlicher `--rollback-compatible`-Vorgang: neue Jobs
(`vocabulary_import`, `language_project`) und neue Aufgaben dürfen weder an den
alten Worker noch an die alte globale Bewertung gelangen. Aktive Aufträge erst
kontrolliert beenden/abbrechen, Schreibzugriffe stoppen und einen kompatiblen
Korrekturrelease einsetzen. Vor neuer Sprachbenutzung (alle neuen Tabellen leer,
keine neuen Aufträge/Sprachrunden) ist der bisherige gesicherte Rückweg möglich.
Andernfalls Restore nur separat prüfen, Löschjournal abgleichen und neue Belege
erhalten; kein routinemäßiges Schema-Downgrade. Details: LANGUAGE_LEARNING.md.

Aktiven und vorherigen Release prüfen: `readlink -f /opt/schulpilot/current` / `readlink -f /opt/schulpilot/previous`.

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/activate.py <vorherige-release-id> --rollback-compatible'
```

Das verwendet denselben Aktivierungsweg, überspringt beim ausdrücklich bestätigten kompatiblen Code-Rollback jedoch die Migration aus dem alten Release. **Nur verwenden, wenn das aktuelle Schema mit dem alten Code kompatibel ist.** Caddy-Sicherungen liegen unter `/etc/caddy/Caddyfile.before-schulpilot-<zeit>`; keine Sicherung einer fremden Anwendung blind zurückspielen. Ein Datenbankupgrade kann bereits erfolgreich committed sein, bevor ein späterer Healthcheck scheitert. Ein automatischer oder manueller Releasewechsel ersetzt dann keine Datenrücksicherung. Migration 0002 ergänzt kompatible Spalten mit Serverdefaults; für inkompatible Migrationen gelten die zusätzlichen Schritte unten.

Bei einem Aktivierungsfehler vergleicht der Aktivierer den Schemastand vor und nach dem Migrationsversuch. Nur bei unverändertem Schema wird der vorherige Code automatisch wieder gestartet. Bei geändertem oder nicht zuverlässig ermittelbarem Schema bleiben die SCHULPILOT-Dienste gestoppt und ein ausdrücklicher Wiederherstellungshinweis erscheint. Betroffene Caddy-Einstellungen werden zurückgesetzt; fremde Anwendungen werden nicht angehalten.

Migration 0007 ergänzt kompatible Spalten und die private Lernbegleitung. Vor dem ersten Upgrade sichern. SQLite verwendet direkte additive Spaltenänderungen; ein Tabellenneuaufbau bei aktiven Fremdschlüsseln würde Antwortdaten gefährden und wird vermieden. Vor einem Rückweg auf Code ohne `coaching.py` die SCHULPILOT-API anhalten und den Worker seine laufenden Coach-Aufträge beenden lassen. Mit `SELECT count(*) FROM jobs WHERE kind='coach' AND status IN ('queued','running');` in der privaten Projektdatenbank prüfen, dass keine solchen Aufträge mehr offen sind. Erst dann den kompatiblen Code-Rollback ausführen; kein gewöhnliches Schema-Downgrade. Andernfalls könnte alter Worker-Code neue Auftragstypen falsch behandeln.

Migration 0009 ergänzt Verkauf und künstliche Push-Testfreigaben. Gewöhnliche Korrekturen zwischen aktuellen 0009-Releases benötigen keinen Schema-Downgrade. Ein Rückweg auf Code vor 0009 ist nach kommerzieller Aktivierung nicht als gewöhnlicher kompatibler Rollback zulässig: alter Code kennt weder bezahlte Laufzeiten noch deren Zugangssperren. Erst Verarbeitung pausieren und einen getrennt geprüften Daten-/Code-Rückweg unter Erhalt der Zahlungsbelege und Löschabgleiche vorbereiten. `alembic downgrade` würde neue Belege/Testfreigaben löschen und ist kein normaler Betriebsrückweg.

### Inkompatible Grenze 0008

Migration **0008 entfernt `users.totp_secret` und `users.totp_last_step`**. Code aus `c7b1f88` oder einem anderen Stand vor 0008 erwartet diese Spalten; `--rollback-compatible` ist dafür ausdrücklich ungeeignet. Die Migration erhält bestehende Passworthashes und Kinder-/Familiendaten, widerruft aber alte Adminsitzungen. Bestehende Konten/Familien schließen den Erstaufruf-Wizard bereits beim Upgrade.

Vor dem Upgrade eine neue verschlüsselte Sicherung erfolgreich erstellen und den Release sowie den Sicherungszeitpunkt festhalten. Für einen Rückweg über diese Grenze:

1. Neue SCHULPILOT-Schreibzugriffe und Anbieterprüfungen verhindern; eigene API anhalten, laufende Arbeiten kontrolliert beenden und den eigenen Worker stoppen. Andere DorfSpy-Dienste weiterlaufen lassen. Aktuellen Stand zusätzlich sichern.
2. Eine zum alten Release passende Sicherung zuerst in einer **separaten Datenbank** wiederherstellen. Neuere Migrationen dort nicht automatisch ausführen. Das aktuelle authentifizierte Löschjournal mit dem dokumentierten Werkzeug abgleichen; Sitzungen/Einmallinks widerrufen, Kosten-/Kontingentstand und seit dem Backup neu entstandene Daten prüfen. Fehlende neuere Datensätze nicht als unverändert wiederhergestellt ausgeben.
3. Alten Code gegen diese getrennte Datenbank und passende Uploadkopien prüfen. Die wiederhergestellten TOTP-Geheimnisse gehören zum alten Stand; erforderliche lokale Adminwiederherstellung ausdrücklich testen. Einrichtung, Providerzugänge und nach dem Backup geänderte Rechte ebenfalls prüfen.
4. Erst den konkret geprüften Daten-/Codekombinationsstand im Wartungsfenster aktivieren und HTTPS-/Rollen-/Lernprüfungen ausführen. Keine automatische produktive Überschreibung durch ein Restore-Prüfprogramm.

Ein Schema-Downgrade auf 0007 erzeugt nur leere TOTP-Spalten und stellt entfernte Zweitfaktoren nicht wieder her. Es ist kein gleichwertiger Rückweg auf den alten Adminbetrieb. Für gewöhnliche Fehler bevorzugt eine korrigierte aktuelle Version einsetzen. Der allgemeine regelmäßige Restorecheck migriert absichtlich auf den aktuellen Stand; für einen alten Release muss die getrennte Rückwegprobe deshalb ausdrücklich das alte Schema beibehalten.

## Sicherungen und Wiederherstellung

### Rückweg über Mindestlernziele (17.10.2026)

Die Änderung benötigt keine Schema-Migration; gespeicherte Minutenwerte bleiben unverändert. Alter Code interpretiert sie wieder als Obergrenzen und kennt die neue Zeit-Baseline nicht. Ein Rückweg würde daher freiwilliges Weiterlernen wieder sperren und die neue Zeitmessung beeinträchtigen. Bevorzugt vorwärts korrigieren. Falls ein Code-Rückweg unvermeidbar ist, eigene laufende Aufträge kontrolliert beenden lassen und sichern; über die wieder eingeführten Lernbeschränkungen ausdrücklich entscheiden. Keine Lernverläufe, beantworteten Aufgaben oder historisch erfassten Sekunden zurücksetzen und keine alte Gesamtdatenbank über neue Daten spielen. Konfiguration von KI-Provider und Reasoning bleibt beim Codewechsel erhalten.

### Rückweg über die Codex-Denkstufe (0013)

Migration 0013 ergänzt nur `provider_config.reasoning_effort` mit dem bisherigen Wert `medium`; keine Quelle, Antwort, Konfigurationsrevision oder Freigabe wird dabei zurückgesetzt. Die Spalte beim gewöhnlichen Code-Rückweg erhalten. Alter Backend-/Workercode kennt die Auswahl nicht und verwendet stets `medium`. Deshalb bei einer später gewählten anderen Denkstufe nicht unbemerkt zurückrollen: Zuerst neue Aufträge unterbinden, eigene laufende Aufträge beenden lassen und eine aktuelle Sicherung erstellen. Eine ausdrücklich gewählte, katalogkompatible `medium`-Konfiguration unter dem neuen Code speichern und regulär prüfen oder einen korrigierten neuen Release verwenden. Erst bei nachvollziehbar passender Modell-/Denkstufenkonfiguration den alten Code aktivieren. Keine alte Gesamtdatenbank über neuere Familienverläufe zurückspielen und keine Modell-/Kostenlimits für den Rückweg stillschweigend ändern.

### Rückweg über die Hintergrundvorbereitung (0012)

Migration 0012 ergänzt `school_days.preparation` additiv. Kein gewöhnliches Schema-Downgrade durchführen: Die gespeicherten Bearbeitungsstände gehören zu den privaten Familienverläufen. Vor einem Code-Rückweg auf 0011 zuerst die eigene API für neue Vorbereitungen sperren, den neuen Worker seine aktuellen Anbieteraufrufe beenden lassen und eine aktuelle verschlüsselte Sicherung erstellen. Offene `jobs` mit `payload.preparation_id` dürfen nicht von einem alten Worker bearbeitet werden, weil dieser die zusätzliche Auftragssitzungsprüfung nicht kennt. Diese Aufträge unter dem neuen Code kontrolliert beenden oder vor einem Rückweg ausdrücklich sicher abbrechen; Kosten/Reservierungen dabei erhalten. Ebenso laufende `school_days.preparation.status=processing` prüfen und ihren Zwischenstand dokumentieren. Erst wenn kein solcher Auftrag mehr offen ist, den vorherigen kompatiblen Code aktivieren. Die zusätzliche JSON-Spalte und inzwischen gespeicherte Seiten/Antworten erhalten; nie die ganze Datenbank auf einen älteren Sicherungsstand überschreiben.

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

Gmail-SMTP wurde nach ausdrücklichem Auftrag aus dem vorhandenen verschlüsselten Merchagent-Mailtresor in die separate geschützte SCHULPILOT-Umgebung übernommen. TLS-Zertifikate werden geprüft. Der Read-only-IMAP-Test sucht nur die zufälligen eigenen Testaliase und liest mit BODY.PEEK; er ändert keine anderen Nachrichten oder Merchagent-Einstellungen. `scripts/mail_smoke.py --browser` prüft echte Zustellung, Übernahme des Link-Codes und Neuladen der drei Flutter-Formulare, Registrierung, Einladung, Wiederherstellung, Rechteentzug und Bereinigung. Zugangsdaten und Mail-Links werden nicht ausgegeben. Verwendet explizit autorisierte TEST_IMAP_USER/PASSWORD nur in der Prozessumgebung oder die bereits geschützte lokale Projektdatei `~/.local/share/schulpilot-operations/monitor.env`. Browsergeheimnisse werden ausschließlich über stdin übergeben. Benötigt die fixierten QA-Abhängigkeiten aus `qa/`.

E-Mail-Codes bleiben im URL-Fragment `#token=…`, damit sie nicht in HTTP-Zugriffsprotokollen oder Referrer-Headern erscheinen. Der Flutter-Pfadrouter muss dieses Fragment mit `PathUrlStrategy(..., true)` erhalten. Bestätigung, Einladung und Wiederherstellung übernehmen es aus `GoRouterState.uri`; beschädigte Links dürfen keine alten Codes weiterverwenden.

OpenRouter Free ist ausdrücklich als Standard beauftragt und freigegeben: [AI_STANDARD.md](AI_STANDARD.md). `configure-free-standard` erhält den vorhandenen verschlüsselten Schlüssel, stellt auf den festen kostenlosen Bild-/Textendpunkt mit Data-Collection-Deny ohne zusätzliche ZDR-Pflicht um und sperrt ihn bis zur dreiteiligen technischen Probe. `probe-private-route` liefert bei fehlgeschlagener Prüfung einen Fehlerstatus und aktiviert nichts. Für den getrennten festen KI-Testpfad bleiben `SYNTHETIC_AI_ENABLED=true` und `SYNTHETIC_AI_DAILY_LIMIT=40` gesetzt. Der ältere Schlüsselimport `configure-free-tests` ist ausschließlich eine Einrichtung des isolierten Fixture-Modus und setzt die normale Anbieterfreigabe zurück; ihn nicht als erneute Einrichtung des regulären Standards verwenden. Ein globaler Notfallstopp sperrt auch die synthetischen Testaufrufe.

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

Migration 0010 ergänzt ausschließlich Google-Identitäten und kurzlebige Anmeldevorgänge. Ein kompatibler Rückweg auf den bisherigen Release 1.0.0+14 ist mit `--rollback-compatible` ohne Schema-Downgrade möglich: bestehende Elternpasswörter und Familienschemata bleiben erhalten. Die optionale Google-Anmeldung entfällt dann vorübergehend; neue Google-Eltern haben ebenfalls ein eigenes Elternpasswort. Die zusätzlichen Tabellen erhalten, nicht per Downgrade löschen. Den HTML-Inhabernachweis für die SCHULPILOT-Subdomain bei längerem Rollback weiter bereitstellen oder den Rückweg um diese öffentliche Datei ergänzen. Keine anderen Domains oder Dienste ändern.
