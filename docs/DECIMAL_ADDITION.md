# Quellengebundene Dezimaladdition

`package_decimal_addition.py` verbindet die vorhandenen Paket-, Etappen- und
Anschlussaufträge mit dem versionierten Rezept `math.decimal.column_sum`, Version 1.
Die KI erhält vor dem Aufruf feste neue Aufgabenkerne und Grafikkennungen. Sie
kann Hinweise formulieren; Zahlen, Lösungen, Zuordnung und Grafik werden nicht
nachträglich passend gemacht.

## Nachweis und Grenzen

Die eigene bestätigte Quelle muss ausdrücklich „Komma unter Komma schreiben“
oder „Kommas untereinander schreiben“ und ein richtiges Additionsbeispiel
enthalten. Der wörtliche Beleg bleibt einschließlich LaTeX-Dezimalkommas erhalten.
Dieses erste Rezept unterstützt positive Summanden mit einer oder zwei
Nachkommastellen, einer Einerstelle und ohne Übertrag. Ein Titel oder eine
beliebige Gleichung allein belegt das Verfahren nicht. Andere Verfahren behalten
ihren bestehenden Weg; sie werden nicht in dieses Rezept umgedeutet.

Die Einführung zeigt das echte Originalbeispiel. Die eigentlichen Aufgaben
verwenden andere Zahlen. Alle Additionspaare aus bestätigten eigenen Materialien
und früheren Aufgaben desselben Kindes werden als Ausschlüsse berücksichtigt;
gespeicherte Kinderantworten werden dafür nicht gelesen. Die neue Runde enthält
verschiedene Operanden und Summen. Eine endliche Auswahl wird bei Erschöpfung
nicht erneut verwendet.

Ganze Summanden wie `2 + 3,7` gehören ebenfalls zu diesem Vertrag. Die frühere
Prüfung ausschließlich geschriebener Dezimalzahlen hätte einen solchen gültigen
Auftrag nach der Modellantwort abgewiesen. Rechnung, Aufgabenprüfung und
Verlaufsschlüssel verwenden jetzt dieselbe Schreibregel.

## Bestehende Lernsteuerung erhalten

Die Paketgruppe, Quellrevisionen, Referenzversion und vorbereitete Grafik gehören
zu derselben Kennung. Feste Vorwissensfragen und ihre eigenen geprüften Grafiken
bleiben erhalten. Auch die bestehenden Einstiegs-IDs bleiben unverändert; sie
werden nicht durch neue `q1`/`q2` ersetzt. Anschlussaufgaben erhalten ihre bereits
geplante Lernziel-ID. Ein fremdes Lernziel wird nicht als Dezimaladdition
umetikettiert. Etappen verwenden die tatsächlich angeforderte Anzahl von 2 bis 5
Aufgaben. Prüfungs- und Hausaufgabenverträge werden nicht überschrieben.

Vor Veröffentlichung wird unter der bestehenden Kind-Sperre erneut geprüft,
ob die Zahlenpaare zwischenzeitlich schon vorbereitet wurden. Quellen-, Sitzungs-,
Familien-, Anbieter- und Kostenprüfungen bleiben erhalten. Ein bloßes Öffnen oder
Bedienen der Grafik erzeugt keinen Antwort- oder Kompetenznachweis.

## Darstellung und Rückmeldung

Flutter zeigt die Zahlen in einer Stellenwerttafel mit ausgerichteten Kommas.
Das Kind kann die Addition von rechts spaltenweise aufdecken, zurückgehen und
zurücksetzen. Es gibt kein Autoplay. Reduzierte Bewegung, Textalternative und
große Schrift werden berücksichtigt. Der Tutor kann die ausgewählte Spalte
als endlichen lokalen Zustand erhalten. Verdeckte Lösungsschritte bleiben
serverseitig geschlossen.

Bei einer passenden falschen Antwort gibt die rechnerische Auswertung einen
Hinweis zur Zehntel- beziehungsweise Stellenwertspalte. Sie behauptet daraus
keine pädagogische Diagnose und verändert weder eine gespeicherte Hauptlösung
noch frühere Versuche. Erneut beziehungsweise mit Hilfe richtige Lösungen und
spätere selbstständige Erstlösungen bleiben unterscheidbar.

## Transport ohne zusätzliche Kostenfreigabe

`package_output_transport.shared_schema` ersetzt identische Schemateile durch
lokale `$defs`/`$ref`. Die kanonische Dekodierung, Quellen, Optionen, Reihenfolge,
Grenzen und Werte ändern sich nicht. Im vorhandenen Acht-Bruch-Test sank der
Schemateil von 57.921 auf 46.762 Bytes. Die konservative Projektion fiel von 268.636
auf 246.318 USD-Mikroeinheiten und liegt damit innerhalb der unveränderten
Reservierung von 250.000. Das sind Messwerte dieses künstlichen Testvertrags,
keine allgemeine Preis- oder Laufzeitzusage.

## Belege vom 30.10.2026

Der isolierte Smartphone-Test mit 390×844 Pixeln verwendete ausschließlich zwei
künstliche Heftfotos, normale Fotoauswahl, Zuschnitt, OCR, ausdrückliche
Quellenbestätigung und reguläre Reservierungen. Nach den gefundenen Fehlern
wurden die Vorbereitung und eine zielgebundene Anschlussrunde mit echten
Anbieterantworten abgeschlossen. Die erste Runde enthielt absichtlich falsche
Antworten und Hilfe; die Anschlussrunde wurde ohne geöffnete Erklärung im
Erstversuch gelöst. Die Oberfläche zeigte korrekt zwei unterstützte/erneute und
anschließend zwei selbstständige Lösungen. Alte Fehler und Kosten wurden nicht
entfernt. Für den neuen Testtag wurde genau ein lokaler Reparaturversuch
protokolliert; weitere Wiederholungskontingente wurden nicht zurückgesetzt.

Lokale Browserbelege liegen außerhalb von Git unter
`artifacts/monthly-qa-20261030/70-dezimal-stellenwert-390.png` bis
`74-dezimal-fertigmeldung-390.png`. Insbesondere Bild72 zeigt die neue konkrete
Rückmeldung, Bild73 die selbstständig gelöste Anschlussrunde. Die späteren
Quellergänzungen sind ein zusätzlicher Regressionstest und ersetzen keine
früher fehlgeschlagenen Monatstage.

Der vollständige 30-Tage-Alltagstest ist weiterhin offen. Diese Prüfung ist
keine Abnahme aller Fächer, aller Handschriften oder eines Android-Geräts.

## Betrieb und Rückweg

Es ist keine SQL-Migration nötig; das neue Referenzrezept wird idempotent ergänzt.
Bestehende Quellen und Antworten werden nicht nachträglich umgeschrieben. Vor
neuen veröffentlichten Dezimalrunden ist der vorherige Release der direkte
Rückweg. Nach Veröffentlichung solcher Runden muss ein Rückbau den Leser für
`decimal_sum` erhalten; der alte Backendstand kennt diesen neuen Typ nicht.
Bei einem Generatorproblem zunächst den vorhandenen KI-Notfallstopp verwenden
und einen kompatiblen Korrekturbuild ausliefern, keine Lernnachweise löschen.
