# Eltern-Lernkompass, Lernplan und Hausaufgaben

Implementierungsstand21.10.2026, Zielversion1.17.2+72. Tatsächlicher Freigabe-,
Test- und Produktionsstand stehen in STATUS.md. Keine neuen Laufzeitpakete oder
Dienste; bestehender FastAPI-Worker, PostgreSQL, OpenRouter-Routing und Flutter.

## Lernbelege vor Einschätzung

`parent_insights.facts` liest über `learning_progress.read_ledger` sämtliche
beantworteten Aufgaben des Kindes, auch begonnene und freiwillige Runden. Pro
Fach/Thema werden selbstständiger Erstversuch, mit Hilfe/erneut richtig, weiter
üben und unklare Bewertung getrennt gezählt. Reflexionen sind eigene Beiträge,
keine überprüften Fachantworten. Die Oberfläche zeigt Handlungsbedarf sofort,
auch ohne KI-Bericht. Unklare Bewertungen werden niemals zu Fehlern umgedeutet.

Eine KI-Auswertung benötigt mindestens drei beantwortete Fachaufgaben. Ihr
kompakter Kontext enthält maximal24 priorisierte Themen mit tatsächlichen
Aggregaten, Klassenstufe und abgeleiteten Fach-/Themenvorgaben. Keine Namen,
Fotos, Rohantworten, privaten Elternnotizen oder Schulnoten. Thema/Fachnamen
bleiben private Lerninhalte; geltende Provider-/Datenschutzfreigaben gelten auch
für diese Anfrage. Nicht alle Gründe eines Fehlers sind aus Summen erkennbar:
Die KI darf nur vorsichtig einordnen und eine nächste Überprüfung vorschlagen.
Keine Diagnose, freien Kompetenzprozente oder behauptete dauerhafte Beherrschung.

Liveprüfung unter70: Die konservative Rechenprüfung kannte einen einfachen
zweistelligen Subtraktionsterm noch nicht; eine falsche Zahl blieb deshalb unklar.
Version71 ergänzt `subject_rules_v5` für vollständige Zweizahlterme, auch mit
TeX-Klammern. Sie verifiziert zuerst die Musterlösung und verwendet exakte rationale
Werte. Unbekannte Sach-, Rundungs- oder Teilfragen werden dadurch nicht geraten.
Bestehende Urteile ändern sich nur bei ausdrücklich angeforderter auditierter
Nachprüfung, ohne neue Antwort, Hilfenlöschung oder zusätzlichen Prüftag.

`ReviewOutput` begrenzt die Ausgabe auf sechs belegte Einschätzungen und sechs
Planschritte. Das private Schema bindet Themenreferenzen an die ausgewählten
Belege; `validate` prüft Bedarf gegen die tatsächlichen Kategorien. Beobachtung
und Interpretation erscheinen getrennt. `ParentLearningReview` speichert den
damaligen Belegstand, Bericht, Signatur, Strategie-/Provider-/Modellrevision und
Status. Historische Berichte bleiben lesbar, neue Belege markieren sie als älter.
Ein späterer Fehler verdrängt keinen früheren fertigen Bericht.
Strategie `parent-review-2` trennt Planungsaufträge ausdrücklich von kompakten
Aufgabengenerierungs- und Auswahlformatanweisungen. Die erste echte künstliche
Auswertung unter70 hatte durch diese Überschneidung Aufgaben im Zusammenfassungstext
enthalten. Version71 verhindert die Überschneidung im tatsächlichen Adapter und
verwirft erkannte Aufgaben-/Lösungsblöcke in Berichten. Frühere Berichte bleiben als
historisch erhalten und werden nicht als aktuelle Planungsstrategie verwendet.

## Regelmäßige Auswertung und Kosten

Pro Kind zunächst ausgeschaltet; ein verwaltendes Elternmitglied kann
„Regelmäßig mit KI auswerten“ ausdrücklich aktivieren und jederzeit abschalten.
Diese revisionsgebundene Erlaubnis übersteht die Elternabmeldung, keine Sitzung
wird dazu reaktiviert. Der bestehende Worker prüft sie höchstens minütlich;
ein reservierter Bericht frühestens24Stunden nach dem letzten Versuch und nur
bei verändertem relevanten Lernstand. Reine Foto-/Seitenaufrufe oder ein neues
unbearbeitetes Foto rechtfertigen keinen neuen Bericht. Neue Installationen
übernehmen keine Freigabe eines anderen Haushalts.

`schedule_one` prüft berechtigte aktive Elternmitgliedschaft, Familie, Tarif und
Freigaberevision. `enqueue` nutzt normale atomare Reservierung, einen dauerhaften
Idempotenzschlüssel und höchstens einen laufenden KI-Schritt pro Kind. Fertiger
identischer Belegstand wird wiederverwendet. Kein automatischer Fehlerretry;
höchstens ein ausdrücklich angeforderter weiterer Versuch desselben Standes.
Keine neuen Käufe, Budgeterhöhungen, Providerwechsel oder Reparaturketten.

`process` prüft Rechte, Belegsignatur und Providerrevision vor/nach dem Aufruf.
Verspätete Ergebnisse eines geänderten Standes werden verworfen; Verbrauch bleibt
erhalten. Bekannter Abbruch vor Versand kostet null, unbekannte Abrechnung behält
die Reservierung. Vorhandenes economy-Routing entscheidet vor Reservierung:
kompakte Auswertung als `decision`, freies neues Unterrichtsthema regulär `unit`.
Keine Modellwahl durch das Frontend. GETs erstellen keine Jobs oder Lernbelege.

