# OpenRouter Free als Standard

Auftrag und Anbieter-/Datenschutzfreigabe vom 14.10.2026: „openrouter mit free modellen wird standard. freigabe erteilt.“ Der Lernablauf soll ausdrücklich auch mit regulären Kinderaccounts funktionieren.

Der fest gewählte Standard für Bilderkennung, einzelne Lerneinheiten und Tagespakete ist `dots-studio/dots-3-note-preview:free`, Endpunkt `atlas-cloud/fp8`. Der aktuelle offizielle Katalog bestätigt Bild-/Texteingaben, strukturierte Ausgaben und Tokenpreise 0. Zusätzlich wird der konkrete Endpunkt vor **jedem** Aufruf auf Preis 0 und erforderliche Fähigkeiten geprüft. Die Anfrage erzwingt Preisobergrenzen 0, genau diesen Upstream und `allow_fallbacks=false`. Keine Werkzeuge, kein bezahltes Ersatzmodell, kein automatischer Modellwechsel und keine automatische Inferenzwiederholung.

## Datenregeln

Normale Lernanfragen behalten `data_collection=deny`. Die zusätzliche Bedingung `zdr=true` wird im ausdrücklich freigegebenen Free-Standard nicht erzwungen. Das ist keine behauptete Zero-Data-Retention-Freigabe oder Garantie. OpenRouters eigene Konto-/Guardrail-Einstellungen gelten zusätzlich und können nicht durch eine Anfrage gelockert werden.

Die getrennte Prüfung am 14.10.2026 ergab: Dots/AtlasCloud beantwortet Bild- und Textanfragen mit `deny` ohne zusätzliche ZDR-Pflicht. Die getesteten Nvidia- und Liquid-Free-Routen antworteten unter denselben Einstellungen mit HTTP 404. Deshalb wird für beide Funktionen ausdrücklich Dots gewählt; die Datenfilter werden nicht auf `allow` umgestellt.

OpenRouter veröffentlicht Datenregeln, Providerregeln, Nutzungsbedingungen und einen DPA. Der Betreiber hat die Anbieter-/Datenschutzfreigabe erteilt; das Repository behauptet keine unabhängige Rechtsprüfung oder vom Anbieter ausgestellte zusätzliche Freigabe. Providerkonten und Schlüssel gehören ausschließlich dem volljährigen Betreiber, nicht den Kindern. Namen, Zugangsdaten und Familienkennungen gehören nicht in Lernprompts. Bilder werden vorher zugeschnitten und ohne unnötige Metadaten gespeichert.

## Einrichtung und Prüfung

Neue Installationen konfigurieren Provider und Schlüssel im lokal freigeschalteten [Einrichtungsassistenten](INSTALLATION.md); danach stehen dieselben Betriebswerte im Adminbereich zur Verfügung. Der dortige echte Beispieltest läuft dauerhaft im vorhandenen Worker, verwendet feste künstliche Bild-/Text-/Paketdaten und reserviert seine Aufrufe im globalen Kontingent. Nur die tatsächlich getestete unveränderte Free-Konfiguration wird aktiviert. Die Anmeldung des Administrators verwendet Benutzername und Passwort ohne TOTP.

