# Familienanrufe: Abnahme am 21.–22.10.2026

## Aufgabenbegleitende Livehilfe83 · 22.10.2026

Version 1.19.4+83 ersetzt beim Kinderaufruf den automatischen Seitenwechsel durch
einen kompakten, aufklappbaren Gesprächsdock. Kamera/Ton/Freigabe bleiben im
kontogebundenen Service, Aufgabe und Entwurf im selben Routerzustand. Native
Benachrichtigungsaktionen erhalten ebenfalls die laufende Aufgabenroute.

98 gemeinsame Flutterfälle einschließlich zehn neuer Dock- und fünf neuer
Main-/Navigationsfälle bestanden, vollständige Flutter-Analyse ohne Hinweise.
36 bestehende Anruffälle erneut in isoliertem PostgreSQL bestanden. Keine
Backend- oder Datenbankänderung außer der Produktversionsangabe, kein neuer
KI-Auftrag oder geändertes Budget.

| Ausgangspunkt → Aktion | Überprüftes Ergebnis |
| --- | --- |
| Aufgabe mit Entwurf/Feedback → Elternhilfe starten | Gleicher Aufgaben-State und Route, genau ein Start, Eingabe und Rückmeldung bleiben. |
| Kompakter Dock → Teilen bestätigen → Stopp | Getrennte ausdrückliche Freigabe; direkt erreichbarer Stopp ohne Wechsel von der Aufgabe. |
| Großansicht → Zurückanimation | Höchstens eine montierte Ansicht pro Renderer, auch mit zusätzlichem Kinderbildschirm in der Elternansicht. |
|320×568 / 640×320, doppelte Schrift, Tastatur, hell/dunkel | Bedienelemente mindestens 48px, keine Test-Overflows, Entwurf weiter bearbeitbar. |
| Nativer Anrufhinweis → Ansehen/Annehmen/Ablehnen | Aufgabe bleibt; Annahme weiterhin ausdrücklich; Ablehnen öffnet keine Medien. |
| Älterer Anruflink oder verspätete Ladeantwort → neueres Gespräch | Kein Ersetzen oder Schließen des neueren Gesprächs. |

Die tatsächliche Browserprüfung der ausdrücklich synthetischen Vorschau deckte
fehlende Dock-Semantik hinter der Router-ModalRoute auf. Die feste Semantikgrenze
behebt sie; Mikrofon, Kamera, Teilen, Auflegen und Aufgabenformular erscheinen nun
gemeinsam im Zugänglichkeitsbaum. Der Renderer-Übergangstest deckte außerdem
doppelte Ansichten während der Pop-Animation auf. Die Präsentationsbelegung bis
zum tatsächlichen Dispose behebt den Fehler. Dialogschutz und Beenden während
einer noch offenen Freigabeabfrage sind zusätzlich geprüft.

Die Vorschau verwendet ausschließlich gezeichnete Kameraplatzhalter und lokale
Mockantworten; sie ist kein Nachweis einer realen Medienverbindung. Der neue
öffentliche Demohaushalt enthält ausschließlich vier feste künstliche Aufgaben
und dient der getrennten signierten Android-Liveprobe. Keine alten Testzugänge
wurden wieder aktiviert und keine Pushfreigaben erteilt.

Die erste signierte 83-Probe hat echte Kamera-/Audio-/Screenübertragung über den
erzwungenen Produktionsrelay nachgewiesen: 180,34 Sekunden, 1962 Kameraframes,
527 Bildschirmframes 1080×2400 und 8551 Audioframes. Die Quellzuordnung verwendet
die signalisierten MSIDs und Transceiver-MIDs. Neun Healthchecks bestanden,
langsamster 0,016 Sekunden; reguläres Ende und Logout per HTTP bestätigt.
Die Android-Aufgabe und ihr Entwurf blieben beim Start erhalten; Tippen mit
sichtbarer Tastatur, Mikrofon/Kamera AUS/AN und der aufgeklappte Videodock wurden
tatsächlich bedient. Danach waren Projection, Capture-Service und FGS aus;
globale Mikrofon-Schutzschalter blieben unverändert.

