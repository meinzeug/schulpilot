# Android-Updates

Die Download-APK prüft **bei jedem Start und bei jedem erneuten Öffnen aus dem Hintergrund** das öffentliche HTTPS-Release-Manifest. Keine Tagesfrist, keine Anmeldung und keine übermittelte Familienkennung. Eine bereits laufende Prüfung wird gemeinsam verwendet; es gibt keine parallelen Downloads. Fehler verhindern das Lernen nicht. Beim nächsten Öffnen erfolgt eine neue Prüfung.

## Direkte APK

Flavor `direct` lädt eine höhere Version automatisch vom festen Schulpilot-Downloadpfad. HTTPS ohne Weiterleitungen, höchstens 150 MiB, begrenzte Verbindungs-/Lese-/Gesamtdauer. Der Download bleibt im privaten App-Cache. Größe, SHA-256, Paketname, exakter Versionscode, Mindest-Android und derselbe Signierer wie bei der installierten App werden geprüft. Kein Downgrade, kein beliebiger Downloadpfad, kein Zugriff auf Account-Tokens. Abgebrochene Dateien werden verworfen; eine schon vollständig geprüfte Datei kann beim nächsten Start erneut geprüft und verwendet werden.

Nach erfolgreicher Prüfung wird die APK an Androids Installationsoberfläche übergeben. Ab Android 8 muss das Betriebssystem gegebenenfalls einmalig die Installation aus dieser App erlauben. Danach bestätigt der Nutzer das Update. Keine stille Installation und keine Erweiterung der Geräteverwaltung. Ablehnung und „Später“ bleiben möglich; die Lernfolge bleibt serverseitig gespeichert. Ein erneuter Start prüft den Server wieder. Erst der tatsächliche neue Versionscode belegt eine erfolgreiche Installation.

Nur der direkte Flavor enthält `REQUEST_INSTALL_PACKAGES` und den nicht exportierten, auf den Update-Cache beschränkten `FileProvider`. Diese Variante wird als Test-APK über die Website verteilt.

## Google Play

Flavor `play` enthält weder die APK-Installationsberechtigung noch den direkten Download-/Installationscode. Er prüft bei jedem Start mit Googles `app-update:2.1.0` und verwendet die offizielle unmittelbare In-App-Aktualisierung. Eine begonnene Play-Aktualisierung wird wieder aufgenommen. Auch hier bleibt die Systembestätigung maßgeblich.

Ohne berechtigtes Play-Projekt, veröffentlichte Version und eine über Play installierte Testversion kann keine echte Play-Updatezustellung geprüft werden. Das gebaute AAB allein beweist diese Zustellung nicht. Play-App-Signing und direkte APKs können unterschiedliche Signierer haben; die Verteilungswege nicht durch eine unsignierte oder anders signierte APK vermischen.

## Reproduzierbarer Build

```bash
cd app
export SCHULPILOT_SIGNING_PROPERTIES="$HOME/.local/share/schulpilot-signing/signing.properties"
export SCHULPILOT_STORE_BUILD=true
flutter build apk --flavor direct --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
flutter build appbundle --flavor play --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api
```

Artefakte: `app/build/app/outputs/flutter-apk/app-direct-release.apk` und `app/build/app/outputs/bundle/playRelease/app-play-release.aab`. Vor Deployment die APK unter `artifacts/schulpilot-0.1.0-test.apk` ablegen; `scripts/android_manifest.py` berechnet das öffentliche Manifest aus dieser Datei. Für jedes neue Update den Versionscode erhöhen. Private Signierschlüssel unverändert außerhalb des Repositorys halten.

## Tatsächliche Prüfung

Der native Prüftreiber `qa/android_update.py` verwendet ausschließlich den eigenen Emulator und zwei tatsächlich signierte Versionen. Er prüft neue Startabrufe und den echten Installationsdialog samt Versionswechsel. Ergebnis und verbleibende Grenzen in [STATUS.md](STATUS.md).
