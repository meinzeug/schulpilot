# Synthetische KI-Qualitätsprüfung

Der versionierte Katalog in `backend/schulpilot/evaluation_corpus.py` enthält acht ausschließlich künstliche Vorlagen: Englisch/Tiere, Deutsch/Nomen und Verben mit ausdrücklich notierter Hausaufgabe, Biologie/Pflanzenteile, Mathematik/Rechtecke, eine nicht vertrauenswürdige Randanweisung, schräge Druckschrift, ein weichgezeichnetes Bild und eine vollständig unleserliche Unterrichtsvorlage. Schräge Druckschrift ersetzt keine echte Handschriftenprüfung.

`scripts/evaluate_ai.py` verwendet ausschließlich diese Konstanten. Keine Fotos, Namen, Antworten oder frei eingegebenen Operator-Texte werden in den Testpfad übernommen. Ohne `--live` werden nur Katalog/Bilder vorbereitet; dabei werden keine KI-Aufrufe als durchgeführt gezählt.

```bash
.venv/bin/python scripts/evaluate_ai.py \
  --output artifacts/eval-corpus.json --images artifacts/eval-images

.venv/bin/python scripts/evaluate_ai.py --live \
  --model dots-studio/dots-3-note-preview:free --upstream atlas-cloud/fp8 \
  --function extract --case eval-english-v1 --case eval-german-v1 \
  --max-calls 2 --output artifacts/eval-vision.json
```

Der ausdrücklich autorisierte Schlüssel wird aus `~/or.txt` nur in den Prozessspeicher gelesen. Vor jedem Aufruf werden der konkrete kostenlose Endpunkt und seine Fähigkeiten geprüft; Modell/Upstream sind fest, Preisgrenze 0, kein Ersatzmodell und keine automatische Wiederholung. Die Operator-Tests haben einen eigenen Bericht mit Aufrufanzahl, Dauer, Modell/Upstream, Tokens und bekannten/unbekannten Kosten. Sie gehören keinem echten Familienkonto und ändern keine Tarifberechtigungen.

## Tatsächlicher Lauf am 14.10.2026

- Erster Bildlauf: Englisch, Deutsch, Biologie und die Randanweisung strukturell gültig; erwartete Fach-/Inhaltsanker und Hausaufgabenkennzeichnung in diesen vier Vorlagen getroffen. Die Randanweisung änderte das Fach nicht. Die unleserliche Seite wurde wegen leerer Pflichtfelder verworfen.
- Erster Aufgabenlauf: vier strukturell gültige Einheiten für Englisch, Deutsch, Biologie und Geometrie. Bei der manuellen Durchsicht fiel in Deutsch eine unberechtigte Zuschreibung zu einer „Hausaufgaben-Beispielangabe“ auf. Damit war dieser Fall pädagogisch nicht abgenommen, obwohl das Schema gültig war.
- Daraufhin wurde ein eigener validierter Lesbarkeitszustand eingeführt. Ein neuer ausdrücklicher Bildlauf erkannte die unleserliche Seite als `unreadable` mit Hinweis und ohne erfundenen Unterrichtsstoff; weiche und schräge Druckvorlagen wurden als lesbar erkannt.
- Die Quellenaussage im Aufgabenprompt wurde präzisiert. Ein neuer ausdrücklicher Deutschlauf enthielt die falsche Hausaufgabenzuschreibung nicht mehr; eine kleinere grammatische Ungenauigkeit blieb sichtbar. Fachliche Antworten der betrachteten Beispiele stimmten mit dem vorgegebenen Stoff überein.

Zusammen 13 ausdrückliche Inferenzversuche: 12 strukturell angenommen, ein früherer Versuch verworfen. Die zwölf angenommenen Aufrufe meldeten Kosten 0; für den verworfenen Aufruf bleiben die Kosten unbekannt. Die zwei gesonderten geschützten Routingprüfungen aus [APPROVALS.md](APPROVALS.md) sind nicht in diesen 13 Inferenzversuchen enthalten.

Die privaten lokalen JSON-Berichte unter `artifacts/eval-*.json` enthalten die künstlichen Ausgaben zur manuellen Prüfung und sind nicht versioniert. Ankerabdeckung und Schemagültigkeit sind Hilfsmetriken, keine allgemeine Aussage über Richtigkeit, Lernerfolg oder Modellzuverlässigkeit. Keine Nutzerstudie, echte Handschriftenabnahme oder Notenprognose behauptet.

## Abnahme für einen Familientest

Auf echten Android-Geräten mit künstlichem Material Kamera, Netzverlust, Speicherknappheit und Wiederaufnahme prüfen. Nach Behebung des geschützten Routingblockers eine kleine begleitete Familienrunde durchführen: Kann ein Kind den Assistenten selbstständig bedienen, stimmen Quellen/Übungen, passen Dauer und Schwierigkeit, und verstehen Eltern den tatsächlichen Unterstützungsbedarf? Beobachtungen und Probleme dokumentieren; keine erfundenen Erfolgswerte.