Die QA-Helfer mussten an aktuelle Einstiegsbezeichnungen, gesprochen dargestellte
Brüche und den nicht selbst anklickbaren TextView des Android-Systemspinners
angepasst werden. Die negativen Helferbelege bleiben erhalten. Die erste Probe
bestätigt weder den separaten 224→192-Stopp vor Gesprächsende noch den kompletten
Sammlungsrückweg bei aktiver Verbindung. Dafür wurde ausdrücklich genau eine
zweite, getrennte künstliche Probe im selben Haushalt freigegeben; keine weitere
Antwort, KI-Wiederholung oder Produktgrenze wurde daraus abgeleitet.

Die zweite Probe übertrug in 180,23 Sekunden 1968 Kamera-, 35 Screen- und 8853
Audioframes, mit drei Angeboten/Antworten und neun erfolgreichen Healthchecks
(maximal 0,020 Sekunden). Vor dem gezielten Stopp war Projection mit FGS 224
aktiv; danach waren Projection=false und Kamera-/Mikrofon-FGS 192 tatsächlich
belegt. Die Screenframes blieben bei 35, Kamera und Audio liefen weiter.
Normales Ende und Eltern-Logout wurden per HTTP bestätigt.

Der echte Rückweg führte nach ausdrücklichem Pausieren über Heute und Lernen
wieder zur selben Aufgabe 2/4. Die unmittelbar dabei gesicherte Android-Aufnahme
zeigt die verbundene Liveleiste und den erhaltenen Entwurf als Zähler 1/Nenner 2;
zeitgleiche native Metadaten zeigen weiter Capture 192 ohne Projection und ohne
globale Mutes. Root hat diesen Sichtbeleg eigenständig geprüft. Ein QA-Helfer
wartete fälschlich auf einen zusätzlichen „Lernen fortsetzen“-Dialog, obwohl die
gespeicherte Runde bereits direkt geöffnet war. Seine negative Datei bleibt
unverändert. Die erneute spätere UIA-Abfrage erreichte das normale 180s-Ende und
bestätigt die Verbindung nicht nachträglich. Dieser Rückweg ist deshalb als
getrennte manuelle Sichtprüfung mit zeitgleichen Metadaten dokumentiert und
nicht als vollständig grüner automatischer Helferlauf. Es gab keine dritte Probe.

Kinderlogout, sämtliche Capture-/Projection-Endflags und vollständiges
Emulatorende sind geprüft. Der neue Demohaushalt wurde danach über seinen
normalen authentifizierten Kontolöschweg entfernt. Die separate lesende
Kaskadenprüfung bestätigt alle gebundenen Datenzähler als null. Zugangsdaten
und privater IDs-Checkpoint sind lokal entfernt; beide alten Logins werden
abgewiesen. API/Worker/Caddy/TURN und Sicherung bleiben gesund, Schema0026 und
Providerrevision29 unverändert. Android36 wurde im eigenen Emulator geprüft;
hörbares Klingeln und Tonqualität eines physischen Telefons bleiben offen.

## Historische Produktionsabnahme82

Produktversion **1.19.3+82**, Commit
`e58e6c4e98411052bda37378d158cf9d30a360b2`, Produktionsrelease
`20261021T194514Z-e58e6c4`. Architektur und Bedienung stehen in
[FAMILY_CALLS.md](FAMILY_CALLS.md), die Android-Anbindung in
[FAMILY_CALL_ANDROID.md](FAMILY_CALL_ANDROID.md). Die folgenden Abschnitte trennen
die ursprüngliche Abnahme 79 und die nachfolgenden Korrekturen80–82.

## Umfang und Daten

Die Prüfungen verwenden ausschließlich künstliche Konten und Medien. Kein echtes
Kind wurde angerufen, keine Kamera oder Bildschirmfreigabe eines echten Geräts
aktiviert und keine Antwort eines echten Kindes zum Testen gespeichert. Familienanrufe verwenden
keinen KI-Anbieter. Der bestehende OpenRouter-Betrieb mit Providerrevision 29,
Paid-/Economy-Routing und ZDR wurde beim Deployment unverändert geprüft.

Die vorhandenen künstlichen Firebase-Testzugänge werden wiederverwendet. Ihre
Passwörter, Sitzungen und FCM-Tokens stehen weder hier noch in Git. Eine angenommene
FCM-Anfrage, eine lokal erzeugte Android-Meldung und eine tatsächlich zugestellte
Meldung sind unterschiedliche Nachweise.

## Automatisierte Fälle des ursprünglichen Anrufreleases 79

