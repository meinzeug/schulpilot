# Zwei Erscheinungsbilder: Cyber-Lerncockpit

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

Stand20.10.2026, Zielversion1.15.0+65. Gemeinsame Flutter-Oberfläche für Web und
Android; Kinder, Eltern und Administration verwenden dieselben semantischen
Farben in `app/lib/app_palette.dart` und kontrollierten Komponenten in `ui.dart`.
Der ausdrückliche Betreiberauftrag ersetzt die frühere reine Hellgestaltung.

## Dunkel und hell

| Ebene | Dunkel | Hell |
| --- | --- | --- |
| Arbeitsfläche | Navy `#080F1F` | `#F4F5FC` |
| Inhaltsfläche | `#132139` | Weiß |
| eingelagerte Gruppe | `#111F35` | `#EBEFF8` |
| normale Schrift | `#EFF6FF` | `#17233C` |
| sekundäre Schrift | `#ADBED5` | `#4C5F79` |
| violette Textakzente | `#B49AFF` | `#623BEA` |
| Cyantext | `#67E8F0` | `#006575` |
| Hauptaktion | `#7048D5` mit Weiß | `#7048D5` mit Weiß |

Der gemeinsame Sonnen-/Mondschalter ist schon vor der Anmeldung erreichbar und
bleibt im Kontokopf. `AppState.setAppearance` ändert ausschließlich die lokale
Anzeigepräferenz; sie bleibt nach Neustart erhalten. Es entstehen keine
Serveränderung, KI-Kosten oder Rollenrechte. Derselbe Router und dieselben
Formularcontroller erhalten Eingaben und Mailfragmente beim Wechsel.
Historische Farbkonstanten dienen nur als kompatible Standardargumente; gemeinsame
Flächen lösen sie über die aktuelle Palette auf. Fotografien und fachliche
Farbwerte werden nicht pauschal invertiert.

## Aufbau der drei Arbeitsräume

Kinder: eine dominante Lernstation mit tatsächlichem nächsten Schritt und eigener
Cyber-Buchdrohne. Ein kompakter Scan-Dock bleibt sichtbar. Echte Lernzeit,
Kurzplan und Postfach sind klar getrennte kleinere Werkzeuge, keine aufklappbaren
Kartenstapel. Lernen verwendet offene Themengruppen, Wörter echte Karteikarten,
Konto geordnete Geräteeinstellungen. Keine erfundenen Punkte, Levels oder Streaks.

Eltern: tatsächliche Übungsbelege vor Verwaltung, vollständige Kategorienverteilung,
Handlungsbedarf und Zeit nebeneinander, flache Fach-/Kinderzeilen. Admin:
reale Triage, priorisierte Betriebsaktionen und breite Verwaltungstabellen.
Der jeweilige Rollenbereich folgt derselben Formensprache ohne Kinderfigur vor
Berichten und Betriebsformularen.

Eine globale Navigation: Sidebar ab1050px, Rail ab720px, darunter Touchnavigation.
Betrieb, Einrichtung, Verkauf und Push bleiben auch mobil erreichbar.
Lokale Kontextreiter wiederholen keine zweite globale Menüleiste.
Die geführte Lernrunde erhält ihren klaren Rückweg und die drei Phasen
Verstehen, Üben, Rückblick. Frage, eigene Antwort und Rückmeldung bleiben
zusammen. Antwortfeedback verschwindet erst nach ausdrücklichem Weitergehen.
Hilfe und Hauptaktion haben feste Plätze außerhalb der Tastatur.

## Schrift und Grafik

Nunito für Fließtext, Space Grotesk für kurze Überschriften und Zahlen, beide
lokal mit OFL-Lizenz gebündelt. Keine Font-CDN-Abfrage. Formelsatz nutzt weiterhin
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
