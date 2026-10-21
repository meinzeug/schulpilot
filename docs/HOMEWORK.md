# Hausaufgabenwerkstatt · 21.10.2026

Ein eigener Kinderbereich unter `/homework/:childId` und eine Arbeitsseite pro
Foto. Buch, Arbeitsheft, Arbeitsblatt und handschriftlicher Hefter verwenden
denselben vorhandenen geschützten Fotoimport samt Zuschnitt und wörtlicher OCR.
Die Fotoabgabe startet genau einen expliziten Erkennungsauftrag. Wiederaufnahme
und Statusabfragen erzeugen keine Aufträge. Das Kind prüft den erkannten Text
mit „Stimmt, weiter“; erst eine weitere ausdrückliche Aktion lässt Aufgaben
gliedern. Die Bestätigung erzeugt hier keine ungeprüften Pflichtaufträge.

Android-Kamerarückkehr ab73: Vor dem externen Picker wird nur der authentifizierte
Kontoinhaber, das Kind und der Zweck gespeichert. Nach einem vom Betriebssystem
ausgelösten Neustart stehen höchstens acht wiedergefundene Fotos mit insgesamt
20MiB im Arbeitsspeicher bereit. Hausaufgaben erscheinen in ihrem eigenen Bereich
und mit einem Rückkehrhinweis unter Heute, niemals im Heftimport. Das Kind öffnet
den Zuschnitt bewusst; Abbrechen erhält das Foto. Kein automatischer Upload oder
KI-Aufruf. Kontowechsel/Abmelden verwirft Fotos und Marker. Die Plattformrückgabe
und Oberflächenfreigabe sind automatisiert geprüft; kein neuer physischer
Android-Kameratest wird daraus abgeleitet.
Diese Rückkehrhilfe gilt für Kinderzugänge. Der bisherige Eltern-Fotoimport
erhält dadurch keine Wiederherstellung nach einem Android-Prozessende.

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
  Aufgabenübersicht plus die letzten40 Gesprächsschritte; keine Schreibvorgänge oder KI.
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

Aufgabenwechsel speichert auch die neue Auswahl. Änderungen an Entwurf,
Frage und Checkliste werden in einer gemeinsamen Reihenfolge gespeichert;
eine währenddessen ausdrücklich vorgenommene Änderung wird nach dem laufenden
Schreibvorgang mit dessen neuer Revision übernommen, auch beim Verlassen der
Seite. Bei Konflikten oder Verbindungsfehlern wird kein neuer Versuch automatisch
gestartet. Die aktuelle Aufgabenübersicht bleibt zusätzlich zu den letzten40
Gesprächsschritten erreichbar. Auch nach langen Verläufen werden eine fertige
Analyse und die drei Hinweisstufen anhand ihrer Quellenrevision wiederverwendet.
Der Stand „x von y selbst abgehakt“ bleibt eine reine Checkliste. Nach dem
Abhaken führt „Nächste offene Aufgabe“ auf ausdrücklichen Klick weiter, ohne
neuen Modellaufruf. Hilfen einer früheren Aufgabenanalyse erscheinen nicht als
aktuelle Rückmeldung zur korrigierten Aufgabe.

Kurze Bezugssätze wie „Beschreibe deinen ersten Schritt“ erhalten höchstens drei
servergeprüfte Originalaufträge derselben aktuellen Analyse als Kontext (je
Zitat/Regel höchstens600 Zeichen, insgesamt2400). Bei mehreren möglichen Bezügen
soll die Hilfe nach der vorhandenen Aufgabennummer fragen. Prüfungen gegen
bekannte Originalergebnisse und ausgefüllte Sprachlücken umfassen auch diesen
Kontext; er enthält keine fertigen Lösungen oder zusätzliche Fotos.

## Nach den Hausaufgaben selbst prüfen

Sind die Aufgaben der aktuellen Übersicht selbst abgehakt, bietet die Arbeitsseite
„Mit neuen Aufgaben prüfen“ an. Ein vorhandener offener Lernversuch oder laufender
Vorbereitungsauftrag derselben aktuellen Quelle bleibt auch davor erreichbar und
wird ausdrücklich als gespeicherte Runde beziehungsweise Vorbereitung beschriftet.
Das Anzeigen oder Wiederöffnen erzeugt keine neue Runde.

`POST /materials/{id}/homework/practice` ist eine eigene bewusste Kinderaktion mit
`source_revision` und Idempotenzschlüssel. Der Adapter übernimmt eine vorhandene
passende offene Runde oder Vorbereitung; sonst reserviert er über das bestehende
`materials.enqueue` genau einen normalen `unit`-Auftrag. Gebunden wird ausschließlich
dieses bestätigte Foto, keine anderen gleichfachlichen Tagesseiten. Danach verwendet
der Client die bestehende reine GET-Statusseite und den regulären Aufgabenraum.
Bei unbekanntem Transportergebnis ist ein ausdrücklicher Abgleich mit demselben
Schlüssel möglich. Weder Seitenaufruf noch Polling wiederholt eine Generierung.

