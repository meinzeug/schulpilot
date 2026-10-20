# Kinder-Lerncockpit: gemeinsame Gestaltung vom 20.10.2026

## Entscheidung nach Produktrecherche

Drei Designagenten haben unter Leitung des Hauptagenten die Kinder-, Eltern- und
Betreiberansichten miteinander abgestimmt. Der Betreiber hat zuletzt zwei
vollständige Erscheinungsbilder derselben Cyberpunk-Anwendung beauftragt: dunkel
und hell. Eine bloße Umfärbung der bisherigen dunklen Einstiegskarten mit weißen
Folgekarten wurde ausdrücklich verworfen.

Gemeinsame Struktur:

- Kinder erhalten eine **Lernstation** mit ihrer tatsächlich nächsten Runde und
  genau einer Hauptaktion. Ein kompakter Fotoeingang bleibt zusätzlich sichtbar.
- Eltern erhalten nachvollziehbare Übungsbelege, fachlichen Überblick und
  konkreten Handlungsbedarf. Betreiber erhalten eine Arbeitsfläche für reale
  Betriebsprobleme. Die Kinderfigur steht nicht vor Berichten oder Formularen.
- Es gibt eine globale Navigation. Lokale Reiter wechseln den Arbeitskontext;
  sie wiederholen nicht die gesamte Hauptnavigation.
- Violett bezeichnet Hauptaktionen, Cyan führt und kennzeichnet Informationen.
  Der aktuelle Zustand bleibt zusätzlich ausgeschrieben oder mit Symbolen
  erkennbar. Lesetexte, Aufgaben und wissenschaftliche Darstellungen bleiben ruhig.

### Verwendete Primärquellen und Grenzen der Übertragung

[Duolingos offizieller Produktrundgang](https://blog.duolingo.com/duolingo-101-how-to-learn-a-language-on-duolingo/)
zeigt einen klar geführten Lernpfad, kurze Einheiten und gezielte Übungen für
Wiederholung und frühere Schwierigkeiten. Übernommen wird die eindeutige nächste
Handlung. Herzen, Wettbewerbsranglisten, künstliche Währungen und Streakdruck
werden nicht übernommen.

[Der offizielle Khan-Kids-Einstieg](https://khankids.zendesk.com/hc/en-us/articles/360006764812-Parent-Guide-Using-Khan-Academy-Kids-at-Home)
trennt einen großen Lernstart, die frei durchsuchbare Bibliothek und eine
Helferfigur. Die
[Zielgruppe von Khan Academy Kids](https://en.khanacademy.org/kids)
ist zwei bis acht Jahre. Deshalb wurde eine vollständige Vorschul-Spielwelt für
Schulpilot Klasse 1–13 abgelehnt. Die Figur hilft bei Einstieg und Orientierung;
sie verdrängt keine Frage oder Formel und spricht nicht automatisch.

Die Agenten haben folgende Gegenargumente ausdrücklich berücksichtigt: keine
lange dekorative Route ohne tatsächlich vorbereitete Schritte; keine gesperrten
Fantasielevel; frei wählbare Hefte und Wörter bleiben erreichbar; kein Maskottchen
vor jeder Liste; Lernstart und Fotoeingang müssen auf kleinen Bildschirmen
praktisch erreichbar bleiben. Die Quellen sind öffentliche Produktdokumentation,
keine eigene Anmeldung oder Wirksamkeitsstudie. Einzelne externe Bildabrufe waren
nicht verfügbar; daraus wird keine native Sichtabnahme der Fremdprodukte behauptet.

## Umsetzung

- `app/lib/child_today_widgets.dart`: Lernstation, ursprüngliche eigene
  Cyber-Buchdrohne als Illustration, kompakter Scan-Dock und flache Anzeige der
  tatsächlich gespeicherten Lernzeit. Plan und Nachrichten öffnen gezielt ihre
  eigenen Ansichten statt zusätzlicher Kartenstapel auf Heute.
- `app/lib/child_section_ui.dart`: offene Bereichsköpfe, einheitliche Kontextreiter
  und Aktionsflächen. Die lokal gebündelte Figur verwendet
  `assets/illustrations/learning-companion.png`; ein lokaler Zeichenfallback hält
  die Oberfläche auch bei einem fehlgeschlagenen Asset lesbar.
- Lernen zeigt bestehende Themen als offene Gruppen. Wörter verwenden deutlich
  erkennbare Karteikarten mit weiterhin bewusstem Aufdecken. Konto trennt Geräte,
  Mitteilungen und App-Informationen. Nachrichten trennen Postfach, Wünsche und
  bereits Besprochenes; gesendete und empfangene Beiträge sind ausgerichtet.
- Alle neuen Flächen und Textfarben verwenden `context.palette`. Dunkel und hell
  haben eigenständige Flächen- und Textwerte, dieselben Funktionen und dieselbe
  Navigation. Nunito und Space Grotesk sind lokal gebündelt; funktionale
  Formelschriften bleiben erhalten.

Die Illustration ist Dekoration, kein Lernbeleg. Es gibt keine erfundenen Punkte,
Kompetenzprozente oder automatisch wachsenden Level. Geplante Runden,
Antwortversuche, Unterstützung und Lernzeit bleiben getrennte Fakten.

Die vorhandene `learning_guidance` verfeinert den Einstieg nur für dieselbe aktive
oder pausierte Hauptrunde. Eine ungelesene Antwort bleibt zuerst sichtbar. Das
Öffnen der Startseite erzeugt weder Aufgaben noch KI-Aufträge. Elternkontakt
bleibt optional und asynchron; nach einer Nachricht kann das Kind weiterlernen.

## Prüfung

Die Widgetregressionen in `child_home_usability_test.dart`,
`child_routine_entry_test.dart`, `child_sections_design_test.dart` und
`adaptive_learning_room_test.dart` umfassen kleine Bildschirme, große Schrift,
beide Farbvarianten, gerenderte Reiterkontraste, Quellen-/Rundenzuordnung,
Feedback-Wiederaufnahme und bewusst ausgelöste Generierung. Die zentrale
Abschlussprüfung dokumentiert die tatsächlich ausgeführten Test- und
Browserergebnisse; diese Entwurfsnotiz behauptet dafür keinen vorweggenommenen
Erfolg.
