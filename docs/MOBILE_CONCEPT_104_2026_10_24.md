# Schmale Seiten und verständliche Grafiken ·104 ·24.10.2026

## Tatsächlich beobachtete mobile Referenz

Simpleclub wurde sichtbar im angemeldeten In-App-Browser bei390×844 untersucht.
Die folgende Liste erfasst27 Funktionsansichten und Bedienzustände aus verschiedenen
Bereichen, keine27 verschiedenen Lernthemen und keine vollständige Abnahme jeder Appfunktion.
Echte Screenshots liegen im lokalen Visualisierungsverzeichnis; sie sind Referenzbelege,
keine übernommenen Produktassets. Die Profilaufnahme enthielt Kontodaten, blieb privat und wurde nach Sichtprüfung gelöscht.

| Nr. | Beobachtete Ansicht / Bedienung | Bild |
| --- | --- | --- |
| 1 | Bibliothek: mobiler Lernplan-Einstieg | `simpleclub104-mobile-01-library.jpg` |
| 2 | Lernpläne: Filter und Sortierung im Overlay | `simpleclub104-mobile-02-plan-sort.jpg` |
| 3 | Sortierung: eigene Auswahlfläche | `simpleclub104-mobile-03-sort-choice.jpg` |
| 4 | Lernplan erstellen: mobile Einstiegswahl | `simpleclub104-mobile-04-new-plan.jpg` |
| 5 | Lernplan-Vorlagen und Fächerkacheln | `simpleclub104-mobile-05-plan-templates.jpg` |
| 6 | Fachvorlage: aufklappbare Vorschau | `simpleclub104-mobile-06-template-preview.jpg` |
| 7 | Lernplan-Vorlagendetail mit Inhaltsstruktur | `simpleclub104-mobile-07-plan-detail.jpg` |
| 8 | Karteikarten: eigener leerer Einstieg | `simpleclub104-mobile-08-cards.jpg` |
| 9 | Karteikarten-Set: Editor ohne Speicherung | `simpleclub104-mobile-09-card-set-editor.jpg` |
| 10 | Karteikarten: Vorder-/Rückseiten-Eingabe und gesperrte Aktionen | `simpleclub104-mobile-10-card-faces.jpg` |
| 11 | Bibliothek: Verlauf | `simpleclub104-mobile-11-history.jpg` |
| 12 | Home: Suche, Lernwerkzeuge und Weiterlernen | `simpleclub104-mobile-12-home.jpg` |
| 13 | Themenkarte: Drei-Punkte-Menü für Nebenaktionen | `simpleclub104-mobile-13-topic-menu.jpg` |
| 14 | Entdecken: Fachnavigation und kompakte Suche | `simpleclub104-mobile-14-discover.jpg` |
| 15 | Globale Suche: eigener Fokusraum mit Inhaltsarten | `simpleclub104-mobile-15-search-overlay.jpg` |
| 16 | Suche: Top-Ergebnisse mit Typkennzeichnung | `simpleclub104-mobile-16-search-results.jpg` |
| 17 | Videosuche: reine Videoergebnisse | `simpleclub104-mobile-17-video-search.jpg` |
| 18 | Aufgabensuche: Auswahl ohne Start | `simpleclub104-mobile-18-exercise-search.jpg` |
| 19 | Thema: Lernarten und Fortschrittsübersicht | `simpleclub104-mobile-19-topic-overview.jpg` |
| 20 | Themenkopf: Nebenaktionen im Mehr-Menü | `simpleclub104-mobile-20-topic-actions.jpg` |
| 21 | Fehler melden: gestufte Auswahl ohne Absenden | `simpleclub104-mobile-21-report-dialog.jpg` |
| 22 | Erklärung: Text und interaktive Grafik im Lesefluss | `simpleclub104-mobile-22-explanation.jpg` |
| 23 | Interaktive Grafik: Nenner hervorheben/animieren | `simpleclub104-mobile-23-interactive-graphic.jpg` |
| 24 | KI-Tutor: kontextbezogener Einstieg ohne Anfrage | `simpleclub104-mobile-24-tutor.jpg` |
| 25 | Profil: Lernprofil und gruppierte Einstellungen | Privat geprüft, danach gelöscht |
| 26 | Bedienungshilfen: Animation und barrierefreie Navigation | `simpleclub104-mobile-26-accessibility.jpg` |
| 27 | Fächerwahl: Auswahlkarten ohne Speicherung | `simpleclub104-mobile-27-subject-choice.jpg` |