Der optionale `homework_practice`-Auftrag verlangt neue Aufgaben zu derselben
Grundidee und andere Zahlen beziehungsweise Größen. Originalaufgaben und bereits
erzeugte Fragen dienen nur als Wiederholungsverbote. Die lokale Ausgabeprüfung
verwirft identische normalisierte Fragen und bekannte numerische Wiederholungen:
Bruchaddition, belegte Bruchoperationen, Zweizahlterme und gleiche Rechteckmaße.
Dies ist eine endliche Sicherung, kein allgemeiner semantischer Nachweis neuer
Fragen in allen Fächern. Unklare oder abgelehnte Ergebnisse werden nicht durch
Ersatzfragen oder automatische Modellreparaturen verdeckt.

Ausdrücklich belegte Bruchverfahren verwenden auch hier den bestehenden endlichen
`fraction_tasks`-Planer vor dem Modellaufruf. Zwei neue Zahlenaufgaben werden im
Schema gebunden und nach der Antwort unverändert geprüft; die KI ergänzt Einführung,
Hinweise und Erklärungen. OCR-Zeilenumbrüche in der eindeutigen Anweisung „Erweitere
Zähler und Nenner mit derselben Zahl“ bleiben im wörtlichen Beleg erhalten.
Diese Anweisung belegt Erweitern, keine fehlende vollständige Additionsregel.
Die geprüfte Lernziel-ID wird erst serverseitig an die validierte Aufgabe gebunden.
Der erklärte Fokus lautet in diesem Fall: „Für das Addieren prüfen wir zuerst das
Erweitern.“ Bekannte Bruch-/Rechensignaturen aus Original- oder Prüfaufgaben dürfen
auch nicht als ausgearbeitetes Einführungsbeispiel vorweggenommen werden.
Gedruckte Originalbrüche sind zusätzlich für alle drei erlaubten Erweiterungsfaktoren
gesperrt. Eine schon erklärte Original-Teilrechnung zählt dadurch nicht als neue
Voraussetzungsprüfung. Solche Ausschlüsse sind kein Übungsverlauf und verändern
die Häufigkeitsgewichtung der Lernziele nicht. Der endliche Zahlpool und bestehende
Abbruchregeln bleiben erhalten; bei Erschöpfung wird keine Ersatzfrage erzeugt.

Der reguläre Coach erhält bei einer einzelnen bestätigten Hausaufgabenquelle
einen eigenen `homework_original_prompts`-Kontext. Er bleibt auch erhalten, wenn
Tagesfragen den begrenzten Übungsverlauf ersetzen. Dieser Kontext ist kein neuer
Jobtyp und übernimmt keine Sitzung aus einem alten Auftrag. Bestehende Coach-
Berechtigungs- und Quellenprüfungen laufen vor und nach jeder Anfrage unverändert.
Der erste Rückblick zu bereits gebundenen Zahlenaufgaben enthält nur deren
tatsächlich geprüfte Voraussetzungen; ein gespeicherter früherer Zielkatalog wird
nie umgeschrieben. Folgeaufgaben behalten ihre bestehenden Ziel-IDs, Original-
Ausschlüsse und den Erklärungsschutz. Gezieltes Nachlernen verwendet weiterhin
die Phase Verstehen; der erstmalige Hausaufgaben-Übergang verwendet Anwenden.

Bei ausdrücklich belegten Bruchregeln nutzt dieser Anschluss den vorhandenen
endlichen Rechenplaner vor dem Modellaufruf. Die kurze wörtliche Regel „Erweitere
Zähler und Nenner mit derselben Zahl“ zählt einschließlich OCR-Zeilenumbrüchen als
Erweiterungsregel. Ein bloßes Additionsthema ersetzt keine vollständige
Additionsregel. Fragen werden nach Schema- und Rechenprüfung serverseitig an ihr
belegtes Teilziel gebunden. Bekannte numerische Original-/Prüfaufgaben dürfen auch
im Erklärungsbeispiel nicht erneut erscheinen.

Der Worker prüft Kinderanmeldung, Familie, Tarif, bestätigte Quellenrevision und
Providerrevision vor und nach dem Modellaufruf. Abmeldung oder Quellenänderung
verhindert die Übernahme; bereits angefallener Verbrauch bleibt erhalten.
Neue Antworten durchlaufen unverändert die reguläre Aufgabenbewertung mit
selbstständigen, unterstützten und offenen Nachweisen. Ein Hausaufgaben-Häkchen,
ein Gespräch oder die bloße Vorbereitung wird dabei weiterhin kein Lernbeleg.

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


## Verifizierte Liveprüfung · 21.10.2026

Produktstand1.16.2+69, Release `20261021T073101Z-56b8849`, Produktcommit
`56b884926d848908f43cf1176b68a4476ec1f475` (main gepusht).
Eigener künstlicher regulärer Haushalt, keine Testantwort in einem echten Kinderprofil.
Alle fünf generierten Fotos wurden über die normale Produktions-API hochgeladen,
mit OpenRouter tatsächlich erkannt, visuell gegen die vollständigen Transkripte
geprüft und ausdrücklich bestätigt. Keine OCR-Korrektur erforderlich.

