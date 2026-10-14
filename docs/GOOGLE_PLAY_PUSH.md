# Google Play und Push

Google wird ausschließlich für Play und freiwilliges Push verwendet. Eigene Anmeldung, Familien und Inhalte bleiben in unserer API. Das vorhandene Firebase-Projekt ist `schulpilot-f6bf3` (460657028995), mit bereits angelegter Android- und Web-App. Keine zweiten Projekte, Apps oder VAPID-Schlüssel erzeugen. Der tatsächliche Cloud-/Build-/Zustellstand steht in `CHATGPT_HANDOFF.txt`; die sichere Fortsetzung beschreibt [FIREBASE_OPERATIONS.md](FIREBASE_OPERATIONS.md). Lernen funktioniert unabhängig von Firebase.

## Android-Dateien und Signierung

- Paket: `de.dorfspy.schulpilot`, Version `1.0.0`, aktueller Version-Code `14`, Android 7.0 / API 24 bis Ziel-API 36. Den tatsächlich bereitgestellten Versionscode aus `/api/app-release` und [STATUS.md](STATUS.md) übernehmen.
- Reguläre Direct-APK: `artifacts/schulpilot-android.apk`. Wird bei Deployment unter `/downloads/schulpilot-android.apk` veröffentlicht und vor/nach Web-Login verlinkt. `/api/app-release` enthält die tatsächliche Größe, Version, SHA-256 und den Kanal `stable`.
- Upload-AAB: `artifacts/schulpilot-play.aab`. Nicht öffentlich und nicht in Git. Google Play verteilt daraus mit Play App Signing signierte APKs.
- Eigener RSA-4096-Upload-Schlüssel und Passwörter: `~/.local/share/schulpilot-signing/`, Verzeichnis 0700, Dateien 0600. Unbedingt separat verschlüsselt sichern. Der private Schlüssel wird weder auf den App-Server noch zu GitHub kopiert. Der Google-App-Signing-Schlüssel ist davon getrennt.

Reproduzierbarer Build mit der fixierten Flutter-Version aus `toolchain.json`:

```bash
python3 scripts/create_upload_key.py # erhält vorhandene Schlüssel
cd app
export SCHULPILOT_SIGNING_PROPERTIES="$HOME/.local/share/schulpilot-signing/signing.properties"
export SCHULPILOT_STORE_BUILD=true
flutter build apk --flavor direct --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
flutter build appbundle --flavor play --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
```

`bash scripts/build_release.sh` setzt die erforderliche Signierung und baut alle drei Artefakte. Release-Aufträge ohne externen Schlüssel werden abgewiesen; normale Debug-Builds bleiben für lokale Entwicklung verfügbar. Der erste historische Stand war debugsigniert; der Wechsel auf den Upload-Schlüssel erforderte gegebenenfalls eine einmalige Deinstallation. Aktuelle signierte Direct-Versionen behalten Paket und Signierer und werden regulär aktualisiert. Vor weiteren Play-Uploads den Version-Code erhöhen.

`firebase_core 4.15.0` meldet im Android-Build einen Hinweis zu künftigem Built-in Kotlin. Die hier fixierte Kombination mit Flutter 3.47.7/AGP 9.1.0 baut erfolgreich. Vor einem Flutter-/Gradle-Upgrade das Plugin und den Hinweis erneut prüfen.

## Push konfigurieren

Der Einrichtungsassistent beziehungsweise der Adminbereich kann öffentliche Firebase-App-Konfiguration, Dienstkonto-JSON und dokumentierte Push-Freigabe verschlüsselt speichern. Die Projekt-IDs werden abgeglichen; Geheimnisse werden nicht zurückgegeben. Damit gelten Änderungen ohne Dienstneustart. Der folgende lokale Dateipfad bleibt als Alternative für Betreiber verfügbar; gespeicherte Einstellungen haben Vorrang.

