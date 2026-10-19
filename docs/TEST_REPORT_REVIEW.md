# Prüfung der Kinder- und Elternprotokolle

Arbeitsbeginn: 19.10.2026, Ausgang main `afb1ea5`, App 1.7.2+40, Schema 0019.

Beide HTML-Dokumente vollständig als Dokumente gelesen: alle geschlossenen Detailbereiche, Anhänge und eingebetteten JSON-Daten (468 bzw. 865 Blattwerte). Keine Skripte ausgeführt. Es gibt keine externen Bild-/Dateianhänge; eingebettet sind die Beobachtungen und Testdaten. Originale/geschützte Arbeitskopien bleiben außerhalb von Git.

Die protokollierte Anzeige 1.0.1 war am Arbeitsbeginn im Client fest verdrahtet und kein verlässlicher Buildnachweis. Frühere und spätere Testbeobachtungen werden deshalb anhand des Codes und isolierter Regressionen geprüft. Absichtliche Fehler und synthetische Blätter sind keine Diagnose eines echten Kindes. Keine Testbereinigung echter Familienkonten.

## Umsetzung und Fortsetzung

1. Verbindliche Bewertung, getrennte Hilfe-/Versuchsgründe, nachvollziehbare Neubewertung und konsistente Ableitungen.
2. Gebündelte und doppelt geschützte Hausaufgabenvorschau mit ausdrücklicher Verbindlichkeit; Quellen-/Importrevisionen erhalten.
3. Gezielte Fehlerhilfen, direkter Tutor, Kinderführung, Worttrainer, Audio-/Foto-/Formularbedienung.
4. Kurze Elternentscheidung, technische Details nachgeordnet, Rechte-/Zeit-/Tageswechseltests.
5. Gesamttests/Analyse/Build, tatsächlicher Web-/Android-Test mit eigener künstlicher Familie, gesicherte Bereitstellung, Commit/Push.

Stand 19.10.2026: Bewertung/Quellenübernahme/Tutor/Darstellung implementiert, noch nicht veröffentlicht. Neue additive Migrationen0020/0021. 109 und zuletzt75 gezielte Backendtests bestanden. Eine größere Zwischenprüfung237/242 deckte fünf Integrationsfehler auf; diese sind korrigiert und die betroffenen75 Prüfungen erneut grün. 345 vollständige Fluttertests und45 gezielte Abschlussprüfungen bestanden; Analyse fehlerfrei. Der erste vollständige PostgreSQLlauf:927 bestanden, zwei veraltete Testerwartungen (Headrevision, unveränderter Bestätigungsretry). Erwartungen korrigiert; Rechteprüfung um echte verbotene Kinderänderungen erweitert. Neuer Backend-Abschlusslauf folgt. Öffentlicher Stand bleibt1.7.2+40/Schema0019, bis eine neue Bereitstellung tatsächlich geprüft ist.

Nächste Aktion: Gesamttestfehler auswerten, Flutter/Analyse abschließen, tatsächliche Web-/native Bedienprüfung ausschließlich eigener künstlicher Familie; anschließend gesicherter Release mit Rückweg. Keine Prüfungen an echten Familien und keine Testdatenbereinigung dort.

## Herkunft

- `Schulpilot_Test_Kind.html`: SHA256 `092053c8a7a7d22386296d6bdf15fd611030e654a713af202513740d31cf708a`.
- `Schulpilot_Test_Eltern.html`: SHA256 `311d48b0011c703c13ef996da0588caacc9e956b1e9c4a0470bf21bea9be745a`.

## Befundliste

Beobachtung/Versionsbezug stammen aus dem jeweiligen Bericht; Aktueller Nachtest/Ursache und Status/Ergebnis beschreiben diese Umsetzung. Historische Beobachtungen sind nicht automatisch aktuelle Fehler. Implementiert ist noch keine vollständige Geräteabnahme.

### F01 · Früherer Zeitrücksprung im aktuellen Stand gezielt nachtesten

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K06, K44 |
| impact | Zeitvorgaben und spätere Elternberichte können missverständlich sein. |
| recommendation | Monotone lokale Anzeige mit sauberer Zusammenführung bestätigter Serverintervalle; Dialoge und erneutes Rendern dürfen keinen älteren Zeitstand zurückbringen. |
| confidence | Zu Beginn mehrfach beobachtet; beim Mathe-Nachtest in sichtbarer Version1.0.1 nicht erneut ausgelöst. Keine Behauptung, dass aktueller Fehler definitiv fortbesteht. |
| status | früher belegt; aktueller Nachtest ohne Rücksprung |
| Aktueller Nachtest/Ursache | Historischer Befund; aktueller Zeitcode synchronisiert Baselines und deckelt Idle/mehrere Geräte. Elternlesen ist separat isoliert geprüft. |
| Komponenten, Änderung, Abnahme | unit_screen.dart, learning.py; monotone Zwischenanzeige/echte Serversekunden, Tageswechsel und Route/Idle erhalten. |
| Status/Ergebnis | Kein aktueller Rücksprung nachgewiesen. Vorhandene Zeitregressionen und isolierter Elternlesetest; erneuter Oberflächentest folgt. |

### F02 · Erklärung ist textlastig und kaum auf den konkreten Irrtum zugeschnitten

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K04, K05 |
| recommendation | Kleine Schritte, Bildbeispiele, Merkmalsvergleich und eine Verständnisfrage; uneindeutige Heftstelle gezielt zur Klärung anbieten. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Bestätigt: gespeicherte Erklärung als langer Textblock. |
| Komponenten, Änderung, Abnahme | LearningExplanation gliedert denselben Text; schrittweises Lesen, normales/langsames Vorlesen und Bruchbalken für kleine Additionen bei geöffneter Hilfe. |
| Status/Ergebnis | Implementiert; Widget-/Bedienprüfung noch laufend. Kein Wirksamkeitsnachweis. |

### F03 · Vorlesen ohne beobachtbare Wiedergabesteuerung

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K05 |
| recommendation | Sichtbare Wiedergabe, Pause/Stopp, Fortschritt und Sprachgeschwindigkeit anbieten; tatsächlicher Ton noch manuell prüfen. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Ältere Beobachtung: aktuelles LessonVoiceSession/ReadAloudButton hat bereits sichtbares Stoppen, langsam/normal, Locales und Lifecycle-Abbruch. |
| Komponenten, Änderung, Abnahme | lesson_voice.dart, lesson_voice_test.dart; erhaltene Bedienung in Erklärungsschritten. |
| Status/Ergebnis | Bereits vorhanden; Mocktests sind kein hörbarer Geräte-/Mikrofontest. Keine vollständige Audioposition/Pause behauptet. |

