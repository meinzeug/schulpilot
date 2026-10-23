# Schulpilot: gemeinsame Lernoberfläche

Gestaltungsstand 23.10.2026, geplant für **1.25.0+96**. Die angemeldete
simpleclub-App wurde auf ausdrücklichen Nutzerauftrag direkt bei
1440×1000 px und mobil bei 390×844 px betrachtet. Die Beobachtung umfasst das
Thema „Brüche“, den Planerstellungsassistenten und die Vorlagenvorschau
„Mathe Abitur NRW“ sowie die ersten zugänglichen Seiten der Lektion
„Berechnung von Bruchteilen“ mit endlicher Torten-/Bruchdarstellung.
Die Übung „Brüche verstehen“ war durch die Unlimited-Bezahlschranke gesperrt.
Es gab weder einen Kauf noch eine Umgehung; die geschützten Aufgaben wurden
nicht bedient oder abgenommen. Die sichtbare Themenübersicht, zugängliche
Lektionsführung und Planvorschau dienen ausschließlich als Gestaltungsreferenz.

Schulpilot übernimmt daraus ruhige Anthrazitflächen, klare Überschriften,
kompakte Format-/Zeit-/Statusangaben, dünne Piktogramme und blaue pillenförmige
Hauptaktionen. Marke, Icons, Vektorgrafiken und Lerninhalte bleiben eigene
Schulpilot-Bestandteile; simpleclub-Assets, Lerntexte oder Kontodaten werden
nicht übernommen. Die Darstellung verwendet die vorhandene gemeinsame
Flutter-App und lokale Nunito-Schrift, ohne neue Pakete, externe Schriftabrufe
oder Bilddienste. Frühere Gestaltungsgrundlage:
[SIMPLECLUB_STYLE_2026_10_22.md](SIMPLECLUB_STYLE_2026_10_22.md).

Die Kinderhefte starten als kompakte Fachliste; eine bewusst gewählte Listen-/
Kachelansicht bleibt beim Wiederöffnen erhalten. Die Startseitensuche öffnet den
vorhandenen Fachfilter ohne Schreib- oder KI-Aufruf.

Bedienprüfung1.19.6: gespeicherte Übungsbelege stehen in der Elternübersicht vor
der optionalen KI-Verwaltung. Listen kennzeichnen Laden, Fehler und leere
Filterergebnisse getrennt; alte interaktive Karten bleiben bei einem
Kontextwechsel nicht stehen. Die Anmeldung bietet Feldhinweise und
Weiter-/Fertig-Tastaturwege. Im Kinderpostfach sind Livehilfe und Nachricht für
später direkt erreichbar, Kontextlinks benennen ihr Ziel. Recherche und
Prüfgrenzen in [UX_REVIEW_2026_10_22.md](UX_REVIEW_2026_10_22.md).

Vereinheitlichung1.18.4: Kinder-Hausaufgaben und Hefte nutzen dieselben
`ChildSectionHero`-/`ChildSectionTabs`-/Aktionsbausteine wie Lernen, Wörter und
Konto. Ein sichtbarer Fotoeinstieg, beschriftete Suche/Filter und klare Rückwege
ersetzen die älteren Kopf-/Iconleisten. Hefterdetails behalten Blättern, Kacheln
und Liste. Elternansichten und Quellen-/Uploadrechte bleiben erhalten. „Meine
Fächer“ zeigt weiter ausschließlich vorhandene Seiten einschließlich unzugeordneter
Quellen. Kartenanzahl und Höhe berücksichtigen große Schrift auch bei320px.
Headerglocke und Kontoname öffnen in beiden Erscheinungsbildern dieselben
kontogebundenen Klappmenüs; mobile Trefferflächen bleiben mindestens48px.

Elternausbau21.10.2026: gleiche Kindnavigation mit Lernstand, Lernplan und
Hausaufgaben. Lernkompass zeigt aktuelle Aufgabenbelege vor der datierten
KI-Einschätzung; drei klare Lernplanansichten statt verschachtelter Formulare.
Hausaufgabenlisten kennzeichnen Selbstangaben ausdrücklich. Gemeinsame Palette,
große Trefferflächen und begrenzte Kartenbreite bleiben erhalten. Fachlicher
Ablauf und Datenschutz in [PARENT_LEARNING.md](PARENT_LEARNING.md).

