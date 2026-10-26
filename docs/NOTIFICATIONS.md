# Benachrichtigungen

Die Glocke im mobilen App-Kopf und im Browser-Kontokopf öffnet eine begrenzte,
inline scrollbar nutzbare Liste aller bereits geladenen Neuigkeiten;
„Alle anzeigen“ führt zur großen gefilterten Ansicht unter `/notifications`.
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
TTL bleibt normalerweise höchstens 60 Sekunden und endet vor der nächsten Ruhezeit.
Die unten beschriebene Kategorie `parent_goal` verwendet eine begrenzte Ausnahme
von höchstens einer Stunde. Das ist
keine Umgehung von Android-Berechtigungen, Geräteeinstellungen, erzwungenem
Beenden oder fehlenden Play-Diensten. Die App initialisiert weder Analytics noch
einen neuen Sprach-/Audio-/Firebase-Dienst.

Klicks öffnen standardmäßig die angemeldete Neuigkeitenansicht; geprüfte
Fertigmeldungen können gezielt ihre gespeicherte Runde öffnen (siehe142 unten).
Systemtexte enthalten weiterhin
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
Für allgemeine Tageskategorien bleibt es bei höchstens einem Tagesbündel je
Gerät/Kategorie. Auftragsgebundene Fertigmeldungen verwenden die unten
beschriebene Ereignis-Deduplizierung; es gibt keinen Hinweis pro falscher Antwort. Die Warteschlange wird zusätzlich unmittelbar nach Abschluss
eines Workerauftrags geprüft; keine zusätzliche KI-Reservierung.

`/admin/push` zeigt nur Betriebsmetadaten, Geräteanzahlen je Plattform und
Versandstatussummen der letzten 24 Stunden. Eine FCM-Annahme ist ausdrücklich
kein Zustellbeleg. Private Tokens und Nachrichten sind dort nicht zugänglich.

## Prüfung und Betrieb

Die gemeinsame Headerglocke zeigt alle bereits geladenen Neuigkeiten in einem
höhenbegrenzten eigenen Scrollbereich; die bestehende Servergrenze bleibt50.
„Alle anzeigen“ öffnet weiterhin die große Ansicht mit Suche und Filtern.
Nach dem Öffnen bzw. Scrollen werden nur tatsächlich sichtbar gerenderte
Einträge über das bestehende ausdrückliche POST als gelesen markiert.
Die große Ansicht verwendet dieselbe Sichtbarkeitsprüfung. Vorgeladene oder
außerhalb des Viewports liegende Karten zählen nicht; ein verdeckender Dialog,
anderes Konto oder Hintergrundzustand verhindert neue Lesebelege. Eine teilweise
sichtbare Karte benötigt konservativ mindestens die halbe Fläche und48Pixel Höhe.

Die Markierung folgt erst auf eine erfolgreiche Serverantwort; Fehler lassen
den Eintrag ungelesen. Gleichzeitiges Anzeigen und Anklicken teilen denselben
laufenden Leseschreibauftrag. Ein neuer bewusster Ansichtsaufruf, Filterwechsel
oder Abgleich kann einen fehlgeschlagenen Beleg erneut versuchen; ein Rebuild
startet keine automatische Wiederholungsschleife. Im Ungelesenfilter bleiben
soeben gelesene Karten bis zur nächsten bewussten Auswahl stehen, damit keine
unsichtbaren Nachfolger automatisch nachrutschen und ebenfalls gelesen werden.
GETs und Backendprojektionen bleiben schreibfrei; keine KI, Lernzeit oder
Kompetenz entsteht aus Sichtbarkeit oder einer Lesemarkierung. Ein Klick öffnet
das bereits serverseitig geprüfte Ziel. Leere und fehlgeschlagene Abrufe haben
eigene Zustände. Betreiber sehen ausschließlich den Push-Betrieb, keinen privaten
Familienposteingang. Das Kontomenü enthält Einstellungen und Abmelden.
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

## Klassenarbeiten · 1.32.0+106

`exam_reminder` und `exam_ready` stammen aus aktuellen gespeicherten
Lernterminen/Runden bzw. Arbeitsbesprechungen. Keine kostenpflichtige Arbeit
startet durch Lesen oder eine Erinnerung. Geräteeinwilligung, Kinderfreigabe,
beide Ruhezeiten, aktuelle Sitzung/Mitgliedschaft und Quellenrevisionen bleiben
Pflicht. Ein ausdrücklich aktivierter Exam-Termin braucht nicht zusätzlich
den allgemeinen Tageserinnerungsschalter. Fertigmeldungen nach einem bewusst
angeforderten Auftrag folgen dem vorhandenen Geräte-Erinnerungsopt-in.