### F04 · Soforthilfe verfehlt den Irrtum, gezieltes Feedback kommt erst später

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K07 |
| impact | Ein Kind weiß bei 4 Paaren nicht, was noch falsch ist; wiederholte unpassende Hinweise fördern Raten statt Verstehen. |
| recommendation | Fehler je Teilantwort diagnostizieren, richtige Paare erhalten/markieren, zunächst Merkmalshinweis zum Hund, danach Vergleich Säugetier/Reptil und erst später Lösung. Nächsten Tipp wirklich erweitern. Die im späteren KI-Rückblick bereits vorhandene konkrete Fehlerdiagnose direkt beim Fehlversuch als abgestufte Hilfe anbieten. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: statischer Hinweis ignorierte einzelne falsche Zuordnung. |
| Komponenten, Änderung, Abnahme | learning_hints.py, learning.py, unit_screen.dart; Teilurteile nach Antwort, richtige Paare erhalten, falschen Teil benennen, drei verschiedene gestufte Hinweise, idempotentes Wiederholen. |
| Status/Ergebnis | Backendregression bestanden; Kinderanzeige und Wiederaufnahme werden zusätzlich geprüft. |

### F05 · Korrekte freie Antworten bleiben ohne kindgerechte Klärung offen

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K10, K27, K45 |
| impact | Inhaltliches Verständnis wird nicht zuverlässig erkannt; Folgen für Ergebnis und Elternbericht sind zu prüfen. |
| recommendation | Robuste, transparente Auswertung mit Synonymen und Satzparaphrasen; bei Unsicherheit separates offen statt falsch, einfache Rückfrage oder Neubewertung ermöglichen. KI-Texte dürfen keine nicht erfolgte Änderung des gespeicherten Bewertungsstatus behaupten. Text, Kennzeichnung und Zähler konsistent halten; Kind soll Unsicherheit ohne Lehrperson auflösen können. Mathematische Brüche durch rationale Gleichwertigkeit prüfen. Bei6/16 statt3/8 Wert richtig anerkennen und gegebenenfalls Kürzen als eigenen Lernschritt behandeln. |
| confidence | Korrekte Biologie-Paraphrase und aktuelle mathematisch gleichwertige Bruchantwort sichtbar offen. Ursache nicht aus UI bestimmt. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: wörtlicher Vergleich kann gleichwertige Brüche und eng belegte Satzformulierungen offen lassen; KI-Prosa war kein Bewertungsbeleg. |
| Komponenten, Änderung, Abnahme | answer_evaluation.py, assessments.py, AttemptAssessment/0020, learning/coaching/families; rationaler Wert und Form getrennt, explizites regelgebundenes Nachprüfen mit Audit, ursprünglicher Versuch bleibt. Unbekannte freie Aussagen bleiben offen. |
| Status/Ergebnis | Bruch-/Paraphrasen-/Negations-, Audit-, Export- und Kind/Eltern-Konsistenztests bestanden. Keine allgemeine semantische Vollbewertung behauptet. |

### F06 · Hilfe-/Vorlagenklassifikation für Kinder nachvollziehbar erklären

| Feld | Stand |
|---|---|
| priority | P3 |
| evidence | K09 |
| recommendation | Kurz erklären, welche kürzlich gesehene Vorlage die Einordnung begründet; erster Versuch, spätere Korrektur, Tipp und Vorlagenlernen getrennt benennen. |
| confidence | Kein Bug belegt. Wiederholungs- oder Vorlagenhistorie könnte die Anzeige korrekt begründen. |
| status | vorhandene Funktion; Verbesserungsvorschlag, kein Fehlend-Befund |
| Aktueller Nachtest/Ursache | Kein belegter Klassifikationsfehler; bisheriges assisted vermischt Hilfe und späteren Versuch. |
| Komponenten, Änderung, Abnahme | Attempt.evaluation enthält support_reasons/attempt_number/independent_evidence; Anzeige unterscheidet erneuten Versuch, echte Hilfe und Vorlage. Keine rückwirkend erfundenen Hilfen. |
| Status/Ergebnis | Neue Belege implementiert; alte Belege ohne genaueren Grund bleiben historisch begrenzt. |

### F07 · Fehlertexte und Planüberlastung werden an Kind/Eltern zurückgegeben

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K12, K14 |
| recommendation | Sprachfehler in konkrete verständliche nächste Schritte übersetzen. Bei zu viel Stoff automatisch priorisieren und eine kleine begründete Auswahl anbieten, statt pauschal gemeinsame Schwerpunktsetzung zu verlangen. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Planer verteilt bereits in kleine Portionen; Text forderte auch ohne Terminproblem gemeinsame Priorisierung. |
| Komponenten, Änderung, Abnahme | daily_planner/learning.py, daily_plan_panel; gespeicherter Rest bleibt für spätere Tage, echte Terminkonflikte gesondert. Grenzen/fehlgeschlagene Jobs bleiben sichtbar. |
| Status/Ergebnis | Vorhandene Verteilungslogik erhalten, überflüssige Elternaufforderung entfernt. Bindendes Minimum nicht abgeschafft. |

### F08 · Kindersprache und geführter Einstieg fehlen an mehreren Stellen

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K12, K14, K15, K16 |
| recommendation | Begriffe wie Wiedervorlage, Stand 1, bestätigter Stoff durch Morgen wiederholen, Aus deinem Heft und konkrete Schritte ersetzen; standardmäßig eine passende 3-Wörter-Runde mit einem Startknopf. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Bestätigt an Wort-/Statusbeschriftungen; Heute besitzt im aktuellen Stand schon einen führenden Lernknopf. |
| Komponenten, Änderung, Abnahme | dashboard, vocabulary_screen, ui; Lernziel/Umfang und vorhandene Schätzung, klare Verbindlichkeit, Aus deinem Heft, kurze Worttexte, keine internen Zustände. |
| Status/Ergebnis | Implementiert; laufende Widget-/Browserprüfung. |

### F09 · Vier vorhandene Vokabelmodi in eine verständliche Lernfolge einbinden

| Feld | Stand |
|---|---|
| priority | P3 |
| evidence | K16, K39 |
| recommendation | Schreiben, Bedeutungswahl, freier Abruf und Hören sind vorhanden. Für Kinder einen passenden nächsten Modus automatisch anbieten. Tonqualität/Aussprache müssen auf echtem Gerät geprüft werden. |
| status | vorhandene Funktion; Verbesserungsvorschlag, kein Fehlend-Befund |
| Aktueller Nachtest/Ursache | Vier Wortmodi sind aktuell vorhanden, frühe Zwei-Modi-Beobachtung ist kein aktueller Fehlend-Befund. |
| Komponenten, Änderung, Abnahme | vocabulary, vocabulary_review, language_tasks/evaluation, study_path; getrennte Richtung/Fähigkeit, bewusste kleine Runden und spätere Abrufe erhalten. |
| Status/Ergebnis | Vorhandene Funktionskette/regressionsgesichert; keine automatische Hochstufung von Erkennen zu Schreiben. |