Gemeinsame Flutter-Oberfläche für Web und Android; Kinder, Eltern und
Administration verwenden dieselben semantischen
Farben in `app/lib/app_palette.dart` und kontrollierten Komponenten in `ui.dart`.
Der ausdrückliche Betreiberauftrag ersetzt die frühere reine Hellgestaltung.

## Dunkel und hell

| Ebene | Dunkel | Hell |
| --- | --- | --- |
| Arbeitsfläche | Anthrazit `#101E24` | `#F4F6F8` |
| Inhaltsfläche | `#202C34` | Weiß |
| eingelagerte Gruppe | `#1B272E` | `#EDF1F4` |
| normale Schrift | `#F5F7F8` | `#17233C` |
| sekundäre Schrift | `#B2BEC4` | `#4C5F79` |
| blaue Textakzente | `#9AC2FF` | `#075BC5` |
| Cyantext | `#67E8F0` | `#006575` |
| Hauptaktion | `#0866E9` mit Weiß | `#0866E9` mit Weiß |

Der gemeinsame Sonnen-/Mondschalter ist schon vor der Anmeldung erreichbar und
bleibt im Kontokopf. `AppState.setAppearance` ändert ausschließlich die lokale
Anzeigepräferenz; sie bleibt nach Neustart erhalten. Es entstehen keine
Serveränderung, KI-Kosten oder Rollenrechte. Derselbe Router und dieselben
Formularcontroller erhalten Eingaben und Mailfragmente beim Wechsel.
Historische Farbkonstanten dienen nur als kompatible Standardargumente; gemeinsame
Flächen lösen sie über die aktuelle Palette auf. Fotografien und fachliche
Farbwerte werden nicht pauschal invertiert.

## Aufbau der drei Arbeitsräume

Kinder: eine klare Lernkarte mit tatsächlichem nächsten Schritt und blauer
Hauptaktion, ohne große Maskottchenfläche. Ein kompakter Scan-Dock bleibt sichtbar. Echte Lernzeit,
Kurzplan und Postfach sind klar getrennte kleinere Werkzeuge, keine aufklappbaren
Kartenstapel. Lernen verwendet offene Themengruppen, Wörter echte Karteikarten,
Konto geordnete Geräteeinstellungen. Keine erfundenen Punkte, Levels oder Streaks.

Eltern: tatsächliche Übungsbelege vor Verwaltung, vollständige Kategorienverteilung,
Handlungsbedarf und Zeit nebeneinander, flache Fach-/Kinderzeilen. Admin:
reale Triage, priorisierte Betriebsaktionen und breite Verwaltungstabellen.
Der jeweilige Rollenbereich folgt derselben Formensprache ohne Kinderfigur vor
Berichten und Betriebsformularen.

Eine globale Navigation: Im Browser steht bei normaler Schrift ab 1050 px eine
224 px breite beschriftete Rail. Bei 720–1049 px verwendet dieselbe Navigation
80 px Breite; bei großer Schrift über dem Faktor 1,4 fällt auch die breite
Browseransicht auf die kompakte 80 px-Rail mit zugänglichen Beschriftungen zurück.
Darunter steht die eingerückte, abgerundete Touchnavigation mit sichtbarer
Auswahl. Das Kontoziel bleibt unten in der Rail; Betrieb, Einrichtung, Verkauf
und Push bleiben auch mobil erreichbar.
Lokale Kontextreiter wiederholen keine zweite globale Menüleiste.
Die geführte Lernrunde erhält ihren klaren Rückweg und die drei Phasen
Verstehen, Üben, Rückblick. Frage, eigene Antwort und Rückmeldung bleiben
zusammen. Antwortfeedback verschwindet erst nach ausdrücklichem Weitergehen.
Hilfe und Hauptaktion haben feste Plätze außerhalb der Tastatur.

## Lernpläne, Aufgaben und Fachgrafiken ab 1.25.0

