# Schulpilot: Produktionsprüfung vom 14.10.2026

Schulpilot ist öffentlich erreichbar. Diese Arbeitseinheit behebt konkrete Fehler und bereitet die Veröffentlichung vor. Die Änderungen sind noch nicht auf der öffentlichen Installation aktiviert; Google-Play-Veröffentlichung und echte Push-Zustellung sind weiterhin offen. Bestehende frühere Abnahmen in STATUS.md gehören zum dort dokumentierten Quellstand und ersetzen keine Abnahme dieses Kandidaten.

## Öffentlich geprüft

| Ablauf | Tatsächliche Beobachtung |
|---|---|
| Startseite | Lädt; Registrierung, Anmeldung, Demo, APK und Datenschutzhinweise sind erreichbar. |
| Demo-Elternkonto | Familienübersicht, Beispielkind und korrekt als unbekannt gekennzeichneter Lernstand sichtbar. |
| Eltern-Lernüberblick | Überblick und Plan/Vorgaben laden; Tages-/Wochenziele und Auftragsaktionen sichtbar. |
| Demo-Kinderwechsel | Klick führt auf der laufenden Installation zur Loginseite. Im Quellcode wird der alte Seitenkontext nach dem Logout verworfen. |
| Barrierefreie Struktur | Flutter bietet Aktivierung der Semantik an; danach sind Bedienelemente zugänglich. Dies allein wurde nicht als Fehler gewertet. |
| Browserkonsole | CPU-Rendering-Fallback im Cloud-Browser; kein daraus abgeleiteter allgemeiner Ausfall oder Leistungswert. Erweiterungsfehler nicht Schulpilot zugeschrieben. |
| Öffentliche APK | Release-Endpunkt bestätigt Verfügbarkeit und Versionscode 11. Kein neuer Android-Build aus dieser Arbeitseinheit. |
| Betreiberangaben | /api/legal: Betreibername, Anschrift und Support-E-Mail leer, complete=false. |

Registrierung mit realer E-Mail, eigene echte Eltern-/Kinderkonten, regulärer Fotoimport/OCR und echte KI-Lernrunden wurden in dieser Sitzung nicht vollständig neu durchlaufen. Gesicherte lokale Tests und früher dokumentierte Abnahmen werden nicht als neue Browserprüfung ausgegeben. Der synthetische Demoraum läuft laut bestehendem System nach 24 Stunden ab.

## Korrekturen im Quellcode

| Priorität | Befund | Korrektur / Nachweis |
|---|---|---|
| P1 | Demo-Wechsel verliert Navigation nach Logout | Dauerhaften GoRouter vor Logout erfassen; Test erzwingt langsame Kinderanmeldung und Seitenentsorgung. |
| P1 | Play-Release kann bei vergessenem Umgebungsflag einen Debugschlüssel verwenden | Play-Release ohne vollständige externe Upload-Signierung verweigert; tatsächliche Gradle-/Signierabnahme noch offen. |
| P1 | Push-Prüfung erfolgt vor längerer OAuth-Anmeldung | Unmittelbar nach Token-Refresh erneut Sitzung, Familienrechte, Gerät, Token, Opt-in, Ruhezeiten und Firebase-Projekt prüfen. Widerrufene Zustellung unterdrücken. |
| P1 | Produktionsstart akzeptiert beliebige vorhandene Migrationstabelle | PostgreSQL und exakte effektive Alembic-Heads des Releases vor Initialisierung verlangen; Entwicklung/Test unverändert. |
| P2 | Fehlgeformte Firebase-Konfiguration kann einen Serverfehler auslösen | Nicht-Objekt-JSON sauber als nicht verfügbare Push-Konfiguration behandeln. |
| P2 | Login per Enter/Fertig fehlt; Fehlermeldung wird nicht zuverlässig angekündigt | Gemeinsame, gegen Doppelanfragen geschützte Anmeldung; dynamische Hinweise als Live-Region. |
| P2 | Releaseprüfung verwechselt Dateipräsenz mit validiertem Bundle | Gewähltes AAB, echtes Manifest, Signatur, Debugmodus, Paket/API/Version und getrennte ZIP-/ELF-Ausrichtung prüfen; Blocker sammeln. |

## Ausgeführte Prüfung dieses Kandidaten

- Backend: 178 Tests bestanden, isolierte SQLite-Datenbank mit künstlichen Daten. Neue Produktions-Guards zusätzlich mit simuliertem PostgreSQL-Dialektnamen geprüft; keine echte PostgreSQL-Produktionsverbindung.
- Flutter: 43 Tests bestanden, einschließlich der neuen Login-/Semantik-/Demo-Wechsel-Regressionen und bestehender mobiler Abläufe.
- Python-Releaseprüfung: 20 Tests bestanden. Ruff und Diff-Prüfung sauber.
- Flutter-Analyse: abschließend ohne Befund. Web-Release-Build mit CSP, ohne externe Web-Ressourcen-CDN und expliziter öffentlicher API erfolgreich (116,1 s Compilerzeit). Der Build wurde nicht auf dem Server aktiviert.
- Keine echte Firebase-Zustellung, kein neuer signierter Android-Build, keine Google-Play-Freigabe.

