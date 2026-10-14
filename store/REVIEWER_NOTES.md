# Interne Play-Abnahme

Paket `de.dorfspy.schulpilot`. Eigener Eltern-/Kinderlogin, kein Google-Login. Test-APK öffentlich vor/nach Login herunterladbar; AAB ausschließlich für berechtigte Console-Uploads. Kein Checkout und keine externen Kaufaufforderungen im Android-Client.

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
| Optionales FCM-Gerätetoken | Freiwillige Push-Zustellung; verschlüsselt, sitzungsgebunden, neutraler Nachrichtentext |
| Betriebs-/Verbrauchsmetadaten | Sicherheit, Kontingente und Kosten; keine vollständigen Fotos oder Antworten in technischen Logs |

Zielalter/Families, Inhaltsbewertung, Datenweitergabe an konkrete Dienstleister, Löschung und erforderliche Angaben zu KI-Inhalten in der Console korrekt beantworten. Fehlende echte Geräte-/Firebase-Zustelltests oder Google-Prüfungen nicht als bestanden markieren.
