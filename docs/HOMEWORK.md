# Hausaufgabenwerkstatt · 21.10.2026

Ein eigener Kinderbereich unter `/homework/:childId` und eine Arbeitsseite pro
Foto. Buch, Arbeitsheft, Arbeitsblatt und handschriftlicher Hefter verwenden
denselben vorhandenen geschützten Fotoimport samt Zuschnitt und wörtlicher OCR.
Die Fotoabgabe startet genau einen expliziten Erkennungsauftrag. Wiederaufnahme
und Statusabfragen erzeugen keine Aufträge. Das Kind prüft den erkannten Text
mit „Stimmt, weiter“; erst eine weitere ausdrückliche Aktion lässt Aufgaben
gliedern. Die Bestätigung erzeugt hier keine ungeprüften Pflichtaufträge.

## Pädagogischer Ablauf

Verstehen → selbst versuchen → gestuft unterstützen → eigenen Weg prüfen.
Eine Aufgabe ist im Fokus; bereits vorbereitete Aufgaben bleiben auswählbar.
„Erkläre es mir“ erklärt den Sinn des Verfahrens und gibt einen kleinen nächsten
Schritt sowie eine Verständnisfrage. „Kleiner Hinweis“ vertieft höchstens drei
Stufen: Denkimpuls, Strategie, unvollständiger erster Schritt. „In Schritte teilen“
liefert einen kurzen Arbeitsplan. „Anderes Beispiel“ verwendet andere Daten und
modelliert dessen Anfang. Eine eigene Frage und eine Rückmeldung zum eigenen
Versuch sind zusätzlich möglich. Die jüngste Hilfe steht beim Eingabebereich;
frühere Hilfen sind getrennt erreichbar. Es gibt keinen Lösungsanzeigen-Knopf.

Eine Aufgabenübersicht wird je bestätigter Revision wiederverwendet. Nach drei
Hinweisen wird der gespeicherte dritte Hinweis erneut angezeigt; keine versteckte
kostenpflichtige vierte Stufe. Bis zu acht belegte Aufgaben/Gruppen je Foto,
ein ausdrücklicher Hinweis bei weiterem Material statt behaupteter Vollständigkeit.

Die Strategie ist aus folgenden Primärquellen abgeleitet, nicht als geprüfte
Lernwirkung dieser App ausgegeben:

- [EEF: Metacognition and Self-Regulated Learning](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition):
  fachgebunden planen, Vorgehen überwachen und reflektieren; Strategien modellieren
  und Unterstützung passend zurücknehmen.
