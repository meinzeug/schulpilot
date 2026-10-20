# OpenRouter-Operatorwechsel ·20.10.2026

Der Betreiber hat ausdrücklich den Wechsel auf bezahlte, bedarfsabhängig
ausgewählte OpenRouter-Modelle mit dem Schlüssel aus `~/or.txt` beauftragt.
Nach nicht möglicher Browseranmeldung folgte ausdrücklich: den Schlüssel direkt
verwenden. Kontoweites OpenRouter-Inhaltslogging und Datenfreigabe konnten deshalb
nicht in der Kontooberfläche eingesehen werden. Das wird nicht als geprüft oder
deaktiviert ausgegeben. Die bestehende allgemeine Betreiberfreigabe bleibt erhalten.

Der Schlüssel stimmt mit der geschützten Serverumgebung überein; kein Schlüssel
in Git, Release, Browser oder Bericht. Anbieterstand vor dem Wechsel geschützt
unter `/var/lib/schulpilot/operator-checkpoints/` gesichert. Konfiguration und
Wechselgrund sind auditiert. Die aktive Auswahl ist OpenRouter, aktuell Revision29.

## Verifizierte Routen und Schutzvorgaben

| Stufe | Modell | Upstream | USD/Mio. Input | USD/Mio. Completion |
| --- | --- | --- | ---: | ---: |
| Luna | openai/gpt-6-luna | azure | 0,10 | 0,50 |
| Sol | openai/gpt-6.1-sol | azure | 2,00 | 10,00 |

Preise, Bildfähigkeit, Reasoning/JSON-Schema-Parameter und ZDR-Endpunkte wurden
am20.10. über die offiziellen Modell-/ZDR-APIs erneut gelesen. Astra bleibt ohne
eigene Inferenzabnahme deaktiviert. Je Auftrag explizite Modell-/Upstreambindung,
medium, ZDR, data_collection=deny, require_parameters=true, allow_fallbacks=false,
Preisobergrenzen, store=false und X-OpenRouter-Cache:false. Keine Werkzeuge,
Plugins, Audio oder Websuche. Kein automatischer Zweitaufruf bei Modellfehlern.
Diese Anfragevorgaben belegen keine eingesehenen kontoweiten Logging-Einstellungen.

ECB-Referenz vom19.10.:1EUR=1,1225USD. Für die Reservierung invertiert und nach
oben auf0,890869EUR/USD gerundet; keine behauptete tatsächliche EUR-Rechnung.
Prüfung auf dem Produktionsserver wiederholt, weil seine Systemzeit gegenüber
dem Arbeitsplatz rund zwei Stunden abweicht. Die Systemuhr wurde wegen anderer
Dienste nicht verändert. Servereigene Prüfzeit vermeidet eine fälschliche
Zukunftsprüfung; die Zeitabweichung bleibt ein separater Betriebsbefund.

Die ausdrücklich angekündigte maximale Auftragsreservierung steigt vom bisherigen
Codex-Buchungswert0,001USD auf0,15USD. Beide Routen reservieren höchstens0,15USD.
Die anfängliche Luna-Reservierung0,05USD stoppte ein normales künstliches Foto
knapp vor dem Versand: Die konservative Prüfung zählt Base64-Bytes als mögliche
Inputtokens. Auditiert auf die bereits freigegebene Obergrenze angeglichen,
ohne Preis-, Modell- oder Quotenänderung; abgebrochener Aufruf mit0USD abgerechnet.
Das sind konservative Reservierungen innerhalb der unveränderten
Familien-/Systembudgets, keine Ausgabenpauschalen. Globales Limit weiterhin10USD;
Familienbudgets, Aufrufkontingente und Zeitlimits unverändert. Ausgabe je Route
höchstens4.000Tokens und weiterhin höchstens der bestehende Konfigurationswert.
Neue lokale CLI-Fassung erlaubt eine solche Buchungsreservierung nur über das
ausdrückliche Feld reservation_micros mit Audit; ohne Feld bleibt der alte Wert.

## Tatsächliche technische Abnahme

Operatorauftrag mit ausschließlich festen künstlichen Vorlagen, gleicher
Produktionsworker und normal gezählte globale Reservierungen:

| Funktion | Modell | Inputtokens | Completiontokens inkl. Reasoning | erfasste USD |
| --- | --- | ---: | ---: | ---: |
| Fotoabschrift | Luna | 1.903 | 1.094 | 0,000738 |
| Aufgaben | Sol | 2.753 | 881 | 0,014316 |
| Tagespaket | Sol | 3.001 | 1.378 | 0,019782 |

