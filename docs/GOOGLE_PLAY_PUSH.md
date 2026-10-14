# Google Play und Push

Die gewünschte Google-Anbindung betrifft Play-Veröffentlichung und Push, keinen Google-Login. Anmeldung, Familien und Inhalte bleiben in der eigenen API. Die Firebase-/Play-Konfiguration wird über den autorisierten Google-Zugang vorbereitet. Ein vorhandenes Firebase-Projekt und öffentliche App-Kennungen belegen weder die Integration des Dienstkontos in das Backend noch eine echte Push-Zustellung oder Play-Veröffentlichung. Reguläre Lernfunktionen benötigen diese optionalen Dienste nicht. Aktueller Schwerpunkt sind funktionierende Lernabläufe und die Flutter-Oberfläche für Mobilgeräte und Web.

## Android-Dateien und Signierung

- Paket: `de.dorfspy.schulpilot`, Version `0.1.0`, zuletzt vor dem aktuellen UI-Ausbau geprüfter Version-Code `10`, Android 7.0 / API 24 bis Ziel-API 36. Den tatsächlich bereitgestellten Versionscode aus `/api/app-release` und [STATUS.md](STATUS.md) übernehmen.
- Test-APK: `artifacts/schulpilot-0.1.0-test.apk`. Wird bei Deployment unter `/downloads/schulpilot-android.apk` veröffentlicht und vor/nach Web-Login verlinkt. `/api/app-release` enthält die tatsächliche Größe, Version und SHA-256.
- Upload-AAB: `artifacts/schulpilot-0.1.0-upload.aab`. Nicht öffentlich und nicht in Git. Google Play verteilt daraus mit Play App Signing signierte APKs.
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

Play-Release-Builds verweigern fehlende Upload-Signierung auch ohne `SCHULPILOT_STORE_BUILD=true`; der Play-Release-Flavour fällt nicht auf den Debugschlüssel zurück. Eine angegebene Properties-Datei benötigt ein vorhandenes Keystore sowie nichtleere Werte für `storeFile`, `storePassword`, `keyAlias` und `keyPassword`. Lokale Entwickler können weiterhin `playDebug` beziehungsweise den Direct-Flavour mit Debugschlüssel testen. `SCHULPILOT_STORE_BUILD=true` verlangt den Upload-Schlüssel zusätzlich bereits bei der Konfiguration des Builds. Der erste öffentlich bereitgestellte Stand war debugsigniert; ein Wechsel auf den Upload-Schlüssel erfordert gegebenenfalls einmalige Deinstallation der alten Test-APK. Vor weiteren Play-Uploads den Version-Code erhöhen.

`firebase_core 4.15.0` meldet im Android-Build einen Hinweis zu künftigem Built-in Kotlin. Die frühere Prüfung des ursprünglichen Releases protokolliert einen erfolgreichen Build mit Flutter 3.47.7/AGP 9.1.0; sie ist kein neuer Android-Build der hier geänderten Signierregel. Vor einem Flutter-/Gradle-Upgrade das Plugin und den Hinweis erneut prüfen.

## Push konfigurieren

Der Einrichtungsassistent beziehungsweise der Adminbereich kann öffentliche Firebase-App-Konfiguration, Dienstkonto-JSON und dokumentierte Push-Freigabe verschlüsselt speichern. Die Projekt-IDs werden abgeglichen; Geheimnisse werden nicht zurückgegeben. Damit gelten Änderungen ohne Dienstneustart. Der folgende lokale Dateipfad bleibt als Alternative für Betreiber verfügbar; gespeicherte Einstellungen haben Vorrang.

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


Aktueller Ausbau: Die Betreiberfreigabe wurde ausdrücklich erteilt und in [APPROVALS.md](APPROVALS.md) protokolliert. Google-Projektkennungen und Zugangsdaten bleiben davon getrennte technische Voraussetzungen. Vorbereitete deutsche Storetexte und ein technisches Data-Safety-/Review-Arbeitsblatt stehen in `store/`. Physische Geräteprüfung und echte FCM-Zustellung bleiben ohne entsprechenden Nachweis offen.

Das Preflight-Skript prüft ausschließlich den vorliegenden Stand; es erstellt weder Google-Ressourcen noch Schlüssel und führt keinen Console-Upload aus:

```bash
python3 scripts/google_readiness.py \
  --aab /pfad/zum/tatsaechlichen/app-play-release.aab \
  --bundletool /pfad/bundletool.jar \
  --strict
python3 -m unittest scripts/test_google_readiness.py -v
```