| Foto | Tatsächlich geprüfte Hilfe |
| --- | --- |
| Mathematikbuch, Rechteck7cm×4cm | Innenfläche als Einheitsquadrate, Länge×Breite; kein vorgegebenes28 |
| Handschriftlicher Mathehefter, Bruchaddition | Gleich große Stücke/gemeinsamer Nenner; kein vorgegebenes1/2 |
| Deutscharbeitsheft, Subjekt/Prädikat | Fragen nach Handelndem und Verb; keine fertig markierten Satzglieder |
| Englischworkbook, simple past | Zeitbezug und nächste eigene Handlung; keine ausgefüllten Lücken |
| Physikarbeitsblatt, Dichte | Bedeutung von Masse/Volumen und Formel; kein vorgegebenes3g/cm³ |

Zusätzlich echte Anbieterantworten für drei Hinweisstufen, vierteiligen Arbeitsplan,
anderes Beispiel5cm×3cm mit bloßem Ansatz, freie Rückfrage, Lösungsverrat-Anweisung
und Gesprächsfortsetzungen geprüft. Die Umfang-Rückfrage klärt ausdrücklich alle
vier Seiten und den Unterschied zwischen cm und cm². Ein vierter Hinweis verwendet
den dritten gespeicherten Schritt ohne weiteren Anbieteraufruf. Eigene Antworten28
und11 werden lokal korrekt unterschieden, ohne neue Usage oder Lernnachweise.

Zwei reale Ablehnungen wurden erhalten und abgerechnet. Die erste Aufgabenübersicht
zur Bruchseite wurde unter67 verworfen; der damalige allgemeine Fehler enthielt
keinen genaueren Prüfgrund. Wörtliche Belege werden seit68 als servergebundene
Indizes übertragen, damit Formeln nicht erneut geschrieben werden müssen. Bei einer
Rückfrage unter68 war Aufgabenreferenz oder Antwortphase unzulässig. Seit69 sind
Phase, konkrete Aufgabenreferenz, leere Ersatzaufgaben und Verständnisfrage schon
im privaten Ausgabeschema an die Aktion gebunden. Statische technische Prüfgründe
enthalten keine Modellantworten oder privaten Eingaben. Je ein ausdrücklicher neuer
Auftrag nach verifiziertem Codefix; keine automatische Reparatur oder Zählerrücksetzung.

26 echte OpenRouter-Aufrufe, ausschließlich `openai/gpt-6-luna`, inklusive beider
Fehlversuche:10856µUSD=0,010856USD, keine unbekannte Abrechnung. Vorgegebenes
Testbudget0,25USD und30Aufrufe sowie die ProviderkonfigurationRevision29 erhalten.
21 erfolgreiche Tutorantworten, zwei Fehlversuche; keine LearningUnit/Attempt und
keine daraus vorgetäuschte Beherrschung. Diese Kosten betreffen OpenRouter,
nicht die separate Bildgenerierung. Ergebnisse sind eine begrenzte Fallprüfung,
kein Nachweis über beliebige Schulbücher, vollständige Aufgabenerkennung oder Lernwirkung.
Die KI kann Arbeitsaufträge gruppieren; Originalfoto bleibt erreichbar. Der Prompt
fordert zusätzliche Beschreibungs-/Begründungsaufträge ausdrücklich mit an.

83 abschließende Backendtests auf isoliertem PostgreSQL16 und zehn abschließende
Hausaufgaben-Widgettests bestanden, Ruff/Flutteranalyse sauber. Bei Featureintegration
998Fluttertests bestanden; überlappende Testzahlen werden nicht addiert.
Web sowie signierte Direct-APK/Play-AAB69 gebaut und validiert, kein Play-Upload.
Keine neue physische Android-/Kamera-/vollständige WCAG-Abnahme behauptet.

Browserprüfung im isolierten lokalen Haushalt mit den tatsächlichen künstlichen
Produktionsantworten als ausdrücklich lokale Bedienprobe: Dateiauswahl, Blobimport,
realer Zuschnitt1024×1536→982×1536, Upload, Quellenbestätigung, Aufgabenwechsel,
Entwurf und Frage nach Reload, Originalfotozoom200%,390px-Mobile sowie Desktop,
hell/dunkel. Dies ist keine zusätzliche lokale KI-Generierung und kein behaupteter
Produktions-Browserupload. Die fünf Produktionsuploads liefen über die normale API.

Öffentlicher Voll-APK-Download, Hash/Größe/Version und Health geprüft. Produktion
Schema0024; vorherige68 bleibt als Coderückweg ohne Schemarückbau verfügbar.
Vor Deployment Datenbank-/Konfigurationssicherung durch regulären Aktivator.
Der künstliche Produktionshaushalt wurde über die berechtigte Kontolöschung entfernt
und gesondert nachgeprüft; authentifiziertes Löschjournal gilt auch für Backups.
Testnachweise und exakte Bildprompts unter `artifacts/homework-20261021/`;
keine Zugangsdaten in diesem Prüfmaterial.