Der ursprüngliche Flutter-Aufruf wurde durch die automatische Sicherheitsprüfung wegen unnötiger Azure-Metadatenerkennung blockiert. Die SDK-Quelle wurde geprüft; das offizielle CI-Signal verhindert diesen Zugriff. Abhängigkeiten, Analyse und Tests wurden anschließend in dieser sicheren Konfiguration ausgeführt.

## Bestätigter Firebase-/Google-Bestand

Projekt schulpilot-f6bf3, Nummer 460657028995. Android de.dorfspy.schulpilot und Web-App vorhanden. FCM HTTP v1 aktiviert; Web-VAPID-Schlüsselpaar vorhanden. Die aktuelle Firebase-Sitzung weicht vom gewünschten Eigentümerkonto ab; dessen Zugriff ist noch nicht bestätigt. Persönliche Kontoadressen werden hier nicht veröffentlicht. Unter dem angemeldeten Konto zeigt Play Console die Entwicklerkonto-Erstellung. Ein Kontowechsel wurde ausgelöst und endete in einem Browser-Timeout; danach zeigt der vorhandene Tab Googles Anmeldung.

Firebase bleibt auf freiwilliges Push beschränkt. Keine zusätzliche Einrichtung von Firebase Auth, Firestore, Analytics, Hosting, Werbung oder Crashlytics. Ein vorhandenes Projekt ist kein Nachweis, dass das laufende eigene Backend gültige Senderzugangsdaten besitzt. In dieser Sitzung wurden weder Dienstkonto noch privater Schlüssel erzeugt und keine neuen IAM-Rechte vergeben.

## Tatsächliche Blocker und nächster Ablauf

1. Google-Anmeldung mit dem vorgesehenen Eigentümerkonto sicher abschließen und dessen bestehendes Play-Konto prüfen. Falls keines besteht, Kontotyp/Identitätsprüfung/Vereinbarung und Registrierung mit tatsächlichen Angaben durchlaufen. Keine fremde oder erfundene Organisation eintragen.
2. Tatsächliche Betreiberangaben für Website und Store hinterlegen. Name, ladungsfähige Anschrift und Supportadresse fehlen derzeit vollständig.
3. Bestehenden SSH-/Build-Zugang verwenden: der hier geklonte Quellcode ist verfügbar, aber kein SSH-Alias dorfspy, keine Server-Schlüssel, kein Android-SDK und kein bestehender Upload-Keystore. Keine Ersatzschlüssel erzeugen, solange die vorhandene Signieridentität fehlt.
4. Geprüften Kandidaten auf dem bestehenden Build-Rechner auschecken. Vor Signierung die nächste Android-Buildnummer größer als den öffentlichen Code 11 wählen, beispielsweise 12. Vorhandenen externen Upload-Schlüssel erhalten. Direct-APK und Play-AAB getrennt bauen.
5. Tatsächliches AAB mit scripts/google_readiness.py --aab ... --bundletool ... --strict sowie Android-Signatur-/16-KB-Gerätetests prüfen. Die neue Play-Signierregel auch ohne Store-Flag auf korrektes Scheitern ohne Schlüssel prüfen.
6. FCM-Dienstkonto mit minimalem Senderecht konkret vorbereiten, Rechte-/Schlüsselerzeugung ausdrücklich bestätigen und ausschließlich im geschützten Backend ablegen. Öffentliche Appkennungen sind hiervon getrennt. Geräte-Opt-in, Vorder-/Hintergrund, Neustart, Abmeldung und Widerruf mit neutralen Nachrichten tatsächlich testen.
7. Deployment über den vorhandenen gesicherten Release-/Rückweg ausführen. Danach den öffentlich reproduzierten Demo-Wechsel, regulären Eltern-/Kinderlogin und den Foto-/Lernablauf erneut im Browser abnehmen.
8. Play-Listing, tatsächliche Zielgruppen-/Data-Safety-/Review-Angaben und echten Testzugang vorbereiten. Bei betroffenem neuen persönlichen Entwicklerkonto: mindestens 12 Testpersonen mindestens 14 Tage ununterbrochen im geschlossenen Test, danach Produktionszugang beantragen. Keine erfundene Testteilnahme oder Freigabe.

Aktuelle Google-Vorgaben: Smartphone-Neueinreichungen/Updates benötigen seit 31.08.2026 Ziel-API 36. Die Quellkonfiguration erfüllt dies; maßgeblich bleibt das gebaute Manifest.

Quellen: [Google Ziel-API](https://support.google.com/googleplay/android-developer/answer/11926878), [Google Testanforderung](https://support.google.com/googleplay/android-developer/answer/14151465), [Firebase Senderauthentifizierung](https://firebase.google.com/docs/cloud-messaging/send/v1-api), [Projektquellen](SOURCES.md).
