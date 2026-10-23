# Interaktive Erklärungen und individuelle KI-Szenen

Nutzerauftrag23.10.2026: simpleclub fachübergreifend auf Grafiken, Animationen,
Drag-and-drop und weitere Bedienelemente untersuchen und auf Schulpilot
übertragen. Individuelle, ad hoc entworfene KI-Grafiken/Animationen sind jetzt
explizit erlaubt. Der bestehende Flutter-/FastAPI-Pfad wird erweitert, kein
zweiter Dienst oder Inhaltsanbieter eingeführt. Zielversion1.26.0+97.

## Tatsächliche Referenzabdeckung

Der direkt im Browser durchgegangene öffentliche
[Fächerkatalog](https://simpleclub.com/subjects) verlinkt36Fach-/Berufsbereiche.
Alle36Übersichtsseiten wurden geöffnet und ihre372Themenverweise erfasst;
das sind Verweise, keine372abgenommenen Aufgaben oder eindeutigen Lektionen.
Die ersten17Bereiche umfassen Schul-/Nebenfächer, Wirtschafts-/Sozialkunde und
Lern-/Lebenskompetenzen; weitere19sind Berufsbereiche. Einzelne öffentliche
Kataloge enthalten Platzhalterüberschriften/-texte; diese sind keine Lehrinhalte
und werden nicht übernommen.

In der angemeldeten App angesehen: Brüche, lineare Funktionen und
Energieerhaltung/-umwandlung, Format-/Aufgabenlisten und zugängliche Texte.
Die geöffneten Bruch-/Funktionsübungen zeigen die unlimited-Sperre; im Physikthema
sind die entsprechenden Aufgaben mit Schloss markiert. Keine Sperre umgangen,
kein Kauf und keine Einladung an Dritte gesendet. Eine vollständige Sichtung
sämtlicher geschützter Aufgaben ist mit diesem Zugang nicht erfolgt.

Desktop und390×844px: Halfpipe-Grafik mit Einstiegshöhen, Energieanteilen,
Geschwindigkeitsanzeige und erklärtem Modell ohne Reibung. Die Touch-Hotspots
wurden angewählt; allein daraus wird kein erfolgreicher vollständiger
Animationsablauf behauptet. Öffentlich tatsächlich bedient wurden die
[interaktiven Businessdemos](https://business.simpleclub.com/fur-bildungsanbieter):
Lötprozess von Start auf Schritt2 mit sichtbarem Werkzeug-/Drahtwechsel sowie
Ebene0→1 in der räumlichen Würfeldarstellung mit sichtbarer Positionsänderung.
Die sichtbaren Canvas-/Kontrollnamen verwenden „rive“; daraus folgt kein Beleg,
dass sämtliche Appgrafiken oder der gesamte Produktionsprozess Rive verwenden.

Weitere öffentliche Primärbeispiele wurden als beschriebene Bedienmuster gelesen;
„App öffnen zum Interagieren“ wird nicht als frei bediente Appaufgabe gewertet:

| Fach | Öffentlicher Bezug | Gestaltungsprinzip |
| --- | --- | --- |
| Mathematik | [Kreuzprodukt](https://simpleclub.com/lessons/mathematik-kreuzprodukt) | Schrittregler, Zwischenzustände statt nur Endbild |
| Physik | [Energieerhaltung](https://simpleclub.com/lessons/physik-energieerhaltungssatz) | Szenenwahl, Bewegung und zugehörige Größen gemeinsam |
| Biologie | [PCR](https://simpleclub.com/lessons/biologie-pcr) | Phasen einzeln anwählen, Beschriftung und Zustand zusammen |
| Chemie | [Gleichgewichtsreaktion](https://simpleclub.com/lessons/chemie-gleichgewichtsreaktion) | Prozesszustände und Teilchenmodelle |
| Englisch | [Simple Past](https://simpleclub.com/lessons/englisch-simple-past) | Veränderbarer Zeitbezug |
| Deutsch | [Bildergeschichte](https://simpleclub.com/lessons/deutsch-bildergeschichte) | Bildfolge und Spannungskurve |
| Informatik | [Queue](https://simpleclub.com/lessons/fachinformatikerin-queue) | Einzelne Operationen, sichtbare Objekte und Zustandswechsel |
| Wirtschaft | [Deflation](https://simpleclub.com/lessons/wirtschaft-deflation) | Erklärte Beziehungen und Rückkopplungen |
| Geographie | [Gezeiten](https://simpleclub.com/lessons/erdkunde-gezeiten) | Vereinfachung und Grenzen explizit; dort sind teilweise nur geplante Rive-Illustrationen beschrieben |

Ein [historischer offizieller Produktionsbericht](https://b2b.simpleclub.com/blog/so-erstellen-wir-unsere-hochwertigen-lerninhalte-2)
beschreibt Autoren-/Designarbeit und Gegenprüfung. Er belegt keine heutige freie
vollautomatische Erzeugung beliebiger Animationen. Die eigene Architektur unten
ist eine Schulpilot-Entscheidung. Keine fremden Assets, Animationen, Lerntexte
oder Zugangsdaten werden ins Produkt kopiert.

## Eigene Umsetzung

Die vorhandenen Zuordnungsaufgaben erhalten wiederverwendbare Antwortkarten und
hervorgehobene Dropziele. Langes Drücken erlaubt Touchscrollen; die volle Zielzeile
öffnet weiterhin die vorhandene Auswahlansicht für Tippen und Tastatur. Dies
erhält auch wiederverwendbare Antworten, das bestehende Semikolonformat und
Entwurfsspeicherung. Ein Drop prüft Einheit, Frage, Sitzung, Familie und den
Bearbeitungszustand. Erst „Antwort prüfen“ sendet und bewertet eine Antwort.
Das ist eine Eingabehilfe auf dem vorhandenen Aufgabentyp. Neue kompakte
KI-Runden dürfen jetzt passende Zuordnungen mit zwei bis vier Paaren erzeugen.
Jedes Paar braucht eine ausdrückliche wörtliche Beziehung im eigenen bestätigten
Gruppeninhalt; bloß beide Begriffe irgendwo zu finden genügt nicht. Die Aufgabe
nutzt einen der vorhandenen Aufgabenplätze und bleibt im bestehenden Budget.

Individuelle Szenen werden als zusätzliche versionierte Grafikart `scene` in der
vorhandenen `presentation` erzeugt. Die KI kann passend zum jeweiligen Stoff
Objekte, Formen, Beschriftungen, Beziehungen, Positionen und Schrittfolgen neu
zusammenstellen. Flutter berechnet Positionen, Pfeile und weiche Übergänge lokal.
Die Komposition ist individuell; es wird kein Modellcode ausgeführt und kein
kostenpflichtiger Bilddienst für das Abspielen aufgerufen.

Das deklarative Format begrenzt Objekte, Slots, Schritte, Kanten und Dauer.
Quellenbelege und die bisherigen Offenlegungsstufen bleiben maßgeblich: Eine
gegebene Szene enthält keine versteckten späteren Lösungsschritte. Ein
Vorwärtsregler darf ausschließlich innerhalb des bereits freigegebenen Blocks
navigieren. Private Quellenzitate werden vor der öffentlichen Ausgabe entfernt.
Alte Clients erhalten beschriftete Textalternativen; bestehende Fachgrafiken
bleiben gültig. OCR, Rückblicke und reine GETs erhalten keinen zusätzlichen
Generierungsauftrag. Kosten-/Zeit-/Providergrenzen bleiben erhalten.

Der Player bietet bewusstes Starten/Pausieren, Vor/Zurück, Wiederholen und einen
Schrittregler. Er hält bei Hintergrund, überdeckter Route und Kontextwechsel an.
Reduzierte Bewegung verwendet statische Schritte. Sichtbare Erläuterungen und
vollständige Alternativtexte sind auch ohne Animation lesbar. Animationstakte
melden keine Antworten, Lernzeit oder Fortschritte.

Bereits vorhandene Prozessgraphen/-kreisläufe können zusätzlich lokal schrittweise
angesehen werden. Vorhandene Begriffe und Beziehungen bleiben vollständig;
Hervorhebung erzeugt keine weitere fachliche Behauptung oder KI-Anfrage.

Native Flutter [Draggable](https://api.flutter.dev/flutter/widgets/Draggable-class.html)
und [DragTarget](https://api.flutter.dev/flutter/widgets/DragTarget-class.html)
sind vorhanden. Die Tippalternative folgt dem
[W3C-Prinzip für Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html).
Die bestehenden Einschränkungen aus SCIENTIFIC_CONTENT.md gelten für alte
Fachmodelle weiter; die ausdrückliche Erweiterung für Szenen steht in AGENTS.md.

## Abnahme

571gezielte Flutterfälle aus16betroffenen Sammlungen bestanden, darunter echte
Draggesten im vollständigen Aufgabenraum, Randscrollen, der explizite
Prüfvorgang, Tastatur-/Tippalternative, Kontowechsel während des Ziehens,
Szenenregler, reduzierte Bewegung und Offenlegungsstufen. Die Analyse der acht
betroffenen Dartdateien ist ohne Befund. Diese gezielte Auswahl ist keine
Behauptung einer vollständigen Projektsuite.

Die einmalige echte synthetische OpenRouter-Probe verwendet ausschließlich die
serverseitige Wasser-/Wasserdampf-/Wolkenfixture, Luna/Azure, medium,
maximal4000Ausgabetokens, ZDR und normale Reservierung/Abrechnung. Der erste
Metadatenvorlauf scheiterte vor jeder Reservierung am optional fehlenden
Preiseintrag request; frischer Endpunkt, Katalog, API-Schema und dokumentierte
Auslassungsregel werden nun gemeinsam geprüft. Der anschließende einzelne
Modellaufruf kostete0,001436USD bei4115Eingabe- und2049Ausgabetokens.
Seine Ausgabe bestand die sichere Aufgabenstrukturprüfung nicht und wurde
verworfen. Kein automatischer Wiederholungsaufruf, keine Ersatzaufgabe und keine
Lockerung der Quellenprüfung. Die fehlende Rohantwort erlaubt keine konkrete
Fehlerursache oder erfolgreiche echte KI-Szenenabnahme zu behaupten.
Das feste Falljournal verhindert einen neuen Auftrag durch bloßes Ändern des
Berichtsverzeichnisses. Die Prüfobergrenze bleibt insgesamt0,25USD.

446gezielte Backendfälle in18Dateien bestanden nach den letzten Korrekturen;
Ruff ohne Befund. Die unabhängige Prüfung fand drei konkrete Lücken, jetzt mit
Regressionen behoben: Pfeilbelege prüfen vollständige Begriffe, neue Zuordnungen
erhalten keine gegebenen erklärenden Grafiken, Paarbelege dürfen keine
Materialgrenze überbrücken. Diese letzten strengeren Änderungen liegen nach
der abgelehnten echten Modellprobe; deren Quellhashes werden nicht als Nachweis
des finalen Codes ausgegeben. Es gab keinen weiteren Modellaufruf.

Zusätzlich13Mobilzoom-/Referenztests bestanden, davon sechs bereits im großen
Flutterlauf enthalten. Szene/Prozessgraph/Prozesszyklus starten im Zoom mit
höchstens der verfügbaren Breite;320/390px mit100/200%Schrift, echte
Reglergesten und weiterhin verborgene Lösungen geprüft. Acht plus zwei betroffene
Dartdateien wurden in getrennten Läufen ohne Befund analysiert.

Künstliche schreibgeschützte Browserprobe:1440×1000Desktop mit Schrittwechsel
und vollständigem Abspielen;390×844Mobil mit vollständig sichtbaren Zoomreglern
und tatsächlicher Reglergeste von Schritt1auf2. Die Zuordnung wurde per
Tippalternative vollständig ausgefüllt; erst danach ist „Antwort prüfen“ aktiv.
Die CUA-Geste ohne Langdruck ergab keinen Browsernachweis für Drag-and-drop;
die reale Langdruck-/Dropfolge ist im Flutter-Aufgabenraumtest geprüft. Keine
physische Touchgeräteabnahme behauptet. Die Vorschau und ihr Server wurden
beendet und der Browserviewport zurückgesetzt.

Releasebelege werden nach ihrer Durchführung ergänzt.
Künstliche Rendererfixtures sind keine echte KI-Ausgabe, keine Handschrift-/
OCR-Abnahme und kein Nachweis einer Lernwirkung.
