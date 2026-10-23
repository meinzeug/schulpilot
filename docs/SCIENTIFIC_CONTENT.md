# Fachliche Darstellung in Aufgaben und Hilfen

Ausbauauftrag20.10.2026, erster Stand1.12.2+58; Lesekorrekturen auf1.13.0+59. Gemeint ist die Darstellung
**innerhalb der App**: Aufgaben, Auswahloptionen, Hinweise, Erklärungen,
Antwortfeedback und Heftfragen. Eingaben bleiben gewöhnliche fotografierte,
auch handschriftliche Schulhefter. Gedruckte KI-Testseiten sind kein neues
Eingabeformat, keine Produktbilder und keine Voraussetzung für diese Funktionen.

## Individuelle Szenen und Zuordnungen · Zielversion 1.26.0+97

Der ausdrückliche Ausbauauftrag vom 23.10.2026 erlaubt zusätzlich individuell
von der bestehenden KI komponierte Grafiken und Animationen. Die bisherigen
endlichen Fachmodelle und ihre fachlichen Prüfungen bleiben erhalten. Neu ist
`Graphic.kind = scene` innerhalb derselben versionierten `presentation`;
`scene.version = 1` beschreibt eine begrenzte, deklarative Komposition. Die
Freigabe umfasst keine ausführbaren Modellprogramme, beliebigen SVG-/HTML-Code,
freien Koordinaten, externen Assets oder zusätzlichen Bilddienst.

| Bestandteil | Tatsächlicher Szenenvertrag |
| --- | --- |
| Aufbau | `grid`, `row` oder `cycle`; lokale schematische Plätze statt Messkoordinaten |
| Objekte | 1–12 eindeutige IDs; belegte Beschriftungen bis 160 Zeichen; `box`, `circle`, `triangle`, `diamond`; semantische Farbtöne `neutral`, `accent`, `secondary` |
| Schritte | 1–8; jeder platziert alle Objekte genau einmal auf eindeutigen Slots 0–11; Beschreibung bis 500 Zeichen |
| Beziehungen | Bis 24 gerichtete Pfeile je Schritt, optionale Beschriftung bis 80 Zeichen; keine Selbstkante, doppelte gerichtete Kante oder unbekannte Objekt-ID |
| Hervorhebung | Ausschließlich vorhandene, nicht doppelte Objekt-IDs |
| Übergang | 0–800 ms; lokale Animation, keine physikalische Simulation oder fachliche Messung |
| Textalternative | Nichtleere äußere `labels`, höchstens 16 Einträge bis 160 Zeichen; gesamte Szene zusätzlich als lesbare Beschreibung |

Titel, Beschriftungen und Zustandsbeschreibungen benötigen wörtliche Belege.
Jeder Schritt besitzt einen privaten `source_excerpt`; seine Beschreibung muss
im Schrittbeleg enthalten sein. Fachliche Pfeile benötigen eine ausdrücklich
bestätigte Richtung zwischen den vollständigen Begriffen, nicht bloß deren
Vorkommen oder eine erfundene Beziehung im erzeugten Aufgabentext. Layout und
Bewegung sind schematische Erläuterungen. Für Funktionsgleichungen, Messwerte,
Molekülbindungen und Schaltungen bleibt das passende geprüfte Fachmodell
maßgeblich. Die Szenengrammatik ist in allen 24 Fachprofilen freigegeben; dies
ist keine Abnahme sämtlicher Fachinhalte oder Lehrpläne.

Die gesamte Szene mit allen Objekten, Schritten und Alternativtexten gehört zu
genau einer vorhandenen Offenlegungsstufe. Ein Regler öffnet keine spätere Hilfe
oder Lösung. Der Server entfernt sowohl den äußeren Quellenbeleg als auch jeden
Schrittbeleg aus der öffentlichen Projektion. Gegebene Darstellungen dürfen
keine richtige Antwort oder Zuordnung vorwegnehmen; erklärende Szenen einer
Zuordnungsaufgabe öffnen erst über die vorhandenen Hilfen bzw. die Lösung.

Der eigene Flutter-Player startet ausschließlich bewusst. Start/Pause,
Vor/Zurück, Wiederholen und ein kontinuierlicher Schrittregler steuern lokale
Übergänge. Beschreibungen, Beziehungen und Alternativtexte bleiben lesbar.
Reduzierte Bewegung verwendet statische Schritte. Hintergrund, überdeckte Route,
Daten-/Frage-/Konto- oder Sitzungswechsel stoppen den Player. Ohne übergebenen
Kontokontext steht nur statisches schrittweises Lesen zur Verfügung. Abspielen
sendet keine Anfrage, Antwort, Lernzeit oder Fortschrittsmeldung. Die bisherigen
`process_graph`-/`process_cycle`-Diagramme bleiben erhalten; „Schrittweise
ansehen“ hebt auf Wunsch ausschließlich bereits freigegebene Knoten und
Beziehungen lokal hervor, ohne neue Fakten oder Modellanfrage.

