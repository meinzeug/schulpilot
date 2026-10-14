# Google Play und Push

Die gewünschte Google-Anbindung betrifft Play-Veröffentlichung und Push, keinen Google-Login. Anmeldung, Familien und Inhalte bleiben in der eigenen API. Ein Firebase-/Play-Zugang wurde bisher nicht bereitgestellt; es wurde kein Konto und keine kostenpflichtige Ressource bestellt.

## Android-Dateien und Signierung

- Paket: `de.dorfspy.schulpilot`, Version `0.1.0`, Version-Code `8`, Android 7.0 / API 24 bis Ziel-API 36.
- Test-APK: `artifacts/schulpilot-0.1.0-test.apk`. Wird bei Deployment unter `/downloads/schulpilot-android.apk` veröffentlicht und vor/nach Web-Login verlinkt. `/api/app-release` enthält die tatsächliche Größe, Version und SHA-256.
- Upload-AAB: `artifacts/schulpilot-0.1.0-upload.aab`. Nicht öffentlich und nicht in Git. Google Play verteilt daraus mit Play App Signing signierte APKs.
- Eigener RSA-4096-Upload-Schlüssel und Passwörter: `~/.local/share/schulpilot-signing/`, Verzeichnis 0700, Dateien 0600. Unbedingt separat verschlüsselt sichern. Der private Schlüssel wird weder auf den App-Server noch zu GitHub kopiert. Der Google-App-Signing-Schlüssel ist davon getrennt.

Reproduzierbarer Build mit der fixierten Flutter-Version aus `toolchain.json`:

```bash
python3 scripts/create_upload_key.py # erhält vorhandene Schlüssel
cd app
export SCHULPILOT_SIGNING_PROPERTIES="$HOME/.local/share/schulpilot-signing/signing.properties"
export SCHULPILOT_STORE_BUILD=true
flutter build apk --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
flutter build appbundle --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
```

`SCHULPILOT_STORE_BUILD=true` verweigert einen Build ohne externen Upload-Schlüssel. Ohne dieses Flag können Entwickler weiterhin ausdrücklich mit einem lokalen Debugschlüssel testen. Der erste öffentlich bereitgestellte Stand war debugsigniert; ein Wechsel auf den Upload-Schlüssel erfordert gegebenenfalls einmalige Deinstallation der alten Test-APK. Vor weiteren Play-Uploads den Version-Code erhöhen.

`firebase_core 4.15.0` meldet im Android-Build einen Hinweis zu künftigem Built-in Kotlin. Die hier fixierte Kombination mit Flutter 3.47.7/AGP 9.1.0 baut erfolgreich. Vor einem Flutter-/Gradle-Upgrade das Plugin und den Hinweis erneut prüfen.

## Push konfigurieren

1. Im autorisierten Firebase-Projekt eine Android-App mit obigem Paketnamen und eine Web-App anlegen. Firebase Cloud Messaging HTTP v1 aktivieren, öffentlichen Web-VAPID-Schlüssel erstellen. Kein Analytics benötigt.
2. Ein eigenes Dienstkonto mit minimaler Berechtigung zum Senden von FCM-Nachrichten verwenden. Dienstkontodatei ausschließlich unter `/etc/schulpilot/fcm-service-account.json` ablegen, root:schulpilot, 0640. Nicht die Entwicklungsidentität oder fremde OAuth-/Google-Ads-Zugänge verwenden.
3. In `/etc/schulpilot/environment` ergänzen (Werte sicher quotieren; Datei ist keine ausführbare Shell):

```dotenv
FCM_SERVICE_ACCOUNT_FILE=/etc/schulpilot/fcm-service-account.json
FCM_PUBLIC_CONFIG='{"apiKey":"PUBLIC_FIREBASE_WEB_API_KEY","appId":"WEB_APP_ID","androidAppId":"ANDROID_APP_ID","messagingSenderId":"SENDER_ID","projectId":"PROJECT_ID","authDomain":"PROJECT_ID.firebaseapp.com","vapidKey":"PUBLIC_WEB_VAPID_KEY"}'
PUSH_APPROVED=true
PUSH_PRIVACY_EVIDENCE='Verweis auf dokumentierte Firebase-/Minderjährigenprüfung'
```

Das sind ausdrücklich Platzhalter. Das Dienstkonto enthält einen privaten Schlüssel; `FCM_PUBLIC_CONFIG` enthält ausschließlich öffentliche Client-Kennungen. Der Dienstkonto-Projektname muss mit der öffentlichen Projekt-ID übereinstimmen; der OAuth-Token-Endpunkt ist fest auf Google beschränkt. Keine automatische Suche nach anderen Google-Zugängen.

