# Kompakte Paketübertragung

`package_transport.py` ergänzt ab `package-wire-2` eine private Projektion für
den vorhandenen Paketauftrag. Worker, Reservierung, Modell, Ausgabelimit,
Kostenprojektion und vollständige kanonische Nachvalidierung bleiben bestehen.
Es gibt keinen weiteren Anbieteraufruf oder automatischen Fallback.

## Ursache und Vertrag

Ein größerer bestätigter Seitenbestand konnte vor dem Versand scheitern, obwohl
das Kinderbudget unbegrenzt war: Die separate konservative Startprüfung zählt
auch Regeln, Schema und Metadaten zur vorhandenen Auftragsreservierung. Derselbe
Quelltext war mehrfach enthalten; wiederholte Schemateile und Belegmetadaten
vergrößerten den Transport zusätzlich. Ein Kinderbudget ist deshalb nicht mit
der technischen Grenze eines einzelnen Auftrags gleichzusetzen.

Die Projektion erhält jeden ausgewählten vollständigen `materials[].content`.
Identische Visualquellen desselben Fachs, derselben Gruppe und desselben Themas
dürfen darauf verweisen. Belegauszüge werden nur nach Prüfung von Material-ID,
Revision, Fach, Gruppe und exaktem Quelltext durch Unicode-Teilbereichsverweise
ersetzt. Kuratierte Zusatzregeln benötigen zusätzlich gleiche Referenzkennung,
Version und Digest; sie werden niemals als fotografierter Stoff ausgegeben.

Gleichförmige Eingabelisten können als erklärte `columns`/`rows`-Tabellen
übertragen werden. Alle Werte einschließlich Nullwerten, Nullen, leeren Listen
und vorhandenen Lernnachweisen bleiben erhalten. Fremde Verweise werden vorher
entfernt; nicht exakt passende oder heterogene Daten bleiben im Vollformat.

Das finale Ausgabeschema faktorisiert nur identische Schemaknoten und ansonsten
identische ID-Alternativen. Es behält die bestehenden `$defs`/`$ref`- und
`anyOf`-Mechanismen. Alle privaten Antwort-, Quellen-, Offenlegungs- und
Darstellungsprüfungen arbeiten weiterhin am kanonischen Vertrag. OpenAI behält
Choice-Antworttexte, OpenRouter/Codex ihre bestehenden Indexschemata. Kompakte
Transportanweisungen verlangen weiterhin altersgerechte deutsche Ausgabe.

## Bewusster Reparaturstart

Ein alter Paketfehler darf mit derselben Konfigurationsrevision genau über den
normalen ausdrücklichen Startweg erneut vorbereitet werden, wenn die gespeicherten
Belege eindeutig `failed_not_sent`, `cancelled`, null Kosten und null Ein-/
Ausgabetokens sowie `pre_dispatch=true` nachweisen. Die alte vollständige
Kostenprojektion muss sich aus der gespeicherten Route exakt nachrechnen lassen;
Quellen- und Tagesrevision müssen weiterhin stimmen. Unbekannte Abrechnung,
gesendete Anfragen und Fehler der neuen Transportrevision bleiben gesperrt.

Der bestehende autorisierte POST unter Kindersperre und mit Idempotenzschlüssel
protokolliert `school_day.package_transport_repair`. Alte Fehler, Verbrauch und
Versuchshistorie werden nicht gelöscht. GET, Neuladen und Statusabfragen starten
weder Reparatur noch KI.

## Prüfgrenzen

Ein privater, rein lesender RAM-Vergleich mit HTTP-Sperre ergab für denselben
aktuellen kanonischen Workerpayload 131741 statt 50569 Transportbytes und
311674 statt 149330 Mikro-USD konservative Projektion. Die Reservierung blieb
150000 Mikro-USD. Alle 23 bestätigten Quellen blieben gebunden; der unveränderte
vorhandene Plan wählte für diese erste Portion 16 Seiten in zwei Gruppen.
Die ausgewählten 7929 UTF-8-Quellbytes blieben vollständig erhalten.

Der Abstand zur Startgrenze beträgt in diesem konkreten Fall nur 335 Bytes.
Größere spätere Anfragen können weiterhin abgelehnt werden. Die Rechnung ist
kein tatsächlicher Anbieterpreis, kein garantiertes Rechnungslimit und kein
Modellqualitätsbeleg. Echte Rechnungen werden separat anhand der vorhandenen
OpenRouter-Belege erfasst. Ein RAM-Vergleich ersetzt weder die Live-Erzeugung
noch die Prüfung ihrer fachlichen Ausgabe.
