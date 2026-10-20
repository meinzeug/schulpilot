# Zustandsbehaftete Lernsteuerung und gemeinsamer Arbeitsraum

Produktionsversion1.15.0+65, Release20261020T184923Z-872d505.
Tatsächliche Bereitstellung, Testabdeckung und Prüfgrenzen stehen in STATUS.md.

## Ziel und tatsächliche Aufgabenteilung

Der reguläre Ablauf soll nach der Schule ohne anwesende Eltern bedienbar sein:
Fotos abgeben, serverseitig vorbereiten lassen, die erkannte eigene Quelle prüfen,
einen überschaubaren Lernschritt beginnen, Rückmeldung lesen und weiterlernen.
Elternkontakt ist ein optionaler asynchroner Hilfsweg. Unlesbare Quellen, unklare
Bewertungen und fehlender externer Zugang werden weiterhin ausdrücklich angezeigt.
Die App behauptet keine lückenlose Betreuung jeder denkbaren Situation und keine
garantierte Notenverbesserung.

Das Gehirn ist kein ständig laufender LLM-Prozess. FastAPI, PostgreSQL und der
vorhandene Worker koordinieren gespeicherte Zustände und einzelne begrenzte
Aufträge. Ein Seitenaufruf startet keine Planung oder Generierung. Der vorhandene
Aktivitäts-Heartbeat eines sichtbaren aktiven Lernraums bleibt davon getrennt.

| Aufgabe | Tatsächliche Funktion |
| --- | --- |
| Aktuelle Belege und Quelle | `learning_controller.facts`, `source_state` |
| Nächste Aktion und Phase | `learning_controller.decide`, `observe`, `execute` |
| Endlicher lokaler Bruchplan | `adaptive_plan.answer_recorded`, `execute`, `public_plan` |
| Individuelle Modellplanung | `instructional_decisions.context`, `prepare`, `process`, `validate`, `execute`, `answered` |
| Fachliche Ziele und langfristige Belege | bestehende `UnitCoaching`, `coaching.goal_states`; neue reine Ableitung `learning_knowledge.catalogue/evidence` |
| Antwortprüfung | bestehende `answer_evaluation`, revisionsgebundene `assessments` und Sprachprüfung |
| Andere Erklärung und Rückkehr | `learning_controller.local_resources`, bestehende LearningTips-Interaktionen, `controller_jobs.prepare/process` |
| Wiederholung | bestehende `coaching.planned_review`, Tagesplanung und ausdrücklich angeforderte neue Runde |
| Oberfläche | `UnitScreen`, `AdaptiveLearningStep`, bestehende `LearningExplanation`/`FractionSumDiagram`, `LearningPreparationScreen` |

## Vier getrennte Arten von Zustand

**Fachwissen:** Lernziele besitzen einen wörtlichen Quellenausschnitt. Gespeicherte
Modellvorschläge tragen in der Wissensprojektion Herkunft
`validated_model_source_quote` und Prüfstatus `source_checked_not_teacher_reviewed`.
Das ist eine geprüfte Quellenzuordnung, keine fachliche Lehrerfreigabe. Lokale
Voraussetzungsbeziehungen sind versionierte geprüfte Regeln und werden nur zwischen
vorhandenen belegten Zielen angezeigt. Es wird kein vollständiger Lehrplangraph
für Klasse 1–13 behauptet und kein unbekanntes Ziel vom Modell frei angelegt.

**Langfristige Beobachtungen:** Die bestehenden Attempt-/Activity-Zeilen bleiben die
einzigen Lernbelege. `learning_knowledge.evidence` wertet alle passenden Runden des
Kindes zu denselben Quellen aus, ohne eine willkürliche Grenze der letzten 100
Runden. Es trennt Aufgaben/Versuche, selbstständige richtige Anwendung,
unterstützte/erneut richtige Anwendung, weiteren Übungsbedarf und offene Bewertung.
Es liefert Belegreferenzen, letzte Beobachtung, letzte selbstständige Anwendung,
Abrufprüftage, Wiederholungsdatum und eine begründete kategoriale Belastbarkeit.
Quellenänderungen erhalten historische Belege, bestätigen damit aber keinen
aktuellen Stoff. Frühere Fehler werden nicht für schönere Zahlen überschrieben.

Drei selbstständige Abrufprüftage mit neuen mathematischen Aufgaben über mindestens
sieben Tage sind erforderlich für `repeated_recall`. Neuere Schwierigkeiten
verhindern diese Einordnung, bis sie erneut geprüft wurde. Eine richtige
Wiedererkennung ist ein anderer Lernzielbeleg als das Addieren von Brüchen.
Eine einzelne neue richtige Aufgabe ist noch keine dauerhafte Beherrschung.

