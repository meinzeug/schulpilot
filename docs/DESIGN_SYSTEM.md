# Oberflächengestaltung

Gemeinsames Flutter-Design für Android und Web, Kinder, Eltern und Administration.
Die Darstellung wird in `app/lib/ui.dart` gepflegt; keine neue UI-Bibliothek,
keine zusätzlichen Schrift- oder Bilddienste. Navy/Cyan/Violett bleiben die Marke.

## Visuelle Ebenen

- **Arbeitsfläche:** blaugrau `#E8EEF6`. Sie trennt die Inhalte von weißen
  Kopfzeilen und Cards; die Navigation verwendet Navy `#14243D`.
- **Cards:** Weiß, sichtbarer Rahmen `#B8C6D9`, dezenter Schatten, Radius 20.
  Zusammengehörige Inhalte stehen innerhalb einer Card, unterschiedliche
  Abschnitte mit Abstand nebeneinander oder untereinander.
- **Eingelagerte Gruppen:** `SurfaceInset`, Graublau `#F2F5FA`, Rahmen und Radius
  14; keine weitere schwebende weiße Card in einer weißen Card. Lernzeit und
  eigene Antwort verwenden diese Ebene.
- **Gezielte Hervorhebung:** Violett `#5936CB` für Hauptaktionen und Auswahl,
  Cyan auf dunklen Einstiegskarten. Auf hellen Flächen wird für Cyan-Symbole
  und Text das dunkle `#006575` verwendet.
- **Zustände:** Grün für gespeicherten Erfolg, Amber für weiteren Übungsbedarf,
  Cyan für offene Bewertung/Information. Text und Symbole bleiben zusätzlich
  erhalten; Farbe allein ist kein Leistungs- oder Statusnachweis.

`PanelTone` legt Flächen für neutrale, untergeordnete, hervorgehobene,
informative, erfolgreiche, warnende und fehlerhafte Bereiche fest.
Benachrichtigungen unterscheiden gelesen/ungelesen mit Fläche, Rahmen,
Schriftgewicht und Symbol. Betriebswarnungen verwenden dunkle Amber-Symbole.

## Lesbarkeit und Bedienung

Fließtext 15–16 px mit Zeilenhöhe 1,5–1,55. Überschriften 28/32 px je verfügbarer
Breite, Abschnittstitel 20 px. Sekundärtexte sind deckend `#4C5F79`, nicht durch
Transparenz abgeschwächt. Normale Buttons mindestens 48 px, Hauptaktionen 52 px
hoch; beschriftete Eingabefelder mit dunklem Rand und eigenem 2,5-px-Fokusrahmen.
Sekundärbuttons besitzen eine weiße Fläche und sichtbare Umrandung.
Tastaturfokus bleibt auch an Buttons und der Browser-Sidebar sichtbar.

Aufklappbare Details haben eigene Flächen, Rahmen und Innenabstände. Kopf,
Lerninhalt und Aktionsbereich des Lernraums sind getrennt; Antwort und Rückmeldung
bleiben gemeinsam sichtbar, bis ausdrücklich weitergegangen wird. Die drei
Lernphasen bleiben beschriftet, ergänzt durch Symbole. Bei großer Schrift
bleibt der Kopf scrollbar; die Aktion liegt weiterhin außerhalb der Tastatur.

Browser: Sidebar ab 1050 px, Rail ab 720 px, darunter Touch-Navigation.
Android behält seine native Touch-Navigation. Keine Rollen-/Rechteänderung
durch die Gestaltung und keine zusätzlichen KI- oder Push-Aufrufe.

## Kontrast und Prüfgrenzen

Grundlage: WCAG 2.2, Textkontrast 4,5:1 für normalen Text und 3:1 für große
Schrift; notwendige Erkennungsmerkmale von Bedienelementen 3:1. Die gemeinsame
Palette prüft auch kleine Beschriftungen mit 4,5:1. Dekorative Card-Rahmen sind
keine Eingabefeldgrenzen; Eingabefelder verwenden das stärkere `#7788A2`.

`app/test/design_accessibility_test.dart` prüft die tatsächlich verwendeten
Themenfarben, Navigationszustände und gerenderte Fokusrahmen. Dazu kommen
Flutter-Kontrast-/Beschriftungsprüfungen mit 320/390/1440 px und normaler/doppelter
Schrift. Bestehende Rollen-, Lernraum-, Tastatur-, Bibliotheks-, Zeit- und
Benachrichtigungstests bleiben bestehen.

Browser- und native Sichtprüfung, Releaseversion sowie tatsächliche Ergebnisse
stehen in `STATUS.md` und `CHATGPT_HANDOFF.txt`. Einzelne Farb-/Widgettests sind
keine vollständige WCAG-Zertifizierung, Screenreader- oder Nutzerstudie.

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
