# Täglicher Ablauf und machbare Lernportionen

Die Heftsammlung ist der Vorrat, keine tägliche Aufgabenliste. Die Kinderstartseite behält den Einstieg zu den heutigen Seiten auch bei offenen älteren Einheiten. „Heute keine neuen Seiten“ gilt nur für den lokalen Kalendertag; spätere Fotos bleiben möglich. Elterliche Lernziele bleiben erhalten; freiwilliges Weiterlernen hat keine zeitliche Obergrenze.

## Vorbereitung nach der Schule

Fotos werden zunächst privat gespeichert. Die ausdrücklich beauftragte Vorbereitung arbeitet anschließend serverseitig weiter, auch wenn das Kind die App verlässt. Erkennung, Quellenprüfung und Paketvorbereitung bleiben getrennt: Erkannte Texte werden nicht heimlich bestätigt. Unsichere Stellen müssen vor Aufgaben aus diesen Quellen geprüft werden. Das Kind beginnt die Lernrunde selbst; ein fertiger Hintergrundauftrag startet keine Einheit.

„Stimmt, weiter“ bestätigt eine geprüfte Seite direkt, ohne zusätzliche Checkbox. Erkennungshinweise bleiben sichtbar. Eine noch unbestätigte eigene Seite lässt sich mit „Seite löschen“ und einer kurzen Rückfrage entfernen. Anschließend erscheint die nächste ungeprüfte Seite; nach der letzten heutigen Seite wieder die Fotoauswahl. Bereits bestätigte Quellen können Kinder dabei nicht löschen.

Fehlende heutige Lernzeit verhindert nicht, geprüften Stoff für spätere Lerntage zu speichern. Ein zusätzlicher KI-Auftrag wird dafür nicht benötigt. Ungeprüfte oder unleserliche Seiten bleiben als solche erkennbar. Bereits gespeicherte Antworten werden beim Ergänzen oder Neuplanen nicht überschrieben.

## Planung

`daily_planner.py` berechnet einen Vorschlag für sieben Kalendertage aus offenen Einheiten, noch nicht erzeugten Etappen, Elternaufträgen und bekannten Wiederholungen. Das Lesen erzeugt keine Jobs, Kostenreservierungen oder gespeicherten Plandaten. Neue Seiten, Antworten, Elternänderungen und Pausen passen den Vorschlag an.

- Die bisherigen Minutenwerte sind Mindestziele: standardmäßig 20 Minuten am Lerntag und 100 Minuten je lokaler Kalenderwoche. Eine Runde von 15 Minuten und eine Pause von 5 Minuten sind Empfehlungen. Weder Zielerreichung noch empfohlene Runden-/Pausendauer stoppen eine Übung. Eltern können die Zielwerte weiterhin festlegen.
- Nur gespeicherte aktive Sekunden erfüllen das Mindestziel. Eine auf 20 Minuten geschätzte, in 12 aktiven Minuten erledigte Einheit lässt 8 Minuten Pflichtlernzeit offen. Der nächste Schritt lautet dann „Weiterlernen“; erst nach tatsächlicher Zielerreichung ist die weitere Zeit freiwillig. Geschätzte erledigte Portionen begrenzen nur den automatischen Vorschlag. Auch Zeit über dem Ziel wird weiter erfasst; offene, im Hintergrund oder über einer anderen Seite liegende Apps sammeln keine unbegrenzte Lernzeit. Die Messung bleibt eine Näherung.
- Elternaufträge behalten ihre Verbindlichkeit, Starttermine und Fristen. Nicht passende Fristen erzeugen einen Hinweis, keine automatische Änderung des Lernziels oder Verlängerung des Tages.
- Angefangene Übungen, fällige Abrufproben, neuer Stoff und ältere Quellen werden in überschaubaren Portionen vorgeschlagen. Fächer werden abgewechselt; Reihenfolge bleibt innerhalb eines Fachs erhalten. Verschiedene Fächer eines Schultags dürfen unterschiedliche Lerntage haben.
- Ein größeres Paket besteht aus mehreren Etappen. Eine vorbereitete Einheit kann pausiert und an einem anderen Tag fortgesetzt werden. Weitere Aufgaben entstehen erst durch einen begrenzten ausdrücklichen Vorbereitungsauftrag.
- Es gibt keine Beschränkung auf die letzten 30 gespeicherten Schultage in der Planung. Material außerhalb des Siebentagevorschlags bleibt erhalten. Der Elternbereich nennt zu umfangreiche Vorgaben, damit gemeinsam Schwerpunkte gewählt werden können.
- Verpasste Tage erhöhen das Mindestziel nicht und erzeugen keinen wachsenden Pflichtberg. An lernfreien Tagen, während Ferien/Krankheit oder nach erfülltem Ziel gibt es keine automatische Zusatzportion. Das Kind kann stattdessen ausdrücklich freiwillig weiterlernen, auch mit bereits gespeicherten Heftseiten. Zukünftige Elternauftrags-Startdaten und echte spätere Abrufprüftermine bleiben verbindlich.

