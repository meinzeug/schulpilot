# Android: Familienanrufe und Geräte-Push

Die bestehende Firebase-App im Projekt `schulpilot-f6bf3` bleibt unverändert.
Es gibt keine neue Firebase-App, keinen neuen VAPID-Schlüssel und keinen zweiten
Nachrichtendienst. Anmeldung allein erlaubt weiterhin keine Push-Verarbeitung.

## Gerätefreigabe

Im Elternzugang unter Benachrichtigungen → Auf diesem Gerät lässt sich zusätzlich
„Familienanrufe auf diesem Gerät“ einschalten. Erst das bewusste Speichern und
die Android-Berechtigung registrieren das Gerät. Diese zusätzliche Auswahl ist
zunächst aus, auch bei bereits erlaubten normalen Familiennachrichten. Sie ist
an das Elternkonto, dessen widerrufbare Sitzung und genau diese Registrierung
gebunden. Kinder können keine Eltern-Gerätefreigabe erteilen.

`PushClient.enable` erzeugt bei dieser Auswahl eine zufällige 256-Bit-Bindung.
Nach erfolgreicher Backend-Registrierung speichert `PushTransport` sie im privaten
Android-Speicher. Tokenwechsel verwenden dieselbe Bindung; erneute Anmeldung und
erneutes Einrichten erneuern sie. Logout entfernt Bindung, sichtbare Anrufe und
den aktiven Übertragungsdienst. Eine verspätete Pushnachricht aus einer älteren
Kontositzung kann deshalb keinen neuen Klingelhinweis auslösen.

Die Einstellungen zeigen den tatsächlichen App-/Kanalstatus sowie fehlenden
Klingelton, niedrig priorisierte Hinweise und Lautlos-/Nicht-stören-Einstellungen.
Es wird weder Nicht-stören-Zugriff noch die Umgehung einer Akku-/Berechtigungssperre
angefordert. Keine Kamera, kein Mikrofon und kein Bildschirm starten durch Push.

## Empfang und Annahme

`FamilyCallMessagingReceiver` ersetzt genau den bisherigen FlutterFire-Receiver
und delegiert sämtliche Nicht-Anrufnachrichten an dessen unveränderte
Implementierung. Der Receiver verlangt dieselbe Google-Signaturberechtigung
`com.google.android.c2dm.permission.SEND`. Eigene Medien-/Ablaufdienste sind nicht
öffentlich aufrufbar.

Anrufnachrichten sind Android-FCM-Datennachrichten mit hoher Transportpriorität.
Nur die Felder `type=family_call`, `event`, die zufällige `call_id`,
`call_binding`, `device_id` und `expires_at` in Millisekunden werden verwendet.
Namen, Lernstoff, Antworten, Nachrichten und Sitzungsgeheimnisse sind nicht
Bestandteil der Darstellung. Die Klasse `FamilyCallPolicy` prüft Bindung,
ID-Format und Ablauf. Ein Anruf klingelt höchstens 45 Sekunden; abgelaufene,
beendete, beantwortete und doppelte Anrufe werden unterdrückt.

Der Kanal `schulpilot_family_calls_v1` verwendet die Android-Klingeltonkategorie,
hohe Wichtigkeit und auf Android 12+ `Notification.CallStyle`. Frühere unterstützte
Versionen erhalten die festen Aktionen „Annehmen“ und „Ablehnen“. Android 8+
begrenzt die Meldung zusätzlich per `setTimeoutAfter`; Android 7 besitzt dafür
einen begrenzten lokalen Ablaufalarm. Die Aktion öffnet die App mit einer
kontrollierten Anruf-ID und einem der Werte `open`, `answer`, `decline`.
`FamilyCallNative` liefert dies an die gemeinsame Flutter-Steuerung. Erst diese
prüft den weiterhin berechtigten Serverzustand und führt eine bewusste Annahme
aus. Ein Push oder ein geöffneter Hinweis zählt nicht als angenommener Anruf.

