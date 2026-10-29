# Paket-Ausgabe: package-output-1

Der Paketauftrag behält seine vorhandenen 4000 Ausgabetokens, `medium`, Route,
Reservierung, Quellen, Fragezahlen und Prüfungen. Es gibt keinen zusätzlichen
Anbieteraufruf, automatischen Retry oder JSON-Reparaturversuch.

## Beleg und Umfang

Für den früheren realen Reparaturauftrag belegte der getrennte Generationabruf
`finish_reason=length`, native 4000 Tokens einschließlich 1552 Reasoningtokens.
Damit war dieser einzelne Output abgeschnitten. Die bereits veröffentlichte
Eingabeverdichtung `package-wire-2` löste dieses Ausgabeproblem nicht.
Es wurden für diesen Fix keine privaten Auftragsinhalte gelesen oder neue reale
Modellaufrufe durchgeführt.

`package-output-1` ist ausschließlich eine Schreibweise für neue
`request_provider(..., 'package', ...)`-Antworten. Gespeicherte Einheiten,
Antworten, private Grafikzitate, öffentliche Projektionen und Flutterverträge
bleiben kanonisch. Alte begonnene Runden werden nicht neu erzeugt oder geändert.

## Datenkette

1. Die bestehenden Fach-, Mathe-, Entry-, Antwort- und Grafikbinder erzeugen das
   vollständige endgültige private Schema.
2. `package_transport.schema_projection` faktorisiert dieses Schema verlustfrei.
3. `package_output_transport.bind` erzeugt pro Request injektive kurze
   Propertynamen und einen gebundenen Decoderplan. Enumwerte, Strings und
   Listenreihenfolgen werden nicht umbenannt.
4. Ein Feld darf nur dann entfallen, wenn **jedes** Schemasvorkommen dieses
   Propertynamens dasselbe explizite skalare `const`, einzelne `enum` oder
   ausschließlich `null` erlaubt und es überall erforderlich ist. Es werden
   weder Pydanticdefaults noch Grafikparameter oder Antwortwerte erraten.
   Diskriminatoren `id`, `type`, `kind`, `group_id`, `subject` bleiben vorhanden.
5. Der Adapter sendet tatsächlich das verkürzte Schema und die Aliaslegende.
   Die Kostenprüfung zählt exakt diese minifizierten Schema-/Promptbytes.
6. Nach vollständiger Providerantwort werden Propertynamen und bewiesene
   Konstanten rückübersetzt. Erst danach laufen unverändert Index-Decodierung,
   kanonische Pydantic-, Paketumfangs-, Fachantwort-, Match-/Grouped-, Entry-,
   Quellen-, Referenz-, Parameter- und Offenlegungsprüfungen.

Unbekannte Felder/Referenzen, mehrdeutige Rekonstruktionen, fehlende Pflichtfelder,
mitgesendete ausgelassene Konstanten und zyklische/unsupported Schemaformen
scheitern geschlossen. Ein `length`-Ergebnis wird auch bei zufällig gültiger
JSON-Klammerung verworfen. Kein Teilpaket wird übernommen.

## Bewusste Grenzen

Der Codec erzeugt keine fachlichen Aussagen und verbessert keine Antwortschlüssel.
Er verwendet keine Stringtabelle, Kompression, Modellprogramme, neuen Szenen-Slots
oder nachträgliche Textkürzung. Nullfelder werden nicht nur aufgrund eines
vermuteten Grafiktyps weggelassen. Bestehende lange Erklärungen und komplexe
Szenen bleiben möglich; ein Paket kann weiterhin am unveränderten Tokenlimit
scheitern. Outputbytes sind keine gemessenen Modelltokens oder Qualitätsabnahme.

Die ersten vollständig validierten künstlichen Größenfälle (je sechs Fragen):

| Fächer | Frage-Erklärschritte | Kanonische UTF8-JSON-Bytes | Wirebytes |
|---|---:|---:|---:|
| 2 | 1 | 13989 | 9472 |
| 3 | 1 | 15915 | 10854 |
| 2 | 2 | 22842 | 15367 |
| 3 | 2 | 24927 | 16908 |

Dies sind minifizierte Größen derselben vollständig rückführbaren Fixtures,
mit echten Frage-/Quellen-/Grafikprüfungen vor und nach dem Roundtrip. Wiederholte
künstliche Fragen dienen nur der Größen-/Formatprüfung, nicht als pädagogischer
Qualitätsnachweis. Die verbliebene Last liegt weiter in Szeneobjekten/-phasen,
wörtlichen Belegen, Prompts/Hinweisen und Erklärungstexten. Der konkrete reale
Paketauftrag war zum Zeitpunkt dieser Größenprüfung mit diesem Codec noch nicht
gesendet oder als erfolgreich belegt. Finale Gatezahlen stehen im separaten
Integrationsbericht.

## Spätere Betriebsprüfung vom 25.10.2026

