# Persistente Lernpaketteile (1.36.1+113)

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