Die gemeinsamen Bausteine in `learning_plan_ui.dart` ordnen vorhandene Pläne:
`PlanSectionTitle` zeigt kurze Abschnittstitel mit ruhiger Trennlinie;
`PlanPill` bündelt bereits vorhandene Zeit-, Format- oder Statusangaben.
`PlanSubjectMark` verwendet die eigenen lokalen Fachsymbole und
`PlanDateMark` eine kompakte Datumsmarke. `PlanDayCard` gruppiert einen Lerntag,
`PlanRow` stellt dessen tatsächliches Thema und die bestehende Aktion dar.
Kinder-Kurzplan, nächste Lerntage, gespeicherter Lernweg und Elternwochenplan
nutzen diese Formensprache. Reihenfolge, Termine, Verfügbarkeit, Pflichten,
Mindestziele und Rückwege bestimmt weiterhin der bestehende Aufrufer.

Der aktive `LearningRoom` verzichtet auf globale Navigation. Ein klarer Rückweg,
dünne segmentartige Phasenführung und kompakte Fortschrittsangaben lassen Platz
für die Aufgabe. Verstehen, Üben und Rückblick bleiben die vorhandenen drei
Phasen. Die breite blaue Hauptaktion und die separate Hilfe haben ihren eigenen
Platz außerhalb des Inhaltsscrollbereichs und oberhalb der Bildschirmtastatur.
Große Schrift verwendet weiterhin den vorhandenen angepassten Aufbau.

Aufgaben, Auswahlantworten und Erklärungen erhalten gleichmäßige Nunito-
Typografie, ruhige Karten und eindeutige Auswahlrahmen. Auswahl bleibt eine echte
Radio-Gruppe mit Tastaturbedienung; Texteingaben behalten ihre Controller und
Entwürfe. Feedback zeigt die eigene Antwort zusammen mit dem bestehenden
Urteil und einem kleinen farbigen Statussymbol auf neutraler Fläche.
Unsicherheit, weitere Versuche und verwendete Unterstützung bleiben ausdrücklich
unterschieden; Gestaltung erzeugt keine zusätzlichen Lernerfolge.

`LearningGraphicFrame` rahmt bereits freigegebene Fachgrafiken einheitlich mit
Titel und gut lesbarer eingelagerter Fläche. Die Vergrößerungsaktion steht bei
ausreichender Breite neben dem Titel, bei schmalem Platz oder großer Schrift
darunter. Die vorhandene lokale Zoomansicht bleibt an Konto und Familie gebunden
und schließt bei Kontowechsel. Fachliche Daten, Geometrie, Farben mit fachlicher
Bedeutung und Alternativtexte werden nicht dekorativ umgedeutet. `given`,
`hint1`/`hint2`/`hint3` und `solution` bleiben die maßgeblichen Offenlegungsstufen.

Diese Überarbeitung ändert keine Backendaufrufe, Berechtigungen, Quellen,
Antworten, Bewertungen, Versuche, Lernzeit oder bewusst auszulösenden KI-Aktionen.
Callbacks und Kontokontextprüfungen bleiben beim bestehenden Aufrufer. Die
vorhandenen fachlichen Regeln gelten weiter:
[SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md).

## Schrift und Grafik

Nunito für gemeinsame Überschriften und Fließtext; Space Grotesk bleibt für
bestehende ausdrücklich gesetzte Zahlen-/Detailanzeigen lokal verfügbar. Beide
Schriften sind mit OFL-Lizenz gebündelt. Keine Font-CDN-Abfrage. Formelsatz nutzt weiterhin
die funktionalen KaTeX-Schriften; Code die lokale System-Monospace-Schrift.
Fließtext15–17px, mindestens1,5-fache Zeilenhöhe. Hauptaktionen52px,
andere Trefferflächen mindestens48px. Eingaben erhalten einen sichtbaren
2,5px-Fokusrahmen. Sekundärtexte werden nicht mit Transparenz abgeschwächt.

