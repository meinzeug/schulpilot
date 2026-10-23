# Zwanzig neue Lernelemente ·23.10.2026

Auftrag: weitere nützliche Simpleclub-Muster untersuchen und mindestens20konkrete
Verbesserungen umsetzen. Diese Liste zählt sichtbare Funktionen in vier
zusammenhängenden Bereichen, keine Testfälle, Schutzprüfungen oder bloßen
Umbenennungen. Alle20Funktionen implementiert; gezielte Tests und Browserprobe
bestanden. Vollständige CI und Veröffentlichung werden im Releasebeleg ergänzt.

Die Referenzen sind Anregungen für eine eigene Implementierung. Keine fremden
Lerntexte, Abbildungen, Animationen oder Icons werden als Produktassets kopiert.
Die [vorangegangene zweite Runde](SIMPLECLUB_ROUND_2_2026_10_23.md) enthält den
genauen Bedienumfang und die Grenzen jeder dort gesehenen Aufgabe.

| Nr. | Neue sichtbare Funktion | Konkrete Abnahme |
| --- | --- | --- |
| 01 | Mehrere beschriftete Texteingaben in einer Aufgabe | Zwei bis vier stabile Felder gemeinsam prüfen, genau ein gespeicherter Versuch. |
| 02 | Zeilenweise Dropdown-Auswahl | Pro Feld nur die zugehörigen belegten Optionen anbieten. |
| 03 | Gemischte Feldgruppen | Text und Auswahl innerhalb derselben Aufgabe verwenden. |
| 04 | Rückmeldung je Feld | Ausschließlich gespeicherte Serverurteile zu den einzelnen Feldkennungen anzeigen. |
| 05 | Vollständigkeitsanzeige mit Sprung zum offenen Feld | Lokalen Ausfüllstand sehen und das erste offene Feld erreichen; dies ist kein Lernfortschritt. |
| 06 | Lesbare Gruppenantworten im Rückblick | Kinder- und Elternansichten zeigen Feldbezeichnungen und eigene Antworten statt JSON. |
| 07 | Wortgruppenlupe | Eine vorhandene Textgruppe vergrößert lesen. |
| 08 | Kontextmarkierung | Die ausgewählte Gruppe im vollständigen belegten Satz wiederfinden. |
| 09 | Geführte Umstellung | Zwischen zwei bis vier vollständig wörtlich belegten Textreihenfolgen wechseln. |
| 10 | Stabile Gruppenidentitäten | Nummer und Farbe derselben Textgruppe über die Varianten hinweg wiedererkennen. |
| 11 | Positionsvergleich für Textgruppen | Geänderte Positionen gegenüber der Ausgangsfolge erkennen. |
| 12 | Direkter Textvergleich | Ausgangs- und gewählte Variante gleichzeitig lesen. |
| 13 | Direkter Modellvergleich | Zwei offengelegte Zustände derselben Szene gleichzeitig sehen. |
| 14 | Ausgangszustand wählen | Einen beliebigen vorhandenen Schritt als Vergleichsbasis setzen. |
| 15 | Direkte Schrittwahl | Einen vorhandenen Grafikschritt ohne Durchspielen aller Vorgänger wählen. |
| 16 | Beschriftete Grafikänderungen | Verschobene Plätze, geänderte Hervorhebungen und hinzugekommene/entfallene Pfeile lesen. |
| 17 | Aufklappbare Objektlegende | Stabile Nummer, Beschriftung und Form der Szenenelemente gemeinsam nachschlagen. |
| 18 | Ansicht zurücksetzen | Vergleich, Ausgangswahl und Abspielposition bewusst auf den Anfang zurücksetzen. |
| 19 | Rundenübersicht | Den aktuellen Lernschritt in der vorhandenen Aufgabenfolge wiederfinden. |
| 20 | Filter für offene/bearbeitete Aufgaben | Die Übersicht lokal nach dem gespeicherten Abschlussstatus filtern. |

Zusätzlich bleiben die Zoomhinweise auf kleinen Displays zunächst eingeklappt.
Die Vergrößerungstasten sind direkt erreichbar; die vollständige Anleitung
lässt sich bewusst öffnen. Schriftgrößen werden dafür nicht begrenzt.

## Erneut tatsächlich untersuchte Referenzen

