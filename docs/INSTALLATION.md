# Einrichtung und Administration

## Neue Installation

Die Datenbank muss migriert sein; API und der vorhandene Hintergrundworker laufen mit derselben geschützten Grundkonfiguration. Datenbankzugang, `DATA_DIR`, `PUBLIC_URL`, `MASTER_KEY`, HTTPS und Dienstrechte werden weiterhin lokal eingerichtet. Der Browserassistent ändert keine Hostrechte, DNS-Einträge oder Deploymentzugänge.

Eine leere Installation leitet den ersten Webaufruf nach `/setup`. Reguläre Registrierung und Familienfunktionen bleiben bis zum Abschluss gesperrt. Bei vorhandenen Konten oder Familien wird die Installation als eingerichtet erkannt; der Assistent kann keine bestehenden Daten übernehmen.

Beim ersten Dienststart entsteht `<DATA_DIR>/setup-code.txt`, im bereitgestellten Serverlayout `/var/lib/schulpilot/setup-code.txt`. Die Datei ist nur für den Dienstbenutzer beziehungsweise den lokalen Administrator lesbar (0600). Den Code ausschließlich in der geschützten Serversitzung lesen und in das verdeckte Feld des Assistenten eingeben; nicht in Links, Screenshots, Logs oder Git übernehmen. Der Server speichert nur den Hash. Der Code gilt 24 Stunden, die freigeschaltete Einrichtungssitzung 30 Minuten. Das HttpOnly-/SameSite-Strict-Cookie ist auf `/api/setup` begrenzt und im Produktionsbetrieb Secure.

Der Assistent führt durch:

1. Administratorkonto mit eigenem Benutzernamen und mindestens zwölf Zeichen langem Passwort, ohne TOTP.
2. Betreiber-/Supportangaben, dokumentierte Anbieter-/Datenschutzfreigabe, optionale Beispielräume und begrenzte künstliche KI-Tests.
3. SMTP-Absender und Zugang mit TLS/STARTTLS; eine Testnachricht prüft die Annahme durch den Mailserver. Den Eingang im Zielpostfach zusätzlich kontrollieren.
4. Provider, Modelle, Fähigkeiten, Schlüssel, Preis-/Kontingentgrenzen, Datenschutznachweise und Notfallstopp. Metadatenprüfung und tatsächliche Bild-/Aufgabenprüfung bleiben getrennt.
5. Standardtarif und Limits für neu registrierte Familien. Bestehende Familien werden dadurch nicht nachträglich geändert.
6. Optionale Firebase-App-/Dienstkontokonfiguration und Push-Freigabe.
7. Übersicht der Voraussetzungen und ausdrücklicher Abschluss.

SMTP-Passwörter und Firebase-Dienstkontodaten werden mit dem lokalen Master-Key verschlüsselt in der Datenbank gespeichert. Provider-Schlüssel bleiben ebenfalls verschlüsselt serverseitig. Die API gibt nur an, ob ein Geheimnis vorhanden ist; leere Passwortfelder behalten bestehende Geheimnisse. Änderungen gelten für API und Worker ohne Neustart. Pfade, Datenbankkennwort und Master-Key bleiben außerhalb des Assistenten.

Der tatsächliche Providerprüfauftrag ist dauerhaft gespeichert und verwendet ausschließlich feste künstliche Bilder/Texte. Er ist auf OpenRouter Free begrenzt, prüft Bild, Einheit und Tagespaket mit maximal drei Aufrufen, bindet Modell/Upstream und erzwingt Preis 0, gesperrte Datensammlung und die gespeicherte ZDR-Einstellung. Keine automatische Wiederholung. Aufrufe werden im globalen Kontingent mitgezählt; unbekannte Kosten behalten ihre Reservierung. Höchstens ein laufender Prüfauftrag, höchstens drei neue Aufträge pro Stunde und zehn pro Tag. Geänderte Konfigurationen werden durch ein altes Testergebnis nicht freigeschaltet. Andere Provider benötigen die dokumentierte separate fachliche und technische Prüfung; sie werden nicht durch einen Free-Test als funktionsfähig ausgegeben.

Der Abschluss erzeugt atomar genau einen Erstadmin, entwertet sämtliche Setup-Sitzungen und entfernt die Codedatei. Danach bleiben alle Setupänderungen dauerhaft gesperrt. Offene optionale Voraussetzungen werden angezeigt; der Abschluss erzeugt keine fehlenden Mail-, Provider- oder Googlezugänge. Die Android-App verweist zur Ersteinrichtung auf den Browser.

Abgelaufenen Code ausschließlich lokal erneuern:

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py rotate-setup-code'
```

Eine abgeschlossene Installation lässt sich damit nicht erneut öffnen. Für eine eigene lokale Installation entsprechend `PYTHONPATH=backend .venv/bin/python -m schulpilot.cli rotate-setup-code` mit der passenden geschützten Umgebung verwenden.

## Bestehende Installation und Wiederherstellung

Die laufende Installation mit bestehenden Familien erhält keinen neuen öffentlichen Assistenten. Administratoren bearbeiten dieselben Betriebseinstellungen im geschützten Adminbereich. Administratorrechte erlauben weiterhin keinen Zugriff auf private Kinderinhalte. Anmeldung und Änderungen werden protokolliert; Rollenprüfung, Rate Limits und eintägige widerrufbare Adminsitzungen bleiben aktiv.

Lokalen Admin interaktiv anlegen beziehungsweise zurücksetzen:

```bash
ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin'
ssh -t dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py reset-admin --username <adminname>'
```

Ein bestehender Nichtadmin wird nicht hochgestuft. `reset-admin` widerruft dessen alte Sitzungen. Es gibt kein öffentliches Rollenwahlfeld und kein Standardpasswort. Ein vorbelegter Benutzername im Formular erzeugt noch keinen Zugang.

Für ausdrücklich autorisierte Automation unterstützt das lokale CLI `--password-stdin --username <adminname>`. Das Kennwort über eine geschützte Datei oder Pipe an stdin übergeben, niemals als Shellargument, Umgebungsvariable oder Textausgabe:

```bash
ssh -T dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py create-admin --username <adminname> --password-stdin' < /geschuetzter/pfad/admin-passwort.txt
```

Die Datei bleibt auf dem autorisierten Rechner und außerhalb des Repositorys. Kein `set -x`, `cat` in Toolausgaben oder Klartextpasswort in einer Kommandozeile verwenden. Eine vorhandene Adminidentität mit `reset-admin` statt `create-admin` zurücksetzen.

## Migration und Nachweise

Migration **0008** entfernt TOTP-Spalten und widerruft bestehende Adminsitzungen. Passworthashes, Familien, Kinder, Antworten und Kindersitzungen bleiben erhalten. Bestehende Konten schließen die Ersteinrichtung bereits bei der Migration. Ein Rückweg auf alten TOTP-Code benötigt den in [OPERATIONS.md](OPERATIONS.md) beschriebenen Datenbankrückweg; ein Symlinkwechsel genügt nicht.

Nachgewiesen für diese Implementierung: **152 bestandene PostgreSQL-Backendtests** sowie **33 gezielte SQLite-Tests**, einschließlich Migration mit Datenerhalt, genau einem Admin unter parallelem Abschluss, abgelaufenen Codes/Sitzungen, verschlüsselten Einstellungen, Rollenprüfung, Runtime-Freigaben, SMTP und begrenzten Providerprüfungen. Die Transporte dieser Regressionstests sind simuliert und verwenden künstliche Inhalte. Öffentliche Browser-/Android-Abnahmen und der tatsächlich bereitgestellte Build stehen in [STATUS.md](STATUS.md).