`assets/illustrations/learning-companion.png` wurde mit dem eingebauten
Bildwerkzeug aus einer rein künstlichen Beschreibung erzeugt. Es enthält keine
Kinderfotos, Namen, Schulheftinhalte oder Anbieter-Schlüssel. Keine neue
Bilddienstintegration in Schulpilot. Die Darstellung ist Dekoration und kein
Kompetenz- oder KI-Erfolgsbeleg. Generierungsauftrag:

> Friendly hovering book-shaped exploration drone for a learning app, cyan
> visor and eyes, violet folded-paper wings, bookmark antenna, sophisticated
> for ages7–17, matte navy body and cyan seams, centered full character in
> three-quarter view, production illustration with genuine transparent alpha,
> works on dark and light backgrounds. No real child, names, text, numbers,
> reward coins, weapons, logos, franchise or cropped limbs.

PNG1254×1254 RGBA, SHA256
`51c202855298bdf9a0656f4974408a24c81182c9d262ee4a0dbd3c65b951df06`.
Ein lokaler Codefallback hält den Einstieg bei einem Ladefehler funktionsfähig.
Schriftquellen/Hashes stehen in SOURCES.md.

## Lesbarkeit und Prüfung

Normale Texte einschließlich kleiner Reiterbeschriftung mindestens4,5:1,
notwendige Kontrollmerkmale mindestens3:1. Zustände zusätzlich durch Text und
Symbole. Wissenschaftliche helle Flächen und ihre Beschriftung werden gemeinsam
behandelt; echte weiße/schwarze Klaviertasten und fachliche Farbcodierung bleiben
fachlich korrekt. Die Formeln behalten Werte, Geometrie und Alternativtexte.

Die Widgetprüfungen umfassen beide Varianten,320/390/1440px, große Schrift,
Tastatur, tatsächliche Fokusrahmen, Entwurferhalt und reine Navigation ohne POST.
`appearance_test.dart` prüft lokalen Wiederanlauf und Mailfragment-/Formularerhalt.
Zusätzliche Rendererfälle prüfen Wechsel beider Themen. Tatsächliche Browser-,
Build- und Testergebnisse stehen in STATUS.md; diese Beschreibung ist keine
vollständige WCAG-Zertifizierung, physische Android- oder Wirksamkeitsstudie.

Abnahme des aktuellen Darstellungsstands: 717 Flutterfälle in 26 Dateien bestanden;
die statische Analyse aller 20 geänderten Dartdateien blieb ohne Befund. Darunter
sind die neuen Plan-/Grafikfälle für 320 px mit 200 % Schrift, 390 px und 1440 px,
Freigabestufen, lokale Zoomaktionen und Kontowechsel sowie bestehende Lernraum-,
Tastatur-, Antwort- und Zeitregressionen. Die eigene Browserprobe bei1440×1000 und390×844
zeigt Planmodal, Aufgabenraum, Antwortkarten und lokalen Grafikzoom mit
ausschließlich künstlichen Beispielen. Schreibende Requests sind dort gesperrt;
keine echte KI oder Lernaktivität. Build-/Deploynachweise folgen in
[RELEASE_96_2026_10_23.md](RELEASE_96_2026_10_23.md).

Die gemeinsame Rechercheentscheidung mit Primärquellen und Grenzen ist in
[CHILD_WORKSPACE_2026_10_20.md](CHILD_WORKSPACE_2026_10_20.md),
[PARENT_WORKSPACE_2026_10_20.md](PARENT_WORKSPACE_2026_10_20.md) und
[ADMIN_WORKSPACE_2026_10_20.md](ADMIN_WORKSPACE_2026_10_20.md) dokumentiert.

## Lokaler Formelsatz

Die funktionale, exakt gepinnte Formelengine flutter_math_fork0.7.4 ergänzt
MathText für native wissenschaftliche Notation. Sie führt kein neues Designsystem,
Webview oder externe Schrift-/Bilddienste ein. Mindestgröße18, geräumige Brüche,
große Schrift und horizontales Lesen breiter Formeln; normale Lerntexte bleiben
im gemeinsamen Design. Tabellen/Code/Fachgrafiken stehen direkt in Aufgaben und
geöffneten Hilfen. Umfang und Grenzen: [SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md).