Schlüssel ausschließlich verschlüsselt serverseitig hinterlegen. Bei bestehendem OpenRouter-Schlüssel und global dokumentierter Betreiberfreigabe:

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py configure-free-standard' <<'JSON'
{"evidence":"2026-10-14: Betreiber beauftragt OpenRouter Free als Standard und erteilt Anbieter-/Datenschutzfreigabe; Data-Collection-Deny, keine zusätzliche ZDR-Pflicht."}
JSON
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py probe-private-route'
```

Der erste Befehl setzt die bekannte kostenlose Konfiguration, erhält den verschlüsselten Schlüssel, dokumentiert den Operatorwechsel und sperrt die Route zunächst. Erst drei erfolgreiche begrenzte Aufrufe mit festem künstlichem Bild/Text/Paket heben den technischen Blocker auf. Ein fehlgeschlagener Test oder eine zwischenzeitlich geänderte Konfiguration aktiviert nichts. API-Keys niemals in JSON-Beispielen, Shell-Argumenten, Flutter oder Git eintragen.

Migration 0006 erhält auf bestehenden Installationen zunächst die bisherige ZDR-Einstellung. Im Adminbereich sind „Nur kostenlose OpenRouter-Modelle“ und die zusätzliche ZDR-Pflicht sichtbar. Änderungen an Modell, Endpunkt, Schlüssel oder Routing invalidieren den bisherigen technischen Nachweis. Ältere Clients, die diese neuen Felder nicht senden, verändern sie nicht versehentlich. Die lokale Konfiguration ist kein öffentlich erreichbarer Befehlsexecutor.

Kosten- und Familienkontingente, Rate Limits, atomare Reservierung und Notfallstopp bleiben wirksam. Nicht ermittelbare Kosten bleiben unbekannt. Providerseitige Free-Kontingente können zusätzliche Begrenzungen verursachen; es werden keine Credits oder Ressourcen bestellt.

Ausdrücklich beschriftete Auswahlantworten werden deterministisch gelesen: Meldet das Modell `B` und enthält seine Optionsliste eindeutig `B: 3/4`, speichert die App die vorhandene vollständige Antwort `B: 3/4`. Die Optionen und dazugehörigen Hinweise bleiben erhalten. Unbeschriftete, doppelte oder mehrdeutige Buchstaben werden nicht erraten; mathematisch falsche Lösungen und falsche Alternativen bleiben abgelehnt. Es entstehen dadurch keine erfundenen Ersatzaufgaben und keine zusätzlichen KI-Aufrufe. `temperature=0` reduziert die Zufälligkeit, garantiert aber keine identischen oder fachlich immer richtigen Ausgaben.

Explizite Brucherweiterungen mit fest genanntem Faktor werden zusätzlich auf die verlangte Zähler-/Nennerdarstellung geprüft. Eine gleichwertige, aber nicht wie verlangt erweiterte Variante darf keine richtige Antwort ergeben. Korrekte Hauptlösungen bleiben unverändert; ungeeignete akzeptierte Varianten werden entfernt. Die Bewertung schützt auch früher gespeicherte Aufgaben mit solchen Varianten.

Einzelne Einheiten und Coach-Folgerunden verwenden im Free-Standard zwei Aufgaben. Tagespakete verteilen zwei bis fünf Aufgaben pro Einheit auf die unterschiedlichen bestätigten Seitenthemen; insgesamt höchstens sechs. Die verfügbare Einheitenzeit begrenzt die Anzahl zusätzlich, drei Minuten bleiben für Lesen und Rückmeldung. Gruppenauswahl, Fach, Aufgabenanzahl und bestehende Elternziele werden serverseitig geprüft. Ausgabeschemas begrenzen Aufgaben-, Hinweis- und Textlängen bereits beim Anbieter. Erste Sachpakete verwenden Auswahl und kurze Eingaben; Mathematik kann außerdem Lückentexte verwenden. Vorhandene Aufgabenrenderer und gespeicherte Einheiten bleiben erhalten. Der ausführliche Reasoning-Modus ist im kompakten Profil abgeschaltet; keine zusätzliche automatische Wiederholung.

Seit 15.10.2026 bindet das private OpenRouter-Ausgabeschema Auswahlantworten über einen ausdrücklich nullbasierten Integerindex an eine vorhandene Option. Indexgrenzen, eindeutige Optionen und die bestehenden Fachprüfungen gelten vor dem Speichern. Web, Android und Datenbank erhalten weiterhin den vollständigen Antworttext. Alte eindeutige Textantworten bleiben kompatibel; Buchstaben, numerische Strings und unvollständige Antworten werden nicht als Index erraten.

Bei anfänglichen Sachpaketen außerhalb Mathematik fordert das Schema keine zusätzlichen akzeptierten Varianten an. Kurze Antworten enthalten höchstens fünf Wörter und 80 Zeichen, keine Formeln oder Aufzählungen; sie müssen als vollständiger Begriff/Ausdruck im bestätigten Inhalt der jeweiligen Fachgruppe stehen. Die Software verwirft unbelegte Werte und fremde Varianten. Das ist ein enger Abrufmodus für den Einstieg; weiterführende Transferaufgaben und begründet unklare Antworten bleiben in der bestehenden KI-Lernbegleitung. Quellenbezug allein garantiert noch keine fachlich richtige Zuordnung. Rechenbeispiele werden nur bei ausgewählten Mathematikfächern in den Prompt aufgenommen.

Der gemeldete Mehrseitenfehler wurde am 15.10.2026 auf dem Server reproduziert. Für die konkret vom Betreiber freigegebenen fünf Seiten entstand anschließend ein Paket mit fünf Aufgaben; Lösungen, Begründungen und Quellen wurden zusätzlich inhaltlich durchgesehen, eine mehrdeutige Frage präzisiert. Eine vorherige unzureichende Ausgabe wurde verworfen. Seitenrevisionen und bisherige Kinderantworten wurden nicht verändert; private Diagnoseinhalte gehören nicht ins Repository. Kosten- und Aufrufzählung bleibt auch für ausdrückliche Prüfungen aktiv.

Die Lernbegleitung verwendet denselben privaten Free-Endpunkt für echte Antwortkontrolle und Anschlussübungen. Zusammenfassung und Fortschritt werden aus gespeicherten Fakten berechnet. Bereits bekannte Lernziele werden serverseitig erhalten und im Modelloutput nicht erneut erzeugt. Das verkürzt die strukturierte Ausgabe und verhindert geänderte Zielkopien. [Ablauf und Grenzen](COACHING.md).

## Regulärer End-to-End-Test

```bash
.venv/bin/python scripts/prepare_normal_ai_smoke.py
cd qa
node download.mjs --reuse-qa-account
node school_day.mjs
```

Ein reguläres Elternkonto wird über echte Gmail-Zustellung verifiziert und ein eigener Kinderzugang angelegt. Zwei ausschließlich künstliche neue Schulstoffbilder werden lokal gesetzt. Im Browser wählt das Kind beide Bilder, bestätigt die Zuschnitte, startet die normale KI-Erkennung, prüft jede Seite und erstellt das Tagespaket. Es beantwortet die tatsächlich erzeugten Aufgaben; Eltern sehen die gespeicherten Ergebnisse. Der Test ruft weder `/demo` noch die synthetischen Material-Endpunkte auf. Das Familienkennzeichen bleibt `synthetic=false`; der Provider erhält die normalen geprüften Lernanfragen, aber ausschließlich künstlichen Teststoff.

Zugangsdaten liegen vorübergehend in der ignorierten Datei `artifacts/.school-day-qa-account.json` mit 0600. Bei Erfolg werden Testfamilie und Datei entfernt. Nach einem fehlgeschlagenen Test kann `scripts/prepare_normal_ai_smoke.py --cleanup` ausschließlich dieses eigene Testkonto entfernen. Tatsächliche Ergebnisse stehen in [STATUS.md](STATUS.md).

## Verfügbarkeit

Die offizielle Modellseite kündigt das Ende dieser kostenlosen Preview zum **31.12.2026** an. Vor diesem Datum ein dann verfügbares kostenloses Modell ausdrücklich auswählen und Bild-/Schema-/Paketprüfung erneut durchführen. Keine dauerhafte Modellverfügbarkeit versprechen. Wenn ein Endpunkt wegfällt oder nicht mehr kostenlos ist, bleibt die Anfrage gesperrt und gespeichertes Lernen nutzbar.

Quellen, geprüft am 14.10.2026: [Modell und Verfügbarkeit](https://openrouter.ai/dots-studio/dots-3-note-preview:free), [Endpunktkatalog](https://openrouter.ai/api/v1/models/dots-studio/dots-3-note-preview:free/endpoints), [Routing und Datenfilter](https://openrouter.ai/docs/guides/routing/provider-selection), [Providerregeln](https://openrouter.ai/docs/guides/privacy/provider-logging), [Datenerfassung](https://openrouter.ai/docs/guides/privacy/data-collection), [Datenschutz](https://openrouter.ai/privacy), [Nutzungsbedingungen/DPA](https://openrouter.ai/terms), [Free-Limits](https://openrouter.ai/docs/api_reference/limits), [AtlasCloud](https://www.atlascloud.ai/privacy).