**Arbeitsgedächtnis:** Bestehende LearningMemory-Zeilen speichern Revision,
Planrevision, Phase, aktuelle Frage, Entwurf, gegebene Hilfen/Medienrückkehr,
Vorbereitungsauftrag und endlichen Kurzplan. Die Erweiterung nutzt die vorhandene
JSON-Arbeitsspalte; keine neue Datenbank oder ersetzende Antworttabelle.
Ungezeigte Erklärungen und interne Plandaten werden aus der normalen Projektion
entfernt. Antwortentwürfe bleiben kindprivat, kontogebunden und revisionsgeschützt.

**Hypothesen:** Eine falsche Antwort kann eine überprüfbare Vermutung begründen.
Die Vermutung trägt ihre tatsächlichen Attempt-Referenzen und einen vorläufigen
Status. Sie wird weder zu einer Diagnose noch zu einem Persönlichkeitsmerkmal.

## Eine Entscheidung vom Ereignis bis zur Anzeige

1. Sitzung, Rolle, Kind und Familie serverseitig prüfen; Einheit vor Kind sperren.
2. Eindeutiges Ereignis beziehungsweise POST-Schlüssel prüfen und speichern.
3. Aktuelle Quellenrevision, Elternauftrag, Antworten, Hilfen und Arbeitsstand laden.
4. Vorhandene Aufgabe, Erklärung, vorbereiteten Plan oder lokalen Katalog nutzen.
5. Pädagogischen Bedarf aus den tatsächlichen Nachweisen bestimmen.
6. Bei passender lokaler geprüfter Regel ohne Modell weiterarbeiten. Ein Fehler
   ist zunächst nur ein Fehler; wiederholte Schwierigkeiten wechseln die Hilfe.
7. Bei bewusst angefordertem individuellen Plan genau einen normalen Job samt
   atomarer Kostenreservierung anlegen. Pro Einheit höchstens zwei Planaufträge;
   ein fehlgeschlagener Auftrag wird nicht automatisch wiederholt.
8. Kompakten Kontext und ein geschlossenes Schema an die gespeicherte Modellroute
   senden. Keine Namen, Noten, Fotos, gesamte Historie oder gesamte Linkdatenbank.
9. Alle Frage-/Ziel-/Ressourcen-/Beleg-IDs, Zuordnungen und Vorwärtszweige prüfen.
10. Sitzung, Familie, Tarif, Anbieterrevision, Quellen, Planrevision und inzwischen
    veränderte Lernnachweise erneut prüfen. Verspätete Antworten verwerfen.
11. Plan und Abrechnung speichern; erst dann die kontrollierte Komponente anzeigen.
12. Eine tatsächliche Antwort, bewusste Hilfe, Rückkehr oder Pause abwarten.

Ein Modellplan enthält 1–4 Schritte mit Aktion, vorhandener Frage, belegtem Ziel,
Belegreferenzen, optionaler echter Ressource, kurzem Grund, erwartetem Ergebnis
und nullbasierten Vorwärtszweigen für selbstständigen Erfolg/anderen Ausgang.
Keine Schleifen, Befehle, freien URLs, Prozenturteile oder internen Gedankengänge.
Erklärungen und Hinweise stammen aus geprüften gespeicherten Inhalten. Freie
Nachfragen verwenden weiterhin den separaten begrenzten Hefttutor.

Selbstständig richtig nimmt den Erfolgszweig; unterstützt richtig, falsch und
unklar werden ausdrücklich anders gespeichert und nehmen den anderen Zweig.
Unklar wird nicht falsch gebucht. Gezeigte Lösungen sperren die Behauptung einer
neuen selbstständigen Prüfung derselben Frage. Nach der letzten Rückmeldung
führt der erste Button weiterhin zum Ergebnis, auch vor offenem Zeitminimum.

## Schnittstellen

| Schnittstelle | Wirkung |
| --- | --- |
| `GET /api/units/{id}/learning-session` | Zustand lesen, keine Kosten/Antworten |
| `GET …/learning-session/knowledge` | belegte Ziele, Voraussetzungen und langfristige Ableitung lesen |
| `PUT …/learning-session/draft` | Entwurf mit eigenem CAS speichern; keine Lernzeit/Antwort |
| `POST …/learning-session/action` | vorhandenen Schritt mit Revision/Idempotenz bewusst ausführen |
| `POST …/learning-session/plan` | individuellen endlichen KI-Plan einmal reservieren |
| `POST …/learning-session/check` | zwei neue quellengebundene Fragen nach Erklärung/Medienrückkehr einmal reservieren |
| `POST …/learning-session/skip` | zurückstellen, keine Ersatzantwort/Kompetenz erzeugen; Modell-Fehlerzweig oder gespeicherte Pause |
| bestehendes `POST …/questions/{id}/answer` | tatsächlichen Attempt prüfen und speichern, danach Plan anpassen |

Job-Statusseiten verwenden reine GETs. Nach Browser-/Serverneustart bleibt ein
vorbereiteter Job sichtbar. Der bestehende Worker setzt angefangene externe
Aufrufe nicht blind erneut ab; abgebrochene Vorgänge enden nachvollziehbar,
unbekannte Kosten bleiben reserviert. Ein erneuter Auftrag braucht eine bewusste
Aktion und die normalen Grenzen.