### F10 · Vokabelhilfe erkennt den Schreibfehler nicht didaktisch

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K17 |
| recommendation | Bedeutungserinnerung, Wortwahl und Rechtschreibung getrennt rückmelden; bei swiming gezielt Doppel-m markieren oder mit einer Lücke erarbeiten lassen; kindgerechter Ton. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: fehlender Buchstabe wurde als beliebig falsche Lösung erklärt. |
| Komponenten, Änderung, Abnahme | language_evaluation.py, learning_hints.py; Rechtschreibziel benennen und auf ausdrücklichen Tipp fehlenden Buchstaben lokalisieren. Keine Ähnlichkeitsannahme als richtig. |
| Status/Ergebnis | Implementiert; bestehende strikte Sprachbewertung erhalten, Regressionen laufen. |

### F11 · Bausteine führen nach einem Fehler zu doppeltem Antworttext

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K18 |
| recommendation | Beim Wechsel zur Bausteinhilfe klaren Neubeginn anbieten oder vorhandene Antwort reparieren; ausgewählte Teile sichtbar markieren, Entfernen und Neustart ermöglichen; Kind soll keine verketteten Fehleingaben bereinigen müssen. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: Bausteine wurden an fehlgeschlagene Antwort angehängt und mehrfach auswählbar. |
| Komponenten, Änderung, Abnahme | unit_screen.languagePrompt; neue Bausteinhilfe leert alten Text, markiert verbrauchte Elemente und bietet Neu zusammensetzen. |
| Status/Ergebnis | Implementiert; gezielter Bediennachtest vorgesehen. |

### F12 · Mehrdeutige Einzelwörter ohne Kontext und undurchsichtige Korrektur

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K19 |
| recommendation | Wortbedeutung mit einfachem Beispielsatz präzisieren, zulässige Varianten abbilden; wenn gezielt das Heftwort gefragt ist, das klar sagen. Nach falschem Versuch verständlich erklären, warum hier exercise erwartet wird. |
| confidence | Fehlende Kontextanzeige und Ablehnung sichtbar; exakte im Heft bestätigte Übersetzungsvarianten noch nicht geprüft |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Mehrdeutigkeit ist real; unbekannte exercise/practice-Varianten dürfen nicht global richtig werden. |
| Komponenten, Änderung, Abnahme | vocabulary.task_for/evaluation; ausdrücklich Heftwort verlangen, vorhandenen Kontext und bestätigte Varianten verwenden; neue Bedeutung separat bestätigen. |
| Status/Ergebnis | Strikte Bedeutungs-/Richtungsprüfung erhalten. Kein automatisches Wörterbuch oder ungeprüfte Synonyme ergänzt. |

### F13 · Kind muss die Bewertungsregeln seiner Wortkarten selbst konfigurieren

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K21 |
| recommendation | Einfacher Ablauf Das Wort stimmt nicht mit markiertem Heftausschnitt und korrigierbarem Vorschlag. Varianten automatisch prüfen; Änderungsverlauf und gegebenenfalls Elternfreigabe statt komplexer Fachformulare. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: Wortkorrektur zeigte fortgeschrittene Antwortregeln sofort. |
| Komponenten, Änderung, Abnahme | vocabulary_screen.edit; Wort/Bedeutung/Kontext zuerst, weitere erlaubte Antworten nur aufgeklappt, bestehende Revisionen/Antworten erhalten. |
| Status/Ergebnis | Implementiert; Oberflächentest folgt. Kinder müssen keine Varianten pflegen, um zu üben. |

### F14 · Fehlerhafte Wortimport-Zeilen bleiben ohne sichtbare Anleitung

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K22 |
| recommendation | Fehler direkt an Zeile 2 zeigen; Beispiel plus einfache Eingabefelder Wort/Bedeutung anbieten; gültige Zeilen erhalten. Leeren Prüfschritt deaktivieren oder mit verständlichem Hinweis versehen. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: ungültige Importzeilen nur per flüchtiger Meldung. |
| Komponenten, Änderung, Abnahme | vocabulary_screen.importDialog; betroffene Zeilennummern direkt am Feld, konkretes Wort=Bedeutung-Beispiel, gültige Eingabe bleibt stehen. |
| Status/Ergebnis | Implementiert; Feldregression/Browserprüfung folgt. |

### F15 · Themenliste zeigt interne Zustände, Dopplungen und falsches Datum

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K25, K41 |
| recommendation | planned/ready aus Kindersicht ersetzen durch Morgen / Bereit / Ich bereite vor; Datum nie aus Nullwert ableiten, ähnliche Themen zusammenführen oder Unterschiede klar benennen. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: nicht gesetzter Unix-Zeitpunkt wurde 1970, einzelne Statusnamen wurden roh dargestellt. |
| Komponenten, Änderung, Abnahme | collection_screen, ui.statusLabel, app_version/build_release; fehlende Zeit nicht rendern, deutsche Statusnamen, tatsächliche Buildversion. |
| Status/Ergebnis | Implementiert. Echte verschiedene Runden/Quellen werden nicht pauschal zusammengelegt; neue Auftragdubletten separat verhindert. |

### F16 · Lernstand verlangt Zahleninterpretation statt Orientierung

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K26 |
| recommendation | Eine kindgerechte Aussage Du kannst … und ein nächster Mini-Schritt. Genaue Statistik optional aufklappen; nachhaltige Abrufleistung von bearbeiteten Aufgaben unterscheiden. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Vorhandene Praxiszählung und spätere Prüftage sind unterschiedliche Beobachtungen; Zahlen brauchen Einordnung. |
| Komponenten, Änderung, Abnahme | practice_evidence, learning_progress, coaching_panel, ParentLearningBrief; alle beantworteten Übungen vorn, spätere unabhängige Abrufe getrennt. |
| Status/Ergebnis | Bestehendes Modell erhalten. Kein Einzeltreffer wird als dauerhaftes Können oder Note ausgegeben. |

### F17 · Seite geprüft verdeckt ungeklärte Quellstellen

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K28, K29 |
| recommendation | Unsichere Tabellenfelder direkt im Bild markieren und gezielt klären; Bestätigung der Texterkennung von fachlicher Richtigkeit unterscheiden. Kind darf nicht pauschal Qualitätsprüfer eines Stoffes sein, den es erst lernen soll. |
| status | beobachtet – vorläufige Bewertung |
| Aktueller Nachtest/Ursache | Bestätigt: Bestätigungskennzeichnung konnte Qualitätsprüfung suggerieren; Unsicherheiten wurden geleert. |
| Komponenten, Änderung, Abnahme | materials.confirm, learning.material_data, extraction/worker/coaching/study_path; Text übernommen, Unsicherheiten erhalten und in Erzeugung weitergeben. |
| Status/Ergebnis | Backendtest für erhaltene Warnungen bestanden. Keine fachliche OCR-Prüfung oder genaue Bildpositionsmarkierung behauptet. |

