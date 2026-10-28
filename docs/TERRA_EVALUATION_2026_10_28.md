# Terra: isolierte Kandidatenprüfung am 28.10.2026

Der Betreiber hat eine Prüfung von `openai/gpt-6.1-terra` als Ersatz der
Sol-Route beauftragt. Die Produktion blieb bei der Prüfung unverändert. Das
Kandidatenskript verwendet eine eigene SQLite-Datenbank, feste künstliche
Vorlagen und den bestehenden Reservierungs- und Abrechnungsweg. Der zunächst
auf 0,25 USD begrenzte Gesamtdeckel wurde auf ausdrücklichen Betreiberauftrag
für den isolierten Test zunächst auf 0,50 und nach dem zusätzlichen ausdrücklichen
Auftrag auf 2,00 USD erhöht. Produktion und PostgreSQL behalten
die bisherige Grenze. Die Kandidatenroute bleibt ausdrücklich
`evaluated=false` und `under13_approved=false`; eine Bildkostenschätzung der
Produktionsroute wird nicht übernommen oder vorzeitig freigegeben.

OpenRouter führte `azure/eu` für Terra im authentifizierten ZDR-Katalog auf;
die Endpoint-Metadaten meldeten den Status 0, Bildfähigkeit, Reasoning und
strukturierte Ausgabe. Der verwendete Endpoint meldete zum Prüfzeitpunkt
1,20 USD pro Million Eingabetokens und 6,00 USD pro Million Ausgabetokens.
Metadaten belegen keine tatsächliche Eignung oder vollständige Datenschutzprüfung.
Die [offizielle Beschreibung der Bildverarbeitung](https://developers.openai.com/api/docs/guides/images-vision)
erläutert modellabhängige Bildtokenisierung. Sie wurde für diese Prüfung gelesen;
die aufgeführten Grenzen wurden nicht ohne entsprechenden Endpunktnachweis als
garantierte Azure/EU-Abrechnung von Terra übernommen.

| Feste Vorlage | Ergebnis | Gemeldete Kosten |
| --- | --- | ---: |
| Fotoabschrift, Bruchseite | Vor Versand durch konservative Kostenprojektion gestoppt | 0 USD |
| Fotoabschrift, kleinere Englischvorlage | Erfolgreich; alle sechs festgelegten Textanker erkannt | 0,005364 USD |
| Fotoabschrift, größere künstliche Bruchseite mit 0,25 USD Einzelreservierung | Erfolgreich; Text und drei feste Anker korrekt erkannt | 0,006954 USD |
| Zehn größere künstliche Seiten aus fünf Fächern | Alle zehn vor Versand von der konservativen Kostenprojektion gestoppt; keine OCR-Bewertung möglich | 0 USD |
| Dieselben zehn größeren Seiten mit 0,75 USD Einzelreservierung | Alle zehn verarbeitet; dokumentierte Textanker gefunden. Ein Bruch wurde korrekt in LaTeX statt als `1/5` geschrieben und gesondert geprüft | 0,069812 USD |
| Bruch-Lerneinheit | Transport und bestehende Inhaltsprüfung erfolgreich; eine Bruchgrafik und zwei Aufgaben erzeugt | 0,021143 USD |
| Bruch-Lernpaket | Transport und bestehende Inhaltsprüfung erfolgreich; eine Einheit mit zwei Aufgaben erzeugt | 0,011904 USD |

Bekannte Gesamtkosten: 0,115177 USD. Die Ergebnisse zeigen nur, dass diese
künstlichen Einzelfälle funktioniert haben; die Textanker allein prüfen weder
jedes Zeichen noch die allgemeine fachliche Qualität. Die sichere, konservative
Kostenschätzung blieb unverändert; sie benötigte für die zehn Seiten höhere
Reservierungen. Für den Produktionswechsel fehlen insbesondere die reguläre
Freigabe der Kinderroute und die Prüfung der weiteren betroffenen Funktionen.
Schutzprüfungen
dürfen dafür nicht umgangen werden. Frühere Antworten und Aufträge bleiben
unverändert; es wurde kein neuer Auftrag für Juna ausgelöst.

Aufruf mit einem eigenen geschützten Verzeichnis außerhalb von Git:

```sh
.venv/bin/python scripts/evaluate_openrouter_mix.py --terra-candidate --directory /path/to/private-evaluation
.venv/bin/python scripts/evaluate_openrouter_mix.py --terra-candidate --terra-full-photo --directory /path/to/private-evaluation
.venv/bin/python scripts/evaluate_openrouter_mix.py --terra-candidate --terra-full-photo --full --directory /path/to/private-evaluation
```

Der private Bericht enthält ausschließlich künstliche Inhalte und bleibt
außerhalb von Git. Produktionsgeheimnisse und Kinderinhalte gehören nicht dorthin.