| Prüfung | Nachweis |
| --- | --- |
| Backend und Rechte | 98 Fälle im gemeinsamen isolierten PostgreSQL-Lauf bestanden: neue Anrufwege, konkurrierende Annahme, fremde Familien, Admins, Sessionwiderruf sowie bestehende Push-, Inbox-, Lern- und Tutorwege. |
| Migration | Gefüllte SQLite- und PostgreSQL-Datenbanken durch 0025 → 0026 → 0025 → 0026 geprüft; Benutzer, Antworten und bestehende Pushzustände erhalten. Neue Anruffreigabe beginnt ausgeschaltet. |
| Flutter | 154 gemeinsame UI-/Servicefälle bestanden; Hilfeauswahl, Signalisierung, Medienbereinigung, Kontowechsel, verspätete Antworten und unabhängiger Berechtigungs-Watchdog enthalten. |
| Native Regeln | Sechs Kotlin-Fälle bestanden, einschließlich herabgestufter FCM-Priorität und verspäteter Bereinigung eines alten Anrufs. |
| Android-Instrumentierung | Auf Android 36 sichtbar geprüfte CallStyle-Meldung; außerdem Klingeltonkanal, Ablauf, Annahmeroute, Deduplizierung, Gesprächsende, alte Gerätebindung und Abmeldung geprüft. Dies ist ein Offline-Nachweis, keine FCM-Zustellung. |
| Relay-Konfiguration | Fünf Regressionen verhindern insbesondere einen unbeschränkten coturn-Sperrbereich aus einer einzelnen Nulladresse. |
| Statische Prüfung | Vollständige Flutter-Analyse, betroffene Ruff-Prüfungen und Diffprüfung ohne Befund. |

Die ursprüngliche Android-36-Instrumentierung deckte einen echten Fehler auf:
CallStyle wurde ohne zulässigen Vordergrunddienst vom System abgelehnt. Der
zeitlich begrenzte Klingeldienst wurde daraufhin korrigiert und erneut erfolgreich
geprüft. Eine normale FCM-Anzeige allein hätte diesen Fehler nicht ausgeschlossen.

## Tatsächliche Medien- und Browserprüfung

Zwei künstliche WebRTC-Peers über den öffentlichen Produktionsrelay wurden bewusst
auf TURN festgelegt. Je ein separater Durchlauf verwendete UDP, TCP beziehungsweise
TLS auf Port 5349. Alle drei Verbindungen tauschten verschlüsselt Kamera-,
Bildschirm- und Elternkamerabilder, stilles Audio in beide Richtungen sowie eine
DataChannel-Echoantwort aus. Pro Durchlauf wurden mindestens drei Videoframes pro
Bildquelle und mindestens 13 Audioframes pro Richtung empfangen. Das belegt die
Medienverbindung; es ersetzt keine Prüfung eines physischen Smartphones.

Dabei wurde ein coturn-4.6.1-Sonderfall gefunden: Ein einzelner gesperrter Bereich
`::` wird intern als unbegrenzter Bereich behandelt und blockiert alle Peers.
Der redundante Eintrag wurde entfernt. Private Zielnetze und die eingebaute
Zero-/Loopbackprüfung bleiben gesperrt; es wurde keine pauschale Allowlist gesetzt.

Der echte Browserdurchlauf verwendete eine separate lokale Datenbank mit
ausschließlich künstlichem Kind. KI und Anrufe waren dort abgeschaltet. Geprüft
wurden Hilfe auf Heute, die Auswahl zwischen Anruf und Nachricht, die Nachricht als
ausdrückliche Alternative ohne Versand sowie der neue Livehilfe-Einstieg an einem
gespeicherten Hausaufgabenfoto. Es wurde keine Medienfreigabe erteilt. Der Browser
zeigte den Kamera-Schalter, die getrennte Bildschirmfreigabe-Erklärung und den
Hinweis auf berechtigte Eltern. Danach wurde das Konto regulär abgemeldet.

## Firebase-Diagnose und Android-Zustellung

Vor Beginn gab es in der Produktion **null registrierte Pushgeräte** und **null
Versandversuche in den vorherigen sieben Tagen**. Das erklärt einen aktuell
fehlenden Versandweg, rekonstruiert aber keine frühere Geräteentscheidung.

Separat geprüft wurden das bestehende Projekt `schulpilot-f6bf3`, beide
Plattformkonfigurationen, benötigte APIs, Schlüsselrestriktionen und die minimale
Senderberechtigung. Der tatsächliche Sender konnte sich authentifizieren;
`validate_only=true` an ein festes künstliches Topic wurde mit HTTP 200 angenommen.
Dabei wurde keine Nachricht an ein reales Gerät geschickt.

