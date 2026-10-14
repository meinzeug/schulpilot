# Projektstand · 14.10.2026 · 0.1.0+11

Web und native Flutter-APK sind auf https://schulpilot.dorfspy.de bereitgestellt. Die Änderungen dieser Arbeitseinheit vereinfachen den Kinderablauf und modernisieren die gemeinsame Oberfläche. Der vollständige reguläre KI-Lernablauf ist öffentlich geprüft. Auch die native Wiederaufnahme wurde geprüft; keine pauschale Produktionsreife behauptet.

## Umgesetzt

- Kinderstart mit einer klaren nächsten Aktion. Plan, Fotos, Nachrichten und Lernstand auf Wunsch öffnen; Elternhilfe ohne Pflichttext.
- Fotoassistent **Fotos → Prüfen → Lernen**: mehrere Seiten aufnehmen/importieren, optional zuschneiden, Weiter startet die Erkennung. Jede Seite und jede Unsicherheit ausdrücklich bestätigen. Jetzt lernen erstellt das Paket und öffnet die erste Einheit. Wiederaufnahme verwendet gespeicherte Inhalte.
- Eine Aufgabe je Ansicht, große mobile Bedienflächen. Rückmeldung und Erklärung bleiben bis zum ausdrücklichen Weiter sichtbar. Kurzer KI-Rückblick mit nächstem Schritt; ausführliche Antworten und Lernziele als Details.
- Navy, Cyan und Violett mit dezenten Raster-/Schaltkreisakzenten; helle, ruhige Lernflächen. Kürzere Texte und Navigation für kleine Touchscreens. Technische API-/Providerhinweise aus dem normalen Ablauf entfernt. Tatsächliche Demos bleiben klar als Beispiele markiert.
- Android startet direkt beim Login oder im eigenen Lernraum. Echte FlutterActivity mit Dart-Oberfläche, keine WebView-Hülle. APK-Download vor und nach Web-Login; Updateprüfung bei jedem Kaltstart, erneutem Öffnen aus dem Hintergrund und Launcher-Aufruf.
- Admin mit Benutzername/Passwort ohne TOTP. Der ausdrücklich beauftragte Zugang `admin` wurde lokal per stdin eingerichtet; kein öffentliches Standardpasswort. Backendrollen, eintägige widerrufbare Adminsitzungen und Audit bleiben aktiv. Admins haben keinen privaten Kinderinhaltszugriff.
- Einmaliger Installationsassistent für neue leere Installationen: lokal erzeugter Setupcode, Admin, Betrieb, SMTP, KI, Freigaben, Tarifgrenzen und optionales Push. Verschlüsselte Geheimnisse; endgültig geschlossen auch bei parallelem Abschluss. Bestehende Installationen öffnen ihn nicht. [INSTALLATION.md](INSTALLATION.md).
- Migration 0008 erhält Familien, Passworthashes, Antworten und Kindersitzungen, entfernt TOTP-Spalten und widerruft alte Adminsitzungen. Atomarer Provider-Erststart; Projektsicherung vor Aktivierung und nach dem Anhalten der eigenen Dienste. Rückweg über inkompatible Schemagrenzen benötigt geprüfte Datenrücksicherung. [OPERATIONS.md](OPERATIONS.md).
- OpenRouter-Fehler im HTTP 200-Body sowie leere Antworten werden gesondert erkannt. Keine rohen Anbieterfehler oder geheimen Daten ausgeben, keine automatische Wiederholung oder Modellumschaltung.
- Gespeicherte Lernzielzuordnungen beantworteter Anschlussaufgaben bleiben serverseitig verbindlich. Bei vollständig bekannten Zuordnungen gibt die KI nur Aufgaben-ID, Urteil und Rückmeldung zurück. Quellenprüfung, unsichere Bewertungen, neue Aufgaben und feste Fortschrittskriterien bleiben erhalten. [COACHING.md](COACHING.md).

## Ausgeführte Prüfungen

