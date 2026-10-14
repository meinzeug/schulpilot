# Projektstand · 14.10.2026 · Ausbau auf 0.1.0+11

Die laufende Arbeitseinheit vereinfacht den Kinderbereich und modernisiert Web sowie die native Flutter-APK. Die öffentliche Abnahme der neuen Version läuft; der zuvor geprüfte öffentliche Stand war 0.1.0+10. Konkrete Ergebnisse werden nach der Bereitstellung ergänzt.

## In dieser Arbeitseinheit umgesetzt

- Kinderstartseite mit genau einer nächsten Hauptaktion. Lernplan, Fotos, Nachrichten und Wiederholungen erst auf Wunsch öffnen; Elternhilfe ohne Pflichttext.
- Einfacher Fotoassistent: Fotos sammeln → Weiter startet die Erkennung → je eine Seite mit echten Unsicherheiten bestätigen → Jetzt lernen erstellt und öffnet die erste Einheit. Fotoverwaltung und Zuschnittregler optional; keine automatische Bestätigung oder versteckte KI-Wiederholung.
- Eine Aufgabe pro Ansicht mit großen Bedienelementen. Nach der Antwort bleiben Rückmeldung und Erklärung bis zum ausdrücklichen Weiter sichtbar. KI-Rückblick mit einem nächsten Schritt; Antworten und Lernstand als Details.
- Dezenter Cyberpunk-Stil mit Navy, Cyan und Violett; ruhige Leseflächen. Kürzere Texte, keine Provider-/API-Erklärungen im normalen Lernablauf. Die missverständliche pauschale Demo-Aussage auf der Startseite ist entfernt. Tatsächliche Demo-Lernräume bleiben ausdrücklich als Beispiele markiert.
- Android startet direkt beim Login beziehungsweise im eigenen Lernraum. Native FlutterActivity mit Dart-Oberfläche, keine WebView-Hülle. Download vor und nach Web-Login erhalten; Updater weiterhin bei jedem Start, Hintergrund-Rückkehr und Launcher-Aufruf.
- Admin-Anmeldung ausschließlich mit Benutzername und Passwort, kein TOTP. Sichere lokale Erstellung/Rücksetzung; keine öffentlichen Administratorrechte. Migration 0008 erhält Kinderkonten, Antworten und deren Sitzungen, widerruft alte Adminsitzungen und entfernt TOTP-Felder.
- Einmaliger Installationsassistent für neue Installationen, durch lokalen zufälligen Setupcode geschützt. Admin, SMTP, KI, Freigaben, Tarifvorgaben und optionale Push-Konfiguration; Geheimnisse verschlüsselt, nicht zurückgegeben. Bestehende Installationen bleiben geschlossen. [INSTALLATION.md](INSTALLATION.md).
- Gleichzeitiger Erststart von API und Worker legt die Providerkonfiguration atomar genau einmal an. Deployment sichert vorher und stoppt Projektdienste vor Migration. Nach geändertem Schema kein automatischer Rücksprung auf inkompatiblen Altcode. [OPERATIONS.md](OPERATIONS.md).

## Bisher ausgeführte Prüfungen dieser Arbeitseinheit

- Vollständige Flutter-Analyse ohne Befunde; **40 Flutter-Tests bestanden**, einschließlich 320/360/390/430px, einfacher Kinderstart, Hilfe ohne Text, alle Unsicherheiten bestätigen, Paket mit einem Start, Rückmeldung vor Folgefrage, unsichere KI-Bewertungen, Verbindungswiederkehr und Wechsel vom Archiv zum heutigen Tag.
- **141 PostgreSQL-Tests** bestanden, einschließlich gleichzeitigem Erststart. Zusätzlich **33 gezielte SQLite-Tests** bei der Backend-Erweiterung bestanden. Ein vorhandener Starlette/httpx-Hinweis ist eine DeprecationWarning.
- Frühere öffentliche Version10: reguläre Elternregistrierung mit tatsächlicher Bestätigungsmail, eigener Kinderlogin, echte KI-Lernpakete aus zwei künstlichen Fotos, sechs Antworten und drei gespeicherte KI-Rückblicke geprüft. Keine Aussage, dass diese früheren Prüfungen bereits die neue Kinderoberfläche abnehmen.
- Signierte Release-Builds für Web, Direct-APK und Play-AAB erfolgreich. APK11: 61.077.524 Bytes, SHA-256 `44ea84d9c2f16ab829c2f9a878e4981867329ff25ef11d62839fab9f8b144200`. APK-Signatur, 16-KB-Ausrichtung aller acht nativen Bibliotheken und AAB-Validierung geprüft; Play-AAB ohne APK-Installerberechtigung. Die öffentliche Browser-/Androidabnahme läuft; bereitgestellter Commit und Bereinigung werden nach Abschluss eingetragen.

## Fortbestehende Lernfunktionen

Rollen-/Familientrennung, Elternplanung, private Materialien, vier feste Aufgabenkomponenten, gespeicherte Hilfen/Antworten und ungefähre aktive Lernzeit; KI-Lernbegleitung mit begrenztem Nachlernen, neuen Abrufaufgaben und Wiederholungen. Ein einzelner Erfolg bedeutet keine sichere Beherrschung; je Ziel mindestens drei selbstständige Prüftage über sieben Tage. Kontingente und Kosten werden atomar reserviert; unbekannte Kosten bleiben unbekannt. [COACHING.md](COACHING.md).

OpenRouter Free ist ausdrücklich freigegeben und Standard; Modell/Upstream fest ausgewählt, Preisgrenze 0, Datensammlung gesperrt. Keine stillen Modellwechsel. Die derzeitige Preview ist bis 31.12.2026 angekündigt und muss vor ihrem Ende ausdrücklich neu ausgewählt/geprüft werden. [AI_STANDARD.md](AI_STANDARD.md).

## Zusätzliche externe Arbeiten

Firebase/Play, vollständige Betreiberangaben und physische Gerätetests sind nach Nutzeranweisung aktuell keine Voraussetzung für den UI-/Funktionsausbau. Tatsächliche Push-Zustellung und Play-Veröffentlichung bleiben ohne Projektzugang unbestätigt. Ein konkreter Firebase-Einrichtungsauftrag liegt lokal in `/home/dennis/firebase.txt`; keine Schlüssel im Repository. Zahlungscheckout und Codex-Lernworker bleiben außerhalb des aktivierten Funktionsumfangs.

GitHub-Push nach main funktioniert. GitHub Actions startet aufgrund einer Abrechnungssperre keine Jobs; lokale und separate PostgreSQL-Prüfungen ersetzen keine behauptete erfolgreiche CI-Ausführung.

APK: `artifacts/schulpilot-0.1.0-test.apk`, AAB: `artifacts/schulpilot-0.1.0-upload.aab`; beide nicht in Git. Öffentliche Adresse: https://schulpilot.dorfspy.de . Sicherer Admin-/Einrichtungsablauf in [INSTALLATION.md](INSTALLATION.md).
