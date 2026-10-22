# Familienanrufe

Implementierung 1.19.4+83. Aktueller Produktionsstand in STATUS.md, ausführliche
Nachweise in [FAMILY_CALL_EVALUATION_2026_10_21.md](FAMILY_CALL_EVALUATION_2026_10_21.md).
Web und Android verwenden dieselbe Flutter-Oberfläche und den eigenen FastAPI-
Server. Kein Videoanbieter-Konto, keine KI-Aufrufe und keine Aufzeichnung durch
Schulpilot. Tatsächliche Kosten für Server-/Datentransfer bleiben Betriebsaufwand.

## Bedienung und Grenzen

### Gespräch neben der Aufgabe

Der Kinderaufruf öffnet keine Gesprächsroute mehr. Die aktuelle Aufgabe bleibt
mit Eingabe und Rückmeldung im selben Router-/Widgetzustand. Oberhalb der
Arbeitsfläche sitzt eine kompakte Liveleiste mit Gesprächsstatus, Mikrofon,
Kamera, separater Bildschirmfreigabe und Auflegen. Kamerabilder lassen sich
bei Bedarf in einem begrenzten Bereich ausklappen. Die Leiste reserviert ihren
Platz im Layout und verdeckt keine Antwort- oder Weiter-Schaltfläche. Beim
Tippen bleibt sie kompakt; das Eingabefeld und die Bildschirmtastatur behalten
ihren eigenen Platz. Freigabe und Stopp erfordern keinen Wechsel weg von der
Aufgabe. Die optionale Großansicht bietet weiterhin einen Rückweg.

`FamilyCallHost` bleibt über dem Router bestehen. Seine eigene Darstellung
schaltet nur den Dockbereich um, niemals die Identität des Routerkindes.
Kamera, Peer und Capture gehören weiterhin zum kontogebundenen
`FamilyCallService`. Ein Ausklappen, Einklappen oder normaler interner
Seitenwechsel startet weder einen neuen Anruf noch eine neue Aufnahme.
Die eigene Großansicht unterdrückt den Dock einschließlich seiner Videovorschau,
damit ein Renderer nicht gleichzeitig an zwei Videoansichten gebunden wird.
Eine kontogebundene Präsentationsbelegung bleibt bis zum tatsächlichen Unmount
der Großansicht bestehen, auch wenn die Routeradresse schon während der
Zurückanimation umspringt. Eine eigene Overlay-Ebene ermöglicht Tooltips; die
feste Semantikgrenze des Routerkindes erhält die Gesprächsbuttons für TalkBack
und die Web-Zugänglichkeit. Mehrfaches Tippen öffnet nicht mehrere Freigabedialoge.

Native Anrufaktionen laden nur den berechtigten Anruf und öffnen gegebenenfalls
die ausdrückliche Annahmeabfrage im vorhandenen Navigator. Sie ersetzen keine
laufende Aufgabenroute. Ein alter Benachrichtigungslink darf ein neueres aktives
Gespräch nicht schließen oder ersetzen. Kontowechsel und serverseitige
Anrufberechtigungen bleiben maßgeblich. Nach Reload werden Kamera und Bildschirm
weiterhin ausschließlich nach bewusster erneuter Teilnahme freigegeben.

Die Kinderzugänge bei Heute, Nachrichten, Lernhilfe und Rückblick bieten
Eltern live dazuholen sowie eine ausdrückliche Nachricht als Alternative.
Auch am Hausaufgabenfoto ist der gemeinsame Livehilfe-Einstieg erreichbar.
Kamera ist beim Start auswählbar, Mikrofon/Kamera benötigen die Gerätefreigabe.
Ein angenommenes Gespräch zeigt Kamera und zusätzlich den geteilten Bildschirm.
Das Kind startet Bildschirm teilen separat; der Browser beziehungsweise Android
zeigt seinen eigenen Freigabedialog. Nur den benötigten App-Bereich oder Tab
wählen. Eigene noch nicht abgeschickte Eingaben können darin sichtbar sein.
Stoppen, stummschalten, Kamera ausschalten und Auflegen bleiben erreichbar.
Die lokale Vorschau schaltet auf Android kein Mikrofon stumm. Mikrofon aus betrifft
nur den eigenen Track; ausschließlich bewusstes Mikrofon an darf eine API-
Stummschaltung aufheben. Geräteschutz und Mikrofonberechtigung bleiben maßgeblich.
Der Anruf bleibt bei Navigation zur Aufgabe sichtbar. Kein unbeaufsichtigter
Elternzugriff, keine Fernsteuerung, kein Hintergrundstart einer Kamera.

