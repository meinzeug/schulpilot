# Produktionsstand1.28.0+100 ·23.10.2026

Live: https://schulpilot.dorfspy.de
Produktcommit `3fb4cb2bb9cecf28e4b3f935a6713fc1cfb265c7`, Release `20261023T143134Z-3fb4cb2`, main gepusht.

[100 weitere sichtbare Bedien- und Lernverbesserungen](IDEAS_100_2026_10_23.md)
für Aufgaben, Lesen, Plan, Hefte, Sammlungen, Wörter, Noten, Hausaufgaben und
Navigation. Lokale Werkzeuge bewerten keine Antworten und erzeugen keine KI-Aufträge.

Vollständige [CI39952366018](https://github.com/meinzeug/schulpilot/actions/runs/39952366018)
grün:2207Backend-/2851Fluttertests,33/19übersprungen; Ruff, Analyse und Webbuild erfolgreich.
Zusätzlich386Fälle im ursprünglichen24Dateien-Gate,211finaleRegressionsfälle
in14Dateien und65Paging-/Ansichtsfälle; diese Läufe überschneiden sich.

Reguläre signierte Artefakte an den Produktcommit gebunden; öffentliche APK-/JS-
Bytes identisch. Fünf Dienste aktiv, Schema0031,17Konfigurationen und Google-
Nachweis erhalten, verschlüsselte Sicherung erfolgreich. Nachweise und Grenzen:
[RELEASE_100_2026_10_23.md](RELEASE_100_2026_10_23.md).
Die zusätzlich gemeldete Lernrunden-/Materialkorrektur wird getrennt abgenommen.

## Vorheriger Stand99

# Produktionsstand 1.27.0+99 · 23.10.2026

Live: https://schulpilot.dorfspy.de
Produktcommit `76ca7e560c23a3e58f11d1cfe192fe679d6c598d`, Release `20261023T120940Z-76ca7e5`, main gepusht.

[20 neue sichtbare Funktionen](LEARNING_ELEMENTS_20_2026_10_23.md): Mehrfeldaufgaben
mit Text und Auswahl, lesbare Feldrückblicke, Textlupe und belegte Umstellungen,
Vergleich vorhandener Grafikzustände mit Legende sowie Rundenübersicht mit
Filtern. Kleine Displays erhalten eingeklappte Zoomhinweise. Die KI kennt die
neuen Formate über den endgültigen fachgetrennten Schema-Katalog.

Vollständige [CI39935538876](https://github.com/meinzeug/schulpilot/actions/runs/39935538876)
grün: 2207 Backendtests und 2710 Fluttertests bestanden; 33/19 übersprungen. Analyse/Ruff/Webbuild erfolgreich.
Zusätzlich400gezielte SQLite-,180PostgreSQL-,183Flutter- und16Aktivierungsfälle grün.
Mobile/Desktopsichtung mit künstlicher schreibgesperrter Vorschau; keine
erfolgreiche echte KI-Erzeugung der neuen99-Verträge behauptet.

Reguläres Web, signierte Direct-APK und Play-AAB exakt an Produktcommit gebunden.
Öffentliche APK-/JS-Bytes identisch; alle fünf Dienste aktiv, Schema0031,
17Konfigurationsdateien/Google-Nachweis erhalten, verschlüsselte Sicherung grün.
Neue grouped/text_probe-JSONs benötigen99-kompatiblen Leser oder Vorwärtsfix;
98 nach Speicherung dieser Formate kein vollständiger Rückweg.

Nachweise und Grenzen: [RELEASE_99_2026_10_23.md](RELEASE_99_2026_10_23.md).

## Vorheriger Stand98

# Produktionsstand1.26.1+98 ·23.10.2026

Live: https://schulpilot.dorfspy.de
Produktcommit `91b3de8ef5c45224018ca50db7bf2d064d02b0cd`, Release `20261023T102329Z-91b3de8`, main gepusht.

Lernrunde und Fotoeinstieg stehen auf der Startseite vor Suche und weiteren
Tagesaktionen. PDF-Import prüft Rechte und Idempotenz nach sperrfreier Extraktion
erneut; lokale SQLite-Katalogjobs serialisieren parallele Kontextänderungen.
Der KI-Darstellungskatalog aus97 mit24Fachprofilen bleibt maßgeblich.

Vollständige [CI39922708482](https://github.com/meinzeug/schulpilot/actions/runs/39922708482)
grün:2096Backend-/2633Flutterfälle bestanden,33/19übersprungen, Analyse/Ruff
und Webbuild erfolgreich. Zusätzlich79betroffene Backendfälle auf PostgreSQL16
und SQLite sowie190gezielte Flutterfälle bestanden. Reguläre signierte Builds,
Quell-/Signatur-/Geheimnisprüfung und öffentliche APK-/JS-Hashprüfung bestanden.
Alle fünf Dienste aktiv, Schema0031,17Konfigurationsdateien bytegleich erhalten.

Nachweise: [RELEASE_98_2026_10_23.md](RELEASE_98_2026_10_23.md).
Weitere tatsächlich bediente Referenzen und priorisierte eigene Ausbauideen:
[SIMPLECLUB_ROUND_2_2026_10_23.md](SIMPLECLUB_ROUND_2_2026_10_23.md).
Keine weitere kostenpflichtige KI-Probe; die einmalige verworfene97-Probe bleibt
vom lokalen Renderer-/Mocknachweis getrennt.97 liest das persistierte Format,
96 nach gespeicherten Szenen weiterhin ungeeignet; keine alte Gesamtdatenbank
über neue Kinderantworten zurückspielen.

## Vorheriger Stand97

# Produktionsstand1.26.0+97 ·23.10.2026

Live: https://schulpilot.dorfspy.de
Produktcommit `11ab8d4e75d075ce3dabc111b9646f19b736c5e8`, Release `20261023T092606Z-11ab8d4`,
main gepusht; Web, signierte Direct-APK und Play-AAB aus demselben sauberen Stand.

Kompakter700px-Aufgabenraum mit angepasster Typografie, ehrlichem Bearbeitet-
Zähler und fester Prüfleiste; Drag-and-drop mit Tippalternative, individuelle
quellgebundene SceneV1-Animationen und begrenzte lokale Funktions-/Messdaten-/
Logikexplorer. Die Aufgabenerstellung kennt jetzt je Fach Zweck und tatsächliche
Fähigkeiten, abgeleitet aus dem endgültigen Schema. Normale Heftaufgaben leiten
ihr Fach auch aus material.subject ab; Legacy-Textmaterial bleibt kompatibel.

684gezielte Flutterfälle plus33überschneidende Nachprüfungen,540Backendfälle
in20Dateien grün; Analyse/Ruff grün. Desktop-/Mobilbrowserprobe mit künstlichen
Beispielen bestanden. Reguläre Paket-/Signatur-/Quell-/Geheimnisprüfungen bestanden,
öffentliche APK und JavaScript bytegleich, fünf Dienste aktiv, Schema0031.
Die einzige echte synthetische Modellprobe wurde verworfen und abgerechnet;
kein weiterer Aufruf, kein erfolgreicher echter KI-Szenennachweis. Finale
Quellen sind offline und mit Provider-Mocks geprüft. Vollständige GitHub-CI
lief beim Releaseabschluss noch; deren Erfolg wird nicht vorweggenommen.

Nachweise und Rückweg: [RELEASE_97_2026_10_23.md](RELEASE_97_2026_10_23.md).
Vor Rückweg gespeicherte scene-JSONs prüfen;96 ist nach neuen Szenen kein
geeigneter Leser. Konfiguration, Google-Nachweis und verschlüsselte Sicherungen
erhalten. Keine alten Datenbanken über neuere Kinderantworten zurückspielen.

## Vorheriger Stand96

# Produktionsstand 1.25.0+96 · 23.10.2026

Live `20261023T061617Z-a02314d`, Produktcommit
`a02314d4076bbe9a66ccd30e604f0319937e32c7`, Schema0031. Lernpläne mit gemeinsamen
Themen-/Tageskarten, Fach-/Datumszeichen und Zeit-/Statuspills; beschriftete
Desktopsidebar, ruhiger Aufgabenraum, klare Antwortkarten und adaptive
Grafikrahmen mit Zoom. Kontowechsel schließt den Grafikzoom auch im untätigen UI.

717Flutterfälle grün, Analyse ohne Befund, künstliche1440px-/390px-Browserprobe
bestanden. Gebundener regulärer Web-/Direct-/Play-Build, Signaturen und
öffentlicher Web-/APK-Bytevergleich geprüft. Alle fünf Dienste aktiv,
Konfiguration/Schema/Google-Nachweis erhalten, verschlüsselte Sicherungen
bestätigt. Kontrollierter Rückweg auf95; kein Storeupload oder tatsächliche
native Updateinstallation. Referenz- und Abnahmegrenzen sowie vollständige
Nachweise: [RELEASE_96_2026_10_23.md](RELEASE_96_2026_10_23.md).

---

# Historischer Produktionsstand 1.24.1+95 · 23.10.2026

Live `20261023T054250Z-4ae6f3e`, Produktcommit
`4ae6f3e48d56ba225616b2fdc15fb32aad681cbd`, Schema0031. Schulbuddy klappt
beide allgemeinen Einleitungsblöcke beim ersten Senden und bei vorhandenem
Verlauf automatisch ein. Das Info-Symbol macht sie wieder zugänglich;
konkrete Fehler-/Sperrhinweise bleiben sichtbar.

47gezielte Flutterfälle grün, Analyse ohne Befund, künstliche390px-Browserprobe
bestanden. Reguläres Web, signierte Direct-APK und Play-AAB aus sauberem Commit
gebaut; Signaturen und öffentlicher Web-/APK-Bytevergleich geprüft. Kein
Storeupload oder tatsächliche native Updateinstallation. Alle fünf Dienste aktiv,
Sicherungen und kompatibler Rückweg auf94 erhalten. Vollständige Belege:
[RELEASE_95_2026_10_23.md](RELEASE_95_2026_10_23.md).

---

# Historischer Produktionsstand 1.24.0+94 · 23.10.2026

Live auf https://schulpilot.dorfspy.de: `20261023T051618Z-de5e0a8`,
Quellcommit `de5e0a878a5a215c76e60d97b05963dca91022cf`, Schema0031.
Der vollständige Gestaltungsumbau einschließlich gemeinsamer Palette, Desktop-/
Mobilnavigation, Icons, Fachbadges und Suche ist über `ssh dorfspy` veröffentlicht.
Reguläres Web, signierte Direct-APK und Play-AAB erfolgreich gebaut und unabhängig
geprüft; öffentliche Web-/APK-Dateien bytegleich. Kein Storeupload.

Alle fünf Schulpilotdienste aktiv, lokale und HTTPS-Healthchecks erfolgreich,
Datenbank-/Konfigurationssicherungen vorhanden. Schema, Konfiguration und
Google-Nachweis erhalten. Vorheriger Release93 bleibt als kompatibler Rückweg.
Öffentlicher Einstieg und mobile Anmeldung tatsächlich im Live-Browser geprüft;
keine Produktionskonten, Formulare, Käufe oder KI-Aufträge zum Test erzeugt.
Die255 Flutterfälle und anschließenden52 überlappenden Such-/Mobilfälle bleiben
getrennt dokumentiert; zusätzlich15Release-/Deploytests und13Subtests grün.
Keine vollständige Geräte-/Barrierefreiheitsabnahme behauptet.

Genaue Buildbindung, Hashes, Sicherungen und Rückweg:
[RELEASE_94_2026_10_23.md](RELEASE_94_2026_10_23.md).

---

# Historischer lokaler Gestaltungsstand · 22.10.2026

Die bestehende Flutter-App in `~/schulpilot` hat eine neue gemeinsame Gestaltung
nach der ausdrücklich beauftragten simpleclub-Referenz. Direkt im Browser wurden
Desktop und390×844px angesehen: Home, Entdecken, Bibliothek, Fach- und
Lektionsansichten. Schulpilot verwendet jetzt ruhige Anthrazitflächen, blaue
Hauptaktionen, lokale Nunito-Überschriften, flache runde Karten,80px-Iconnavigation
im Browser und eine schwebende mobile Navigation. Eigene dünne Canvas-Icons und
farbige Fachbadges ergänzen Startseite, Suche und Fachlisten. Die gemeinsame
Palette wirkt auch in Eltern-, Verwaltungs-, Zugangs- und Lernansichten sowie im
Webstart und den eigenständigen Webformularen.

Nachgewiesen:

- **255 Flutterprüfungen** aus19 betroffenen Testsammlungen bestanden. Rollen,
  Kontowechsel, reine GET-Navigation, Formular-/Providerentwürfe, Kontraste,
  Tastaturfokus und320/390/960/1440px einschließlich200% Schrift geprüft.
- Anschließend **52 gezielte Hefter-/Mobilprüfungen** bestanden, darunter zwei
  neue Rückkehrfälle für die Startseitensuche mit zuvor gemerkter Ansicht
  „Alle Seiten“. Diese52 überschneiden sich mit dem großen Lauf und werden
  nicht als zusätzliche52 unabhängige Prüfungen ausgegeben.
- Statische Analyse der12 betroffenen Dartdateien ohne Befund. Webmanifest
  geprüft, Diff ohne Whitespacefehler und auf eingefügte Zugangsdaten geprüft.
- Regulärer Release-Webbuild und eine getrennte lokale Browser-Vorschau mit
  künstlichen Daten erfolgreich gebaut. Die Vorschau verwendet die tatsächlichen
  Flutter-Ansichten; sie verweigert sämtliche schreibenden Anfragen.
- Lokale Browser-Sichtprüfung auf Desktop und390px: Startseite, Fachsuche,
  Suchfilter und Hefterdarstellung. Screenshots enthalten ausschließlich
  ausdrücklich gekennzeichnete Beispieldaten.

Quellversion bleibt1.23.0+93. Es wurde keine neue APK gebaut und kein
Produktionsdeployment durchgeführt. Die bestehende Live-Abnahme darunter
beschreibt weiterhin die zuvor veröffentlichte Version. Umfang:
[SIMPLECLUB_STYLE_2026_10_22.md](SIMPLECLUB_STYLE_2026_10_22.md), gemeinsame Regeln:
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

---

# Produktionsstand 1.22.2+92 · 22.10.2026

Live: `20261022T212319Z-12d4389`, Produktcommit
`12d43896ce4c2fb55839eba218beb8ffce374252`, main gepusht, Schema0029.
Gebundener Build und öffentliche APK-/JavaScript-Byteprüfung bestanden.
Die tatsächlich noch zu hohen Eltern- und Admin-Mobilköpfe sind nachgebessert
und im Produktionsbrowser bei320px/390px bedient.86 native UI-Fälle,91
Backend-/Migrationsfälle,7 Offline-Agentfälle,13 Operator-Widgetfälle sowie
Betriebsregressionen bestehen; diese gezielten Läufe werden nicht zu einer
erfundenen Vollsuite addiert. Alle5Produktionsdienste sind aktiv.

Die normale künstliche Buddy-Familie und die ursprüngliche Browser-Demo sind
bereinigt. Der ausdrücklich genehmigte Testadmin ist gesperrt und seine
Sitzungen sind widerrufen; private QA-Zugangsdaten wurden nach401Nachweisen
entfernt. Die erfolgreiche einzelne Luna/high-UI-Frage und die fehlgeschlagene
zweite Sol/max-Reparaturprobe bleiben getrennt dokumentiert. Kein dritter
Reparaturaufruf, kein Patch angewendet, keine Quotenänderung. Einzelbelege,
Artefakthashes und Rückweg: [RELEASE_92_2026_10_22.md](RELEASE_92_2026_10_22.md).

Neuer Folgeauftrag: marktreifer Webverkauf mit Überweisung, PayPal und noch
zu konkretisierender Google-Zahlungsart. Der öffentliche Katalog meldet derzeit
Verkauf/Testphase aus; echte Betreiber-/Bank-/Steuerangaben und Händlerfreigaben
fehlen. Ein persönlicher PayPal-Login ist im geöffneten Browser angefragt.
Die Implementierung entsteht getrennt im verwalteten Commerce-Worktree; keine
erfundene Händlerfreigabe oder Aussage bereits möglicher Zahlung.

---

# Historischer Produktionsstand 1.22.1+91 · 22.10.2026

Live: `20261022T204523Z-b42447c`, Produktcommit
`b42447cb61a53d2249a0eddd09cd31f51e67b50a`, main gepusht, Schema 0029.
Web, signierte Direct-APK und tatsächliches Play-AAB sind aus diesem sauberen
Quellstand gebaut und unabhängig geprüft. Öffentliche APK und öffentliches
JavaScript stimmen bytegenau mit den lokalen Release-Dateien überein.
Signierer/Version, Play-Bundle und fehlende Play-Installerberechtigung sind
geprüft; kein Storeupload. Erneute Geheimnisprüfung: 909 Quellen/Assets,
350 Archiveinträge, 24 bekannte Secretquellen, 0 Treffer. Belege und Hashes:
[RELEASE_91_2026_10_22.md](RELEASE_91_2026_10_22.md), `artifacts/ux91/`.

Die kompaktere mobile Führung, erhaltene Info-/Filter-/Mehrmenüaktionen und
Google-Zugangshinweise sind veröffentlicht. Der neue öffentliche Einstieg
bezieht Trial und Preise aus dem echten Katalog. Betreiberangaben werden vom
Nutzer später nachgereicht; kostenlose 30-Tage-Testphase und bezahlter Verkauf
bleiben bis zu vollständiger Konfiguration und bewusster Freigabe gesperrt.
Veröffentlichung der Oberfläche ist keine Freigabe dieser Angebote.

Schulbuddy ist mit eigener Luna/high-Bindung ohne Websuche integriert. Die
normale 91er-UI-Probe verwendete eine neu registrierte und per Plusmail
verifizierte eigene künstliche Familie mit genau einem Kind und einer eng
begrenzten, einmaligen auditierten QA-Freigabe; kein Demo-Flag. Genau ein
Starter wurde gesendet. Die sichtbare Antwort gab einen Denkschritt ohne
Lösungsverrat; Schließen/Wiederöffnen erhielt die History. Serverbeleg:
genau ein abgeschlossener Job, ein bereiter Turn und ein Verbrauchsbeleg,
Settlementversion 1 und 150000 USD-Mikroeinheiten weiterhin angerechnet.
Tatsächliche Codex-Kontokosten bleiben unbekannt. Bild-/Metadatenbelege:
`buddy-regular-ready.png`, `buddy-regular-answer.png` und
`regular-buddy-after-ui.json` unter `artifacts/ux91/`. Dies ist getrennt von der
historischen 90-Operatorprobe und kein allgemeiner fachlicher Qualitätsnachweis.

Die vollständigen lokalen Erstläufe bleiben dokumentiert:
PostgreSQL 1896 bestanden/2 fehlgeschlagen; Flutter 2466 bestanden/12 Webskips/
7 fehlgeschlagen. Die betroffenen korrigierten Pfade bestanden ihre gezielten
Nachläufe, darunter 175 Backend-/Betriebsfälle und 38 mobile Vertragsfälle.
Google 28 nativ/9 Chrome, Commerce 17 nativ/2 Webskips sowie 19 Chrome und
Schulbuddy 34 nativ/9 Chrome sind getrennte, teilweise überlappende Nachweise;
ein vollständig grüner Wiederholungslauf liegt damit nicht vor.
Vollständige Analyse und Ruff sind ohne Befund. Ein gehosteter grüner CI-Lauf
ist hier nicht belegt.

Die getrennte zweite echte Sol/max-Reparaturprobe endete mit `empty_patch`;
ein erfolgreicher Patch und Nachhertest sind nicht belegt. Das normale künstliche
Buddy-Testkonto wurde über den regulären Löschweg vollständig bereinigt
(`artifacts/ux91/regular-buddy-cleanup.json`); Demo und Reparaturtestadmin bleiben
bis zur abschließenden Nachprüfung getrennt offen. Die tatsächliche 320px-
Browserprüfung fand außerdem einen weiterhin zu hohen Eltern-Kind-
Navigationsblock; eine enge 92-Folgekorrektur wird separat bearbeitet.
Keine pauschale erfolgreiche Browserprüfung aller Menüs, keine neue physische
Android-/Pushzustell-/vollständige WCAG-Abnahme. Die unveränderlichen 91er-
Produktbelege werden durch nachfolgende Dokumentation nicht ersetzt.

---

# Historischer Produktionsstand 1.21.1+89 · 22.10.2026

Live: `20261022T134524Z-03e3bfe`, Produktcommit
`03e3bfeffd654ff169ebf2daceb6537476cadf03`, main gepusht.

Mit Root und drei parallelen Fachagenten wurden **317 zusätzliche eigenständige
Bedienverbesserungen** gegenüber dem321er-Zwischenstand umgesetzt und belegt:
88 Kind,85 Eltern,89 Administration/Bestellungen und55 gemeinsame Wege.
Die früheren321 Maßnahmen werden nicht erneut gezählt. Karten mit einem klaren
Ziel sind über die gesamte Fläche bedienbar, mit sichtbarer Zielbeschriftung,
Pfeil, Tastaturfokus und benannter Aktion. Formular-/Mehrfachaktionen bleiben
gezielt erreichbar. Elternkarten öffnen passende Planreiter und gespeicherte
Aufgabenfilter; Kinder-, Konto-, Anmelde-, Admin- und Bestellwege wurden ebenfalls
verbessert. Kontowechsel-/Routenprüfungen verwerfen verspätete private Inhalte
und alte Aktionen. Lesende Wege starten keine KI.

Breite Browserprüfung von88 und anschließende89-Abnahme im eigenen künstlichen
Haushalt: Kinder-Reload erhält Sitzung; korrigierte Eltern-Lernzeitkarte ist im
Accessibilitybaum eine Schaltfläche und führt direkt zu Woche & Vorgaben.
Die Browserkorrektur89 schließt nur dekorative Fortschrittsindikatoren aus der
Kartensemantik aus; genaue Zeit-/Statusinformationen bleiben zugänglich.
320px-Kinderansicht und Elternansicht gesichert, Viewport zurückgesetzt.
Beide Rollen regulär abgemeldet, eigener Testhaushalt normal gelöscht; alte
Sitzung und beide Logins danach401, lokale Zugangsdaten entfernt. Null KI- und
Push-Aufträge. Öffentliche Startseite offen, ursprünglicher Google-Tab erhalten.

Vollständiger isolierter PostgreSQL16-Lauf: **1593 bestanden**; drei bestehende
Abhängigkeitshinweise. Vollständiger nativer Flutterlauf89: **2009 bestanden**,
fünf reine Webfälle bewusst übersprungen. Betroffene Kartenrollen zusätzlich
nativ und im echten Chrome-Runner geprüft; vollständige Analyse und Ruff sauber.
GitHub-Lauf39772352507 startete wegen der bestehenden Abrechnungssperre keine
Flutter-/Backendjobs. Keine gehostete grüne CI behauptet.

Web, signierte Direct-APK und tatsächliches Play-AAB gebaut und unabhängig
geprüft. Öffentliche APK und öffentliches JavaScript stimmen bytegenau mit den
lokalen Release-Dateien überein. Signierer/Version korrekt, Play-Bundle gültig
und ohne APK-Installerberechtigung; kein Storeupload. Quellen-/Archiv-/Web- und
Relaysecretprüfung ohne Treffer, nach Testkontobereinigung erneut geprüft.

API, Worker, Caddy und TURN aktiv; Sicherung erfolgreich, Schema0026 und
OpenRouter-Providerrevision29 mit Economy/ZDR unverändert. Rückweg für Web/API:
`20261022T131154Z-9498e08` (88 mit dokumentiertem Kartenrollenfehler), auf dem
Server erhalten. Keine Datenbankrücksetzung; Androidkorrektur mit höherem Code.

Vollständige317er-Liste, Artefakthashes, Recherche, Code-/Testverweise und Grenzen:
[UX_300_ROUND2_2026_10_22.md](UX_300_ROUND2_2026_10_22.md).
Die Tutor-Vorschauseitenbegrenzung K081 und der ungünstige Hausaufgaben-Umbruch
bei320px bleiben ausdrücklich offen und erhöhen die Maßnahmezahl nicht.
Keine neue physische Android-, Live-Admin-, Foto-/KI-Qualitäts-, Pushzustell-
oder vollständige Screenreader-/WCAG-Abnahme. Nachfolgende reine
Dokumentationsänderungen verändern den bereitgestellten Produktcode nicht.

---

# Historischer Produktionsstand 1.19.6+85 · 22.10.2026

Live: `20261022T075254Z-a8201fc`, Produktcommit
`a8201fcc3c596f6a1f0243b5e7443d482256a9ca`, main gepusht.

Drei parallele Fachagenten prüften Kinderbereich, Elternbereich und Anmeldung;
die gegenseitige Gegenprüfung ergänzte konkrete Kontowechsel-/Dialogfehler.
Die Elternübersicht beginnt mit gespeicherten Übungsbelegen. Lernplan und
Hausaufgabenlisten unterscheiden Laden, Fehler, leere Filter und Fortsetzung;
keine alten Themen unter neuer Seitenwahl. Pagination auch bei 320px und
200% Schrift ohne Überlauf. „Frage schreiben“ ist im Kinderpostfach direkt
erreichbar; Kontextlinks und Empfänger sind konkret beschriftet. Geräteaktionen
haben gezielte Bestätigung, Rückmeldung und einen verständlichen Leerzustand.

Anmeldung: Weiter-/Fertig-Tastaturwege, Autofillgruppe, lokale Feldhinweise ohne
leere Loginanfrage, erhaltene Eingaben und Mailfragmente. Google-/Passwortstarts
gegenseitig gesperrt, optionaler Google-Status kontogebunden zwischengespeichert.
Kein Wechsel an OIDC, Authregeln, Rollen, Anbietern oder Kontingenten.

Exakte Sitzungsbindung und Kind-/Generationsstempel verhindern die Übernahme
verspäteter Inhalte. Alte Geräte-, Nachrichten- und Eltern-Themendialoge werden
gezielt geschlossen; verspätetes Speichern darf keinen neuen Dialog schließen.
Unbekannte Ladefehler geben keine internen Exceptiontexte mehr aus.

Alle 1.203 Fluttertests im abschließenden Gesamtlauf bestanden; vollständige
Analyse ohne Befund. Im ersten Lauf wurden ausschließlich zwei historische
Beschriftungsassertionen an die konkreteren Texte angepasst; Navigations-,
Hilfe- und GET-only-Prüfungen blieben erhalten. Gehosteter GitHub-Lauf 39730113540
startete wegen der bestehenden Abrechnungssperre keine Prüfschritte. Lokale
Prüfungen bleiben davon getrennt.

Web, signierte Direct-APK und korrektes Play-AAB gebaut und unabhängig geprüft.
APK 111875235 Bytes, SHA256
`ddb025e2c09e658f6413800a6a90fc0876e75312d938ec3639993d3c17341993`;
AAB 89135569 Bytes, SHA256
`490eb414fcc39944e99de7d82821c0f26b57d319f0d5a6a123fc883b872dd815`.
Öffentlicher vollständiger APK-Download identisch. Signierer und Version stimmen;
Play-Bundle gültig und ohne APK-Installerberechtigung, kein Storeupload.
Geheimnisprüfung von Quellen/Web/Archiven sowie Relaysecretprüfung ohne Treffer.

API, Worker, Caddy und bestehender TURN-Dienst aktiv; Sicherung erfolgreich,
Schema 0026 und OpenRouter-Providerrevision 29 mit Economy/ZDR unverändert.
Rückweg für Web/API: `20261022T065736Z-1647c03`, keine Datenbankrücksetzung.
Native Folgekorrekturen benötigen einen höheren Versionscode.
Details, Recherche und Grenzen in [UX_REVIEW_2026_10_22.md](UX_REVIEW_2026_10_22.md).


Produktionsbrowser mit eigener künstlicher Familie geprüft: Elternübersicht
hell/dunkel, mobiler Lernplan/Navigation, Hausaufgabenfilter-Rückweg,
Pflichtfeldfokus und Enter-Anmeldung, direkte Frage mit Abbrechen und echtes
Abmelden der aktuellen Kindersitzung. Viewport zurückgesetzt und Testtab
entfernt. Normaler Account-Löschpfad bestätigte die eigene Testfamilienlöschung;
alte Sitzung und beide Logins anschließend 401. Lokale Zugangsdaten entfernt,
null KI-/Push-Aufträge. Keine neue physische Android- oder echte Google-
Anmeldung und keine vollständige Screenreader-/WCAG-Abnahme behauptet.
Nachfolgende Dokumentationskorrektur verändert den bereitgestellten Produktcode
nicht.

---

# Historischer Produktionsstand 1.19.5+84 · 22.10.2026

Live: `20261022T065736Z-1647c03`, Produktcommit
`1647c03533a0f493edab66b941499a1a34aa5b11`, main gepusht.

Firebase unter dem beauftragten Google-Konto und auf dem Server unabhängig
abgeglichen: bestehendes Projekt, Plattform-Apps/-Keys, VAPID, APIs und minimale
Senderrolle stimmen; OAuth und Versandberechtigung funktionieren. Zum
Prüfbeginn waren keine Pushgeräte registriert. Freigaben, Ruhezeiten und
Sitzungsbindung bleiben erforderlich.

Der Android-Empfänger verlor beim manuellen Delegieren den frameworkgebundenen
PendingResult. Die signierte 83-APK reproduzierte mit genau einer echten
Nachricht einen Absturz ohne sichtbare Meldung. Der korrigierte Receiver erbt
vom fixierten FlutterFire-Receiver. Signierte 84-APK auf eigenem Android-36-
Emulator: kalter Prozess und Vordergrund getrennt erfolgreich, echte Meldungen
sichtbar und richtige Kindersitzung geöffnet. Exakt zwei neue Meldungen;
Screenshotpause und sichtbare Helfernavigation erzeugten keine weiteren.

Web: ausdrücklicher Permissionbutton mit Timeout, kontogebundene Wiederaufnahme
und geordnete SDK-/Tokenwechsel. Im freigegebenen isolierten Chrome-Profil null
Firebaseverkehr vor App-Opt-in, echte Registrierung und Validierung erfolgreich,
Vordergrundbanner sichtbar. Zweite Meldung ohne geöffnetes App-Dokument durch
den Serviceworker als Notification registriert; kein sichtbarer Desktop-OS-
Banner behauptet. Restore und Logout/Registrierungsentfernung bestätigt.
Im integrierten Browser zeigt die nicht beantwortete Permissionanfrage jetzt
einen begrenzten Fehlerhinweis und gibt den Einschaltbutton wieder frei.

1.155 Fluttertests einschließlich 20 gezielter Push-/Webfälle, volle Analyse,
22 PostgreSQL-Push-/Inboxfälle, sechs native Regelfälle, echte Frameworkprobe
und sechs lokale QA-Guardfälle bestanden. Gehosteter GitHub-Lauf 39724081470
startete wegen der bestehenden Abrechnungssperre keine Schritte; lokale
Prüfungen bleiben davon getrennt.

Web, signierte Direct-APK und Play-AAB geprüft. APK 111776935 Bytes, SHA256
`46c69e8e3b77ab98920dcc9826d8ea57071ccb047000e355c36ed930e8e47da9`;
AAB 89009534 Bytes, SHA256
`bde6cc79060e74b11243ee5461e5ab5c867829926e2be4c17f0e422032bb0ce1`.
Vollständiger öffentlicher APK-Download identisch; Play ohne Installerberechtigung,
kein Play-Upload. Releasequellen/Web/Archive gegen lokale Geheimnisse geprüft,
Relaysecret zusätzlich ausschließlich im Speicher: keine Treffer.

API/Worker/Caddy und projektspezifischer TURN-Dienst aktiv, Sicherung erfolgreich,
Schema 0026 und Providerrevision 29 Economy/ZDR unverändert. Künstlicher
Haushalt normal gelöscht; alle 15 gezielten Kaskadenzähler null, Logins/Sitzungen
ungültig, Audit/Löschjournal bestätigt und lokale Zugangsdaten entfernt. Emulator
beendet. Physisches Smartphone und hörbarer Ton bleiben getrennt ungeprüft.
Rückweg für Web/API: `20261022T052536Z-e502960`, keine Datenbankrücksetzung.
Native Folgekorrekturen brauchen einen höheren Versionscode.

Vollständige Abnahme und eigene Gerätefreigabe in
[FIREBASE_EVALUATION_2026_10_22.md](FIREBASE_EVALUATION_2026_10_22.md).
Nachfolgende reine QA-/Dokumentationskorrekturen ändern den bereitgestellten
Produktcode nicht.

---

# Historischer Produktionsstand 1.19.4+83 · 22.10.2026

Live: `20261022T052536Z-e502960`, Produktcommit
`e502960a96ce84f4c26899f0fc4bf44ee02ea3a3`, main gepusht.

Die Livehilfe öffnet beim Kind keine eigene Gesprächsseite mehr. Ein kompakter,
aufklappbarer Dock sitzt oberhalb der weiterhin geöffneten Aufgabe. Mikrofon,
Kamera, Teilen/Stopp und Auflegen bleiben erreichbar; Videos sind optional.
Entwurf und Antwortfeedback bleiben erhalten. Auch native Anrufaktionen ersetzen
keine laufende Aufgabenroute. Alte Anruflinks verdrängen kein neueres Gespräch.
Eine freiwillige Großansicht bietet einen Rückweg; ihre Rendererbelegung bleibt
bis nach der Pop-Animation exklusiv. Overlay- und Semantikgrenzen erhalten
Tooltips und zugängliche Bedienelemente außerhalb des Aufgaben-Navigators.

98 gemeinsame Fluttertests einschließlich zehn neuer Dock- und fünf neuer
Main-/Navigationsfälle sowie vollständige Flutter-Analyse bestanden.
36 Anruffälle erneut in isoliertem PostgreSQL bestanden. Echte Browserprüfung
der ausdrücklich synthetischen Vorschau in hell/dunkel und 390 × 844: Aufgabe,
Entwurf, Freigabedialog und Rückkehr aus Großansicht geprüft. Kameraansichten in
dieser Vorschau sind ausschließlich gezeichnete Platzhalter.

Zwei begrenzte künstliche Liveproben mit der signierten 83-APK auf Android 36:
Kamera/Audio/Screen wurden über den Produktionsrelay empfangen, Entwurf und
Antwortaktion blieben während echter Tastatureingabe nutzbar. Gezielter
Bildschirmstopp 224→192 beendet Projection und erhält Kamera/Ton. Der Rückweg
über Heute und Lernen zeigt dieselbe Aufgabe 2/4 mit erhaltenem Bruchentwurf;
dieser Teil ist separat visuell mit zeitgleichen nativen Metadaten geprüft,
nicht als grüne alte Helferdatei ausgegeben. Beide Parentpeers normal beendet
und ausgeloggt, Kinderlogout/Capture-Aus und Emulatorende geprüft. Keine dritte
Probe. Der neue Demohaushalt ist über seinen regulären authentifizierten
Löschweg vollständig bereinigt; alle zugehörigen Datenzähler stehen auf null.
Zugangsdaten und privater IDs-Checkpoint entfernt, beide alten Logins ungültig.
Physische Smartphone-Ruflautstärke und Tonqualität bleiben getrennt ungeprüft.

Web, signierte Direct-APK und Play-AAB aus demselben Produktcommit geprüft.
APK 111744163 Bytes, SHA256
`97dc018cf9537f955820b306f6a1b911b49f27581ea94b25afad50ddd53ba2ee`;
AAB 88983781 Bytes, SHA256
`72a2eccbad9c8cce14662cb334cecd1ea110cade0d0fcda03a86ac86f5217708`.
Vollständiger öffentlicher APK-Download identisch, Play ohne Installerberechtigung,
kein Play-Upload. 684 Quellen/Assets und 350 Archiveinträge gegen 14 lokale
Secretquellen ohne Treffer; Relaysecret zusätzlich nur im Speicher gegen 782
Dateien und dieselben Archiveinträge geprüft: 0 Treffer.

API/Worker/Caddy aktiv, Sicherung erfolgreich, Schema 0026 und Providerrevision 29
Paid/Economy/ZDR unverändert. Keine neuen Pakete, Dienste, KI-Aufträge oder
Berechtigungen. Vorheriger kompatibler Release für Web/API-Rückweg:
`20261021T194514Z-e58e6c4`. Keine Datenbankrücksetzung; bereits installierte
Android-83-Clients benötigen bei einer nativen Korrektur eine höhere Version.

Bedienung und Abnahme in [FAMILY_CALLS.md](FAMILY_CALLS.md) und
[FAMILY_CALL_EVALUATION_2026_10_21.md](FAMILY_CALL_EVALUATION_2026_10_21.md).

---

# Historischer Produktionsstand 1.19.3+82 · 21.10.2026

Live: `20261021T194514Z-e58e6c4`, Produktcommit
`e58e6c4e98411052bda37378d158cf9d30a360b2`, main gepusht.
Anruffunktion nach Sicherung und Audit wieder aktiviert.

- Livehilfe bei Heute, Aufgaben, Rückblick, Nachrichten und Hausaufgaben:
  ausdrücklicher Anruf an berechtigte Eltern, Bildschirmfreigabe separat.
  Keine Aufzeichnung, Fernsteuerung oder KI-Verarbeitung der Gesprächsmedien.
- Späte Bildschirmangebote erhalten durch stabile Sequenzzähler ihren Platz oberhalb
  bestehender Empfangscursor. Private SDP-/ICE-Inhalte verfallen weiter nach 90 Sekunden;
  begrenzter Hashindex und Zähler enden mit der festen Anruffrist. Ein eigener
  API-Timer bereinigt ohne Seitenaufruf und wartet nie blockierend auf seinen Lock.
- Fehlgeschlagene Capture-/Angebotsschritte stoppen nur die Bildschirmfreigabe,
  räumen ausstehende Flags auf und erlauben einen bewussten Neuversuch. Nach
  Bildschirmstopp entfällt nur der Android-Projection-Diensttyp; Kamera/Ton bleiben.
- Die echte 81-Probe deckte eine vorhandene API-Blockade auf: 15 Poolplätze waren
  belegt, während die synchrone Installationsprüfung im Async-Eventloop wartete.
  Kontrollierter Rückweg auf 80 ohne Datenbankrücksetzung; 82 verlagert die gesamte
  Gate-Session in einen Worker und erhält Setup-Sperre sowie redigierte Fehler.
  Der alte Pfad scheitert im kontrollierten Engpasstest, der neue bleibt ansprechbar.

136 gemeinsame PostgreSQLfälle einschließlich kompletter Installation, Pool-/
Eventloop-Konkurrenz, Anrufrechten, Migrationen, Push, Inbox, Tutor und Feedback
bestanden. Die 83 Flutterfälle und sechs Kotlin-Regelfälle für den unveränderten
Clientcode sowie vollständige Flutter-Analyse bleiben gültig; 19 abschließende
Headerfälle sind eine Teilmenge, keine zusätzliche Gesamtzahl. Ruff/Diff sauber.

Die signierte 80-APK hat echte FCM-Hintergrundzustellung und CallStyle-Annahme sowie
zwei gleichzeitig sichtbare Kinder-Videobilder und die eigene Elternkamera belegt.
Die abschließende 82-APK überträgt echte Emulator-Kamera, Audio und den ausdrücklich
geteilten Bildschirm über den erzwungenen Produktionsrelay: 143,36 Sekunden
zwischen Erstangebot und erstem Screenangebot, 300,26 Sekunden Beobachtung. Bildschirmstopp
beendet Projection bei weiterlaufendem Kamera-/Mic-Dienst; bewusstes Mic AUS/AN
lässt globale Schutzschalter unverändert. 15 Healthchecks während des
Gesprächs erfolgreich, langsamster 0,029 Sekunden. Danach regulär beendet und
abgemeldet; die unbestätigt abgemeldete Sitzung des fehlgeschlagenen 81-Tests gezielt
im künstlichen Haushalt widerrufen und auditiert. 10 künstliche Anrufe insgesamt, null außerhalb; keine aktiven Calls oder QA-Pushgeräte.

Web, Direct-APK und Play-AAB aus demselben Produktcommit signiert/validiert.
Öffentlicher APK-Voll-Download stimmt überein. APK 111662243 Bytes, SHA256
`9bbc8ba3b16f4a2cef13fc4f467072aba9afaba3ef6d2df7dea9b117ef535e1a`;
AAB 88908351 Bytes, SHA256
`646702fb157cb54dca7310ae4ad475c651a230a3e2cb8ffde632542814d7f1a7`.
Play ohne APK-Installerberechtigung; kein Play-Upload. 681 Quellen/Assets und 350
Archiveinträge gegen 14 lokale Secretquellen ohne Treffer; Relaysecret zusätzlich
nur im Speicher gegen 779 Dateien und dieselben 350 Einträge geprüft: 0 Treffer.

API/Worker/Caddy und eigener TURN-/Zertifikattimer aktiv, Sicherung erfolgreich,
Schema 0026, Providerrevision 29 Paid/Economy/ZDR unverändert. Familienanrufe nutzen
keine KI. Rückweg: zunächst `SCHULPILOT_CALLS_ENABLED=false` und Dienste neu starten; vorheriger 80-Release
`20261021T184832Z-fe3810f` kennt 0026. Keine Datenbankrücksetzung auf alte Antworten.

Physisches Smartphone weiterhin nicht in die VM importiert: BeagleOS-Konfiguration
gefunden, Thinclient erreichbar, SSH-Identität abweichend und USB-Tunnel gestört.
BeagleOS-Verwaltung im Browser benötigt noch die eigene Anmeldung. Keine
Hostkeyprüfung umgangen, kein allgemeiner USB-Listener gestartet. Hörbares Klingeln
auf dem physischen Telefon bleibt ungeprüft. Nur der eigene kurzlebige Emulator
wurde auf bestätigte UTC gesetzt und nach den Tests beendet.

Details: [FAMILY_CALLS.md](FAMILY_CALLS.md),
[FAMILY_CALL_ANDROID.md](FAMILY_CALL_ANDROID.md),
[FAMILY_CALL_EVALUATION_2026_10_21.md](FAMILY_CALL_EVALUATION_2026_10_21.md).

---

# Historischer Zwischenstand 1.19.0+79 · 21.10.2026

Live: `20261021T180510Z-f24e19c`, Produktcommit
`f24e19c5438956a38ddf9c87224e6d42403a3382`, main gepusht.

Abnahmehinweis: Neue Anrufe sind vorübergehend serverseitig angehalten. Der echte
Android-Medientest deckte einen nativen Renderer-/Mikrofonfehler auf. Korrektur80
ist mit75 Flutterfällen und vollständiger Analyse vorbereitet; bisher ausschließlich
drei künstliche Testanrufe, keine Anrufe anderer Haushalte.
Details: [FAMILY_CALL_EVALUATION_2026_10_21.md](FAMILY_CALL_EVALUATION_2026_10_21.md),
[FAMILY_CALLS.md](FAMILY_CALLS.md), [FAMILY_CALL_ANDROID.md](FAMILY_CALL_ANDROID.md).

- Gemeinsame Livehilfe bei Heute, Aufgaben, Rückblick, Nachrichten und Hausaufgaben:
  ausdrücklicher Video-/Audioanruf an berechtigte Eltern, Bildschirmfreigabe separat.
  Kamera, Ton, Bildschirm und Auflegen bleiben steuerbar; keine Aufzeichnung,
  Fernsteuerung oder KI-Verarbeitung von Gesprächsmedien.
- Backend bindet Kind und annehmende Elternsitzung, prüft aktuelle Familienrechte,
  hält Signale begrenzt im Arbeitsspeicher und speichert nur 30 Tage Metadaten.
  Widerruf, Neustart und abgelaufene Berechtigung beenden das Gespräch. Angenommene
  Hilfe zählt bei neuen passenden Antworten als Unterstützung; alte Antworten bleiben.
- Android: eigener freiwilliger Anrufschalter, neutraler hoch priorisierter Push,
  zeitlich begrenzter Klingeldienst und Annehmen/Ablehnen. Android-36-CallStyle-Fehler
  durch echten Systemtest gefunden und behoben. Keine Vollbild- oder Lautlosumgehung.
- Firebase-Diagnose: anfangs null Pushgeräte und null Versandversuche in sieben
  Tagen. Projekt/APIs/Schlüssel/Sender geprüft. Mit signierter APK 79 anschließend
  genau eine neutrale Hintergrundmeldung auf künstlichem Elterngerät tatsächlich
  angezeigt und durch Antippen geöffnet; FCM-Annahme separat nachgewiesen.
- Eigener authentifizierter coturn-Relay installiert. Konkrete Portfreigabe vom
  Betreiber bestätigt, nur am Schulpilot-Server ergänzt. Verschlüsselte künstliche
  Kamera-/Bildschirm-/Audiomedien über UDP, TCP und TLS tatsächlich übertragen.
  Gefundene Nullbereich-Sperre korrigiert, private Zielnetze weiter gesperrt.

98 gemeinsame PostgreSQLfälle einschließlich gefüllter Migrationen für SQLite
und PostgreSQL, 154 gemeinsame Flutterfälle, sechs native Kotlin-Regelfälle und
fünf TURN-Konfigurationsfälle bestanden. Native Android-36-Instrumentierung und
realer Browserdurchlauf mit künstlichem Kind durchgeführt. Vollständige Flutter-
Analyse, Ruff und Diffprüfung sauber. Kein hörbarer oder physischer Telefonbeleg.

Web und signierte APK/AAB 79 gebaut; Paket, Version, Signierer und Play-Bundle
geprüft. Play ohne APK-Installerberechtigung. Geheimnisprüfung des Releasecodes,
Webs und 350 Archiveinträge ohne Treffer; neuer TURN-Schlüssel zusätzlich nur im
Speicher geprüft. Öffentlicher APK-Voll-Download stimmt überein. APK 111449251 Bytes,
SHA256 `9de9d7baf1ba1aab0467d5a8129fdef5cff8dd93ea65928e86573887a797a52e`;
AAB 88862355 Bytes, SHA256
`f44b43db8dc656f37121c2a1f9bd55cdd61652b46769122d41fecb9b20f5e337`.
API/Worker/Caddy und eigener TURN-/Zertifikattimer aktiv, Sicherung erfolgreich,
Schema 0026, Providerrevision 29 Paid/Economy/ZDR unverändert. Anrufe erst nach
Relayprüfung explizit über geschützte Umgebung aktiviert und auditiert.

Bei Anrufproblemen zunächst Anruffunktion abschalten und aktuelle Dienste neu
starten; Vorwärtsfix bevorzugen. Release 78 ist nur ein begrenzter Notfallrückweg
mit `--rollback-compatible`. Seine alte Restoreprüfung kennt 0026 nicht, Call-
Export/Aufbewahrung fehlen. Keine Datenbankrücksetzung und keine vollständig
geprüfte langfristige Rückbetriebsbehauptung. Kein Play-Upload.

Zusätzliche Smartphone-Suche: BeagleOS-Pfad gefunden, USB/IP-Controller vorhanden,
kein physisches Telefon importiert. Thinclient-SSH-Schlüssel weicht ab, beide
konkreten USB/IP-Pfade nicht erreichbar, Mikrofontunnel ebenfalls gestört. Keine
Schutzprüfung umgangen oder allgemeiner USB-Listener gestartet. BeagleOS-
Verwaltungsanmeldung zur sicheren Fortsetzung angefordert.

---

# Produktionsstand1.18.4+78 ·21.10.2026

Live: `20261021T164256Z-7367ee4`, Produktcommit
`7367ee4d95e6af398195962496a16968c2faddcf`, main gepusht.
Details: [UI_AND_PARENT_REVIEW_2026_10_21.md](UI_AND_PARENT_REVIEW_2026_10_21.md).

- Kinder-Hausaufgaben und Hefte samt Details verwenden gemeinsame Seitenköpfe,
  Reiter, Fotoaktionen und beschriftete Suche/Filter. Meine Fächer behält den
  Seitenfilter; unzugeordnete Seiten bleiben erreichbar. Kartenüberlauf mit
  großer Schrift auf320px korrigiert; Elternabläufe erhalten.
- Headerglocke: maximal vier Meldungen, Alle anzeigen; Lesen erst bei Eintragsklick.
  Kontoname/Avatar: Einstellungen und reguläres Abmelden. Kontowechsel und verspätete
  Abmeldeantworten einschließlich401 dürfen keine neue Sitzung löschen. Admin bleibt
  auf Betriebsinformationen beschränkt.
- Elternbericht: Ausgabeschema und Validator teilen dieselben Belegkategorien und
  erlaubten Klärungsaktionen. Strenge Inhaltsprüfung bleibt; sieben feste private
  Ablehnungskategorien statt unbekanntem Fehler. Keine privaten Fehlerwerte loggen.
  Historisch war der Anbieteraufruf erfolgreich, lokale Prüfung gescheitert; genaue
  damalige Regel mangels gespeichertem Antwortinhalt nicht rekonstruierbar.
- Konkret beauftragte Reparatur nach Codefix einmal über bestehende berechtigte
  Elternsitzung normal reserviert und auditiert:1Aufruf/1Jobversuch,0,001337USD.
  Bericht ready, fachlich validiert, Elternansicht aktuell, Lernplan anwendbar.
  Alte Antworten/Fehlerberichte/Verbrauch hashgeprüft unverändert; keine neuen
  Kinderantworten eingetragen. Frühere0,001201USD erhalten. Keine Retrykette,
  Kontingenterhöhung oder Sitzungsreaktivierung. Privater Helper/Checkpoint entfernt.

130 gemeinsame Fluttertests,33PostgreSQL- und14SQLitefälle in separaten Läufen
bestanden; Ruff/Flutteranalyse/Diffprüfung sauber. Tatsächlicher Browserdurchlauf
mit lokalem ausschließlich künstlichem Kind und Elternkonto, Provider abgeschaltet;
hell/dunkel, Köpfe/Details/Filter/Meldungsziel/Lesemarkierung/Settings/Logout geprüft.
Browser tatsächlich1101×884; mobile Großschriftprüfung als Widgetnachweis.
Lokale Zugangsdaten, Testdatenbank und private Anbieterdiagnosekopien entfernt.

Web und signierte APK/AAB78 gebaut; Bundle/Paket/Version/Signierer geprüft,
Play ohne APK-Installerberechtigung. Geheimnisprüfung652 Quellen/Assets und344
Archiveinträge/14 bestehende Secretquellen ohne Treffer; Provider-Key/Base640.
Vor Entfernung lokaler Testzugänge zusätzlicher Quellencheck mit deren Passwörtern
sauber. Öffentlicher APK-Voll-Download stimmt überein. APK75400770Bytes, SHA256
`fbc6f8eb5c8a298cd7a5ee357ce7c7f44db1b7620d8a47587dfe281e46eff7f6`;
AAB70817705Bytes, SHA256
`15494379e49c3290cf84a49b02bf6172f8277a1706bece59825ea595017142ab`.
API/Worker/Caddy aktiv, Sicherung erfolgreich, Schema0025, Providerrevision29,
Paid/Economy/ZDR unverändert. Rückweg:77 (`20261021T150342Z-14fe339`), gleiches
Schema; keine DB-Rücksetzung. Kein Play-Upload, keine neue physische Android-
oder vollständige WCAG-/Lernwirkungsabnahme.

---

# Produktionsstand1.18.3+77 ·21.10.2026

Live: `20261021T150342Z-14fe339`, Produktcommit
`14fe339f579b84c85d54ee31cbb4f33d49d98569`, main gepusht. Vollständiger künstlicher
Nachmittag mit echter OpenRouter-KI über normale Produktionskonten und tatsächliche
Browserbedienung vom Fotoimport bis zum Elternbericht durchgeführt. Keine Antworten
oder Änderungen im echten Kinderprofil. Ausführliche Ereignismatrix, Grenzen und
Schnittstellen: [AFTERNOON_EVALUATION_2026_10_21.md](AFTERNOON_EVALUATION_2026_10_21.md).

- Hausaufgaben: wörtlicher begrenzter Nachbaraufgaben-Kontext für „ersten Schritt“,
  sinnvolles lokales Bruchfeedback und abgeglichener Speicherfehler. Bewusster
  Übergang „Mit neuen Aufgaben prüfen“ nutzt bestätigte Quelle und normale Reservierung.
- Neue Bruchfragen werden vor der KI exakt geplant; Originale/alte Fragen bleiben
  ausgeschlossen. Erweiterungseinführung enthält ein anderes belegtes Beispiel,
  keinen vollständigen Additionsweg. Zielzuordnung bleibt serverseitig gebunden.
- Eine bewusst erneut abgegebene gleiche falsche Antwort erhält nach quittiertem
  Feedback einen neuen Versuch. Unklare Transportwiederholungen bleiben idempotent.
- KI-Erklärung mit gezeigter Lösung → andere Prüfaufgabe speichert eine eigene
  quellengebundene Zurückstellung. Originalfehler bleiben Übungsbedarf; neuer und
  alter Kurzplan schließen bewusst lokal ab, ohne weitere Antwort/Reparaturplanung.
  GET bleibt lesend, letzte Rückmeldung bleibt bis Weiter sichtbar. Verbrauchte
  Planfreigabe wird vor POST nochmals geprüft; gespeicherte Hilfe bleibt erreichbar.
- Elternbericht erhält nur beantwortete Zielaggregate. Live:6 Aufgaben,9 Versuche,
  2 selbstständig,2 unterstützt,2 weiter üben,0 unklar;3 Runden abgeschlossen.
  Alle6 dem tatsächlichen Teilziel Erweitern zugeordnet. Eltern-KI grenzt von
  Addition ab und plant Verstehen→neue eigene Aufgabe→späterer Abruf; keine
  erfundene dauerhafte Beherrschung. Drei Hausaufgabenhäkchen zählen separat.

Wirklicher Verbrauch:16 fertige KI-Aufrufe,0,088137USD,0 unbekannte Kosten;
Luna/Sol im unveränderten Economy-Modellmix, Providerrevision29, Paid/ZDR erhalten.
Alle Fehleraufrufe/Rückblicke enthalten.12:56 gespeicherte Aktivität;15-Minuten-
Mindestziel korrekt noch offen, keine Warte-/Buildzeit oder Uhrverstellung.

Abschlussregression77:79 gemeinsame PostgreSQLfälle,21 unterschiedliche gezielte
Entscheidungsplanfälle unter PostgreSQL und21 im vollständigen SQLite-Replay
bestanden;35 abschließende Flutterfälle sowie Ruff/Analyse/Diffprüfung grün.
Frühere featurebezogene Prüfungen im Bericht separat, nicht aufsummiert.
Web und signierte APK/AAB77 gebaut, Bundle/Signer/Paket/Version geprüft;
Play ohne APK-Installerberechtigung. Geheimnisprüfung649 Quellen/Assets und344
Archiveinträge/16 bekannte Secretquellen ohne Treffer; Provider-Key/Base64 ebenfalls0.
Öffentlicher APK-Voll-Download stimmt überein. APK75236762Bytes, SHA256
`55d7cff65a4b86c6ecce83eab71e22b7ff7f990a8bf26f4234ea91ac94999238`;
AAB70583093Bytes, SHA256
`d0e5cdf0a8ee2e4b1cb55e41934a51434fb9bf37b934da9debc0703a32436d93`.
API/Worker/Caddy aktiv, Sicherung erfolgreich, Schema0025.
Rückweg:76 (`20261021T142904Z-d8e78c4`), gleiches Schema; keine DB-Rücksetzung.
Kein Play-Upload. Kein physischer Androidkamera-/vollständiger WCAG-/Langzeitnachweis.

Bereinigung abgeschlossen nach ausdrücklicher Betreiberfreigabe: genau der
künstliche Testhaushalt über DELETE /account gelöscht. Familie, Kind, beide
Testbenutzer, Foto, drei Lernrunden, Elternberichte und private Usage jeweils0;
globale Aufruf-/Kostenstände erhalten. Zwei signierte Löschjournalbelege für
Familie/Kind unabhängig geprüft. Lokale Testzugangsdaten entfernt. Keine neue
Codeänderung/Bereitstellung; Produktionsversion77 bleibt unverändert.

---

# Produktionsstand1.17.3+73 ·21.10.2026

Live: Release `20261021T120244Z-1b014ea`, Produktcommit
`1b014ea7cf47fb3346ae9a4997d941555d34a150`, main gepusht. Erneute Eltern-/
Kinderprüfung mit drei Agenten und tatsächlicher Browserbedienung abgeschlossen.
Details und Fallmatrix: [APP_REVIEW_2026_10_21.md](APP_REVIEW_2026_10_21.md).

- Hausaufgaben behalten Auswahl, Entwurf und Checkliste bei Unterbrechung und
  parallelem Speichern. Übersicht und Hinweis-Cache funktionieren auch bei über
  hundert Gesprächsschritten. Alte Hilfen/Häkchen nach Quellenkorrektur bleiben
  getrennt. Neu: echter Checklistenstand und „Nächste offene Aufgabe“.
- Eltern können Themen ausdrücklich erledigen. Ältere offene Runden und
  gespeicherte KI-Kurzpläne werden vor der begrenzten Vorschau gesucht. Kein
  vorheriger Kindername während Nachladen; Kompass setzt GET-Polling nach Rückkehr fort.
- Alte Übung ohne gespeicherte Quellenrevision zählt weiterhin als Übung, jedoch
  nicht als aktueller Kompetenznachweis für inzwischen korrigierten Stoff.
- Android-Kinderkamera erhält eine kontogebundene Hausaufgaben-/Heft-Rückkehrhilfe.
  Bewusster Zuschnitt vor Abgabe. RAM-Fotos/Marker auch bei direktem Kontowechsel
  entfernen; asynchronen Heftimport an stabilen Eigentümer binden.
- SQLite-Migration0025 mit Inline-Referenz repariert; gefüllte Auftrags-/Runden-/
  Antwortketten beim Hin- und Rückweg erhalten. PostgreSQL-Pfad unverändert.

133 gemeinsame Backendfälle auf isoliertem PostgreSQL16,70 abschließende Widget-
fälle sowie Ruff/Flutteranalyse und Diffprüfung bestanden. 1035Fluttertests bei
Integration vollständig grün; späterer erneuter Gesamtlauf nach1014 bestandenen
Fällen durch SIGTERM beendet, ausdrücklich kein zweiter behaupteter Gesamterfolg.
Zusätzlicher ursprünglicher SQLite-0001→head-Replay bestanden. Überlappende Läufe
nicht addieren. Keine neuen OpenRouter-Aufrufe oder Testantworten im echten Profil.

Browser: bestehender produktiver Kinderzugang nur lesend (Heute/Kurzplan, Lernen,
Wörter, Hefte, Hausaufgaben). Schreibende Eltern-/Kinderprobe ausschließlich lokal
mit künstlichen Daten,390px/1280px und hell/dunkel. Auswahl/Entwurf/Häkchen nach
Reload, Kontowechsel, Themenabschluss und erneutes Anzeigen tatsächlich bedient.
Eltern sehen den ungesendeten Entwurf nicht. Screenshots unter artifacts/review73/.
Kein Providerzugang/Worker in der lokalen Vorschau. Keine neue physische Android-
Kamera-, vollständige WCAG- oder Lernwirkungsabnahme. Grenzen in HOMEWORK.md.

Web und signierte Direct-APK/Play-AAB73 erfolgreich gebaut; Signierer/Paket/
Version/Bundletool und Play ohne APK-Installerberechtigung separat geprüft.
Geheimnisprüfung643 Quelldateien/Assets und344 Archiveinträge,14 bekannte Secret-
Quellen,0 Treffer; zusätzlicher Provider-Key-/Base64-Abgleich ebenfalls0.
Öffentlicher APK-Voll-Download stimmt mit dem lokalen Artefakt überein.
APK75171226Bytes, SHA256
`41504ac7bbaf8904edd640942ee93675f8af0e15ead00a18e73524110db72195`;
AAB70562027Bytes, SHA256
`be08066956b0736295e2146fc77a3546563cf5c442e80705fc1aa86341c1ffe6`.
Kein Play-Upload. API/Worker/Caddy aktiv, reguläre Sicherung erfolgreich,
Schema0025; OpenRouter-Providerrevision29, Paid/ZDR/Freigaben erhalten.
Rückweg: vorherige72 (`20261021T094655Z-019d20e`), gleiches Schema0025,
keine Datenbankrücksetzung für diesen Coderückweg. Andere Dienste nicht geändert.

---

# Produktionsstand1.17.2+72 ·21.10.2026

Live: Release `20261021T094655Z-019d20e`, Produktcommit
`019d20e5b0d288698530584ab349e8a126a1c51d`, main gepusht. Elternbereich erweitert:

- Lernkompass aus sämtlichen gespeicherten Aufgabenbelegen mit getrennten
  Kategorien für selbstständig, unterstützt/erneut, weiter üben und unklar.
  Vorsichtige KI-Einschätzung, nächste Überprüfung und Berichtshistorie.
- Regelmäßige KI-Auswertung pro Kind ausdrücklich aktivierbar, bei neuen Belegen
  höchstens täglich im bestehenden Budget. Kein Modellaufruf beim Lesen.
- Detaillierter Lernplan mit KI-Schwerpunkten, tatsächlichen gespeicherten
  Kurzplänen, Wochenvorschlag und eigenen Elternaufträgen aus bestätigten Seiten,
  vorhandenen Übungen oder neuen Themen ohne Foto. Vorbereitung bewusst und
  idempotent; vorhandene Runden/Antworten bleiben erhalten.
- Eltern-Hausaufgaben je Kind mit Filtern, Originalfoto, Teilaufgaben und
  abgegebener Begleitung. Häkchen sind Selbstangaben; ungesendete Entwürfe bleiben
  kindprivat. Gemeinsame Bereichsauswahl, direkte Themenbelege ohne Berichtsschleife.

Details, Schnittstellen, gespeicherte Daten, regelmäßige Freigabe, Kosten und
konkrete Testspuren: [PARENT_LEARNING.md](PARENT_LEARNING.md).
Der Hausaufgabenbereich für Kinder und die fünf echten künstlichen Foto-/KI-
prüfungen aus69 bleiben enthalten, siehe [HOMEWORK.md](HOMEWORK.md).

Eigener künstlicher regulärer Produktionshaushalt: neues Thema, bestätigte
Fotoquelle, Übernahme aus Übung, selbstständige/unterstützte Antworten,
Elternauswertung und regulärer Worker tatsächlich mit OpenRouter getestet.
9Aufrufe inklusive Rundenrückblicken und der ersten ungeeigneten Zusammenfassung,
41066µUSD=0,041066USD; unbekannte Kosten0. Budget0,25USD/12Aufrufe und
Providerrevision29 erhalten. Keinerlei Testantworten im echten Kinderprofil.
Produktions-Testkonto normal gelöscht und Konten/Quellen/Runden/Berichte separat
nachgeprüft; Verbrauch und Löschjournal erhalten. Private QA-Zugangsdaten entfernt.

Zwei echte Befunde korrigiert: einfacher Rechenterm81−35 mit Antwort0 blieb zuvor
unklar; `subject_rules_v5` prüft vollständige Zweizahlterme samt Musterlösung exakt.
Ausdrückliche Nachprüfung korrigiert nur das Urteil mit Audit, keine neue Antwort
oder verlorene Hilfe, null Anbieteraufrufe. Allgemeine Aufgabenanweisungen werden
nicht mehr an Planungs-/Elternberichte angehängt; Strategie `parent-review-2`.
Die neue echte KI-Auswertung bleibt bei den gespeicherten Belegen. Die regelmäßige
Folgeauswertung nimmt die korrigierte Datenlage als Übungsschwerpunkt auf.
Nur der Tagesabstand des künstlichen Kindes wurde für diese Ablaufprüfung
simuliert, keine globale Zeit, Budget- oder Versuchszähleränderung.

1022Fluttertests bei Integration bestanden; abschließend37 betroffene Widgettests,
Flutteranalyse,19Elternfälle auf PostgreSQL16 sowie Ruff sauber. Zusätzlich149
Bewertungs- und107Adapter-/Planungsfälle bestanden, bei Integration162Backendfälle;
überlappende Läufe nicht addieren. Migration0025 tatsächlich bis Head geprüft.
Browser: Elternformular, einheitliche Navigation, Wochenplan, Bericht→Themenbelege,
Hausaufgabenfilter/Originalfoto,390px/1280px und hell/dunkel. Ausschließlich lokale
Bedienprobe mit echten künstlichen Produktionsantworten; keine zusätzliche lokale
KI. Die kurzlebige Vorschau hat keinen Providerzugang oder Worker.
Keine neue physische Android-, vollständige WCAG- oder Lernwirkungsabnahme.

Web und signierte Direct-APK/Play-AAB72 gebaut und separat validiert, kein Play-
Upload. Aktuelle API/Worker/Caddy gesund, Schema0025, reguläre Sicherung erfolgreich.
Rückweg: vorherige71 (`20261021T092711Z-31a1c55`), gleiches Schema0025;
für diesen Coderückweg keine Datenbankrücksetzung. Andere Dienste nicht geändert.
APK75072918Bytes, SHA256
`e6aa6c235d8549029b1838c489553a385152cfffc251ccd56136849d5d6ce9f6`;
AAB70506697Bytes, SHA256
`2d22fc25345c2ae09028e393f362ce1238920f31fd1d77dbb81fdbdfb6c9c094`.
Signierer/Paket/Version/Bundletool geprüft, Play ohne APK-Installerberechtigung.
Öffentlicher APK-Voll-Download entspricht dem lokalen Release.

---

# Produktionsstand1.16.2+69 ·21.10.2026

Live: Release `20261021T073101Z-56b8849`, Produktcommit
`56b884926d848908f43cf1176b68a4476ec1f475`, main gepusht. Neuer Kinderbereich
Hausaufgaben mit geschütztem Fotoimport, geprüfter Aufgabenübersicht, gestuften
Hilfen, eigenen Fragen und lokalem Rechencheck. Entwürfe/Phasen bleiben gespeichert;
Selbstcheck ist kein Kompetenznachweis. Details: [HOMEWORK.md](HOMEWORK.md).

Fünf tatsächlich generierte und visuell geprüfte Fotos im eigenen künstlichen
regulären Produktionshaushalt mit realem OpenRouter getestet. OCR, Aufgabenübersicht,
Erklärungen sowie sämtliche Hilfearten und Rückfragen fachlich geprüft. Zwei dabei
aufgedeckte Ablehnungen behoben, Fehlversuche/Kosten erhalten.26 Aufrufe über Luna,
10856µUSD=0,010856USD, keine unbekannten Kosten, keine Kontingentlockerung.
Testhaushalt einschließlich Quellen/Gesprächen/Sitzungen normal gelöscht und verifiziert.
Keine Testantworten im echten Kinderprofil. Bildprompts/Transkripte/Prüfungen liegen
lokal unter `artifacts/homework-20261021/`; keine Zugangsdaten im Prüfmaterial.

Abschließend83Backendtests auf PostgreSQL16, zehn Hausaufgaben-Widgettests,
Ruff/Flutteranalyse und Diff-/Geheimnisprüfung sauber. Bei Integration998Fluttertests
bestanden; keine Addition überlappender Testläufe. Browserimport mit echtem Zuschnitt,
Quellenbestätigung, Entwurf nach Reload, Aufgabenwechsel, Fotozoom und hell/dunkel
auf390px sowie Desktop geprüft (isolierte lokale Bedienprobe mit echten künstlichen
Produktionsantworten). Fünf Produktionsuploads über die normale API. Keine neue
physische Android-/vollständige WCAG-/Lernwirkungsabnahme oder Play-Veröffentlichung.

Schema0024, API/Worker/Caddy gesund, reguläre Datensicherung vor Aktivierung.
Rückweg: vorherige68 (`20261021T071825Z-86561e6`), gleiches Schema; keine
Datenbankrücksetzung für diesen Coderückweg. Andere Dienste unverändert.
APK74712362Bytes, SHA256
`9d7074735f241c0cb48abb6f372246b9f7135cdde95c81ba68982ded120045f5`;
AAB70286004Bytes, SHA256
`359c152040551e054e79f1846dd708a88a56a9ba3dce1c47f31bf912bb8e0d0f`.
Signierer/Paket/Version/Bundletool geprüft, Play ohne APK-Installerberechtigung.
Öffentlicher APK-Voll-Download entspricht dem lokalen Release.

Der damals offene Elternzusatzauftrag ist im oben dokumentierten aktuellen Stand umgesetzt.

---

# Produktionsstand1.15.1+66 ·21.10.2026

Live: Release `20261021T045349Z-394d122`, Produktcommit
`394d122f273ab5fae6b240bc8c56139cbc9dc0ef`, nach main gepusht.
Healthcheck status=ok/1.15.1; API, Worker und Caddy aktiv. Vorgeschaltete
Datenbanksicherung erfolgreich, Schema0023 unverändert.

Eindeutige Zahlenantworten auf die begrenzt erkannten Rechteckflächenaufgaben
werden rechnerisch gegen Länge × Breite und die Musterlösung geprüft. Eine
bereits in der Frage vorgegebene Flächeneinheit muss nicht nochmals eingegeben
werden; eine ausdrücklich verlangte ausgeschriebene Einheit bleibt erforderlich.
Die Dreiecksprüfung verwendet dieselbe Unterscheidung. Falsche Zahlen/Einheiten
bleiben falsch, widersprüchliche Musterlösungen unklar. Keine allgemeine
semantische Textaufgabenprüfung behauptet. Details und künstliche Beispiele:
[AREA_ASSESSMENT_2026_10_21.md](AREA_ASSESSMENT_2026_10_21.md).

Die ausdrücklich beauftragte konkrete offene Bewertung im freigegebenen Haushalt
mit Regelversion subject_rules_v4 historisiert korrigiert und anschließend in
einer neuen Transaktion verifiziert. Originalantwort, Hilfe, Datum, Aufgabe,
Versuchsanzahl, Rundenstatus und Lernzeit erhalten; Lerncontroller und Lernstand
neu projiziert. Keine Testantwort und kein zusätzlicher Provideraufruf. Zugriff,
Korrektur und Abschlussprüfung separat auditiert; private Diagnosekopien entfernt.

223 gezielte Backendtests auf isoliertem PostgreSQL16 bestanden; darunter neue
Zahlen-/Einheiten-/Musterlösungsfälle, neue geführte Antworten, idempotente
Nachkorrektur mit und ohne Hilfe, Brüche, Lerncontroller, Feedback und Fortschritt.
Ruff/Flutteranalyse sauber. Web, signierte Direct-APK und Play-AAB66 gebaut und
validiert. Keine neue physische Android-/Lehrplan-/WCAG-Abnahme, kein Play-Upload.

APK74499062 Bytes, SHA256
`530b4911de1b00a77344b7a2cf1e813172d146aef5b4ddcbf90c8ac07748227f`;
öffentlicher Voll-Download, Manifest und Version identisch.
AAB70091416 Bytes, SHA256
`28ab73f7367379121a0692d6fbf5daf47977bdaad8f2686320397ed2ad6cd79a`;
Bundletool, Paket, Signierer und Version korrekt, keine Play-Installerberechtigung.
619 Quelldateien,344 Archiveinträge und98 Webdateien gegen bekannte Geheimnisse
geprüft, keine Treffer. Modellmix, Budgets, Providerrevision und Grenzen unverändert.

Rückweg: `/opt/schulpilot/releases/20261020T184923Z-872d505` (1.15.0+65),
auch als previous erhalten. Kein Datenrestore über die neue Korrektur oder spätere
Antworten/Löschungen; vor Code-Rollback neue KI-Aufträge anhalten und aktive
kontrolliert abarbeiten. Der alte Prüfer besitzt die neue Flächenregel noch nicht.

---

Nachfolgend historische Produktionsnachweise.

# Produktionsstand1.15.0+65 ·20.10.2026

Live: Release `20261020T184923Z-872d505`, Produktcommit
`872d505375894ffd4e1c173af5a1d6513aff0e75`. Öffentlicher Healthcheck status=ok/1.15.0;
API, Worker und Caddy aktiv. Caddy-/Datenbanksicherung vor Aktivierung erfolgreich,
Schema0023 unverändert. Produktcommits nach main gepusht; nachfolgender
Dokumentationscommit ändert keine Releaseartefakte.

## Ergebnis

Zwei vollständige Erscheinungsbilder derselben Cyber-Anwendung: Dunkel und Hell,
lokal umschaltbar und nach Neustart erhalten. Neue Kinder-Lernstation mit eigener
künstlicher Buchdrohne, kompaktem Fotoeingang, einer nächsten Hauptaktion und
klar getrenntem Plan/Postfach. Lernen, Wörter, Nachrichten und Konto verwenden
einheitliche Navigation. Eltern sehen tatsächliche Übungsbelege und Handlungsbedarf;
Admins Triage, Kosten und Betriebsaktionen. Adminlogin und alte Startlinks führen
unmittelbar ins Betriebscockpit. Lokale Nunito-/Space-Grotesk-Schriften mit OFL,
keine Schrift-CDN-Abfrage und keine neue Bilddienstintegration in der App.

Zustandsbehaftete Lernsteuerung mit vorhandenen Attempts/Activities als Belegen,
endlichem Kurzplan, geprüfter Bruch-Vorwissensverzweigung, getrenntem langfristigem
Lernmodell, optionaler begrenzter Modellentscheidung über vorhandene Inhalte,
echten lokalen Ressourcen und Medienrückkehr. Nach Erklärungen bewusst neue
Verständnisfragen; unklare Bewertung bleibt offen. Gezeigte Hilfe und ursprüngliche
Antworten werden nicht für bessere Statistiken überschrieben. Entwürfe,
Planrevisionen und Feedback überleben Unterbrechungen; ein Reload erzeugt keine KI.

OpenRouter bleibt aktiv, Revision29, bezahlter Mix Luna/Sol mit economy_mode,
Medium, ZDR und unveränderten Kosten-/Token-/Systemgrenzen. Keine Astra-Freigabe,
kein automatischer Fallback. Kontodatenschutz zusätzlich gespeichert und nach
Reload geprüft: ZDR, keine Trainingsfreigabe oder Observability-Inhaltsspeicherung.
Ein zusätzlicher künstlicher normal reservierter Entscheidungsjob erfolgreich,
erfasste Kosten0,000514USD; gesamte bisherige künstliche Evaluation0,238013USD
innerhalb0,25USD. Keine echte Kinderantwort oder echte Seite an einen Testanbieter.

## Nachweise und Grenzen

983 Fluttertests im vollständigen Lauf bestanden; danach201 Renderer-/Design-/
Lernraumprüfungen,11 gezielte Abschlussprüfungen und23 Router-/Adminprüfungen
bestanden. Mengen überschneiden sich. Flutteranalyse und Ruff sauber.

Backend: vollständige eindeutige Abdeckung aller1269 Fälle in75 Dateien auf
isoliertem PostgreSQL16. Lange Prozesse endeten vor Abschluss mit143; ausdrücklich
kein sauber beendeter monolithischer Gesamtlauf behauptet. Nachgewiesen sind625
abgeschlossene serielle Fälle des unterbrochenen Teillaufs,634 Fälle mit fertigem
JUnit-Bericht und10 separat erfolgreich nachgeprüfte Restfälle. Reihenfolge,
Identität und Überschneidungsfreiheit gegen die vollständige Collection geprüft;
kein Fehler/Skip in dieser finalen Fallabdeckung. Der vorher aufgedeckte direkte
FastAPI-Header-Defaultfehler wurde behoben und unter anderem mit43 Tutor-/
Adaptivregressionen nachgeprüft. Rohprotokolle/Abdeckungsnachweis unter artifacts.

Browser: künstliche Kinder-/Eltern-/Adminprofile bei390px und1280px in beiden
Varianten geprüft. Bruchspur1/3+1/6 →2/9 →gezielte Gleichwertigkeitsprobe →
visuelle Erklärung →neue1/4+1/8 →3/8 tatsächlich bedient. Rückmeldung nach Reload
erhalten; Elternprojektion zeigt3 Aufgaben/3 Versuche,2 selbstständig gelöst und1
weiter zu üben, offene Runde separat. Adminentwurf über Reiter-/Designwechsel
sichtbar erhalten, ohne Speichern/Providerprüfung. Verkauf/Push rein lesend geprüft.

Produktion nach Deployment: bestehende Kindersitzung erhalten, neue Heute-Seite in
beiden Varianten und Lernen/Wörter/Hefte/Konto gezeigt, Clientversion1.15.0+65 in
App-Informationen bestätigt. Keine Testantwort, Nachricht, neue Lernrunde,
Providerprüfung oder Pushnachricht im echten Haushalt ausgelöst. Browser wieder
auf Heute im dunklen Design bereit. Temporäre künstliche Konten/Datenbanken entfernt, lokalen API-/Workerprozess
beendet und Testtab geschlossen.
Keine vollständige physische Android-/TalkBack-/FCM-Zustellabnahme, gesamte
Klasse1–13-Lehrplanabnahme oder gemessene Lernwirkung behauptet.

Web, signierte Direct-APK und Play-AAB65 gebaut und validiert; kein Play-Upload.
APK74499066 Bytes, SHA256
`9e267af37540a0822d858ba8c70771581d5a85c193e4478449ded8a7c054de7f`.
Öffentlicher Download und Manifest vollständig identisch. AAB70090963 Bytes,
SHA256 `fa87bafcfa657b33ad8972f2501ff4db70144b43608667e7b87cf208c7d14a52`;
Bundletool, Version, Paket und Signierer korrekt, keine Play-APK-Installerberechtigung.
617 Quelldateien,344 Archiveinträge und98 Webdateien gegen bekannte Geheimnisse
geprüft, keine Treffer; Provider-Schlüssel zusätzlich roh/base64 geprüft.

Architektur/Funktionen/Schnittstellen/Beispielspur:
[LEARNING_CONTROLLER_2026_10_20.md](LEARNING_CONTROLLER_2026_10_20.md).
Design, Recherche und Assetherkunft: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md),
[CHILD_WORKSPACE_2026_10_20.md](CHILD_WORKSPACE_2026_10_20.md),
[PARENT_WORKSPACE_2026_10_20.md](PARENT_WORKSPACE_2026_10_20.md),
[ADMIN_WORKSPACE_2026_10_20.md](ADMIN_WORKSPACE_2026_10_20.md).

Rückweg: `/opt/schulpilot/releases/20261020T160732Z-421e0ea` (1.14.3+63),
auch als previous erhalten, Schema0023. Vor Code-Rollback neue KI-Aufträge
anhalten/aktive abarbeiten und Löschjournal beachten. Keine Datenrücksicherung
über neuere Antworten oder Löschungen. Restorewerkzeuge mindestens1.14.2.

---

Nachfolgend historische Produktionsnachweise.

# Produktionsstand 1.14.2+62 · 20.10.2026

Live: Release `20261020T132931Z-091b791`, Produktcommit
`091b791130abc898585aec0fbedf9d84284251cb`. Health status=ok/1.14.2, API/Worker/Caddy aktiv,
aktuelle Sicherung erfolgreich, Schema 0023 unverändert. Produktcode nach main
gepusht; anschließender Dokumentationscommit ohne Clientänderung.

Elternübersicht neu geordnet: gespeicherte Aufgaben/Versuche und selbstständige
oder unterstützte Ergebnisse zuerst, Lernzeit daneben, Fach-/Themenrückweg,
Pflichtaufträge/aktuelle Runde und spätere Festigung getrennt. Gemeinsame acht
Bereiche mit geordneter Desktopnavigation und mobiler Auswahl. Plan, Noten, Hefte,
Wörter, Verlauf und Nachrichten klar erreichbar; Einstellungen nach den Inhalten.
Quellen, Antworten, Familienrechte und tatsächliche Serversekunden erhalten.

Alle Foto-/Prüflöschwege verwenden die gezählte, revisionsgebundene Seiten-/
Runden-/Antwortvorschau. Alte Tages-DELETEs mit gespeicherten Runden sperren.
Historische Auftrags-/Sprachprojekt-/Wortrevisionen, Folgeübungen, Aufbewahrung
und Restore alter Materialjournale berücksichtigen dieselbe Kaskade.
Im ausdrücklich geprüften Haushalt vier alte quellenlose Testaufträge entfernt;
keine verwaiste Runde vorhanden, keine weitere quellenlose Aufgabe übrig. Zehn
Seiten und sechs gültige Runden erhalten. Audit und Löschjournal publiziert.
Keine neuen Produktivantworten, Nachrichten, Noten oder Inferenzaufträge.

898 Fluttertests vollständig bestanden, 22 passende Tests nach letzter
Textkorrektur zusätzlich (überlappend). 130 isolierte PostgreSQL-Prüfungen zur
Löschung; zuvor 69 PostgreSQL-Prüfungen für Elternprojektion/Noten/Sammlungen/
Mindestzeit. Flutteranalyse/Ruff sauber. Alle Elternbereiche und verschachtelte
Rückwege live gelesen; finale Übersicht/Plan bei 390 px und Desktop 1101 px
nachgeprüft. Keine vollständige physische Android-/TalkBack-/WCAG-Abnahme oder
gemessene Lernwirkung behauptet.

Web/Direct-APK/Play-AAB 62 vollständig gebaut und validiert, finaler Build Status 0
nach unbenutztem Zwischenlauf Status 143. APK 72.383.151 Bytes, SHA256
`f3638c645b1f03b3bcbf2485fb8f7ecb5f27e69c5297a19f9a06979449003b0d`.
Öffentlicher Download/Manifest identisch. AAB 68.134.391 Bytes, SHA256
`739e3a559c68ee8499ef3cadb4ac8c5d69c7dee24bcb4efa6225255a1c9e39e8`; Version/Signatur/Bundletool
korrekt, keine Play-APK-Installerberechtigung, kein Play-Upload. Bekannter
Provider-Schlüssel in 451 Quelldateien, 334 Archiveinträgen und 93 Webdateien
nicht gefunden. Anbieterrevision/Kontingente/Schlüsselablage unverändert.

Details: [PARENT_OVERVIEW_2026_10_20.md](PARENT_OVERVIEW_2026_10_20.md),
[SOURCE_DELETION_2026_10_20.md](SOURCE_DELETION_2026_10_20.md).
Rückweg `20261020T124231Z-8bbd152` (60), Schema 0023. Neue KI-Aufträge anhalten/
aktive abarbeiten; Journalpublikation vor Code-Rollback prüfen. Restorewerkzeuge
**mindestens 1.14.2**, damit typisierte Auftragslöschungen angewendet werden.
Keine Datenrücksicherung über neuere Antworten oder Löschungen.

---

Nachfolgend historische Zwischenstände; aktuell ist der Kopf oben.

# Produktionsstand 1.13.0+59 · 20.10.2026

Live: Release `20261020T115520Z-0720f90`, Produktcommit
`0720f9093ceb6768135db799097a794f53b13b2b`. Healthcheck status=ok/Version 1.13.0,
API/Worker/Caddy aktiv, Sicherung erfolgreich, Schema 0023 unverändert. Produktcode
nach main gepusht; anschließender Dokumentationscommit ohne Clientänderung.

Erneute Menüprüfung umgesetzt: Hefte startet für Kinder mit vorhandenen Seiten,
Wörter mit klaren Lade-/Leer-/Fehlerzuständen und Filterrückweg, Nachrichten direkt
lesbar, veraltete/fremde Verweise ausgeblendet, leere Vorbereitungsmeldungen und
bestätigte Wort-Prüfaufforderungen entfallen. Lernliste ohne doppelte Statusangabe,
Geräteaktionen eindeutig und bei großer Schrift erreichbar. Normale Handschrift
bleibt Eingabe. Formeln in Tabellen verursachen keinen intrinsischen Layoutfehler;
Code/Matrizen bleiben zusammen. Neue Erklärung und Schrittwechsel beginnen oben;
Überschrift bleibt beim ersten Inhalt. Darstellung benötigt keine zusätzliche KI.

889 Fluttertests vollständig bestanden, Analyse/Ruff sauber. 81 PostgreSQL-
Prüfungen plus 19 Nachprüfungen für den finalen Serverstand (überschneidende
Mengen). Web-Nachprüfung mit künstlichen Daten bei 200 %, Live-Wortsuche mit
Rücksetzen, Hefter, Nachrichtenreader, Konto, Neuigkeiten und Lernliste geprüft.
Keine vollständige Live-Abnahme aller Eltern-/Adminaktionen, Smartphone-/TalkBack-
Zertifizierung oder gemessene Lernwirkung behauptet.

Endbestand: zehn bestätigte Seiten, sechs Einheiten (fünf fertig, eine pausiert),
21 Antwortversuche, keine laufende Verarbeitung. Keine neuen Testantworten oder
Nachrichten gesendet. OpenRouter/Revision 29 und Grenzen unverändert; keine
eigenen neuen Inferenzaufträge dieser Menüprüfung. Alte Kosten/Unklarheiten erhalten.

Web, signierte APK und Play-AAB 59 gebaut/validiert, kein Play-Upload. Vollständiger
Wiederholungsbuild Status 0 nach einem Abschlussstatus 143; Artefaktprüfungen danach
erfolgreich. APK 72.284.767 Bytes, SHA256
`8b5c2065cffbde69b5de4a5a61bb1f4bdcf2f288e4038e0ff4b409b9ddf92bbb`.
Öffentlicher Download/Server/Manifest identisch. AAB 68.077.470 Bytes, passende
Version und Signatur, keine Play-Installerberechtigung. 445 Quelldateien und beide
Android-Archive auf den bekannten Provider-Schlüssel geprüft, kein Treffer.

Details, Grenzen und Belege: [MENU_REVIEW_2026_10_20.md](MENU_REVIEW_2026_10_20.md).
Kompatibler Rückweg `20261020T104607Z-f3a631a` (58), Schema 0023. Neue KI-Aufträge
anhalten/aktive abarbeiten, vorhandenes activate.py --rollback-compatible; kein
Restore über neue Antworten oder Löschjournal und kein stiller Providerwechsel.

---

Nachfolgend historische Zwischenstände mit damaligen Artefakten/Kosten/Rückwegen.
Aktuell ist der Kopf oben.

# Historischer Produktionsstand 1.12.2+58 · 20.10.2026

Live: Release `20261020T104607Z-f3a631a`, Produktcommit
`f3a631ac6e7876e8cbd4a7bb755e2385cda449f6`, main gepusht, Schema 0023.
Healthcheck status=ok/Version 1.12.2; API, Worker und Caddy aktiv. Sicherung
vor Aktivierung erfolgreich. Web, signierte Direct-APK und Play-AAB 58 gebaut.
Der abschließende Dokumentationscommit verändert die gebauten Clientquellen nicht.

Die Nutzerkorrektur ist umgesetzt: normale handschriftliche Schulhefter bleiben
die Eingabe. Formeln, Tabellen, Code und begrenzte Fachgrafiken werden direkt in
Aufgaben, geöffneten Hilfen, Rückmeldungen und Heft-Hilfe lesbar dargestellt.
Keine gedruckten Ersatzhefte hochgeladen. Lokaler Formelsatz benötigt keine
zusätzlichen KI-Aufträge. Zehn neue Grafikfamilien ergänzen die bisherigen Typen;
Quellenbindung und Offenlegungsstufen bleiben erhalten. Verlorene Hinweisgrafiken,
Tippscrollposition, gesprochene TeX-Steuerzeichen und doppelte Großschriftskalierung
behoben. Umfang und Grenzen: [SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md).

870 Fluttertests vollständig bestanden, 277 gezielte Tests, Analyse/Ruff sauber.
294 PostgreSQL-Integrationsprüfungen und 63 gezielte Nachprüfungen bestanden
(überschneidende Mengen). 127 Formelfälle/28 neue Grafikfälle; keine vollständige
Lehrplan-, Smartphone- oder TalkBack-Abnahme behauptet. Tatsächlicher
Handschrift-/OCR-/Formelhilfetest im normalen Kinderzugang erfolgreich, gespeicherte
Hilfe auf 58 ohne neue KI wieder geöffnet. Danach zehn bestätigte Seiten, fünf
abgeschlossene Runden, 18 beantwortete Aufgaben und 21 Antwortversuche.

OpenRouter-Sparbetrieb Revision 29 unverändert: Luna für kleine OCR/Hilfen,
Sol für umfangreicheren Bedarf; feste Upstreams, kein Fallback, Grenzen erhalten.
Zwei zusätzliche echte Aufträge: 0,001876 USD berichtet. Mit vorheriger Abnahme
0,225889 USD berichtet; einschließlich konservativer Obergrenze der alten
ungeklärten 400er höchstens 0,239375 USD, unter 0,25 USD. Keine Aussage über
unbekannte Kontogebühren oder Bildgenerierungs-/Codex-Kosten.

APK 58: 72.284.703 Bytes, SHA256
`7a3f2e082573174e07b2f3ac0feb70a36ce7478cbcaf5f7be81c5fc3dbb9a7bf`.
Öffentlicher Download/Serverdatei/Manifest abgeglichen; AAB 68.025.009 Bytes,
Signaturprüfung erfolgreich, kein Play-Upload. Beide Archive und 575 Quelldateien
auf den bekannten Provider-Schlüssel geprüft, kein Treffer.

Prüfprotokoll samt Produktionsnachweisen/Kosten/Rückweg:
[SCIENTIFIC_QA_2026_10_20.md](SCIENTIFIC_QA_2026_10_20.md).
Kompatibler Rückweg `20261020T102707Z-79c80ff` (57), verliert letzten Skalierungsfix.
Vor Rückweg neue KI-Aufträge anhalten und aktive abarbeiten; kein DB-Restore über
neue Antworten oder Löschjournal. Provider nur bewusst revisionsgebunden ändern.

---

Der folgende Stand dokumentiert die frühere App-Abnahme auf 55. Seine Kosten,
Artefakte und Rückweg sind historische Zwischenstände; aktueller Kopf oben gilt.

# Historischer Produktionsstand 1.11.5+55 · 20.10.2026

Live: Release `20261020T074833Z-65e3ea6`, Produktcode
`65e3ea64996e4ef3547489ea393b661721f4232f`, Schema0023. Healthcheck status=ok,
Version1.11.5. Web, signierte Direct-APK und Play-AAB55 gebaut; main gepusht.
Vor Aktivierungen bestehende Sicherungen erstellt; Caddy ergänzt und validiert,
andere Dienste aktiv. Backend-Folgekorrekturen ändern den gebauten Client nicht.

## Ergebnis der beauftragten App-Abnahme

- Nach konkreter Nutzerbestätigung 42 Heftseiten mit 34 verknüpften Runden und
  120 Antwortversuchen gelöscht. Quellenlöschung entfernt jetzt die zugehörigen
  Übungen; einzelne gespeicherte Runden unter Lernen ebenfalls löschbar.
  Finanzbelege und unabhängige Elternaufträge bleiben erhalten.
- Neun künstliche Heftbilder mit je drei Themen erstellt und normal im Browser
  hochgeladen, zugeschnitten, erkannt, geprüft und bestätigt: je drei für Deutsch,
  Englisch und Mathematik. Neun Wortpaare ausdrücklich aus der Vorschau übernommen.
- Neue lokale Vokabelrunden: Standard zehn, Auswahl fünf/zehn/fünfzehn. Bei weniger
  verfügbaren Wörtern entsprechend kürzer. Begonnene Runden erhalten; keine KI für
  diese Übungsform. Tatsächlich neun Wörter in einer größeren Runde gelöst.
- Drei erzeugte Fachrunden mit zusammen sechs Aufgaben vollständig beantwortet,
  Lösungen und Hilfen geprüft. Zusammen mit zwei Wörterrunden: fünf abgeschlossene
  Runden, 18 Aufgaben, 21 Versuche. Öffentlicher Lernstand und Server stimmen überein:
  zehn allein, acht mit Hilfe gelöst. Das belegt Bedienung, keine Lernwirkung.
- Fotoreservierungsfehler verständlich und ohne sinnlosen Retry; erfolgreicher
  Teilimport bleibt erhalten. Nach Fotoabschluss Seiten nachreichen und aus dem
  Fotoeinstieg zur vorhandenen Auswahl zurückkehren. Allgemeine Einführung führt
  nach „Weiter üben“ zur Aufgabe. Fragewort im Feedback erhalten.
- Belegter OpenRouter-400er durch Anführungszeichen im Quellenzitat-Enum behoben:
  private Integerindizes, danach unverändertes Originalzitat und alle bestehenden
  Prüfungen. Drei erfolgreiche günstige Fachrückblicke; einmalige auditierte
  Reparatur nach Codefix, alte Fehler und Verbrauch erhalten.
- „Übung:“ verdeckt keine Bruchregel mehr (subject_rules_v3). Im Browser4/5für
  Erweiterung mit3ausdrücklich nachgeprüft: falsch;12/15danach richtig. Vorherige
  offene Bewertung im Prüfprotokoll erhalten. Lokaler Tipp und Tutor-Beleg geprüft.

Einzelheiten, Prompts, Befunde und Grenzen: [APP_AUDIT_2026_10_20.md](APP_AUDIT_2026_10_20.md).
Private Testbilder/Screenshots bleiben außerhalb von Git. Alle neuen Eingaben waren künstlich.

## Bezahlter sparsamer OpenRouter-Betrieb

Expliziter Betreiberauftrag ersetzt für diese Installation den früheren
Codex-/Free-Standard. Schlüssel aus der beauftragten lokalen Datei geschützt auf
Server verwendet; keine OpenRouter-Webanmeldung erforderlich. Revision29, Policy
paid-economy-20261020-v3-photo-hold: Luna für überschaubare OCR, Rückblicke und
quellgebundene Hilfe; Sol für anspruchsvolleren/umfangreicheren Stoff. Feste Azure-
Bindung, medium, ZDR/Data-Collection-Deny/Cache-Opt-out, kein automatischer Fallback.
Die Kontoeinstellungen beim Anbieter wurden nicht unabhängig eingesehen.

Bestehende Kosten-/Tarifgrenzen erhalten. Fotoreservierung innerhalb der ausdrücklich
freigegebenen0,15USD; paid-Routen maximal4000Ausgabetokens, keine Kontingenterhöhung.
Anbieteraufrufe erzeugter Pakete auf den tatsächlich geplanten Einstieg begrenzt,
spätere Etappen bewusst einzeln;34geplante Aufgaben sind kein fertiger Aufgabensatz.

Abnahme:0,224013USD gemeldete Inferenzkosten einschließlich drei fester Probeabläufe.
Drei400er mit unbekannter tatsächlicher Abrechnung behalten die volle Reservierung;
aus den genauen Anfragen konservativ berechnete zusätzliche Modellkosten höchstens
0,013486USD. Somit höchstens0,237499USD für diesen Teststand, unter0,25USD.
Gebühren/Steuern sind damit nicht als null behauptet; alte unbekannte Codex-Belege
unverändert. Aktivierung/Preise/Freigaben: [OPENROUTER_ACTIVATION_2026_10_20.md](OPENROUTER_ACTIVATION_2026_10_20.md).

## Prüfung und Artefakte

1148PostgreSQLtests vor den Folgekorrekturen vollständig bestanden. Danach gezielte
Suiten, insbesondere159Provider-/Wortschatztests,85Zitat-/Rückblick-/Routentests,
72Bruch-/Providerprüfungen und32Lern-/Prüfprotokolltests.617Fluttertests vollständig
auf54; danach36gezielte Tests für den Erklärungseinstieg55. Analyse/Ruff sauber,
Diff- und Geheimnisprüfung ohne Treffer. Dies sind überlappende Suiten, keine
aufsummierte Anzahl unterschiedlicher Tests.

APK55:68.123.902Bytes, SHA256
`14b60432fa9ac73b6bf180fe92efe28ee4937e15f043451da211f14bec8beb60`.
Vollständiger öffentlicher Download mit lokalem und serverseitigem Hash abgeglichen.
[Direct-APK herunterladen](https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk).
Play-AAB55:64.467.422Bytes, lokal gebaut; kein Play-Upload. Keine vollständige native
Android-, Sprach-, Google-Login- oder Push-Abnahme dieser Arbeit behauptet.

Rückweg: previous=`20261020T074208Z-b4e70f8`, gleiches Schema0023. Neue KI-Aufträge
anhalten, aktive Aufträge abarbeiten, dann bestehendes deploy/activate.py mit
--rollback-compatible. Dieser Rückweg verliert den Präfix-Bruchfix, erhält aber
die Kaskadenlöschung und den Zitatfix. Kein DB-Restore über neue Antworten oder
Löschjournal. Providerwechsel nur lokal mit Revision/Audit, keine stillen Fallbacks.

---

Die folgenden Abschnitte dokumentieren ältere Releases und deren damalige Grenzen.
Sie beschreiben nicht den aktuellen Anbieter- oder Löschbetrieb.

# Historischer Stand 1.11.0+50 ·20.10.2026

Web und reguläre signierte Direct-APK50 über den vorhandenen Deploymentweg
bereitgestellt. Release `20261020T053724Z-82a6078`, Produktcode
`82a6078ae45a92d6da6556a0703b2d5d6c6a9d73`. Der öffentliche Deployment-Healthcheck
meldet status=ok und API-Version1.11.0. Vorherige Sicherung und Aktivierung über
scripts/deploy.sh erfolgreich. Keine neue Migration: Schema0023 bleibt erhalten.

## Neue Heftaktionen

- Papierkorb und KI-Neueinlesen sichtbar im Album direkt über dem Foto sowie an
  Kachel-/Listenseiten und im Materialdetail. Kinder dürfen nach dem ausdrücklichen
  Auftrag nun auch eigene bestätigte Seiten löschen. Bestehende Antworten und
  erzeugte Übungen bleiben im Lernverlauf; feste Beispiele sind geschützt.
- Liste: Seiten auswählen, Alle auswählen über Pagination, Auswahl löschen und
  Alles löschen für den aktuellen Hefter/Filter. Servervorschau mit Anzahl und
  sitzungsgebundenem Zehn-Minuten-Snapshot; Änderungen und laufende Verarbeitung
  verhindern die gesamte Löschung, keine stille Teilmenge.
- KI-Neueinlesen legt eine neue unbestätigte Fassung des eigenen Fotos an. Genau
  ein normal reservierter OCR-Auftrag, ursprüngliche Quelle/Antworten erhalten.
  Statusseite nach Neustart/Reload nur GET. Danach Seite prüfen und ausdrücklich
  eine neue Runde vorbereiten; keine automatische Quellenbestätigung.
- Alte Fotoassistenten-Löschroute und ihre Weiterführung erhalten. Rechte bleiben
  im Backend; Lese-Eltern, Geschwister/fremde Familien und Betriebsadmin gesperrt.

Details/API/Größenlimits: NOTEBOOKS.md. Herkunft und Status: NOTEBOOK_ACTIONS_QA.md.
Anbieter-, Firebase-, Tarif- und Budgeteinstellungen wurden nicht umgeschaltet.

## Builds und Nachweisgrenze

Web, signierte Direct-APK und Play-AAB50 erfolgreich gebaut. Gepinnte Toolchain
und externe Signierung unverändert. Die bestehenden verpflichtenden APK-/Paket-/
Versions-/Signierer-/Hash-/16KB-Prüfungen liefen im Build-/Deploymentweg.
Bekannte flutter_tts-Wasm- und Kotlin-Plugin-Hinweise bleiben. AAB gebaut,
kein Play-Upload und auf Nutzerwunsch keine zusätzliche Bundletool-Abnahme50.

Vor der abschließenden Nutzersteuerung bestanden192 PostgreSQL-Tests (31 neue
Fälle), vier SQLite-Kompatibilitätsprüfungen und610 Fluttertests; Analyse ohne
Befund. Eine eigene künstliche Seite wurde noch auf49 normal erkannt und geprüft.
Danach ausdrücklich: nur bauen/ausrollen, weitere Funktionstests durch Nutzer.
Daher keine öffentliche Lösch-/Bulk-/Reprocess50-Abnahme und kein nativer50-
Funktionstest behauptet. Die vorbereiteten Treiber wurden nicht mehr ausgeführt.
Eigene Testfamilie regulär gelöscht, private Zugangsdaten entfernt und dedizierten
Emulator nach Bereinigung beendet. Keine echten Familien verändert.

APK: `artifacts/schulpilot-android.apk`,68.058.366Bytes, SHA256
`c25da2e7db8610ec7c54d0e1b2a1386bcec2447d20df7ee22e4c33790a93036e`.
Download: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk
Play-AAB: `artifacts/schulpilot-play.aab`,64.444.596Bytes, lokal gebaut.

Vorheriger Release `20261019T205610Z-5c3811c` (49, ebenfalls Schema0023) bleibt
als previous verfügbar. Vor Rückweg neue KI-Aufträge anhalten und laufende
Neu-Einleseaufträge abarbeiten; Code49 kennt deren Zusatzguards nicht.
Danach deploy/activate.py <vorheriger-release> --rollback-compatible verwenden,
kein DB-Downgrade oder Restore über neue Antworten/Löschjournale.

Nutzer-Nachtest: Hefte → Hefter → Papierkorb/KI-Icon; Liste → Mehrfachauswahl
und bestätigte Anzahl; neue KI-Fassung prüfen → Stimmt, weiter → Jetzt lernen.
Für Android die reguläre APK50 aktualisieren. Im Web den neuen Stand laden.

## Vorheriger Produktionsstand1.10.0+49

# Produktionsstand 1.10.0+49 · 19.10.2026

Öffentlich verifiziert: https://schulpilot.dorfspy.de, Release
`20261019T205610Z-5c3811c`, Produktcode
`5c3811c46c9baa530d4b8e6d8c3f60bb5930a0a3`, PostgreSQL-Schema `0023`.
Datenbanksicherung vor Aktivierung: success/Exit0. API, DB-Worker, isolierter
Codex-Worker, Caddy und Backuptimer aktiv. HTTP leitet mit308 auf HTTPS;
Webbundle und vollständiger öffentlicher APK-Download sind bytegleich zum Build.
Andere Dienste, echte Familien und bestehende Limits wurden nicht verändert.

## Tatsächlich umgesetzt

Persistenter ereignisgesteuerter Lerncontroller mit begrenztem Aktionsvertrag,
Belegverweisen, Quellen-/Planrevision und kompakter Sitzung. Einzelfehler,
wiederkehrender belegbarer Rechenfehler, Hilfe, unklare Bewertung, spätere
Wiederholung und Abschluss werden getrennt behandelt. Bestehende Attempts
bleiben maßgeblich; keine künstlichen Beherrschungsnachweise aus Klicks oder Zeit.
Antwortentwürfe über Pause/Neustart erhalten, konkurrierende Geräte mit CAS und
Idempotenz gesichert. Ungesendete Entwürfe fehlen in normalen Elternansichten.

Sofatutor aus lokalem Katalog am konkreten Lernziel einsetzen; empfohlen/geöffnet/
selbst als angesehen gemeldet/nicht hilfreich/defekt getrennt speichern. Nach
Rückkehr bewusst zwei neue Aufgaben anfordern, alte Runde/Antwort erhalten.
Kein kostenpflichtiger Aufruf beim Lesen, keine automatische Endlosschleife.
Inline-Rückkehr verbleibt in der Lernrunde; Eltern sehen Medienstatus lesend.
Alte Einheiten ohne Quellenrevision bleiben lesbar, ohne aktuelle Grafik zu
unterstellen. Providerrevision wird auch vor alten Nicht-Mix-Aufträgen geprüft.

OpenRouter-Chat-Completions-Adapter mit gebundenem Modell/Upstream, medium,
ZDR, Data-Collection-Deny, Cache-Opt-out und ohne Providerfallback. Additive
Migration0023 für Lernmemory/-ereignisse und Kosten-/Budgetzustand. Atomare
Integer-/Decimal-Reservierung, Kinderbudget zusätzlich zu bestehenden Grenzen,
Abgleich von tatsächlich abgerechneter Usage, unbekannte Kosten weiter gebunden.
Fehlgeschlagene kostenpflichtige Ausgaben bleiben erfasst. Metadaten-Abgleich
kann nicht mehr durch alte ungeeignete Datensätze verhungern. Geschützte
Betreiberansicht für Routing, Kosten, Gebührenbelege und Latenzen.
Architektur, zehn Controller-Szenarien und Betreiberanleitung:
[ADAPTIVE_OPENROUTER.md](ADAPTIVE_OPENROUTER.md).

## Prüfungen und ihre Grenzen

- Vollständiger PostgreSQL-Lauf:1081 bestanden; nach abschließenden Auditfixes
  weitere60 gezielte PostgreSQL-Regressionen bestanden. Überlappende Läufe,
  keine Addition zu einer behaupteten Zahl unterschiedlicher Tests.
- Finaler Flutter-Gesamtlauf auf49:583 bestanden; Analyse ohne Befund.
  Ruff, Compile, Node-/Shellsyntax, Diff- und Geheimnisprüfung bestanden.
- Öffentliche App49:24 Rollen-/Browserprüfungen bei320–1440px, keine
  Laufzeitfehler oder fehlgeschlagenen authentifizierten GETs.
- Zwei zusätzliche Agenten durchspielten Kind und Elternteil mit getrennten
  Browsern in einer eigenen künstlichen Familie:23 Kinderprüfungen sowie
  20 Eltern-Baseline- und30 Eltern-Nachtestschritte. Vier Aufgaben/fünf Versuche,
  drei selbstständig und eine unterstützt; Reload und Hinweis nachvollziehbar.
  Elternlesen erzeugt keine Kinderzeit/Antworten und verrät keinen Entwurf.
- Echtes Browser-Dateifeld:249.521Byte-PDF, drei Noten übernommen, erneuter
  Import erkennt alle drei ohne Neuanlage. Mindestziele25/125 gespeichert;
  bereits gemessene27Sekunden bleiben27. Null Provideraufrufe in dieser Familie.
- Die dabei gefundenen Singulartexte in Lernstand und Heute sind korrigiert;
  gezielter49-Nachtest mit unveränderten Lern-/Zeit-/Notendaten bestanden.
  [Kinderbericht](ROLE_SIMULATION_2026_10_19_CHILD.md),
  [Elternbericht](ROLE_SIMULATION_2026_10_19_PARENT.md).
- Native Flutter auf Android36: gespeicherter Entwurf über Pause und Prozess-
  neustart mit echter200%-Systemschrift auf48 geprüft. Danach echtes OTA48→49
  über geprüften Download und Android-Installationsbestätigung, ohne adb-Install.
  Auf49 drei Updatechecks bei Kaltstart, Vordergrund und erneutem Launcheraufruf.
  Öffentliche49-API bestätigt Entwurfs-/Idempotenz-/Eltern-Lesetrennung erneut.
- Web, signierte Direct-APK49 und Play-AAB49 gebaut. Paket/Signierer/Version,
  APK-Hash und16KB-Ausrichtung geprüft. Offizielles bundletool1.18.3 validiert
  AAB49; kein Debug und keine Direct-Installerberechtigung im Play-Manifest.
  Kein Play-Console-Upload. Bekannte TTS-Wasm-/Kotlin-Plugin- und
  Starlette/Alembic-Hinweise sind nicht durch Paketupdates verdeckt worden.

Beide eigenen künstlichen Familien anschließend über die normale Account-API
entfernt, private Kontocheckpoints gelöscht; eigene Emulator-Appdaten entfernt
und dedizierten Emulator beendet. Kosten-Evaluationsledger bleibt geschützt
außerhalb von Git erhalten. Keine echten Konten oder Antworten testbereinigt.

## Tatsächlicher Provider- und Kostenstand

`OPENROUTER_API_KEY` aus `~/or.txt` liegt ausschließlich serverseitig in
`/etc/schulpilot/environment`, root:schulpilot0640. Keine Ausgabe des Schlüssels.
Aktiv nach Deployment49: **Codex/gpt-6-luna**, Mix deaktiviert, Notfallstopp aus.
OpenRouter-Code ist bereit, aber **kein erfolgreicher produktiver Wechsel**:
Workspace-Inhaltslogging/Datenfreigabe und die vollständige Bild-/Aufgaben-/
Paketprüfung der aktuellen Mix-Konfiguration sind noch nicht belegt. Eine
bestehende Betreiberfreigabe wird nicht nochmals pauschal abgefragt; es fehlen
konkrete technische Nachweise, kein weiteres allgemeines Einverständnis.

25 verwertbare synthetische OpenRouter-Antworten: **0,065440USD** Inferenz erfasst;
mit zwei ungeklärten Reservierungen **0,195440USD** gebunden, Gesamttestlimit
0,25USD eingehalten. Gebühren/FX tatsächlich unbekannt. Azure-ZDR und medium
bei erfolgreichen Proben, Astra nur Katalogmetadaten. Kein vollständiger
Fünf-Fächer-Livevergleich, kein Nachweis garantierter7€ pro Kind/Monat.
Bereinigte Messwerte: OPENROUTER_EVALUATION_2026_10_19.json.

Keine physische Handy-, hörbare TTS-/Mikrofon-, TalkBack- oder neue sichtbare
Firebase-Zustellabnahme. Chrome-OS-Textskalierung veränderte die getesteten
Fluttertexte nicht: daraus wird keine200%-Browserabnahme behauptet. Rollenlauf
verwendete eine feste gekennzeichnete Mathe-Demo, keine neue OCR und keine
vollständige Fachabdeckung. Die begrenzte Voraussetzungsliste ist kein kompletter
Lehrplangraph. Externe Medien-Anschlussjobs sind mit synthetischen Modellantworten
regressionsgeprüft, nicht durch ein echtes Kind als wirksam nachgewiesen.

## Artefakte und Rückweg

APK: `artifacts/schulpilot-android.apk`,68.009.006Bytes, SHA256
`bc62e71dbc47006e039ca2ff3c9f380b2510d496c73d9cf8118a74701ccafec8`.
[Öffentlicher Download](https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk).
Play: `artifacts/schulpilot-play.aab`,64.352.329Bytes, SHA256
`8347b6d678a386680d348388789f216907180466efc30e6fbcd2c06169c1df23`.

Vorheriger kompatibler Release: `20261019T204352Z-9c7f8f3` (48, ebenfalls0023).
Code-Rückweg mit `deploy/activate.py <id> --rollback-compatible` über vorhandenes
SSH; keine Datenbankrückstufung und kein Restore über neuere Antworten.
Nur current/previous bleiben als Releases erhalten. Vor Rückweg auf Code vor
0023 neuen KI-Auftrag stoppen und die Hinweise in ADAPTIVE_OPENROUTER.md beachten.

Nächste konkrete Aktion: OpenRouter-Kontologging/Datenfreigabe im autorisierten
Workspace prüfen und dokumentieren, aktuelle Route gezielt technisch abnehmen;
erst danach über den vorhandenen Operatorweg aktivieren. Anschließend kleine
normale künstliche Fünf-Fächer-Kette und physisches Audio-/Geräteverhalten prüfen.

## Vorheriger verifizierter Produktionsstand


# Produktionsstand · 19.10.2026 · App1.9.0+44

Öffentlich unter https://schulpilot.dorfspy.de verifiziert. Aktiver Release
`20261019T180543Z-55533ec`, Produktcode `55533ec034a6e462472a6f5b05fb72a71fbd4168`.
Web und signierte Direct-APK44 entsprechen dem geprüften Build; spätere
Backendabsicherungen ändern Flutter und Artefakte nicht. PostgreSQL-Schema0022
unverändert, keine neue Datenmigration. Pre-Deployment-Sicherungen erfolgreich;
API, Lernworker, isolierter Codex-Worker und Caddy aktiv. Kompatibler vorheriger
Release bleibt über /opt/schulpilot/previous erreichbar; kein DB-Downgrade.

Praxistest P01–P12 umgesetzt und einzeln nachverfolgt:
[PRACTICE_REVIEW_2026_10_19.md](PRACTICE_REVIEW_2026_10_19.md).
Englischer großer Anfangsbuchstabe wird zielbezogen angenommen; ausdrückliche
Kleinschreibung bleibt streng. Kein globales Casefolding. Bruchaddition in drei
Balkenschritten, quellgebundene Wurzel-/Bestäubungsschemata, passende Erklärung
zur aktuellen Frage und konkrete gespeicherte Hilfengründe. Interne Fotovorschau
mit Zoom/Retry;21 gespeichert+3 vorgemerkt geprüft. Wörter einzeln bestätigen,
korrigieren, abwählen oder zurückstellen; Buchstabenhilfe mit Rückschritt.
Hilfeauswahl vor Elternnachricht, zusätzliche Problemmeldungen, Themenbündelung
mit erhaltenen Runden und lokale Mengen-/Datumsanzeige. API-Fehler mit
Wiederaufnahme statt automatischem Antwortretry.

Nachgereichten PDF500 öffentlich mit künstlichen249.521Bytes reproduziert:
versehentliche ungenutzte GradeImport.source_blocks-ORM-Spalte entfernt. Sie war
in Alembic nie für grade_imports angelegt und wird nicht benötigt. Tatsächlich
migriertes Schema gegen alle ORM-Spalten geprüft. Öffentlicher Upload danach201,
drei künstliche Noten übernommen, erneuter Import erkennt alle drei und erzeugt
keine Dubletten. Keine echten Noten oder anderen Familien verändert.

Prüfungen:268 PostgreSQL-Regressionen;55 zusätzliche Noten-/PDF-/Migrationstests;
72 Fach-/Audit- und26 Sprach-/Wortschatztests nach den letzten Backendanpassungen
erneut bestanden.323 Fluttertests plus25 Foto-/Entwurfs-/Designtests bestanden;
39 Zeit-/Rückblick- und neun neue Interaktionstests erneut. Flutteranalyse,
Ruff, Compile, Diff-/Geheimnisprüfung ohne Befund. Bekannte Starlette/httpx-
Warnung. Web, Direct-APK und Play-AAB gebaut; Paket, Signierer, Version und
16-KB-Ausrichtung verifiziert. Bekannte TTS-Wasm-/Kotlin-Pluginhinweise bleiben.
Kein Play-Upload oder Bundletool-Abnahme in dieser Arbeitseinheit.

Öffentlich24 Browserprüfungen aller Rollen bei320–1440px ohne Laufzeitfehler.
Normale künstliche Wörterfamilie per echter Mail verifiziert; Swimming pool
richtig, Antwort und Feedback nach Reload erhalten, je Aufgabe genau ein
Attempt. Vorherige Wortvorlage bleibt als Unterstützung erfasst. Native Flutter-
APK44 auf Android36: eigener Kinderlogin, Glocke/Heftansicht, vier Aufgabentypen
über Unterbrechungen, vier gespeicherte Elternantworten, Elternlogin/Logout.
Drei Start-/Vordergrund-Updatechecks und200% Systemschrift geprüft. Beide
künstlichen Familien normal gelöscht; private Checkpoints entfernt und eigener
Emulator beendet. Null externe KI-Aufrufe in diesen Nachtests, keine Limits
oder Provider-/Firebasefreigaben verändert.

APK: artifacts/schulpilot-android.apk,67.664.730Bytes, SHA256
`827b65247e17e0964670d1ca2b7e0d5e3f2352444e6e3c6101a6f8e32776dcfc`.
Download: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk
Play-Artefakt: artifacts/schulpilot-play.aab.

Grenzen: kein physisches Smartphone, hörbares TTS/Mikrofon oder TalkBack
beobachtet; Semantik-/Adaptertests sind keine Audioabnahme. Keine neue Live-OCR
oder externe KI-Fachgenerierung und keine vollständige Liveprüfung aller24
Fächer. Ursprung des alten about:blank und Vorgeschichte der alten Mathe-Runde
nicht reproduziert; keine nachträgliche Umwertung echter Antworten. Nächster
Schritt: den dokumentierten kleinen Nachtest auf einem echten Smartphone mit
künstlichen Fotos, Ton, Mikrofon und Screenreader durchführen.

## Historischer Stand vor dieser Arbeitseinheit

# Produktionsstand · 19.10.2026

## Aktive Version

App `1.9.0+43` läuft auf `https://schulpilot.dorfspy.de` als Release
`20261019T163738Z-9131cce`, Quellcommit
`9131cce89efa4bc215ec9a74baece549f7e60895`. Der direkte Rollback-Release ist
`20261019T153515Z-8850ec9`; PostgreSQL meldet Schema `0022`. Die erforderliche
Sicherung wurde erstellt. API, Worker, isolierter Codex-Worker und Caddy sind
aktiv. `/`, `/login`, `/hefte` und `/api/health` liefern HTTPS `200`; HTTP wird
mit `308` auf HTTPS umgeleitet. Der öffentliche Healthcheck meldet den Release-
und Quellcommit.

Die Webdatei `main.dart.js` ist bytegleich mit dem lokalen Releasebuild. Der
öffentliche Direct-APK-Endpunkt meldet Version `1.9.0`, Build `43`; der
vollständige öffentliche Download stimmt mit dem geprüften lokalen Artefakt
überein: 67.615.154 Bytes, SHA-256
`7fd79e450ecb903c340ca08bb3dfb68073552966453cad458e315c6da30f6df7`. Der
Play-AAB wurde gebaut, aber nicht veröffentlicht oder mit Bundletool geprüft.

Auf dem Server wurden zunächst 72 alte Schulpilot-Releases entfernt; nach dem
Rollout räumte die neue Routine ein weiteres aus. Nur `current` und `previous`
bleiben als Code-Releases erhalten. `/opt/schulpilot/releases` belegt 512 MiB,
Backups 470 MiB; auf dem 38-GB-Dateisystem sind 17 GB frei (54 % belegt). Keine
anderen Anwendungen, Datenbanken, Familieninhalte, Kontingente oder Provider
wurden verändert. Künftige Deployments räumen alte Releases erst nach
erfolgreichem öffentlichen Healthcheck auf und lassen Daten und Backups aus.

## Heftseiten löschen und Lernzeituhr · 19.10.2026

Löschaktionen in Album-, Kachel- und Listenansicht sowie „Alle Heftseiten“ ergänzt; die bereits bestehende Materialdetail-Aktion bleibt erhalten. Eltern benötigen verwaltende Familienrechte, Kinder können nur noch nicht bestätigte Seiten entfernen. Feste Testbeispiele zeigen keine Löschaktion. Löschen fragt nach und weist darauf hin, dass vorhandene Übungen erhalten bleiben. Nach Erfolg wird die Liste aktualisiert und ein leeres Heft korrekt angezeigt. Die Backend-Löschroute bleibt die maßgebliche Rechteprüfung.

Die Lernzeitanzeige verwendet Klartext statt des Bruch-Renderers; `6:25 / 20:00` bleibt damit eine Zeitangabe.

Prüfungen für diesen Release: 39 Flutter-Regressionen bestanden, `flutter analyze --no-pub` ohne Befund, 42 Backendtests bestanden und 2 übersprungen (eine bekannte Starlette/httpx-Warnung). Ruff, Python-Compile, Shellsyntax, Diff- und Geheimnisprüfung ohne Befund. Web, signierte APK `1.9.0+43` und Play-AAB gebaut. Webbuild meldet die bekannte Wasm-Trockenlaufwarnung aus dem gepinnten `flutter_tts`; Android-Plugins melden den bekannten Kotlin-Gradle-Migrationshinweis. Keine physische Geräte-, Audio- oder Play-Console-Abnahme in diesem Rollout.

Umgesetzt im lokalen Code: sichere Einzelbestätigung von Vokabelpaaren; sichtbare Datei-Uploadstatus; klassifizierte Vorbereitungsfehler; stabile Lernzielzuordnungen und Ergebniszusammenfassung aus gespeicherten Antworten; exakte Bruchnotation/-eingabe; quellgebundene Fachgrafiken für 24 Fächer mit getrennter Offenlegung; inhaltliche Dreiecksfehlerhilfe; passende Pause-/Zeit-/Statusdarstellung. 48 künstliche Quellenfälle prüfen Schema, Renderer und Antwortregel. Sie beweisen weder OCR noch Providerqualität oder vollständige Live-Fachabdeckung.

Vorherige Produktion `1.9.0+42` und die fachliche Prüfgrenze dieses Releases sind unter `docs/FACHTEST_2026_10_19.md` dokumentiert.

# Protokollkorrekturen · 19.10.2026 · App 1.8.0+41

Beide vollständigen HTML-Protokolle einschließlich aller Details, Anhänge und
JSON-Testdaten gelesen. Vollständige Befundliste mit 32 Befunden und allen
69 Testfallbezügen: docs/TEST_REPORT_REVIEW.md. Absichtliche Testfehler sind
keine Diagnose echter Fähigkeiten. Keine echte Familie oder ihre Daten verändert.

Der folgende Abschnitt hält den Ausgangsstand vor der Fachtest-Änderung fest.
Vor der Produktivbereitstellung war der aktive Produktcode
`863d4f9ef7a9d6671b6d3bc3ff8e06d3177dadfc`, Release
`20261019T065608Z-863d4f9`, Schema `0021`.
Vorheriger kompatibler Release: 20261019T063153Z-8990410. Bei Code-Rückweg
Schema 0021 und neuere Antworten erhalten; kein Downgrade oder DB-Zurücksetzen.
Additive Migration0020: versionierte Bewertungs-Audithistorie.
Additive Migration0021: Herkunft/Entscheidungen der Aufgaben und Nachrichtenbezug.
Sicherung Result=success/Exit0; sieben Dienste aktiv, Caddy gesichert/geprüft.
Keine fremden Dienste, Provider-, Firebase- oder Familienrechte verändert.

Umgesetzt: rationale Antwortgleichheit wie6/16=3/8 ohne Kürzvorgabe, getrennte
Inhalts-/Form-/Versuchs-/Hilfenbewertung, ausdrückliche auditierte Nachprüfung,
konsistente Kind-/Eltern-/Rückblick-/Fortschrittsprojektion. Offene Bewertung ist
keine Wissenslücke. Hausaufgaben werden gebündelt, ausdrücklich bestätigt und
gegen doppelte Übernahme abgesichert; Quellenrevisionen und Entscheidungen
bleiben nachvollziehbar. Gezielte unterschiedliche Fehlerhilfen, sichere
Wortbausteine, konkrete Formularfehler, kurze Erklärschritte mit Bruchdarstellung,
kuratierte NOAA-belegte Wal-Erklärung und direktes Tutor-Antwortfeld ergänzt.
Kinderführung/Fotostart/Zuschnitt verbessert; kurze Elternentscheidung vor den
Details, technische Ereignisse nachgeordnet, konkrete Nachrichtenziele.
Native Nachprüfung fand zusätzlich fehlende Erstblock-Fächer: begonnenes Mathe
wurde hinter Biologie verdeckt. Altpläne lesen das Fach jetzt aus der Einheit,
neue Erstblöcke speichern es. Freie-/Pausentage verwenden in allen Projektionen
denselben Zielstatus. Verbindliches echtes Mindestziel an Lerntagen erhalten.

Prüfungen: vollständiger PostgreSQL16-Lauf932 bestanden (1175,33s), nach späteren
Korrekturen alle125 betroffenen Backendregressionen bestanden (123,99s).
Vier neue Fach-/Resume- und zwei freie-Tag-Projektionsfälle vor dem Fix rot,
danach grün. Drei überholte Erwartungen im Verlauf ausdrücklich korrigiert,
Rechteprüfung verschärft. Keine Summierung überlappender Prüfgruppen.
346 vollständige Fluttertests bestanden, danach alle15 Eltern-Detailtests nach
der letzten Ereignisfilterkorrektur erneut bestanden. Flutteranalyse/Ruff,
Node-Syntax/Python-Compile/Diffprüfung bestanden. Keine Abhängigkeiten erneuert.
Web, signierte Direct-APK41 und Play-AAB41 gebaut. Tatsächliche Paket-/Versions-/
Signatur-/16-KB-Ausrichtung und AAB mit bundletool1.18.3 geprüft. Späterer Fix
betrifft nur das Backend; unveränderte App-/Buildquellen nachgewiesen.
Öffentliches Web-JavaScript und APK bytegleich, gültiges HTTPS, HTTP-Weiterleitung,
Direktlinks und DNS91.99.217.84 geprüft. SDK-Warnungen zu Wasm-Trockenlauf und
künftiger Kotlin-Migration sind keine neue Wasm-/Audiofreigabe.

Echter öffentlicher Chrome390/1440px: normaler eigener Kinder-/Elternlogin,
Dateiauswahl/Zuschnitt von drei künstlichen Fotos, drei echte reservierte Codex-
OCRs, Quellen-/Aufgabenvorschau und genau ein verbindlicher Auftrag aus zwei
Foto-Varianten. Ein echtes Paket mit Biologie/Mathematik, gespeicherter Rundenstart
und eine echte Tutorantwort mit gekennzeichnetem Zusatzbeleg. Modell gab bei
dieser Frage keine weitere Lehrerfrage zurück; direkter reply_to-Dialog durch
Integrations-/Widgettests geprüft, kein echter weiterer Tutoraufruf behauptet.
Erneuter Webdurchlauf nach dem Fix ohne zusätzliche KI,0 JavaScriptfehler.

Reguläre native Flutter-APK auf AndroidAPI36: tatsächliches OTA40->41 mit
Servercheck/Hash/Größe/Paket/Signierer und Android-Bestätigung, kein adb install.
Drei weitere Kalt-/Vordergrundprüfungen bestanden. Eigenständiger Kinderlogin,
Mathe aus Lernen öffnen, zwei echte Antworten einschließlich gleichwertigem
Bruch, Feedback nach Prozessneustart mit identischer Antwort-ID, keine
Doppelbuchung. Tatsächlicher reservierter Coach erfolgreich, keine erfundene
Hilfe. Nur37 aktive Sekunden gespeichert;20-Minuten-Ziel bleibt offen.
Neue Heftfotos öffnet frische Aufnahme ohne alte bestätigte Fotos. Logout geprüft.
Ein System-UI-ANR beim Emulatorstart und ein alter zusätzlicher Installer-Dialog
wurden auf dem eigenen Emulator geschlossen; kein SCHULPILOT-ANR daraus abgeleitet.
Eigener Emulator danach beendet. Keine physische Geräte-/Audioabnahme behauptet.

Eltern danach tatsächlich im Browser390/1440px: dieselben zwei richtigen
selbstständigen Antworten, identische37 Sekunden und offenes Mindestziel.
Keine Schreibanfrage oder Kinderaktivität durch Elternlesen. Regulärer Export
enthielt3 Fotos,2 Einheiten,2 Attempts,1 verbindlichen Auftrag, Aufgabenentscheidungen,
Auditstruktur und6 tatsächliche Verbrauchsbelege. Alle6 Codex-Kosten unbekannt,
nicht null. Eigenen künstlichen Haushalt regulär gelöscht, beide alten Sitzungen
401, privater Testcheckpoint und private Protokoll-Arbeitskopien entfernt.
Downloads-Originale unverändert. Keine Passwörter/Sitzungen/Tokens übergeben.

APK: artifacts/schulpilot-android.apk,66926838Bytes, SHA256
3b5e857362a98bed84d8e88361e8dc87140e1a5b21c6f185ffdce341b75e00e5.
Öffentlicher Download: https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk
Play-AAB: artifacts/schulpilot-play.aab,63548292Bytes; nicht veröffentlicht.
Belege: artifacts/report-review-{web,native,parent-after,erasure}-result.json,
artifacts/test-report-review/{public-release41-final.json,backend-final-all.log,
native-final-regressions2.log,flutter-release-final.log,deploy41-resume-fix.log}.

Nachtest nach normalem eigenem Login(/login), ohne weitergereichte Zugangsdaten:
Kind -> Neue Heftfotos -> künstliche Seiten -> Stimmt, weiter -> Aufgaben-/
Beispielvorschau -> Lernpaket -> Lernen. Antwort/Feedback nach Neustart erhalten;
weitere Hinweise verschieden, unklare Bewertung über Bewertung prüfen klären.
Eltern -> /child/<eigene-Kind-ID> -> Das gelang/Das übernimmt die App/Jetzt für euch,
Zeit/Verlauf -> /unit/<berechtigte-Einheit> mit Antworten, Hilfen und Bewertungshistorie.
Kein bestehendes echtes Kind als Fehlerfixture verwenden. Für neue Automatiktests
qa/prepare_report_review.py, qa/report_review.mjs, qa/android_report_review.py,
qa/report_review_parent_result.mjs, qa/report_review_cleanup.py in dieser Reihenfolge.

Offen: unbekannte freie Sätze bleiben konservativ unklar; Tutor-Grundwissen ist
bewusst klein, kein allgemeines Wörterbuch. Keine automatische fachliche OCR-
Zertifizierung, kein vollständiger Offline-Neustart zugesichert, keine vollständige
WCAG-/Lernwirksamkeitsprüfung. Physischer Ton/Mikrofon und Verstehen durch Kinder
brauchen eigene Beobachtung. Neue Push-Zustellung/Google-/Play-Prüfung ist nicht
Teil dieser Protokollkorrektur; bestehende Freigaben/Nachweise bleiben unverändert.
GitHub-Actions39202054006 startet wegen Billing-Kontosperre keine Jobs;
Annotationen117896914608/117896914923 tatsächlich gelesen. Lokale Tests/Builds und
main-Push erfolgreich. Nutzeraktion: GitHub-Kontoinhaber klärt die Abrechnungssperre.
Serverlaufwerk aktuell97% belegt/1,2GB frei; gesonderte geplante Bereinigung alter
Release-Artefakte sinnvoll, keine fremden Daten oder Ressourcen dafür verändert.
Nächster unabhängiger Schritt: physischer Android-Alltagstest mit Ton/Mikrofon;
kein Codeblocker für die ausgelieferten Korrekturen festgestellt.

Die folgenden älteren Abschnitte sind historische Nachweise. Für den aktuellen
Produktcode gilt der Abschnitt oben; spätere reine QA-/Dokumentationscommits
ändern nicht den hier tatsächlich bereitgestellten Quellcommit.

# Kompakte Hefter1.7.2+40 – produktiv geprüft18.10.2026

Aktueller Produktstand: Commit 1e644c2447a5ad2951d10c415ef6b123140e4a2b, main gepusht.
Release 20261018T201730Z-1e644c2, Schema0019 unverändert. Vorheriger kompatibler
Release20261018T195453Z-ba21953; beim Code-Rückweg additives Schema erhalten.
Sicherung success/Exit0, sieben Dienste aktiv, projektspezifische Caddy-
Konfiguration gesichert. Keine fremden Dienste oder Providergrenzen geändert.

„Hefte“ zeigt eine kompakte Icon-Leiste: Suche erst nach eigener Aktion,
Meine Fächer, Kacheln/Liste, Fotoimport und weiteres Menü. Tooltips und48px-
Trefferflächen erhalten. Auf390/529px beginnt der erste Hefter bei224px,
auf1440px bei249px. Wörter bleiben im regulären Menü. „Meine Fächer“ filtert
jetzt ausschließlich nach vorhandenen Seiten: auch persönlich ausgewählte
leere Fächer ausgeblendet, vorhandene unzugeordnete Seiten bleiben erreichbar.
Ohne Filter vollständiger Fachstamm. Fachsuche ohne Tastatur-Autokorrektur.

337 vollständige Fluttertests für die kompakte39-Basis bestanden; nach den
Such-/Filterkorrekturen40 alle26 betroffenen Fluttertests und Analyse erneut
bestanden. Drei Release-Policy-Tests auf isoliertem PostgreSQL bestanden.
Web, reguläre signierte Direct-APK40 und Play-AAB40 gebaut. Signatur/Paket/
Version/16-KB-Ausrichtung und tatsächliches AAB mit bundletool1.18.3 geprüft.
Keine SDK-/Abhängigkeitsupdates oder neue Migration. Quellen/Builds gegen16
konkrete Geheimnisquellen geprüft:0 Treffer. GitHub-Actions39153166860 konnte
wegen Kontosperre durch ein Abrechnungsproblem keine Jobs starten; Annotation
117750827826 geprüft. Lokale Prüfungen und main-Push funktionieren.

Öffentlicher Chrome390/529/1440px: Kinder-/Elternlogin, kompakte Position,
Suchfeld öffnen/eingeben/schließen, nur belegte Fächer, Listen-/Kachelwechsel,
Menü/Aktualisieren/Alle Heftseiten/Elternrückweg bestanden.0 JavaScriptfehler,
0 Schreibaufrufe durch Werkzeuge,0 zusätzliche KI-Aufträge. Zwei künstliche
Fotos normal hochgeladen, ohne OCR/KI, ausschließlich eigener Testhaushalt.
Reales natives OTA39->40: automatischer Servercheck, verifizierter Download,
Android-Installationsbestätigung, kein adb install. Drei weitere Startchecks
bestanden. Reguläre native Flutter-APK40/API36: kompakte Leiste, tatsächliche
Suche mit englisch eingestellter Tastatur, leerer ausgewählter Hefter verborgen,
unzugeordnete Seiten erreichbar, Ansichts-/Menüwechsel und Logout bestanden.
Ein System-UI-ANR beim Emulatorstart erforderte Neustart der eigenen System-UI;
native Prüfung anschließend erfolgreich. Kein physisches Gerät daraus ableiten.
Export des eigenen künstlichen Haushalts mit zwei Fotos und null Lernantworten/
KI-Verbrauchsbelegen geprüft; regulär gelöscht, beide alten Sitzungen401,
privater Zugang entfernt und eigener Emulator beendet. Keine neue Audio-/Push-
Zustellung, Play-Veröffentlichung oder Lernwirksamkeitsprüfung behauptet.

Öffentliche HTTPS/API/Direktlinks, Web-JavaScript und APK bytegleich geprüft.
APK artifacts/schulpilot-android.apk: 66681078Bytes, SHA256
6f3634d8c49f01182d5bcdda358ae655bcc173e0f5450507d4e9e0e57e072169.
Web https://schulpilot.dorfspy.de ; APK /downloads/schulpilot-android.apk.
Browser: normaler Login -> Hefte -> Filter-Icon „Meine Fächer“; mit Inhalt
sichtbar, ohne Inhalt verborgen. Ohne Filter bleiben alle Fächer öffnbar.
Bereinigte Belege artifacts/notebook-toolbar-{web,native,erasure}-result.json,
notebook-toolbar-public40.json und notebook-toolbar-ota39-to40.json.
Nächste unabhängige Prüfung: persönlicher Alltagstest auf physischem Android;
GitHub-Kontoinhaber muss die vorhandene Actions-Abrechnungssperre klären.

# Katalog/Lerntipps1.7.0+38 · produktiv18.10.2026

Produktcommit f04539fd5d959b7a5b082dacb1573a8d907b5379, main gepusht.
Release20261018T181932Z-f04539f, Schema0019. Migration und vollständiger
Katalogimport tatsächlich auf dem Server abgeschlossen.24 feste Fächer,
16 Katalogfächer,126 Stufen/124 aktiv,1558 Themen,4188 Platzierungen,
8227 Inhalte(7559 Videos/668 Lerntexte),9828 Themenbeziehungen,
24459 Herkunftszeilen. Vier bestätigte leere Hauptlisten erhalten.
Snapshot c67500bd581a16aaca394ab042c511836a91f223056445c51c4610778690b481.
Lokale Zuordnungs-/Backfillaufträge beendet, keine fehlgeschlagenen Aufträge.
Sicherung success/Exit0; API/DB-Worker/Codex/Caddy und drei andere Anwendungen
aktiv. Vorheriger kompatibler Release20261018T155252Z-56f1112; Schema0019
beim Code-Rückweg erhalten, keine neueren Antworten zurücksetzen.

Vorhandene Bildhefter/echtes Fotoalbum mit Blättern/Zoom/Kacheln/Liste um
quellgebundene Sofatutor-Lerntipps ergänzt. Derselbe Dienst in Quellen,
Einheiten/Tutor/Aufträgen/Plan; paginierte Themenauswahl auch im leeren Fach,
bekannte Stufe ausdrücklich, Sprachlernjahr nicht aus Schulklasse geraten.
Eltern konfigurieren Stufen und sehen getrennte Linkereignisse. Links zählen
weder als Übung noch als Videoabschluss. Keine privaten Texte/Zugänge an
Sofatutor; HTTPS-Hosts/gespeicherte Parameter/kein Referrer geprüft.
Keine zusätzlichen Modellaufrufe auf GET und kein neuer Anbieter/Sprachdienst.

907 vollständige PostgreSQLtests495,91s;337 vollständige Fluttertests115s,
Analyse/Ruff bestanden. Nach letzter Aliasprüfung44 gezielte PostgreSQLtests
und nach Datenschutzhinweis neun Fluttertests/öffentlicher Datenschutztest
erneut bestanden. Tatsächlicher CSV-Abgleich19603 Beziehungen,0 vorliegende
Fehler/465 Hinweise. Web/Direct-APK/Play-AAB38 signiert gebaut, Paket/Version/
Signatur/16-KB-Ausrichtung und bundletool1.18.3 geprüft; keine SDK-Updates.
Quellen/Builds gegen16 konkrete Geheimnisse geprüft:0 Treffer; beide
entpackten Metadatenbündel zusätzlich geprüft. Öffentliche HTTPS/API,
Direktlinks/APK und Web-JavaScript bytegenau mit Build abgeglichen.

Öffentlicher Chrome390/1440px: normaler unabhängiger Kinderlogin, Fotoauswahl
zweier künstlicher Seiten samt Zuschnitt, zwei echte reservierte Codex-OCRs,
ausdrückliche Quellenbestätigung, reale Tutorantwort samt Quellenbelegen und
echtes Tageslernpaket geprüft. Private Lösungen nicht an Kinder ausgeliefert.
Lerntipps aus denselben Quellen und bekannter Klasse, externe Navigation mit
ursprünglichen Themenparametern und leerem Referrer, Album/Zoom/Ansichten,
normaler Elternlogin/Linkverlauf/exklusive Stufeneinstellung bestanden.
Null JavaScriptfehler, null erfundene Attempts; insgesamt vier reservierte
KI-Aufträge. Kein Wiedergabenachweis oder Notenversprechen abgeleitet.

Reales natives OTA37->38 bestanden: automatischer Servercheck/Download,
Hash/Paket/Signierer und Android-Installationsbestätigung; kein adb install
für dieses Upgrade. Drei weitere Kalt-/Vordergrund-/Startprüfungen bestanden.
Native reguläre Flutter-APK38/API36: dieselben eigenen privaten Fotos,
Blättern/Zoom/Kacheln/Liste, Themenfilter für bekannte Stufe, Lerntipps,
externer HTTPS-Browserintent, Sessionfortsetzung nach Neustart und Logout
bestanden. Kein Videoabruf aus dem Browserintent abgeleitet. Danach regulärer
Familienexport mit zwei Fotos, einer Einheit, einer Tutorfrage, vier privaten
Tippkontexten/drei Linkereignissen und vier Verbrauchsbelegen geprüft.
Null Attempts/Noten. Eigenen Haushalt regulär gelöscht; beide alten Sitzungen
401, privater QA-Checkpoint entfernt, eigener Emulator beendet.
Keine neue physische Geräte-, Audio-, Push- oder Play-Abnahme behauptet.

APK artifacts/schulpilot-android.apk:66615438Bytes, SHA256
18daaaa3329f8302c28d43b420760614dd2d697fa3f773d141d4da9ff54153a6.
Web https://schulpilot.dorfspy.de ; Download /downloads/schulpilot-android.apk.
Browser: normaler Login(/login) -> Hefte(/library/<eigene-Kind-ID>) ->
Fachhefter -> Themen entdecken oder Lerntipps bei einer bestätigten Heftseite.
Für weitere Tests eigenes künstliches Konto normal anmelden/erstellen;
keine Passwörter/Sitzungen/Gerätetokens weitergeben. Testbelege in
artifacts/catalog-{web,native,erasure}-result.json an denselben künstlichen
Haushalt gebunden; keine privaten Kontodaten in diesen Übergabedateien.
Weitere Cloud-/Gerätetests nur nach normalem eigenem Login. Keine neue
Firebase-Freigabe, IAM-Änderung oder Zustellprüfung in dieser Katalogarbeit.

GitHub-Actions39143922108 startete keine Jobs: Konto wegen eines
Abrechnungsproblems gesperrt. Annotation117723783110 ausdrücklich geprüft.
Lokale Tests/Builds und main-Push funktionieren; kein bezahltes Upgrade.

# Fachhefter/Fotoalbum1.6.1+37 · produktiv geprüft18.10.2026

Aktiv: Produktcommit `56f1112eb7fe0c63db284ab72e4a917985faa708`, main gepusht,
Release `20261018T155252Z-56f1112`, Schema0018. Vorheriger Release
`20261018T152551Z-007c570` als kompatibler Code-Rückweg; additives Schema
behalten. Sicherung success/Exit0, sieben Dienste aktiv. Öffentliche HTTPS,
Web-Direktlink, APK und Web-JS bytegenau geprüft. Andere Anwendungen erhalten.

„Hefte“ zeigt24 feste Fächer mit eigenen fotorealistischen A4-Papphefterbildern
und einen neutralen Hefter für private/unzugeordnete Inhalte.25 WebP-Assets,
784.908Bytes samt bereinigtem Promptmanifest. Belegte/ausgewählte Fächer zuerst;
auch leere Fächer bleiben sichtbar und öffnbar. Fachkarten, Suche und Liste.
Echte private Fotos im kompakten Album, Wischen/Pfeile/Tastatur, Blättereffekt
mit reduzierter Bewegung, Zoom, Filter, Seitensprung über Metadatenseiten,
Kachel-/Listenübersicht. Bestehende Quellenprüfung und Lernen erhalten.
Stabile Fach-IDs/Aliase, Geschwisterschutz und Kompatibilitätsprüfung gegen
ignorierte Fachfilter alter Backends. Fotos begrenzt/lazy laden und bei
Logout/Dispose verwerfen. Lesen erzeugt keine KI oder Lernleistung.

**Tatsächlich geprüft:**875 vollständige PostgreSQLtests511,43s auf derselben
Backendlogik; für37 nochmals57 betroffene Regressionen42,96s.328 vollständige
Fluttertests104s, Analyse, Ruff und Diff sauber. Web, signierte Direct-APK
und Play-AAB37 gebaut; Signaturen/Android-Metadaten/16-KB-Ausrichtung sowie
bundletool1.18.3 geprüft. Keine SDK-/Abhängigkeitsaktualisierung.

Öffentliche Flutter-App in Chrome390/1440px: unabhängiger Kinderlogin,
Fächer ohne vorheriges Material, leeres Fach, echte Fotos/Blättern/Zoom,
Kacheln/Liste, Sprung zur24. Seite über zweite Metadatenseite, normaler
Elternlogin mit denselben Anzahlen/Null-Fortschritt, Netzverlust und bewusstes
Erneutladen bestanden. Null JavaScriptfehler und null Album-Schreibanfragen.
Native reguläre Flutter-APK37 im eigenen Android-API36-Emulator: dieselben
Foto-/Übersichts-/Seitensprungfunktionen, App-Neustart und Logout bestanden.
Echtes OTA35->36 und36->37 mit automatischem Download/Hash-/Paket-/Signaturcheck
und Android-Installationsbestätigung, kein adb install für diese Upgrades.
Auf37 drei tatsächliche Startprüfungen bestanden. Kein physischer Gerätetest
oder neue Push-/Audio-/Play-Veröffentlichung daraus abgeleitet.

Eigener normal verifizierter künstlicher Haushalt:26 normale Foto-Uploads,
zwei echte reservierte Codex-OCR-Aufträge, zwei bestätigte Mathematikseiten,
24 ehrlich unzugeordnete Seiten. Keine Datenbankinjektion/erfundenen Antworten.
Nach Web und Android Export/all26 privaten Fotos geprüft, genauzwei
Verbrauchsbelege/keine Attempts oder Noten, Haushalt regulär gelöscht,
beide alten Sitzungen401 und privater Konto-Checkpoint entfernt. Emulator
beendet. QA-Berichte in artifacts/notebooks-{web,native,erasure}-result.json;
Web/native Berichte vor Löschung an denselben künstlichen Haushalt gebunden.
Flutter-Textfelder im Web-QA vor nächster Aktion über Tab/Frame abschließen;
ein DOM-inputValue allein war kein sicherer Flutter-Eingabenachweis.

APK: `artifacts/schulpilot-android.apk`,66.320.086Bytes, SHA256
`d1389872e092cae2e1227b42f1791d9f22214678b5f571b27aa55dffbf6751ae`.
Download vor/nach Login unter https://schulpilot.dorfspy.de verfügbar.
GitHub-CI39133398904 fehlgeschlagen; vorherige konkret gelesene Annotation
117687457475 nennt Kontosperre wegen Billing, Jobs ohne ausgeführte Schritte.
Lokale Tests, Builds und Push funktionieren; keine erfolgreiche CI behauptet.

**Offen/nächste Aktion:** vollständiger Sofatutor-Metadatenimport und gemeinsame
Lerntipps, siehe CATALOG_INTEGRATION.md. Unregistrierter Modellentwurf weiterhin
in artifacts/wip/catalog_models.py, nicht Teil dieses Releases. Bildhefter
sind vollständig integriert und geprüft, nicht mit Katalogempfehlungen verwechseln.

# PDF-Größenfehler behoben · 18.10.2026

**Produktiv:** `961b1537dafc0ddb8d88a80ca95ab92db6d0b03c`, main gepusht,
Release `20261018T142657Z-961b153`, Schema0018. Ursache: der zweite
Content-Length-Check hatte trotz PDF-Uploadlimit noch64KiB erzwungen.
Bereitgestellte234.106Byte-PDF auch auf Server isoliert korrekt gelesen
(14 Einzelnoten/Schuljahr2026), keine Werte/Personenköpfe ausgegeben.
Vor Fix mit künstlicher240KiB-PDF in öffentlichem Web413 reproduziert.
Gemeinsame Größenpolicy für Header/Stream korrigiert; PDF selbst weiter6MiB,
normale JSON-Endpunkte64KiB. Rechte/Bestätigung/Quoten unverändert.

**Geprüft:**82 PostgreSQLtests83,20s inklusive normalem/gestreamtem größeren
Upload, Dublettenschutz, großem Bestätigungspayload, alten JSON-Grenzen,
Rechten, Noten/Migration und Fachgrundlage;17 Fluttertests, Analyse/Ruff/Diff
sauber. Öffentlich390/1280px Dateidialog, Vorschau, manuelle Zuordnung,
Übernahme und identischer Upload ohne weitere Noten bestanden. Native
Flutter-APK35/API36 mit Systemdateidialog, ergänzter/geänderter PDF,
bewusster Übernahme und App-Neustart erfolgreich; fünf eindeutige Noten/
Quellpositionen. Export/Kindersperre/Null-KI-Nutzung geprüft, eigener künstlicher
Haushalt regulär gelöscht, beide alten Sitzungen401, Zugangsdaten entfernt.
Größere Originalfixtures jetzt dauerhaft im öffentlichen/nativen QA-Pfad.

Keine Appquelländerung oder neue APK für diesen Backendfix: vorhandene signierte
Web-/Android-/Play35-Artefakte unverändert. Native Kaltstartumgebung meldete
zunächst alten Seed4, daher signierte APK35 mit adb install -r eingerichtet;
**kein neuer OTA-Nachweis** daraus abgeleitet. HTTPS, Noten-Direktlink200 und
öffentliche APK/Web-JS bytegenau geprüft. Backup success/Exit0, sieben Dienste
aktiv, vorheriger Release20261018T132538Z-87f9cf6 als Rückweg vorhanden.
Erster Stagingversuch vor Aktivierung abgebrochen wegen APK-Symlink im eigenen
temporären Deployverzeichnis; mit regulärer Datei erfolgreich wiederholt.
Deployment aus sauberem separatem Worktree, unfertige Katalogdatei nicht kopiert.
Reproduktion/Ergebnisse: artifacts/grade-pdf-size-*.log, grade-pdf-*-result.json.
Nutzer muss zuvor abgewiesene PDF erneut auswählen und ausdrücklich übernehmen;
keine Roh-PDF gespeichert und keine private Note automatisch hinzugefügt.

# In Umsetzung · Fachstamm/Katalog/Bildhefte · 18.10.2026

**Fachgrundlage seit PDF-Hotfix produktiv:** Migration0018 an0017,
versionierter24-Fächer-Seed aus allen16 tatsächlichen Katalogfächern plus acht
zusätzlichen Schulfächern. Alias-/Providerzuordnung und persönliche Fächer/
Stufentypen getrennt. Additive Fachreferenzen für Material/Auftrag/Einheit/
Note/Mastery; historische Labels, Antworten und Quellenrevisionen unverändert.
Zusätzliche alte Fächer familienprivat erhalten; Kinder sehen keine eigenen
Fachnamen von Geschwistern. Neue explizite Elternfächer ebenfalls privat,
keine automatische Anlage durch KI oder normale Backfills. Profilanlage,
Export und Kinder-/Familienlöschung verwenden dieselbe Grundlage.

**Geprüft:**31 gezielte PostgreSQLtests bestanden (21,46s): frische Fächer ohne
Material/Account/KI, eigener Kinderlogin, leere Fächer, wiederholter Seed und
Backfill, Aliasgrenzen, private Extras, Geschwisterschutz, Löschung, eigene
Fächerlimits einschließlich Profilumgehung, alte SQLite-Migration mit
Antworterhalt und unveränderte PDF-Migrations-/Importregression. Ruff und
Diff sauber. Keine Flutteränderung in diesem Paket; zuvor318 Tests und
Web/APK/Play35 tatsächlich gebaut/geprüft. Neue volle Regression erst nach
Katalog-/Oberflächenintegration. Quelle/Arbeitsplan: CATALOG_INTEGRATION.md.

**Noch offen / nächste Aktion:** Katalogmodelle in artifacts/wip/catalog_models.py sind nur
unregistrierte Grundlage. Tabellenmigration0019, vollständiger idempotenter
Import samt Herkunft/CSV-Abgleich, gemeinsamer präziser Matcher, bestehende
KI-Pfade begrenzen und private Kontexte/Feedback integrieren. Danach tatsächliche
Fach-/Lerntipp-/Albumoberflächen, Tests und gesicherter kombinierter Release.
Alle16 Referenzcovers liegen erzeugt als PNG/optimierte WebP in
artifacts/folder-covers mit Promptmanifest; Zusatzfächer brauchen noch Bilder.
Produktiv ist PDF-Hotfix1.5.0+35, Schema0018,961b153.
Katalogimport und sichtbare neue Hefter sind weiterhin in Umsetzung.

# Noten-PDFimport1.5.0+35 · bereitgestellt18.10.2026

**Produktiv aktiv:** Produktcommit `87f9cf68962385cd1dd7c996eacdd02dde6e3462`,
main gepusht, Release `20261018T132538Z-87f9cf6`, Schema0017.
Sicherung success/Exit0, sieben bestehende Dienste aktiv. Gültiges HTTPS,
öffentliche APK/Webbundle bytegenau verglichen; Noten-Direktlink200.
Web https://schulpilot.dorfspy.de ; API unter/api, keine neuen Dienste.
APK35 enthält den echten nativen Android-Dateidialog, kein WebView.

**Implementiert:** lokale begrenzte Fuxnoten-Extraktion ohne KI, Vorschau und
Übernahme im Elternbereich. Quellpositionen wiedererkennen, manuelle
Überschneidungen und geänderte Werte ausdrücklich klären, atomare/idempotente
Bestätigung. Unbekannte Bewertungsdaten bleibenNULL mit Schuljahr/Halbjahr;
keine Ø-/Summennoten importieren. Bestehende Datumswerte, Korrekturen,
Löschungen und Lernziele erhalten. Export/Aufbewahrung/Kinderlöschung erweitert.
Migration0017 an0016 angeschlossen. Details docs/GRADE_PDF_IMPORT.md.

**Prüfungen:**861 PostgreSQLtests bestanden in602,73s, alle318 Fluttertests,
Analyse/Ruff/Diff/Syntax bestanden. Darunter22 neue Backendtests mit echtem
PostgreSQL-Upgrade, alten datierten Noten, sicherem Downgradeschutz,
Parallelität, Rechteentzug nach Parsing, Export/Löschung; nach gemeinsamem
Fixture-Refactoring nochmals22 bestanden. Reale gelieferte PDF ausschließlich
lokal analysiert:14 Einzelnoten/sechs Fächer, keine Namen/Notenwerte ausgegeben,
keine echte PDF in Git/externen Modellen; private Diagnosekopien entfernt.

**Tatsächlich öffentlich bedient:** normaler eigener künstlicher Haushalt,
Browser-Dateiauswahl einer künstlichen A1-PDF, vorhandene manuelle Note
zugeordnet, drei neue übernommen. Wiederholter Upload:vier bestehende,
null zusätzliche Noten. Feedback/Reload,390/1280px und null JS-Fehler geprüft.
Native Flutter-APK35/API36: Android-Systemdateiauswahl, neue fünfte Note aus
aktualisierter PDF, geänderten Quellwert ausdrücklich übernommen, Neustart,
Sitzungsfortsetzung und gespeicherte Noten geprüft. Exaktfünf Noten und fünf
Quellpositionen, keine KI-Nutzung oder erfundene Übungsantworten. Eltern/Kind
haben konsistentnull Übungsaufgaben, Kind darf private Noten nicht lesen.
Export enthält alle neuen Tabellen; eigenen Haushalt normal gelöscht,
alte Sitzungen401, private Kontodatei entfernt. Keine physische Telefonprüfung.
Reproduzierbar: scripts/prepare_grade_smoke.py, qa/grade_pdf_web.mjs --run,
qa/android_grade_pdf.py, qa/grade_pdf_cleanup.py. Roh-PDFs niemals an KI senden.

Web/signierte Direct-APK/Play-AAB1.5.0+35 gebaut, Signatur/Zipalign/bundletool
und Versionscode geprüft. APK65.300.445Bytes, SHA-256
`02df1d2f4279a08bd89ec9ee6d0f7910cf16f6bd22721585f5034a1bf856a667`.
Tatsächliches OTA34->35 mit Systembestätigung, ohne adb install; danach drei
Kalt-/Warmstartchecks bestanden. Geheimnisprüfung gegen16 tatsächliche Quellen
vor Testkontolöschung ohne Fund; finalen bereinigten Scan nachführen.
Rückweg20261018T125246Z-8ada817: additives Schema erhalten, Vorwärtskorrektur
bevorzugen; Downgrade mit undatierten Noten absichtlich gesperrt.
GitHub-CI39123259701:beide Jobs null Schritte, gelesene Annotation weiterhin
Kontosperre/Abrechnung. Produktpush und lokale/öffentliche Tests erfolgreich.

**Fortsetzung:** Sofatutor-ZIP liegt vor und ist geprüft. Nächste Migration0018
an0017 anschließen: zentraler Fachstamm vor Upload, kontrollierte Alias-/
Referenzmigration, kompletter idempotenter Katalogimport, quell-/stufentreue
Lerntipps in vorhandenen Ansichten. Danach beziehungsweise gemeinsam
Bildhefter/Fotoalbum/Listenschalter integrieren. Alle16 Referenz-Fachbilder
sind mit eingebautem Imagegen erzeugt, in artifacts/folder-covers gespeichert
(PNG und optimierte WebP, zusammen528KB), noch nicht ins Produkt eingebunden.
Prompts und Quellenpfade stehen dort in generation-manifest.json; keine
bestehenden Bilder überschrieben. Zusätzliche vorhandene Schulfächer erhalten.

Echter Sprachwerkstatt-Prüfauftrag weiterhin unverändert fehlgeschlagen:
auditierte Metadatenkontrolle bestätigte keinen neuen Job/keine Einheit.
Frischer normaler Kinderlogin und ausdrückliches „Erneut vorbereiten“ sind
weiter nötig; keine alte Sitzung reaktiviert. Unabhängige Arbeit fortsetzen.

# Sprachwerkstatt 1.4.4+34 · 18.10.2026

**Bereitgestellt:** Produktcommit `8ada817856e2789ea6e84300828be9975571b536`,
main gepusht, Release `20261018T125246Z-8ada817`, Schema 0016.
Sicherung Result=success/Exit=0, sieben bestehende Dienste aktiv, HTTPS gültig,
öffentliche APK und Webbundle bytegenau geprüft; Direktlinks 200.
Belegfix und sichere ausdrückliche Wiederaufnahme nach erneutem Kinderlogin
implementiert. Beide Reparaturwege zusammen höchstens ein normal reservierter
Zusatzauftrag. Keine alte Sitzung reaktivieren; alte Fehler/Verbrauch erhalten.

**Geprüft:** alle 839 PostgreSQLtests bestanden (432,00 s), 313 Fluttertests,
Analyse/Ruff/Syntax-/Diffprüfung bestanden. Erster Backendlauf: 838 bestanden,
bestehender tatsächlicher Codex-Metadatentest vorübergehend 503; danach alle
27 Modultests und erneuter vollständiger Lauf bestanden. Grenzen unverändert.
Web/signierte Direct-APK/Play-AAB 1.4.4+34 gebaut, Signatur/Zipalign/bundletool
geprüft. APK 65.168.233 Bytes, SHA-256
`6e9e1321bb6580ee34559918afadf3275376ca5bfb2e2823be2fe3a09f9d9316`.
Geheimnisprüfung: 405 Quelldateien/244 Archiveinträge gegen 14 tatsächliche
Geheimnisquellen, kein Fund. Tatsächliches Android-OTA33->34 mit
Systembestätigung, ohne adb install, danach drei Kalt-/Warmstartchecks bestanden.
Rückweg `20261018T121428Z-9e53947`, keine DB-Rücksicherung/Schemaänderung nötig.

**Öffentliche Lernprobe:** eigener künstlicher regulärer Haushalt, zehn
bestätigte Wörter, genau ein Codex-Auftrag, fünf validierte Prüfaufgaben.
Erste Antwort im Web, vier weitere in nativer Flutter-APK33/API36 fortgesetzt;
Feedback nach Reload, keine Lösungsschlüssel vorab, fünf identische Aufgaben
bei Kind/Eltern. Export mit genau fünf Attempts/Reviewereignissen, einem Projekt
und einer KI-Nutzung geprüft; Haushalt normal gelöscht, alte Sitzungen401,
private Kontodatei entfernt. Keine neue Audio-/physische Telefonabnahme.

**Echter Prüfauftrag:** ursprüngliche Kindersitzung inzwischen abgemeldet,
lokaler Reparaturversuch vor Reservierung korrekt mit401 gesperrt. Betreiber
um normalen frischen Kinderlogin und ausdrückliches „Erneut vorbereiten“ am
ursprünglichen Link gebeten. Kein erfolgreich neu erzeugtes echtes Projekt
behaupten, bevor dessen neuer Auftrag tatsächlich erfolgreich ist.
GitHub-CI39118506744 wegen Kontosperre/Abrechnung ohne Schritte abgewiesen;
Produktlauf39121059397 ebenfalls ohne Schritte wegen derselben gelesenen
Billing-Annotation abgewiesen.

Danach beauftragte Folgearbeiten (noch nicht begonnen):
1. Eltern-Notenimport aus `~/Downloads/Elternportal_fuxNoten.pdf`, aktuelles
   Schuljahr, wiederholbarer Import mit Erkennung bereits vorhandener Noten.
2. `~/Downloads/Schulpilot_Sofatutor_ThemenDB.zip` tatsächlich untersuchen und
   importieren; zentraler vorab vorhandener Fachstamm, kontrollierte
   Altdatenmigration und gemeinsame quell-/stufengetreue Lerntipps integrieren.

3. Bildbasierte A4-Papphefter je Fach, echtes privates Fotoalbum mit
   Blättern sowie Listen-/Kachelansichten. Zentralen Fachstamm weiterverwenden.
PDF und Sofatutor-ZIP liegen jetzt vor. Archiv 1.5 tatsächlich geprüft:
16 Fächer, 126 Stufen (124 aktive und zwei Legacy), 1.558 Themen, 7.559 Videos,
668 Lerntexte, 19.603 bestätigte Video-Zuordnungszeilen. Noch nicht importiert.
PDF lokal ohne KI untersucht; 14 Einzelnoten in sechs Fächern erkannt,
Summen-/Schnittspalten ausgeschlossen, kein individuelles Bewertungsdatum.
Keine Notenwerte oder Namen in Logs/Git übernehmen.

# Aktueller Stand · Foto-Vokabeln 1.4.3+33 · 18.10.2026

**Implementiert und bereitgestellt:** Wörtliche
Wortpaare mit Übersetzung/Sprachbestätigung werden zusammen mit der Heftseite
in den bestehenden Wortschatz übernommen. Unklare Paare bleiben zur Prüfung
offen. Bereits gespeicherte Seiten nachträglich übernehmen, Textkorrekturen
vor Speichern neu prüfen, „Wörter“ im regulären Kinder-/Elternmenü.
Keine neue Migration, keine Anbieter-/Firebaseänderung und keine zusätzliche
automatische KI. Einzelheiten: [LANGUAGE_LEARNING.md](LANGUAGE_LEARNING.md).

Alle 309 Fluttertests einschließlich sechs neuer Material-Widgets bestanden;
dabei echten Refreshfehler behoben:
`LoadView.refresh` gab im setState-Callback einen Future zurück. Menü-/Assistent-
Regressionen zuvor 42 bestanden. 35 gezielte PostgreSQLtests einschließlich
Parallelität, Quellenrevision, Export und Löschung bestanden; finale Analyse
und Ruff ohne Befund. Abschließender vollständiger PostgreSQLlauf:
**806 bestanden in 526,48 Sekunden**. Im ersten Lauf meldete ein bestehender
echter Codex-Katalogtest 503 (804 bestanden); separat, alle 27 Modultests und
der erneute Gesamtlauf anschließend bestanden, Limits unverändert. Web,
signierte Direct-APK und Play-AAB 1.4.3+33 gebaut; Signatur/Zipalign und
bundletool erfolgreich, Versionscode 33. APK 65.168.237 Bytes, SHA-256
`39c3550d8b18a1061d26642a36fb88b43a172176fc805df276240d581cbeb925`.
Geheimnisprüfung: 399 Quelldateien/244 Archiveinträge gegen 16 tatsächliche
Geheimnisquellen, kein Fund.
Zusätzlicher Mischseiten-Test schützt Grammatikregeln vor Übernahme als
vermeintliche Wortpaare.

**Öffentlich aktiviert:** Produktcommit `48add35e43f027bed560d47e2198f4c35f289647`,
main gepusht, Release `20261018T112557Z-48add35`, Schema weiter 0016.
Sicherung Result=success/Exit=0 und sieben vorhandene Dienste aktiv. HTTPS
gültig, HTTP 308, sieben Direktlinks 200 und vier private APIs anonym 401.
Öffentliche APK und Webbundle entsprechen bytegenau den lokalen Artefakten.
Rückweg auf `20261018T101528Z-505312c` dokumentiert, nicht ausgeführt.

**Tatsächliche Browserkette:** normale Anmeldung eines ausschließlich künstlichen
regulären Haushalts, Foto auswählen/zuschneiden, echte Codex-OCR, fünf sichtbare
Wortpaare und Locale, einmalige Quellenbestätigung speichert alle fünf Wörter
mit Übersetzung. Drei reale Übungsantworten, gespeicherte Rückmeldung nach
Reload, Netzverlust/Wiederaufnahme, konsistente Eltern-/Kinderansicht und
weiter offenes gemessenes Zeitminimum geprüft. Eine OCR-Reservierung, keine
weitere KI für Wortübernahme/Runde; Wiederholung ohne Duplikate. Wörter im
regulären Menü, Eltern-Kind-Auswahl und Ansichten bei 320/390/960/1440 px.
Null JavaScript-Laufzeitfehler. Ein anfänglicher Prüfskript-Selektor für das
sichtbare Dropdown wurde korrigiert; gespeicherte OCR fortgesetzt, kein neuer
Anbieteraufruf und keine Produktkorrektur dadurch nötig.

Reales Android-OTA 32 → 33 mit Systembestätigung, kein adb install; drei
Kalt-/Warmstartprüfungen bestanden. Native Flutter-APK33 im API36-Emulator:
Kinderlogin, reguläres Wörter-Menü, drei weitere Bedeutungsaufgaben,
gespeicherte Rückmeldung nach Kaltstart und explizites Weitergehen bestanden.
Elternlogin, eigener Wörter-Menüpunkt, Kind-Auswahl und Wortschatzanzeige
bedient. Eltern sehen exakt sechs Aufgaben aus beiden Clients; keine doppelte
Antwort durch Neustart. Beide Konten auf dem Emulator abgemeldet.

Export aller acht vorhandenen Sprachtabellen geprüft: fünf Wörter, ein Import,
sechs Reviews und sechs eindeutig referenzierte Attempts/Reviewereignisse;
eine OCR-Nutzung. Eigenen künstlichen Haushalt über die normale Account-API
vollständig gelöscht, beide alten Sitzungen danach 401, private Kontodatei
entfernt. Keine neue Firebase-Zustell-, Mikrofon-, physische Telefon- oder
Lernwirksamkeitsprüfung aus diesen Tests ableiten.

GitHub-Produktpush erfolgreich. Actions-Lauf 39115365110: beide Jobs mit null
Schritten wegen bestehender Kontosperre/Abrechnungsproblem abgewiesen; konkrete
Annotation gelesen. Lokale Prüfungen oben bestanden. Nächste optionale
Abnahme: physisches Telefon/Audio mit neuem eigenen künstlichen Haushalt;
GitHub-Abrechnung benötigt die Betreiberaktion. Kein neuer Funktionsblocker
für die geprüfte Foto-Wortkette.

# Bereitgestellt · Design 1.4.2+32 · 18.10.2026

**Implementiert:** gemeinsame Flächenhierarchie für alle drei Rollen auf Web
und Android. Blaugraue Arbeitsfläche, weiße Cards mit sichtbaren Rahmen/Schatten,
eingelagerte Gruppen, stärkere Textkontraste, klare Eingaben und Buttons,
Tastaturfokus, aufgeklappte Details, Statusflächen und hervorgehobene Glocke.
Der Lernraum trennt Kopf, Aufgabe, eigene Antwort, Rückmeldung und Aktionsbereich.
Familienübersicht und Admin-Status verwenden dieselben Komponenten.
Details: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

**Geprüft:** 303 Flutter-Tests einschließlich acht neuer Designprüfungen bestanden;
60 gezielte vorhandene Rollen-/Kinder-/Glockentests zuvor bestanden.
Tatsächliche Fokusrahmen, Text-/Steuerelementfarben und gerenderte Kontrast-
und Beschriftungsprüfungen bei 320/390/1440 px, normaler/doppelter Schrift.
Analyze und Ruff ohne Befund. Drei Backend-Releaseprüfungen bestanden;
keine fachliche Backendänderung außer Versionsnummer, keine Migration.
Weiß/Violett 7,461:1, Sekundärtext/Arbeitsfläche 5,587:1;
Kontrollrand/Arbeitsfläche 3,087:1. Keine pauschale WCAG-Zertifizierung.

**Öffentlich aktiviert:** Produktcommit `505312c3e0949545be9f119e22b69c74cac7b1fc`,
Release `20261018T101528Z-505312c`, Schema unverändert 0016.
Web, signierte Direct-APK und Play-AAB gebaut; Signatur/Zipalign und bundletool
bestanden, beide Android-Artefakte mit Versionscode 32. Geheimnisprüfung über
391 Quelldateien/244 Archiveinträge gegen 16 tatsächliche Geheimnisquellen:
kein Fund. APK 64.922.473 Bytes, SHA-256
`88b5b6d7231a7481050e29395f74d65813c79e3a6b5a5c85627362d5f8d4e31d`.
Sicherung Result=success/Exit=0, sieben bestehende Dienste aktiv. Gültiges HTTPS,
HTTP 308, sieben Direktlinks 200, vier private APIs anonym 401. Öffentliche
APK und Webbundle stimmen bytegenau mit den lokalen Releaseartefakten überein.
Chrome auf öffentlichem HTTPS: 24 Ansichten aller Rollen bei vier Breiten,
null Laufzeitfehler/fehlgeschlagene API-Leseaufrufe. Vorgängige Loopback-Vorschau
mit 23 Ansichten und Farbzählung zusätzlich geprüft. Kein externer KI-Aufruf.
Reales OTA 31 → 32 über Android-Systembestätigung erfolgreich, kein adb install;
anschließend drei Kalt-/Warmstart-Updatechecks erfolgreich.
Native Flutter-APK32 im API36-Emulator: eigener Kinderlogin, sichtbare Glocke,
Heftsammlung, Verstehen und alle vier Aufgabenformen tatsächlich bedient.
Eingaben mit offener Tastatur, grüne Rückmeldung, explizites Weitergehen,
App-Neustart und Wiederaufnahme derselben Rückmeldung geprüft. Eltern sehen
exakt vier gespeicherte Antworten; native Elternansicht und Logout geprüft.
Ältere Prüfskriptbezeichnungen an „Rückmeldung ansehen“/„Ergebnis ansehen“
angepasst; keine zusätzliche Antwort zum Wiederaufnehmen gesendet.
Eigener künstlicher Haushalt danach gelöscht, private Kontodatei entfernt.
Keine physische Telefon-, Audio-, Screenreader- oder Lernwirksamkeitsabnahme.
Aktuell nächste Aktion: den unten ausdrücklich beauftragten Vokabel-Zusatz umsetzen.

GitHub-Push von 505312c nach main erfolgreich. Cloud-CI-Lauf 39110829970 startete
laut GitHub-Annotation wegen bestehender Kontosperre/Abrechnungsproblem nicht;
keinen fehlgeschlagenen Test daraus ableiten. Lokale Prüfungen siehe oben.

**Danach ausdrücklich beauftragter Zusatz:** erkannte Vokabelseiten bis zu
Wortpaaren in der bestehenden Wortschatzdatenbank führen und „Wörter“ als
regulären Menüeintrag anbieten. Quellen-/Sprachbestätigung und Revisionen
erhalten; keine ungeprüften Ergänzungen als Unterrichtsstoff übernehmen.

# Bisheriger Stand · Benachrichtigungen 1.4.1+31 · 17.10.2026

**Öffentlich aktiviert:** Produktcommit `dd6e30c09c41c1455f743c20ff5e26862bae298a`,
Release `20261017T202938Z-dd6e30c`, Migration 0015 → 0016. Backend/Web und reguläre
signierte Direct-APK unter https://schulpilot.dorfspy.de. Erfolgreiche Sicherung
(Result=success/Exit=0), alle sieben geprüften bestehenden Dienste aktiv.
HTTPS gültig, HTTP 308, sechs Direktlinks 200, drei private Push-APIs anonym 401;
öffentlicher APK-Download und main.dart.js stimmen mit den lokalen Hashes überein.

**Neu:** sichtbare Glocke auf Android und im Browser, echte private Neuigkeiten
und kontogebundene Lesemarkierungen. Gerätefreigabe über „Gerät einstellen“;
Elternfreigabe, Android-Berechtigung und Kanalstatus werden konkret angezeigt.
Nativer neutraler Android-Kanal/Vordergrundhinweis, Token-Erneuerung und
Fertigmeldungen für Sprach-/Wortaufträge. Keine Firebase-Initialisierung durch
Glocke/GET; keine neue KI, Anbieter-, Schlüssel- oder Freigabeänderung.
Einzelheiten/Bedienung: [NOTIFICATIONS.md](NOTIFICATIONS.md).

**Tatsächliche Zustellung:** Android-API-36-Emulator mit nativer Flutter-APK 31:
Glocke sichtbar, Kinder-Opt-in registriert. Activity STOPPED vor dem einzigen
Hintergrund-Testversand nachgewiesen; FCM-Annahme, tatsächliche Android-Meldung
und Öffnen der Neuigkeiten im richtigen Kinderkonto beobachtet. Gesonderter
Vordergrund-Test: In-App-Hinweis und native Android-Meldung bei aktiver App
sichtbar. Beide Testsendungen ausschließlich an das eigene künstliche Gerät.
Danach Registrierung entfernt und abgemeldet. Web/Chrome: echte gespeicherte
Familienanfrage, Lesemarkierung und Reload konsistent; explizites Opt-in,
Installations-/Registrierungs-API jeweils 200, eigener /push/-Worker, eigene
FCM-Validierung und Annahme mit sichtbarem Vordergrundbanner, Logout 401.
Anfängliche Web-Prüfskriptfehler (zusammengefasste Flutter-Semantik und nicht
abgewartetes POST) korrigiert; kein Softwarefehler oder Zustellbeleg daraus
abgeleitet. Abschließender öffentlicher Lauf erfolgreich.

**Build und Regressionen:** 791 PostgreSQL- und 295 Flutter-Tests bestanden.
Zusätzliche gezielte Push-/Migrationsprüfung 25, Inboxprüfung 5 und Flutter-
Push-/Geräte-/Anmeldetests 12 bestanden. Analyze/Ruff ohne Befund. Finales Web,
Direct-APK und Play-AAB gebaut; Signatur/Zipalign und bundletool 1.18.3 erfolgreich.
386 Quelldateien/244 Archiveinträge gegen 14 echte Geheimnisquellen geprüft,
kein Fund. Bestehende Hinweise zu künftigem Kotlin/optionalem Wasm bleiben;
JavaScript-Webrelease und native Builds erfolgreich, keine Abhängigkeitsmigration.

APK 1.4.1+31: 64840505 Bytes,
SHA-256 `21c2529a4d568f68be631723c90c74c870f10b525f8fb7c820e2ec264c490b77`.
`artifacts/schulpilot-android.apk` und `artifacts/schulpilot-play.aab`.
Tatsächlicher OTA-Pfad im Emulator von 30 auf 31 mit Android-Bestätigung,
kein adb install; anschließend drei Updatechecks bei Kalt-/Warmstarts bestätigt.

**Firebase/Betrieb:** bestehendes Projekt/Apps/APIs/minimale Senderrolle und
getrennte Plattformkeys geprüft. Runtime nutzt das dedizierte Senderkonto aus
/etc/schulpilot/fcm-service-account.json (root:schulpilot 0640). Echter OAuth-
Refresh und validate_only HTTP 200 am Server. Lokale Probe scheiterte an der
versetzten Entwicklungsuhr; dies betrifft nicht den geprüften Appserver.
Produktionsfreigabe unverändert aktiv. Codex CLI/gpt-6.1-sol/xhigh/Revision 18
unverändert. Eigene künstliche Alt-Testsitzungen widerrufen, drei Prüfanfragen
als besprochen markiert, beide Testkonten ohne aktive Pushgeräte abgemeldet.

**Grenzen:** keine physische Smartphone-/Huawei-Abnahme und keine erneute
Web-Systemanzeige im Hintergrund; Webnachweis betrifft das Vordergrundbanner.
Play-AAB nicht im Store veröffentlicht. GitHub-Actions-Lauf 39058428549 startete
wegen Kontosperre durch ein Abrechnungsproblem nicht; lokale Prüfungen bestanden.
Keine allgemeine Zustellgarantie gegen Gerätesperren/fehlende Play-Dienste.
Rückweg: vorheriger Release 20261017T140346Z-58f2c8c mit --rollback-compatible,
additive Tabelle erhalten. Keine produktive Rücksicherung durchgeführt.
Nächste optionale Prüfung: eigener physischer Android-Alltag mit denselben
Gerätefreigaben; reguläre Anmeldung, keine privaten Schlüssel weitergeben.

# Aktueller Stand · Sprachausbau 1.4.0+30 · 17.10.2026

Eigener bestätigter Wortschatz aus Foto, Text oder manuellen Paaren; Sammlungen,
Suche/Seitenteilung, Revisionen, kleine echte Abrufrunden und getrennte Fähigkeiten
und Richtungen. Tagesplan, Elternansicht und gebündelte neutrale Erinnerungen sind
integriert. 18 begrenzte Sprachprojektarten verbinden Quellen, eigene Entwürfe,
beratende Kriterien und interaktive Aufgaben. Datenmodell, Modusregeln und die
20 Werkzeugzuordnungen: [LANGUAGE_LEARNING.md](LANGUAGE_LEARNING.md).

**Öffentlich aktiviert:** 1.4.0+30, Produktcommit `58f2c8cbe874a3e6e0802e0a64190749efec5d91`,
Release `20261017T140346Z-58f2c8c`, Migration 0014 → 0015. Eigene Sicherung mit
Result=success/Exit=0, sieben vorhandene Dienste aktiv. Gültiges HTTPS,
HTTP-Weiterleitung 308, sieben Direktlinks 200 und drei private Routen anonym 401.
Vollständiger öffentlicher APK-Download in Größe/Hash geprüft. Provider unverändert
Codex CLI 0.162.1, gpt-6.1-sol/xhigh, Revision 18; keine Firebase-Änderung.

**Tatsächlicher öffentlicher Funktionstest:** Eigenes normales künstliches Konto
über echte Bestätigungsmail verifiziert; Kind im Browser angemeldet. Normaler
Fotoassistent/Zuschnitt → wörtliche Codex-Erkennung → bestätigte Heftseite → eigener
Wortschatzauftrag → fünf bestätigte Paare → drei beantwortete Aufgaben. Offline-
Wiederholung, gespeicherte Rückmeldung nach Reload, gleiche Eltern-/Kinderstände,
noch nicht erfülltes 20-Minuten-Ziel aus echten Sekunden und Wortvorschlag im Plan
geprüft. Kindansichten bei 320/390/1280 px und Eltern bei 390/1280 px bedient.
Zwei echte KI-Kontextaufgaben, zwei belegte Simple-Present-Aufgaben und drei
beratende Kriterien zum eigenen künstlichen Text erzeugt. Sechs Reservierungen:
fünf erfolgreiche Aufträge und ein gespeicherter früherer Fehler; Kontokosten
unbekannt. Keine zusätzlichen automatischen Aufrufe. Null Browserlaufzeitfehler.

**Gefundene Korrektur:** Die bisherige Schemaaufbereitung entfernte das echte
Feld title aus properties. Dadurch war das neue Sprachprojekt-Schema ungültig
(HTTP 400). Feldnamen und Schemaknoten werden jetzt getrennt verarbeitet; ein
gezielter Regressionstest sichert die vollständigen required-Felder. Der
fehlgeschlagene Auftrag wurde nicht überschrieben; genau ein bewusster neuer
Auftrag nach Bereitstellung der Korrektur gelang.

**Lokale Tests:** 784 isolierte PostgreSQL-16-Tests im Gesamtlauf bestanden
(437,99 s), anschließend 94 gezielte Prüfungen sowie drei abschließende
Migrations-/Datenschutz-/Parallelitätsprüfungen. Nach Schemafix weitere 70
Provider-/Sprachtests und 21 Mathematik-/Coach-Regressionen bestanden. Alle 285
Fluttertests im Gesamtlauf, nach letzter Statuskorrektur zehn Wortschatz-Widgettests
bestanden. Analyse und Ruff ohne Befund. Keine Abhängigkeiten aktualisiert.

**Finaler Build:** Web, signierte Direct-APK und Play-AAB 1.4.0+30 gebaut;
Analyse und zehn finale Widgettests bestanden. APK 64.806.733 Bytes, SHA-256
`c40e2af9a288cb2ab0c587a198c0414664bc0f28042d70ea8a0ad37a51c3b169`.
Die Oberfläche unterscheidet vorbereitete, begonnene und pausierte Runden
ausdrücklich. bundletool 1.18.3, Signatur, Paket und 16-KB-Zipausrichtung geprüft.
Geheimnisprüfung über 376 Quelldateien, Web, 242 Archiveinträge und Übergaben mit
16 tatsächlichen Geheimniswerten: null Treffer. Kotlin-/optionale Wasm-Hinweise
bleiben ohne Fehler der tatsächlichen JavaScript-/Android-Releasebuilds.

**Native Abnahme:** Android-API-36-Emulator, reguläre Flutter-APK 1.4.0+30.
Echte automatische Updates 28 → 29 und 29 → 30 über den Android-Systeminstaller,
kein adb install für die Updates. Je drei Kaltstart-/Wiederöffnungsprüfungen
bestanden. Eigenständiger Kinderlogin, vorhandenes Kontextprojekt mit zwei
Tastaturantworten und gespeicherter Rückmeldung abgeschlossen, Kaltstart und
Wiederaufnahme geprüft. Fünf echte Aufgaben insgesamt (drei Web, zwei Android),
keine doppelten Antworten oder zusätzlichen KI-Aufrufe. Bei früheren wiederholten
Prüfanmeldungen griff die reguläre Drossel; das Zeitfenster wurde abgewartet,
keine Schutzgrenze gelockert. Der abschließende Browserlauf auf Build 30 erzeugte
null weitere Modellreservierungen und bestätigte die vorbereiteten Statuswerte.

**Export/Löschung:** Der tatsächliche private Familienexport enthielt alle acht
neuen Tabellen, fünf unveränderte Attempts und genau fünf referenzierende
Reviewereignisse. Kind-/Elternfortschritt nach Android identisch. Ausschließlich
den eigenen künstlichen Haushalt gelöscht; alte Kinder-/Elternsitzungen danach
401. Auch die native App verlangte nach Kaltstart wieder die normale Anmeldung.
Private Exportbytes blieben nur im Speicher, die lokale Kontodatei ist entfernt.

**Verbleibende Grenzen:** Physisches Telefon, hörbare englische/deutsche Ausgabe
und echte Mikrofon-/Berechtigungsbeobachtung sind nicht abgenommen. SDK-/Mocktests
beweisen keine Audioqualität oder Lernwirksamkeit. Alle 18 Projekte sind im
Transport-/Worker-Test geprüft; echte Modellprüfungen hier für Kontext, Grammatik
und Textfeedback. Optionaler Druck-/PPTX-Export bleibt offen. GitHub-Actions startet
wegen Kontosperre durch ein Abrechnungsproblem nicht (Run 39031127815); sämtliche
oben genannten Tests/Builds wurden lokal durchgeführt. Push nach main erfolgreich.
Nächster konkreter Schritt: TTS/STT mit echten Sprachvarianten, fehlender Stimme,
Mikrofonverweigerung und Routen-/Hintergrundwechsel auf einem physischen Telefon
prüfen. Der laufende Kernablauf ist öffentlich und nativ geprüft.

## Vorheriger geprüfter Produktstand

Quellversion **1.3.0+28** für Flutter Web und native Android-App. Das zusammenhängende [Lernmodell](LEARNING_MODEL.md) verbindet bestätigten Heft-/Arbeitsheftstoff, schulische Schwerpunkte, kurze Erklärungen mit belegten Beispielen, eigene Anwendung, gestufte Hilfe und spätere Abrufe. IES/WWC und die EEF-Leitfäden wurden tatsächlich erneut geprüft; Umsetzung und Schwellen bleiben Produktentscheidungen, keine Garantie besserer Schulnoten.

**Alle Übungen:** Führende Anzeige aus allen gespeicherten Versuchen, einschließlich freiwilliger Übungen und begonnener Runden. Aufgaben einmal je Runde/Aufgabenkennung, weitere Versuche separat. Alleine im ersten Versuch, unterstützt/erneut richtig, weiter zu üben und Bewertung offen bleiben unterscheidbar. Gleiches bestätigtes Fach/Thema über verschiedene Lernfolgen zusammengefasst; kein Abschneiden nach 100 Wurzeln. Kind und Eltern öffnen Fach → Thema → einzelne Runden mit Seitenteilung. Die strengen späteren Prüftage stehen als zusätzliche aufklappbare Beobachtung; sie ersetzen oder löschen keine Übungsleistung. Vorhandene Antworten und Zeiten werden nicht umgeschrieben.

**Eltern und Noten:** Kinderdetail enthält Fächer & Fortschritt und Noten. Echte private CRUD-Verwaltung mit Skalen 1–6/0–15, Datum, Fach, optional Thema/Notiz, Gewicht und stabilem Export. Revisionsgebundene Änderung, idempotentes Anlegen auch unter Parallelität. Leseberechtigte Eltern können nachvollziehen, nicht ändern; Kinder, fremde Familien und Betriebsadministratoren erhalten keinen Notenzugriff. Höchstens fünf aktuelle Einträge je Fach/90 Tage beeinflussen das Gewicht im Wochenplan und die Auswahl der ersten Fächerportion; Tages-/Wochenminima, Pflichttermine und Elternvorgaben bleiben erhalten. Gewichtung abschaltbar. Passendes bestätigtes Material kann ausdrücklich in einen verbindlichen Elternauftrag übernommen werden, sonst ehrlicher Hinweis auf die fehlende Quelle. Notenänderungen und reine Fortschrittsabfragen starten keine KI. Export, Löschung und 365-Tage-Aufbewahrung enthalten die neuen Daten.

**Unterrichtliche Unterstützung:** Neue Einheiten, Pakete und Lernwegetappen erhalten eine aus tatsächlichen Schwierigkeiten oder schulischen Schwerpunkten abgeleitete Unterstützungsstrategie. Mehr Anleitung mit kleinen belegten Beispielen, anschließend eigene Anwendung; kurze Hilfen zum nächsten Teilschritt. Keine automatische Übermittlung gespeicherter Schulnoten oder Notennotizen an die KI. Bestehende zielbezogene Lernbegleitung, Quellenbindung, Klassenstufe, Aufgabenvalidierung, Kosten-/Sitzungs-/Providerprüfungen bleiben bestehen. Vorhandene Aufgaben werden nicht nachträglich geändert.

**Prüfung vor Bereitstellung:** Vollständiger isolierter PostgreSQL-16-Lauf: 720 Tests bestanden (560,18 s); zusätzlich ein danach ergänzter Test der echten Schultagplanung mit vier bestätigten Fächern bestanden. Alle 269 Fluttertests im Gesamtlauf bestanden; nach Erweiterung der mobilen Formprüfung weitere zwölf gezielte Tests bei 320/390/1280 px bestanden. Flutter-Analyse, Ruff und Diffprüfung ohne Befund. Der Parallelitätstest fand zunächst einen Zwischencommit des Rate-Limits, der die Idempotenzsperre löste; auf gemeinsame Transaktion korrigiert und durch gezielten sowie vollständigen PostgreSQL-Lauf bestätigt. Keine echten Kinderdaten oder externen KI-Aufträge in diesen Tests.

**Build:** Web, signierte Direct-APK und Play-AAB 1.3.0+28 erfolgreich; gleiche fixierte SDKs und Signieridentität. APK 64.445.825 Bytes, SHA-256 `9c2bffd5c0142eee3c580d89ef25da27723149b93554890bdb68915940e7b000`. bundletool 1.18.3, apksigner und 16-KB-Zipausrichtung erfolgreich. Bestehende Pluginhinweise zu Kotlin und optionalem Wasm bleiben; der tatsächliche JavaScript-Webbuild und beide nativen Releasebuilds sind erfolgreich. Geheimnisprüfung über Quellen, Web, beide Androidarchive und bereinigte Übergaben: 360 Quelldateien, 242 Archiveinträge, 14 tatsächliche Geheimniswerte, null Treffer.

**Bereitstellung:** Produktcommit `8770118ef04f7be6655fc49feb4616fc5c45b5f7`, Release `20261017T104304Z-8770118`, öffentlich https://schulpilot.dorfspy.de . Health bestätigt den Quellstand, KI verfügbar. Vollständiger öffentlicher APK-Download stimmt in Größe/Hash mit Manifest und lokalem Build überein; elf Webdirektlinks 200, fünf private API-Routen anonym 401, gültiges HTTPS und HTTP-Weiterleitung 308. Schema 0014 und unveränderte Codex-Konfiguration (gpt-6.1-sol, xhigh, Revision 18) am Server bestätigt. Eigene Konfigurations-/Datenbanksicherung erfolgreich; sieben bestehende Dienste einschließlich der drei anderen DorfSpy-Anwendungen aktiv. Vorheriger Releasepointer `20261017T103014Z-7fc41e0`; davor `20261017T085036Z-14d1789` mit Schema 0013. Migration 0014 ergänzt nur Schulnoten und eine eigene Planungsoption; bestehende Elternpräferenzen und Planfingerprints ohne Noten bleiben erhalten. [Sicherung und kompatibler Rückweg](OPERATIONS.md).

**Öffentliche Bedienung:** Genau eine eigene feste künstliche Familie, ein Initialjob, alle vier Aufgabenkomponenten, fünf Versuche, ein Hinweis und gespeicherte Rückmeldung nach Reload. Abschluss und nächste bereits gespeicherte Runde tatsächlich gerendert. Kind/Eltern sehen dieselben vier geübten Aufgaben, drei selbstständige und eine unterstützte Lösung; Fach → Thema → Runde bedient. Im Elternbereich eine Schulnote und ausdrücklich ein quellgebundener Pflichtauftrag über die Oberfläche angelegt, Schwerpunkt 2 bestätigt; Kind erhält für Schulnoten 403. Ansichten bei 320/390/1280 px visuell geprüft. Zwei Treiberläufe korrigierten die zusammengefasste Kartensemantik und die normalisierten zugänglichen Buttonnamen am selben Fall, ohne neue Familie, Antworten oder Aufgaben zu erzeugen. Danach vollständig erfolgreich, keine blockierten Mutationen oder Laufzeit-/Layoutfehler. Null externe KI-Aufträge und Reservierungen; Familie regulär gelöscht und beide Sitzungen 401. Bericht: `artifacts/child-learning-room-result.json`.

**Native Android-App:** Automatisches Update 27→28 über Appprüfung, geprüften Download und Android-Installationsbestätigung, ohne `adb install`. Drei weitere Startprüfungen bestanden. Auf installierter APK 28 genau eine eigene künstliche Familie/ein Initialjob: alle vier Komponenten, Prozessneustart mit derselben Rückmeldung, bewusster Tipp/erneute Antwort/Pause/Fortsetzung und Abschluss geprüft. Fünf Versuche, drei selbstständige/eine unterstützte Lösung; 111 gespeicherte aktive Sekunden und 20 Minuten Mindestziel in Eltern- und Kinderansicht übereinstimmend, Mindestziel bleibt offen. 20 beobachtete Pausensekunden erzeugten null Gutschrift. Fach-/Themenfortschritt und private Noten in der nativen Elternansicht bedient und visuell geprüft. Familie regulär gelöscht, Sitzungen 401, App wieder im Gastzustand, eigene Appdaten und privates Journal entfernt. Null externe KI-Aufträge. Bericht: `artifacts/progress-grades-native-result.json`. Kein physischer Geräte-, akustischer Sprach-, neuer Google-/FCM- oder Play-Uploadnachweis daraus abgeleitet.

**CI:** [Produktlauf 39017676358](https://github.com/meinzeug/schulpilot/actions/runs/39017676358) verweigert beide Jobs mit null ausgeführten Schritten wegen einer Abrechnungssperre des GitHub-Kontos. Push erfolgreich, lokale Tests und Builds tatsächlich ausgeführt; kein erfolgreicher gehosteter CI-Lauf behauptet.

**Abschließender Fachfilter:** Mathe/Mathematik und unterschiedliche Groß-/Kleinschreibung werden jetzt auch beim Notenfiltern gemeinsam behandelt. Eine bereits aktive Auswahl bleibt nach dem Löschen ihres letzten Eintrags darstellbar. Nach dieser Backendkorrektur alle 45 gezielten PostgreSQL-Tests zu Noten, Lernstand, Migration und Datenschutz bestanden (23,59 s). Mit Produktcommit `8770118ef04f7be6655fc49feb4616fc5c45b5f7` bereitgestellt und Health/Download/Direktlinks erneut geprüft. Appquellen und signierte APK sind identisch zum vollständig auf Web/Android geprüften Stand `7fc41e0`. Auf dem neuen öffentlichen Backend mit genau einer weiteren eigenen künstlichen Familie ohne Lernjob drei Noten angelegt: Alias-/Großschreibungsfilter, Seitenteilung und aktive Auswahl nach Löschung des letzten Facheintrags erfolgreich. Null KI-Aufrufe/Reservierungen, Familie regulär gelöscht und Sitzung 401; privates Journal entfernt. Bericht: `artifacts/progress-grades-filter-public-result.json`. Damit alle drei eigenen öffentlichen Testfamilien dieser Arbeitseinheit bereinigt. Weitere tatsächliche Geheimnisprüfungen während beider UI-Fälle mit 21 und während des Filterfalls mit 17 Geheimniswerten: null Treffer.

---

## Vorheriger bestätigter Stand und historische Prüfungen

# Aktueller Stand · Geführte Kinder-Lernrunde · 17.10.2026

Flutter Web und native Android-App 1.2.0+27: Der Lernablauf wurde mit drei weiteren Agents vor der Umsetzung, während der Diskussion und nach der Umsetzung gegen UX-Leitlinien und Primärquellen zur Lernforschung geprüft. Konkrete Gegenargumente führten zu sichtbaren täglichen Fotos neben dem Resume, fachlichem Abschluss vor allgemeinem Weiterlernen und einer Hauptaktion mit eigenem Platz statt eines Tastaturoverlays. Die Gestaltung ist eine Produktentscheidung, kein behaupteter Wirksamkeitsnachweis dieser App. [Quellen](SOURCES.md), [Ablauf](DAILY_ROUTINE.md).

**Einstieg:** Stabile „Deine Lernrunde“-Karte, vorhandene aktive/pausierte Runde vorrangig, heutige Heftfotos direkt daneben und „Anderes Thema“. Ungelesene letzte Rückmeldung auch nach abgeschlossener Einheit vom Home aus erreichbar. Vorbereitungsstatus erzeugt keine weiteren Aufgaben; bestehende Runden bleiben zugänglich. Kindliches Lernen zeigt Suche/Fach/Filter auf Anfrage, die paginierte Bibliothek und Elternansichten bleiben erhalten. Verbindliche Elternaufträge werden auch nach erreichtem Zeitminimum nicht freiwillig umetikettiert.

**Während der Runde:** Ruhiger eigener Lernraum mit Verstehen → Üben → Rückblick, kompakter echter Sekundenanzeige und Zeitdetails auf Wunsch. Frage, eigene Antwort und konkrete Rückmeldung bleiben zusammen sichtbar. Ein Hilfezugang liefert zuerst einen bestehenden Tipp; weiterführende Erklärung, Heftfrage, Elternhilfe und Schwierigkeitsrückmeldung auf Wunsch. Exklusive Auswahl mit Tastatur, vollständige Zuordnungsbegriffe statt abgeschnittener Dropdowntexte. Pause und Verlassen bleiben erreichbar; die Hauptaktion erhält eigenen Platz, auch bei Tastatur und großer Schrift. Keine automatische Sprache oder versteckte Mikrofonaufnahme.

**Ergebnis und Wiederaufnahme:** Letzte Antwort führt immer erst zum fachlichen Ergebnis. Gespeicherte selbstständige Lösungen, Hilfe, unklare Antworten und weiter zu übende Aufgaben getrennt; passende fachliche Anschlussaktion zuerst. Das echte Mindestziel bleibt davon unabhängig verbindlich. Neue Rückmeldungen werden serverseitig gespeichert und ausdrücklich idempotent quittiert; ACK erzeugt keine Antwort, Lernzeit oder KI-Kosten. Alte Clients und ein älteres Backend bleiben ohne automatische Antwortwiederholung benutzbar. Routen-/Kontowechsel verhindern späte Rücksprünge oder die Übernahme alter Inhalte. Drei Prüftage allein erzeugen keine behauptete hundertprozentige Beherrschung.

**Vorbereitung:** Ein bewusster neuer Einzelrundenauftrag öffnet eine eigene Statusseite statt eines minutenlang blockierten Startknopfs. Reine Status-GETs, Hintergrundverarbeitung, kein automatischer Neuversuch und bewusstes Beginnen nach Fertigstellung. Quellen-, Zukunftstermin-, Rollen-, Quoten- und Kostenprüfungen unverändert. Keine Schemaänderung oder Migration und keine Providerumstellung.

**Lokale Prüfung:** 688 Backendtests mit isoliertem PostgreSQL 16 bestanden (642,58 s). Nach der ergänzten kompakten Rückmeldungs-Wiederaufnahme weitere 54 gezielte PostgreSQL-Prüfungen zu Feedback, Bibliothek, Mindestzeit und Konten bestanden (40,02 s), einschließlich paralleler ACKs, fremder Familien und Datenerhalt. Abschließend alle 259 Fluttertests bestanden (90 s); Flutter-Analyse ohne Befund, Ruff und Diffprüfung sauber. Der erste komplette Flutterlauf fand einen alten Textfinder im Einführungstest; auf die tatsächlich sichtbare Phasen-Semantik angepasst und vollständig erneut geprüft. Keine externen KI-Aufträge in diesen isolierten Tests.

**Sichtprüfung und Korrektur:** Die erste öffentliche Version 26 bestand den vollständigen Aufgabenablauf, zeigte im Web aber fälschlich 0:00 bei einem echten 20-Minuten-Ziel. Ursache: zwei übergroße Bitshift-Grenzen bei der Formatierung; gespeicherte Zeit und Ziel blieben korrekt. Version 27 ersetzt genau diese beiden Grenzen durch portable Zahlen. Der echte Chrome-Widgettest zeigt nun 20:00 als positives Ziel und Rest sowie 2:00 Einheitszeit, zusätzlich alle 16 Zeitmessungstests auf der nativen Dart-VM bestanden. Keine Änderung an Heartbeat-, Mindestziel- oder Backendregeln.

**Öffentliche Lernrunde:** Mit genau einer eigenen festen künstlichen Familie alle vier Aufgabentypen, fünf Antworten (eine erste falsche und vier richtige), ein Hinweis, fünf Rückmeldungsquittungen und Neuladen mit erhaltener Rückmeldung bedient. Abschluss bei 320/390/1280 px: drei selbstständige und eine unterstützte Lösung, keine erfundenen Leistungen, Tagesminimum bleibt offen. Gespeicherte nächste synthetische Runde direkt gestartet (HTTP 200, Unitroute), keine neue Übung erzeugt; erster Folgerunden-Screenshot noch mit Ladespinner, daher daraus keine fertig gerenderte nächste Aufgabe behauptet. Eltern sehen dieselben fünf Antworten und den Hinweis. 14 normale UI-Heartbeats mit HTTP 200 beobachtet, keine vollständige Body-/Zeitmessungsabnahme daraus abgeleitet. Null externe KI-Aufträge/Reservierungen, keine blockierten Mutationen oder Laufzeitfehler. Familie regulär gelöscht, Eltern-/Kindersitzungen danach 401. Bericht: `artifacts/child-learning-room-result.json`.

**Einstieg im Android-Browserprofil:** Vorbereitet, aktiv und pausiert bei 320/390/1280 px geprüft; Lernrunde, tägliche Fotos, anderes Thema und reduzierte Lernliste erreichbar. Echter Start, UI-Pause und bewusste Wiederaufnahme jeweils HTTP 200, fertiger Vorbereitungslink rein lesend. Tatsächliche geklickte Nebenflächen 48 px, Hauptaktion 52 px hoch. Genau eine eigene feste künstliche Familie/ein Initialjob, keine Antworten/Hinweise oder externen KI-Aufträge. Anfängliche Treiberfehler bei User-Agent, Semantics-Aktivierung und einem oberen Randabstand am selben Fall korrigiert; keine Ersatzfamilie erzeugt. Der erste schmale Linux-Desktopversuch ist kein Mobilnachweis. Derselbe Fall wurde für den rein lesenden Zeitvergleich regulär pausiert; nach der Prüfung normal gelöscht (HTTP 200), Eltern-/Kindersitzungen danach 401 und privates Journal samt temporären Dateien entfernt. Bericht: `artifacts/child-learning-entry-cleanup-result.json`. Der laufende Wartestatus wurde nicht live erzwungen; der fertige Statuslink live, Warte-/Fehler-/Routenfälle mit Widgettests geprüft.

**Build:** Web, signierte Direct-APK und Play-AAB 1.2.0+27 mit unveränderter fixierter Toolchain erfolgreich gebaut; APK 63.790.101 Bytes, SHA-256 `5751deb347ca12cdd6212e1ca9b3fa1b849494a31bab555963331130175b3b2a`. Paket, stabile Signieridentität, 16-KB-Zipausrichtung und AAB mit bundletool 1.18.3 geprüft. Ein vorheriger Buildprozess endete nach dem erfolgreichen Webbuild mit Signal/Exit 143; Ursache nicht unabhängig belegt. Den vollständigen Release-Build danach erfolgreich erneut ausgeführt, den ersten Log erhalten. Keine abgebrochenen Teilartefakte veröffentlicht. Produktcommit `14d1789993a5c7a33ea9d9207433babd61c46eb3` auf `main` gepusht; öffentliches Release `20261017T085036Z-14d1789`, https://schulpilot.dorfspy.de . Health bestätigt den Quellstand, KI verfügbar. Öffentlichen vollständigen APK-Download mit lokalem Build und Manifest verglichen: Version, Größe und Hash stimmen. Neun Webdirektlinks 200, private API anonym 401, HTTPS geprüft und HTTP-Weiterleitung 308. Sieben bestehende Dienste einschließlich der drei anderen DorfSpy-Anwendungen aktiv; Konfigurations-/Datenbanksicherung erfolgreich, vorheriger Releasepointer `20261017T083609Z-ec48f1f`. Keine Migration, Providerwechsel oder Änderung bestehender Freigaben; Workerfingerprint erhalten. Rückweg: [OPERATIONS.md](OPERATIONS.md).

**CI:** [Produktlauf 39011474012](https://github.com/meinzeug/schulpilot/actions/runs/39011474012) hat beide Jobs ohne einen ausgeführten Schritt abgewiesen: GitHub-Konto wegen Abrechnungsproblem gesperrt. Push erfolgreich, lokale Prüfungen/Builds tatsächlich ausgeführt; kein erfolgreicher gehosteter CI-Lauf behauptet. Kontoinhaber muss diese GitHub-Sperre klären.

**Öffentlicher Zeitvergleich auf 27:** Derselbe pausierte künstliche Fall ausschließlich mit GET/HEAD bei 320/390/1280 px gelesen. Server und Übersicht: eine gespeicherte aktive Sekunde, 20 Minuten Ziel. Tatsächliche Darstellung „Heute 0:01 / 20:00“, „Diese Einheit 0:01“ und „Noch 19:59 Min.“ stimmt überein. Status, Antworten, Hinweise, Aktivität, Kontingente und privates Journal unverändert; keine neuen Logins/Familien/Jobs oder Laufzeit-/Layoutfehler. Screenshots visuell geprüft. Bericht: `artifacts/learning-clock-readonly-result.json`.

**Android-Update:** Reguläre Appprüfung, geprüfter Download und Android-Installationsbestätigung für 25→26 sowie 26→27 auf eigenem API-36-Emulator erfolgreich, kein `adb install` beim Upgrade. Auf 27 drei zusätzliche reale Prüfungen bei Kaltstart, Wiederöffnen aus dem Hintergrund und weiterem Launcher-Intent bestanden. Bestehender eigener Lernfall blieb dabei erhalten. Kein Play-Upload oder physischer Gerätetest daraus abgeleitet.

**Native Lernrunde und Elternvergleich:** Derselbe eigene künstliche Fall auf installierter APK 27 fortgesetzt, keine Ersatzfamilie oder erneute Erzeugung. Alle vier Komponenten bedient; falsche Antwort samt eigenem Wert und Rückmeldung nach echtem Prozessneustart mit derselben Versuchkennung wiederhergestellt. Ein ausdrücklicher Tipp, richtige Wiederholung als unterstützt, insgesamt fünf Versuche (2/1/1/1), drei selbstständige und eine unterstützte Lösung. Rückmeldungen ausdrücklich quittiert, letzte Antwort zuerst zum fachlichen Ergebnis. 20 echte Sekunden manueller Pause: null Sekunden Gutschrift; Quittung im pausierten Zustand startet die Runde nicht neu. Eltern-Familie und Kinderdetail zeigen dieselben 184 Sekunden (3:04) bei 20 Minuten Mindestziel, somit 16:56 weiterhin offen. Rollenprüfung bestanden. Feste synthetische Anschlussrunde nur gelesen, unbegonnen und ohne Antworten belassen; kein weiterer Start/Job oder externer KI-Auftrag. Bericht: `artifacts/learning-room-native-result.json`.

Der erste native Anlauf wurde beim Erkennen des Web-Zeitfehlers im selben privaten Fall angehalten und nach OTA27 fortgesetzt. Eine zu enge QA-Annahme über einen synthetischen Rückblick wurde danach korrigiert: Der feste Coach kann seine feste Anschlussrunde unmittelbar ohne Job/Provider speichern. Ursprünglichen Fehlbericht erhalten, nur den Prüftreiber ergänzt und denselben abgeschlossenen Fall am Ergebnis fortgesetzt; keine Produktänderung. Familie normal gelöscht, Eltern-/Kindersitzungen danach 401, Appneustart am Gastlogin, nur Daten des eigenen Emulatorpakets geleert und privates Journal entfernt. Alle drei eigenen Familien dieser Abnahme regulär bereinigt.

**Abschlussprüfung:** Quellen, Web, entpackte APK/AAB und bereinigte Übergabe gegen tatsächlich vorhandene private Werte geprüft: null Treffer; während der laufenden Prüfkonten deren Zugangsdaten einbezogen (21 Werte), nach kompletter Kontobereinigung erneut gegen 14 dauerhaft vorhandene Geheimniswerte. Keine privaten Dienstkonto-/OAuth-/Prüfdateien in Übergabe oder Git. Bereinigte Dateien unter `artifacts/firebase-handoff/`, aktuelle Anleitung in `CHATGPT_HANDOFF.txt`. Nur QA-/Dokumentation nach dem oben genannten bereitgestellten Produktcommit geändert.

**Grenzen:** Die öffentlichen Aufgabenablauf-/Home-Prüfungen liefen zuerst auf 26, die Zeitformatkorrektur wurde mit echtem Chrome-Widgettest und zusätzlichem unveränderndem öffentlichem Vergleich auf 27 geprüft; native Aufgabenabnahme auf 27. Keine wiederholten externen KI-Qualitäts-, neuen Google-/FCM-Zustell-, akustischen TTS-/Mikrofon-, TalkBack- oder physischen Geräteprüfungen aus diesen UI-Beobachtungen ableiten. Konkrete Quellen und Designableitungen in [SOURCES.md](SOURCES.md); keine Wirksamkeitsgarantie der App.

# Vorheriger Stand · Mindestlernzeit und freiwilliges Weiterlernen · 17.10.2026

Web und native Flutter-App 1.2.0+25: Die bisherigen täglichen und wöchentlichen Minuten sind Mindestziele. Zielerreichung beendet keine Einheit und sperrt keine freiwillige Runde. Lerntage, Fachlerntage, Ferien/Krankheit und empfohlene Runden-/Pausendauer gestalten den Vorschlag; das Kind kann darüber hinaus bewusst weiterlernen. Starttermine verbindlicher Elternaufträge und spätere Abrufprüftermine bleiben geschützt. Einzelne freiwillige Runden nutzen weiterhin die vorhandenen Konto-, Kosten-, Provider-, Idempotenz- und Quellprüfungen. Keine automatische Endlosgenerierung und kein Anbieterwechsel.

Der konkrete Startfehler der zwei ausdrücklich genannten gespeicherten Übungen wurde auf dem Server ohne Änderung von Antworten diagnostiziert und auditiert: Samstag bei bevorzugten Lerntagen Montag bis Freitag. Der frühere Kalenderstopp erzeugte 409. Die neue Backendregel erlaubt diesen ausdrücklichen freiwilligen Start. Der WebGL-CPU-Hinweis betrifft die Darstellung, nicht diese serverseitige Ablehnung.

Mindestziele beruhen ausschließlich auf gespeicherten aktiven Sekunden. Eine auf 20 Minuten geschätzte, nach 12 aktiven Minuten abgeschlossene Einheit lässt das Tagesziel mit 8 Minuten offen: Weiterlernen bleibt bis zum Mindestziel verpflichtend. Die Einheit zeigt laufende Sekunden, der Server bestätigt das Ziel; Eltern erhalten dieselben tatsächlichen Werte. Geschätzte erledigte Portionen begrenzen nur den automatischen Tagesvorschlag; sie gelten nie als gemessene Lernzeit. Ein erfülltes Wochenminimum streicht den nächsten Tagesvorschlag nicht. Home, Lernraum und Hefte erlauben ausdrücklich weitere Runden; schon vollständig geübte bestätigte Quellen können erneut normal geübt werden, ohne einen späteren Prüftag vorzutäuschen. Höchstens drei Fachgruppen je bewusstem Paketauftrag; weitere Etappen bleiben im Lernweg. Vorbereitung funktioniert auch bei freiem Tag und über Mitternacht.

Zeitmessung zählt über dem Ziel weiter, serialisiert Intervalle pro Kind gegen Doppelzählung verschiedener Übungen/Geräte und synchronisiert nach Hintergrund, verdeckter Route, Inaktivität oder Verbindungsverlust ohne Nachtragen. Erste Synchronisierung sofort, letzter Teilabschnitt vor Antworten/Pausieren. Die Messung bleibt eine Näherung aktiver Übungszeit: passives Heftlesen und überdeckende Tutoransichten werden nicht pauschal als Zeit gutgeschrieben. Historische Zeiten bleiben erhalten, fehlende alte Sekunden werden nicht erfunden. Es gibt einen wegklickbaren Pausenvorschlag, keinen erzwungenen Zeitstopp. Bestehende Einstellungen und Datenbankschema bleiben erhalten; keine Migration erforderlich. [Ablauf](DAILY_ROUTINE.md).

Eltern- und Adminbereich sind neu gegliedert: kompakte Statuskarten, messbarer Mindestfortschritt, übersichtliche Lernvorgaben, administrative Bereiche und getrennte Modell-/Nachweis-/Kostenfelder. Browseransichten erhalten einen Rollen-/Kontokopf, Tablet-Rail, Desktop-Sidebar und passende Inhaltsbreiten statt einer breitgezogenen mobilen Navigation. Native Touchbedienung und APK-Download bleiben erhalten.

**Lokale Prüfung:** 678 Backendtests mit PostgreSQL 16 bestanden (681,30 s), anschließend 23 gezielte PostgreSQL-Prüfungen zu Mindestzeit, Konten und der Pausenempfehlung. 195 Fluttertests im Gesamtlauf bestanden, danach die letzten Änderungen mit 9 Admin- und 14 Elterntests geprüft. Flutter-Analyse, Ruff und Diffprüfung ohne Befund. Keine erfundenen Minuten oder Testleistungen und keine externen KI-Aufrufe in diesen isolierten Tests.

**Build und Deployment:** Web, signierte Direct-APK und Play-AAB 1.2.0+25 mit unveränderter fixierter Toolchain gebaut. APK: `artifacts/schulpilot-android.apk`, 63.314.609 Bytes, SHA-256 `69311fb8b5d377b269e727df61f464f9aa605eba26cb9148af2c4df9b5441b91`; Paket, stabile Signieridentität und 16-KB-Zipausrichtung geprüft. Produktcommit `c8123d233714030ff6bf906a9c0ee4b365c4a545`, öffentliches Release `20261017T072625Z-c8123d2`, https://schulpilot.dorfspy.de . Öffentliche Health bestätigt diesen Quellstand, KI verfügbar. Den vollständigen öffentlichen APK-Download mit lokalem Build und Manifest verglichen: Größe und SHA-256 stimmen überein. Startseite und Web-Direktlinks 200, private API anonym 401, HTTP-Weiterleitung 308. Beide ursprünglich beanstandeten gespeicherten Einheiten sind nun ohne den früheren Zeit-/Kalenderstopp startbar; weiterhin unbegonnen, keine echten Antworten verändert.

API, Lernworker, isolierter Codexworker, Caddy und die drei bestehenden DorfSpy-Anwendungen sind aktiv. Projektspezifische Konfigurationssicherung und Datenbanksicherung erfolgreich; vorheriger Releasepointer `20261017T062237Z-7a43ff1`. Schema unverändert. Vorhandene Providerkonfiguration erhalten: Codex, Lern-/Bildmodell `gpt-6.1-sol`, Denkstufe `xhigh`, Revision 18; keine erneute technische Sperre und keine Kontingenterhöhung. Rückweg: [OPERATIONS.md](OPERATIONS.md).

**Öffentliche Adminabnahme:** Normaler Adminlogin; Übersicht und Modell-/Denkstufenauswahl bei 1440/960/390/320 px tatsächlich bedient. Familientarife, Protokoll und direkte Betriebseinstellungsreiter zusätzlich bei 1440 px geprüft. Neun echte CLI-Katalogeinträge; alternatives Modell und kompatible andere Denkstufe je Breite ausschließlich im Formular gewählt. Gespeicherte Konfiguration vorher/nachher identisch, null Provider-Speicherungen, null KI-Aufträge, keine Browser-Laufzeitfehler. Prüfsitzung normal abgemeldet, danach 401. Der Katalogendpunkt antwortete vorübergehend mit 429; der spätere reguläre Katalogaufruf gelang ohne Grenzänderung, die erste Ursache wurde nicht unabhängig nachgewiesen. Fehler in Prüflocatoren und einem lokalen Variablenscope ausschließlich im QA-Treiber korrigiert. Berichte: `artifacts/minimum-time-admin-public-result.json` und `artifacts/minimum-time-admin-workspace-result.json`.

**Öffentliche Mindestzeit-/Elternabnahme:** Genau eine eigene künstliche Demo-Familie, zwei feste synthetische Einheiten, null externe KI-Aufträge. Unabhängiger Kinderlogin und beide ausdrücklichen Einheitenstarts HTTP 200. Ohne Uhrmanipulation oder direkte Heartbeat-Aufrufe 355 Sekunden lang die echte Flutter-Oberfläche bedient: 299 gespeicherte Sekunden bedeuten weiterhin ein offenes Fünf-Minuten-Ziel, 319 erfüllen es; bei 339 Sekunden bleibt die Einheit aktiv. Pausenvorschlag sichtbar, weitere 24 reale Sekunden und anschließend die zweite Einheit erlaubt. Eltern-Familie und Kinderdetail bei 1280/390/320 px zeigen übereinstimmend 5:39 / 5 Minuten und erfüllte Tages-/Wochenziele, ohne horizontalen Überlauf. Kinderänderung der Vorgaben, Kinderadminzugriff und Elternstart einer Kinderübung jeweils 403. Keine Browser-Laufzeitfehler. Familie regulär gelöscht, Eltern-/Kindersitzungen danach 401, privates Journal entfernt.

Beobachtungsgrenze dieser Webprüfung: Zwei der ursprünglich 18 erfolgreichen HTTP-200-Heartbeatantworten wurden vom QA-Observer nicht vollständig erfasst. Deren Inhalte bleiben unbekannt; der ursprüngliche Fehlbericht wurde erhalten. Die Zeitfolge ist durch die übrigen Antworten und regelmäßige normale Einheiten-/Übersichts-GETs belegt und mit einem erneuten GET bestätigt. Fortsetzung mit derselben Familie und gespeicherter Zeit, ohne neuen Zeitlauf oder zusätzliche Erzeugung; abschließend insgesamt 19 normale UI-Heartbeats. Der Ergebnisbericht `artifacts/minimum-learning-time-result.json` kennzeichnet den Zeitnachweis als teilweise rekonstruiert und `heartbeat_body_observation_complete=false`; keine lückenlose Bodybeobachtung behauptet.

**Android-Update:** Direct-APK 24 → 25 über den automatischen Servercheck, geprüften Download und Android-Installationsbestätigung auf dem eigenen API-36-Emulator ausgeführt; kein `adb install` beim Upgrade. Auf 25 anschließend drei reale Prüfungen bei Kaltstart, Wiederöffnen aus dem Hintergrund und zusätzlichem Launcher-Intent bestanden. Kein Play-Upload oder physischer Gerätetest daraus abgeleitet.

**Native Mindestzeit-/Elternabnahme:** Installierte APK 25 im eigenen Emulator bedient: separater Eltern-/Kinderlogin, sichtbare Sekundenanzeige, eine feste künstliche Einheit, genau eine gespeicherte Antwort mit Hinweis. Mindestens 35 Sekunden tatsächlich im Vordergrund interagiert; bei 88 gespeicherten aktiven Sekunden bleibt das Fünf-Minuten-Ziel offen. Während 20 Sekunden am Android-Homescreen kein zusätzlicher Sekundenzuwachs; Resume schreibt die Hintergrundlücke nicht nach, ausdrückliches Pausieren bleibt möglich. Eltern-Familie und Kinderdetail zeigen dieselben 1:28 / 5 Minuten, Rollenprüfung bestanden, null externe KI-Aufträge. Beide eigenen nativen Testfamilien regulär gelöscht, Sitzungen danach 401, Appneustart am Login und nur Appdaten des eigenen Emulators bereinigt; private Journale entfernt.

Der native Prüftreiber musste die unterhalb des sichtbaren Ausschnitts liegenden Statuskarten durch Scrollen auffinden. Ersten eigenen Fall nach dem Selektorfehler vollständig bereinigt; genau ein Ersatzfall mit einer synthetischen Einheit, dessen restlicher Elternvergleich nach Korrektur am selben pausierten Fall fortgesetzt wurde. Keine dritte Familie und kein erneuter Zeitlauf. Die exakte Dauer des ursprünglichen Vordergrundabschnitts und das genaue Resume-Delta waren vor dem Selektorabbruch nicht gesichert und bleiben im Endbericht ausdrücklich null; nur die belegte Untergrenze und die bereits bestandene Hintergrund-/Resumeprüfung ausgewiesen. Bericht: `artifacts/android-minimum-time-result.json`, ursprüngliche Fehlberichte erhalten. Kein Produktcode musste für diese Automationsfehler geändert werden.

**Abschlussprüfung:** QA-Treiber mit Offline-Schutz, Node-Syntax, Ruff und Diffprüfung ohne Befund. Quellen, fertiges Web, entpackte APK-/AAB-Inhalte und bereinigte Übergabe gegen die tatsächlich vorhandenen privaten Werte geprüft: null Treffer; während der eigenen Liveprüfungen auch deren Zugangsdaten einbezogen. Private Journale und temporäre Journale entfernt, Screenshots/Ergebnisdateien geschützt. Die aktualisierte bereinigte Übergabe liegt unter `artifacts/firebase-handoff/`; private Dienstkonto- und OAuthdateien sind nicht enthalten.

Produktcommit auf `main` gepusht. [GitHub-Actions-Lauf 39006063297](https://github.com/meinzeug/schulpilot/actions/runs/39006063297): Beide Jobs wurden ohne ausgeführte Schritte abgewiesen, weil das GitHub-Konto wegen eines Abrechnungsproblems gesperrt ist. Lokale Tests und Builds wurden tatsächlich ausgeführt; kein bestandener gehosteter CI-Lauf behauptet. Nachfolgende reine QA-/Dokumentationscommits ändern den oben genannten bereitgestellten Produktcode nicht.

# Vorheriger Stand · Codex-Modellwahl und Denkstufen · 17.10.2026

Flutter Web und Android 1.2.0+24: Im Adminbereich erscheinen bei Codex eine Modellauswahl und direkt darunter „Reasoning / Denkstufe“. Der Katalog stammt aus der eigenen fixierten CLI 0.162.1; auch ausgeblendete Einträge sind sichtbar. Das optionale Bildmodell hat eine eigene Auswahl; angeboten werden die gemeinsamen Denkstufen beider Modelle. Laden, Fehler, gespeicherte unbekannte Werte und Wiederholen sind behandelt, ohne stillschweigenden Modellwechsel. Andere Anbieter behalten ihre bisherigen Felder. Der abgesicherte Erstassistent verwendet dieselben Komponenten.

Das Backend prüft jede neue Auswahl gegen die Worker-Metadaten. Die gespeicherte Denkstufe erreicht sowohl die CLI-Konfiguration als auch die tatsächliche Anbieteranfrage. Der private Katalog startet nur initialize/model/list, keinen Thread, Turn oder Lernauftrag. Zeit, Ausgabe, Seitengröße, Rate und gemeinsamer Worker-Slot sind begrenzt. Anmeldung bleibt im isolierten Worker; zulässige Token-Erneuerung bleibt auch nach Metadatenfehlern erhalten. Katalogeinträge sind kein Nachweis einer Modellberechtigung. Neue Modell-/Denkstufen benötigen weiterhin den regulären künstlichen Prüflauf; Kontingente, Zeit und Kostengrenzen bleiben bestehen. Migration 0013 ergänzt nur die bisherige effektive Stufe medium und erhält Konfigurationsrevision/Freigabe. Der unveränderte medium-Transport funktioniert während des rollenden Updates auch mit dem vorherigen Worker.

**Lokale Client- und Workerprüfung:** Alle 115 Fluttertests bestanden, einschließlich 17 neuer Formular-/Auswahltests; Flutter-Analyse ohne Befund. 71 Worker-/Katalogtests bestanden. Die echte fixierte CLI wurde mit künstlichem API- und Kontologin gegen einen lokalen simulierten Responses-Upstream geprüft: medium und xhigh erreichen in beiden Modi tatsächlich den Request. Der native Metadatenaufruf lieferte lokal elf normalisierte Einträge ohne externe KI-Anfrage. Diese Tests behaupten keine reale Berechtigung oder KI-Qualität eines neu gewählten Modells.

**Releasebuild:** Web, signierte Direct-APK und Play-AAB 24 mit unveränderter fixierter Toolchain und externer Signierung gebaut. Direct-APK: 63.182.449 Bytes, SHA-256 `0879e1e806d6a0b35581a700a806bd8849d01af00227f28971b7198900a1f069`; Paket, Versionscode, stabile Signieridentität und 16-KB-Zipausrichtung geprüft. Play-AAB: 60.354.021 Bytes. Quellen, Web und entpackte APK-/AAB-Inhalte gegen 14 tatsächliche Geheimniswerte geprüft, null Treffer.

**Backendprüfung:** Alle 651 Tests auf isoliertem PostgreSQL 16 bestanden (438,26 s), einschließlich Katalogschutz, tatsächlichem CLI-Transport, neuer Denkstufe, Legacy-Kompatibilität, vollständigem Lernablauf und Datenerhalt bis Migration 0013. Eine bestehende Starlette-TestClient-Deprecationwarnung. Ruff und Diffprüfung ohne Befund. Zwei belegte Testumgebungsprobleme wurden zuvor behoben: Coach-Fixtures legen ihre Lerntage ausdrücklich fest, damit ein Samstag nicht ihre fachfremde Standardannahme verletzt; der echte native CLI-Test verwendet wie der Produktionscontainer tmpfs statt des unter Last blockierenden Host-ext4. Produkt-Lerntage und die 9s-Metadatengrenze wurden dafür nicht geändert. Eine neue Regression bestätigt außerdem, dass ein während des Katalogabrufs aktivierter Notfallstopp nicht von einem älteren Formularwert aufgehoben wird.

**Deployment:** Produktcommit `7a43ff1dc79210953135bbf548774c8aa0512b0a`, Release `20261017T062237Z-7a43ff1`, https://schulpilot.dorfspy.de . Öffentliche Health bestätigt den Quellstand; Startseite und Web-Direktlinks HTTP 200, geschützter Modellkatalog anonym 401, abgeschlossener Setup-Katalog 409. Den öffentlichen APK-Download vollständig geladen und Größe/SHA-256 mit dem lokalen Build verglichen. Schema 0013 und medium am Server bestätigt; die vorhandene Konfigurationsrevision 16 und Freigabe bleiben erhalten. Projektspezifische Konfigurationssicherung und Datenbanksicherung vor Aktivierung erfolgreich. API, Lernworker, neuer isolierter Codexworker, Caddy und die drei bestehenden DorfSpy-Anwendungen aktiv. Vorheriger Releasepointer `20261016T092033Z-e61c08e`; Rückweg unter [OPERATIONS.md](OPERATIONS.md).

**Öffentlicher Browser bestanden:** Normaler Adminlogin über HTTPS, echter Katalog des angemeldeten isolierten Workers mit neun Modellen. Modell und gemeinsame Denkstufe bei 1280/390/320 px tatsächlich über die Dropdowns ausgewählt, ohne zu speichern. Keine Provideränderung, keine Inferenz, keine Browser-Laufzeitfehler. Gespeicherte Konfiguration danach unverändert; Prüfsitzung normal abgemeldet und 401 bestätigt. Der erste Prüftreiber berücksichtigte Flutters Menüelementrolle noch nicht; ausschließlich den Treiber angepasst, anschließende vollständige Abnahme grün. Sechs geschützte Screenshots und bereinigter Bericht unter artifacts; reproduzierbarer Treiber `qa/codex_models.mjs`. Neue Modell-/Denkstufenberechtigungen oder reale High-Inferenz wurden dadurch ausdrücklich nicht nachgewiesen.

**Android-Update bestanden:** Die vorher installierte native Direct-APK 23 wurde über den eingebauten Updater, geprüften Download und Android-Installationsbestätigung auf 24 aktualisiert; kein adb install beim Upgrade. Danach drei tatsächliche Serverprüfungen bei Kaltstart, Wiederöffnen aus dem Hintergrund und zusätzlichem Launcher-Intent bestanden. Die Adminauswahl wurde auf der öffentlichen Web-App und in gemeinsamen Flutter-Komponententests geprüft; kein gesonderter nativer Admin-Bedienungstest behauptet.

Produktcommit auf `main` gepusht. [GitHub-Actions-Lauf 39002600988](https://github.com/meinzeug/schulpilot/actions/runs/39002600988) wurde tatsächlich geprüft: beide Jobs ohne ausgeführte Schritte abgewiesen; beide Annotationen nennen weiterhin „The job was not started because your account is locked due to a billing issue.“ Lokale und öffentliche Abnahmen sind oben getrennt belegt; kein erfolgreicher gehosteter CI-Lauf behauptet. Der nachfolgende QA-/Dokumentationscommit verändert den bereitgestellten Produktcode nicht.

**Nachfolgende Betreiberänderung · 17.10.2026:** Nach der Abnahme wurde die Denkstufe ausdrücklich über die Admin-Konfiguration von medium auf xhigh geändert (Revision 17); Lern- und Bildmodell bleiben gpt-6.1-sol. Die dadurch gesetzte technische Prüfsperre verursachte den gemeldeten Hinweis bei „Jetzt lernen“. Genau einen regulären Betreiber-Prüfauftrag mit den drei festen künstlichen Vorlagen gestartet, ohne echte Kinderseiten zu lesen oder Kinderantworten einzutragen. Fotoerkennung, Übungserstellung und Tagespaket jeweils mit xhigh erfolgreich; drei gezählte Anbieteraufrufe, keine automatische Wiederholung, Geldkosten weiterhin unbekannt. Der normale Abschluss hat die Route bei Revision 18 freigegeben; Modellwahl, Denkstufe und Limits blieben erhalten. Öffentliche HTTPS-Statusprüfung danach: ai_available=true, ai_block_reason=null, „SCHULPILOT ist bereit.“ Keine neue Datenschutzfreigabe und kein Providerwechsel vorgenommen. Reine Betriebsprüfung; bereitgestellter Produktcode, Web und APK 24 unverändert, kein neuer Build oder Deployment behauptet.

# Vorheriger Stand · Einfache Seitenprüfung · 16.10.2026

Web und native Flutter-App 1.2.0+23: „Stimmt, weiter“ bestätigt eine importierte oder fotografierte Seite direkt. Zusätzliche Prüfcheckboxen entfallen; unsichere Stellen bleiben sichtbar und bearbeitbar. „Seite löschen“ entfernt nach kurzer Rückfrage eigene unbestätigte Seiten, auch direkt in der Prüfung. Danach folgt die nächste ungeprüfte Seite oder der heutige Fotoeinstieg; nach der letzten archivierten Seite die Startseite. Bestätigte Kindermaterialien, fremde Familien und laufende Verarbeitung bleiben geschützt. Der Vorbereitungsstand wird unter den bestehenden Sperren aktualisiert, ohne neue KI-Reservation. Bestehende Antworten und Verbrauch bleiben erhalten. Die feste zusammengehörige Zwei-Seiten-Demo bleibt vor einem defekten Teilpaket geschützt.

**Clientprüfung und Builds:** Alle 98 Fluttertests bestanden, darunter direkte Bestätigung, weiterhin sichtbare Unsicherheiten, Löschabbruch, nächste/letzte Seite bei 320/390/1280 px und Archiv-Rücknavigation. Flutter-Analyse ohne Befund. Web, Direct-APK und Play-AAB mit unveränderten fixierten SDK-Versionen und externer Signierung erfolgreich gebaut. APK 23: 63.084.149 Bytes, SHA-256 `cb3d8654f95f184ad4f93f3c261f06c507a94feb53396ee68b0a7ce41a7dee7f`; Manifest, Signatur und 16-KB-Zipausrichtung geprüft. Keine neue Abhängigkeit oder Schemaänderung.

**Backendprüfung:** 91 gezielte PostgreSQL-Tests bestanden (70,99 s), einschließlich Löschrechten, vollständigen Tagesassistent-/Hintergrund-/Tutor-Modulen und zwei echten gleichzeitigen Bestätigungs-/Löschvorgängen. Laufende Jobs und inzwischen bestätigte Quellen werden unter den bestehenden Sperren erneut geprüft. Auch nach Löschen der letzten ungeprüften Seite braucht ein Paket einen bewussten neuen Vorbereitungsauftrag. Anfängliche neue Test-Fixtures um Pflicht-Idempotenzschlüssel und getrennte Elternsitzungen korrigiert; keine Abschwächung der Produktprüfung. Ruff, Diff- und konkrete Geheimniswertprüfung ohne Befund.

**Deployment:** Produktcommit `e61c08ea3f39b90d3a2d5212ae1134fa86da2890`, Release `20261016T092033Z-e61c08e`, https://schulpilot.dorfspy.de . Öffentliche Health, Startseite und Web-Direktlinks geprüft, private API anonym 401. Den öffentlichen APK-Download vollständig auf passenden Hash und Größe geprüft. API, Lernworker, Codexworker, Caddy und die drei bestehenden DorfSpy-Anwendungen aktiv. Datenbanksicherung und projektspezifische Konfigurationssicherung vor Aktivierung erfolgreich; Datenbankschema unverändert. Der eingebaute Android-Updater hat APK 22 → 23 mit überprüftem Download und nativer Installationsbestätigung aktualisiert, ohne `adb install` beim Upgrade. Danach drei reale Startprüfungen bestanden.

**Öffentlicher Browser bestanden:** Unabhängige Kinderanmeldung bei 320/390 px, sichtbare Unsicherheiten ohne Checkboxen, genau eine Bestätigung mit „Stimmt, weiter“, dauerhafte Speicherung nach Reload und kein Löschbutton bei bestätigter Kinderseite. Separater Löschfall: Abbruch unverändert ohne Request, dann genau ein bewusster DELETE, Quelle unter Eltern-/Kinderzugang 404 und Rücknavigation zur Startseite. Keine zusätzlichen KI-Aufträge, keine Browser-Laufzeitfehler. Ein anfänglicher Prüftreiber nahm fälschlich ein öffentliches Revisionsfeld an; gegen den tatsächlichen Serializer korrigiert, vollständige Abnahme danach bestanden. Alle drei dafür angelegten eigenen Demo-Familien regulär gelöscht und Sitzungen anschließend 401; privates Recoveryjournal entfernt.

**Installierte APK 23 bestanden:** Im eigenen API-36-Emulator unabhängiger Kinderlogin, Hefte öffnen, direkte Bestätigung ohne Checkbox und unveränderte gespeicherte Quelle; bestätigte Kindermaterialien ohne Löschaktion und serverseitig 403. Zweiter eigener Fall: Löschen abbrechen erhält die Seite, dann bestätigte Löschung mit echter 404, Home-Rücksprung und leere Sammlung. Beide eigenen Demo-Familien normal gelöscht, Eltern-/Kindersitzungen 401 und native Sitzungen nach Neustart am Login. Kein KI-Verbrauch. Abschließend nur die Appdaten des eigenen Emulators und private QA-Journale entfernt; fünf geschützte native Screenshots und bereinigte Ergebnisdatei erhalten. Reproduzierbare Prüftreiber: `qa/page_review.mjs` und `qa/android_page_review.py`.

Produktcommit auf `main` gepusht. [GitHub-Actions-Lauf 38866748742](https://github.com/meinzeug/schulpilot/actions/runs/38866748742) startet erneut keine Schritte: Beide Jobs wegen der bestehenden Kontosperre „The job was not started because your account is locked due to a billing issue.“ abgewiesen. Lokale Tests und Builds wurden tatsächlich ausgeführt; kein erfolgreicher gehosteter CI-Lauf behauptet.

# Vorheriger Stand · Tagesroutine und Hintergrundvorbereitung · 15.10.2026

Implementiert für Flutter Web und die native Direct-/Play-App 1.2.0+22: dauerhafter täglicher Fotoeinstieg, „Heute keine neuen Seiten“, begrenzte Lernportionen und ein anpassbarer Siebentagevorschlag. Elterntermine, Fachlerntage, Tages-/Wochenlimits und Pausen bleiben erhalten; alte Schultage verschwinden nicht nach 30 Tagen. Erledigte geschätzte Portionen verhindern ständiges Nachfüllen, ohne geplante Minuten als tatsächlich gemessene Aktivität auszugeben.

Fotos werden ausdrücklich zur persistenten Servervorbereitung abgegeben. Jeder Erkennungs-/Paketauftrag wird separat reserviert, vor/nach dem Anbieter auf Sitzung/Familie/Quellen geprüft und dauerhaft gespeichert. Nach Erkennung ist die Quellenbestätigung erforderlich; ein fertiges Paket startet keine Lernrunde. In-App-Meldungen und optionaler neutraler Push, Wiederaufnahme nach App-Neustart/Tageswechsel, Ablage unlesbarer Archivseiten und kontingentbegrenzte bewusste Wiederholungen sind implementiert. Schema 0012 ergänzt den privaten Vorbereitungsstand. [Alltag und Grenzen](DAILY_ROUTINE.md), [Rückweg](OPERATIONS.md).

**Echte Codex-Verbindung:** Eigene Anmeldung des dedizierten Workerbenutzers erkannt und ausschließlich in den getrennten Anmeldespeicher übernommen. Der bisherige Account-HTTP-400 wurde gegen die offizielle Dokumentation korrigiert: `max_tool_calls` und `max_output_tokens` sind auf diesem Kontotransport nicht zulässig. Der Betreiber hat zusätzliche Websuche ausdrücklich freigegeben; `CODEX_WEB_SEARCH=true`, ein Anbieteraufruf und höchstens 145 Sekunden, keine vorab garantierte Suchanzahl. Der dritte regulär gezählte Prüflauf hat Bildlesen, Einheit und Paket mit echten Codex-Antworten erfolgreich abgeschlossen. Geldkosten bleiben unbekannt und voll reserviert; keine Budget-/Tariflockerung. [Betrieb und Belege](CODEX.md).

**Prüfung vor Deployment:** 562 Backendtests in einer isolierten PostgreSQL-16-Instanz bestanden (547,79 s), danach ergänzende gezielte Konto-/Suchzählungs-/Migrations- und Transaktionspushprüfungen. Alle 94 Fluttertests bestanden; Flutter-Analyse, Ruff und Diffprüfung ohne Befund. Web, Direct-APK und Play-AAB mit der fixierten Toolchain gebaut. Tatsächliche APK-Metadaten: 1.2.0+22, 63.084.077 Bytes, SHA-256 `909410d26f86775d879e2e7577951a85c1a0eae38db87b5fa4865b22f6926074`; Signatur und 16-KB-Zipausrichtung geprüft. Bekannte Warnungen der fixierten Firebase-/TTS-Plugins zur zukünftigen Kotlin-Migration verhindern diese Builds nicht.

**Öffentlich bereitgestellt:** Release `20261015T181351Z-0c673e9`, Produktcommit `0c673e9288bb0d47cf48976147a94010cb7f59a3`, https://schulpilot.dorfspy.de . Öffentliche Health bestätigt diesen Stand; Web-Direktlinks HTTP 200 und private API ohne Anmeldung 401. Regulären APK-Download erneut vollständig geladen: Größe und SHA-256 stimmen mit dem Manifest und dem lokalen Build überein. Schema 0012 aktiv. API, Lernworker, isolierter Codexworker, Caddy und die drei bestehenden DorfSpy-Anwendungen bleiben aktiv. Vor Aktivierung beide verschlüsselten Datenbanksicherungen erfolgreich; vorheriger Releasepointer `20261015T163349Z-f36f16b`. Für einen Rückweg die Vorbereitungshinweise in OPERATIONS.md beachten.

**Echter öffentlicher Alltagsablauf bestanden:** eigene reguläre, per echter E-Mail verifizierte Eltern-/Kinderzugänge und zwei ausschließlich künstliche Originalbilder; kein Demo-KI-Pfad. Genau zwei Codex-OCR-Aufträge und ein Paketauftrag, ohne Providerwiederholung. Während Erkennung und Paketvorbereitung war der Kinderclient geschlossen, ohne einen einzigen Kinderrequest; nur die berechtigte Elternseite las den Stand. Beide Seiten wörtlich geprüft und ausdrücklich bestätigt, eine Einheit blieb ungestartet, keine Antworten eingetragen, beide Quellen verknüpft und zwei neutrale In-App-Meldungen gespeichert. Zwei wiederholte Abgaben mit demselben Schlüssel erzeugten keine zusätzlichen Aufträge. Alle drei Geldkosten korrekt unbekannt, volle Reservierungen erhalten; nicht als kostenlos bezeichnet. Neue vorbereitungsbezogene Push-Zustellung dabei nicht beobachtet.

Anschließend genau eine reguläre Heftfrage über den echten Codex-Tutor: Antwort gespeichert, wörtliches Quellenzitat geprüft, berechtigter Elternzugriff bestätigt. Genau ein weiterer Verbrauchseintrag, tatsächlich gemessene Suchanzahl 0, Geldkosten weiterhin unbekannt. Beide Testsitzungen normal abgemeldet. Allgemeiner öffentlicher API-Test zusätzlich bestanden: Kinderlogin, Rollen-/Familienschutz, vier Aufgabentypen, Hinweise, Pause/Fortsetzung, Elternverlauf, Export, Sitzungswiderruf und vollständige Löschung der eigenen synthetischen Testfamilie; keine externen KI-Aufrufe in diesem separaten Test.

**Android-Update tatsächlich ausgeführt:** Direct-APK 21 → 22 über automatischen Servercheck, geprüften Download und Android-Installationsbestätigung; kein `adb install` beim Upgrade. Auf Build 22 anschließend drei reale Startprüfungen bei Kaltstart, Wiederöffnen aus dem Hintergrund und zusätzlichem Launcher-Intent bestanden.

**Browser und installierte native Flutter-App geprüft:** echte reguläre UI-Anmeldung des eigenen künstlichen Kinderkontos, Tagesstart/Plan bei 320 und 390 px, bestätigte Heftseite über den Fotoeinstieg geöffnet und genau eine vorbereitete Einheit bewusst gestartet. Eltern bei 1280 px: Siebentagevorschlag und Kalenderwochen-/Tagesgrenzen sichtbar. Keine Antworten, Hinweise oder zusätzlichen KI-Aufträge; Verbrauch blieb bei den vier bereits nachgewiesenen Codex-Aufrufen, null Browser-Laufzeitfehler. In der nativen APK 22 auf dem eigenen API-36-Emulator zusätzlich separater Eltern-/Kinderlogin, sichere Sitzungswiederaufnahme nach Prozessneustart, Hinweis/Antwort mit Elternverlauf, explizites Feedback vor der nächsten Aufgabe sowie Elternwiderruf und Testfamilienlöschung erfolgreich. Dieser separate native Test verwendet ausschließlich feste künstliche Demoaufgaben, keine externe KI. Ein erster UI-Automationsversuch scheiterte an einem gleichzeitigen UI-Dump; der unabhängige vollständige Wiederholungslauf ist erfolgreich.

Mit APK 22 anschließend auch das reguläre künstliche KI-Kinderkonto geöffnet: heutige Lernportion und gespeicherte Heftseiten sichtbar, Tagespaket und bestätigte Originalseite über die native Oberfläche geöffnet; keine Antworten oder KI-Aufträge. Native Prüflocatoren an den tatsächlich gerenderten Aufklappstatus und „Seite geprüft“ angepasst, keine Appkorrektur dafür benötigt. Vor der abschließenden normalen Kontolöschung weiterhin genau vier KI-Aufrufe und null Aufgabenantworten. Nach Löschung neue Eltern-/Kindersitzungen 401, die native Sitzung nach Prozessneustart ebenfalls abgewiesen. Private Kontodatei entfernt und nur Appdaten des eigenen Emulators gelöscht. Quellen, Web und entpackte APK-/AAB-Dateien gegen 14 tatsächlich vorhandene Geheimniswerte geprüft: 609 Dateien/Archiveinträge, null Treffer. Echte Kinderhaushalte wurden für diese Abnahme weder gelesen noch geändert.

GitHub-Push des Produktcommits auf `main` erfolgreich. [Actions-Lauf 38768768366](https://github.com/meinzeug/schulpilot/actions/runs/38768768366) startet erneut keine Schritte: Beide Jobs sind wegen „The job was not started because your account is locked due to a billing issue.“ gesperrt. Dies bleibt eine GitHub-Kontovoraussetzung; die lokalen, öffentlichen und nativen Tests sind oben getrennt ausgewiesen.

Die nachfolgenden älteren Abschnitte sind historische Abnahmen.

# Vorheriger Stand · Codex-Umstellung · 15.10.2026

Backendcommit `f36f16b7ea93329dbf745c56dca5a824d02f584b`, öffentliches Release `20261015T163349Z-f36f16b`, https://schulpilot.dorfspy.de . Website, Web-Direktlink und API über gültiges öffentliches HTTPS geprüft. **Codex CLI mit `--search` und festem Modell `gpt-6.1-sol` ist dauerhaft in der Datenbank ausgewählt** (Revision 12); die technische Sperre bleibt bis zur eigenen Anmeldung und den erfolgreichen künstlichen Prüfungen erhalten. Kein echter Codex-Anbieteraufruf und keine erfolgreiche Modellberechtigung behauptet. Die reguläre signierte APK **1.2.0+21** und der Flutter-Webclient bleiben unverändert und verwenden diese gemeinsame Backendkonfiguration; APK-Metadaten, Signatur und SHA-256 erneut geprüft, kein neuer Clientbuild behauptet.

Anmeldung durch den Betreiber: `ssh -t dorfspy 'sudo schulpilot-codex login'`. Der getrennte Helfer übernimmt keine Entwicklungsanmeldung, startet nach erfolgreicher eigener Anmeldung den gezählten Bild-/Einheits-/Pakettest und aktiviert die Route erst bei drei erfolgreichen Funktionen. Konto-USD-Kosten bleiben unbekannt; atomare Aufruf-/Familien-/Unternehmensgrenzen und volle Reservierungen bleiben erhalten. Einrichtung, Voraussetzungen und Grenzen: [CODEX.md](CODEX.md).

**Tatsächliche Prüfungen:** 492 PostgreSQL-Backendtests bestanden in 248,05 s; nach der gezielten Paketbedingung weitere 82 relevante Tests, nach Konfigurationssicherung der entsprechende Auswahltest, nach Erweiterung der Account-Headerprüfung beide echten lokalen CLI-Transporttests erneut erfolgreich. Ruff, Diff-/Geheimnisprüfung bestanden. Die echte CLI wurde lokal und im gestarteten Rootless-Container mit künstlichem API- und Kontologin gegen simulierte Antworten geprüft; keine echten Zugangsdaten oder Kinderinhalte. Container: kein Root, effektive Capabilities 0, nur eigene Auth- und Socket-Mounts, keine öffentlichen Ports, Socket 0660. Auch das Hostkonto hat eine eigene Gruppe und kann App-Umgebung und App-Daten nicht lesen. Installationswiederholung und Dienstneustart mit Healthcheck erfolgreich. Offizielle npm-Distribution über Registry-SHA-512 und natives Binary über SHA-256 abgeglichen.

**Öffentliche API-Prüfung nach Deployment bestanden:** eigener künstlicher Eltern-/Kinderzugang, Rollenprüfung, vier Aufgabentypen, Hinweise, Pause/Fortsetzung, gespeicherte Antworten und Elternübersicht, Export, Sitzungswiderruf, vollständige Testkontolöschung; keine externen KI-Aufrufe. Normaler Adminlogin und geschützte Provideransicht geprüft, Prüfsitzung anschließend widerrufen. Fehlende Codex-Anmeldung wird im Betrieb korrekt angezeigt. API, Lernworker, isolierter Codexworker, Caddy und die bestehenden Merchagent-/Artist-Studio-/Buddys-Art-Dienste aktiv. Aktuelles Hindernis: ausschließlich die noch fehlende eigene Codex-Anmeldung und der danach ausstehende echte Anbieter-/Bild-/Schematest; sichtbare KI-Qualität ist durch simulierten Transport nicht belegt.

Vor dem Deploy verschlüsselte Datenbanksicherung und projektspezifische Konfigurationssicherung erstellt. Providerwechsel hält zusätzlich eine private Kopie ausschließlich der vorherigen Providerzeile unter `/var/lib/schulpilot/operator-backups/` vor (0600, vorhandener Schlüssel ausschließlich verschlüsselt). Vorheriger Releasepointer: `20261015T140058Z-25f5614`. Nur Providerkonfiguration zurücksetzen, keine später gespeicherten Kinderantworten durch eine alte Gesamtdatenbank ersetzen. Eine bekannte Starlette-Testclient-Abkündigungswarnung bleibt bestehen; keine ungeprüfte SDK-Migration.

GitHub-Push auf `main` erfolgreich. Die GitHub-Actions-Prüfung für `a08f454` (Run `38753290782`) startete in beiden Jobs keinen einzigen Schritt: GitHub meldet eine Kontosperre wegen eines Abrechnungsproblems. Dies ist kein ausgeführter oder bestandener CI-Test; die oben genannten lokalen und öffentlichen Prüfungen wurden tatsächlich durchgeführt. Die Abrechnung muss der GitHub-Kontoinhaber klären.

Der folgende Abschnitt dokumentiert den unveränderten vorherigen Flutter-Client und dessen bereits durchgeführte Geräte-/Browserprüfungen.

# Vorheriger Clientstand · 15.10.2026 · 1.2.0+21

Web und signierte native Flutter-APK 21 sind öffentlich aktiv: https://schulpilot.dorfspy.de . Produktcommit `25f5614916f27e3b3f53814ff513464151009069`, Release `20261015T140058Z-25f5614`; über gültiges öffentliches HTTPS geprüft. Nachfolgende reine Prüf-/Dokumentationscommits ändern den bereitgestellten Produktcode nicht. Datenbankschema 0011 unverändert; keine neuen Dienste oder SDK-Abhängigkeiten.

## Bibliothek und übersichtliches Lernen

- „Hefte“ und „Meine Heftseiten“ öffnen eine eigene Bibliothek. Serverseitige Suche in Titel, Thema, Fach und Quelltext; Fach, Bestätigungsstand, Unterrichts-/Uploaddatum und Sortierung kombinierbar. Standard 20, wahlweise 10/50 Metadateneinträge pro Seite. Keine Fotos oder vollständigen Abschriften in Listen.
- Kleine Startseitenvorschau mit nächster Aktion; das Archiv entfällt dort. Filter und Seite bleiben bei Rücksprüngen erhalten, liegen nur im Arbeitsspeicher und verschwinden bei Kontowechsel/Abmeldung. Verspätete Suchantworten ersetzen keine neueren Ergebnisse. Ältere Clients behalten die bisherige Overview-Antwort ohne compact=true.
- „Lernen“ trennt Offen, Später und Erledigt. Gespeicherte Antwortversuche bestimmen den angezeigten Bearbeitungsstand; Abschluss bedeutet keine sichere Beherrschung. Elternvorgaben, Zukunftstermine und Pausen bleiben verbindlich. Das Öffnen einer Liste erzeugt keine KI-Aufträge.
- Fertige Kinderrunden zeigen Rückblick und Antworten einzeln, bei tatsächlichem Tagespaket zusätzlich den Lernweg. Doppelte Überschrift und wiederholte Navigationsknöpfe entfallen. Feedback wartet weiterhin auf „Weiter“. Lernkarten behalten ihren Button für Screenreader; Filter schließen die Such-Tastatur, statt sie über der Navigation erneut zu öffnen. Gewählte und ungewählte Reiter haben dunkle Schrift; der gerenderte Textkontrast ist mit mindestens 4,5:1 geprüft.
- Eltern erhalten dieselben berechtigten paginierten Sammlungen und einen suchbaren Picker für bestätigte Heftseiten beim Lernauftrag. Private Antworten, Hinweise und Erklärungen stehen in der Detailansicht. Administratoren erhalten dadurch keinen Kinderinhaltszugriff.

Einrichtung, API und reproduzierbare Prüfabläufe: [LIBRARY.md](LIBRARY.md).

## Tatsächliche aktuelle Prüfungen

**468 PostgreSQL-Backendtests bestanden** (281,72 s, isolierter Lauf), **76 Fluttertests**, Flutter-Analyse, Ruff und Format-/Diffprüfung bestanden. Darunter 1.205 Seiten über 25 stabile Datenbankseiten, deutsche Suche/literal gesuchte Prozentzeichen, Datum/Zeitzone, Rechte/Entzug/Logout, kompakte gegenüber bisherigen Antworten, gespeicherte Fortschritte, Zukunftsplanung, verspätete Antworten, Kontowechsel, 320/1280 px und Fokus-/Screenreaderregression. Der Backendcode blieb bei den anschließenden reinen Flutter-Fokuskorrekturen unverändert. Eine bekannte Starlette-Testclient-Abkündigungswarnung; keine ungeprüfte SDK-Migration.

Öffentlicher echter Browser: eigene isolierte Demo mit 601 künstlichen Seiten, unabhängige Anmeldung, Fach-/Such-/Statusfilter, Sortierung, Seitengröße, Detail/Rücksprung, 320 px Filter, 390 px Kind und 1280 px Eltern. Bestätigter Picker, Lernverlauf und getrennte Rückblick-/Antwortenansichten bestanden; null JavaScript-Laufzeitfehler. Vier feste Demoaufgaben wurden zuvor über die UI gelöst; der abschließende Durchlauf liest deren vier tatsächlich gespeicherte korrekte Antworten wieder ein (0 neue Antworten in diesem Wiederaufnahme-Durchlauf). Keine externen KI-Aufrufe und kein neuer KI-Qualitätsnachweis. Die öffentliche API lieferte alle 601 Quellen über 13 Seiten mit je höchstens 50 Einträgen genau einmal, ohne private Volltexte. Echte Kinderhaushalte wurden für diese Bibliotheksprüfung nicht gelesen oder geändert.

Native APK 21 im dedizierten API 36-Emulator tatsächlich bedient: unabhängiger Kinderlogin, 601 Heftseiten, Seitennavigation/Android-Zurück, Fach-/Tastatursuche, Filter schließen ohne erneute Tastatur und Wechsel nach Lernen. Vier gespeicherte Antworten sowie Rückblick/Antworten geprüft; dunkle Reitertexte zusätzlich im installierten APK sichtbar kontrolliert. Installierte APK unabhängig auf denselben SHA256 wie der öffentliche Download geprüft. Kein akustischer TTS-/Mikrofon- oder neuer Push-Nachweis.

Gesamten eigenen Prüfhaushalt anschließend normal gelöscht; frische Eltern-/Kindersitzungen vor Löschung gültig, danach 401. Private Prüfdatei entfernt, Appdaten nur im eigenen Emulator gelöscht; APK 21 bleibt installiert. Keine echten Haushalte oder anderen Geräte bereinigt. Vor Löschung tatsächliche 18 Geheimniswerte gegen Quellen, Web, APK/AAB und Übergabe geprüft: keine Treffer.

Web, signierte Direct-APK und Play-AAB 21 mit fixierter Toolchain gebaut. APK-Signatur, Quellversion, Hash und 16-KB-Zipausrichtung sowie bundletool 1.18.3 geprüft. APK: `artifacts/schulpilot-android.apk`, 62.903.665 Bytes; SHA256 `706bdcf04bf3817ceecb24da0154f861b2e423b834eb47f19bf8febed89d989d`. Play-AAB: `artifacts/schulpilot-play.aab`, 60.190.882 Bytes. Öffentlicher HTTPS-Download auf Größe/Hash geprüft; Bibliothek-/Lernen-Direktlinks 200, private Listen ohne Anmeldung 401. Kein Play-Console-Upload oder neuer Firebase-/Google-Nachweis daraus abgeleitet. Bekannte Warnungen der fixierten Plugins zum zukünftigen Kotlin-/Wasm-Ausbau verhindern diese tatsächlichen JS-/Android-Builds nicht.

Tatsächliches Android-Update 17→18→19→20→21 über den eingebauten Updater mit geprüftem Download und Android-Installationsbestätigung bestanden; kein adb install beim Upgrade. Auf Build 21 drei Prüfungen bei Kaltstart, Wiederöffnen und zusätzlichem Launcher-Intent beobachtet.

GitHub-Push funktioniert. [CI-Lauf des Produktcommits](https://github.com/meinzeug/schulpilot/actions/runs/38731618294): beide Jobs ohne ausgeführte Schritte gesperrt; Annotation „The job was not started because your account is locked due to a billing issue.“ Lokale erfolgreiche Prüfungen sind oben getrennt ausgewiesen.

API, Worker, Caddy und die drei zuvor geprüften anderen DorfSpy-Dienste sind weiterhin systemd-aktiv. Verschlüsselte Sicherungen vor Aktivierung vorhanden, zuletzt `20261015T120228Z.tar.enc`; Daten außerhalb der Releases. Gesicherte Vorversion für den dokumentierten [Rückweg](OPERATIONS.md): `/opt/schulpilot/releases/20261015T134620Z-eeac47c`. Kein Schemawechsel; andere Anwendungen wurden nicht umgestellt.

## Vorheriger Stand · 15.10.2026 · 1.1.1+17

Web und signierte native Flutter-APK 17 sind öffentlich aktiv: https://schulpilot.dorfspy.de . Aktiver Produktcommit `df7c6b69a43722a5c674cdd0fc1fd60cdf9536ab`, Release `20261015T100726Z-df7c6b6`; öffentliche HTTPS-Healthprüfung bestätigt Version 1.1.1 und diesen Commit. Nachfolgende reine Dokumentationscommits ändern den bereitgestellten Produktcode nicht. Migration 0011 ist aktiv. Kein neuer Dienst und keine Änderung anderer DorfSpy-Anwendungen.

### Lernweg, Rückblick und Heftfragen

- Der Lernweg richtet seinen geplanten Gesamtumfang nach bestätigten Seiten und Textdichte. Die erste Runde mit 2–5 Aufgaben ist der Einstieg; weitere kleine Etappen zum Verstehen, Fehlerfinden, Anwenden und späteren Abrufen werden ausdrücklich vorbereitet. Geplant, bereit und bearbeitet bleiben unterscheidbar; Elternzeiten, Lerntage und Pausen gelten weiterhin. Keine automatisch anwachsenden Nachholberge und kein Beherrschungsversprechen nach einer richtigen Antwort.
- Im ausdrücklich freigegebenen Originalfall mit fünf Seiten: 20 Aufgaben geplant, 5 bisher bearbeitet, KI-Rückblick mit 5 Einzelrückmeldungen bereit und 3 weitere neue Aufgaben tatsächlich vorbereitet. Vorhandene Fragen und alle 6 gespeicherten Antwortversuche unverändert verglichen; keine künstlichen Antworten im echten Kinderkonto. Die übrigen 12 Aufgaben sind geplant, noch nicht erzeugt. Zugang/Korrektur auditiert, temporäre Prüfsitzung widerrufen, private Diagnoseprogramme entfernt.
- Fotoerkennung ist ein eigener Abschreibauftrag mit geordneten Abschnitten/Formeln und konservativer Umfangsprüfung. Zwei künstliche volle Seiten lieferten 199 und 209 erkannte Wörter statt kurzer Bildbeschreibungen; Quellen werden weiterhin ausdrücklich bestätigt. Unleserliche Stellen werden nicht erfunden.
- Rückblick und Anschlussübungen sind getrennte begrenzte KI-Aufträge. Ein Generatorfehler verliert keinen fertigen Bericht oder Antworten. Bekannte Ziele, wörtliche Quellenoptionen und Aufgaben-/Zielpaare sind im Schema und nach dem Parsen gebunden. Bei bestätigten Bruchregeln plant der Server neue Zahlenbeispiele und prüft die Hauptlösungen vor dem KI-Aufruf; die KI ergänzt Lerntexte. Neue Aufgaben berücksichtigen wenig geübte Ziele und andere Tagesetappen. Einschränkungen, Zahlwörter und unpunktierte Heftzeilen sind geprüft. Keine Ersatzfragen nach einem Modellfehler.
- „Frag nach“ beantwortet Fragen zu eigenen bestätigten Seiten mit geprüften Originalzitaten; Folgefragen und Eltern-Leseansicht werden gespeichert. Erfolgreiche Erklärungen zählen während begonnener passender Einheiten als Hilfe. Keine Leistungsbewertung aus bloßen Fragen. Quellenlöschung, Export, Sitzungs-/Familienrechte und 365-Tage-Aufbewahrung gelten auch hier.
- Freiwilliges Vorlesen und Diktieren; bearbeitbarer Fragetext ohne automatisches Senden. Kein Autoplay oder Hintergrundmikrofon. Hinweis vor Aufnahme, Stoppen bei Hintergrund/Routenwechsel/Logout; Geräte-/Browserdienste können online arbeiten. Tippen/Lesen bleibt erhalten. Kurzes Antwortfeedback bleibt bis „Weiter“ sichtbar; Quellen und längere Details sind aufklappbar.

Einzelheiten und Quellen: [STUDY_PATH_TUTOR.md](STUDY_PATH_TUTOR.md), [COACHING.md](COACHING.md), [SOURCES.md](SOURCES.md). Die Etappen orientieren sich an Abrufübungen, verteilter Wiederholung und dem Wechsel zwischen Erklärung und eigenem Lösen; keine externe Wirksamkeitszertifizierung behauptet.

### Tatsächliche Abnahme

447 Backendtests auf isoliertem PostgreSQL bestanden (220,91 s, Exit 0) am oben genannten Produktcommit; darunter 50 Prüfungen der Bruchplanung einschließlich unpunktierter Regeln. 68 Fluttertests, Flutter-Analyse, Ruff und Format-/Diffprüfung bestanden. Fixierte Toolchain Flutter 3.47.7/Dart 3.13.5; neue Sprachpakete flutter_tts 4.2.5 und speech_to_text 7.5.0. Keine Anbieter-/Modellmigration oder Lockerung der Kosten-/Datenschutzgrenzen.

Öffentliche mobile Browserprüfung bei 390 px mit normalem eigenem Eltern-/Kinderkonto und künstlichen Fotos erfolgreich: Upload/Zuschnitt, vollständige Erkennung und Bestätigung, 8 geplante Aufgaben, erste Runde, zusätzliche Etappe, getrennte Rückblicke/Anschlussübungen, insgesamt 3 fertige Einheiten / 7 Antworten, tatsächlicher Hinweis, 2 echte Heftfragen mit Zitaten/Folgefrage, Elternansicht und Reload ohne neue Reservierung. 5 neue Rechenlösungen unabhängig mit JS-Ganzzahlrechnung bestätigt; ihre Hinweise/Erklärungen zusätzlich gelesen. Keine Browserlaufzeitfehler oder automatischen Aufnahmen. Keine vollständige automatische Prüfung natürlicher Lehrtexte behauptet.

Frühere synthetische OCR-, Coach- und Wiederholungsfehler sind in ihren alten Berichten erhalten, nicht nachträglich als Erfolge umgeschrieben. Genau ein ausdrücklich freigegebener Wiederholungsversuch nach der Mathekorrektur. Familienverbrauch 22 Aufrufe, davon 11 im erfolgreichen zweiten Durchlauf; bekannte Kosten 0 und unbekannte Kosten 0 für genau diese Aufrufe. Keine Familienlimits zurückgesetzt, kein drittes Kind angelegt, kein Anbieter gewechselt. Anschließend den eigenen gesamten Testhaushalt mit beiden künstlichen Kindern regulär gelöscht: Eltern-/beide Kindersitzungen 401, frühere private Bilder gesperrt, private Zugangsdaten-Datei entfernt. Echte Haushalte davon unberührt.

Installierte native APK 17 im API 36-Emulator: 16→17 über eingebauten Updater, echter Download und Android-Installationsbestätigung; kein adb install beim Upgrade. Installierte base.apk unabhängig auf Größe/Hash verglichen. Bei320dp reicht die erste Berührung des Fragefelds; Entwurf und Fokus überstehen die Tastaturänderung. Starter lesbar, gespeicherte Antworten und aufgeklappte Quellen sichtbar. Mikrofonhinweis ausdrücklich abgelehnt, RECORD_AUDIO weiterhin verweigert, kein Audio gestartet. Hörbare TTS-Ausgabe und reale Spracherkennung sind damit nicht als beobachtet behauptet. Appdaten des eigenen Emulators nach Familienlöschung entfernt; APK bleibt installiert.

Web, Direct-APK und Play-AAB 17 mit externer Signierung gebaut; Android-Metadaten, Signatur, 16-KB-Zipausrichtung und bundletool 1.18.3 geprüft. Regulärer Download vor/nach Login vorhanden. APK: `artifacts/schulpilot-android.apk`, 62.460.885 Bytes, SHA256 `28c6d3bc64da9d9e9d45670219eca835b54cf84d14725dff9e4a8be4a94b4a94`. Play-AAB: `artifacts/schulpilot-play.aab`, 59.749.479 Bytes. Öffentlicher Download erneut über gültiges HTTPS auf Hash/Größe geprüft. Direct nutzt den geprüften APK-Updater, Play ausschließlich Play-In-App-Updates; keine Play-Veröffentlichung behauptet.

Vor Aktivierung verschlüsselte Datenbanksicherung erfolgreich; vorheriger Release für Rückweg vorhanden. API/Worker/Caddy sowie merchagent, artist-studio-web und buddys-art aktiv. Web-Direktlinks und Datenschutz-HTML 200. Web/APK/AAB/Quellen und bereinigte Übergabe vor Bereinigung gegen 18 konkrete Geheimnisquellen geprüft: keine Treffer. Bereinigte Dateien unter `artifacts/firebase-handoff/`; private Dienstkonto-/OAuth-/Signierdateien bleiben außerhalb von Git und Downloads.

Google-/Firebase-Login- und Push-Nachweise unten stammen aus der früheren gesonderten Abnahme; keine erneute Zustellung mit APK 17 daraus abgeleitet. Verbleibende externe Voraussetzungen bleiben unverändert: vollständige Betreiber-/Bankangaben für zahlungspflichtige Bestellungen, zugängliches Play-Entwicklerkonto und die tatsächliche GitHub-Actions-Abrechnungssperre. Lokaler Build und GitHub-Push funktionieren; keine erfolgreiche gehostete CI oder 100 % Fehlerfreiheit behauptet.

### Archivierte Abnahme · 1.0.1+15

Die folgenden Abschnitte dokumentieren den früheren Stand. Insbesondere die damalige Gesamtgrenze von sechs Aufgaben, Build15 und damalige Testzahlen sind durch den oben beschriebenen Lernweg/Build17 ersetzt.


Web und reguläre signierte Direct-APK sind unter https://schulpilot.dorfspy.de aktiv. Implementierungscommit `6c2e434b8d5f177e0d9e0b20c53da1cac47bfecb`, Release `20261015T072218Z-6c2e434`, öffentlich über `/api/health` geprüft. Nachfolgende QA-/Übergabecommits ändern diesen bereitgestellten Produktcode nicht. Branch main wird ohne Force-Push zum bestehenden Remote gepusht.

### Mehrseitige Lernpakete · 15.10.2026

Den gemeldeten Fehler auf dem Server bei einer konkret freigegebenen Sammlung aus fünf bestätigten Seiten reproduziert: erste Auswahlantwort nicht eindeutig mit einer vorhandenen Option verbunden. Das private OpenRouter-Schema fordert nun einen ausdrücklich nullbasierten Integerindex an; vor dem Speichern bleiben alle bestehenden Fach-/Strukturprüfungen wirksam. Client und Datenbank erhalten vollständige Antworttexte.

Paketumfang nach bestätigten Themen und Elternzeit statt pauschal zwei Fragen: 2–5 je Einheit, höchstens sechs insgesamt. Erste Sachfragen verlangen kurze belegte Begriffe, keine unkontrollierten Varianten oder mehrteiligen Formeln. Rechenbeispiele nur in Mathematik. Auch eine strukturell gültige, aber inhaltlich ungeeignete Ausgabe wurde bei der Durchsicht verworfen; endgültiges Paket mit fünf Aufgaben und Erläuterungen geprüft, eine mehrdeutige Frage präzisiert. Alle fünf Quellenrevisionen erhalten, keine Kinderantworten zum Testen eingetragen, keine begonnene Einheit überschrieben. Zugriff und Korrektur auditiert; private Diagnoseinhalte nicht in Git.

Nach Deployment über öffentliche HTTPS unter dem berechtigten Kinderzugang gelesen: Paket ready, fünf Aufgaben, alle fünf privaten Bilder erreichbar, anonyme Bilderanfrage 401, Lösungen vor Bearbeitung verborgen. Reine Bewertung der gespeicherten Musterlösungen korrekt; fremde Aufgabenantworten nicht als richtige Lösung akzeptiert. Temporäre Prüfsitzung abgemeldet und widerrufen. API/Worker/Caddy sowie die drei geprüften fremden DorfSpy-Dienste aktiv; Sicherung vor Aktivierung erfolgreich. Schema weiterhin 0010; kompatibler Code-Rückweg auf den vorherigen Release vorhanden.

Private Diagnosekopien und Hilfsprogramme lokal und am Server nach Abschluss entfernt; originales Material und das geprüfte Lernpaket bleiben erhalten. Quelltext zusätzlich gegen konkrete private Materialausschnitte und Kontokennung geprüft, keine Treffer.

Reine Backendkorrektur, keine Flutter-/SDK-/Datenbankschemaänderung. Bestehende Web-, Direct-APK- und Play-Builds15 unverändert übernommen; Signatur, Hash, Quellversion und 16-KB-Zipausrichtung erneut geprüft. Kein erneuter Android-Build oder neuer Geräte-/Push-Test behauptet. Die Korrektur wirkt auch auf bereits installierte Clients.

### Damals implementiert und geprüft

- Native Flutter-App, responsive Flutter-Web-App, eigene API und PostgreSQL mit unabhängigen Eltern-/Kinderaccounts. Admin-Passwortlogin ohne TOTP, einmaliger abgesicherter Installationswizard. Rollen, Familientrennung und Sitzungswiderruf im Backend. Vorhandener Lernablauf, Elternplanung, KI-Lernbegleitung und wiederholte Abrufübungen bleiben erhalten.
- Regulärer Kanal **stable**, semantische Version und Paketmetadaten stimmen überein. Kein „Test-APK“-Name mehr. Release ohne eigenen externen Signierschlüssel scheitert; Manifest-/Deployprüfung verweigert Debug, fremde Signierer und veraltete Versionen. Ein anfänglich veraltetes APK-Artefakt wurde tatsächlich abgefangen; der anschließend vollständige Build15 besteht alle Prüfungen.
- Neuer schwarzer US-Abschlusshut als App-Logo, adaptives Android-Launcher-Icon und Startsymbol, Web-/PWA-/Store-Assets. Im tatsächlich installierten Android-Launcher mit APK-Build 15 sichtbar geprüft. Bildquelle, finale Vorgabe und reproduzierbare Größenexporte in `design/brand/` und `scripts/export_brand.py`.
- Optionaler **Google-Elternlogin** über eigenes Backend, ausschließlich openid/email, kein Firebase Authentication. Tatsächlicher Google-Consent, Codeaustausch, Signaturprüfung, Elternregistrierung, erster und wiederholter Weblogin gegen Google bestanden. Genau eine Familie/Identität, zwei auditierte Google-Anmeldungen. Eigenes Elternpasswort funktioniert; unabhängiges künstliches Kind angelegt und angemeldet, Eltern-/Admin-/Google-Rollenwechsel 403, Logout 401. Gesamten eigenen Google-QA-Haushalt einschließlich Identität anschließend normal über die API gelöscht; Sitzungen 401.
- Keine automatische E-Mail-Verknüpfung: bestehendes Elternpasswort und aktive Sitzung nötig. Nicht von Google betriebene Postfächer werden zusätzlich durch die eigene echte Bestätigungsmail geprüft. Web liefert nur HttpOnly-Cookie; Android braucht Client-PKCE und separates Callback-Ticket. Kryptografische und Missbrauchsregressionen, Einmaligkeit, Ausfälle und Rechte geprüft. Android-App-Links tatsächlich verifiziert; kalter HTTPS- und warmer eigener Rücksprung lehnen ungültige Antworten/fehlenden Geräte-Proof sichtbar ab. Ein vollständiger Android-Google-Login mit einem auf dem Gerät angemeldeten Google-Konto ist noch eine gesonderte Beobachtung.
- Bestehendes Google-Projekt `schulpilot-f6bf3`; ein Web-OAuthclient „SCHULPILOT Elternzugang“. Branding, Hut und URLs gespeichert, Zielgruppe extern **In Produktion**. Inhaberschaft nur der SCHULPILOT-Subdomain durch offizielle HTML-Datei erfolgreich bestätigt; keine DNS-/Nameserveränderung. Datenschutz liegt nun ohne JavaScript als lesbares HTML vor. Google zeigte vor dieser Korrektur fehlenden Inhaberschaftsnachweis/maschinenlesbare Datenschutzinhalte; Branding-Wiederprüfung nach Googles genannter Aktualisierungsfrist bis zu 24 Stunden offen. Grundlegender Google-Login funktioniert bereits; die Konsole bestätigt keinen zusätzlich prüfpflichtigen Datenzugriff. [GOOGLE_LOGIN.md](GOOGLE_LOGIN.md).
- Firebase-Projekt/Apps, drei benötigte APIs und tatsächliche bestehende Keyrestriktionen unabhängig geprüft; getrennte Plattformkeys. Dedicated-Sender mit ausschließlich `cloudmessaging.messages.create`, genau ein geschützter Schlüssel. Echte Sender-OAuth- und FCM-ValidierungHTTP 200; keine Nachricht durch die Validierung gesendet. Produktive Push-Freigabe nach eigenständigem Betreiberauftrag auditierbar aktiv; neue Installationen bleiben standardmäßig aus. Opt-in, zusätzliche Elternzustimmung, Sitzungsbindung, neutrale Inhalte, Ruhezeiten und Widerruf erhalten.
- Tatsächlicher Web-Push: null Firebase-Anfragen vor Opt-in, danach Installations-/Registrierungs-/eigene API 200, separater Serviceworker unter `/push/`, Validierung, FCM-Annahme und sichtbarer Vordergrundhinweis. Tatsächlicher APK-Build 14 im Android-Emulator (API 36): Kinderlogin, Registrierung, erteilte Android-Berechtigung, zwei FCM-Annahmen und sichtbarer Vordergrundhinweis. Der ursprüngliche zweite Hinweis kam 456 ms vor onStop und ist ausdrücklich kein zuverlässiger Hintergrundtest oder nachgewiesener Produktfehler. Mit APK-Build 15 anschließend sauber bei nachgewiesenem STOPPED genau eine weitere Nachricht eingereiht: FCM-Annahme, sichtbare Android-Benachrichtigung und Öffnen ins richtige geschützte Kinderkonto bestanden. Gerät und Sitzungen danach abgemeldet/entfernt. Weitere Einzelheiten im bereinigten Handoff.
- Automatisches Android-Update13→14 und14→15 mit echtem Download/Hashprüfung und Android-Installationsbestätigung bestanden; kein adb install beim Upgrade. Auf Version 14 und 15 jeweils drei tatsächliche Prüfungen bei Kaltstart, Wiederöffnen und zusätzlichem Launcher-Intent. Direkter und Play-Updateweg bleiben getrennt.
- Web-Verkaufsseite, vorausbezahlte Tarife, Überweisungsaufträge und manuelle atomare Freischaltung implementiert. Echte Betreiber-/Anschrift-/Steuer-/Bankangaben fehlen; zahlungspflichtige Bestellungen deshalb weiterhin serverseitig gesperrt. Keine erfundenen Bank- oder Betreiberangaben. [STORE.md](STORE.md).

### Tests und Builds des damaligen Stands

**221 PostgreSQL-Backendtests bestanden** am 15.10.2026 (146,41 s; isolierter Lauf, Exit 0), Ruff und Python-Kompilierung ohne Befund. Darunter neue Regressionen zu Auswahlindizes, falschen Aliasen, Quellenbezug, kurzen Sachantworten und Zeit-/Aufgabenlimits. Zuvor zwei veraltete Schema-Erwartungen und eine nicht dem angeforderten Umfang entsprechende Mockantwort korrigiert; ein früherer Gesamtlauf wurde vom Ausführungsprozess abgebrochen. Der abschließende vollständige Lauf ist erfolgreich. **43 Fluttertests und Flutter-Analyse zuletzt am 14.10.2026 bestanden**; Flutter blieb unverändert. Migrationsprüfung erhält vorhandene Daten bis 0010; negative Releaseprüfungen und echte Google-Verifikationsbibliothek gegen synthetisch signierte gültige/abgelaufene/falsche Tokens geprüft.

Web, Direct-APK und Play-AAB 15 erfolgreich mit fixierter Toolchain gebaut. APK `apksigner verify` und `zipalign -c -P16 4` erfolgreich; AAB mit bundletool1.18.3 validiert. Bekannte Starlette-/zukünftige Kotlin-Pluginhinweise, keine offenen Buildfehler. Neue Google-Dart-Abhängigkeit `crypto 3.0.7` war bereits in derselben Version transitiv fixiert.

Öffentliche HTTPS-Browserprüfungen: mobile 390 px, Angebote/Vertragslink, Eltern-/Admin-Rollensperren, geschützte Push-/Verkaufsseiten, private Geheimnisse nicht in Antworten, keine Firebase-Anfragen vor Opt-in, null JavaScript-Laufzeitfehler. Zwei tatsächliche APK-Downloads vor/nach Login mit passender Größe/SHA256. Eigenen zusätzlichen Download-Testraum gelöscht. Öffentliche Health-, Google-Status-, Datenschutz-, Assetlinks- und Google-Datei-EndpunkteHTTP 200.

APK: `artifacts/schulpilot-android.apk`, 61.869.521 Bytes; SHA256 `de2a48a357ececb5452c6c31a026a1c1f4dec7039af35b54689456da7cf9f1c0`. Play-AAB: `artifacts/schulpilot-play.aab`, 59.288.710 Bytes. Privater Signierschlüssel und Google-Dateien außerhalb von Git und Builds. Bereinigte drei Übergabedateien unter `artifacts/firebase-handoff/`.

GitHub-Push funktioniert. [Tatsächlich geprüfter CI-Lauf](https://github.com/meinzeug/schulpilot/actions/runs/38637840266) für e6faf72: beide Jobs ohne ausgeführte Schritte abgewiesen, Annotation jeweils „The job was not started because your account is locked due to a billing issue.“ Keine erfolgreiche GitHub-CI behauptet. Die Play Console wurde mit dem autorisierten Google-Konto tatsächlich geöffnet und bietet die erstmalige Entwicklerkonto-Erstellung an; kein vorhandenes Entwicklerkonto zugänglich, keine kostenpflichtige Registrierung oder Veröffentlichung ausgeführt.

### Erhaltene KI-Abnahme

Der reguläre KI-Lernablauf wurde zuvor mit normalen unabhängigen Eltern-/Kinderzugängen und ausschließlich künstlichen Heftseiten über öffentliche HTTPS tatsächlich bedient: zwei Fotos importiert/zugeschnitten, erkannt und bestätigt; Tagespaket, Antworten/Hinweise, KI-Rückblick und neue Anschlussübungen; fortgesetztes Paket und Elternverlauf. Gesamter zweiter Durchlauf zwölf gespeicherte externe Free-Aufrufe, alle erfolgreich, feste Modell-/Upstreambindung, erfasste Kosten0 für diese bekannten Gratisaufrufe. Frühere unbekannte Kosten bleiben unbekannt und wurden nicht nachträglich als0 bezeichnet. In der nativen App auf drei Neustarts verteilt wieder aufgenommen; zwei Materialien/ein Paket/zwei Einheiten, keine doppelten Quellen.

OpenRouter Free ist ausdrücklich freigegeben und Standard. Preisgrenze0 und Data-Collection-Deny bleiben aktiv; die zusätzliche ZDR-Anforderung ist im beauftragten Free-Standard nicht erzwungen. Gratisanbieter können ausfallen oder ungültige Antworten liefern; keine erfundenen Erfolge, heimlichen Providerwechsel oder unbegrenzten Wiederholungen. Lernziele verlangen mehrere selbstständige Prüftage über mindestens sieben Tage; ein einzelner Erfolg beweist keine sichere Beherrschung. [AI_STANDARD.md](AI_STANDARD.md).