### F18 · Neue Heftfotos startet in altem Lernweg mit bereits gesammelten Bildern

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K30, K41 |
| recommendation | Neue Aufnahme direkt starten; schon verarbeitete Seiten klar kennzeichnen. Text-/Bildähnlichkeit nutzen, um versehentliche Dubletten vor Bestätigung anzusprechen und Zusammenführen zu ermöglichen. |
| confidence | Vorhandene Seiten bei OCR nicht erneut zur Prüfung verlangt. Zwei inhaltsgleiche Testvarianten wurden separat erkannt und bestätigt, ohne sichtbare Dublettenwarnung. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: Einstieg führte in vorhandenen Tagesweg statt neue Aufnahme. |
| Komponenten, Änderung, Abnahme | SchoolDayScreen.startWithPhotos, Router capture=1, Dashboard/Heftaktion; neuer Fotobereich, nur unbestätigte Fotos; bestehende bestätigte Seiten bleiben im Tagesweg. |
| Status/Ergebnis | Implementiert. Bloßes Öffnen ist GET; Erweiterung erst bei wirklicher neuer Aufnahme. |

### F19 · Namenschutz beim Fotografieren aktiver unterstützen

| Feld | Stand |
|---|---|
| priority | P3 |
| evidence | K30 |
| recommendation | Zuschnitt ist vorhanden und wurde praktisch getestet. Ergänzend direkte Bildmarkierung/optionale Namenshilfe und gut sichtbare Vorschau anbieten. Echte Kamera und Aufnahmequalität auf Smartphone noch testen. |
| status | vorhandene Funktion; Verbesserungsvorschlag, kein Fehlend-Befund |
| Aktueller Nachtest/Ursache | Zuschnitt/Metadatenentfernung waren vorhanden, aber wenig auffällig. |
| Komponenten, Änderung, Abnahme | CropDialog; größere Vorschau, benannte Ränder/Ecken, Namenschutz am vorhandenen Aufnahme-/Zuschnittschritt, EXIF-freies Ergebnis. |
| Status/Ergebnis | Bedienung verbessert; keine automatische zuverlässige Erkennung persönlicher Namen behauptet. |

### F20 · Fotoübernahme verzögert, Rückmeldung und sichtbares Entfernen fehlen

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K34 |
| recommendation | Unmittelbar lokalen Platzhalter/Übernahmefortschritt pro Foto anzeigen, bis Speicherung bestätigt ist; Doppeleinreichen verhindern und jedes neue Foto mit sichtbarem Entfernen/Rückgängig versehen. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: verzögerte lokale Bildarbeit und alte Fotos erschweren Rückmeldung. |
| Komponenten, Änderung, Abnahme | school_day_screen, compute(encodeMaterialCrop), PendingUploads; sichtbare Übernahme, nur neue Fotos im Sammelschritt, native Bildverarbeitung separat. Bestätigte Seiten geschützt. |
| Status/Ergebnis | Implementiert; Web-CPU bleibt browserbedingt, keine künstliche Sofortgarantie. Fotoentfernen und Wiederaufnahme werden bedient. |

### F21 · Bildzuschnitt ist schwer zugänglich und zeigt eine sehr kleine Vorschau

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K33 |
| recommendation | Große Bildvorschau mit direkt ziehbarem Rahmen; Randregler optional. Semantische Namen, korrekte Werte und Tastaturbedienbarkeit prüfen. |
| status | im früher geladenen Client beobachtet; Versionsnachtest offen |
| Aktueller Nachtest/Ursache | Bestätigt: kleine Vorschau und unbenannte Randsteuerung. |
| Komponenten, Änderung, Abnahme | CropDialog; 40% hohe begrenzte Vorschau, gezogene Ecken sowie weiterhin beschriftete Prozentregler und 48px-Bedienung. |
| Status/Ergebnis | Implementiert; Widget-/Browserprüfung folgt. Keine vollständige WCAG-Zertifizierung behauptet. |

### F22 · Strenge Heftbindung lässt normale Verständnisfragen unbeantwortet

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K35 |
| impact | Kind kommt beim grundlegenden Warum nicht selbstständig weiter; Elternentlastung scheitert genau bei fehlendem Vorwissen. |
| recommendation | Heftbeleg und ergänzende geprüfte Erklärung klar unterscheiden. Eine kuratierte alters-/lehrplanpassende Wissensbasis für kurze Zusatzklärungen einsetzen, etwa beim Wal. Verständnis mit einer Rückfrage prüfen; bei Unsicherheit einen passenden konkreten Weiterweg statt Sackgasse anbieten. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: nur Heftquellen erlaubten keinen Weg zur Walfrage. |
| Komponenten, Änderung, Abnahme | foundations.py, tutor_schemas/tutor; eng kuratierte eigene NOAA-basierte Ergänzung mit Herkunft, strikt als Zusatzwissen, keine neue Heftquelle oder erfundener Heftbeleg. |
| Status/Ergebnis | Drei Tutorregressionen bestanden. Ergänzungsbestand bewusst begrenzt; unbekanntes Grundwissen nicht automatisch behauptet. |

### F23 · Lerntipps passen nicht automatisch zur konkreten Frage

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | K36 |
| recommendation | Frage, Fehlkonzept und Alter für Auswahl nutzen: Wal→Säugetiere im Wasser. In-App-Kurzklärung zuerst; externe Empfehlungen als optionale Vertiefung mit klarer Zugangskennzeichnung. Kein selbstständiges Navigieren durch eine fremde Abo-Plattform als nötiger Hilfeschritt. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: Tutor-Tipps nutzten den gesamten Hefttext und übergingen die konkrete Frage. |
| Komponenten, Änderung, Abnahme | catalog_jobs/search/import/ai, learning_tips; Matcher tips-v2 verwendet Frage+Antwort im Tutor, lokale revidierte Zuordnung ohne zusätzlichen KI-GET. |
| Status/Ergebnis | Katalog-/ID-/Versionsregressionen bestanden. Keine erzwungenen Treffer oder erfundene Klassenbeziehungen. |

### F24 · Interaktive KI-Übung benötigt Umwege über ein Frageformular

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K47 |
| recommendation | Frage stellen/Frage beantworten klar unterscheiden; nach KI-Frage direkt eine einfache Antwortfläche zeigen, Gesprächszusammenhang sichtbar lassen und für sehr einfache Schritte zeitnahes Feedback liefern. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: Rückfrage erschien als Textbaustein zum Kopieren statt direktes Gespräch. |
| Komponenten, Änderung, Abnahme | tutor_sheet, tutor_schemas; eigene Lehrerfrage sichtbar, Deine Antwort/Antwort senden mit reply_to, Kontext bleibt offen, andere Frage bewusst wählbar. |
| Status/Ergebnis | Implementiert; direkte Gesprächsregression/Browserprüfung folgt. Jede Antwort bewusst reserviert, keine Daueraufnahme. |