Anschließend wurde die signierte reguläre APK 79 auf dem eigenen Android-36-
Emulator installiert. Im normalen künstlichen Elternkonto wurden Gerätehinweise
und der getrennte Familienanruf-Schalter ausdrücklich eingeschaltet. Erst nach
nachgewiesenem Hintergrundzustand wurde genau eine neutrale Testmeldung über den
bestehenden Produktionsversand angefordert. FCM nahm sie an; die Android-
Benachrichtigung erschien tatsächlich und ihr Antippen öffnete die Neuigkeiten
der App. Protokoll: `artifacts/family-call79/parent79-background-result.json`,
Bild: `android-fcm-background79.png` im selben Ordner.

Dieser Hintergrundnachweis ist eine echte Zustellung und bleibt vom Offline-
CallStyle-Test getrennt. Angenommene Anrufe und Medien werden in den folgenden Gegenproben separat belegt.
Hörbares Klingeln auf einem physischen Telefon wird daraus nicht abgeleitet.

Der erste Livecall wurde im Test nicht angenommen. Die Produktionsdaten belegten
sofortige FCM-Annahme für Eingang und Ende, gültige Sitzungen/Gerätebindung und
freie Ruhezeiten. Die Test-VM und der Emulator gingen jedoch ungefähr 7122 Sekunden
vor. Android verwarf deshalb die absolute Anruffrist korrekt als abgelaufen. Der
Server war über Hetzner-NTP synchronisiert; ungecachte HTTPS-Zeitstempel von Google
und GitHub bestätigten seine UTC-Zeit unabhängig. Das lokale Clocktool teilte die
VM-Zeitbasis und war hierfür kein unabhängiger Nachweis.

Nur der eigene kurzlebige Emulator wurde anschließend auf diese geprüfte UTC-Zeit
gesetzt; Restabweichung rund 0,45 Sekunden. Seine automatische Zeitübernahme war
für die QA vorübergehend ausgeschaltet. Produktionsserver, Host-VM, Thinclient und
echte Telefone blieben unverändert. Die 45-Sekunden-Frist wurde nicht gelockert,
der erste fehlgeschlagene Versuch und seine Versandbelege bleiben erhalten.

Beim zweiten Versuch erschienen die echte native Anrufkarte und die ausdrückliche
In-App-Annahme. Der Android-Elternclient verband sich über den Produktionsrelay;
der künstliche Gegenpeer empfing 962 Kamera- und 4497 Audioframes. Die beiden
Kinder-Videokacheln blieben jedoch dunkel. Empfangene Audioframes allein belegen
keinen hörbaren oder ungestummten Mikrofonton.

Die gezielte Prüfung des fixierten Plugins deckte zwei Produktfehler auf:
`RTCVideoRenderer.muted=true` schaltet nativ das tatsächliche Mikrofon über den
AudioManager stumm; bei einem Remote-Stream wirft derselbe Setter eine Ausnahme.
Der eigene Emulator zeigte danach tatsächlich API-Stummschaltung, während
Hardware-/Restriktionsschutz ausgeschaltet waren. Es gab ausschließlich drei
Anrufe im geprüften künstlichen Haushalt und null außerhalb davon. Die neue
Anruffunktion wurde bis zur Korrektur serverseitig deaktiviert und der Wechsel
auditiert. Es wurde kein echtes Gerät automatisch entstummt.