Android-Eltern schalten unter Benachrichtigungen ausdrücklich Familienanrufe
auf diesem Gerät ein. Vorher ist die normale Geräteanmeldung nötig. Der eigene
hoch priorisierte Kanal verwendet einen Anrufton und Annehmen/Ablehnen. Android 31+
zeigt CallStyle, ältere unterstützte Versionen beschriftete Aktionen. Keine
Fullscreenberechtigung, Dialerrolle, exakten Alarme oder Umgehung des Lautlosmodus.
Kanal, Gerätestummschaltung, Ruhezeiten, Google Play Services und Systemrestriktionen
entscheiden über tatsächliches Klingeln. Der Browser bietet eine sichtbare
Einladung im geöffneten Elternbereich; kein zugesicherter Handy-Anrufton daraus.
Ein verpasster Anruf bleibt als neutrale In-App-Neuigkeit erreichbar.

## Rechte und gespeicherte Daten

Nur das eigene Kind kann anrufen; genau eine berechtigte Elternsitzung nimmt an.
Familienrollen owner/manage, aktuelle Sitzungen, Mitgliedschaften und Fristen
werden serverseitig geprüft. Administratoren und andere Familien erhalten keinen
Zugriff. Call-Signale sind keine Kameraerlaubnis. Kamera/Mikrofon erst bei eigener
bewusster Start-/Annehmenaktion, Bildschirmfreigabe separat.

`family_calls.py` enthält Start, Annahme, Ablehnung, Auflegen, Heartbeat, ICE und
Signalisierung. Kind- und annehmende Elternsitzung sind gebunden, Schlüssel
idempotent, aktive Slots eindeutig. Sperren: Elternsitzung vor Unit→Child→Call
bei Annahme; bestehende Lernpfade behalten Unit vor Child. Signale liegen begrenzt
im API-Arbeitsspeicher (128 Gespräche, insgesamt 4 MB), niemals in Logs,
SQL oder Backups. SDP-/ICE-Inhalte gelten 90 Sekunden und werden zusätzlich durch
einen API-eigenen 1-Sekunden-Cleanup ohne Seitenaufruf entfernt. Bei belegtem
RAM-Lock entfällt nur der aktuelle Tick; Lesen/Schreiben prüft die Gültigkeit
weiterhin unmittelbar. Sequenzzähler und ein
begrenzter Hashindex für Wiederholungen bleiben bis zum festen Gesprächsende
plus 90 Sekunden erhalten. Eine spät gestartete Bildschirmfreigabe liegt dadurch
weiter oberhalb des gespeicherten Empfangscursors. Reads und Heartbeats verlängern
diese Grenze nicht; volle Kapazität verdrängt keine aktiven Gesprächszähler.
Die aktuelle API verwendet einen Prozess. Mehrere API-Prozesse
erfordern zuerst eine gemeinsame private Signalisierung; nicht einfach skalieren.

Klingeln 45 Sekunden, Berechtigungsfrist 90 Sekunden, höchstens 60 Minuten pro Gespräch.
Der unabhängige Client-Watchdog beendet Medien auch bei blockierter HTTP-Verbindung.
Serverneustart beendet alte Verbindungen kontrolliert; keine stille Kameraaufnahme
nach Reload. Wiederverbinden erfordert eine bewusste Aktion. GETs beginnen keinen
Anruf, keine KI oder Lernaktivität. Metadaten bleiben 30 Tage, enthalten keine Medien
und gehören zu Export und Kontolöschung. Angenommene Hilfe zählt bei neu abgegebenen
Aufgaben als Unterstützung; alte Antworten werden nicht umgeschrieben.

## Relay und Betrieb

Ein eigener coturn-Relay ist nötig, weil direkte Peer-Verbindungen zwischen
Mobilfunk, NAT und WLAN nicht zuverlässig möglich sind. TURN leitet verschlüsselte
WebRTC-Pakete weiter. Die Authentifizierung verwendet serverseitiges HMAC und
kurzlebige, pro Teilnehmer getrennte Zugangsdaten ohne private Familienkennungen.
Die Gültigkeit deckt die begrenzte Gesprächsdauer ab; die unabhängige 90-Sekunden-
Berechtigungsfrist bleibt strenger. Keine öffentlichen Discovery-/Ersatzanbieter.