### F25 · Tageszielanzeige widerspricht dem freiwilligen Lerntag

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | K46, K48 |
| recommendation | Ohne eingeplantes Mindestziel kein pauschales Tagesziel erreicht anzeigen. Freiwillige Aktivität, Pflicht-Hausaufgabe und fester Zeitplan klar unterscheiden; kindgerecht heute genug/optional weiter darstellen. |
| status | im aktuell geladenen Stand belegt |
| Aktueller Nachtest/Ursache | Bestätigt: Tageszielmet-Flag wurde auch an freien Tagen vor goal_required ausgewertet. |
| Komponenten, Änderung, Abnahme | learning_time und CoachingPanel; kein erfülltes Mindestziel an frei/pausiert, freiwillige Übung zählt trotzdem als Aktivität. |
| Status/Ergebnis | Isolierter Sonntagstest mit >20 real gespeicherten Minuten bestanden; Zeitzonen-/Pausenregressionen laufen. |

### EF01 · Korrekte Antwort erzeugt trotz KI-Bestätigung weiteren Betreuungsbedarf

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | E05, K45 |
| recommendation | Rationale Gleichwertigkeit fest prüfen; Lernstatus und KI-Text aus denselben Fakten erzeugen. Falsch, unbewertet und richtig mit Formhinweis getrennt darstellen; bei offenen Fällen einen konkreten Klärungsschritt anbieten. |
| Aktueller Nachtest/Ursache | Entspricht F05: fachlich richtiger Bruch offen, KI-Kommentar behauptete mit Hilfe gespeichert. |
| Komponenten, Änderung, Abnahme | Zentraler Evaluator, auditierte Nachprüfung, Faktenprojektion für Rückblick/Eltern, keine Elternalarmierung aus bloß offener Bewertung. |
| Status/Ergebnis | Neue konsistente Antwort-/Mastery-/Exporttests bestanden; keine echten historischen Kinderantworten verändert. |

### EF02 · Elternübersicht überträgt Priorisierung und Bewertung zurück an Eltern

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | E04, E05 |
| recommendation | Drei begründete Hinweise statt Statistikflut: Was gelingt, welchen nächsten Schritt übernimmt die App, wofür braucht es tatsächlich einen Elternteil? Automatische Schwerpunktsetzung mit einfacher Änderungsmöglichkeit. |
| Aktueller Nachtest/Ursache | Bestätigt: lange Detailseite ohne kurze Entscheidung zuerst. |
| Komponenten, Änderung, Abnahme | ParentLearningBrief: Das gelang / Das übernimmt die App / Jetzt wichtig, Fakten aus gespeichertem Ledger. Technische und fachliche Probleme getrennt, echte Hilfewünsche gesondert. |
| Status/Ergebnis | Implementiert, weitere Details erreichbar. Kein versprochener automatischer Auftrag ohne eigene bewusste Aktion. |

### EF03 · OCR-Aufträge erst bündeln, deduplizieren und bestätigen

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | E07 |
| recommendation | Überschrift und Ausdruck zu einer Aufgabe bündeln; gleiche Seiten/gleiche Aufgaben erkennen; Vorschau vor Verbindlichkeit; kein automatischer Pflichtauftrag aus einer Übungsüberschrift. |
| Aktueller Nachtest/Ursache | Bestätigt: rohe homework-Zeilen wurden einzeln automatisch verbindlich, Bestätigung löschte/erzeugte Aufträge neu. |
| Komponenten, Änderung, Abnahme | material_tasks, Assignment-Provenienz/0021, TaskDialog; Überschriften bündeln, Beispiele/unklar/Pflicht wählen, gleicher Tag/Quelle/Inhalt idempotent, andere Termine erlaubt, veraltete Quelle blockiert neue Planung. |
| Status/Ergebnis | Neue Import-/Deduplizierungs-/Korrekturregressionen bestanden. Alte echte Aufträge nicht gelöscht oder heimlich bereinigt. |

### EF04 · Technikdetails aus Elternentscheidungen entfernen

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | E10, E16 |
| recommendation | Verständlicher Wochenrückblick und Verbrauch pro erfolgreichem Vorgang; technische Kosten-/Eventdetails in Diagnoseansicht. |
| Aktueller Nachtest/Ursache | Bestätigt: active_time und weitere Rohereignisse in Hauptchronik. |
| Komponenten, Änderung, Abnahme | dashboard.activityLabel/Chronik; verständliche Lernereignisse zuerst, technische Ereignisse nachgeordnet aufklappbar. Ursprung einer Hausaufgabe trotz Elternänderung erhalten. |
| Status/Ergebnis | Implementiert; Elternlesen isoliert geprüft: keine Kinderzeit/Antwort/Mastery, Schreibpfade403. |

### EF05 · Hilfe bei technischen Problemen absichern

| Feld | Stand |
|---|---|
| priority | P1 |
| evidence | E16 |
| recommendation | Fehlversuche transparent behandeln, keine Angst vor Hilfekosten im Kinderfluss; vorhandene Erklärungen und offline verfügbare Basisübungen als belastbaren Fallback anbieten. |
| Aktueller Nachtest/Ursache | Kontingente/Fehler dürfen Hilfe nicht wegnehmen, Kosten müssen ehrlich bleiben. |
| Komponenten, Änderung, Abnahme | Vorhandene gespeicherte Erklärungen/Quellen/Antworten und Elternhilfewunsch bleiben ohne neue KI nutzbar; keine Providerumstellung oder Quotenlockerung. |
| Status/Ergebnis | Bestehende Rechte-/Quoten-/Fehlerpfade in Gesamttests. Unbekannte Kontokosten bleiben unbekannt, keine pauschale Rückerstattung behauptet. |

### EF06 · Meldungen zur konkreten Aufgabe führen

| Feld | Stand |
|---|---|
| priority | P2 |
| evidence | E11, E18 |
| recommendation | Automatische Paketmeldungen bündeln, Absender und Bezug klar nennen; Klick öffnet genau die relevante Seite und notwendige Aktion. |
| Aktueller Nachtest/Ursache | Bestätigt: automatischer Status ohne präzises Ziel konnte zu allgemeiner Heute-Seite führen. |
| Komponenten, Änderung, Abnahme | Message.context/0021, schemas/learning/notification_inbox/school_preparation und Dashboard; eigenes geprüftes Unit/Material/Day-Ziel, System/Eltern/Kind unterscheiden. |
| Status/Ergebnis | Eigentums- und exakter Inbox-Zieltest bestanden. Bestehende Firebase-/Ruhezeitenfreigaben unverändert, keine Zustellung daraus ableiten. |

## Maßnahmen und vollständiger Fallbezug

