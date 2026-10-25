# Persistente Lernpaketteile (ab 1.36.1+113)

Ein bestätigter Schultag kann mehr Stoff enthalten, als in eine vollständige
KI-Antwort passt. Der höhere Sol-Ausgaberahmen allein löste den konkreten Fehler
nicht: Auch der separat genehmigte Versuch mit 8000 Tokens endete mit `length`.
Die tatsächliche Generationabrechnung betrug 0,107296 USD; keine Teilaufgaben
wurden übernommen. Rohantworten oder private Hefttexte gehören nicht hierher.

## Verarbeitung

`package_partitions.build_plan` verteilt die bestehenden ausgewählten Fachgruppen
auf stabile Teile. Ziel sind höchstens drei vollständige Seiten und 6000 Zeichen
je Teil. Eine größere einzelne Seite bleibt bis zur bestehenden Grenze von
24000 Zeichen ungekürzt in einem eigenen Teil. Ausschlüsse aus der Quellenprüfung
bleiben erhalten; kein Modell ersetzt oder erfindet fehlende Heftinhalte.

Ein bewusster `POST /school-days/{id}/prepare` speichert die Absicht. Der bestehende
`school_preparation`-Coordinator reserviert anschließend genau einen normalen
`package`-Job je noch fehlendem Teil, jeweils in einer eigenen Transaktion.
Jeder Teil enthält ein Fach und genau zwei Aufgaben. Der bestehende Einstieg ist
nur im ersten Teil eines Fachs aktiv, sofern der ursprüngliche Client ihn
unterstützt. Ein weiterer Upload erzeugt keine Lernnachweise.

Alle Teile binden den gesamten Quellenstand, die Elternplanung, Konfiguration,
Familie und Sitzung. An den Anbieter gelangen jeweils nur die Quellen des
aktuellen Teils. `package_part_output` begrenzt neue Prosa, Grafikschritte und
Szenen, ohne Quellen, Antworten oder bereits erzeugte Antworten abzuschneiden.
Die vorhandenen Quellen-, Mathematik-, Auswahlindex-, Fach-, Referenz-, Parameter-
und Offenlegungsprüfungen laufen weiterhin. Animationen benötigen bei ihrer
Auswahl zwei fachlich unterschiedliche belegte Zustände.

## Speicherung und Wiederaufnahme

Fertige, vollständig geprüfte Ergebnisse werden mit ihrem Darstellungskontext
privat in `SchoolDay.preparation.package_outputs` gespeichert. Sie sind an
Plan-, Quellen-, Job-, Output- und Kontextbelege gebunden. Öffentliche Tages- und
Jobantworten enthalten daraus ausschließlich Zähler und Status, keine Lösungen.
Ein Neuladen, GET oder erneuter identischer POST startet keine weitere KI.

Nach einem Fehler stoppt die Verarbeitung. Ein ausdrücklicher Retry verarbeitet
den fehlenden Teil; erfolgreiche Teile bleiben erhalten. Höchstens zwei
tatsächliche Versuche je Teil gelten weiterhin, bekannte kostenlose
Nichtversandfehler werden gesondert gezählt. Bezahlte Fehler und unbekannte Kosten
bleiben erhalten. Es gibt keine automatische Anbieterwiederholung.

Erst wenn alle erforderlichen Teile fertig sind, veröffentlicht
`school_day.save_package_parts` sie atomar als Lernrunden einer gemeinsamen
Paketversion und eines Lernpfads. Quellenlinks, Grafiken, Referenzversionen,
Einstieg und Katalogzuordnungen bleiben erhalten. Alte Runden und Antworten
werden nicht überschrieben. Danach entfernt derselbe Commit die privaten
Zwischenkopien, damit spätere Rundenlöschung keine zweite Antwortkopie hinterlässt.
Quellenlöschung beziehungsweise ungültige Quellenstände entfernen die betreffenden
privaten Zwischenstände ebenfalls.

Kleine neue Pakete mit nur einem Teil und feste synthetische Anbieterproben
behalten ihren vorhandenen Ablauf. Die einmalige Migration eines alten,
bezahlten `length`-Fehlers erfordert eine neue bewusste Abgabe; ein Versionsmarker
und stabile Teilkennungen verhindern eine wiederholbare Rücksetzung alter
Versuchszähler. Für die JSON-Erweiterung ist keine SQL-Migration nötig. Ein alter
Worker versteht diese neuen Zwischenstände trotzdem nicht automatisch.

## Grenzen und Prüfung

Die Betreiberfreigabe erhöht die gemeinsame Sol-Route auf 8000 Tokens und
250000 µUSD Reservierung. Jeder Teil wird regulär reserviert und tatsächlich
abgerechnet; eine Reservierung ist keine garantierte Rechnung. Tages-/Monats-
Kinderbudgets, globale Sperren, Datenschutz und feste Upstreams bleiben wirksam.
Mehrere Teile bedeuten mehrere begrenzte Aufrufe und können insgesamt mehr kosten.