Alle drei erfolgreich; insgesamt0,034836USD gemeldete Inferenzkosten. Gebundener
Prüfbetrag nach Abrechnung ebenfalls0,034836USD, keine unbekannte neue Rechnung
und Prüfcap0,25USD eingehalten. Die technische Produktionssperre ist aufgehoben.
Reguläre reservierungsfähige Routen für OCR, Aufgaben, Pakete, Coach, Tutor und
Sprachprojekte wurden zusätzlich ohne Inferenz geprüft. Kein Kinderinhalt wurde
für diese Operatorprobe übertragen. Dies ist keine allgemeine Qualitäts- oder
Lernwirksamkeitsgarantie und kein Guthabenkauf; Kaufgebühren bleiben unbekannt.

## Kostengünstige Auswahl ab51

Der weitere ausdrückliche Auftrag verlangt günstige Modelle auch bei Hilfen.
`economy_mode` ist eine explizite versionierte Policy, standardmäßig aus für
unveränderte Installationen. Der lokale Router liest Umfang und Zuordnung aus
eigenen gespeicherten Quellen und bisherigen Attempts; kein zusätzlicher
KI-Klassifikator. Klare kurze Heftfragen und Rückblicke sowie eng begrenzte
einfach-fachliche Übungen können Luna nutzen. Unbekannter oder größerer Umfang,
mehrere Fächer, unklare Quellen, mindestens zwei Fehler oder unklare Bewertungen
wählen Sol vor dem Aufruf. Das ist eine überprüfbare Kostenheuristik, kein
empirischer Gleichwertigkeitsnachweis. Reservierte Routen bleiben unverändert.

Identische zusammengestellte Hefttexte in Anschlussaufträgen werden nur einmal
übertragen; Quelldaten, Revisionen und interne Antwort-/Schema-Prüfungen bleiben
vollständig. JSON wird ohne unnötige Trennzeichen-Leerzeichen übertragen. Keine
unbelegte feste Tokenersparnis aus einer reinen Bytezählung ableiten.

Der Sparmodus ist aktiv. Eine weitere vollständige feste Probe nach Aktivierung
kostete0,033344USD, die Probe nach Anpassung der Fotoreservierung0,033884USD.
Alle drei Proben erfolgreich, zusammen0,102064USD bekannte Inferenzkosten.
Aktive Policy: paid-economy-20261020-v3-photo-hold, Konfigurationsrevision29.
Die normale App-Abnahme verwendet zusätzlich ausschließlich die neun künstlichen
Seiten aus qa/notebook_audit_images_20261020.json. Deren Kosten werden getrennt
von den festen Operatorproben erfasst; keine alten echten Antworten zum Testen.

## Abnahme55

Abgeschlossene künstliche Browserabnahme auf1.11.5+55: neun normale OCRs,
gemeinsames Paket, drei erfolgreiche Luna-Rückblicke und eine belegte Luna-Hilfe.
Details in APP_AUDIT_2026_10_20.md. Einschließlich drei fester Probeabläufe
0,224013USD gemeldete Inferenzkosten. Drei400er behalten unbekannte Abrechnung
und volle Reservierung; deren konservative Modellkostenobergrenzen zusammen
0,013486USD. Insgesamt höchstens0,237499USD dieser Abnahme, unter0,25USD.
Keine weiteren Prüfaufrufe oder erneute Operatorprobe nötig. Fehlerursache der
400er (Anführungszeichen in strengem Quellen-Enum) durch geprüfte Integerindizes
behoben; keine Quellenprüfung gelockert. Kontoeinstellungen nicht unabhängig
eingesehen; Gebühren/Steuern und unbekannte Altbelege nicht als0behauptet.

## Rückweg

Vorher neue KI-Aufträge stoppen und aktive Aufträge abarbeiten. Gesicherten
Providerstand lokal mit Revisionserhöhung und Audit wiederherstellen; keine
Ausgaben, offenen Reservierungen oder bestehenden Antworten zurücksetzen.
Keine automatische Rückkehr zu Codex oder Free bei Providerfehlern. Code-Rückwege
nach der neuen Rundenlöschung müssen den neuen unit-Löschjournalscope erhalten;
siehe NOTEBOOKS.md. Keine Datenbankrücksicherung über neue Löschungen.