## Menüs und gemischter Lernstoff ab 1.13.0

Die rollenbezogene Hauptnavigation bleibt erhalten. Kinder starten unter Hefte
mit vorhandenen Seiten; der vollständige Fachkatalog bleibt über den bestehenden
Filter erreichbar. Bereits im Konto gewählte Ansichten bleiben erhalten. Keine
neue Rolle oder Freigabe durch diese Voreinstellung.

Wortfilter müssen Ladestand, fehlende Treffer und einen Ladefehler unterscheiden.
Alte Wörter dürfen beim Wechsel der Sprache/Sammlung/Suche nicht unter den neuen
Filtern bearbeitet oder geübt werden. Ein Rückweg setzt die Filter der gewählten
Sprache zurück; es wird dadurch kein Lernauftrag gestartet. Geräteaktionen heißen
„Hier abmelden“ oder „Gerät abmelden“ und stehen bei langen Namen/großer Schrift
unterhalb der Gerätebeschreibung.

Gemischte Erklärungen erkennen Überschriften, Tabellen und Code auch ohne leere
Trennzeile. Matrizen/TeX-Umgebungen und Code bleiben zusammen. Tabellenzellen
respektieren explizite Mathematik und maskierte Trennzeichen. Formelwidgets dürfen
keine intrinsische Tabellenbreitenmessung auslösen: begrenzte responsive feste
Spalten und horizontales Lesen verwenden. Neue Erklärungen beginnen wieder bei
Schritt eins; gespeicherte Quellen und fachliche Lösungen nicht umschreiben.

Nach einem Erklärungsschrittwechsel den Anfang des neuen Schritts sichtbar machen,
auch nach langem Scrollen und bei großer Schrift. Gleiches gilt beim Austausch
der Erklärung. Keine Quellen-/Antwortänderung und keine zusätzliche KI dabei.

## Elternübersicht ab 1.14.0

Fachlicher Übungsstand steht vor Planung und Verwaltung. Ergebnisse sind
beantwortete Aufgaben mit getrennten Kategorien; Wissensprozente werden daraus
nicht abgeleitet. Serverzeit/Mindestziele bleiben ein eigener Bereich. Eine
gemeinsame Kindnavigation und kompakte mobile Bereichsauswahl verbinden die
Detailseiten. Noteneinstellungen und Wiederholungsdetails bei Bedarf aufklappen.
Abnahme: [PARENT_OVERVIEW_2026_10_20.md](PARENT_OVERVIEW_2026_10_20.md).


## Fortsetzung und Formulare ab 1.19.7

Sammlungen merken ausschließlich Ansichtswahl, Suche, Filter und Seite im
Arbeitsspeicher derselben Sitzung. Neue Anmeldung, auch derselben Benutzer-ID,
verwirft diese Merkliste. Während Filterabrufen bleibt die gewählte Sammlung
beschriftet; alte Wörter und Aufgaben werden nicht als neue Treffer angezeigt.

Die detaillierte Eltern-Lernstandseite zeigt Titel, tatsächliche Übungsbelege
und Fachkarten vor der optionalen KI-Einschätzung. Gefilterte Leerlisten nennen
den gewählten Bereich und bieten „Alle Fächer anzeigen“. Aktualisierung gehört
zur gemeinsamen Kindnavigation. Lade-, Treffer- und Fehlerstatus sind beschriftet.

Elternformulare scrollen auch bei Bildschirmtastatur und großer Schrift. Fehler
bleiben im Dialog, bestehende Eingaben erhalten. Laufende Änderungen sperren
doppeltes Absenden und Abbrechen. Löschen nennt das konkrete Ziel. Offene
Formulare bleiben an das ursprüngliche Konto und die Familie gebunden.

Beim bewussten Wechsel zwischen Anmeldung, Passwort-Hilfe und Registrierung
kann der gerade eingegebene Benutzername bzw. die E-Mail einmalig im RAM
weitergegeben werden. Ein Kindername wird nicht als Eltern-E-Mail ausgegeben.
Keine Passwörter, URL-Parameter oder persistente Speicherung für diese Übergabe.