Bereits geöffnete Hilfen/Lösungen der Typen `function_graph`, `data_plot` und
`logic_table` erhalten mit gültigem Kontokontext eine lokale „Erkunden“-Ansicht.
Polynommarker verwenden dieselbe Plotgeometrie wie der Graph und berechnen X/Y
innerhalb−4bis4 in0,1-Schritten; sie sind keine Messung. Datenplots wählen nur
vorhandene Originalpaare, ohne Interpolation oder Regression. UND/ODER/NICHT
berechnen ihre endliche Wahrheitstafel und markieren die aktive Zeile. Given-
Blöcke und Ansichten ohne Kontokontext bleiben statisch. Die Ansichten erzeugen
keine eigenen Netzwerk-, Bewertungs-, Fortschritts- oder Zeittakte; die bestehende
Aufgabenraum-Interaktions-/Zeitmessung bleibt bestehen. Kontext-, Routen- und
Lebenszykluswechsel setzen lokale Auswahl und alte Rückrufe außer Kraft.
Auch im Mobilzoom passen diese Bedienelemente in die verfügbare Breite.

Bestehende Zuordnungen erhalten Drag-and-drop mit sichtbaren Antwortkarten,
Zielen und mobilem Randscrollen. Tippen und Tastatur verwenden weiterhin die
vollständige vorhandene Auswahl. Ein Drop aktualisiert nur den Entwurf;
„Antwort prüfen“ bleibt die ausdrückliche Bewertungsaktion. Neue kompakte
OpenRouter-Runden dürfen zwei bis vier eindeutige, gruppenlokal wörtlich als
`links = rechts`, `links: rechts`, `links → rechts`, `links -> rechts` oder
`links | rechts` belegte Paare erzeugen. Bloß benachbarte Begriffe reichen nicht.
`options` bleibt `links|rechts`, `answer` enthält die rechten Werte in linker
Originalreihenfolge mit Semikolon, `accepted` bleibt leer. Die Begriffe enthalten
keine Semikolons; richtige Paarungen dürfen im Prompt nicht bereits stehen.
Dies nutzt bestehende Aufgabenplätze, Anbieterreservierung und Token-/Zeitlimits;
Codex-Pakete behalten ihren bisherigen choice/short-Umfang. Kein zusätzlicher
Dienst, keine neue Generierung durch OCR, Rückblick oder GET.

Der bestehende KI-Erzeugungsauftrag erhält außerdem einen fachgetrennten
Darstellungskatalog mit Lernzweck, tatsächlicher App-Bedienung und den aus dem
endgültigen Schema abgeleiteten Fragearten/Blockgrenzen. Er verwendet dieselben
Profile, erweitert keine Ausgabeformate und behebt die fehlende Fachableitung
normaler Heftaufgaben aus material.subject. Hinweise/Lösungen werden im selben
Auftrag geplant und später nur projiziert. Details:
[AI_RENDER_CAPABILITIES.md](AI_RENDER_CAPABILITIES.md).

Prüfstand dieses Ausbaus:684gezielte Flutterfälle in25Dateien bestanden,
anschließend33überschneidende Fälle nach äquivalenter Null-aware-Lintkorrektur;
Analyse von21betroffenen Dartdateien ohne Befund.488Backendfälle in18Dateien,
Ruff und Diffprüfung grün. Die lokalen geschützten Mockpfade prüfen Szenen und
Zuordnungen; künstliche Rendererfixtures sind keine echte KI-Ausgabe.
Die einmalige echte synthetische Modellprobe wurde wegen ungültiger Struktur
verworfen:0,001436USD,4115Eingabe-/2049Ausgabetokens, normal abgerechnet,
kein Retry. Ohne gespeicherte Rohantwort ist die genaue Ursache unbekannt.
Kein erfolgreicher echter KI-Szenennachweis; spätere strengere Quellenprüfungen
sind offline geprüft. Quellenabgrenzung an Pfeilbegriffen und Materialgrenzen
sowie vorweggenommene gegebene Zuordnungen sind mit Regressionen abgesichert.
Das ist keine vollständige Sicherheits-, Inhalts- oder Lernwirkungsprüfung.
Vertrag, Recherchegrenzen und Rückweg:
[INTERACTIVE_LEARNING_2026_10_23.md](INTERACTIVE_LEARNING_2026_10_23.md),
[RELEASE_97_2026_10_23.md](RELEASE_97_2026_10_23.md).

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