Gezielte künstliche Tests prüfen Teilplanung, private Belege, Anbieterformat,
Worker-Reihenfolge, unterbrochene Verarbeitung, expliziten Retry, atomare
Veröffentlichung, ursprüngliche Lernbelege und die mobile Zähleranzeige.
Diese Mockprüfungen sind kein Beleg für eine erfolgreiche reale KI-Verarbeitung;
Live-Ausgang, Gebühren und Screenshots werden separat nachgewiesen.

## Grafikvertrag (1.36.2+114)

Der reale Mehrteillauf unter 113 speicherte seinen ersten geprüften Teil. Der
zweite Teil endete mit 3391 Ausgabetokens an drei Grafik-Modellprüfstellen,
ausdrücklich nicht am Ausgabelimit. Beide gemeldeten Gebühren sind erhalten:
0,039938 USD beziehungsweise 0,049182 USD. Die ursprünglichen vier Runden
und fünf Antwortversuche blieben erhalten; der erste Teil wurde nicht erneut
erzeugt. Die konkrete verworfene Parameterkombination ist ohne gespeicherte
Rohantwort nicht rückwirkend belegbar.

Eine öffentliche synthetische Prüfung reproduziert dieselben drei Pfade mit
mehreren bisher schemaerlaubten, fachlich ungültigen Kombinationen, etwa einer
Lernszene mit Zahlen-/Einheitenparametern oder fehlenden Szenendaten. Neue
Teilaufträge binden Grafiktypen und ihre Parameter daher bereits im
Anfrageschema über begrenzte vollständige `anyOf`-Zweige. Die kanonischen
Fach-, Quellen- und Darstellungsvalidatoren bleiben unverändert. Fertige gültige
Teilbelege werden weiterverwendet; Konfiguration und Versuchszähler bleiben
erhalten. Geschlossene Diagnosecodes nennen künftig ausschließlich die
Prüfstelle und Fehlerklasse, niemals Anbietertexte, Eingaben oder Antworten.

## Zusammenhängender Erzeugungsvertrag (1.36.3+115)

Ein neu gestarteter realer Teilauftrag unter 114 wurde erneut abgewiesen
(gemeldete Gebühr 0,049308 USD). Die generische Value-/Key-/Index-/Type-Meldung
belegt keine einzelne konkrete Fehlerstelle; die verworfene Rohantwort wurde
nicht gespeichert. Der fertige erste Teil und sämtliche bisherigen Gebühren
bleiben erhalten. Eine reine Erhöhung der Ausgabelänge ist hierfür kein Beleg.

Künstliche Gegenbeispiele zeigen zwei weitere Lücken im Anfrageschema: Eine
gültige Grafik konnte mit einer anderen gültigen Referenz kombiniert werden;
außerdem konnte die Katalogzuordnung das bereits serverseitig festgelegte Fach
weglassen. Neue Teilaufträge binden deshalb Referenz-ID und -Version, Grafiktyp,
gegebenenfalls Rezeptvariante, Fach-/Gruppenquellen und Aufdeckstufe im selben
vollständigen Schritt. Das bekannte Fach bleibt in der Katalogzuordnung fest;
unsichere Themenzuordnungen dürfen weiterhin leer bleiben. Fertige Teilbelege,
Antworten und bestehende Einzelaufträge werden nicht umgeschrieben.

Die Fähigkeitsbeschreibung verwendet tatsächlich erreichbare Darstellungen
des endgültigen Schemas, einschließlich dieser gebundenen Kopien. Sämtliche
nachgelagerten Quellen-, Fach-, Rechen-, Rezept- und Antwortprüfungen bleiben
maßgeblich. Bei einer Ablehnung nennen geschlossene Diagnosedaten zusätzlich
die lokale Prüfphase und bekannte Fehlerklassen. Anbietertexte, Eingaben,
Quellzitate, unbekannte Schlüssel und Tracebacks werden dabei nicht gespeichert.
Die Abrechnung behält ihre originalen Werte. Keine automatische Wiederholung,
keine neue Migration und keine Änderung an Modell, Denkstufe oder Kostengrenzen.

## Vorbereitete quellgebundene Grafiken (1.36.4+116)

Der nächste reale Versuch wurde unter 115 mit `visual/subject_source`
abgewiesen, gemeldete Gebühr 0,050074 USD. Damit ist die fachliche
Quellenprüfung der Grafik eingegrenzt; der bisherige gemeinsame Fehlercode
unterscheidet noch nicht zwischen Zitat, Zahl und Beschriftung. Die konkrete
verworfene Rohantwort bleibt unbekannt. Diese drei Fehlerklassen sind nun
getrennte geschlossene Tags.

Neue geeignete Mathematikteile erhalten vor dem Anbieteraufruf eine begrenzte
Auswahl individuell aus ihren bestätigten Quellen aufgebauter Bruchmodelle
und gegebenenfalls belegter Pfeilfolgen. Originalzitat, Zahlen, Beschriftungen,
Referenzversion, Fachgruppe und Aufdeckstufe werden gemeinsam mit den
bestehenden kanonischen Prüfungen validiert. Ungültige, negative oder nicht
darstellbare Brüche werden nicht gerundet, gekürzt oder passend gemacht.

