# Darstellungskatalog für die Aufgabenerstellung

Nutzerauftrag23.10.2026: Die KI soll bei der Erzeugung wissen, welche
Darstellungen und Interaktionen Schulpilot tatsächlich ausführen kann.
Ein Grafikname allein genügt nicht: Fach, Datenvertrag, Fragetyp und
Offenlegungsstufe entscheiden gemeinsam über die verwendbare Darstellung.

Die servereigene Auswahlhilfe liegt in
[presentation_capabilities.py](../backend/schulpilot/presentation_capabilities.py).
`subject_profiles`, `question_types`, `answer_ui`, `max_blocks`, `use_for` und
`local_interactions` werden nach dem endgültigen Schema-Zuschnitt in
`content_context` übergeben. Nicht erreichbare Schemadefinitionen erweitern den
Katalog nicht. Die normale Heftaufgabe leitet das Fach auch aus `material.subject`
ab; ein ausdrücklich engerer Auftrag bzw. die ausgewählten Paketgruppen bleiben
vorrangig.

Der gemeinsame Einstieg ist `providers.request_provider`; Fachprofile und
Darstellungsregeln liegen in `subject_content`. Der Erzeugungsauftrag erhält
nur die zum konkreten Fach und endgültigen Antwortschema passenden Fähigkeiten.
Der Katalog beschreibt Eingaben für die KI, keine zusätzlichen Eigenschaften
im strikt validierten Ausgabeformat. Er ersetzt weder Quellenprüfung noch
mathematische Planung oder das technische Schema.

## Auswahl nach Fach

Ab1.27.0+99 besitzen alle24Profile zusätzlich `process_graph`, `process_cycle`,
`scene` und den ausschließlich belegten Textvergleich `text_probe`.
Die folgende Liste stammt aus den tatsächlichen Backendprofilen:

| Fach | Weitere Darstellungen |
| --- | --- |
| Mathematik | `fraction`, `triangle`, `function_graph`, `data_plot`, `function_curve` |
| Deutsch | `sentence`, `speech` |
| Englisch | `forms`, `timeline`, `picture_words` |
| Französisch | `forms`, `picture_words` |
| Spanisch | `forms`, `picture_words` |
| Latein | `forms`, `picture_words` |
| Deutsch als Zweitsprache | `forms`, `picture_words`, `sentence`, `position` |
| Biologie | `plant`, `food_chain`, `forms`, `cell`, `data_plot` |
| Geographie | `compass`, `water_cycle` |
| Geschichte | `timeline`, `statements` |
| Physik | `reflection`, `circuit`, `function_graph`, `data_plot`, `circuit_network`, `function_curve` |
| Chemie | `particles`, `filtration`, `molecule`, `data_plot` |
| Ethik | `perspectives`, `statements` |
| Gemeinschaftskunde | `bar_chart`, `statements` |
| Informatik | `flowchart`, `place_values`, `logic_table`, `data_plot` |
| Kreativität und Bewegung | `movement`, `pattern` |
| Kunst | `colour_wheel`, `layers` |
| Lerntechniken | `flashcard`, `mindmap` |
| Musik | `notes`, `keyboard` |
| Religion | `traditions`, `perspectives` |
| Sachunterricht | `senses`, `seasons` |
| Sport | `movement`, `fairplay` |
| Technik | `gears`, `forces`, `technical_drawing`, `circuit_network`, `logic_table`, `function_graph`, `data_plot`, `function_curve` |
| Wirtschaft | `money`, `statements` |

Diese Liste ist keine Stoff-/Lehrplanzuweisung nach Klassenstufe. Eine
Darstellung wird nur gewählt, wenn die bestätigte Quelle ihre benötigten Daten
wirklich enthält und sie das konkrete Lernziel erklärt. Ein Profil darf nicht
auf die vereinigten Fähigkeiten anderer Fächer eines Pakets zugreifen.

## Was sich tatsächlich bedienen lässt

| Element | Daten und Verhalten |
| --- | --- |
| `function_graph` | Belegtes Polynom bis Grad2, Koeffizienten `[a,b,c]`; lokale Punktwahl auf x=−4…4 in0,1-Schritten mit berechnetem Y. |
| `data_plot` | Zwei bis acht originale X/Y-Paare; Auswahl ausschließlich dieser Messpunkte, keine erfundenen Zwischenmesswerte oder Regression. |
| `logic_table` | Ausschließlich UND/ODER/NICHT; A/B-Schalter, AusgabeY und aktive Tabellenzeile. |
| `process_graph` / `process_cycle` | Vollständige belegte gerichtete Beziehungen; optional lokale schrittweise Hervorhebung. Ein Kreislauf braucht die belegte Abschlusskante. |
| `scene` | SceneV1: bis12Objekte,8Schritte und24Pfeile je Schritt; Formen, lokale Slots und belegte Texte, bewusster Start/Pause/Regler, direkte Schrittwahl, wählbarer Ausgangs-/Zielvergleich und rein beschreibende Änderungsliste. Keine physikalische Simulation. |
| `type=match` | Zuordnung innerhalb der vorhandenen Antwortfläche per Langdruck/Drag oder Tippen/Tastatur; Drop ändert nur den Entwurf, explizites Prüfen bewertet. |
| `type=grouped` | Zwei bis vier stabile Text-/Auswahlfelder, auch gemischt; bewusste gemeinsame Prüfung als ein Versuch, serverseitige Feldrückmeldungen. Eigener versionierter JSON-Antwortvertrag, keine Semikolon-Zweckentfremdung. |
| `text_probe` | Zwei bis acht Textgruppen in zwei bis vier vollständig wörtlich belegten Reihenfolgen. Lupe, Kontextmarkierung, feste Gruppenidentität, Positionsvergleich und direkter Textvergleich. Keine freie Grammatikbewertung. |
| Andere Fachgrafiken | Statische Fachmodelle/Begriffsfolgen und Zoom. `function_curve` besitzt keinen Explorer; `speech` erzeugt kein Audio, `keyboard` kein spielbares Instrument und `flashcard` keinen frei programmierbaren Flip. |