Die anschließend ausgelieferte Nachkorrektur **1.19.1+80**, Produktcommit
`fe3810fc139e61d3afdc5c66389510ee1420be90`, trennt Browser-Preview und native
Mikrofonsteuerung, bindet Kamera und Bildschirm ausdrücklich an Video-Tracks und
unterscheidet Track-Ankunft vom ersten gerenderten Bild. Mikrofon aus verändert nur
die eigenen Tracks; ausschließlich die bewusste Aktion Mikrofon an darf eine
API-Stummschaltung aufheben. Das doppelte große Banner entfällt auf der eigenen
autorisierten Anrufseite; Beenden steht dort zusätzlich oben. 75 gemeinsame
Flutter-Fälle und die vollständige Flutter-Analyse sind für diesen Fix bestanden.
Die echte Android-Gegenprobe mit 80 zeigt nun gleichzeitig grünes Bildschirmbild,
rotes Kinderkamerabild und die eigene Emulator-Kamera. Der native Elterneingang
kam nach nachgewiesenem Hintergrundzustand tatsächlich über FCM an; CallStyle,
Annehmen und die zusätzliche ausdrückliche In-App-Annahme wurden beobachtet.
Der künstliche Gegenpeer empfing 845 Elternvideoframes und 4511 Audioframes über
den erzwungenen Relay. Beide bereits erteilten OS-Rechte waren weiterhin gültig;
API- und Systemstummschaltung waren während und nach dem Gespräch ausgeschaltet.
Nach regulärem Logout waren Gerätebindung, Klingelstatus, CaptureService und
Projection entfernt. Die CallStyle-Aufnahme 80 traf eine Launcher-Animation; sie
ist ausdrücklich kein Bildnachweis der Anrufkarte. Für diese bleibt das echte79-
Bild erhalten. Belege: `artifacts/family-call80/parent-fcm-media-acceptance.json`,
`live-child-result.json`, `android-parent-two-video-sources.png`.

Die zusätzliche Android-Capture-Gegenprobe scheiterte zunächst vor der
Bildschirmfreigabe an einem Guard des lokalen Python-Prüfpartners. Dessen
MAX_BUNDLE-Konfiguration verlor bei abweichender Track-Reihenfolge den
Haupttransport. Nur der Harness wurde auf sichere BUNDLE-Aushandlung und
vollständiges Gathering korrigiert; der strikte Relay-Guard bleibt erhalten.

## Späte Bildschirmfreigabe und Fehlerbereinigung81

Zwei weitere echte80-Gegenproben empfingen die Androidkamera und Audio. Die
Elternkamera wurde auf Android sichtbar; MediaProjection und CaptureService
liefen nach dem bewussten Systemdialog. Dennoch fehlte das spätere Bildschirmbild.
Die zweite Gegenprobe mit 240 Sekunden Beobachtung erhielt nur das Erstangebot.
Die Diagnose fand den konkreten Backendfehler: Nach 90 Sekunden ohne neue
Signalisierung wurden zusammen mit den privaten Umschlägen auch Sequenzzähler
entfernt. Ein späteres Bildschirmangebot begann wieder unter dem Clientcursor.

81 trennt diese Lebensdauern: SDP/ICE verfallen weiter nach 90 Sekunden und werden
auch ohne GET/POST durch einen eigenen API-Timer entfernt. Zähler und begrenzter
Hash-Idempotenzindex bleiben bis zum festen Gesprächsende plus 90 Sekunden. Eine
verspätete HTTP-Wiederholung erzeugt dadurch kein neues Angebot; neue Angebote
liegen weiter oberhalb des alten Cursors. Speicher, Nachrichten, Indexeinträge
und Gesprächsslots bleiben begrenzt. Volle Kapazität verdrängt keine aktiven
Gesprächszähler.

Zusätzlich deckte ein injizierter SDP-Fehler einen Clientfehler auf: Ein gesetzter
Screenstatus und ein ausstehendes Angebot konnten nach einem Fehler bestehen
bleiben. 81 übernimmt Capture erst nach erfolgreichem Trackanbinden und räumt
fehlgeschlagene Angebote kontrolliert auf. Bildschirmtracks stoppen zuerst;
anschließend entfernt Android nur den Projection-Diensttyp. Kamera und Mikrofon
bleiben erhalten. Es gibt keinen automatischen Aufnahme-/Versandretry. Die
Glocke hat auch mit Badge einen verständlichen Accessibility-Namen.

Der endgültige 81-Backendstand besteht 109 gemeinsame isolierte PostgreSQL-
Fälle (eine bestehende Starlette-Warnung), einschließlich des 120s-Cursorfalls,
der rein zeitgetriebenen Bereinigung und des regulären/fehlerbedingten Shutdowns.
83 gemeinsame Flutterfälle der sechs betroffenen Dateien sowie sechs Kotlin-
Regelfälle und die native Kompilierung sind bestanden. Die vier Bridgefälle sind
in der Flutter-Suite enthalten und werden nicht zusätzlich als neue Fälle gezählt.
Es ist keine Datenbankmigration erforderlich. Protokolle:
`artifacts/family-call81/backend-regression.log`, `kotlin-tests.log` und die
Flutter-Prüfprotokolle für 81. Diese automatischen Fälle sind von den tatsächlichen
Android-Medien-/FCM-Gegenproben getrennt.