| Maßnahme | Priorität | Beobachtungsbezug | Stand |
|---|---|---|---|
| R01 Bewertung und Lernstatus aus einer verlässlichen Grundlage ableiten | P1 | F05, K45, E05 | Umgesetzt; rationale Bewertung/Audithistorie/Konsistenz gezielt geprüft, vollständiger Abschlusslauf folgt. |
| R02 Hausaufgaben vor dem Einplanen bündeln und auf Dopplungen prüfen | P1 | E07, F18 | Umgesetzt; gebündelte Vorschau, Beispiele/unklar, Idempotenz, andere Tage/Termine gezielt geprüft. |
| R03 Hilfen am konkreten Fehler ausrichten | P1 | F04, K07, K43 | Umgesetzt; Teilurteile und verschiedene Hinweise, Backend + 320px-Rückmeldung geprüft. |
| R04 Den Tutor zu einem direkten Lernpartner machen | P1 | F22, F23, F24, K35, K36, K47 | Umgesetzt; kuratiertes Grundwissen, konkreter Matchingkontext, direktes Antwortfeld geprüft; öffentliche Providerprüfung folgt. |
| R05 Die Kinderoberfläche auf einen klaren nächsten Schritt konzentrieren | P1 | F08, F15, F25, K41, K46, K48 | Umgesetzt; vorhandene Hauptaktion erhalten, Status/Datum/Fotostart verbessert;345 vollständige Fluttertests grün. |
| R06 Eltern mit einer kurzen Entscheidungshilfe entlasten | P1 | EF01, EF02, E04, E05, E10 | Umgesetzt; kurze Elternentscheidung und technische Diagnose getrennt, Elternleserecht/Zeitzähler isoliert geprüft. |
| R07 Vorhandene Wiederholungen zu einer nachvollziehbaren Lernfolge verbinden | P2 | F09, F16, E14, E15 | Bestand erhalten; Richtungen/Fähigkeiten, spätere Abrufe und kleine Folgerunden regressionsgeprüft. |
| R08 Erklärungen in kurze, anschauliche Lernschritte übersetzen | P2 | F02, K04, K42 | Umgesetzt; schrittweise gespeicherte Erklärung und zugängliche Bruchbalken geprüft; keine Lernwirksamkeit zugesichert. |
| R09 Wortlernen fehlertolerant und kontextreich gestalten | P2 | F10, F11, F12, F13, F14 | Umgesetzt; Schreibziel, Bausteinneustart, bestätigte Varianten, fortgeschrittene Wortkorrektur und Zeilenfehler; keine globale Fuzzyannahme. |
| R10 Quellenqualität prüfen, ohne das Kind zur Redaktion zu machen | P2 | F17, F19, F20, F21, K28, K29, E09 | Umgesetzt; Quellenwarnungen, ausdrückliche Aufgabe, größerer Zuschnitt und neue Fotos; keine automatische fachliche OCR-Abnahme. |
| R11 Lernzeit, Pausen und Motivation am Kind ausrichten | P2 | F07, F25, E06, E07 | Bestand/Fehler korrigiert; reales Zeitminimum bleibt bindend, frei/pausiert ohne tägliche Zielbehauptung. Kein unbegrenzter Planberg. |
| R12 Fortschritt als Können mit nächstem Schritt erklären | P2 | F06, F16, E03, E14 | Bestand erklärt; alle Antworten im Praxisstand, spätere selbstständige Abrufe extra. Nachprüfung aktualisiert ursprünglichen Beleg statt neuen Lerntag. |
| R13 Bedienung und Rückmeldungen zugänglich machen | P2 | F03, F08, F14, F21, E12 | Umgesetzt; kleine Displays/konkrete Feldfehler/benannte Kontrollen geprüft. Physische Audio- und vollständige WCAG-Abnahme bleiben separat. |
| R14 Hilfen auch bei Fehlern und Kontingentgrenzen erreichbar halten | P2 | E16, EF05 | Bestand erhalten; gespeicherter Stoff und menschlicher Hilfewunsch ohne neue KI erreichbar. Fehler und unbekannte Kontokosten nicht verschwiegen. |
| R15 Kommunikation, Privatsphäre und Rollen klar halten | P2 | K49, E11, E17, E18, E19 | Umgesetzt; rollen-/sitzungsgebundene Kontextziele, Systemmeldungen und Hilfewünsche, Elternlesen ohne Kinderaktivität. Keine neue Push-Zustellbehauptung. |

## Einzelbeobachtungen