1. Bestehende Apps verwenden: Android `1:460657028995:android:9475b4497b0c9de08590b6`, Web `1:460657028995:web:67373b18092ab46f8590b6`. FCM-, Registration- und Installations-APIs sowie die tatsächlichen API-Key-Einschränkungen prüfen. Vorhandenen VAPID-Schlüssel erhalten. Keine weiteren Firebase-Dienste aktivieren.
2. Ein eigenes Dienstkonto mit minimaler Berechtigung zum Senden von FCM-Nachrichten verwenden. Dienstkontodatei ausschließlich unter `/etc/schulpilot/fcm-service-account.json` ablegen, root:schulpilot, 0640. Nicht die Entwicklungsidentität oder fremde OAuth-/Google-Ads-Zugänge verwenden.
3. In `/etc/schulpilot/environment` ergänzen (Werte sicher quotieren; Datei ist keine ausführbare Shell):

```dotenv
FCM_SERVICE_ACCOUNT_FILE=/etc/schulpilot/fcm-service-account.json
FCM_PUBLIC_CONFIG='{"apiKey":"PUBLIC_FIREBASE_WEB_API_KEY","androidApiKey":"PUBLIC_FIREBASE_ANDROID_API_KEY","appId":"WEB_APP_ID","androidAppId":"ANDROID_APP_ID","messagingSenderId":"SENDER_ID","projectId":"PROJECT_ID","authDomain":"PROJECT_ID.firebaseapp.com","vapidKey":"PUBLIC_WEB_VAPID_KEY"}'
FCM_CONFIG_VERIFICATION='Nachweis tatsächlich geprüfter Apps, APIs und Schlüsselrestriktionen'
PUSH_APPROVED=false
PUSH_PRIVACY_EVIDENCE='Verweis auf dokumentierte Firebase-/Minderjährigenprüfung'
```

Das sind ausdrücklich Platzhalter. Das Dienstkonto enthält einen privaten Schlüssel; `FCM_PUBLIC_CONFIG` enthält ausschließlich öffentliche Client-Kennungen. Der Dienstkonto-Projektname muss mit der öffentlichen Projekt-ID übereinstimmen; der OAuth-Token-Endpunkt ist fest auf Google beschränkt. Keine automatische Suche nach anderen Google-Zugängen.

4. Ein Schlüssel allein erlaubt keine produktive Push-Freigabe. Allgemeine Freigabe und Testfreigaben sind getrennt; allgemeines `available:true` setzt dokumentierte technische Prüfung und Betreiberentscheidung voraus. Nur SCHULPILOT-API/-Worker neu starten. Keine Dienstkontoinhalte oder OAuth-Tokens zurückgeben. Betriebsprüfung unter `/admin/push`.
5. Unter `/settings` freiwillig je Gerät einschalten. Kinder benötigen vorher die zusätzliche Elternfreigabe in den Lernvorgaben. Erst dann initialisiert Flutter Firebase und fragt die Geräteerlaubnis ab. `/push/firebase-messaging-sw.js` verwendet den eigenen Bereich `/push/` und JS 12.19.0; der frühere Rootpfad bleibt für ältere Clients erreichbar. Das fixierte Messaging-SDK 16.7.0 verwendet weiterhin seine tatsächlich vorhandenen `getToken`-/`onTokenRefresh`-APIs; keine Migration nur aufgrund einer neueren Anleitung.
6. Tatsächliche Zustellung auf Android und Web im Vordergrund, Hintergrund und nach Neustart testen. Registrierung allein ist kein Zustellnachweis. Bei HTTP-/Authentifizierungsfehlern bleibt ein inhaltsfreier Fehlercode in der geschützten Outbox. `accepted` bedeutet Annahme durch FCM, nicht nachgewiesene Anzeige auf dem Gerät.

Push-Gerätetokens liegen verschlüsselt in der DB und sind an eine widerrufbare SCHULPILOT-Sitzung gebunden. Konto-/Gerätewechsel ersetzt alte Registrierungen. Abmeldung, Ablauf, Rechteentzug und Kontolöschung verhindern weitere Sendungen; Rechte werden unmittelbar vor dem Aufruf erneut geprüft. Ungültige FCM-Tokens werden entfernt. Höchstens ein Tagesbündel pro Kategorie/Gerät, aktuelle Elternvorgaben und Ruhezeiten gelten zusätzlich zu Geräteinstellungen. TTL höchstens 60 Sekunden und spätestens bis zur nächsten Ruhezeit. Timeouts werden nicht automatisch wiederholt.

