# Fachliche Darstellung in Aufgaben und Hilfen

Ausbauauftrag20.10.2026, Zielversion1.12.0+56. Gemeint ist die Darstellung
**innerhalb der App**: Aufgaben, Auswahloptionen, Hinweise, Erklärungen,
Antwortfeedback und Heftfragen. Eingaben bleiben gewöhnliche fotografierte,
auch handschriftliche Schulhefter. Gedruckte KI-Testseiten sind kein neues
Eingabeformat, keine Produktbilder und keine Voraussetzung für diese Funktionen.

## Gemeinsame Darstellung

`MathText`/`FormulaNotation` setzen Standard-TeX lokal mit dem exakt fixierten
flutter_math_fork0.7.4. Brüche, Wurzeln, Potenzen, Indizes, griechische Zeichen,
Summen, Integrale, Grenzwerte, Vektoren, Matrizen und chemische Ladungen erscheinen
als gesetzte Formeln. Auch vorhandene numerische Schreibweisen1/2,¼,\\frac{1}{2}
bleiben unterstützt. Einzelne ältere vollständige TeX-Zeilen werden konservativ
erkannt; normaler Fließtext, Datumsangaben und URLs werden nicht umgedeutet.

Formeln mindestens18logische Pixel; Bruchzähler und große Operatoren mit mehr
Platz statt verkleinerter Textstilbrüche. Große Schrift wird übernommen, breite
Ausdrücke können horizontal gelesen werden. Maximal1800Zeichen je Formel,
40Formelsegmente,24Klammerebenen,100Parserexpansionen. Keine externen Fonts,
HTML/Webviews, Bilder, Makrodefinitionen oder Netzwerkbefehle. Nicht unterstützte
Notation bleibt als Text sichtbar. Dies ist keine vollständige mathematische
Sprachausgabe oder formale Prüfung beliebiger Mathematikantworten.

`LearningContent` erhält Absätze, Überschriften, Tabellen mit leeren Zellen,
Codeeinrückungen und zusammenhängende Formel-/Codeblöcke auch in Aufgaben und
Hilfen. Darstellung verändert keine gespeicherten Quellen, Lösungen oder
Bewertungen. Einheiten-/Antwort-/Hilfenachweise bleiben die bestehenden Belege.

## Fachzeichnungen

Die bisherigen36endlichen Fachbausteine bleiben erhalten. Hinzu kommen zehn
begrenzte Familien mit serverseitiger Prüfung in `science_graphics.py`:

| Familie | Tatsächlicher Umfang und Bindung |
| --- | --- |
| Funktionsgraph | Explizites Polynom bis Grad2; Koeffizienten aus der vollständigen belegten Gleichung prüfen, keine frei ausführbare Formel |
| Standardkurve | Genau sin(x),cos(x),e^x,ln(x),sqrt(x),1/x,x³,\|x\|; endlicher Ausschnitt, Definitionsbereich und Unterbrechung bei1/x beachten |
| Datenplot | Zwei bis acht exakte Zahlenpaare oder zwei ausdrücklich zugeordnete Tabellenspalten; Streupunkte oder Linienzug bei steigenden x, keine erfundene Regression |
| Zellmodell | Vereinfachte Pflanzen-/Tierzelle mit festen, belegten Beschriftungspositionen |
| Bindungsschema | H–O–H, O=C=O, Methan und Ethanol; Strukturbeleg erforderlich, Summenformel allein genügt nicht; keine behauptete Raumgeometrie |
| Logiktafel | UND/ODER/NICHT, deterministisch; vollständige abgeleitete Tabelle nur nach geöffnetem Hinweis oder als Lösung |
| Widerstandsnetz | Zwei Widerstände ausdrücklich in Reihe oder parallel, gleiche Knoten im Parallelmodell |
| Technische Skizze | Rechteckige Platte, belegte Maße und mittige kleinere Bohrung; mm/cm, Maßlinien, Hinweis auf schematische Darstellung |
| Prozessgraph | Zwei bis acht belegte Knoten, ausschließlich wörtlich belegte Pfeile, zusammenhängend und ohne Kreis |
| Prozesskreislauf | Ausdrücklich geschlossene belegte Reihenfolge, einschließlich letzter→erster Kante |