- [IES/What Works Clearinghouse: Organizing Instruction and Study to Improve Student Learning](https://ies.ed.gov/ncee/wwc/PracticeGuide/1):
  Beispiele mit eigenständigen Aufgaben verbinden, konkrete und abstrakte
  Darstellungen verknüpfen sowie erklärende Fragen stellen.

## Daten und Schnittstellen

Migration0024 ergänzt bestehende private Daten: `Material.purpose=homework`,
`Material.homework_state` und `TutorTurn.homework_context`. Keine neue Warteschlange,
kein zusätzlicher Dienst. Bestehende Heftmaterialien behalten `purpose=notebook`.
Erneutes Einlesen erhält den Bereich; Entwürfe werden nicht in eine neue Quelle kopiert.

- POST `/children/{id}/materials?purpose=homework`: eigener Upload mit Schlüssel.
- POST `/materials/{id}/extract`: bestehende atomare OCR-Reservierung.
- PUT `/materials/{id}/confirm`: ausdrücklich bestätigter Quelltext.
- GET `/children/{id}/homework`: begrenzte Metadatenliste mit stabilem Cursor.
- GET `/materials/{id}/homework`: autorisierte Quelle, aktuelle Arbeitsdaten und
  die letzten40 Gesprächsschritte; keine Schreibvorgänge oder KI.
- PUT `/materials/{id}/homework`: CAS und Idempotenz für gewählte Aufgabe,
  eigene Entwürfe, Frageentwurf und selbst abgehakte Aufgaben.
- POST `/children/{id}/tutor/questions`: vorhandener serverseitiger Tutorweg mit
  validiertem `homework`-Aktionsraum; `analyze`, `explain`, `hint`, `plan`, `example`,
  `check` oder `question`. `analysis_id`/`task_id` werden gegen eine eigene,
  erfolgreiche und revisionsgebundene Aufgabenübersicht geprüft.

`tutor.context`/`homework.enrich_context` stellen den begrenzten Kontext zusammen.
`request_provider` wählt für diesen Modus `HomeworkOutput` und `HOMEWORK_SYSTEM`.
`tutor.process` prüft Sitzung, Familie, Tarif, Quelle und bezahlte Providerrevision
vor und nach dem Aufruf. Bestehende Unit-vor-Child-Sperrfolge auch bei Hilfebelegen.
`homework.checked_reply` prüft Schema, Zitate, Aufgaben, Arbeitsanweisungen und
bekannte Lösungsvorwegnahmen. Ein fehlerhafter Aufruf bleibt fehlgeschlagen und
abrechenbar nachvollziehbar; keine automatische Reparaturanfrage oder Ersatzroute.

Der Modellauftrag fordert keine Lösung der Originalaufgabe an. Ein lokaler
Prüfer verwirft vorweggenommene bekannte Bruch-/Rechteck-/Dichteergebnisse und
einige ausdrücklich erkennbare ausgefüllte Englischlücken. Dies ist eine finite
zusätzliche Sicherung, kein allgemeiner Beweis über jede mögliche freie Antwort.
Fachlichkeit und didaktische Qualität werden deshalb anhand tatsächlicher
Anbieterantworten mitgeprüft. Unklare Aufgaben werden konkret zurückgefragt.
Eine Aufgabenquelle belegt den Auftrag; ein Aufgaben-Zitat wird nicht als Beweis
für eine darüber hinausgehende fachliche Erklärung ausgegeben.

## Eigene Antworten, Kosten und Datenschutz

Eindeutig unterstützte eigene Zahlen-/Bruchantworten verwenden die vorhandenen
versionierten Prüfer aus `answer_evaluation.py`. Ein normaler dauerhafter Tutorjob
mit `local_check=homework_math_v1` nimmt dieselben Rechte-/Revisions-/Hilfesicherungen,
ruft jedoch keinen Anbieter auf und reserviert keine KI-Kosten. Das Ergebnis heißt
„Rechnerisch geprüft“. Bei anderen eigenen Lösungswegen bleibt „KI-Rückmeldung“
eine beratende Einschätzung. Aus diesen Gesprächen entsteht kein Attempt und kein
neuer Kompetenznachweis. Passende laufende Lernrunden erfassen Hilfe weiterhin
regulär, abgeschlossene Antworten werden nicht rückwirkend umgeschrieben.

„Ich habe diese Aufgabe bearbeitet“ ist eine Selbstangabe für die Checkliste,
keine bestätigte Richtigkeit, Lernzeit, Zielerfüllung oder gesicherte Beherrschung.
Keine erfundenen Spielwerte. Eltern dürfen gespeicherte Gespräche lesen; aktuelle
unabgeschickte Versuche und Fragen bleiben in normalen Ansichten kindprivat.
Maximal acht offene Entwürfe,24Stunden, serverseitige Löschung nach Ablauf oder
Abmelden. Bei Mehrgeräte-Konflikt bleiben lokale Eingaben erhalten, bis das Kind
den gespeicherten Stand ausdrücklich lädt. Kontowechsel leert die Ansicht.

Modellmix und ZDR-/Data-Collection-Deny-/Cache-/Upstreamregeln bleiben unverändert.
Kurze Hilfen nutzen die vorhandene sparsame Tutorroute. Keine automatische Suche,
keine zusätzlichen Sprach-/Bildanbieter im Produkt. Fotos werden ausschließlich
authentifiziert ausgeliefert. Bestehender Familienexport erfasst die ergänzten
Material-/Tutorattribute; Quelllöschung entfernt Entwürfe und Tutor-Zitate über
den bestehenden Löschweg.365-Tage-Material-/Gesprächsaufbewahrung bleibt erhalten.

## Abnahme

Künstliche Regressionen in `test_homework.py`, `homework_screen_test.dart` und
den bestehenden Tutor-/Foto-/Navigations-/Provider-/Migrationsprüfungen.
Die fünf zusätzlich erzeugten und visuell geprüften Fotoartefakte sowie exakte
Prompts, Hashes, OCR und tatsächliche Anbieterantworten liegen unter
`artifacts/homework-20261021/`. `scripts/homework_live_smoke.py` prüft ausschließlich
diese fünf Bilder im eigenen zeitlich begrenzten regulären Testhaushalt, mit
normaler Reservierung und höchstens0,25USD. Nach OCR stoppt der Ablauf für eine
tatsächliche Textprüfung. Keine künstlichen Antworten im echten Kinderprofil.
Abschließende Ergebnisse, Kosten, Release und Rückweg im Kopf von `STATUS.md`.
