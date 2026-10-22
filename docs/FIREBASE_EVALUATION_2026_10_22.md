# Firebase, Web und Android · Prüfung vom 22.10.2026

## Bestand vor der Korrektur

Die Firebase-Konsole wurde mit dem ausdrücklich genannten Konto geöffnet.
Das bestehende Projekt `schulpilot-f6bf3` enthält die dokumentierte Web-App
und Android-App für `de.dorfspy.schulpilot`. Cloud Messaging HTTP v1,
FCM Registration und Firebase Installations sind aktiviert. Das vorhandene
Web-Push-Schlüsselpaar stimmt mit der geschützten lokalen und serverseitigen
Konfiguration überein. Keine weiteren Apps, Projekte oder Schlüssel angelegt.

Die vorhandene isolierte Google-CLI-Anmeldung bestätigt zusätzlich die
Projekt-/App-IDs, getrennte Plattformkeys, API-Zustände und genau die minimale
Senderrolle mit `cloudmessaging.messages.create`. Die Plattformkeys haben
leere Anwendungsbeschränkungen und die bestehende Firebase-API-Allowlist;
diese Konfiguration ist kein nachgewiesener Zustellfehler. Eine ungetestete
Domainbeschränkung würde mit der bestehenden `no-referrer`-Policy kollidieren.
Eine alleinige Direct-Signiererbeschränkung würde einen anders signierten
Play-Client ausschließen. Es wurden keine Schutzregeln stillschweigend gelockert.

Serverseitig wurden ausschließlich redigierte Betriebsmetadaten gelesen:
Laufzeitkonfiguration und Projekt stimmen, Dienstkontodatei mit Modus 0640
für den Dienst lesbar, Dienstkonto-OAuth und Versandberechtigung erfolgreich,
Produktionsfreigabe vorhanden, Worker aktiv. Zum Prüfzeitpunkt gab es **null
registrierte Pushgeräte**, keine wartenden Sendungen und keine Zustellbelege
der letzten sieben Tage. Das erklärt die fehlende aktuelle Zieladresse;
es beweist weder eine frühere Registrierung noch die Geräteeinstellungen
des physischen Smartphones. In-App-Neuigkeiten benötigen keine Pushfreigabe.

## Nachgewiesene Codeprobleme

### Android-Broadcast

Der eigene `FamilyCallMessagingReceiver` hatte für normale Meldungen eine neue
`FlutterFirebaseMessagingReceiver`-Instanz erzeugt und deren `onReceive` direkt
aufgerufen. Das fixierte Messaging 16.7.0 verwendet `goAsync()` und anschließend
`PendingResult.finish()`. Nur die tatsächlich vom Android-Framework zugestellte
Receiverinstanz besitzt diesen PendingResult. Die neue Instanz konnte die
Broadcast-Lebensdauer und Abschlussverarbeitung nicht übernehmen.

Der eigene Receiver erbt jetzt vom FlutterFire-Receiver und delegiert normale
Meldungen mit `super.onReceive`. Der gesondert gebundene Familienanrufzweig und
die festen neutralen Meldungsinhalte bleiben erhalten. Keine statischen
Firebase-Schlüssel oder zusätzliche Firebase-Dienste eingebaut.

### Web und Kontowechsel

Das tatsächlich fixierte `firebase_messaging_web 4.2.5` liefert für
`onTokenRefresh` einen leeren Stream. Eine bereits freigegebene Websitzung
benötigt deshalb beim Wiederaufnehmen einen gezielten Tokenabgleich.
`PushClient.refreshRegistration` prüft nur bestehende Freigaben, begrenzt
Abgleiche und speichert nur einen geänderten Token. Kein Permissionprompt,
Providerauftrag oder Hintergrund-Polling. Generation und Kontobindung schützen
vor verspäteten Ergebnissen nach Logout oder Kontowechsel.

Der bisherige Permissionaufruf lag hinter Config- und SDK-Laden. Die dafür
benötigte Browseraktion konnte inzwischen abgelaufen sein. Der neue explizite
Bestätigungsbutton ruft die Browserfreigabe unmittelbar aus seinem Klickhandler
auf. Abbruch ist kein erfolgreicher Opt-in. Eine ausbleibende Browserantwort
darf die Oberfläche nicht unbegrenzt blockieren.