Es werden ausschließlich neutrale Texte mit festem `/app`-Ziel übertragen: keine Kindernamen, Familien-IDs, Themen, Antworten, Noten oder Diagnosen, keine öffentlichen FCM-Themen. Es gibt kein öffentliches „Nachricht an beliebigen Token senden“-API. Nicht jede falsche Antwort erzeugt eine Meldung. In-App-Erinnerungen bleiben unabhängig von Firebase nutzbar.

## Veröffentlichung abschließen

Im berechtigten Play-Console-Konto die App mit dem festen Paketnamen anlegen, Play App Signing einrichten und zunächst das signierte AAB im internen Test prüfen. Eine Console-Veröffentlichung wurde ohne vorliegenden Zugang nicht durchgeführt.

Vor Store-Veröffentlichung müssen die tatsächlichen Angaben zu Betreiber, Support, Datenschutz, Zielalter/Families, Data Safety, Inhaltsbewertung, KI-Inhalten und App-Zugriff vollständig hinterlegt sein. Keine Betreiberangaben erfinden. Die Anbieter-/Datenschutzfreigabe für den regulären OpenRouter-Free-Modus ist erteilt; Konfiguration und tatsächliche Abnahme stehen in [AI_STANDARD.md](AI_STANDARD.md) und [STATUS.md](STATUS.md). Unsere Prüfungen verwenden ausschließlich künstliche Daten. Ein fertiger Build ersetzt weder die pädagogische Abnahme noch Googles Prüfung.

Web-Ressource zur Kontolöschung: https://schulpilot.dorfspy.de/account-deletion . Der vollständige authentifizierte Löschablauf ist auch ohne Android-App im Web verfügbar. Für Reviewer ist ein zeitlich begrenzter synthetischer Testzugang vorzusehen; keine echten Kinderinhalte bereitstellen. APK-/AAB-Signaturen und 16-KB-Seitengrößen-Kompatibilität vor dem Store-Upload mit dem tatsächlichen Bundle prüfen.


Tatsächliche Validierung vom 14.10.2026: endgültige APK installiert und in einem API-36-Emulator gegen die öffentliche HTTPS-API bedient (Eltern-/Kinderlogin, Sitzungsneustart, Hinweis/Antwort, Widerruf, Löschung). Alle vier Aufgabenarten zusätzlich im echten Web-Browser geprüft. Das endgültige AAB besteht `bundletool 1.18.3 validate`; APK besteht `apksigner verify` und `zipalign -c -P 16 4`. Alle acht geprüften 64-Bit-ELF-Bibliotheken haben PT_LOAD-Ausrichtungen von mindestens 16 KB. Das ist kein behaupteter Play-Console-Prüferfolg oder Firebase-Zustelltest.


Aktueller Ausbau: Die KI-Betreiberfreigabe ist in [APPROVALS.md](APPROVALS.md) protokolliert. Firebase-Projekt, APIs, getrennte Plattformkeys, minimal berechtigtes Senderkonto und serverseitige OAuth-/FCM-Validierung wurden tatsächlich geprüft. Die allgemeine Push-Freigabe bleibt bis zur gesonderten konkreten Betreiberentscheidung aus. Vorbereitete deutsche Storetexte und ein technisches Data-Safety-/Review-Arbeitsblatt stehen in `store/`. `scripts/google_readiness.py --bundletool /pfad/bundletool.jar` prüft den öffentlichen APK-Stand, Betreiberangaben, Textlängen und das tatsächliche AAB, führt aber keinen Console-Upload aus. Sichtbare FCM-Zustellung und physische Gerätebeobachtung bleiben getrennte offene Prüfungen; der aktuelle Einzelstand steht in `CHATGPT_HANDOFF.txt`.

Android prüft jetzt bei jedem Start auf Updates. Direkter Download und Google Play verwenden getrennte Build-Flavors; siehe [ANDROID_UPDATES.md](ANDROID_UPDATES.md). Ein Play-AAB darf keine direkte APK-Installationsberechtigung enthalten.

Vor einer Console-Einreichung auch das ausschließlich im Play-Flavor enthaltene In-App-Update-SDK in den Datensicherheitsangaben prüfen. Die direkte APK verwendet dieses SDK nicht.