Ein neuer realer Paketversuch unter Release 112 erreichte erneut die
Ausgabegrenze. Die geschlossene Auswertung der gespeicherten Fehlermeldung
belegt `length`; sie belegt keinen Decoder-, Quellen- oder Grafikfehler.
Es wurden keine Teilaufgaben übernommen. Die tatsächliche abgerechnete Gebühr
dieses fehlgeschlagenen Versuchs beträgt 0,067296 USD.

Die aktive Basiskonfiguration erlaubte bereits 8000 Ausgabetokens, während die
ausgewählte Sol-Route weiterhin auf 4000 Tokens und 150000 µUSD Reservierung
begrenzt war. `select_route` verwendet jeweils das Minimum der beiden Ebenen.
Eine allgemeine Anhebung allein an der Basis hätte diesen Engpass daher nicht
beseitigt. Der Betreiber hat anschließend ausdrücklich eine Anpassung des
Budgets beauftragt. Die gezielte Betriebsänderung und ihr tatsächliches Ergebnis
werden im Betriebsbeleg außerhalb von Git festgehalten; private Quellen,
Auftragskennungen und Schlüssel gehören nicht in diesen Bericht.

Die zusätzlichen künstlichen Regressionstests in
`backend/tests/test_package_output_budget.py` prüfen beide Grenzebenen, den
unveränderten Luna-Pfad, tatsächlich gesendete 8000 Tokens bei `medium`, sechs
vollständige Aufgaben mit Grafikschritten sowie die weiter geltende Ablehnung
und Abrechnung einer abgeschnittenen Antwort ohne automatischen zweiten Aufruf.
Diese Tests ersetzen keinen erfolgreichen realen Paketauftrag.

Die Ausgabegrenze umfasst auch nicht sichtbare Tokens. Sie ist keine Zusage
über die verfügbare sichtbare JSON-Länge oder einen Rechnungsbetrag:
[OpenAI: Counting tokens](https://developers.openai.com/api/docs/guides/token-counting),
am 25.10.2026 gelesen.


Auch der anschließend ausdrücklich genehmigte reale Versuch mit 8000 Tokens
endete am 25.10.2026 mit `length` (bestätigte Generationgebühr: 0,107296 USD).
Der höhere Rahmen allein reicht damit für diesen Paketvertrag nicht aus.
Release 1.36.1+113 ergänzt deshalb persistente begrenzte Teilaufträge mit
abschließender atomarer Veröffentlichung, siehe [PACKAGE_PARTS.md](PACKAGE_PARTS.md).

## Zusätzliche Begrenzung fester Ausgabelisten

`package-fixed-arrays-1` ergänzt den bestehenden Codec für neu angeforderte
Pakete. Ausschließlich Listen, für die das konkrete Schema bereits dieselbe
positive Mindest- und Höchstzahl von höchstens acht Einträgen vorgibt, werden
als geschlossenes Objekt mit genau dieser Zahl verpflichtender Felder
übertragen. Die Rückübersetzung erhält Reihenfolge und Werte; fehlende oder
zusätzliche Felder werden abgewiesen. Variable Listen, gespeicherte Pakete und
alle nachfolgenden Quellen-, Grafik- und Aufgabenprüfungen bleiben unverändert.
So hängt die Anzahl dieser Felder nicht nur von `minItems`/`maxItems` ab.

Microsoft dokumentiert für Azure Structured Outputs Einschränkungen bei
bestimmten Schema-Schlüsselwörtern, darunter Listen- und Textlängen; die
allgemeine Dokumentation ist keine Aussage über das Verhalten jedes einzelnen
OpenRouter-Endpunkts. Ein künstlicher Grenztest mit `maxItems=1` und
`maxLength=4` am tatsächlich gewählten Sol/Azure-EU-Endpunkt lieferte einen
Eintrag mit vier Zeichen. Das ist ein Einzeltest, kein Beweis für jede
Kombination. [Microsoft: Structured Outputs](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/structured-outputs)

Mit ausschließlich künstlichem Stoff wurden echte reservierte Paketaufrufe
über `openai/gpt-6.1-sol` und `azure/eu` ausgeführt. Der heutige Stand vor der
Feldbegrenzung erzeugte drei Biologiepakete sowie je ein Mathematik- und
Deutschpaket vollständig. Der neue Transport erzeugte je ein Paket in den drei
Fächern vollständig und bestand die bestehenden Grafik- und Inhaltsprüfungen.
Ein Vergleich mit Version 1.38.6 lieferte eine vollständige, aber wegen nicht
belegter Grafikbeschriftungen verworfene Antwort. Er reproduzierte die beiden
historischen `length`-Abbrüche nicht. Die zehn echten künstlichen Aufrufe
einschließlich Vergleich und Schema-Grenztest kosteten laut Anbieter zusammen
0,2495394 USD; keine echten Kinderinhalte wurden verwendet.

Feste Felder vermeiden unbeschränkt anwachsende Listen an diesen Stellen,
garantieren aber keine vollständige Antwort bei jedem Modellaufruf: Andere
Listen, Texte, Reasoning und Anbieterfehler bleiben begrenzt oder werden
weiterhin wie bisher geprüft. Ein `length`-Ergebnis wird unverändert verworfen;
es gibt keinen stillen Modellwechsel oder automatischen erneuten Aufruf.
