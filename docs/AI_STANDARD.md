# OpenRouter Free als Standard

Auftrag und Anbieter-/Datenschutzfreigabe vom 14.10.2026: „openrouter mit free modellen wird standard. freigabe erteilt.“ Der Lernablauf soll ausdrücklich auch mit regulären Kinderaccounts funktionieren.

Der fest gewählte Standard für Bilderkennung, einzelne Lerneinheiten und Tagespakete ist `dots-studio/dots-3-note-preview:free`, Endpunkt `atlas-cloud/fp8`. Der aktuelle offizielle Katalog bestätigt Bild-/Texteingaben, strukturierte Ausgaben und Tokenpreise 0. Zusätzlich wird der konkrete Endpunkt vor **jedem** Aufruf auf Preis 0 und erforderliche Fähigkeiten geprüft. Die Anfrage erzwingt Preisobergrenzen 0, genau diesen Upstream und `allow_fallbacks=false`. Keine Werkzeuge, kein bezahltes Ersatzmodell, kein automatischer Modellwechsel und keine automatische Inferenzwiederholung.

## Datenregeln

Normale Lernanfragen behalten `data_collection=deny`. Die zusätzliche Bedingung `zdr=true` wird im ausdrücklich freigegebenen Free-Standard nicht erzwungen. Das ist keine behauptete Zero-Data-Retention-Freigabe oder Garantie. OpenRouters eigene Konto-/Guardrail-Einstellungen gelten zusätzlich und können nicht durch eine Anfrage gelockert werden.

Die getrennte Prüfung am 14.10.2026 ergab: Dots/AtlasCloud beantwortet Bild- und Textanfragen mit `deny` ohne zusätzliche ZDR-Pflicht. Die getesteten Nvidia- und Liquid-Free-Routen antworteten unter denselben Einstellungen mit HTTP 404. Deshalb wird für beide Funktionen ausdrücklich Dots gewählt; die Datenfilter werden nicht auf `allow` umgestellt.

OpenRouter veröffentlicht Datenregeln, Providerregeln, Nutzungsbedingungen und einen DPA. Der Betreiber hat die Anbieter-/Datenschutzfreigabe erteilt; das Repository behauptet keine unabhängige Rechtsprüfung oder vom Anbieter ausgestellte zusätzliche Freigabe. Providerkonten und Schlüssel gehören ausschließlich dem volljährigen Betreiber, nicht den Kindern. Namen, Zugangsdaten und Familienkennungen gehören nicht in Lernprompts. Bilder werden vorher zugeschnitten und ohne unnötige Metadaten gespeichert.

## Einrichtung und Prüfung

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