## Tatsächlicher Lernplan

`/parent-plan/:child` zeigt drei getrennte Ansichten:

- **KI-Lernweg:** gespeicherte längerfristige KI-Schwerpunkte und tatsächliche
  Kurzpläne aus `LearningMemory.working.instructional_plan`, mit aktuellem Schritt,
  Grund und erwarteter Überprüfung. Ein vorhandener Plan wird angezeigt, kein
  Modellplan beim Lesen erfunden.
- **Meine Themen:** verbindliche/zusätzliche Elternaufträge mit Quellen,
  Startdatum, Termin, Revision und vorhandenen Runden. Neue Themen frei eingeben,
  aus einer bestätigten Heftseite oder einer vorhandenen Übung übernehmen.
  Zusammengehörige bestätigte Seiten bleiben gemeinsam revisionsgebunden.
- **Woche & Vorgaben:** alle sieben Tage, konkrete verfügbare Runden, Zeitvorschlag,
  Mindestziele und Pausenrahmen. Geplant bedeutet weder erzeugt noch gelernt.

`apply_guidance` verwendet einen fertigen KI-Bericht maximal sieben Tage für die
Priorisierung passender verfügbarer Themen. Quellen-/Auftrags-/Klassen-/Fokusänderung
beendet die Verwendung sofort; neue Antworten kennzeichnen den Bericht als älter,
ohne eine brauchbare Priorisierung bei jeder Antwort zu verwerfen. Lokale Regeln
in `daily_planner.distribute` behalten verbindliche Termine, früheste Startdaten,
Quellenreihenfolge, Fachverteilung und bereits begonnene Arbeit. Die KI kann keine
fehlenden Runden beim GET erzeugen oder Minuten zu einer zusätzlichen Pflicht machen.
Die Anzeige kennzeichnet, ob aktuell ein KI-Schwerpunkt einfließt.

Themen speichern ist kostenfrei. `POST .../assignments/{id}/prepare` reserviert
bewusst genau eine normale Runde. Eine bereits vorhandene offene Runde derselben
Auftragsrevision wird wiederverwendet; laufende Vorbereitung bleibt nach Neustart
zugänglich. Neuer Inhalt wird an Fach, Thema, Klasse und Quellen gebunden.
Elternthemen ohne Heftfoto sind ausdrücklich als solche gekennzeichnet; die KI darf
passende Grundlagen und eigene Aufgaben erstellen, keine fotografierten Belege
erfinden. Bearbeiten erhält frühere Antworten/Quellen und erzeugt eine neue
Auftragsrevision. Eltern betrachten vorbereitete Übungen, ohne Kinderzeit oder
einen Lernstart zu erzeugen.

## Hausaufgaben pro Kind

`/parent-homework/:child` listet Fotos mit Fach, Thema, Erkennungs-/Prüfstatus und
Checkliste. Serverseitig gefiltert und stabil auf20Fotos begrenzt; „Mit Häkchen“
bedeutet mindestens eine vom Kind markierte Aufgabe, keine fachlich geprüfte
Vollständigkeit oder Richtigkeit. Detailansicht zeigt Original und abgegebene
Fragen/Hilfen. Nicht abgeschickte eigene Antworten und Fragen bleiben kindprivat.
Listen, Filter, Details und Elternlesen erzeugen keine KI oder Lernzeit.

## Schnittstellen und Datenpflege

- `GET /api/children/{id}/parent-insights[?review_id=...]`: aktuelle Belege,
  gespeicherter Bericht, Status und begrenzte Berichtshistorie.
- `PUT .../parent-insights/settings`: verwaltende Eltern, CAS-Revision.
- `POST .../parent-insights/review`: ausdrücklicher Auftrag mit Idempotency-Key.
- `GET .../learning-plan`: konkrete Planung, Aufträge, gespeicherte KI-Kurzpläne.
- `POST/PUT .../assignments[/id]`: Themen samt Quellen- und optionaler CAS-Revision.
- `POST .../assignments/{id}/prepare`: genau ein ausdrücklich reservierter Job.
- `GET .../homework-review?state=all|worked|open|review&cursor=...`: Elternliste.

Migration0025 ergänzt Felder und Berichtstabelle additiv. Familien-/Kindrechte
aus der Sitzung; reine Lesemitglieder dürfen lesen, keine kostenpflichtigen
Auswertungen/Änderungen anfordern. Kinder und Betriebsadmins dürfen private
Elternberichte nicht lesen. Export enthält Berichte/Einstellungen, Kontolöschung
entfernt sie. Quellen-/Rundenlöschung entfernt abgeleitete Berichte, normale
Aufbewahrung maximal365Tage. Tatsächlicher Verbrauch wird nicht zurückgesetzt.

Referenzfälle in `backend/tests/test_parent_insights.py`: Ausgangsbelege →
idempotenter Auftrag → gespeicherte Auswahl → validierte Entscheidung → Ergebnis
und signierter Belegstand; außerdem Quellenänderung, Widerruf, Budgetgrenze,
Providerausfall, regelmäßige Freigabe, Priorisierung/Elterntermine, Export/Löschung,
mehrseitige Übernahme und privates Hausaufgabenlesen. Widgettests in
`app/test/parent_insights_test.dart` und bestehende Navigation-/Lernstandstests.