Die echte Android-36-Instrumentierung zeigte vor Freigabe, dass `CallStyle`
einen Vordergrunddienst verlangt. `FamilyCallRingingService` hält deshalb nur
die sichtbare Klingelphase als `shortService`, höchstens 45 Sekunden und ohne
Medien, Telefonrolle oder automatischen Neustart. Der Receiver prüft die
tatsächlich zugestellte FCM-Priorität einschließlich einer Herabstufung durch
Google. Bei normaler Priorität oder verweigertem Dienststart bleibt eine normale
hohe Anrufmeldung mit denselben festen Aktionen möglich. Es wird kein erneuter
Dienststart und keine Vollbildfreigabe erzwungen. Ablauf, Annahme, Ablehnung und
Logout beenden den Klingeldienst.

Die App fordert bewusst keine `USE_FULL_SCREEN_INTENT`-Berechtigung an. Android
14 und Google Play beschränken deren automatische Freigabe auf Apps, deren
Hauptfunktion Anrufe oder Wecker sind. Je nach Geräteeinstellung erscheint die
Live-Hilfe als hervorgehobene Anrufmeldung oder in der Benachrichtigungsleiste.
Erzwungenes Beenden, fehlende Play-Dienste, Offlinebetrieb und Systembeschränkungen
können die zeitnahe Zustellung verhindern; In-App-Anrufe bleiben im Vordergrund
über den berechtigten Serverstatus erreichbar.

## Kamera, Mikrofon und Bildschirm

Der gemeinsame WebRTC-Code verlangt eine ausdrückliche Medienaktion. Android
prüft Kamera-/Mikrofonberechtigungen regulär. `FamilyCallCaptureService` ist nur
der sichtbare Lebenszykluscontainer für die vom Flutter-Plugin gehaltenen
Medientracks; er öffnet selbst keine Kamera, kein Mikrofon und keine Projektion.
Der Dienst beginnt erst nach erteilter Berechtigung aus der sichtbaren App,
deklariert die erforderlichen Kamera-/Mikrofon-/Projektions-Typen und wird bei
Anrufende, Logout und zerstörter Flutter-Aktivität entfernt. Er startet nach
einem Prozessneustart nicht automatisch neu (`START_NOT_STICKY`).

Android-Bildschirmfreigabe verwendet die Reihenfolge:

1. `Helper.requestCapturePermission()` mit dem echten Systemdialog.
2. `FamilyCallNative.startProjection(callId)` startet und bestätigt den sichtbaren
   `mediaProjection`-Vordergrunddienst.
3. `getDisplayMedia()` verwendet die soeben erteilte Zustimmung.
4. Beenden stoppt die Tracks und den zugehörigen Dienst.

Ablehnung führt nicht zu einer Ersatzfreigabe. Ein fehlender nativer
Übertragungsdienst darf nicht als erfolgreiche Aufnahme behandelt werden.

## Überprüfungen am 21.10.2026

Die separate Betriebsdiagnose fand eine freigegebene, verfügbare korrekte
Firebase-Konfiguration, aber **keine registrierten Geräte und keine
Versandvorgänge in den vorherigen sieben Tagen**. Damit lag für das gemeldete
Ausbleiben von Android-Hinweisen kein erreichbares registriertes Gerät vor.
Diese Diagnose rekonstruiert keine unbekannte frühere Geräteentscheidung.

Die anschließende reine Google-Prüfung bestätigte bestehendes Projekt und beide
Apps, aktivierte FCM-/Installations-/Registrierungs-APIs, getrennte Plattformkeys
ohne fehlende erforderliche APIs und die beschränkte Senderberechtigung
`cloudmessaging.messages.create`. Der tatsächliche Serversender konnte OAuth
verwenden; die Validierung an einem festen künstlichen Topic mit
`validate_only=true` antwortete mit HTTP 200. Dabei wurde keine Meldung an echte
Geräte geschickt. Eine solche Annahme allein beweist keine sichtbare Zustellung.

