# Alltagstest und Modellprüfung · 28.10.2026

## Neuer Zugang und digitale Materialien

Ein separates reguläres Elternkonto wurde mit bestätigter E-Mail und einem
eigenen Kinderkonto angelegt. Ausschließlich selbst erzeugte, als Testmaterial
gekennzeichnete Bilder wurden verwendet. Zwei Mathematikfotos wurden über den
normalen Upload im heutigen Schultag gespeichert; sie erscheinen in der
Materialsammlung unter „Noch zuordnen“. Der authentifizierte Fotoabruf lieferte
HTTP 200, der Abruf ohne Anmeldung HTTP 401. Diese Prüfung verwendete die
öffentliche API; sie ist kein Nachweis eines vollständig im Browser oder auf
einem Android-Gerät ausgeführten Fotoimports.

Der bewusste Vorbereitungsstart wurde angenommen, der Hintergrundstatus wechselte
jedoch zu `blocked`, bevor eine Seite erkannt wurde. Grund: Für die neue Familie
gibt es keinen aktiven Tarif; im öffentlichen Katalog sind Testphase und
Bestellungen deaktiviert. Die beiden Fotos blieben gespeichert. Es wurden weder
eine erfolgreiche Erkennung noch ein Lernpaket, Benachrichtigungszustellung oder
Antworten behauptet. Die weitere echte Lernpfadprüfung hängt von einem regulären
Zugang für ein Testkonto ab. Es wurde keine Zahlung vorgetäuscht und keine
Zugangskontrolle umgangen.

Der bisherige separate Elternimport verlangte vor der Fotoauswahl einen
verfügbaren KI-Dienst, obwohl der Server Upload und Erkennung trennt. Der
Fotoimport bleibt nun bei vorübergehend nicht verfügbarer KI erreichbar;
die Datenschutzfreigabe für den Upload bleibt Voraussetzung. Die anschließende
Erkennung bleibt eine eigene bewusste Aktion. Ein Widgettest prüft die Auswahl
ohne unbeabsichtigten Erkennungsauftrag. Der Fotoeinstieg benennt Schulmaterial
allgemein; geschriebene Arbeiten bleiben im bestehenden Klassenarbeitenbereich.

Eine Internetverbindung ist für den authentifizierten Zugriff auf gespeicherte
Fotos weiterhin erforderlich. Die bestehende Aufbewahrungsregel für Materialien
und Lernaufzeichnungen beträgt höchstens 365 Tage; ein dauerhaftes Archiv oder
Offlinezugriff wurde nicht implementiert.

## Terra

Die Tests verwendeten ausschließlich künstlichen Stoff, eine getrennte lokale
Testdatenbank und einen fest gebundenen OpenRouter-Endpunkt. Zehn größere Fotos
lieferten zehn technisch akzeptierte Texterkennungen; technische Ankerprüfungen
sind kein vollständiger Nachweis der wörtlichen Richtigkeit. Die zugehörigen
zehn Aufrufe kosteten laut verbuchter Anbieterangabe zusammen 0,069812 USD.

Bei fünf fachübergreifenden Runden scheiterten zwei Ausgaben: eine am
Grafiktransport, eine an der Ausgabelängengrenze. Ein isoliert getesteter Hinweis
auf kompaktes JSON verbesserte einen einzelnen Deutschfall; ein weiterer Lauf
mit fünf Fächern scheiterte dennoch dreimal. Einzelne spätere Wiederholungen
waren erfolgreich und belegen daher keine ausreichende Zuverlässigkeit. Der
kompakte Hinweis wird nicht in den Produktionsprompt übernommen. Sol bleibt
aktiv, weil die ausdrücklich verlangte Bedingung erfolgreicher Tests für den
Modellwechsel nicht erfüllt ist. Die Diagnostik erhält nur geschlossene
Fehlerkennungen und protokolliert keine Inhalte.
# Zweiter Live-Durchlauf: zwei künstliche Mathematikseiten

Ein isolierter interner Testhaushalt hat zwei künstliche Fotos über den regulären
Fotoablauf abgegeben. Die beiden Erkennungen und der jeweilige automatische
Gegencheck wurden beendet. Auf der zweiten Seite wurden unleserliche Stellen
ausdrücklich als unsicher geführt. Die anschließende Paketerzeugung scheiterte
bei der Prüfung von Grafikparametern; ein Lernpaket wurde nicht veröffentlicht.
Der damalige inhaltsfreie Diagnosecode fasste drei unterschiedliche Grafikarten
zusammen, sodass sich die konkrete Abweichung nachträglich nicht bestimmen lässt.