4. Nur SCHULPILOT-API/-Worker neu starten. `/api/notifications/config` muss `available:true` liefern; es werden niemals Dienstkonto, OAuth-Token oder private Schlüssel zurückgegeben.
5. Angemeldet unter „Zugänge & Einstellungen → Benachrichtigungen“ freiwillig je Gerät aktivieren. Erst dann initialisiert Flutter Firebase und fragt die Betriebssystem-/Browser-Erlaubnis ab. Ohne gültige Sitzung/Opt-in keine Firebase-Registrierung. Der serverseitig erzeugte `/firebase-messaging-sw.js` initialisiert die fixierte JS-Version 12.19.0 synchron mit ausschließlich öffentlichen Kennungen.
6. Tatsächliche Zustellung auf Android und Web im Vordergrund, Hintergrund und nach Neustart testen. Registrierung allein ist kein Zustellnachweis. Bei HTTP-/Authentifizierungsfehlern bleibt ein inhaltsfreier Fehlercode in der geschützten Outbox. `accepted` bedeutet Annahme durch FCM, nicht nachgewiesene Anzeige auf dem Gerät.

Push-Gerätetokens liegen verschlüsselt in der DB und sind an eine widerrufbare SCHULPILOT-Sitzung gebunden. Konto-/Gerätewechsel ersetzt alte Registrierungen. Abmeldung, Ablauf, Rechteentzug und Kontolöschung verhindern weitere Sendungen; Rechte werden unmittelbar vor dem Aufruf erneut geprüft. Ungültige FCM-Tokens werden entfernt. Höchstens ein Tagesbündel pro Kategorie/Gerät, aktuelle Elternvorgaben und Ruhezeiten gelten zusätzlich zu Geräteinstellungen. TTL höchstens 60 Sekunden und spätestens bis zur nächsten Ruhezeit. Timeouts werden nicht automatisch wiederholt.

Es werden ausschließlich neutrale Texte mit festem `/app`-Ziel übertragen: keine Kindernamen, Familien-IDs, Themen, Antworten, Noten oder Diagnosen, keine öffentlichen FCM-Themen. Es gibt kein öffentliches „Nachricht an beliebigen Token senden“-API. Nicht jede falsche Antwort erzeugt eine Meldung. In-App-Erinnerungen bleiben unabhängig von Firebase nutzbar.

## Veröffentlichung abschließen

Im berechtigten Play-Console-Konto die App mit dem festen Paketnamen anlegen, Play App Signing einrichten und zunächst das signierte AAB im internen Test prüfen. Eine Console-Veröffentlichung wurde ohne vorliegenden Zugang nicht durchgeführt.

Vor Store-Veröffentlichung müssen die tatsächlichen Angaben zu Betreiber, Support, Datenschutz, Zielalter/Families, Data Safety, Inhaltsbewertung, KI-Inhalten und App-Zugriff vollständig hinterlegt sein. Keine Betreiberangaben erfinden. Die Anbieter-/Datenschutzfreigabe für den regulären OpenRouter-Free-Modus ist erteilt; Konfiguration und tatsächliche Abnahme stehen in [AI_STANDARD.md](AI_STANDARD.md) und [STATUS.md](STATUS.md). Unsere Prüfungen verwenden ausschließlich künstliche Daten. Ein fertiger Build ersetzt weder die pädagogische Abnahme noch Googles Prüfung.

Web-Ressource zur Kontolöschung: https://schulpilot.dorfspy.de/account-deletion . Der vollständige authentifizierte Löschablauf ist auch ohne Android-App im Web verfügbar. Für Reviewer ist ein zeitlich begrenzter synthetischer Testzugang vorzusehen; keine echten Kinderinhalte bereitstellen. APK-/AAB-Signaturen und 16-KB-Seitengrößen-Kompatibilität vor dem Store-Upload mit dem tatsächlichen Bundle prüfen.


Tatsächliche Validierung vom 14.10.2026: endgültige APK installiert und in einem API-36-Emulator gegen die öffentliche HTTPS-API bedient (Eltern-/Kinderlogin, Sitzungsneustart, Hinweis/Antwort, Widerruf, Löschung). Alle vier Aufgabenarten zusätzlich im echten Web-Browser geprüft. Das endgültige AAB besteht `bundletool 1.18.3 validate`; APK besteht `apksigner verify` und `zipalign -c -P 16 4`. Alle acht geprüften 64-Bit-ELF-Bibliotheken haben PT_LOAD-Ausrichtungen von mindestens 16 KB. Das ist kein behaupteter Play-Console-Prüferfolg oder Firebase-Zustelltest.


Aktueller Ausbau: Die Betreiberfreigabe wurde ausdrücklich erteilt und in [APPROVALS.md](APPROVALS.md) protokolliert. Fehlende Google-Projektkennungen und Zugangsdaten bleiben davon getrennte technische Voraussetzungen. Vorbereitete deutsche Storetexte und ein technisches Data-Safety-/Review-Arbeitsblatt stehen in `store/`. `scripts/google_readiness.py --bundletool /pfad/bundletool.jar` prüft den öffentlichen APK-Stand, Betreiberangaben, Textlängen und das tatsächliche AAB, führt aber keinen Console-Upload aus. Physische Geräteprüfung und echte FCM-Zustellung bleiben ohne entsprechendes Gerät/Projekt offen.
