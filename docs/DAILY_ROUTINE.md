# Täglicher Ablauf und machbare Lernportionen

Die Heftsammlung ist der Vorrat, keine tägliche Aufgabenliste. Die Kinderstartseite behält den Einstieg zu den heutigen Seiten auch bei offenen älteren Einheiten. „Heute keine neuen Seiten“ gilt nur für den lokalen Kalendertag; spätere Fotos bleiben möglich. Das setzt weder Lernziele noch Zeitgrenzen außer Kraft.

## Vorbereitung nach der Schule

Fotos werden zunächst privat gespeichert. Die ausdrücklich beauftragte Vorbereitung arbeitet anschließend serverseitig weiter, auch wenn das Kind die App verlässt. Erkennung, Quellenprüfung und Paketvorbereitung bleiben getrennt: Erkannte Texte werden nicht heimlich bestätigt. Unsichere Stellen müssen vor Aufgaben aus diesen Quellen geprüft werden. Das Kind beginnt die Lernrunde selbst; ein fertiger Hintergrundauftrag startet keine Einheit.

Fehlende heutige Lernzeit verhindert nicht, geprüften Stoff für spätere Lerntage zu speichern. Ein zusätzlicher KI-Auftrag wird dafür nicht benötigt. Ungeprüfte oder unleserliche Seiten bleiben als solche erkennbar. Bereits gespeicherte Antworten werden beim Ergänzen oder Neuplanen nicht überschrieben.

## Planung

`daily_planner.py` berechnet einen Vorschlag für sieben Kalendertage aus offenen Einheiten, noch nicht erzeugten Etappen, Elternaufträgen und bekannten Wiederholungen. Das Lesen erzeugt keine Jobs, Kostenreservierungen oder gespeicherten Plandaten. Neue Seiten, Antworten, Elternänderungen und Pausen passen den Vorschlag an.

- Tages- und Kalenderwochenlimits bleiben erhalten. Standardwerte sind 20 Minuten pro Tag, 100 pro Woche und höchstens 15 Minuten am Stück, mit 5 Minuten Pause. Eltern können diese Werte ändern.
- Eine erledigte Lernportion zählt mit ihrer geschätzten Dauer zum Ziel. Schnelles Beantworten füllt den Tag dadurch nicht ständig mit neuen Etappen. Gemessene Aktivität wird separat als Näherung angezeigt; geplante Minuten sind keine behauptete Lernzeit.
- Elternaufträge behalten ihre Verbindlichkeit, Starttermine und Fristen. Nicht passende Fristen erzeugen einen Hinweis, keine automatische Änderung des Lernziels oder Verlängerung des Tages.
- Angefangene Übungen, fällige Abrufproben, neuer Stoff und ältere Quellen werden innerhalb des Budgets berücksichtigt. Fächer werden abgewechselt; Reihenfolge bleibt innerhalb eines Fachs erhalten. Verschiedene Fächer eines Schultags dürfen unterschiedliche Lerntage haben.
- Ein größeres Paket besteht aus mehreren Etappen. Eine vorbereitete Einheit kann pausiert und an einem anderen Tag fortgesetzt werden. Weitere Aufgaben entstehen erst durch einen begrenzten ausdrücklichen Vorbereitungsauftrag.
- Es gibt keine Beschränkung auf die letzten 30 gespeicherten Schultage in der Planung. Material außerhalb des Siebentagevorschlags bleibt erhalten. Der Elternbereich nennt zu umfangreiche Vorgaben, damit gemeinsam Schwerpunkte gewählt werden können.
- Verpasste Tage erhöhen das Tagesziel nicht. Ferien/Krankheitspausen und lernfreie Tage gelten auch für vorhandene Einheiten. Die Startseite holt zurückgestellten Stoff an solchen Tagen nicht als freiwillige Ersatzaufgabe nach vorn.

Der Vorschlag garantiert nicht, dass jeder vorhandene Stoff bis zu einem bestimmten Tag sicher beherrscht ist. Zusätzliche Hilfen und Abrufproben hängen von gespeicherten Antworten ab. Fehlende Nutzung belegt kein fehlendes Verständnis; bestätigte Beherrschung bleibt an die bestehenden unabhängigen Prüftage gebunden.
