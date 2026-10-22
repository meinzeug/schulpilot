# Benachrichtigungen

Die Glocke im mobilen App-Kopf und im Browser-Kontokopf öffnet eine kleine
Vorschau; „Alle anzeigen“ führt zu `/notifications`.
Kinder und berechtigte Eltern sehen bis zu 50 gespeicherte Neuigkeiten aus den
letzten 30 Tagen. Beim Betriebsadmin öffnet sie ausschließlich `/admin/push`.
Die Übersicht funktioniert ohne Geräte-Push und ohne Firebase-Initialisierung.

Die Prüfung vom 22.10.2026 trennt Googlekonfiguration, serverseitige Anmeldung
und tatsächliche Geräteanzeige. Befunde, Korrekturen und Abnahme stehen in
[FIREBASE_EVALUATION_2026_10_22.md](FIREBASE_EVALUATION_2026_10_22.md).

## Direkter Nachrichtenweg ab 1.13.0

Neue Clients melden `messages-v1` und öffnen bei Elternantworten/Hilfewünschen
`/messages/<child_id>`. Dort ist zuerst die Nachricht lesbar; der zugehörige
Lernstoff ist eine eigene bewusste Aktion. Der Reader verwendet die bestehende
berechtigte kompakte Übersicht, keine Aufgabenantworten oder neue KI. Eltern mit
Leserechten können lesen, weiterhin keine Nachricht senden. Betriebskonten werden
abgewiesen. Ältere Clients behalten ihre bisherigen Routen.

Gelöschte/fremde Verweise werden beim Lesen ausgeblendet; der ursprüngliche
Nachrichtentext und gespeicherte Kontext bleiben erhalten. Die begrenzten
Nachrichten werden stabil nach Datum/ID sortiert. Quellen- und Absenderprüfungen
werden gebündelt geladen. Vorbereitungsnachrichten zu einem inzwischen leeren
Schultag und Prüfaufforderungen zu bereits bestätigten Wortimporten erscheinen
nicht mehr als offene Neuigkeit. GET löscht weder Nachrichten noch Lesebelege.
Laden und eine tatsächlich leere Liste sind sichtbare unterschiedliche Zustände.

## Gerätefreigabe

1. Eltern erlauben beim Kind unter Lernvorgaben → Erinnerungen & Ruhezeiten
   „Push am Kindergerät erlauben“ und speichern die Vorgaben.
2. Am jeweiligen Kindergerät die Glocke öffnen und „Auf diesem Gerät
   einschalten“ wählen. Die Android-/Browsererlaubnis ausdrücklich bestätigen.
3. Ruhezeit und Kategorien auf Wunsch einstellen und speichern. Eltern geben
   ihren eigenen Geräten dieselbe gesonderte Freigabe über die Glocke.

Eine Anmeldung in SCHULPILOT allein ist keine Push-Einwilligung. Ohne die
Elternfreigabe zeigt die Kinderansicht deren konkreten Hinweis. Die Seite prüft
auch Android-Appberechtigung und den Kanal „Lernen & Familie“. Ein gesperrter
Kanal oder eine verweigerte Berechtigung wird nicht als eingeschaltet ausgegeben.
„Android-Einstellungen öffnen“ führt zur passenden Systemseite; nach Rückkehr
wird der Status neu gelesen. Verweigerung, fehlende Google Play-Dienste oder
Netzausfall lassen die In-App-Neuigkeiten weiter nutzbar.

Firebase Core 4.15.0 / Messaging 16.7.0 bleiben fixiert. Nach ausdrücklicher
Einwilligung wird `setAutoInitEnabled(true)` wieder gesetzt; Manifest und Logout
halten Auto-Initialisierung sonst aus. Sitzungswiederaufnahme fragt keine neue
Berechtigung an. Tokenwechsel aktualisiert genau die angemeldete Sitzung;
Fehler werden sichtbar, weitere Versuche erfolgen bewusst beim Speichern oder
bei einer regulären Sitzungswiederaufnahme. Kein Fallbackanbieter.

## Sichtbare Android-Meldung