Ein unabhängiges Review hat zusätzlich verspätetes Ausschalten,
überlappende Tokenwechsel, Abo-Wechsel und Fehlercleanup bei Kontowechsel
geprüft. SDK-Mutationen bleiben geordnet, auch wenn eine Plattformantwort erst
nach dem sichtbaren Timeout eintrifft. Serielles Speichern übernimmt aus
wartenden Tokenwechseln nur den jüngsten. Eine alte Ausschaltaktion darf keine
neuere Registrierung löschen. Alle 20 gezielten Clientfälle und die gesamte
Suite mit 1.155 Fluttertests bestanden.

## Nachweistrennung

Cloudkonfiguration, Dienstkonto-OAuth, `validate_only`, FCM-Annahme und tatsächlich
sichtbare Geräteanzeige sind verschiedene Nachweise. Die Abnahme verwendet
einen einzigen neu angelegten künstlichen Haushalt, zeitlich begrenzte
Testfreigaben und getrennte Eltern-Web-/Kinder-Android-Sitzungen. Keine echten
Kinderinhalte, KI-Aufträge oder Testmeldungen an fremde Geräte.

Für die Android-Kaltprozessprobe gilt: App normal in den Hintergrund bringen,
den Hintergrundprozess beenden und das Fehlen des Prozesses vor Versand
nachweisen. `force-stop` vor Versand wäre kein gültiger Vergleich, weil Android
dadurch FCM bis zum erneuten Öffnen sperrt. FCM-Annahme allein ist kein
Anzeigeerfolg.

Bereits vor dem Release mit der unveränderten signierten 83-APK tatsächlich
reproduziert: Kind normal angemeldet und nach ausdrücklichem Opt-in registriert;
Activity STOPPED und Prozess vor Versand nachweislich nicht vorhanden. Genau
eine normale eigene Testmeldung reserviert und von FCM angenommen. Anschließend
`PendingResult.finish()`-NullPointer, Prozessabsturz und **keine sichtbare
Benachrichtigung**. Dies belegt den Androidfehler unabhängig von den korrekten
Google-/Servereinstellungen.

Die korrigierte Logik besteht die echte lokale Frameworkprobe: geordneter
Android-Broadcast, neutrale Nachricht vor Receiverabschluss gespeichert,
Route/Titel geprüft und Prozess bleibt am Leben. Sechs vorhandene native
Regelfälle und 22 Backend-Push-/Inbox-/Freigabefälle bestanden. Echte
Zustellnachweise der signierten neuen APK und des Webclients folgen unten;
sie sind von diesen lokalen Proben getrennt.

## Tatsächliche Abnahme der Version 1.19.5+84

| Fall | Beobachtetes Ergebnis |
| --- | --- |
| Signierte APK84, Android API36, Activity gestoppt und Prozess vor Versand nicht vorhanden | Genau eine Testmeldung von FCM angenommen, echte Androidmeldung sichtbar; Tipp öffnet dieselbe geschützte Kindersitzung. Kein erneuter PendingResult-Absturz. |
| Dieselbe APK84, App beim Empfang RESUMED | Eine weitere Nachricht von FCM angenommen; In-App-Hinweis und native Meldung sichtbar. Echte Android-Leiste separat aufgenommen. |
| Web, eigenes reguläres Chrome-Profil nach ausdrücklicher Betreiberfreigabe | Null Firebaseanfragen vor App-Opt-in; FIS-/Registrierungs-HTTP200, aktuelle Sitzung gebunden und eigener `/push/`-Worker registriert. |
| Web, Validierung und Vordergrund | Eine Validierung erfolgreich; eine Testmeldung von FCM angenommen und der tatsächliche In-App-Banner sichtbar. |
| Web ohne geöffnetes Schulpilot-Dokument (`about:blank`) | Eine zweite Meldung angenommen; echter Worker registriert eine `Notification` mit exakt dem neutralen Titel und Inhalt. Kein sichtbarer Desktop-OS-Banner behauptet. |
| Web-Rückkehr und Abmeldung | Bestehende Gerätefreigabe wiederhergestellt; Logout401 und Entfernung der exakten alten Registrierung bestätigt. Chromeprofil danach entfernt. |
| Integrierter Browser mit ausbleibender Permissionantwort | Neuer ausdrücklicher Bestätigungsdialog tatsächlich bedient; Timeout-Hinweis erscheint und Einschaltbutton wieder nutzbar. Keine Registrierung oder Testsendung. |

Das isolierte Chrome-Profil hatte seine Browserberechtigung vorab erteilt.
Die ausdrückliche **App**-Freigabe und null Firebaseverkehr davor wurden trotzdem
geprüft; daraus wird keine beobachtete native Browser-Permissionbestätigung
abgeleitet. Den neuen Bestätigungsdialog und den begrenzten Fehlerfall hat der
integrierte Browser getrennt nachgewiesen.