Positionen, Pfade und Kurvenpunkte berechnet die App lokal. Messwerte sind
fachliche Daten, keine vom Modell frei gewählten Bildkoordinaten. Es gibt keine
kostenpflichtige Bildgenerierung für Lernaufgaben. Die Regeln für neue Familien
werden nach den ausgewählten Fachprofilen begrenzt, ebenso der private Grafiktyp-Enum; reine Rückblicke erhalten
keinen Grafikauftrag. Die bestehenden Modelle, Routen, Reservierungen und Limits
bleiben maßgeblich, kein zusätzlicher KI-Aufruf für Darstellung oder GETs.

Quellenbelege und Freigabestufen bleiben verpflichtend: given vor der Antwort,
hint1/2/3 erst nach geöffneter Hilfe, solution im Ergebnis. Ein konkreter Fehler
im Aufgabenraum wurde behoben: Die Hinweisantwort muss die Grafik in der
führenden lokalen Einheit aktualisieren; `currentQuestion` ist nur eine Kopie.
Ein erneuter Widget-Aufbau darf die gerade freigegebene Grafik nicht verlieren.

## Prüfraster Klasse1bis13

Die Reihenfolge ist ein Darstellungs-Prüfraster, kein für alle Länder/Schulformen
gleicher Lehrplan und keine automatische Stoffzuweisung aus einer Klassenstufe.
Naturwissenschaftliche Grundlagen der ersten Schuljahre gehören häufig zum
Sachunterricht. Technik/Informatik beginnen je nach Schulform unterschiedlich.
Quelle und ausdrücklich bekannte Stufenart bleiben für echte Aufgaben bindend.

| Prüfstufe | Mathematik und Notation | Naturwissenschaftliche Formen | Technik/Informatik und weitere Formen |
| --- | --- | --- | --- |
| 1 | Mengen, Zahlzeichen, +/−, Vergleich, Grundformen | Körper-/Pflanzenteile, Sinne | Reihenfolge, Bild-/Formenmuster |
| 2 | Stellenwerte, Zahlenstrahl, Länge/Uhr/Geld | Jahreszeiten, Beobachtungstabellen | einfache Anleitungen und Zuordnung |
| 3 | schriftliche Verfahren, Multiplikation/Division, Größen | Wasserzustände, Kreisläufe | Abläufe, einfache technische Funktionen |
| 4 | Flächen, Bruchanteile, Spiegelung, Daten | Lebensräume, Nahrungspfeile | Tabellen, Symbole, einfache Regeln |
| 5 | natürliche Zahlen, Maße, Geometrie, Diagramme | Zellen, Stoffe/Teilchen, Bewegung | Maßskizzen, binäre Stellenwerte |
| 6 | Brüche/Dezimalzahlen, Verhältnis, Winkel | Atmung, Pflanze, Licht/Schaltungen | Flussbilder, einfache Programme |
| 7 | negative Zahlen, Prozent, Terme/Gleichungen | Reaktionsgleichung, Energie, Organmodelle | Kräfte, Hebel, Wahrheitstafeln |
| 8 | lineare Funktionen, Gleichungssysteme, Wahrscheinlichkeit | Atom-/Ionenzeichen, Strom/Spannung, Vererbung | Reihen-/Parallelverbindung, Algorithmen |
| 9 | Potenzen/Wurzeln, quadratische Funktionen, Pythagoras | Molekülstruktur, Kräfte/Bewegung, Ökosystem | Technikmaße, Daten-/Beziehungsdiagramme |
| 10 | Trigonometrie, Exponential-/Logarithmusnotation, Stochastik | Säure/Base, Wellen, Evolution/Regelung | Regelkreis, Automaten, Komplexitätsnotation |
| 11 | Grenzwerte, Ableitung, Vektoren/Matrizen | Felder, Organik, DNA/Proteinbiosynthese | Funktions-/Datenmodelle, Code und Logik |
| 12 | Integral, analytische Geometrie, Verteilungen | Gleichgewicht, Elektrochemie, Genetik | Zustände, Übertragungssysteme, Datenmodelle |
| 13 | verknüpfte Analysis/Geometrie/Stochastik, Summen | Quanten-/Kernnotation, Biochemie/Populationen | kombinierte technische/informatische Darstellungen |