Die Erzeugungsanweisung nennt nun die bestehenden Konsistenzregeln ausdrücklich;
die Regeln selbst bleiben unverändert. Künftige Diagnosen unterscheiden Bruch-,
Dreieck- und Spiegelparameter, ohne Modellantworten zu protokollieren. Ein
erneuter KI-Auftrag ist ein eigenständiger Test und kein Nachweis für die Ursache
des alten Modelloutputs.

Ein zweiter Fehler betraf die Statusanzeige: Ein aktiver Testphasenzugang wurde
in der lesenden Verfügbarkeitsprüfung als aufgebrauchtes Kontingent behandelt,
obwohl die tatsächlichen Aufruf- und Kostengrenzen noch Spielraum hatten. Die
Prüfung erkennt diesen Zustand jetzt und behält die bestehenden Grenzprüfungen.
Weder die öffentliche Testphase noch die Bestellfunktion wurden freigeschaltet.

Nach Veröffentlichung von 1.38.1 war die reguläre Wiederholung im Testkonto
verfügbar. Ein bewusst gestarteter weiterer Paketauftrag scheiterte erneut:
Diesmal zeigt die geschlossene Diagnose `visual_fraction_parameters`, dass im
Erklärschritt genannte Brüche nicht mit den Bruchgrafikparametern übereinstimmen.
Der verworfene Modelltext wird nicht gespeichert; die konkrete Formulierung und
ob sie fachlich falsch oder lediglich von der Grafik abweichend war, lassen sich
nicht nachträglich belegen. Die zusätzlichen Anweisungen haben diesen Fall somit
nicht zuverlässig behoben. Es erfolgte kein dritter Versuch.

Die gespeicherten Aufträge verwendeten keinen Teilplan. Kleine neue Pakete mit
nur einem geplanten Teil bleiben derzeit bewusst auf dem bisherigen Paketpfad;
die für Teilpakete vorbereiteten quellgebundenen Grafik-IDs werden dort nicht
gebunden. Ein möglicher Wechsel auf diesen Weg benötigt eigene Prüfungen für
Aufgabenanzahl, Wiederholungsgrenzen, bestehende Aufträge und Quellenbindung;
er ist nicht durch ein bloßes Freischalten einer weiteren Wiederholung erledigt.
Der vollständige Durchlauf von Aufgaben, adaptiver Weiterübung und
Fertigstellungsbenachrichtigung bleibt bis zu einem erzeugten Paket offen.

## Korrektur für neue kleine Pakete

Neue bewusst abgegebene Materialstände verwenden auch für einen einzelnen
Paketabschnitt den vorhandenen quellgebundenen Teilplan mit separater normaler
Reservierung und geprüften Grafikreferenzen. Die einmalige Entscheidung wird
über die automatische Bilderkennung hinweg gespeichert. Bereits fehlgeschlagene
ältere Aufträge werden nicht allein durch das neue Format wieder freigeschaltet:
Gespeicherte Zähler und tatsächlich vorhandene Aufträge werden berücksichtigt.
Ein wirklich geänderter Materialstand kann nach erneuter ausdrücklicher Abgabe
neu geplant werden; alte Versuche bleiben erhalten. Teilrunden enthalten im
bestehenden Vertrag zwei Aufgaben und sind nur ein Einstieg in den Lernweg.

Isolierte Tests decken neue und alte Einzelpakete, gebundene Grafikdaten,
automatische Nachprüfung, Ausschluss unsicherer Quellen und den Abschluss ab.
Der reale KI-Durchlauf muss gesondert erfolgen; ein erfolgreiches Mock-Ergebnis
ist kein Nachweis für die Qualität oder Verfügbarkeit des Modells.

## Live-Durchlauf mit zusätzlichem Arbeitsblatt

Auf Version 1.38.2 wurde im isolierten Testkonto ein weiteres künstliches
Arbeitsblatt mit einer falschen Schülerlösung und rotem Kreuz abgegeben. Die
Erkennung übernahm die falsche Lösung als Schülerarbeit und erfasste das rote
Kreuz als Korrektur; das fertige Lernpaket enthält einen Grundlagencheck und
verweist auf eine geprüfte Bruchdarstellung. Die In-App-Benachrichtigung führt
zur zugehörigen Runde. Eine Zustellung durch Firebase auf einem realen Gerät
wurde damit nicht nachgewiesen.

Eine absichtlich vertauschte Antwort auf den Grundlagencheck wurde zunächst als
unklar statt als falsch bewertet. Version `subject_rules_v6` ergänzt dafür eine
eng begrenzte Regel für die bestehende Frageform: Sie berechnet den Anteil aus
den angegebenen Teilzahlen, prüft zuerst die gespeicherte Musterlösung und lässt
nicht eindeutig auswertbare Eingaben offen. Eine ausdrückliche Nachprüfung
behält die eingegebene Antwort, Unterstützung und den früheren Bewertungsstand
in der bestehenden Bewertungshistorie; sie erstellt keinen weiteren KI-Auftrag.