Zusätzliche Nachprüfung57: reine TeX-Abstands-/Klammergrößenbefehle aus den
Vorlesetexten entfernen, Operatoren und Einheiten erhalten. Fachgrafiken verwenden
dieselbe gesprochene Beschreibung im Bild-Alternativtext; gängige
TeX-Steuerzeichen sind dort bereinigt. Dies erweitert die partielle Formelvorlesehilfe, ersetzt
keine vollständige mathematische Sprachausgabe.
Prozess-/Kreislaufbeschreibungen nennen jede tatsächliche Pfeilrichtung auch
sprachlich; die Bildbeschreibung ersetzt eine doppelte vorgelesene sichtbare
Wiederholung. Numerische Datenbelege bleiben unverändert.

Produktiver Praxistest auf56: eine bereits geprüfte künstliche Handschriftseite
im normalen angemeldeten Kinderzugang bewusst erneut gelesen. Alle drei Themen,
Formeln und fünf Zeichnungsbereiche erhalten; Originalausschnitte tatsächlich
geöffnet, Seite ausdrücklich bestätigt. Echte quellengebundene Heft-Hilfe zu
Umfang/Fläche6cm×4cm fachlich richtig mit gesetzten Formeln und Einheiten.
Luna/Revision29: OCR4766Input-/1669Ausgabetokens,0,001312USD;
Tutor3704Input-/387Ausgabetokens,0,000564USD berichtet. Zusammen0,001876USD,
keine neue Lernrunde oder Antwortversuche. Alte Reservierungen/Unklarheiten
erhalten. Nachprüfung57:276gezielte Fluttertests bestanden, Analyse ohne Befund.

Nachprüfung58: Der echte Web-Großschrifttest zeigt eine doppelte Skalierung von
WidgetSpans. Das gepinnte Flutter skaliert das gesamte eingebettete Widget bereits;
innerhalb des Formel-/Bruchwidgets wird deshalb nur der zweite Textskalierungs-
durchgang abgeschaltet. Standalone-Formeln und normaler Text behalten ihre
Systemschriftgröße. Der neue Test misst das tatsächliche globale Höhenverhältnis
für TeX und ältere Brüche: vor dem Fix deutlich über2, danach bei200%genau2.

Abschluss58: 870 Fluttertests vollständig bestanden,277gezielte Nachprüfungen
und Analyse ohne Befund. Auf1.12.2gespeicherte produktive Heft-Hilfe nach Reload
ohne neue KI erneut geöffnet. Release, Hashes, Kosten und Grenzen:
[SCIENTIFIC_QA_2026_10_20.md](SCIENTIFIC_QA_2026_10_20.md).

Weitere Abnahme 59: Formeln in Tabellen ohne intrinsische Breitenmessung,
mehrzeilige Matrizen auch ohne äußere TeX-Klammern, gemischte Blöcke ohne
Leerzeile, Überschriften beim ersten Inhalt, Erklärungsschritte wieder am Anfang.
889 Fluttertests vollständig bestanden; tatsächliche Web-/Menünachprüfung,
Signaturen, Kostenabgrenzung und Rückweg in
[MENU_REVIEW_2026_10_20.md](MENU_REVIEW_2026_10_20.md).

Abschluss der lokalen97-Abnahme:446Backendfälle in18Sammlungen bestanden nach
allen drei strengeren Quellen-/Offenlegungsfixes; keine weiteren Modellaufrufe.
571Flutterfälle plus13Zoom-/Referenzfälle (sechs überschneiden sich), Analyse
acht plus zwei betroffener Dateien ohne Befund. Künstliche1440px-/390px-Probe
mit Abspielen, Schrittwechsel, Reglergeste und Tippzuordnung abgeschlossen.
Physische Geräteabnahme und erfolgreiche echte KI-Szenenerzeugung bleiben offen;
Build/Deployment ausschließlich gemäß RELEASE_97_2026_10_23.md bewerten.

Darstellungskatalog zusätzlich lokal abgenommen:35neue Registry-/Schemafälle
und13neue vollständige Provider-Mockpfade bestanden. Sie prüfen alle24Profile,
endgültige Frage-/Blockgrenzen, normale material.subject-Aufgaben auf drei
Anbieterwegen, Fachtrennung im Paket, Codex-Grenzen und ausgeschlossene reine
Rückblicke/Sprachprojekte.48neue Fälle, keine echten Modellaufrufe; die finale
vereinte20-Dateien-Backendprüfung läuft vor Veröffentlichung.