„Erkunden“ für Funktion, Messdaten und Logik steht ausschließlich in bereits
geöffneten `hint1/2/3`- oder `solution`-Blöcken mit gültigem Kontokontext zur
Verfügung. Die KI erzeugt die belegten Daten, die App ergänzt die Bedienung.
Es gibt keine frei definierbaren Regler, Ereignisse, Dragziele, 3D-Objekte,
Bild-/Audiogenerierung oder ausführbaren SVG-/HTML-/Programmcodes.

## Aufgaben und Offenlegung

`choice` ist eine einzelne Radioauswahl. `gap` und `short` sind freie Eingaben,
keine beliebigen Dropdown-Lückentexte. `match` ist nur dort verfügbar, wo das
endgültige Schema diesen Typ zulässt. Kompakte OpenRouter-Runden können zwei bis
vier ausdrücklich wörtlich belegte eindeutige Paare verwenden; fachliche
Codex-Pakete behalten `choice/short`. Feste geplante Rechenaufgaben bleiben
an ihre bestehende Planung und Lösung gebunden.

Ab1.27.0+99 ist `grouped` ein eigenständiger zusätzlicher Fragetyp, nur wenn das
endgültige Schema ihn wirklich zulässt. Jedes Feld braucht einen ausdrücklich
belegten Zusammenhang wie Beschriftung:Antwort in einer einzigen Originalquelle.
Unbekannte freie Formulierungen bleiben ungeklärt; Groß-/Kleinschreibung und
mathematische Sonderzeichen werden nicht pauschal gleichgesetzt. Optionen,
Feld-/JSON-Längen und Quellrevisionen bleiben begrenzt. Codex-Sachpakete und
Etappen sowie feste Mathematik-/Reasoningpfade erweitern ihre Typen nicht.
Ältere Clients ohne `grouped-v1` müssen für solche Runden aktualisiert werden.

`text_probe` öffnet ausschließlich in einer bereits erlaubten Hilfe/Lösung.
Eine vollständige Reihenfolge muss wörtlich belegt sein; keine erfundenen
falschen Gegenbeispiele oder versteckten Grammatikurteile in Titel/Alttext.
Die Bedienung beschreibt Textpositionen, keine allgemeine Sprachkorrektheit.
Feldlösungen, Belegzitate und private Variantenzitate verlassen den normalen
Clienttransport nicht. Rundenfilter und Modellvergleich sind lokale Ansichten,
keine neue Bewertung, Freischaltung oder zusätzliche KI-Anfrage.

`given` ist schon vor einer Antwort sichtbar. Vollständige richtige Zuordnungen,
Zielwörter, Ergebnisse und erklärende Lösungsschritte gehören in eine passende
geöffnete Hilfe oder Lösung. Eine Scene hat mit sämtlichen Schritten genau eine
Freigabestufe; ein Regler öffnet keine spätere Stufe. Private äußere und
Schritt-Quellenbelege werden vor öffentlicher Ausgabe entfernt.

Neue Praxis wird in den vorhandenen autorisierten Unit-/Paketpfaden geplant.
Gespeicherte Hinweise/Erklärungen werden nur projiziert. Reine Rückblicke,
Entscheidungen, Buddygespräche und Sprachprojektschemas ohne `presentation`
erhalten keinen zusätzlichen Grafikauftrag. Keine neuen Provideraufrufe,
Dienste, Reservierungen oder erhöhten Token-/Kostenlimits durch den Katalog.

Prüfstand und Grenzen:
[INTERACTIVE_LEARNING_2026_10_23.md](INTERACTIVE_LEARNING_2026_10_23.md),
[RELEASE_97_2026_10_23.md](RELEASE_97_2026_10_23.md).

Die konkrete20-Punkte-Abnahme steht in
[LEARNING_ELEMENTS_20_2026_10_23.md](LEARNING_ELEMENTS_20_2026_10_23.md);
Veröffentlichungsstand und Grenzen in [RELEASE_99_2026_10_23.md](RELEASE_99_2026_10_23.md).

Die Runde1.28.0+100 ergänzt lokale Lese- und Eingabewerkzeuge für bereits
vorhandene Daten: beschriftete Options-/Versuchsvergleiche, Abschnittssuche,
Tabellenzeilenansicht, Codeumbruch, Formelansicht und eigene Zeichen-/Cursorhilfen.
Das erweitert keinen KI-Ausgabevertrag und verlangt keine neue Generierung.
Suche und Vergleiche gelten nur für bereits berechtigt sichtbare Inhalte;
Vorschauen eigener Antworten bewerten nichts. Einzelne Funktionen und deren
Prüfstand stehen in [IDEAS_100_2026_10_23.md](IDEAS_100_2026_10_23.md).