Der native Flutter-Host erstellt `schulpilot_updates_v1` mit einem weißen
Abschlusshut als Statussymbol. Im Hintergrund präsentiert das vorhandene FCM-SDK
die notification-Nachricht. Im Vordergrund zeigt der eigene eng begrenzte
MethodChannel dieselbe neutrale Android-Meldung sowie den In-App-Hinweis.
Der Kanal ist zunächst ohne Ton/Vibration; eigene Android-Kanaleinstellungen
bleiben maßgeblich. Android 7 / API 24 erhält die kompatible native Darstellung.

FCM erhält eine sichtbare, gebündelte Nachricht mit hoher Transportpriorität;
TTL bleibt höchstens 60 Sekunden und endet vor der nächsten Ruhezeit. Das ist
keine Umgehung von Android-Berechtigungen, Geräteeinstellungen, erzwungenem
Beenden oder fehlenden Play-Diensten. Die App initialisiert weder Analytics noch
einen neuen Sprach-/Audio-/Firebase-Dienst.

Klicks öffnen die angemeldete Neuigkeitenansicht. Systemtexte enthalten weiterhin
keine Namen, Fächer, Noten, Antworten oder privaten Chattexte. Empfangene Daten
werden nicht als beliebige URL ausgeführt. Logout löscht die eigene sichtbare
Android-Meldung und lokale FCM-Registrierung; das Backend widerruft die Sitzung
und damit auch ausstehende Versandberechtigungen.

## Gespeicherte Fakten und Rechte

Die Übersicht projiziert Familiennachrichten, Vorbereitungsnachrichten und
abgeschlossene oder fehlgeschlagene Sprach-/Wortschatzaufträge. Ein Klick öffnet
den bestehenden berechtigten Lern-/Familienbereich. Keine Modellaufrufe oder
Lernfortschritte durch GET oder durch das Öffnen der Glocke. Im Vordergrund
höchstens ein Abgleich alle 45 Sekunden, außerdem bei Push, bewusster
Aktualisierung und Rückkehr aus dem Hintergrund. Kontowechsel löscht den Cache;
verspätete Antworten des früheren Kontos werden verworfen.

Migration **0016 nach 0015** ergänzt nur `notification_reads` mit eindeutigem
Schlüssel `(user_id, event_key)` und löschenden Fremdschlüsseln auf Benutzer und
Kind. Inhalte bleiben in ihren ursprünglichen Tabellen. Lesemarkierungen sind
pro Konto; gleichzeitige Bestätigungen auf zwei Geräten sind idempotent.
Fremde Ereignis-IDs sind nicht bestätigbar. Entzogene Mitgliedschaften und
abgelaufene Familien erscheinen nicht mehr; Betriebsadmins haben keinen Zugriff.

Lesemarkierungen werden nach 30 Tagen entfernt und mit dem zugehörigen Konto
oder Kind gelöscht. Der Familienexport enthält Kinder-Lesemarkierungen und nur
die eigenen Markierungen des exportierenden Elternteils, keine anderer Eltern.

Fertige Sprachprojekte und Wortimporte sind nun zusätzliche gebündelte
Push-Anlässe. Vor Einreihen und Versand werden Quellsitzung, Familienrechte,
aktuelle Quellen, Elternfreigabe, Kategorien und beide Ruhezeiten geprüft.
Weiterhin höchstens ein Tagesbündel je Gerät/Kategorie und kein Hinweis pro
falscher Antwort. Die Warteschlange wird zusätzlich unmittelbar nach Abschluss
eines Workerauftrags geprüft; keine zusätzliche KI-Reservierung.

`/admin/push` zeigt nur Betriebsmetadaten, Geräteanzahlen je Plattform und
Versandstatussummen der letzten 24 Stunden. Eine FCM-Annahme ist ausdrücklich
kein Zustellbeleg. Private Tokens und Nachrichten sind dort nicht zugänglich.

## Prüfung und Betrieb

