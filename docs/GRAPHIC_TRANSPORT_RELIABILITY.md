# Flacher Grafiktransport für Lernrunden

Stand: 28.10.2026, Version1.37.1+152. Keine Schema-/Datenmigration.

## Befund

Ein gemeldeter normaler Heft-Rundenauftrag wurde nach etwa zwei Sekunden mit einer Fehlerhülle innerhalb einer HTTP200-Antwort abgebrochen. Es gab weder Aufgaben noch einen verifizierten Kostenbeleg. Die bisherige Fehlerbehandlung speicherte bei diesem Transportfall keine geschlossene Anbieter-Fehlerkategorie. Der nachträgliche Generierungsabruf lieferte404; das beweist keine Gebührenfreiheit. Eine genaue ursprüngliche Anbieterbegründung ist damit nicht rekonstruierbar.

Der rein lokale Wiederaufbau genau dieser Anfrage zeigte unabhängig davon eine konkrete Kompatibilitätslücke: Das Schema erlaubte13 verschachtelte JSON-Container, unter anderem über Aufgabe → Erklärschritt → Darstellung → Grafik → Szene → Phase → Platzierung. Auch Sprachbausteine können tiefe Pfade bilden. Die Dokumentation nennt höchstens zehn Verschachtelungsebenen. Die bisherige Regression zählte nur Objekte und übersah die zusätzlichen Arrays. Eine erfolgreiche frühere spezialisierte Runde hatte einen deutlich flacheren Grafikvertrag. Die Tiefe ist ein belegter Vertragsfehler und eine plausible Ursache für den frühen Abbruch; der fehlende ursprüngliche Anbieterfehler erlaubt keine stärkere Kausalbehauptung.

## Zusätzlicher echter Produktionsbefund

Der einzelne regulär reservierte Reparaturaufruf mit dem flacheren Schema brach ebenfalls nach etwa einer Sekunde ab. Die ergänzte Diagnose erfasste diesmal den Anbieterfehler502 und die tatsächliche Grafiktransportversion. Damit ist belegt, dass die Schemaabflachung allein diesen konkreten Produktionsfehler **nicht** löst.

Die anschließend gelesenen offiziellen Modell- und ZDR-Endpunktkataloge meldeten für den fest gebundenen Sol-Endpunkt `azure` Status−5 und0% Verfügbarkeit in den letzten5/30Minuten. `azure/eu` war dagegen im ZDR-Katalog mit Status0 und100% verfügbar. Luna auf `azure` war ebenfalls verfügbar; betroffen ist diese konkrete Sol-Route. Die EU-Tokenpreise liegen10% über den bisherigen Sol-Preisobergrenzen. Eine reine OpenAI-Route war in der gelesenen ZDR-Liste nicht für diese Konstellation enthalten; sie wurde nicht als Ersatz aktiviert.

Der Betrieb wurde nicht stillschweigend umgeschaltet. Ein konkreter Freigabevorschlag umfasst ausschließlich Sol auf Azure/EU, gleiche Denkstufe, gleiche8000Ausgabetokens und0,25USD Reservierung je Auftrag, drei feste künstliche Funktionstests und genau eine weitere Vorbereitung aus den bereits bestätigten Quellen. Zusätzliche Gesamtkosten höchstens1USD. Diese zusätzliche Freigabe steht noch aus. Historische Fehler und unbekannte Kosten bleiben erhalten. Eine erfolgreiche neue Runde oder sichtbare Pushzustellung ist nicht belegt.

## Umsetzung

`graphic_table_transport.py` zählt die tatsächlich erreichbaren Objekt- **und Arraycontainer**, löst lokale `$ref` auf und zählt Alternativen nicht als zusätzliche Datenebene. Nur zu tiefe neue OpenRouter-Einzelrunden erhalten `graphic-table-1`:

- Vollständige Grafikblöcke stehen in einer begrenzten anfragebezogenen `graphic_catalog`-Liste auf oberster Ebene.
- `presentation.blocks` enthält stattdessen eindeutige lokale Grafikkennungen. Jeder Eintrag ist genau einmal definiert und verwendet.
- Das native Ausgabeschema bindet weiterhin den vollständigen Grafikvertrag. Keine freien JSON-Strings, kein Modellcode oder zusätzliche Anbieteranfrage.
- Die Dekodierung stellt den ursprünglichen Block an exakt derselben Stelle wieder her, vor der bisherigen Bruch-, Quellen-, Referenz-, Fach-, Szenen- und Offenlegungsprüfung. Unbekannte, doppelte, unbenutzte und inline statt referenziert gelieferte Blöcke werden verworfen.
- Die ursprüngliche Anfrage wird dadurch von13 auf9 Container abgeflacht. Bereits flache spezialisierte Grafikverträge bleiben unverändert. Kanonisch gespeicherte Aufgaben und Flutter-Renderer verwenden weiterhin dieselbe Struktur.
- Eine lokal nicht sicher abflachbare Struktur bricht vor dem Anbieteraufruf mit einem nachvollziehbaren Fehler ab. Keine automatische Wiederholung oder Quotenänderung.

HTTP200- und sonstige Anbieterfehler behalten künftig ausschließlich fest erlaubte Kategorien und numerische Fehlercodes. Ungefilterte Fehlermeldungen, Prompt-Echos, Rohmetadaten und Fotos werden nicht gespeichert. Abrechnungsbelege erhalten den Hash des tatsächlichen Ausgabeschemas und gegebenenfalls die Transportversion. Unbekannte Kosten bleiben konservativ reserviert.

## Prüfung und Betrieb

Die lokalen künstlichen Fälle prüfen sämtliche vorhandenen Fachprofile mit und ohne Laboroption, exakte Szenen-Rundreisen, fehlerhafte Kennungen, vollständige Phasen, Quellen-/Aufdeckstufen und die tatsächliche HTTP-Adapterkette. Modellantworten in diesen Tests sind kontrollierte Fixtures, kein echter Erzeugungsbeleg. Die konkrete Produktionsanfrage wurde separat ohne externe Verarbeitung und mit gesperrten Datenbankschreibzugriffen vor/nach der Änderung rekonstruiert.

Auslieferung, vollständige Testergebnisse und eine gegebenenfalls regulär reservierte einmalige Produktionsreparatur werden in STATUS.md/SOURCES.md getrennt belegt. Historische Fehler und Verbrauch werden nicht zurückgesetzt. Rückweg ist Release151 mit den unmittelbar vor Auslieferung gesicherten unveränderten Betriebseinstellungen; neue Antworten/Runden nicht durch Datenbankrestore verlieren.

Quellen: [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [OpenRouter Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs), geprüft28.10.2026. Die Modell-/Providerroute, Reasoningstufe und Kostenobergrenzen bleiben unverändert.

Eine ausdrücklich und normal reservierte Reparatur verweist mit `repairs_failed_job_id` auf den alten Fehlerauftrag. Dessen Status und Abrechnung bleiben unverändert. Die berechtigte Statusabfrage liefert ausschließlich eine gleichartige Ersatzvorbereitung desselben Kindes. Die Oberfläche liest diese bestehende Vorbereitung beim alten Link nach; Öffnen, Neuladen und Warten erzeugen weiterhin keinen neuen Auftrag. Es gibt daraus keinen öffentlichen Operatorzugang oder automatischen Anbieterretry.
