# Kinderstartseite: aufgeräumter Tagesbereich

Der zusätzliche Betreiberauftrag vom22.10.2026 ersetzt den unteren Heute-Bereich
mit seiner verstreuten Mischung aus Zeitzeile, Outlinebuttons, Textlinks und
Androidbanner. Diese Neugestaltung wird nicht zusätzlich in die300er-Matrix
aufgespalten oder dort erneut gezählt.

`ChildTodayTools` fasst die sekundären Werkzeuge in einer ruhigen Fläche zusammen.
Oben steht `ChildTodayProgress`: tatsächlich gespeicherte Lernzeit, unverändertes
Mindestziel und echter Rundenstand. Die gesamte Zeitfläche öffnet die vorhandenen
Details. Zeitfortschritt bleibt von fachlichen Kompetenznachweisen getrennt.

Darunter öffnen vier vollständige Touchkarten die vorhandenen Wege: Mein Plan,
Nachrichten & Wünsche, Ich brauche Hilfe und Meine Heftseiten. Eine vorhandene
Elternnachricht erscheint als Vorschau innerhalb der Nachrichtenkarte. Es gibt
keine zweite konkurrierende Nachrichtenkarte und keine losen Aktionsgruppen.
Bei wenig Breite oder großer Schrift wechseln die Kacheln ohne feste Höhen in
eine Spalte. Die bestehende Hauptlernaktion bleibt darüber erhalten.

„Was sehen meine Eltern?“ bleibt über eine48px-Infoaktion erreichbar; ihr
kontogebundener Dialog verschwindet beim Zugang-/Familienwechsel. Die vorhandenen
Routen-, Quellen- und Sitzungsprüfungen bleiben erhalten. Native Tastatur- und
Semantikaktionen verwenden dieselben kontrollierten Tapziele.

Der Kinderbereich zeigt auf Heute keinen Downloadbanner mehr. Der reguläre
Web-Download der signierten Direct-APK bleibt ausdrücklich unter Konto → Geräte.
Eltern-/öffentlicher Download und der Play-Kanal werden dadurch nicht verändert.
`WorkspaceShell` lädt für die Kinderstartseite auch keine Releaseabfrage mehr.

## Nachweise

- Nativer gezielter Integrationsblock111/111 grün:
  `artifacts/today-redesign/targeted-native-verified.log`.
- Echter isolierter Chrome-Widgetrunner9/9 grün:
  `artifacts/today-redesign/targeted-chrome.log`.
- Unabhängige fünf Fälle für320px/200%, beide Paletten,48px-Trefferflächen,
  tatsächliche Semantik-Taps und Tab/Enter samt gemaltem Fokusrahmen grün:
  `artifacts/today-redesign/independent-review.log`.
- Zwei lokale Rendererbilder mit echten App- und Iconschriften grün und von
  zwei Agenten sowie Root visuell geprüft. Werte sind ausdrücklich künstliche
  Testdaten: `tools-dark.png` und `tools-light.png` im selben Artefaktverzeichnis.
- Vollständige eingefrorene Flutter-Regression: 2.404 bestanden, zehn
  plattformgebundene Fälle übersprungen
  (`artifacts/ux90/flutter-today-release-final.log`). Die zunächst entdeckte
  kurzzeitige Downloadkarte beim Abmelden ist durch einen Konto-Guard behoben;
  der unveränderte strenge Logoutfall und ein eigener Zwischenzustandstest sind
  grün. Die abschließende statische Analyse meldet keine Befunde.
- Dieselben Abmelde-/Downloadgrenzen zusätzlich im echten Chrome-Runner:
  vier von vier bestanden (`logout-release-chrome.log`).

Diese synthetischen Nachweise ersetzen keine physische Android- oder
Screenreaderabnahme und keine Studie mit Kindern. Der saubere Quellcommit,
Build und die Veröffentlichung folgen im Releaseprotokoll. Der GitHub-Lauf
39811469793 startete wegen der bestehenden Kontosperre zur Abrechnung keine
Prüfjobs; gehostete grüne CI wird nicht behauptet.
