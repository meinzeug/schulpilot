# Eltern-Lernkompass, Lernplan und Hausaufgaben

Implementierungsstand21.10.2026, Version1.17.3+73. Tatsächlicher Freigabe-,
Test- und Produktionsstand stehen in STATUS.md. Keine neuen Laufzeitpakete oder
Dienste; bestehender FastAPI-Worker, PostgreSQL, OpenRouter-Routing und Flutter.

Version73 erhält ältere offene Runden und gespeicherte Kurzpläne unabhängig von
begrenzten Verlaufsvorschauen. „Als erledigt markieren“ schließt einen Elternauftrag
nach Rückfrage ab; eine mitgesendete Revision schützt vor überholten Änderungen.
Wiederholter Legacy-Aufruf erzeugt keinen zweiten Abschlussbeleg. Bestehende
Runden/Antworten bleiben erhalten; ein erledigter Auftrag beweist keine Beherrschung.
Der Lernkompass lädt bei Rückkehr aus einer Detailseite den gespeicherten Status
mit GET nach. Vollständige Fehlerprüfung: [APP_REVIEW_2026_10_21.md](APP_REVIEW_2026_10_21.md).

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

## Tatsächlicher künstlicher Produktionsnachweis21.10.2026

Eigener regulärer, ausdrücklich künstlicher Haushalt, kein öffentlicher Demo-
Sonderpfad, keine Antwort im echten Kinderprofil. Festes Testbudget0,25USD und
zwölf Aufrufe; weder Providerrevision29 noch Familien-/Systemgrenzen geändert.

| Ausgang / Ereignis | Tatsächliche Entscheidung und gespeichertes Ergebnis |
| --- | --- |
| Neues Elternthema ohne Foto | Sol erzeugt eine Einführung und zwei kontrollierte Aufgaben:47+26=73 und81−35=46. Fach/Thema exakt gebunden; erneute Vorbereitung verwendet die vorhandene Runde. |
| Bestätigtes künstliches Rechteckfoto | Luna gliedert zwei Hausaufgaben, Eltern sehen1von2Häkchen und das Original. Nicht abgeschickte Antwort/Frage bleiben verborgen. |
| Elternauftrag aus bestätigter Quelle | Luna erzeugt eine Begriffsfrage und die neue Rechnung6cm×3cm=18cm². Thema aus dieser Runde wird mit derselben Quellenrevision übernommen. Dies ist eine normale Lernrunde mit ausgearbeitetem Beispiel, keine zusätzliche Hausaufgaben-Tutorhilfe. |
| Vier künstliche Antworten | Zwei selbstständig richtig, eine mit Hinweis richtig, eine zunächst unklar; die erste KI-Auswertung behandelt unklar ausdrücklich als offen, nicht als Fehler. |
| Rechenprüfung korrigiert | Die eigene alte Antwort0auf81−35 wird ausdrücklich nachgeprüft: falsch statt unklar. Antwort, Hilfenutzung, Datum und Anzahl bleiben erhalten; genau ein Assessment-Eintrag trotz zweimaligem POST, null Anbieteraufrufe. |
| Regelmäßige Auswertung | Elternfreigabe aktiv; ausschließlich im künstlichen Kind wurde der bereits vergangene Tagesabstand auditierbar simuliert. Der reguläre Worker erzeugt selbstständig einen neuen Bericht: ein Übungsschwerpunkt plus ein Thema mit Unterstützung, danach Verständnisprüfung, neue Anwendung und späterer Abruf. Kein globaler Uhr-/Budget-/Versuchszählerwechsel. |
| Lesen / neu laden | Mehrfaches Lesen von Bericht und Lernplan verändert Usage nicht. Kein neuer Bericht ohne neue Belege; entsprechende Zeit-/Revisionsfälle zusätzlich auf isoliertem PostgreSQL geprüft. |

Neun tatsächliche OpenRouter-Aufrufe inklusive normaler Rundenrückblicke und der
inhaltlich ungeeigneten ersten Zusammenfassung unter70:41066µUSD=0,041066USD,
keine unbekannten Kosten. Modelle `openai/gpt-6-luna` und `openai/gpt-6.1-sol`.
Die korrigierte ausdrücklich angeforderte Elternauswertung kostete459µUSD; die
regulär vom Worker erzeugte Folgeauswertung613µUSD. Keine automatische Reparatur
oder Rücksetzung früherer Kosten. Der Produktionshaushalt wurde über die normale
berechtigte Kontolöschung entfernt, anschließend Konten, Quellen, Runden und
Berichte sowie unveränderte Providerrevision serverseitig geprüft. Verbrauch und
authentifiziertes Löschjournal bleiben bestehen.

Browserprüfung mit denselben tatsächlichen künstlichen Antworten als ausdrücklich
lokaler Bedienprobe: Thema anlegen, gemeinsame Bereichsauswahl, Wochenplan,
Hausaufgabenfilter, Aufgabenstatus, geschütztes Originalfoto, Themen-Beleglink,
Desktop/Mobil sowie hell/dunkel. Die lokale Vorschau besitzt keinen KI-Schlüssel
oder Worker. Sie beweist Darstellung/Navigation, keine zusätzlichen Liveaufrufe.
Die eigentlichen Livefälle liefen über die normale Produktions-API.

Vollständige Flutter-Reihe1022Tests bestanden; nach der letzten direkten
Themen-Belegnavigation37 betroffene Widgettests und Flutteranalyse sauber.
162 Backendfälle bei Integration,149 Rechen-/Bewertungsfälle,107 Adapter-/Planungs-
fälle und19 abschließende Elternfälle bestanden; überlappende Läufe werden nicht
addiert. PostgreSQL-Migration0025 tatsächlich bis zum Head geprüft. Keine neue
physische Android-/Kamera-, vollständige WCAG- oder Lernwirkungsabnahme behauptet.
Build-/Produktionsstand und Rückweg stehen im Kopf von STATUS.md.
