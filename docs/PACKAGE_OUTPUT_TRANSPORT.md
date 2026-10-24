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
Paketauftrag wurde mit diesem Codec noch nicht gesendet oder als erfolgreich
belegt. Finale Gatezahlen stehen im separaten Integrationsbericht.