Die alten Testhelfer hatten noch veraltete Flutter-/Kontonavigation. Der erste
84-Locatorlauf und der erste Chrome-Locatorlauf endeten vor Registrierung bzw.
Versand und meldeten normal ab; negative Berichte bleiben erhalten. Die
Android-Vordergrundstufe wurde im selben begrenzten Lauf sichtbar zur Pushseite
geführt. Screenshotpause und Navigation erzeugten keine weitere Nachricht.
Die permanenten Helfer verwenden jetzt den direkten Glockenweg und aktivieren
die Flutter-Semantik korrekt. Kein Produktfix aus einem bloßen Locatorfehler
abgeleitet.

Insgesamt genau fünf tatsächliche Meldungen: eine negative 83-Probe, zwei
positive 84-Androidproben und zwei Webproben. Zusätzlich eine `validate_only`-
Anfrage. Keine automatischen Sendwiederholungen oder KI-Aufträge. Android nach
normalem Logout: Auto-Init aus, Registrierung/Meldungen entfernt, Anrufbindung,
Klingeln und Capture aus; eigener Emulator beendet. Physisches Smartphone,
hörbarer Ton und Desktop-OS-Banner sind damit nicht abgenommen.

Der neue künstliche Haushalt wurde abschließend über den normalen
authentifizierten Kontolöschweg entfernt. Alte Sitzung und beide Logins sind
ungültig; alle 15 gezielten Kaskadenzähler einschließlich Sitzungen,
Testfreigaben, Pushgeräten und Zustellungen stehen auf null. Lösch-Audit und
publiziertes Löschjournal bestätigt; lokale Zugangsdaten und privater
IDs-Checkpoint nach dieser Bestätigung entfernt. Echte Haushalte unverändert.

## Release und Rückweg

Live `20261022T065736Z-1647c03`, Produktcommit
`1647c03533a0f493edab66b941499a1a34aa5b11`. Web, signierte Direct-APK und
Play-AAB mit fixierter Toolchain gebaut und geprüft. Vollständiger öffentlicher
APK-Download identisch: 111776935 Bytes, SHA256
`46c69e8e3b77ab98920dcc9826d8ea57071ccb047000e355c36ed930e8e47da9`.
AAB 89009534 Bytes, SHA256
`bde6cc79060e74b11243ee5461e5ab5c867829926e2be4c17f0e422032bb0ce1`;
bundletool, Signierer und fehlende APK-Installerberechtigung im Play-Artefakt
geprüft. Kein Play-Upload daraus abgeleitet.

1.155 Fluttertests, volle Flutteranalyse, 22 PostgreSQL-Push-/Inboxfälle,
sechs native Regelfälle, echte Frameworkprobe und sechs lokale QA-Guardfälle
bestanden. Die gehosteten Jobs des
[GitHub-Laufs 39724081470](https://github.com/meinzeug/schulpilot/actions/runs/39724081470)
starteten wegen der bestehenden Abrechnungssperre keine Schritte; sie sind
kein bestandener CI-Nachweis.

Konfigurationssicherung und vorgeschaltete Datensicherung erfolgreich,
Caddy validiert; API, Worker, Caddy und projektspezifischer TURN-Dienst aktiv.
Schema `0026` und Providerrevision `29` unverändert. Rückweg für Web/API:
`20261022T052536Z-e502960`, siehe [OPERATIONS.md](OPERATIONS.md). Keine
Datenbankrücksetzung; eine native Folgekorrektur benötigt eine höhere
Android-Versionsnummer. Nachfolgende reine QA-/Abnahmekorrekturen ändern den
hier genannten bereitgestellten Produktcode nicht.

## Eigenes Gerät einschalten

Nach Installation des aktuellen Updates: Glocke → Alle anzeigen → Gerät
einstellen → Auf diesem Gerät einschalten. Androids Berechtigung erlauben;
die Kategorie „Lernen & Familie“ muss aktiv sein. Familienanrufe haben eine
eigene freiwillige Freigabe und einen eigenen Kanal. Im Kinderkonto ist
zusätzlich die Elternfreigabe erforderlich. Jedes Gerät und jeder Browser
benötigen eine eigene Registrierung. Abmelden widerruft sie absichtlich.

Ruhezeiten, Android-Lautlos/Nicht-stören und ein ausdrücklich vom Nutzer
gestoppter Client werden nicht umgangen. Normale Lernmeldungen sind über den
bestehenden ruhigen Kanal sichtbar; nur der gesonderte Anrufkanal klingelt.