- **152 PostgreSQL-Backendtests bestanden**, zuletzt 97,16s. Einschließlich paralleler Kosten-/Setup-/Startprüfungen, Rollen-/Familientrennung, Migration mit Datenerhalt und bekannten Lernzielzuordnungen. Zusätzlich 33 gezielte SQLite-Tests beim Ausbau sowie 5 abschließende SQLite-Regressionen zur Zuordnung bestanden. Ein vorhandener Starlette/httpx-Hinweis ist eine DeprecationWarning.
- **40 Fluttertests bestanden**, Analyse ohne Befunde. Darunter 320/360/390/430 px, eine nächste Kinderaktion, Hilfe ohne Text, unleserliche Fotos, einzelne Unsicherheiten, ein Paketstart, ausdrückliches Weiter, offene KI-Bewertungen, Verbindungswiederkehr und Archivwechsel.
- Release-Builds für Web, signierte Direct-APK und signiertes Play-AAB erfolgreich. Signatur, zipalign mit 16 KB, sämtliche 8 nativen ELF-Bibliotheken und AAB-Validierung geprüft. Play-AAB ohne APK-Installerberechtigung.
- Öffentlicher Browser bei 390 px: alle 4 Aufgabenkomponenten, Materialbestätigung, eigenständiger Kinderlogin, gespeicherte Antworten/Hinweise im Elternverlauf und mobile Startseite. Ausschließlich feste Beispiele, 0 externe KI-Aufrufe, keine Browserlaufzeitfehler; eigene Demo gelöscht.
- Echte Gmail-Zustellung: Registrierung, Einladung mit eingeschränkten Rechten und Entzug sowie Passwortwiederherstellung mit Sitzungswiderruf. Bestätigungs-/Einladungs-/Resetlinks befüllen die Flutter-Formulare auch nach Neuladen. Eigene Testkonten gelöscht.
- Öffentlicher Adminlogin ohne TOTP, sichere Sitzung, geschlossenes Setup 409, verschlüsselte Geheimnisse nicht in API-Antworten, Logout 401. Isolierter Erstaufruf-Wizard vollständig bis Adminlogin/Einstellungen/Logout geprüft; tatsächliche begrenzte Bild-/Aufgaben-/Paketprobe beim Gratisanbieter erfolgreich, jeweils gemeldete Kosten 0. SMTP-Test wurde tatsächlich angenommen.
- Installierte APK im eigenen Android-API-36-Emulator: Eltern-/Kinderlogin, sichere Wiederaufnahme nach Prozessende, Hinweis und gespeicherte Antwort, Rückmeldung vor Folgefrage, elterlicher Sitzungsentzug und Löschung der eigenen Demo geprüft.
- **Echtes Update 10→11** über automatischen Download und Androids Installationsbestätigung; kein adb-install im Upgrade. Anschließend 3 tatsächliche Manifestprüfungen bei Kaltstart, Hintergrund-Rückkehr und erneutem Launcher-Aufruf; kein Downgrade.
- Nativer Android-Systempicker: zwei künstliche Bilder ausgewählt, beide Zuschnitte bestätigt, zwei verschiedene private Materialien gespeichert, unnötige Bildmetadaten entfernt. Keine OCR-/KI-Anfrage durch diesen Fototest.
- APK im echten Browser vor und nach Login heruntergeladen; Bytes/Größe/SHA256 stimmen mit `/api/app-release` überein. HTTPS-Zertifikat von Let's Encrypt, HTTP 308, Direktlinks und private API-Sperren geprüft.
- Verschlüsselte Sicherung, isolierte Wiederherstellung mit Schema 0008 und authentifiziertem Löschjournal geprüft: zuerst vier Bilder/vier Antworten und abschließend zwei Bilder/sechs Antworten sowie drei KI-Rückblicke der entfernten eigenen Testhaushalte wurden aus den wiederhergestellten Kopien entfernt; Produktion nie überschrieben. Beide regulären Haushalte, weitere eigene Mail-/Demo-Testkonten und temporäre Geräte-/Setupzugänge bereinigt. Offsite-Pull, unabhängige HTTPS-Prüfung und Servermonitor ohne Fehler. Andere DorfSpy-Dienste bleiben aktiv.