Fächerübergreifend außerdem Sprach-/Formtabellen, Satzglieder, Gedichtzeilen,
Zeitachsen, Karten/Legenden, Noten/Tasten, Farbmodelle, Bildaufbau, Argumente,
Budgettabellen, Lernkarten und Mindmaps. Die vorhandenen48Fachfixtures umfassen
alle24Katalogfächer. Neue Prozessdarstellungen sind für diese Fächer nutzbar,
wenn die Beziehungen ausdrücklich belegt sind. Deutsch/DaZ und
Sachunterricht/Biologie bleiben getrennte Fachidentitäten.

## Heftfotos und Grenzen

OCR bleibt ein eigener wörtlicher Auftrag ohne Aufgaben oder Lernhistorie.
Zeilen, Fehler und Unsicherheiten bleiben erhalten. Formeln werden symbolgetreu
notiert, Code auch mit Einrückung in der ersten Zeile. Sichtbare eindeutige
Pfeile können als A→B transkribiert werden; unklare Beziehungen bleiben offen.
Die Quellenbestätigung ist weiterhin eine ausdrückliche Benutzeraktion.

Die optionale Leseansicht kann außerdem eine Zeichnung aus dem privaten
Originalfoto zeigen. `image_region` sind ausschließlich Begrenzungen vorhandener
Pixel, keine generierte Zeichnung. Revisionsgebundener authentifizierter GET,
keine öffentliche Bild-URL/Kopie, no-store und dieselben Familienrechte wie das
Original. Korrigierter Text mit veralteten Blöcken zeigt keine alten Ausschnitte.
Höchstens sechs Vorschauen pro Ansicht, Cache bei Kontowechsel/Dispose leeren.
Originalausschnitte stehen nur in der Quellenansicht und umgehen keine
Offenlegungsstufe einer Aufgabe. Ein unsicherer Ausschnitt ersetzt nie das
vollständige Heftfoto.

Die Rasterprüfung beansprucht weder sämtliche denkbaren Zeichnungen noch alle
Lehrpläne als erfolgreich getestete KI-Ausgabe. Komplexe Anatomie, vollständige
Organik-/Schaltpläne oder andere nicht implementierte Spezialbilder werden
nicht frei erfunden. Bestätigter Originalstoff und lesbare Notation bleiben
verfügbar. Fachliche Unsicherheit und bestehende Antwortprüfungen bleiben bestehen.

## Nachweise

- `testdata/scientific_notation_v1.json`:127künstliche Formelsatzfälle bis zur
  Oberstufe, tatsächlicher Parser/Renderer statt bloßer Zeichenkettenprüfung.
- `testdata/science_graphics_v1.json`:28künstliche Aufgaben-/Hilfefälle für die
  zehn neuen Familien; Schema, Quellenbeleg, Freigabestufe,320/1440px und100/200%.
- Reale Aufgabenraum-Widgets prüfen Formel in Frage, Auswahl und geöffnetem
  Tipp sowie erst dann sichtbare Fachgrafik. Öffnen sendet keine Antwort.
- Native Flutter-Renderer-Screenshots mit echter Schrift; gesonderte lokale
  Web-Galerie verwendet denselben UnitScreen. Lokale Fixtures/Mockantworten sind
  ausdrücklich kein OCR-/Anbietererfolg oder Nachweis einer Lernwirkung.
- Tatsächliche Tests, Release- und Praxisbefunde werden im Abschlussprotokoll
  ergänzt. Bisherige Testkosten/ungeklärte Gebühren bleiben erhalten; Darstellung
  selbst benötigt keine Inferenzkosten.

Abnahme vor Build:867Fluttertests vollständig, nach den letzten Darstellungs-/
Schriftkorrekturen248gezielte Rendererprüfungen mit tatsächlich geladenen
KaTeX-/Roboto-Schriften sowie154Aufgabenraum-/Formelprüfungen.294PostgreSQL-
Integrationsprüfungen und63gezielte Quellen-/Fachschema-Nachprüfungen bestanden
(überschneidende Teilmengen). Ruff und Flutter-Analyse ohne Befund.
Die spätere Nullstelle eines Achsenticks wird relativ zur Achsenspanne
normalisiert; kleine echte Messwerte und vollständige Datenpunktwerte bleiben
erhalten. Zwei veraltete Rückblicktest-Assertions auf ein null-Platzhalterfeld
wurden an den bereits bestehenden OpenRouter-Vertrag ohne dieses Feld angepasst.
