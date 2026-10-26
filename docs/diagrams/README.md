# Eigene Ablaufdiagramme

Die vier Diagramme enthalten ausschließlich allgemeine Produktabläufe und keine privaten Daten. Mermaid-Dateien beschreiben die Abläufe textuell; Graphviz-Dateien sind die reproduzierbare Quelle der eingebetteten SVGs. Die beiden Fassungen zeigen dieselben fachlichen Beziehungen, nicht dieselbe automatische Positionierung.

| Diagramm | Inhalt |
| --- | --- |
| `learning-flow` | Foto, Quellenprüfung, Teilaufträge und echte Übung |
| `learning-controller` | Kontext, lokale Entscheidung und ausdrücklich reservierter neuer Modellauftrag |
| `learning-plan` | Elternvorgaben; geplante, erzeugte und bearbeitete Aufgaben; getrennte Mindestzeit |
| `learning-evidence` | Antwortnachweise, Hilfe, spätere Abrufe und ausgeschlossene Scheinbelege |

Lokal mit vorhandenem Graphviz neu rendern:

```bash
dot -Tsvg docs/diagrams/learning-flow.dot -o docs/diagrams/learning-flow.svg
dot -Tsvg docs/diagrams/learning-controller.dot -o docs/diagrams/learning-controller.svg
dot -Tsvg docs/diagrams/learning-plan.dot -o docs/diagrams/learning-plan.svg
dot -Tsvg docs/diagrams/learning-evidence.dot -o docs/diagrams/learning-evidence.svg
```

Kein Browser, Netzwerkdienst, Bitmapgenerator oder Modellaufruf wird benötigt. Die SVGs enthalten Text und Vektoren, keine externen Bilder oder ausführbaren Inhalte. Die manuelle/automatische Quellenprüfung ist vom Bereitstellungsstand abhängig; die README kennzeichnet den Kandidaten bis zur dokumentierten Integration ausdrücklich.