Fehlende Dateien und nicht erreichbare öffentliche Endpunkte werden als Blocker im JSON-Bericht gesammelt. `--strict` liefert dann einen Fehlerstatus, ohne den Bericht zu verlieren. Das weiter unterstützte Feld `aab_built` bedeutet ausschließlich, dass die ausgewählte Datei existiert (`aab_built_evidence:file_presence_only`). Dateiname, Größe und SHA-256 ordnen den Bericht dem tatsächlich geprüften Bundle zu.

Mit vorhandenem Bundletool prüft das Skript Bundle-Struktur und tatsächliches Base-Manifest: Paketname, mindestens Ziel-API 36, Versionsstand gegenüber `pubspec.yaml`, deaktivierten Debugmodus und fehlende APK-Installerberechtigung im Play-Bundle. Jarsigner prüft die tatsächliche Bundle-Signatur; Keytool erkennt den üblichen Android-Debugsignierer. Die angeforderte 16-KB-ZIP-Ausrichtung aus der Bundle-Konfiguration und die tatsächlichen 64-Bit-ELF-Load-/RELRO-Ausrichtungen sind getrennte Ergebnisse. Diese Prüfungen sind kein Laufzeittest auf einem 16-KB-Gerät und keine Google-Freigabe.

Beim Review dieser Änderung wurde die fixierte Flutter-Toolchain eingerichtet. Android-SDK, Keystore und das ursprüngliche AAB sind in dieser Arbeitsumgebung nicht vorhanden. Die neue Signierregel ist deshalb noch mit der fixierten Toolchain auf dem vorhandenen Build-Rechner zu prüfen: `playDebug` ohne Upload-Schlüssel muss möglich bleiben; `playRelease` ohne Schlüssel muss scheitern; der signierte Play-Release muss mit dem vorhandenen externen Schlüssel neu gebaut und geprüft werden. Der früher protokollierte APK-/AAB-Prüfstand oben wird damit nicht als neuer Build dieser Änderung ausgegeben.

## Aktuelle Google-Vorgaben, Stand 14.10.2026

Für neue Smartphone-Apps und Updates verlangt Google Play seit 31.08.2026 mindestens Android 16 / Ziel-API 36. Die Quellkonfiguration setzt Compile- und Ziel-API bereits auf 36; das endgültige Bundle-Manifest bleibt maßgeblich. [Google: Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en).

Persönliche Entwicklerkonten, die nach dem 13.11.2023 erstellt wurden, benötigen vor dem Antrag auf Produktionszugang einen geschlossenen Test mit mindestens zwölf Personen, die mindestens 14 Tage ununterbrochen angemeldet bleiben. Das ist keine pauschale Pflicht für jedes Kontomodell und kein interner Test. Kontotyp, Erstellungsdatum und konkrete Console-Anforderung erst im tatsächlichen Konto feststellen; vorhandene Testteilnahme oder Produktionsfreigabe nicht unterstellen. Nach Erfüllung sind echte Testnutzung, Rückmeldungen und Änderungen für den Produktionsantrag zu beschreiben. [Google: App testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en).

Die technischen 16-KB-Prüfschritte und ihre Grenzen richten sich nach [Android: Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes). Ein aktuelles AGP allein beweist weder die Ausrichtung jeder vorcompilierten Flutter-/Plugin-Bibliothek noch das Verhalten der App auf einem tatsächlichen 16-KB-System.

Android prüft jetzt bei jedem Start auf Updates. Direkter Download und Google Play verwenden getrennte Build-Flavors; siehe [ANDROID_UPDATES.md](ANDROID_UPDATES.md). Ein Play-AAB darf keine direkte APK-Installationsberechtigung enthalten.

Vor einer Console-Einreichung auch das ausschließlich im Play-Flavor enthaltene In-App-Update-SDK in den Datensicherheitsangaben prüfen. Die direkte APK verwendet dieses SDK nicht.

## In dieser Sitzung bestätigter Firebase-Bestand

Am 14.10.2026 in der Firebase-Konsole gelesen: Projekt `schulpilot-f6bf3`, Projektnummer `460657028995`; Android-Paket `de.dorfspy.schulpilot`, Android-App-ID `1:460657028995:android:9475b4497b0c9de08590b6` und Web-App-ID `1:460657028995:web:67373b18092ab46f8590b6`. FCM HTTP v1 ist aktiviert und ein öffentliches Web-VAPID-Schlüsselpaar existiert. Ein Dienstkonto wurde in dieser Sitzung nicht erzeugt; ein funktionierender Backend-Versand ist damit nicht nachgewiesen. Aktuelle Google-Sitzung weicht vom gewünschten Eigentümerkonto ab; dessen Zugriff ist noch nicht bestätigt. Persönliche Kontoadressen werden hier nicht veröffentlicht. Unter dem angemeldeten Konto zeigt Google Play die Entwicklerkonto-Erstellung.