Ab1.18.4 öffnet die gemeinsame Headerglocke ein Klappmenü mit maximal vier
vorhandenen Neuigkeiten und „Alle anzeigen“ zur vollständigen bisherigen Seite.
Öffnen/Neuladen liest ausschließlich den vorhandenen Posteingang. Erst der
bewusste Klick auf einen Eintrag setzt dessen kontogebundene Lesemarkierung und
öffnet das bereits serverseitig geprüfte Ziel. Leere und fehlgeschlagene Abrufe
haben eigene Zustände. Betreiber sehen ausschließlich den Push-Betrieb, keinen
privaten Familienposteingang. Das Kontomenü enthält Einstellungen und Abmelden.
Verzögerte Abmeldeantworten dürfen eine inzwischen neu angemeldete Sitzung nicht
löschen; Identitätsprüfung gilt auch bei erneuter Anmeldung desselben Kontos.

Gezielte Prüfung:

```sh
TMPDIR=/dev/shm .venv/bin/python scripts/test_postgres.py backend/tests/test_notification_inbox.py backend/tests/test_notifications.py backend/tests/test_push_handoff.py
cd app
flutter test test/push_client_test.dart test/notification_inbox_test.dart test/browser_workspace_test.dart
```

Eigene künstliche Android-Geräteprüfung nach regulärem Build und Deployment:

```sh
SCHULPILOT_QA_ADB_SERIAL=emulator-5560 \
SCHULPILOT_QA_PUSH_CREDENTIALS="$PWD/artifacts/firebase84/.qa-private.json" \
  .venv/bin/python qa/android_push_background.py \
  --expected-code 84 --cold-process --foreground
```

Versionscode und privater Fixturepfad müssen zur ausdrücklich freigegebenen
Prüfung passen. Der alte lokale Standardpfad bleibt kompatibel; neue künstliche
Fixturedateien dürfen die Zugangsdaten unter `credentials` kapseln und müssen
dann `synthetic_only=true` ausweisen. Dateien benötigen Modus 0600. Zusätzlich
prüft der Server weiterhin Sitzung, künstlichen Haushalt, zeitbegrenzte
Testfreigabe, Elternzustimmung und Ruhezeiten; die lokale Markierung ersetzt
diese Prüfungen nicht. Tastatureingaben gehen ausschließlich über ADB-stdin.

Die Prüfung beobachtet STOPPED vor genau einem Hintergrundversand. Mit
`--cold-process` beendet sie anschließend nur den zwischengespeicherten Prozess
(`am kill`, kein `force-stop`) und verlangt eine leere PID-Abfrage vor der
Sendreservierung. Danach werden sichtbare Android-Anzeige, Klickziel und mit
`--foreground` genau eine gesonderte Vordergrundnachricht geprüft. Atomare
lokale Reservierungen verhindern versehentliche Wiederholungen nach Abbruch
oder bei gleichzeitigem Start. Keine Reservierungsdatei löschen, um einen
fehlgeschlagenen Lauf automatisch zu wiederholen. Kein öffentlicher Versand an
frei wählbare Tokens. Webprüfungen benötigen entsprechend beobachtete
Browser-/Systemzustellung. Ergebnisse und konkrete Endgerätelücken stehen in
STATUS und CHATGPT_HANDOFF.

Rückweg: Vor Deployment eigene verschlüsselte Sicherung prüfen. Alter Release
`20261017T140346Z-58f2c8c` kann mit unveränderter additiver Tabelle 0016 betrieben
werden (`--rollback-compatible`); Migration nicht zurückrollen oder vorhandene Antworten löschen. Alte
Clients verwenden weiterhin die bisherigen Push-APIs und das feste `/app`-Ziel.
Nach einem APK-Update bleiben Signierer, Paket und Konten erhalten; Android-APKs
werden nicht automatisch heruntergestuft. Vorwärtskorrektur bevorzugen.

## Altverweise und gelöschte Sprachrunden ab 1.14.3

Nachrichtenreader und Glocke verwenden dieselbe gebündelte Zielprüfung gegen
das eigene Kind. Auch ältere Clients bekommen keine gelöschten/fremden Links;
die ursprüngliche Nachricht bleibt erhalten. Jobtombstones nach Rundenlöschung
erzeugen keine neue „Sprachübung bereit“-Meldung. Vorbereitungszeilen mit mehr
als zwei Fächern kennzeichnen die gekürzte Auswahl. GETs bleiben ohne Writes/KI.