## Datenbankpool und Eventloop82

Die erste echte 81-Gegenprobe scheiterte nach 13,85 Sekunden beim Übermitteln
der ersten Verbindungsantwort. Auch öffentliche und lokale Healthchecks liefen
in Zeitlimits. Die Diagnose erfasste 15 Poolverbindungen im Zustand idle in
transaction, keine wartenden Datenbanksperren und mehrere Pooltimeouts. Es gab
sieben Anrufe im künstlichen Haushalt und null außerhalb davon.

Der vorhandene asynchrone Middlewarepfad führte die synchrone Installationsprüfung
direkt im Eventloop aus. Bei einem belegten Pool konnte dessen Checkout damit
auch das Freigeben bereits laufender Requests blockieren. Unabhängiger Review
bestätigte diese Verkettung. Die Anwendung wurde kontrolliert auf den zuvor
geprüften 80-Stand zurückgesetzt und neue Anrufe mit gesicherter Konfiguration und
Audit vorübergehend angehalten. Die Datenbank blieb auf 0026 und wurde nicht aus
einer alten Sicherung ersetzt. Der öffentliche Healthcheck antwortete danach
wieder in 0,05 Sekunden.

82 lagert den gesamten synchronen Gate-Aufruf einschließlich Sessionopen/-close
aus, erhält die Prüfung je geschützter Anfrage und nimmt ihre Fehler in die
redigierte Behandlung auf. Der reine RAM-Cleanup versucht seinen Lock ohne Warten. Ein belegter Lock
lässt nur den aktuellen Tick aus; die einzige Task prüft nach einer Sekunde
erneut. Es wird kein zusätzlicher Bestand an Cleanupjobs gestartet.
DB-Pool und Anfrage-/Providergrenzen bleiben unverändert. Der erste fehlgeschlagene
Liveversuch und seine neutrale Diagnose bleiben als separate Nachweise erhalten:
`artifacts/family-call81/live-parent-attempt1.json`, `timeout-diagnostic.json`,
`rollback.log`, `rollback-health.json` und die native lokale Medienbereinigung.

## Abschließende tatsächliche 82-Gegenprobe

Die erste 82-Probe hatte bereits 240 Sekunden stabile Kamera-/Audioübertragung
und zwölf erfolgreiche Healthchecks (maximal 0,037s). Der QA-Helfer hatte jedoch
die bewusst getrennte In-App-Erklärung nicht bestätigt. Der erste Druck öffnet
dieses Panel; erst „Bereich auswählen und teilen“ startet die Systemauswahl.
Der korrigierte Helfer folgt diesem Ablauf, ohne Produktberechtigungen zu ändern.
Die nächste Probe übertrug 263 neue 1080×2400-Frames nach einer späten Freigabe,
blieb im Prüfer aber wegen dessen unvollständiger Trackkennung source=unknown.
Der Prüfer berücksichtigt jetzt tatsächliche Media-/SSRC-MSID und die Receiver-
Zuordnung über Transceiver-MID. Ein synthetischer Negativtest lässt fremde IDs
weiter unbekannt; Auflösung und Ankunftsreihenfolge bestimmen keine Quellrolle.
Alle Vorversuche bleiben unverändert erhalten. Die finale Probe bestätigt
beide Quellen anhand echter Metadaten und den getrennten Bildschirmstopp.

In der abschließenden Probe erschien das erste Screenangebot nach
**143,36 Sekunden** seit Erstangebot.
Kamera, Audio und ein eigener Bildschirmtrack wurden über den erzwungenen
Produktionsrelay tatsächlich empfangen. Beobachtung: 300,26 Sekunden;
15 Healthchecks erfolgreich, langsamster 0,029 Sekunden.
3 Kinderangebote und 3 Elternantworten wurden verarbeitet.
Nach Screenstopp lief Kamera/Mikrofon weiter; Projection endete. Bewusstes Mic
AUS/AN, globale Schutzschalter und abschließende Dienstbereinigung wurden nativ
beobachtet. Ende und Logout sind diesmal zusätzlich durch erfolgreiche HTTP-
Antworten bestätigt. Die nicht bestätigt abgemeldete Elternsitzung des fehlgeschlagenen
81-Versuchs wurde separat und ausschließlich im künstlichen Haushalt auditiert
widerrufen. Abschließend 10 künstliche Anrufe, null außerhalb,
keine aktiven Calls und keine QA-Pushgeräte.