Sechs native Kotlin-Regeltests bestanden einschließlich herabgestufter FCM und
verspäteter Bereinigung eines früheren Anrufs. Die anschließende Instrumentierung
auf dem eigenen Android-36-Emulator bestätigte `CallStyle`, Klingeltonkanal,
Ablauf, Annahmeweitergabe, Deduplizierung, beendete Anrufe, alte Kontobindung und
Logout. Reproduzierbare lokale Sicherheitsprüfungen:

```sh
cd app
flutter test test/push_client_test.dart test/family_call_native_test.dart
cd android
./gradlew :app:testDirectDebugUnitTest
```

Die Android-Instrumentierung `FamilyCallInstrumentation` ist ausschließlich im
Test-APK enthalten. Sie verwendet feste künstliche IDs auf dem eigenen Emulator,
prüft sichtbare CallStyle-Meldung, Kanal, Ablauf, Annahmeweitergabe, Deduplizierung
und Abmeldung. `test/fixtures/native_call_runner.dart` ist ein ausdrücklich
künstlicher Offline-Einstieg und niemals das Ziel eines regulären Releasebuilds.
Eine Prüfung im Emulator ohne Audioausgabe ist kein Beleg für hörbares Klingeln
auf einem physischen Smartphone. Konkrete Zustell-/Gerätenachweise des Releases
stehen in STATUS und CHATGPT_HANDOFF.

Mit der signierten Version 1.19.0+79 wurde anschließend das bestehende künstliche
Elternprofil regulär angemeldet und Push einschließlich Familienanrufen ausdrücklich
auf dem eigenen Android-36-Emulator freigegeben. Eine einzelne normale
FCM-Hintergrundmeldung wurde nach belegtem Hintergrundwechsel tatsächlich in der
Android-Benachrichtigungsleiste angezeigt und öffnete die App. Das ist ein
Zustellnachweis dieses künstlichen Geräts, keine Aussage über andere Telefone.

Der erste echte künstliche Testanruf deckte eine Besonderheit der QA-Umgebung auf:
Host-VM und Emulator lagen rund 7.122 Sekunden vor der durch Produktions-NTP sowie
unabhängige HTTPS-Zeitquellen bestätigten UTC. Der native Ablauf verwarf deshalb
die bereits abgelaufenen absoluten Anrufzeitstempel korrekt. Gerätebindung und
Serverbindung stimmten überein. Ausschließlich der kurzlebige Emulator wurde für
die Gegenprobe auf die bestätigte UTC gesetzt und seine automatische Zeitquelle
vorübergehend abgeschaltet; Produktions-, Host- und echte Telefonuhren sowie
die Produkt-Ablaufprüfung blieben unverändert. Beim zweiten Versuch erschienen
die echte CallStyle-Karte und ihre Annahmeaktion. Der normale App-Dialog führte
zu einer verbundenen verschlüsselten Sitzung. Der Gegenpart empfing 962
Eltern-Videoframes und 4.497 Audioframes. Diese Framezahlen beweisen allein weder
hörbaren Ton noch die korrekte Anzeige der Kinder-Videospuren; die zunächst
dunklen Remote-Kacheln wurden als eigener Fehler zur Prüfung weitergegeben.
Der reguläre Elternlogout entfernte die native Gerätebindung und den Klingelstatus.

## Primärquellen

- [Android: CallStyle](https://developer.android.com/develop/ui/compose/notifications/call-style)
- [Android 14: Vollbildberechtigung](https://developer.android.com/about/versions/14/behavior-changes-14)
- [Android: Vordergrunddiensttypen](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android: Hintergrundstart von Vordergrunddiensten](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Android: Medienprojektion](https://developer.android.com/media/grow/media-projection)
- [Firebase: Empfang auf Android](https://firebase.google.com/docs/cloud-messaging/android/receive-messages)
- [Firebase: Nachrichtenpriorität](https://firebase.google.com/docs/cloud-messaging/android-message-priority)
- [flutter_webrtc 1.6.2+hotfix.4, Quellcode](https://github.com/flutter-webrtc/flutter-webrtc)
