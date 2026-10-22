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
Zustellnachweise der signierten neuen APK und des Webclients werden gesondert
ergänzt; aus diesen lokalen Proben wird noch keine Zustellung abgeleitet.

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