| Protokoll | Testfall | Bereich | Ursprünglicher Prüfstatus | Aktueller Nachweis |
|---|---|---|---|---|
| Kind | K01 | Heute | baseline | Vorhandene Hauptaktion erhalten; child_home/routine/minimum-Tests grün; echter Browsernachtest folgt. |
| Kind | K02 | Lernrunde | pass | Bestehende geführte Lernrunde regressionsgeprüft; neuer echter Provider-/nativer Ablauf folgt. |
| Kind | K03 | Pausen | pass | Pausen/Resume und echte Zeitmessung in vollständigen Fluttertests bestanden. |
| Kind | K04 | Hilfe | pass | Gespeicherte Hilfe erhalten, gestufte Hinweise/Teilfeedback ergänzt; Regression bestanden. |
| Kind | K05 | Erklärung/Vorlesen | partial | Schrittweise Erklärung/normal-langsam/Stopp geprüft; kein physischer Ton- oder Mikrofontest. |
| Kind | K06 | Zeitmessung | fail | Historische Auffälligkeit aktuell nicht bewiesen; Ticker-/Idle-/Resync-Regression bestanden. |
| Kind | K07 | Fehlerfeedback | fail | Bestätigten Fehler korrigiert: Teilurteile, falscher Hund-Paarfokus, verschiedene Hinweise; Backend/Widget grün. |
| Kind | K08 | Wiederholen | pass | Getrennte Praxis und spätere Wiederholung erhalten, keine künstlichen Prüftage hinzugefügt. |
| Kind | K09 | Freie Antwort kurz | partial | Hilfen-/Vorlagen-/Versuchsgründe getrennt. Alter Fall ohne historischen Grund nicht neu diagnostiziert. |
| Kind | K10 | Freie Antwort Satz | fail | Exakte synthetische Satzparaphrase und Negativfälle regelgebunden geprüft; unbekannte Sätze bleiben offen. |
| Kind | K11 | Rückblick | partial | Gespeichertes Ergebnis führt Rückblick an; KI-Prosa darf keine Speicherung/Hilfe erfinden; Regression grün. |
| Kind | K12 | Plan/Transparenz | pass | Plan verteilt bereits; allgemeine Aufforderung zur Elternpriorisierung bei normalem Vorrat entfernt. |
| Kind | K13 | Nachrichten/Benachrichtigungen | pass | Bestehende Glocke/Lesestatus/Push-Opt-in erhalten; genaues Inhaltsziel ergänzt. Keine neue Zustellung behauptet. |
| Kind | K14 | Sprachwerkstatt-Reparatur | in_progress | Vorhandene begrenzte Sprachprojektreparatur erhalten; Wiederholungs-/Fehlerregression grün. |
| Kind | K15 | Wörter-Übersicht | partial | Wortübersicht vereinfacht, verständliche Herkunft/Termine. Vorhandene Filter/Pagination erhalten. |
| Kind | K16 | Wörter-Start | partial | Vorhandene kleine Runde und vier Modi erhalten, Fähigkeit/Richtung ausdrücklich getrennt. |
| Kind | K17 | Wort-Schreibfehler | fail | Schreibziel und Hinweis auf fehlenden Buchstaben statt Fuzzy-Richtig; Sprachregressionen erhalten. |
| Kind | K18 | Bausteinhilfe | partial | Bausteine leeren alten Fehltext, sind einmal auswählbar und zurücksetzbar; noch gezielter Browsernachtest. |
| Kind | K19 | Wortauswertung | partial | Nur bestätigte Bedeutungsvarianten, Heftwort ausdrücklich gefragt; kein ungeprüftes exercise/practice-Gleichsetzen. |
| Kind | K20 | Sprachprojekt-Reparatur | pass | Bestehende Reparatur-/Aufbewahrungs-/Idempotenztests erhalten; kein fehlendes Sprachprojekt neu behauptet. |
| Kind | K21 | Wortkarte/Korrektur | partial | Wortkorrektur mit aufklappbaren Varianten und erhaltenen alten Antworten/Revisionen. |
| Kind | K22 | Wortimport | partial | Importfehler direkt am Feld mit Zeilennummern und Beispiel. Eingaben bleiben erhalten. |
| Kind | K23 | Sprachwerkstatt/Satzkontexte | pass | Bestehende quellengebundene Satz-/Grammatikprojekte regressionsgeprüft, keine neuen Kurse. |
| Kind | K24 | Sprachrunde-Abschluss | pass | Bestehendes getrenntes Wortergebnis erhalten; keine sicheren Schreibkenntnisse aus Erkennen abgeleitet. |
| Kind | K25 | Themenübersicht | fail | Interne Statusnamen/Nullzeit korrigiert; reale verschiedene Runden bleiben getrennt. |
| Kind | K26 | Lernstand gesamt | partial | Praxisstand und spätere Prüftage erhalten; Elternkurzsicht ergänzt, keine Notenprognose. |
| Kind | K27 | Später KI-Rückblick | partial | Auditierte Nachprüfung und verbindliche Faktenprojektion geprüft; kein KI-Urteil als sichere Neubewertung. |
| Kind | K28 | Heftübersicht | partial | Aktueller kompakter Hefterbestand erhalten; keine fehlende Fachsammlung aus älterem Client behauptet. |
| Kind | K29 | Heftqualität | partial | OCR-Warnungen bleiben sichtbar und in Erzeugungsquellen; Bestätigung heißt Text übernommen. |
| Kind | K30 | Foto-Import | partial | Neue Fotos über capture=1; nur unbestätigte Seiten im Sammelschritt, bestehender Tagesweg erhalten. |
| Kind | K31 | Kinderkonto | pass | Eigener Kinderzugang und Sitzungs-/Familienrechte erhalten; keine administrativen Kinderrechte. |
| Kind | K32 | Datenschutzhinweise | partial | Datenschutzinformationen erhalten; keine neue juristische oder Anbieterfreigabe behauptet. |
| Kind | K33 | Foto-Zuschnitt | partial | Größerer ziehbarer Zuschnitt, beschriftete Prozentregler, native separate Verarbeitung; Cropregression grün. |
| Kind | K34 | Foto-Übernahme/Undo | partial | Sichtbare Verarbeitung/Entfernen neuer Fotos; lokale Wiederaufnahme/Logout-Regressionsprüfung grün. |
| Kind | K35 | Freie KI-Lernhilfe | partial | Kuratiertes Wal-Grundwissen mit NOAA-Herkunft getrennt vom Heft; gezielte Tutorregression grün. |
| Kind | K36 | Lerntipps | partial | Tutor-Matching aus Frage+Antwort statt gesamtem Hefter; kein Zusatzmodell auf GET, Katalogregression grün. |
| Kind | K37 | OCR Ende-zu-Ende | pass | Neuer automatischer OCR-Pfad erhält Bestätigung; Aufgabenübernahme ausdrücklich und doppelt geschützt. |
| Kind | K38 | Lerntipp-Filter | partial | Manuelle Themenwahl/Stufenbelege erhalten; konkrete Frage als automatischer Matchingkontext ergänzt. |
| Kind | K39 | Wortmodus Bedeutung | pass | Vorhandener Bedeutungsmodus unverändert als Erkennungsbeleg, andere Fähigkeiten nicht hochgestuft. |
| Kind | K40 | Aktuelle Heftansicht | pass | Bildhefter/Fotoalbum unverändert erhalten, Mine-Filter nur belegte Fächer; vollständige Flutterregression grün. |
| Kind | K41 | Aktueller Stand/erneute Prüfung | fail | Tatsächliche Buildversion, deutsche Zustände, kein 1970; neue doppelte Pflichtaufträge verhindert. |
| Kind | K42 | Neue Mathe-Verstehensphase | pass | Gespeicherte Verstehensphase in kurzen Schritten; Bruchbalken bei geöffneter Rechenhilfe; Widgettest grün. |
| Kind | K43 | Aktuelle Mathe-Fehlerhilfe | pass | Bereits brauchbare Mathematikhilfen erhalten, weitere Tipps unterscheiden sich statt Wiederholung. |
| Kind | K44 | Zeitnachtest aktueller Stand | partial | Kein aktueller Rücksprung bewiesen; Resync/Serverminimum/Idle/Route-Regressionsprüfungen grün. |
| Kind | K45 | Gleichwertige Bruchantwort | fail | 6/16=3/8 bei nicht verlangtem Kürzen korrekt; Form/Wert/Hilfe getrennt; Backend und Nachprüf-UI grün. |
| Kind | K46 | Tagesziel-Rückblick | partial | Frei-/Auszeit nicht als erfülltes Tagesminimum; tatsächliche freiwillige Aktivität zählt. Sonntagstest grün. |
| Kind | K47 | Aktives Tutorengespräch | partial | Lehrerfrage direkt beantworten mit reply_to, bewusstes Senden und erhaltenem Verlauf; Widgettest grün. |
| Kind | K48 | Abschlusszustand Heute | partial | Tageszielanzeige und freiwilliger Tag angeglichen; tatsächliche Serversekunden entscheiden weiter. |
| Kind | K49 | Abschlusszustand Lernstand | pass | Praxis und spätere Abrufe bleiben erhalten; keine neue pauschale Lernstandsdiagnose. |
| Kind | K50 | Tutorengespräch abgeschlossen | pass | Gespeicherter Tutorverlauf/Abschluss erhalten; kein dauerhaft laufender Chat oder automatische Modellschleife. |
| Eltern | E01 | Familienstart | baseline | Vorhandene Familien-/Kinderkarten erhalten, kurze Entscheidung vor Details ergänzt; Eltern-Widgettests grün. |
| Eltern | E02 | Datumswechsel | context | Europe/Berlin/Tageswechsel weiter servergebunden; kein neuer Diagnosebefund aus Uhrzeitunterschieden. |
| Eltern | E03 | Eltern-Lernstand | pass | Fach/Thema/Runde aus demselben Attempt-Ledger; Praxis und spätere Abrufe getrennt. |
| Eltern | E04 | Überblick und Entlastung | partial | Drei kurze Elternantworten zuerst, weitere Details erreichbar; Eltern-Widgettests grün. |
| Eltern | E05 | Mathe-Audit und Bewertung | fail | Rationale Bewertung, getrennte Hilfen und auditierte Nachprüfung; aktuelle Ableitungen statt KI-Speicherbehauptung. |
| Eltern | E06 | Planung | Beobachtung | Bestehender Wochenplan verteilt kleine Portionen, tatsächliches Minimum/Pause/Elternstartdaten erhalten. |
| Eltern | E07 | Auftragsübernahme | Beobachtung | Gebündelte Vorschau/Bestätigung, keine Überschrift als Pflicht, gleicher Tag doppelt geschützt, anderer Termin möglich. |
| Eltern | E08 | Auftragsbearbeitung | Beobachtung | Ursprung notierte Hausaufgabe trotz Elternänderung erhalten; offen zählt nur verbindlich/bestätigt. |
| Eltern | E09 | Heftverwaltung | Beobachtung | Quellenkorrekturen erhalten Belege, markieren veraltete Aufträge, keine historischen Antworten löschen. |
| Eltern | E10 | Verlauf | Beobachtung | Verständliche Lernchronik; raw active_time/vocabulary_exposure in aufklappbarer Diagnose. |
| Eltern | E11 | Nachrichten | Beobachtung | Konkrete Kontexte und System/Kind/Eltern-Absender ergänzt, Meldung/Hilfewunsch unterscheidbar. |
| Eltern | E12 | Auftragserstellung | Beobachtung | Kalender, gültige deutsche/ISO-Daten und Inline-Korrektur; echtes Formular-Lifecycleproblem behoben und getestet. |
| Eltern | E13 | Noten | Beobachtung | Bestehende Noten-/PDF-/Fachpriorisierung unverändert; vollständige Flutterregression bestanden. |
| Eltern | E14 | Fortschritt | Beobachtung | Alle Übungen zählen im gemeinsamen Praxisstand; spätere Abrufe kein erfundener Erfolg. |
| Eltern | E15 | Wörter | Beobachtung | Getrennte Fähigkeiten/Richtungen und Wortrevisionen erhalten; Wortansicht vereinfacht. |
| Eltern | E16 | Tarif/Nutzung | Beobachtung | Bestehende Reservierungs-/Quoten-/Kostenlogik erhalten, unbekannte Kosten nicht nullgesetzt. |
| Eltern | E17 | Konto | Beobachtung | Backendrollen und getrennte Sitzungen erhalten; keine neuen Verwaltungsrechte durch Sichtbarkeit. |
| Eltern | E18 | Benachrichtigungen | Beobachtung | Kontextlinks verbessert; Opt-in, Elternfreigabe, Ruhezeiten unverändert. Kein neuer Zustellnachweis. |
| Eltern | E19 | Zeitmessung (offen) | Beobachtung | Isoliert geprüft: Eltern-GETs erzeugen keine Kinderzeit/Antwort/Mastery; Start/Heartbeat403. Historische Ursache nicht bewiesen. |