Der endgültige Backendstand besteht 136 isolierte PostgreSQL-Fälle einschließlich
vollständiger Installation und neuer Engpassfälle. Der absichtlich injizierte alte
Inlinepfad scheitert in beiden Poolfällen; der reparierte Pfad besteht alle sechs
neuen Fälle. Der unveränderte native/UI-Code behält 83 Flutterfälle, sechs Kotlin-
Regelfälle und die saubere vollständige Analyse. Keine doppelte Summierung der
19 abschließenden Headerfälle. Protokolle liegen in `artifacts/family-call82/`,
die Flutterprotokolle in `artifacts/family-call81-*.log`.

## Auslieferung und Rückweg

Web, Direct-APK und Play-AAB stammen aus demselben geprüften Produktcommit.
Signaturen, Version, Paket, Quellbindung und Play-Bundle sind validiert. Der
öffentliche vollständige APK-Download stimmt überein:

- APK: 111662243 Bytes, SHA-256
  `9bbc8ba3b16f4a2cef13fc4f467072aba9afaba3ef6d2df7dea9b117ef535e1a`.
- AAB: 88908351 Bytes, SHA-256
  `646702fb157cb54dca7310ae4ad475c651a230a3e2cb8ffde632542814d7f1a7`.

681 Quellen/Assets und 350 Archiveinträge wurden gegen 14 vorhandene Secretquellen
geprüft: keine Treffer. Der Relay-Schlüssel wurde zusätzlich ausschließlich im
Speicher gegen 779 Dateien und dieselben 350 Einträge verglichen: keine Treffer.
Private Schlüssel und QA-Anmeldedaten wurden nicht in Git übernommen.

Konfiguration und Datenbank wurden vor dem Deployment gesichert. Schema 0026,
API, Worker, Caddy, TURN und Zertifikattimer sind gesund; Sicherung erfolgreich.
Providerrevision 29 mit OpenRouter Paid/Economy/ZDR bleibt unverändert. Die
Anruffunktion wurde nach dem geprüften Poolfix mit erneut gesicherter Umgebung
und Audit wieder aktiviert. Kein Play-Upload. Familienanrufe verbrauchen keine KI.

Bei Anrufproblemen zuerst `SCHULPILOT_CALLS_ENABLED=false` setzen und die aktuellen
App-Dienste neu starten. Der vorherige 80-Release `20261021T184832Z-fe3810f` ist
als Rückweg vorhanden und kennt Schema 0026. Der tatsächliche Rückweg 81→80 wurde
ohne Datenbankrücksetzung durchgeführt und öffentlich geprüft. Keine aktuelle
Antwort durch eine alte Sicherung ersetzen.

## Angeschlossenes physisches Smartphone

Die zusätzliche Gerätesuche wurde anhand der lokalen BeagleOS-Systembeschreibung
durchgeführt. Die VM besitzt USB/IP-Controller, aber kein importiertes physisches
Telefon. Der bekannte Thinclient ist über WireGuard erreichbar; seine SSH-Identität
weicht jedoch vom gespeicherten Schlüssel ab. Beide dokumentierten USB/IP-Pfade
sind nicht erreichbar. Der vorhandene Mikrofon-SSH-Tunnel ist ebenfalls gestört.

Die Hostmanager-Identität ist bekannt, die vorhandenen SSH-Schlüssel gewähren dort
jedoch keinen Zugang und im Browser fehlt die Anmeldung. Zur sicheren Fortsetzung
wurde die Anmeldung in der BeagleOS-Verwaltung angefordert. Weder Hostkeyprüfung
noch andere Schutzmechanismen wurden umgangen. Der NetBridge-Status wurde nicht
als vermeintlich reine Abfrage ausgeführt, weil er einen allgemeinen USB/IP-
Listener starten könnte. Keine Telefoninhalte oder Seriennummern wurden gelesen.

## Grenzen

Der Emulator hat keine Audioausgabe. Selbst eine sichtbare Anrufkarte und ein
korrekt konfigurierter Klingeltonkanal beweisen kein hörbares Klingeln auf einem
physischen Telefon. Android-Berechtigung, Gerätekanal, Ruhezeiten, Lautlosmodus,
Google Play Services und Herstellerbeschränkungen bleiben maßgeblich. Kein
Vollbild- oder Lautlosmodus-Bypass und keine automatische Kameraaktivierung.
