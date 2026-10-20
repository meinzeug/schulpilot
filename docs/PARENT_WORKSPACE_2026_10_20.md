# Gemeinsamer Elternarbeitsraum

Der Elternbereich ist ein offenes Lerncockpit mit zwei vollständigen Varianten:
Cyberpunk Dark und Hell. Beide verwenden `context.palette`, dieselben Abstände,
Navigation, Schriftfamilien und überprüfbaren Daten. Die Umschaltung verändert
keine Lernstände, Rechte oder Provideraufträge. Dunkle Kopfblöcke über alten weißen
Karten wurden durch eine gemeinsame, durchgehend passende Arbeitsfläche ersetzt.

## Gestaltung und Informationshierarchie

`ParentWorkspaceHero` ist trotz seines historischen Klassennamens jetzt eine
offene typografische Kopfzeile ohne Hero-Kasten. Ein kleines lokales Emblem
kennzeichnet den Arbeitsraum; es ist für Screenreader ausgeblendet und stellt
keinen Messwert dar. Die Inhalte stehen vor dekorativen Elementen.

- Der Familienstart zeigt gespeicherte Tagesdaten, sofern sie vorhanden sind.
  Kinder erscheinen als offene Zeilen mit Namen, konkreten Anliegen und einer
  separaten Zeitspalte statt gleichförmiger Kinderkarten.
- `ParentChildNavigation` verbindet alle acht Kinddetailbereiche mit demselben
  knappen Kindkopf und derselben Bereichsauswahl. Der globale Rahmen bleibt die
  einzige Hauptnavigation.
- `ParentPracticeSummary` zeigt beantwortete Aufgaben und Versuche getrennt.
  Eine breite Verteilung und beschriftete Kategorien unterscheiden selbstständige
  Lösungen, Hilfe/erneuten Versuch, weiteren Übungsbedarf, unklare Bewertung und
  gegebenenfalls eigene Beiträge. Das sind Bearbeitungsnachweise, keine behaupteten
  Wissensprozente oder Notenprognosen.
- Handlungsbedarf und gespeicherte Lernzeit stehen auf breiten Flächen
  nebeneinander, mobil untereinander. Hilfewünsche und Aufträge haben konkrete
  nächste Aktionen. Der fachliche Übungsstand bleibt vor diesem Bereich sichtbar.
- Fächer sind flache lesbare Zeilen mit tatsächlichen Ergebnissen und direktem
  Zugang zu Themen und Antworten. Verlauf und spätere Festigung bleiben getrennt.
- Plan, Verlauf, Lernstand und Noten folgen denselben offenen Überschriften und
  passenden Farben. Notenaktionen und der lokale Fuxnoten-Import bleiben erhalten.

## Konto und Rechte

Eltern wählen zwischen **Konto & Geräte**, **Familie** und **Daten & Umfang**.
Google-Verknüpfung, Benachrichtigungen, eigene Sitzungen, Elternrechte, Einladungen,
Kinderangaben/Passwörter, Kindergeräte, Nutzungsgrenzen, Export und Kontolöschung
bleiben in ihrem bisherigen Berechtigungsmodell. Verwaltungsaktionen stehen unter
langen Namen statt daneben. Leseberechtigte erhalten keine neuen Schreibaktionen.
Auch die erste Kinderanlage ist an `canManage` gebunden.

Das Öffnen eines Abschnitts liest ausschließlich bestehende Endpunkte. Es startet
keine KI und verändert keine Daten. Familienbezogene Ladeschlüssel enthalten die
Familie. Fehlende optionale Zeit-/Zusammenfassungsdaten erscheinen als nicht
verfügbar; unvollständige Rundenzuordnungen erzeugen keine ungültigen Links.
Themenpfade werden einmal materialisiert dedupliziert, damit vorhandene Pfade
nicht gleichzeitig einen Leerzustand erzeugen.

## Recherche und gemeinsamer Beschluss

Die Kinder-, Eltern- und Adminagenten haben offizielle Produktdokumentationen
verglichen und ihre Vorschläge gegenseitig auf Ablenkung, Altersangemessenheit,
Lesbarkeit und überprüfbare Zustände geprüft. Die Nutzerwahl für Dark und Hell
bestimmt die zwei Varianten; die Informationsarchitektur folgt der Aufgabe.

- [Google Classroom: individuelle Arbeitsübersicht](https://support.google.com/edu/classroom/answer/9157286)
  beschreibt Statusfilter und das Öffnen einzelner Antworten aus einer Übersicht.
- [Google Classroom: kommende Arbeit](https://support.google.com/edu/classroom/answer/6020284)
  trennt eine begrenzte Startvorschau vom vollständigen Aufgabenbestand.
- [Google Classroom: Elternberichte](https://support.google.com/edu/classroom/answer/6388136)
  trennt fehlende/kommende Arbeit und Aktivität. Daraus übernehmen wir die
  Handlungsorientierung, nicht Googles abweichendes Rollenmodell.
- [ANTON: Elternkonto](https://anton.app/de/faq/ak900x/eltern-konto/)
  erklärt, dass kein spezielles Elternkonto existiert. Es ist daher kein belegtes
  Elterndashboard als Gestaltungsvorlage behauptet worden.
- [ANTON: Übungsverlauf](https://anton.app/de/faq/au93t6/uebungsverlauf-einsehen/)
  nennt Aufgaben, Fehler und Zeit als nachvollziehbare Details.
- [ANTON: Reportwerte](https://anton.app/de/faq/kaub37/report-durchschnittswerte/)
  grenzt Sterne ausdrücklich von Schulnoten ab.

Gemeinsamer Beschluss: Kinder erhalten eine klare nächste Lernaktion und einen
kompakten Fotoeingang; Eltern eine ehrliche Belegübersicht und konkrete Anliegen;
Administration eine Triageansicht. Gemeinsame Shell und Typografie, knappe lokale
Kontexte, keine Fake-XP, gesperrten Fantasielevels oder erfundenen Kurven. Große
Illustrationen gehören an geeignete Kindereinstiege/Leerzustände und verdrängen
weder Aufgaben/Formeln noch Elternzahlen. Öffentliche Dokumentation wurde gelesen;
eine eigenständige Browser-Screenshotabnahme der fremden Apps wird nicht behauptet.

## Prüfung

`parent_workspace_design_test.dart` prüft Kontoabschnitte in beiden Varianten bei
320/390/1440 px einschließlich doppelter Schrift, ausschließlich lesende Aufrufe,
lange Verwaltungsaktionen und fehlende optionale Metadaten. Weitere Regressionen
prüfen stabile Themen-Deduplizierung und ausdrücklich fehlende Zeitdaten. Die
bestehenden Elternübersichts-, Lernstands-/Noten- und Menütests bleiben relevant.
Tatsächliche Test- und Browserergebnisse werden im gemeinsamen Release festgehalten.