## Technischer Abnahmestand und bewusste Grenzen

- Neue zentrale Regeln: rationale Ergebnisgleichheit getrennt von verlangter
  Darstellung, begrenzte Sachparaphrasen, kein globales unscharfes Akzeptieren.
  Sprachbewertung und mathematische Sonderziele bleiben getrennt.
- Nachprüfung ist ausdrücklich, versioniert und rollenbegrenzt. Ursprüngliche
  Antworten/Versuche/Zeit/Hilfen bleiben erhalten, auch in Export und Löschkaskade.
  Kind und Eltern können den vorherigen und aktuellen Bewertungsstand aufklappen.
  Eine offene Prüfung hat einen eigenen Lernwegzustand, keinen falschen Fehlerbeleg.
- Aufgabe/Beispiel/unklar wird gespeichert. Wiederholte Vorschau/Bestätigung,
  Textvarianten desselben Tags und wiederhergestellte Entscheidungen wurden
  geprüft; andere echte Termine bleiben möglich. `homework` als historischer
  Erkennungstext ist keine automatische Pflichtfreigabe.
- 345 vollständige Fluttertests vor der letzten Auditdarstellung bestanden;
  danach48 betroffene Tests, acht Audit-/Dialogtests und die eigene
  Bausteinregression bestanden. Abschließender vollständiger Lauf läuft erneut.
- Erster vollständiger PostgreSQLlauf927/929; beide veralteten Erwartungen
  (Headrevision und unveränderter Bestätigungsretry) korrigiert und Rechteprüfung
  verschärft.109 gezielte Tests,108 für die offene Bewertung und105 für den
  endgültigen Quellen-/Migrations-/Bewertungsstand bestanden. Keine Summierung
  überlappender Testzahlen als Anzahl unterschiedlicher Prüfungen. Letzter
  vollständiger Lauf folgt im finalen Handoff; ein Zwischenlauf wurde vor weiteren
  Korrekturen bewusst abgebrochen und zählt nicht als bestandener Gesamtlauf.
- Ruff und Flutteranalyse fehlerfrei. Web/Direct-/Play-Builds der41-Vorstufe,
  Paket/Signatur/16-KB-Ausrichtung und tatsächliches AAB mit bundletool1.18.3
  geprüft; finaler Build nach den letzten Darstellungen folgt. Kein SDK-Update.
  Vorhandene Pluginwarnungen betreffen Wasm-Trockenlauf und künftige
  Kotlin-Migration; keine Wasm-Unterstützung oder neue Audioabnahme behauptet.
- Unbekannte freie Aussagen bleiben konservativ offen. Der Ergänzungsbestand des
  Tutors ist gezielt kuratiert, kein allgemeines ungeprüftes Wörterbuch. Keine
  automatische zuverlässige fachliche OCR-Qualitätsprüfung, Bildstellenmarkierung,
  Diagnose tatsächlicher Fähigkeiten oder garantierte Lern-/Notenwirkung.
- Geladene gespeicherte Erklärungen und Antworten bleiben bei einem Anfragenfehler
  sichtbar. Ein vollständiger Offline-Neustart mit lokalem Lehrmaterialbestand
  ist keine neue zugesicherte Funktion. Antworten werden erst nach tatsächlicher
  Serverbestätigung als gespeichert/bewertet bezeichnet.
- Mikrofon/physischer Ton und ein begleitetes Verstehen durch echte Kinder
  brauchen getrennte Beobachtung. Widget-/Emulator-/Kontrasttests sind keine
  vollständige WCAG-Konformitäts- oder Lernwirksamkeitsstudie.