Das Glocken-Capability `exams-v1` ermöglicht den gezielten App-Einstieg.
FCM `data.route` bleibt `/app`; ein optionales `exam_path` nimmt ausschließlich
den servererzeugten lokalen Exam-Pfad mit festen UUID-Parametern oder eine
Unit-ID an. Web-Serviceworker und Flutter prüfen denselben endlichen Pfadraum.
Kein Name, Fach, Prüfungstitel, Notentext oder privater Inhalt im Push.
Kontowechsel/Abmeldung verwerfen vorgemerkte Ziele und Vordergrundaktionen.


106: Fertigmeldungen der Fotoverarbeitung verlinken auf den konkreten Schultag
(`/after-school/<Kind>?day=<Tag>`), mit derselben strikten lokalen Whitelist in
Web-Serviceworker und APK. Pro Gerät, Schultag, Verarbeitungsdurchlauf und Status
ist eine Meldung möglich; ein späterer erfolgreicher Wiederholungsdurchlauf wird
nicht durch eine ältere Meldung desselben Tages unterdrückt. Sitzung, Quellen,
Elternfreigabe, Geräte-Opt-in und beide Ruhezeiten werden vor Versand erneut
geprüft. Firebase-Annahme ist kein Beweis für eine sichtbare Android-Zustellung.

## Persönliche Eltern-Lernhinweise · 1.34.0+109

Eltern können je eigenem Kind unter Einstellungen → Familie →
„Lernhinweise einstellen“ Wochentage, Uhrzeit und Zeitzone wählen. Die beiden
Anlässe „Tageslernziel noch offen“ und „geplante Klassenarbeitsrunde noch offen“
sind getrennt schaltbar. Die Regel gehört dem angemeldeten Elternkonto;
Mitbetreuende haben ihre eigene Auswahl. Neue Regeln sind ausgeschaltet.
Die Einstellung verändert keine Kinderziele und erteilt keine Gerätefreigabe.

Der bestehende Serverworker prüft fällige Regeln auch bei geschlossener App.
Für das Tagesminimum zählen ausschließlich gespeicherte Aktivitätssekunden am
Lerntag des Kindes. Klassenarbeitsanlässe beziehen sich auf heute geplante,
weiterhin gültige Termine, nicht auf einen anwachsenden Rückstand. Eine
In-App-Meldung entsteht höchstens einmal je Elternkonto, Kind und lokalem
Regeltag. Neue Abfragen und Appstarts erzeugen keine Meldung oder KI-Arbeit.

Die optionale Gerätekategorie `parent_goal` braucht zusätzlich das ausdrücklich
bestätigte Geräte-Opt-in. Vor Versand werden aktuelle Sitzung, Mitgliedschaft,
Regel und offene Ziele erneut geprüft. FCM erhält ausschließlich den bestehenden
neutralen Text und `/app`, keine Kinderkennung oder Lerninhalte. Die Lebensdauer
beträgt höchstens 3600 Sekunden und endet vor Ruhezeiten und Regelmitternacht;
ein Tagesminimum-Anlass endet zusätzlich vor der Mitternacht des Kindes.
Ein getrennt noch gültiger Klassenarbeitstermin darf dabei erhalten bleiben.

Migration0039 ergänzt Regeln, Änderungen und Ereignisse additiv. Änderungen
verwenden Revision und Idempotenzschlüssel; Familienentzug und Kontolöschung
bereinigen die Zuordnung. Beim Familienentzug werden die persönlichen Regeln
atomar deaktiviert und ihre Revision erhöht; eine schnelle erneute Einladung
aktiviert sie nicht wieder. Bereits gespeicherte Prüfereignisse und
Speicherversuchsbelege werden dabei nicht umgeschrieben. Ereignisse werden nach30Tagen entfernt. API-,
Worker-, Transport- und Oberflächentests verwenden künstliche Konten; eine
sichtbare Android-Hintergrundzustellung ist erst mit beobachtetem Endgerät belegt.


## Bereite Lernrunden ab 1.36.30+142