Materialupload/-bestätigung/-korrektur, Elternplan-/Terminänderungen und fällige
Wiederholungen laufen weiter durch ihre bestehenden persistenten Aktivitäten,
Quellen-/Planrevisionen und Tagesplanung. Sie starten nicht auf einem GET eine
neue KI. Einheitenbezogene Ereignisse referenzieren die vorhandenen Aktivitäten:
Start/Fortsetzung, Antwort, Hilfe/Beispiel, Pause, Rückmeldung, Abschluss,
Medienöffnung/-rückkehr, Neubewertung und Zurückstellen.

## Vollständige künstliche Bruchspur

| Ausgang/Ereignis | Beobachtung und Entscheidung | Aktion und gespeicherte Folge |
| --- | --- | --- |
| bestätigte allgemeine Regel für ungleichnamige Addition; `1/3 + 1/6`, Antwort `2/9` | mathematisch falsch; Zähler und Nenner jeweils addiert; nur vorläufige Hypothese | `offer_probe`, tatsächliche falsche Antwort bleibt erhalten |
| bewusst Zwischenschritt starten | neue Frage erkennt dieselbe Menge `1/3 = 2/6` | zusätzliche eigene Frage, getrenntes Ziel „Gleichwertige Brüche erkennen“ |
| A: Probe falsch/unklar | Voraussetzung benötigt Unterstützung beziehungsweise Prüfung | Erklärung der gleich großen Mengen, lokal gerenderte passende Bruchteile |
| B: Probe selbstständig richtig | Wiedererkennung belegt; keine pauschale Grundlagenwiederholung | gezielt gemeinsame Einteilung/Rechenschritt erklären |
| Erklärung ausdrücklich ansehen | gezeigter Inhalt ist Hilfe für die erklärte Frage | Erklärung/Quellenbeleg gespeichert; keine erfundene richtige Antwort |
| neue Anwendung ausdrücklich starten | unversuchte Rechnung `1/4 + 1/8` | neue eigene Frage, Lösung `3/8`, keine umgeschriebene Originalfrage |
| selbstständig `3/8` oder äquivalent `6/16` | neuer selbstständiger Anwendungsbeleg | ursprünglicher Fehler bleibt; Hypothese `new_independent_success`; Wiederholung vorgesehen |
| weitere Hilfe/erneuter Fehler | unterstütztes Üben, keine freie Beherrschung | Darstellung wechseln; höchstens drei tatsächliche Versuche, dann übrige Aufgaben erreichbar |
| später eigene neue Abrufrunde `2/5 + 1/10` | `1/2` mathematisch richtig, Unterstützung separat | späterer Abrufbeleg; weitere unterschiedliche Prüftage erforderlich |

`test_adaptive_plan.py` prüft beide Zweige durch echte API-/DB-/Controllerwege.
`test_learning_knowledge.py` führt die Bruchspur mit späterer Wiederholung und
getrennten Lernzielen weiter. Synthetische Check-Runden werden dort mit bekannten
fachlich geprüften Erwartungen angelegt; das ist kein Nachweis einer realen
OCR oder live generierter Folgefragen. Die gesamte lokale Bruchverzweigung
benötigt keinen Modellaufruf. Die bestehende neue Zweierprobe nach Sofatutor wird
separat inklusive normaler Reservierung und validierter Modelltransportfixtures
in `test_controller_media.py` geprüft.

## Kosten, Datenschutz und Qualitätsprüfung

Vorhandener freigegebener bezahlter OpenRouter-Mix bleibt aktiv. Kurzer klarer
Kontext kann im economy_mode Luna verwenden; gespeicherte Mehrfachfehler,
Unsicherheit oder größerer Bedarf wählen vor Reservierung Sol. Keine zweite
automatische Anfrage, kein Providerfallback, keine freigegebene Astra-Route.
Medium, Azure-Bindung, ZDR, Data-Collection-Deny und Cache-Opt-out bleiben erhalten.
Unbekannte Abrechnung ist keine Nullkostenangabe. Bekannte eindeutig zugeordnete
Rundenkosten und Kostenverteilung auf selbstständig angewendete gespeicherte
Lernziele werden getrennt ausgewiesen; keine vollständigen Materialkosten oder
Kosten pro dauerhaft beherrschtem Ziel behauptet.

Die Regel-/Promptversionen `school-controller-2`, `adaptive-plan-1` und
`instructional-decisions-1` sind Codeversionen mit Tests und normalem Deployment.
Die App ändert keine Modellgewichte oder Produktionsprompts aus Kinderantworten.

Referenzfälle: `test_learning_controller.py`, `test_adaptive_plan.py`,
`test_learning_knowledge.py`, `test_instructional_decisions.py`,
`test_controller_media.py`, `test_model_routing.py`, `test_coaching.py`,
`test_assessment_corrections.py` sowie Flutter
`adaptive_learning_room_test.dart`, `adaptive_learning_test.dart` und die
bestehenden Feedback-/Zeit-/Vorbereitungs-/Darstellungstests.