Die KI wählt im privaten Anfrageschema eine dieser unveränderlichen Kennungen
und erstellt weiterhin die eigentlichen Aufgaben, Hinweise und Antworten.
Der Codec stellt die gewählte Darstellung vor Pydantic und den bisherigen
Fach-/Quellen-/Antwortprüfungen verlustfrei wieder her. Dies ist das vorher
angeforderte Transportformat, keine nachträgliche Reparatur einer verworfenen
Grafik. Fremde Kennungen oder gemischte Quellen/Stufen werden abgewiesen.
Ohne geeignete Kandidaten bleibt der bestehende streng geprüfte Erzeugungsweg
erhalten; es gibt keine erfundene Ersatzdarstellung. Bestehende fertige Teile
und Lernnachweise bleiben unverändert, ebenso Reservierungen und Providerroute.

Die Grafik muss außerdem einen ausdrücklichen Bezug zur einzelnen Frage haben:
ein Bruchmodell verwendet dasselbe Zähler-/Nennerpaar im Frageprompt, eine
vorbereitete Pfeilszene mindestens zwei dort vollständig genannte Objekte.
Wertgleiche andere Bruchdarstellungen und ähnliche Teilwörter ersetzen diesen
Bezug nicht. Einführungen behalten ihren eigenen, quellgebundenen Erklärzweck.
Diese begrenzte Parameterprüfung ist kein allgemeiner semantischer Fachbeweis.

Die rein lesende Prüfung aller sechs tatsächlichen Teile zeigte außerdem eine
unabhängige Vorlagenlücke: Zwei Englischteile hatten nur das Pfeilszenenrezept,
obwohl ihre bestätigten Quellen keine Pfeile enthielten. Die neue unveränderliche
Referenz `language.forms.original_comparison` Version1 verwendet stattdessen
zwei bis vier wortgetreue Originalausdrücke aus demselben bestätigten Beleg.
Mindestens ein vollständiger Ausdruck muss in der zugehörigen Frage stehen.
Die gemeinsame Flutter-Darstellung fokussiert auf Wunsch gleiche Wörter oder
Unterschiede; sie erfindet keine Beispielsätze oder Grammatikurteile und erzeugt
keine Lernbelege. Sie ist für die ausdrücklich genannten Sprachprofile gedacht,
nicht als allgemeiner Ersatz für eine fachliche Grafik.

Neue Sprachteile mit diesem Vergleichsrezept bieten das alte Pfeilszenenrezept
bei fehlenden Quellpfeilen nicht mehr im Anfrageschema an. Seine ursprüngliche
Pfeilprüfung bleibt erhalten. Gespeicherte Referenzen, Antworten und fertige
Teile werden nicht umgeschrieben; die zusätzliche Referenz wird über den
vorhandenen idempotenten Seed eingespielt, ohne SQL-Migration.

## Frage und Grafik gemeinsam anfordern (1.36.5+117)

Der echte Versuch unter 116 wurde in der Phase `prepared_graphics` abgewiesen;
OpenRouter meldete 0,036372 USD. Der bisherige gemeinsame Bindungsfehler sagt
nicht, welche einzelne Bedingung verletzt war. Es gibt keine gespeicherte
Rohantwort, aus der sich das nachträglich beweisen ließe.

Ein künstliches Gegenbeispiel belegt jedoch eine Vertragslücke: Das Schema
band die Grafikparameter, ließ den Frageprompt aber frei. Eine fremde
Bruchfrage war damit noch schemaerlaubt und wurde erst nach dem Aufruf vom
Frageanker abgewiesen. Der neue Vertrag bindet die ganze Frage und ihren
Grafikschritt im selben vollständigen Schemazweig. Das Stringmuster fordert
das genaue, ungekürzte `n/d`-Paar dieser Grafik ausdrücklich im neuen Prompt.
Die übrige Aufgabenstellung, Hinweise und Antworten erstellt weiterhin die KI;
der Server fügt keinen Frageanker nachträglich hinzu und schreibt keine
Antwort um. Der nachgelagerte Parameteranker bleibt verpflichtend.

Vorbereitete Pfeilszenen bleiben für geeignete Einführungen möglich. Für
vorbereitete Mathematikfragen verwendet dieser begrenzte Vertrag die exakt
gekoppelten Bruchmodelle. Bestehende andere Erzeugungswege und gespeicherte
kanonische Darstellungen werden nicht geändert. Sechs feste Fehlerklassen
unterscheiden künftig Struktur, Offenlegung, Kennung, Fachgruppe, Metadaten und
Frageanker, ohne Inhalte zu speichern. Der historische Sammelcode bleibt in
der Diagnoseauswertung lesbar.

Gleiche Grafikbasen teilen sich dabei einen Fragezweig für ihre vier erlaubten
Hinweis-/Lösungsstufen. Quelle, Referenz und Parameter bleiben gekoppelt;
verschiedene Quellen oder wertgleiche andere Bruchdarstellungen werden nicht
zusammengelegt. Das vermeidet vierfach wiederholte Fragefelder, ohne eine
Darstellung oder Hilfestufe zu entfernen.