**Abschließender regulärer KI-Durchlauf bestanden:** echte Gmail-Verifikation und eigenständiger Kinderlogin, zwei künstliche Fotos mit Zuschnitt/OCR/Bestätigung, echtes Paket, drei Lernrunden mit sechs gespeicherten Antworten und drei KI-Rückblicken. Nachlernen → neue selbstständige Prüfrunde → späterer Wiederholungstermin; keine sichere Beherrschung nach einem Tag behauptet. Sieben tatsächliche Gratisaufrufe einschließlich einer ausdrücklichen Coach-Wiederholung, gemeldete Kosten 0, keine unbekannten Kosten. Paketwiederaufnahme ohne zusätzliche KI; Eltern sehen alle gespeicherten Antworten, Hilfen und Rückblicke. Keine Browserfehler. Native APK-Wiederaufnahme bestanden: eigener Kinderlogin, beide Heftseiten, gespeicherter KI-Rückblick und Einzelrückmeldungen auch nach Prozessneustart; dabei 0 zusätzliche KI-Aufrufe und kein adb-install über die zuvor automatisch aktualisierte APK.

Der erste reguläre Versuch benötigte nach zwei unverwertbaren Paketantworten einen getrennten Diagnoseversuch und durchlief zwei Lernrunden. Seine acht Aufrufe enthielten zwei unbekannte Kosten; diese wurden nicht als 0 ausgegeben. Die erneute KI-Zielzuordnung blockierte die zweite Lernbegleitung. Der Fehler wurde korrigiert und mit Regressionen sowie dem frischen vollständigen Durchlauf geprüft. Der erste Haushalt wurde gelöscht und der Löschabgleich aus einer Sicherung nachgewiesen; keine nachträglich erfundenen Lernergebnisse.

## Lernverhalten und Grenzen

Rollen-/Familientrennung, Elternplanung, private Materialien, vier feste Aufgabenkomponenten und gespeicherte Hilfen/Antworten bleiben erhalten. Lernzeit bildet ungefähr die aktive Nutzung ab. KI-Nachlernen und neue Abrufaufgaben beachten Lernzeiten, Pausen und höchstens drei Tagesrunden. Sichere Beobachtung setzt je Ziel mindestens drei selbstständige Prüftage über sieben Tage voraus; ein einzelner Erfolg oder fehlende Nutzung ist keine Beherrschungsdiagnose.

OpenRouter Free ist ausdrücklich freigegeben und Standard. Modell und Upstream bleiben fest ausgewählt, Preisgrenze 0 und Datensammlung gesperrt. Die angekündigte Preview endet am 31.12.2026; spätere Modellmigration ausdrücklich prüfen. Gratisanbieter können ausfallen oder unbrauchbare Antworten liefern. Gespeicherte Antworten bleiben erhalten; keine unbegrenzten Versuche, erfundenen Ersatzaufgaben oder heimlichen Providerwechsel. [AI_STANDARD.md](AI_STANDARD.md).

Firebase/Play-Zugänge, Betreiberangaben und physische Gerätetests wurden nach Nutzeranweisung für diesen Ausbau zurückgestellt. Echte Push-Zustellung und Play-Veröffentlichung bleiben ohne Projektzugang unbestätigt. Der konkrete Firebase-Einrichtungsauftrag liegt lokal unter `/home/dennis/firebase.txt`. Zahlungscheckout und experimenteller Codex-Lernworker sind nicht aktiviert.

GitHub-Push auf main funktioniert. GitHub Actions startet wegen einer Abrechnungssperre keine Jobs; keine erfolgreiche CI-Ausführung behauptet. Tatsächlicher aktivierter Quellstand über `/api/health`.

## Artefakte

- APK: `artifacts/schulpilot-0.1.0-test.apk`, Version 0.1.0+11, 61.077.524 Bytes.
- SHA256: `44ea84d9c2f16ab829c2f9a878e4981867329ff25ef11d62839fab9f8b144200`.
- Play-AAB: `artifacts/schulpilot-0.1.0-upload.aab`, 58.533.770 Bytes. Signierschlüssel außerhalb des Repositorys; keine Play-Veröffentlichung.
- Öffentlicher APK-Download: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk .
