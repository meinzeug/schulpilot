# Familienanrufe: Abnahme am 21.10.2026

Produktversion **1.19.0+79**, Commit
`f24e19c5438956a38ddf9c87224e6d42403a3382`, Produktionsrelease
`20261021T180510Z-f24e19c`. Architektur und Bedienung stehen in
[FAMILY_CALLS.md](FAMILY_CALLS.md), die Android-Anbindung in
[FAMILY_CALL_ANDROID.md](FAMILY_CALL_ANDROID.md).

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

## Automatisierte Fälle

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
CallStyle-Test getrennt. Ein angenommener Produktionsanruf wird zusätzlich geprüft.
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

Die vorbereitete Nachkorrektur **1.19.1+80** trennt Browser-Preview und native
Mikrofonsteuerung, bindet Kamera und Bildschirm ausdrücklich an Video-Tracks und
unterscheidet Track-Ankunft vom ersten gerenderten Bild. Mikrofon aus verändert nur
die eigenen Tracks; ausschließlich die bewusste Aktion Mikrofon an darf eine
API-Stummschaltung aufheben. Das doppelte große Banner entfällt auf der eigenen
autorisierten Anrufseite; Beenden steht dort zusätzlich oben. 75 gemeinsame
Flutter-Fälle und die vollständige Flutter-Analyse sind für diesen Fix bestanden.
Tatsächliche Medienabnahme und Auslieferung von 80 werden separat ergänzt.

Die zusätzliche Android-Capture-Gegenprobe scheiterte zunächst vor der
Bildschirmfreigabe an einem Guard des lokalen Python-Prüfpartners. Dessen
MAX_BUNDLE-Konfiguration verlor bei abweichender Track-Reihenfolge den
Haupttransport. Nur der Harness wurde auf sichere BUNDLE-Aushandlung und
vollständiges Gathering korrigiert; der strikte Relay-Guard bleibt erhalten.

## Auslieferung und Rückweg

Web, Direct-APK und Play-AAB wurden mit der fixierten Toolchain aus demselben
Produktcommit gebaut. Paket, Version, Signierer und Bundlevalidierung sind geprüft.
Das Play-Artefakt enthält keine APK-Installerberechtigung. Der öffentliche vollständige
APK-Download stimmt mit dem lokalen signierten Paket überein:

- APK: 111449251 Bytes, SHA-256
  `9de9d7baf1ba1aab0467d5a8129fdef5cff8dd93ea65928e86573887a797a52e`.
- AAB: 88862355 Bytes, SHA-256
  `f44b43db8dc656f37121c2a1f9bd55cdd61652b46769122d41fecb9b20f5e337`.

Vor dem Deployment wurden Konfiguration und Datenbank gesichert. Schema 0026,
API, Worker und Caddy sind nach dem Wechsel geprüft; der vorhandene eigene TURN-
Dienst und Zertifikattimer laufen. Die konkrete Portfreigabe wurde vom Betreiber
ausdrücklich bestätigt. Die Anruffunktion wurde nach den Relaytests über die
geschützte Serverumgebung aktiviert und der Operatorwechsel auditiert.

Die Geheimnisprüfung fand in 678 Quellen/Assets und 350 APK-/AAB-Einträgen bei
16 vorhandenen Secretquellen keinen Treffer. Der neue serverseitige TURN-Schlüssel
wurde zusätzlich ausschließlich im Speicher gegen 776 Dateien und dieselben
350 Archiveinträge geprüft: ebenfalls kein Treffer.

Bei einem Anrufproblem zunächst `SCHULPILOT_CALLS_ENABLED=false` setzen und die
aktuellen App-Dienste neu starten. Ein Vorwärtsfix erhält die aktuelle
Wiederherstellungs-, Export- und Aufbewahrungslogik.

Release 78, `20261021T164256Z-7367ee4`, ist nur ein begrenzter Notfallrückweg.
Das Schema 0026 ist additiv, wurde aber nicht mit einer laufenden alten 78-API
abgenommen. Dessen normaler Migrations- und Restoreprüfpfad kennt Revision 0026
nicht. Eine Notfallaktivierung benötigt deshalb ausdrücklich
`--rollback-compatible`; sie darf weder das Schema zurücksetzen noch aktuelle
Antworten oder Pushgeräte durch eine alte Datenbanksicherung ersetzen. Für einen
längeren Rückbetrieb wären zusätzlich eine 0026-fähige Restoreprüfung und die
aktuelle Call-Aufbewahrungs-/Exportpflege erforderlich. Kein langfristig vollständig
geprüfter Rückbetrieb wird behauptet. Es erfolgte kein Play-Upload.

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