Referenzseiten: https://app.simpleclub.com/library,
https://app.simpleclub.com/learning-plan-templates, https://app.simpleclub.com/search,
https://app.simpleclub.com/topic/vwYaXbxOe0pD0CXOv8ed und https://app.simpleclub.com/profile.

Lernpläne/Sets wurden nicht gespeichert, keine Rückmeldung oder Tutorfrage versandt.
Der automatische Freigabecheck verweigerte „Fertig“ im Editor und „Teste dich“;
die Inspektion ging mit lesenden Alternativen weiter. Die interaktive Zähler-/Nennergrafik
wurde tatsächlich bedient; weder Übungsantwort noch Bewertung wurde ausgeführt.

## Umsetzung in Schulpilot

- Ein gemeinsamer Seitenkopf bündelt Suche, Filter und Nebenwerkzeuge hinter drei Punkten.
  Der Menüeintrag öffnet vorhandene Formulare am ursprünglichen Platz. Verdeckte Formulare
  bleiben montiert, sind vom Fokus ausgeschlossen und verlieren ihre Entwürfe nicht.
- Kinder: Lernen, Hefte, Wörter, Aufgabenfotos, Nachrichten, Verlauf, Lernstand,
  Sprachwerkstatt und Schultag. Wesentliche Reiter und nächste Handlungen bleiben direkt.
- Eltern und Administration:30 zusätzliche Werkzeuggruppen in14 Produktdateien, darunter
  Plan, Noten, Aufgaben, Verlauf, Familien, Protokoll, Bestellungen, Vorfälle und Push.
  Konkrete Arbeitseditoren, Pflichtaufträge, Notfallstopp und notwendige Warnungen bleiben direkt.
- Der Fachhefter hat einen eigenen kompakten Kopf. Blättern/Kacheln/Liste, Suche, Filter,
  Aktualisieren und Themen öffnen sich im Menü. Aktive Einschränkungen und Pager bleiben sichtbar.
- Menübefehle prüfen Konto, Sitzung, Familie, Quelle, Revision, Vordergrund und Hostroute.
  Eigene Menüs starten keine neue Abfrage oder KI. Bestehende Statuspoller werden nach dem
  Schließen mit ihren bisherigen begrenzten GET-Prüfungen fortgesetzt. Ein Dropdown oder
  Datumsdialog darf das darunterliegende Formular nicht schließen.
- Die eigene transparente [Einstiegsillustration](ILLUSTRATION_104.md) erscheint nur in leeren,
  ungefilterten Einstiegen. Gefüllte Seiten behalten den Platz für tatsächliche Inhalte.
- Bereits offengelegte Bruchmodelle erhalten Kreis-/Balkenansicht sowie getrennte Zähler-/
  Nennerhervorhebung. Zahlen und Quellen bleiben unverändert; keine Aufgabe wird dadurch bewertet.
  Animation ist lokal, bewusst und bei reduzierter Bewegung als Einzelzustand bedienbar.
- Bei allen deklarativen Fachszenen steht die eigentliche Grafik vor zusätzlichen Vergleichs-/
  Rücksetzwerkzeugen. Der bestehende fachübergreifende Szenenvertrag, Offenlegungsstufen und
  KI-Quellenbindung gelten weiter. Keine beliebigen Modellprogramme oder externen Grafikskripte.

Quellprüfung, künstliche Browserdaten, Widgetregressionen und veröffentlichte Produktionsbytes
sind verschiedene Nachweise. Technische Endergebnisse und Rückweg werden im Releasebericht dokumentiert.


Tatsächliche abschließende Prüf-/Build-/Deploymentwerte und Browsergrenzen: [Release104](RELEASE_104_2026_10_24.md).