- Die [Deutsch-Aufgabe mit mehreren Feldern](https://app.simpleclub.com/topic/s6aGA5W0VCV88ozDJgjT/story/d7liyNBzAWund0O63Chn) und die [Geo-Dropdownzuordnung](https://app.simpleclub.com/topic/JrKHtABpjgBDGW4KEuLk/story/Cf0efQjgRMaomfaLBmGF) begründen die erste Gruppe. Die gemeinsame Serverprüfung und der lesbare Schulpilot-Rückblick sind unsere Umsetzung, keine Behauptung über die genaue Bewertung der Referenz.
- [Satzglieder](https://app.simpleclub.com/topic/s6aGA5W0VCV88ozDJgjT) und [indirekte Rede](https://app.simpleclub.com/topic/cpU7G7pPIAk0UuYr3BFP) zeigen vorgegebene Wechsel von Text-/Dialogsituationen. Die Lupe und die explizite Anzeige verschobener Textgruppen sind eigene Ergänzungen.
- [Kreuzprodukt](https://app.simpleclub.com/topic/H5bfbGV8FeADUSdmijeK/story/wUoqa4po5lhHf2kjCw7V), [PCR](https://app.simpleclub.com/topic/53U9YDbQjx7WnOU7bBmN), [Marktgleichgewicht](https://app.simpleclub.com/topic/woDBH6TsL5yP0OeoQsZy) und [Queue](https://app.simpleclub.com/topic/eTYmQNPfkaYEi9oFSnLB) wurden in der zweiten Runde tatsächlich bedient. Direkter Vergleich und rein beschreibende Änderungslisten sind eigene Ergänzungen zum vorhandenen Schulpilot-Szenenplayer.
- Zusätzlich jetzt auf [Home](https://app.simpleclub.com/home) den Lernplan-Assistenten geöffnet, Vorlagen gewählt, den Abschnitt Geschichte aufgeklappt und die [Geschichte-NRW-Vorschau](https://app.simpleclub.com/learning-plan-templates/0LgEMMJ6hPeNPaptM8Rv) gelesen: Fachgruppen mit Anzahl, Vorschau vor Übernahme, Themenabschnitte und kompakte Themenzeilen. „Vorlage nutzen“ wurde nicht betätigt und kein Referenzplan gespeichert. Die neue Rundenübersicht überträgt die klare Gliederung auf vorhandene Aufgaben; Offen/Bearbeitet sind eigene lokale Filter.

Die Geschichte-NRW-Vorschau wurde zusätzlich bei390×844px gelesen. Daraus die
[Kieler-Matrosenaufstand-Aufgabenrunde](https://app.simpleclub.com/topic/rEKlByles417II6G0s2D/story/HoH1A5MKAZ22ESMQHiVj)
geöffnet: erste von vier Aufgaben als Einfachauswahl gelesen, nicht beantwortet.
Die Themeninhalte-Schaltfläche wurde tatsächlich geöffnet: mobile Begleitübersicht
mit Text, Video, Aufgabe, Dauer und0/3-Abschlussstatus. Keine Antwort oder
Vorlagenübernahme ausgeführt. Dies ist eine weitere direkte Anregung für die
Schulpilot-Übersicht, kein Nachweis identischer Aufgabenfilter der Referenz.

Die20Punkte sind keine vollständige Prüfung aller verfügbaren Referenzaufgaben.
Weitere Vorlagen-, Aufgaben- und Mobilbeobachtungen werden nur nach tatsächlich
erfolgter Bedienung ergänzt. Eine öffentliche Beschreibung allein wird nicht
als bedienter App-Nachweis gezählt.

## Daten und Lernbelege

Mehrfeldaufgaben sind ein eigener versionierter Vertrag. Eine bewusste Prüfung
speichert genau einen bisherigen Antwortversuch mit Feldurteilen, keine neue
Prüfroute oder zusätzliche KI-Anfrage. Entwürfe bleiben privat. Unbekannte freie
Formulierungen werden nicht automatisch als richtig ausgegeben. Feldlösungen
und Belegzitate werden vor dem normalen Transport entfernt.

Textvarianten bestehen ausschließlich aus vollständigen belegten Reihenfolgen;
keine freie Grammatikbewertung und keine erfundenen falschen Beispiele.
Die Textprobe öffnet nur in einer bereits erlaubten Hilfe-/Lösungsstufe.
Szenenvergleiche beschreiben lediglich sichtbare Änderungen. Sie errechnen
keine physikalischen Zustände, Marktprognosen oder neue fachliche Behauptungen.

Lupe, Auswahl, Vergleich und Filter speichern keine richtigen Antworten,
Kompetenzen oder eigenen Lernzeittakte. Konto-, Sitzungs-, Quellen- und
Fragenwechsel schützen sämtliche lokalen Ansichten. Die Übersicht schaltet
keine Aufgaben frei und umgeht keinen adaptiven Lernschritt.

Der serverseitige KI-Katalog wird erst um tatsächlich erreichbare Schema- und
Rendererfähigkeiten ergänzt. Alle24Profile bleiben fachgetrennt; bestehende
Token-, Kosten-, Quellen- und Reservierungsgrenzen gelten weiter. Keine weiteren
kostenpflichtigen Modellproben für diese Umsetzung.

## Gemeinsame lokale Abnahme

400gezielte Backendfälle unter SQLite und180Fälle in einer isolierten
PostgreSQL16-Datenbank bestanden.183Flutterfälle in15betroffenen Dateien sowie
die vollständige Flutteranalyse und Ruff ohne Befund. Browser: künstliche,
schreibgesperrte Vorschau; Mehrfeldtexte und Dropdown bei390×844px ausgefüllt,
Textuntersuchung/Variante/Gruppenlupe/Vergleich bedient, Szenenvergleich mit
anderer Basis und Objektlegende geöffnet, Rundenfilter Offen/Bearbeitet geprüft.
Keine Antwortprüfung oder KI-Anfrage in dieser Vorschau ausgelöst.
