# Interne Play-Abnahme

Paket `de.dorfspy.schulpilot`. Eigener Eltern-/Kinderlogin, optionaler Google-Elternlogin über eigene API (kein Firebase Authentication). Reguläre signierte APK öffentlich vor/nach Login herunterladbar; AAB ausschließlich für berechtigte Console-Uploads. Kein Checkout und keine externen Kaufaufforderungen im Android-Client.

`de-DE/` enthält vorbereitete Texte, keine bereits veröffentlichte Storebeschreibung. Vor öffentlicher Freigabe den tatsächlichen Funktionsumfang, Betreiberangaben und die aktuelle Testphase prüfen. Vorhandene native Icons verwenden; Screenshots ausschließlich aus dem tatsächlichen Build mit künstlichen Daten erstellen.

## Reviewablauf

1. Synthetischen Testraum auf der Startseite öffnen. Erzeugte Zugangsdaten nur über einen geschützten Console-Reviewkanal weitergeben, niemals hier eintragen. Die kurzlebige Testfamilie läuft nach 24 Stunden ab; für einen konkreten Reviewtermin eine neue bereitstellen.
2. Eltern-/Kinderzugang getrennt prüfen, Heftseiten-Assistent mit den zwei festen Testbildern durchlaufen, Lernpaket erstellen und eine Einheit bearbeiten. Erklärungen, Hinweise, Verlauf und Elternüberblick vergleichen.
3. Tageshistorie/Direktlinks und Wiederaufnahme nach Prozess-Neustart prüfen. Unleserliche, fremde und nicht freigegebene Daten dürfen keine erfundenen Übungen erzeugen.
4. Push ist erst mit dem zugehörigen Firebase-Projekt und Dienstkonto tatsächlich zustellbar. Ohne Konfiguration gibt es eine ausdrückliche Nichtverfügbarkeit; keine Firebase-/Analytics-Initialisierung vor Geräte-Opt-in.
5. Kontolöschung im Web und in der App prüfen. Öffentliche Webressource: https://schulpilot.dorfspy.de/account-deletion .

## Data-Safety-Arbeitsblatt

Dies sind technische Bestandsangaben, keine automatisch ausgefüllte rechtliche Erklärung. In der Console anhand des tatsächlich aktivierten Betriebs prüfen:

| Daten | Zweck / Speicherung |
| --- | --- |
| Eltern-E-Mail und Zugangsdaten | Eigene Authentifizierung, Verifikation, Einladungen, Wiederherstellung; Passwörter ausschließlich als Argon2id-Hash |
| Kinder-Anzeigename, Klasse, gewählte Fächer | Familienzuordnung und Lernbegleitung; keine Kinder-E-Mail erforderlich |
| Private Fotos, bestätigter Stoff, Antworten | Private Lernbegleitung und berechtigter Elternüberblick; bei aktivierter geeigneter KI Weiterleitung über Backend an ausdrücklich konfigurierten Anbieter |
| Aktive Lernereignisse / ungefähre Zeit | Fortschritt, Wiederholung und Elternübersicht; keine Erfassung außerhalb von SCHULPILOT |
| Optionale Google-Kontokennung / bestätigte Eltern-E-Mail | Ausdrücklich gestartete Elternanmeldung und passwortbestätigte Verknüpfung über eigene API; keine Google-Access-/Refresh-Tokens gespeichert |
| Optionales FCM-Gerätetoken | Freiwillige Push-Zustellung; verschlüsselt, sitzungsgebunden, neutraler Nachrichtentext |
| Betriebs-/Verbrauchsmetadaten | Sicherheit, Kontingente und Kosten; keine vollständigen Fotos oder Antworten in technischen Logs |

Zielalter/Families, Inhaltsbewertung, Datenweitergabe an konkrete Dienstleister, Löschung und erforderliche Angaben zu KI-Inhalten in der Console korrekt beantworten. Fehlende echte Geräte-/Firebase-Zustelltests oder Google-Prüfungen nicht als bestanden markieren.

Aktuell tatsächlich geprüft am 14.10.2026: Google-Elternregistrierung und wiederholter Google-Weblogin mit eigenem anschließend gelöschtem künstlichem Haushalt; unabhängiger Kinderlogin und Backend-Rollensperren. Web-FCM-Registrierung/Vordergrundhinweis sowie native Android-Registrierung, Vordergrundhinweis, echte Hintergrundbenachrichtigung und Öffnen ins richtige Kinderkonto beobachtet. Im beobachteten Browser keine Google-/Firebase-Anmeldeanfrage vor bewusstem Start/Opt-in. Die native Firebase-Initialisierung ist ebenfalls im Code an Opt-in gebunden; sonstiger Google-Play-Services-Verkehr des Geräts wurde dadurch nicht als Appverkehr bewertet. Vollständiger Google-Login im Android-Systembrowser mit angemeldetem Google-Konto und eine physische Gerätebeobachtung bleiben gesonderte Tests.

Die Play Console des autorisierten Kontos bietet die erstmalige Entwicklerkonto-Erstellung an; keine vorhandene Entwicklerberechtigung zugänglich. Keine Registrierung mit Gebühren ausgelöst. Storetexte sind vorbereitet, keine behauptete Veröffentlichung. Google-Branding wartet nach bestätigter HTML-Inhaberschaft und lesbarer Datenschutzerklärung auf die spätere Wiederprüfung (Google nennt bis zu 24 Stunden Aktualisierung). Datenzugriffsprüfung für openid/email ist laut Konsole nicht zusätzlich erforderlich. Bei Play App Signing den tatsächlichen von Google verwendeten App-Signing-Fingerprint ergänzen; Upload-Zertifikat allein reicht für den Play-App-Link nicht.