Der Vorschlag garantiert nicht, dass jeder vorhandene Stoff bis zu einem bestimmten Tag sicher beherrscht ist. Zusätzliche Hilfen und Abrufproben hängen von gespeicherten Antworten ab. Fehlende Nutzung belegt kein fehlendes Verständnis; bestätigte Beherrschung bleibt an die bestehenden unabhängigen Prüftage gebunden.

## Freiwilliges Weiterlernen und Zeitmessung

`plan.voluntary` enthält eigene, jetzt inhaltlich geeignete nächste Schritte ohne neue Generierung. `daily_goal_met` und `weekly_goal_met` vergleichen exakte Aktivitätssekunden mit dem Mindestziel; `completed_portion_minutes` sind dafür ohne Bedeutung. `available_minutes` bezeichnet nur den verbleibenden automatischen Vorschlag und ist keine Startberechtigung. Ein bereits erfülltes Wochenminimum streicht den nächsten Tagesvorschlag nicht.

Jede bewusste Lernaktion verwendet die bestehenden autorisierten Endpunkte. Sie erzeugt weiterhin höchstens einen begrenzten Auftrag. Familien-/Anbieter-/Kostenkontingente, Idempotenz, Quellenprüfung und Wiederholungsgrenzen fehlgeschlagener KI-Aufträge bleiben unverändert. Zusätzliche normale Übungen zählen nicht als vorgezogener erfolgreicher späterer Prüftag.

Der Heartbeat schreibt nur kurze, aktuelle Intervalle fort und serialisiert sie je Kind gegen doppelte Zeitgutschriften auf mehreren Geräten. Nach Rückkehr aus Hintergrund, überdeckter Route, längerer Inaktivität oder Verbindungsverlust setzt `baseline: true` nur den Zeitanker. Die Pause bleibt eine freiwillige Aktion. Bereits historisch erfasste Zeiten werden erhalten; fehlende alte Zeit wird nicht erfunden.

Die Einheit zeigt laufende Sekunden mit einem lokalen Sekundenticker; alle 20 Sekunden gleicht ein authentifizierter Heartbeat mit der Serveruhr ab. Lokale Zwischenstände sind gekennzeichnete Näherungen und erfüllen allein kein Ziel. Letzte kurze Intervalle werden vor Antwort/Pause synchronisiert. `learning_time` in Einheit und Heartbeat enthält dieselben gespeicherten Tages-/Wochensekunden und Zielbooleans wie die Elternübersicht. Die Familienübersicht aggregiert diese Werte gemeinsam und getrennt je Kind/Zeitzone, ohne geschätzte Rundendauern anzurechnen. Eltern sehen in der offenen Kinderdetailansicht einen Abgleich alle 15 Sekunden; im Hintergrund, nach Routen- oder Kontowechsel stoppt er. Es gibt keinen zusätzlichen Websocketdienst und keine sekündlichen HTTP-Anfragen.

Ein offenes Mindestziel sperrt weder das Gerät noch andere Apps. Fehlende Quellen oder ausgeschöpfte KI-Kontingente dürfen nicht durch erfundene Minuten, automatische Käufe oder unbegrenzte KI-Aufträge umgangen werden. Verbindliche Lernziele bleiben in SCHULPILOT sichtbar offen.
