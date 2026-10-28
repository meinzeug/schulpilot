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