Expliziter lokaler Operatoraufruf `deploy/install_turn.py --install` installiert
das offizielle Ubuntu-coturn-Paket. Dies passiert niemals automatisch auf einer
leeren Installation. Getrennter Benutzer/Dienst, begrenzte Relayports und Datenrate,
private/Loopback-/Multicastziele gesperrt, keine Anwendungsprotokollierung.
Die bestehende Caddy-Zertifikatskette wird nur für diese Domain in einen isolierten
Pfad kopiert; ein Timer hält sie aktuell. Vorhandene Caddy-/andere Dienste bleiben
erhalten. Eigene Hetzner-Firewall nur am Schulpilot-Server: 3478 TCP/UDP, 5349 TCP,
49160–49259 UDP; konkrete Betreiberbestätigung im Chat erteilt. Bestehende Regeln
werden unverändert erhalten. Kein stilles Öffnen solcher Ports im Deployment.

Geschützte Umgebung außerhalb von Git/Releases:
`SCHULPILOT_TURN_URLS`, `SCHULPILOT_TURN_SECRET` und
`SCHULPILOT_CALLS_ENABLED` (neue Installation standardmäßig false). Erst nach
geprüfter Medienverbindung aktivieren. Abschalten beendet aktive Gespräche beim
nächsten Berechtigungsabgleich. API-/Client-/Call-ID-gebundene Bereinigung stoppt
alte Streams, ohne neue Gespräche eines inzwischen gewechselten Kontos zu beenden.

Bei der Abnahme wurde ein coturn-spezifischer Konfigurationsfehler entdeckt:
Ein einzelner gesperrter Bereich `::` bedeutet in 4.6.1 unbegrenzt an beiden Enden
und sperrt alle Peers. Dieser redundante Eintrag wurde entfernt, ein Erzeugungs-
Guard verhindert seine Wiederkehr. Die eingebaute Zero-/Loopbackprüfung und alle
privaten Netzsperren bleiben erhalten. Keine pauschale Allowlist oder Öffnung
privater Zielnetze als Reparatur.

## Firebase

Bestehendes Projekt schulpilot-f6bf3, SDK 16.7.0, Schlüssel und Einwilligungen
bleiben erhalten. `PushDevice.family_calls` beginnt false; eine zufällige lokale
Gerätebindung verhindert alte Anrufsignale nach Kontowechsel. Nur berechtigte,
angemeldete Elterngeräte mit ausdrücklichem Opt-in erhalten kurze neutrale
Datenmeldungen. Firebase bekommt keine Kamera-/Bildschirm-/Lerninhalte.
Bestehende dauerhafte Push-Warteschlange und begrenzte sofortige Hintergrund-
Versender verhindern, dass ein 145-Sekunden-KI-Auftrag einen 45-Sekunden-Anruf
blockiert. Kein automatischer Wiederholungsversand bei unklarem Ausgang.

Die beauftragte Android-Diagnose ergab zunächst null angemeldete Pushgeräte und
null Versandversuche in den letzten sieben Tagen. Das belegt eine fehlende
Geräteanmeldung, keinen bewiesenen Google-Ausfall. Produktionsfreigabe, Projekt,
APIs, Schlüsselrestriktionen und Sender wurden separat geprüft; FCM validate_only
mit synthetischem Ziel war HTTP 200. Tatsächliche Android-Zustellung und deren
Grenzen werden in STATUS.md getrennt davon dokumentiert.

## Fehler beim Start einer Bildschirmfreigabe

Der Client übernimmt den Screenstatus erst, nachdem der Videotrack erfolgreich
angebunden ist. Fehlende Freigabe, Trackfehler oder fehlgeschlagener Angebotsversand
stoppen die Bildschirmaufnahme und geben den Android-Projection-Diensttyp frei.
Kamera- und Mikrofontracks bleiben erhalten. Ein ausstehendes Angebot blockiert
nach einem Fehler keine bewusste neue Aktion; es gibt keinen automatischen
Aufnahme- oder Versandretry. Beim regulären Bildschirmstopp endet zunächst die
Aufnahme, danach entfällt ausschließlich der Projection-Diensttyp.

## Anfrageverarbeitung unter Datenbanklast

Die Installationsprüfung öffnet und schließt ihre synchrone Datenbanksitzung
vollständig im Workerthread. Ein wartender Pool-Checkout blockiert dadurch
nicht den Async-Eventloop und die Freigabe laufender Requests. Die Setup-Sperre
bleibt bei jeder geschützten Anfrage erhalten. Fehler durchlaufen die bestehende
redigierte Fehlerbehandlung. Der Signalisierungs-Cleanup versucht seinen kurzen RAM-Lock ohne Warten.
Ist er belegt, entfällt nur der aktuelle Tick; die einzige Cleanup-Task prüft
nach einer Sekunde erneut.
Poolgröße, Berechtigungen und Providergrenzen werden dafür nicht erhöht.