Neue ausdrücklich angeforderte Materialrunden, Anschlussübungen und Lernetappen
können nach ihrem gespeicherten Abschluss ein neutrales `round_ready`-Ereignis
erhalten. Der bestehende Worker legt den Hinweis erst nach dem Commit der Runde
an; ein fehlgeschlagener Hinweis verliert weder die Runde noch ihre Antworten.
Die lokale Wiederaufnahme kann einen fehlenden Hinweis zu einem neuen,
herkunftsgebundenen Auftrag ergänzen, ohne einen Modellaufruf zu wiederholen.
Alte Aufträge ohne `completion_origin` werden nicht nachträglich aufgefüllt.
Klassenarbeits- und Tagespaketaufträge behalten ihre bestehenden getrennten
Fertigmeldewege und erzeugen dadurch keinen zweiten Rundeneintrag.

Die Glocke zeigt „Deine Lernrunde ist bereit“ auch ohne Firebase- oder
Geräte-Opt-in. Berechtigte Kinder und Eltern erhalten nur gültige Verweise auf
das eigene Kind. Ziel ist die tatsächlich gespeicherte, noch nicht gestartete
Runde unter `/unit/<Unit-ID>`; aktuelle Quellenrevisionen, Nutzbarkeit und
gegebenenfalls vollständige Erklärgrafiken werden geprüft. Ein geänderter oder
entzogener Verweis, eine gelöschte Quelle oder bereits gestartete Runde wird
nicht weiter als bereit angeboten. Lesen der Glocke erzeugt weder Hinweise,
KI-Aufträge noch Lernnachweise. Lesemarkierungen bleiben ausdrücklich und
kontogebunden.

Auch die Fertigmeldung des Foto-Tages kann direkt die erste noch nicht
gestartete, verwendbare Runde aus genau dessen abgeschlossenem Paket öffnen.
Fehlt ein solches Ziel, bleibt der passende ursprüngliche Schultag erreichbar;
„Fotos gespeichert“ wird nicht zu einer angeblich fertigen Lernrunde umgedeutet.

Geräte-Push bleibt davon getrennt und freiwillig. Der Kinderzugang benötigt
weiterhin die Elternfreigabe, das Geräte-Opt-in samt aktivierter Kategorie
„Erinnerungen“, einen zulässigen Android-/Browserzustand und die bestehende
Firebase-Betriebsfreigabe. Der allgemeine Schalter für planmäßige
Tageserinnerungen ist keine zusätzliche Voraussetzung für eine bewusst
angeforderte fertige Runde. Sitzung, Familienrechte, aktueller Auftrag,
Quellen, Rundenzustand sowie Kinder- und Geräte-Ruhezeit werden vor Versand
erneut geprüft. Die Lebensdauer beträgt höchstens 60 Sekunden und endet vor
beiden Ruhezeiten.

FCM erhält nur den vorhandenen neutralen Systemtext, keine Namen, Fächer,
Aufgaben, Ergebnisse oder privaten Chattexte. Für diese Meldung enthält
`data.route` den streng geprüften lokalen Pfad `/unit/<32-stellige Hex-ID>`;
der Weblink verwendet denselben Pfad unter der eigenen öffentlichen App-URL.
Es werden keine beliebigen Fremd-URLs ausgeführt. Die bereits vorhandenen
Web-/Android-Routenprüfungen bleiben maßgeblich.

Die In-App-Nachricht ist eindeutig an Auftrag und gespeicherte Runde gebunden.
Die Push-Warteschlange dedupliziert je Gerät und Ereignis statt pauschal je Tag:
zwei verschiedene neue Runden am selben Tag dürfen je einen Hinweis erhalten,
das erneute Verarbeiten desselben Abschlusses keinen zweiten. Für die
Foto-Tagesmeldung bleibt der konkrete Durchlauf/Status maßgeblich. Ein
Sendetimeout wird nicht automatisch wiederholt, weil FCM die erste Sendung
bereits angenommen haben könnte.

Für 142 sind Inbox, Herkunfts-/Quellenkontrolle, Ereignis-Deduplizierung,
Ruhezeiten und neutraler FCM-Transport bislang lokal mit künstlichen Daten und
Transportattrappen geprüft (`backend/tests/test_round_ready_notifications.py`
sowie die bestehenden Benachrichtigungstests). Das belegt weder ein bereits
erfolgtes Deployment noch sichtbare Android-Hintergrundzustellung. FCM-Annahme,
sichtbare Systemmeldung und korrektes Öffnen am realen Gerät sind getrennte
Abnahmeschritte nach dem Release.
