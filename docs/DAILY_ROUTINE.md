# Täglicher Ablauf und machbare Lernportionen

Die Heftsammlung ist der Vorrat, keine tägliche Aufgabenliste. Die Kinderstartseite behält den Einstieg zu den heutigen Seiten auch bei offenen älteren Einheiten. „Heute keine neuen Seiten“ gilt nur für den lokalen Kalendertag; spätere Fotos bleiben möglich. Elterliche Lernziele bleiben erhalten; freiwilliges Weiterlernen hat keine zeitliche Obergrenze.

## Vorbereitung nach der Schule

Seit 17.10.2026 bleibt die Lernkarte auf der Startseite an derselben Stelle. Eine aktive oder pausierte Runde hat Vorrang; die heutigen Heftfotos bleiben als eigene kurze Aktion erreichbar. Neue Fotos und laufende Fotovorbereitung verdrängen keine bereits lernbare Runde. „Anderes Thema“ öffnet die Sammlung. Fachliche Elternaufträge bleiben auch nach erreichtem Zeitminimum verbindlich gekennzeichnet.

Fotos werden zunächst privat gespeichert. Die ausdrücklich beauftragte Vorbereitung arbeitet anschließend serverseitig weiter, auch wenn das Kind die App verlässt. Erkennung, Quellenprüfung und Paketvorbereitung bleiben getrennt: Erkannte Texte werden nicht heimlich bestätigt. Unsichere Stellen müssen vor Aufgaben aus diesen Quellen geprüft werden. Das Kind beginnt die Lernrunde selbst; ein fertiger Hintergrundauftrag startet keine Einheit.

„Stimmt, weiter“ bestätigt eine geprüfte Seite direkt, ohne zusätzliche Checkbox. Erkennungshinweise bleiben sichtbar. Eine noch unbestätigte eigene Seite lässt sich mit „Seite löschen“ und einer kurzen Rückfrage entfernen. Anschließend erscheint die nächste ungeprüfte Seite; nach der letzten heutigen Seite wieder die Fotoauswahl. Bereits bestätigte Quellen können Kinder dabei nicht löschen.

Fehlende heutige Lernzeit verhindert nicht, geprüften Stoff für spätere Lerntage zu speichern. Ein zusätzlicher KI-Auftrag wird dafür nicht benötigt. Ungeprüfte oder unleserliche Seiten bleiben als solche erkennbar. Bereits gespeicherte Antworten werden beim Ergänzen oder Neuplanen nicht überschrieben.

## Geführte Lernrunde

Der Aufgabenraum zeigt die festen Schritte Verstehen → Üben → Rückblick. Globale Menüs treten während der Runde zurück; Verlassen, Pause und Hilfe bleiben erreichbar. Uhrdetails stehen auf Wunsch bereit. Frage und eigene Antwort bleiben bei der Rückmeldung sichtbar, bis das Kind bewusst weitergeht. Eine feste Hauptaktion erhält eigenen Platz oberhalb der Tastatur; sie überdeckt kein Antwortfeld. Einfache Hinweise, Erklärung, eigene Heftfrage und Elternhilfe sind am selben Hilfezugang erreichbar; Sprache startet nur ausdrücklich.

Neue Antworten verwenden `guided_feedback: true`, sobald die Einheit mit dem Feld `pending_feedback` die Unterstützung dieses Protokolls anzeigt. Der Server merkt die jüngste noch nicht quittierte Rückmeldung, auch bei Pause, Neuladen oder Wechsel auf ein anderes eigenes Gerät. `POST /units/{id}/feedback/acknowledge` quittiert nur den zugehörigen Versuch idempotent; es erzeugt weder Antwort, Lernzeit noch KI-Auftrag. Alte Clients bleiben kompatibel, alte abgeschlossene Antworten werden nicht als ungelesen markiert. Bei einem älteren Backend verwendet der neue Client den bisherigen lokalen Rückmeldungsablauf ohne zusätzliches Schemafeld oder automatischen Antwortwiederholungsversuch. Die internen Marker erscheinen nicht als technische Ereignisse im Elternverlauf.

Nach dem letzten Antwortfeedback erscheint immer der fachliche Abschluss. Selbstständig gelöst, mit Hilfe gelöst, unklar und weiter zu üben werden aus gespeicherten Versuchen getrennt gezählt. Die fachliche Anschlussaktion hat Vorrang vor einer allgemeinen Runde. Ein offenes Mindestziel bleibt sichtbar und führt anschließend weiter; ein geschafftes Zeitminimum erklärt keinen Stoff für beherrscht. Spätere Abrufe behalten ihre Termine. Drei Prüftage allein sind kein Nachweis über sieben Tage; eine gefestigte Beobachtung wird ausschließlich aus dem Backend übernommen.

Eine neue Einzelrunde wird einmal ausdrücklich reserviert. Danach zeigt `/learning-preparation/{childId}/{jobId}` den gespeicherten Status, ohne weitere Erzeugung oder automatische Fehlerwiederholung. Abgleich nur für das eigene Konto, im Vordergrund und bei aktueller Route; bei Verbindungsfehlern bewusst neu laden. Nach Fertigstellung bewusst beginnen. `learning_preparation` in der Übersicht enthält nur ID und Status eines eigenen aktiven Einzelrundenauftrags; vorhandene Einheiten bleiben zugänglich. Tagespaket- und Fotovorbereitung behalten ihren eigenen Ablauf.

Die Gestaltung wurde mit drei weiteren Agents vor der Umsetzung, während der Gegenprüfung und nach der Umsetzung gegen Primärquellen geprüft. Die Übertragung auf SCHULPILOT ist eine Produktentscheidung, kein nachgewiesener Wirksamkeitseffekt dieser App. [Quellen und Grenzen](SOURCES.md).

## Planung

Noten können seit 17.10.2026 als zusätzliche schulische Beobachtung berücksichtigt werden. Eltern verwalten sie je Kind unter „Noten“; Familienmitglieder mit Leserecht können sie nachvollziehen. Schlechtere aktuelle Ergebnisse erhöhen das Fachgewicht über den Wochenvorschlag, ohne Tageskapazität, Elternfristen oder Startdaten zu verändern. Die Gewichtung ist abschaltbar und startet keine KI. Bestätigte passende Seiten sind Voraussetzung für daraus angenommene Elternlernziele. [Genaue Berechnung, Pädagogik und Grenzen](LEARNING_MODEL.md).

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
