Erweiterung20.10.2026: [Ausführbare Lernsteuerung und Belegspur](LEARNING_CONTROLLER_2026_10_20.md)
mit getrennten Quellenzielen, langfristigen Beobachtungen und gespeicherten Kurzplänen.

# Vom Schulstoff zum nachvollziehbaren Lernweg

Stand 19.10.2026. SCHULPILOT unterstützt das Verstehen und Üben des tatsächlich bestätigten Unterrichtsmaterials. Schulnoten geben einen zusätzlichen Hinweis auf Schwerpunkte. Sie ersetzen weder die Beobachtung beim Üben noch eine fachliche Diagnose durch Lehrkräfte. Verbesserte Schulnoten sind ein Ziel, keine zugesicherte Wirkung der Software.


## Zustandsbehaftete Steuerung ab Build45

Der zentrale Controller verbindet vorhandene Quellen, Lernziele, Attempt-Belege,
Planung und Ressourcen. Ablauf, endlicher Aktionsraum, Datenschutz und zehn
Szenarien stehen in [ADAPTIVE_OPENROUTER.md](ADAPTIVE_OPENROUTER.md).
Antwortentwürfe, betrachtete Medien und Modellvorschläge sind keine Kompetenz-
belege. Selbst gemeldetes Ansehen einer Erklärung wird bei der zugehörigen
noch offenen Aufgabe als Hilfe erfasst. Neue Anschlussfragen benötigen eine
eigene bewusste Aktion und Reservierung; vorherige Antworten bleiben unverändert.
Eine abgeschlossene Runde darf unabhängig vom offenen Zeitminimum enden.

## Fachliche Darstellung und offene Bewertung

Build44: Bruchaddition lässt gleich große Ganze, Erweitern und Zusammenführen
in drei bewusst gesteuerten Schritten betrachten. Farben werden durch A/B und
verbale Teilanzahlen ergänzt. Der Hilfedialog bekommt die konkrete Frage samt
Zahlen; seine Hilfe zählt nur für diese Frage. Alte globale Erklärungseinträge
behalten ihre ursprüngliche Bedeutung. Gespeicherte Unterstützungsgründe werden
bei Kind und Eltern angezeigt, fehlende Legacydetails ehrlich benannt.
Die lokale Nennerfehlerregel liefert erst einen Denkhinweis, nicht sofort das
Ergebnis. Gleichwertige Bruchwerte und ausdrücklich verlangte Form bleiben
getrennte Prüfungen.

Wurzel- und Bestäubungsschemata sind endliche, fachlich kuratierte
Erklärkomponenten. Alteinheiten erhalten sie nur mit passenden bestätigten
Quellenrevisionen und passender Aufgabenerklärung. Sie werden ausschließlich als
`solution` nach bewusster Erklärung oder abgeschlossener Antwort gezeigt. Kein
zusätzlicher Anbieteraufruf, kein automatisch aktivierter Biologiekurs. Für
andere Themen wird keine beliebige Grafik behauptet.

Aufgaben dürfen ergänzend eine versionierte `presentation` mit höchstens vier festen Inhaltsblöcken tragen. Jeder Block enthält einen wörtlichen Quellbeleg, einen Darstellungstyp aus dem Fachprofil und eine Offenlegungsstufe: `given`, gestufter Hinweis oder `solution`. Der Provider liefert keine freien Grafikkoordinaten, SVGs oder Netzwerkbilder. Backend-Schemata prüfen Fachtyp, Zahlen, Beschriftungen und fachliche Beziehungen vor dem Speichern; der Client stellt dieselben Daten als Flutter-Vektor, Tabelle oder Wortkarte dar und gibt eine verbale Bildbeschreibung an assistive Technologien weiter. Lösungen und Hinweise werden erst nach dem passenden Schritt projiziert.

Fachlich prüfbare Mathematik verwendet exakte Wertvergleiche. Eine gleichwertige Bruchantwort wie `6/16` gilt wie `3/8`, sofern die Aufgabe nicht ausdrücklich kürzen lässt. Bei einem ausdrücklich verlangten Format bleibt der Inhalt als richtig und die Form separat bewertbar. Andere Fächer erhalten keine globale Ähnlichkeitstoleranz. Reflexion, kreative Entscheidungen, Religion und körperliche Ausführung zählen nicht als eindeutig richtiges Können; sie bleiben als eigener Beitrag nachvollziehbar.

Für den Fachtest vom 19.10.2026 sind24 Fachprofile und je zwei lokale synthetische Quellfälle in `testdata/subject_cases_v1.json` festgehalten. Sie prüfen Schema, Quellenbindung, festgelegte Bewertung und Flutter-Layout bei schmaler/weiter Ansicht sowie100/200% Textskalierung. Diese Fixtures sind weder OCR-Nachweis noch vollständige Live-KI- oder Lernwirksamkeitsabnahme; der genaue Stand steht in [FACHTEST_2026_10_19.md](FACHTEST_2026_10_19.md).

## Der durchgängige Ablauf

Fotografierte Vokabellisten bleiben nicht nur Heftseiten: Sichtbare Wortpaare
und Lernsprache zusammen mit der Quelle bestätigen und in den persönlichen
Wortschatz übernehmen. Fehlende/mehrdeutige Bedeutungen zunächst klären;
Grammatikregeln nicht als Übersetzung ausgeben. Speichern ist noch keine
Lernleistung. Erst die anschließenden kurzen Abrufrunden erzeugen Attempts
und fähigkeitsbezogene Wiedervorlagen, sichtbar für Kind und Eltern.

Sprachlernen ergänzt diesen Ablauf innerhalb derselben Lernräume. Die genaue
Bewertungspolitik, getrennte Sprachfähigkeiten/Richtungen, Eintragsrevisionen,
Intervallregel und Werkzeugzuordnung stehen in [LANGUAGE_LEARNING.md](LANGUAGE_LEARNING.md).
Ein umgedrehter Kartenrücken ist keine Leistung. Modellbeispiel und eigener
Entwurf bleiben getrennt. Erst echte Antworten zählen; ein späterer selbstständiger
Abruf erhält eine eigene zeitliche Beobachtung. Neue Kontext- und Grammatikübungen
benötigen bestätigte Wörter/Unterrichtsquellen und eine bewusste Aktion.

1. Heft- und Arbeitsheftseiten abgeben; die Vorbereitung läuft im Hintergrund. Erkannte Inhalte und Unsicherheiten ausdrücklich prüfen. Ohne bestätigten Stoff werden daraus keine Aufgaben.
2. Elternaufträge, Termine, offene Schwierigkeiten und spätere Wiederholungen bestimmen die nächste überschaubare Portion. Aktuelle Schulnoten verändern die Fachgewichtung innerhalb derselben verfügbaren Zeit. Bestehende Pflichtziele bleiben erhalten.
3. Verstehen: kurze, altersgerechte Erklärung. Für ein im Heft belegtes Verfahren ein kleines gelöstes Beispiel mit Zwischenschritten; bei Sachthemen ein konkretes belegtes Beispiel. Kein unbekanntes Zusatzwissen als Voraussetzung.
4. Selbst anwenden: eine neue passende Aufgabe lösen. Bei Schwierigkeiten zunächst Hilfe zum nächsten Teilschritt, dann Erklärung oder eine eigene Heftfrage; Elternhilfe bleibt erreichbar. Hilfe wird gespeichert, nicht als selbstständige Lösung umgedeutet.
5. Konkrete Rückmeldung bei der eigenen Antwort lesen. Die Aufgabe, Antwort und Rückmeldung bleiben zusammen sichtbar. Fehler und unklare Bewertungen bestimmen gezieltes Nachlernen; das Kind fordert die nächste begrenzte Runde bewusst an.
6. Später mit neuen Aufgaben ohne vorgeschaltete Lösung erneut abrufen. Die Planung verteilt den Vorrat; vergessene Tage erzeugen keine wachsenden Pflichtberge. Das tatsächliche Zeitminimum bleibt unabhängig vom fachlichen Fortschritt.

Die neuen Erzeugungsaufträge erhalten eine abgeleitete Unterstützungsstrategie: `guided_example` bei aktuellen schulischen Schwerpunkten oder gespeicherten Schwierigkeiten/Unterstützung in einer der zwei jüngsten fachbezogenen Runden; ansonsten `practice_and_retrieval`. Die bestehenden Ziel-, Quellen-, Schema- und Quotenprüfungen bleiben maßgeblich. Gespeicherte Aufgaben werden nicht nachträglich umgeschrieben. Die Strategie ist eine Heuristik, keine Diagnose und keine bestätigte Aussage über allgemeine Fähigkeiten.

## Jede Übung zählt – zwei unterschiedliche Beobachtungen

Die führende Anzeige zählt **alle tatsächlich beantworteten Aufgaben**, auch freiwillige, an anderen Tagen und in begonnenen Runden. Bestehende gespeicherte Versuche sind sofort enthalten; kein künstlicher Neustart des Lernstands.

- Eine Aufgabe wird je Runde und Aufgabenkennung einmal gezählt. Wiederholte Versuche werden zusätzlich ausgewiesen.
- „Alleine gelöst“: der erste Versuch ist richtig und ohne erfasste Hilfe. „Mit Hilfe gelöst“ umfasst auch richtig nach einem weiteren Versuch. „Weiter üben“ und „Bewertung offen“ bleiben getrennt. Maßgeblich ist der letzte gespeicherte Versuch; die ursprünglichen Versuche bleiben in der Detailansicht erhalten.
- Die Themenanzeige verbindet alle Runden desselben bestätigten Fachs/Themas. Unterschiedliche Themen werden nicht durch eine vermutete semantische Übereinstimmung zusammengelegt. Mathe/Mathematik werden beim Fachabgleich gleich behandelt.
- Kind und Eltern können Fach → Thema → einzelne Runden mit serverseitiger Seitenteilung öffnen. Diese Lesezugriffe erzeugen keine Aufgaben und verändern keine Ergebnisse.
- Zusätzlich zeigt ein aufklappbarer Abschnitt, was an späteren Tagen selbstständig erneut abgerufen wurde. Drei erfolgreiche Prüftage über mindestens sieben Tage bleiben eine transparente **Produktregel**, keine wissenschaftliche Universalgrenze. Gewöhnliche Übungen zählen oben mit, ohne einen nicht durchgeführten späteren Abruf vorzutäuschen. Neue Hilfen können die strenge Beobachtungsfolge zurücksetzen, niemals die geleisteten Übungen löschen.

Für die quellengebundene langfristige Kompetenzableitung braucht eine alte Runde
einen passenden gespeicherten `UnitSource`-Revisionsbeleg. Ein bloßer historischer
`material_id` beweist nicht, welche Fassung der Seite damals verwendet wurde.
Solche Antworten bleiben unverändert in der allgemeinen Übungszählung und werden
im Lernzielgedächtnis als `historical_tasks` ausgewiesen; sie erzeugen keine
aktuellen sicheren Abrufbelege oder Wiedervorlage für inzwischen korrigierten
Stoff. Die Runde bleibt lesbar, ohne einen fehlenden Quellenstand nachträglich
aus der heutigen Seite zu erfinden.

## Noten und verständliche Planung

Nur berechtigte Eltern verwalten Noten. Familienmitglieder mit Leserecht sehen die Einträge; Kinder und Betriebsadministratoren erhalten keinen Notenzugriff. Erfasst werden Fach, optional Thema, Art, Datum, Wert, System 1–6 oder 0–15 Punkte, Gewicht 1–5 und optionale Notiz. Bearbeitung ist revisionsgebunden, wiederholtes Anlegen mit demselben Anfrageschlüssel erzeugt unter Parallelität keinen Doppeleintrag.

Für die Gewichtung zählen höchstens die fünf jüngsten datierten Noten je Fach aus 90 Tagen. Zusätzlich zählen lokal importierte, undatierte Einzelnoten des ausdrücklich bestätigten aktuellen Schuljahres. Sie behalten ihr belegtes Halbjahr, ohne ein Bewertungsdatum oder regionale Halbjahresgrenzen zu erraten. Enthält die Gruppe undatierte Noten, wird kein zeitlicher Trend berechnet. Innerhalb eines Systems wird ein ausdrücklich unverbindlicher gewichteter Eintragsschnitt angezeigt. Bei gemischten Systemen gibt es keinen erfundenen Gesamtschnitt. Für die Priorität werden beide Skalen auf Unterstützungsbedarf 0–1 abgebildet: `(Note-1)/5` bzw. `(15-Punkte)/15`. Ab 0,4 leichtes, ab 0,6 stärkeres Gewicht; ein schwächerer Verlauf der letzten zwei gegenüber den vorherigen zwei Einträgen um mindestens 0,15 berücksichtigt zusätzlichen Übungsbedarf. Unter vier Einträgen kein Verlauf behauptet. Diese Schwellen sind nachvollziehbare Produktentscheidungen.

Der Wochenvorschlag balanciert geplante Fachminuten mit Gewicht 1/2/3. Das erhöht bei ausreichend vorhandenem Material die Häufigkeit eines Schwerpunktfachs, ohne andere Fächer pauschal zu entfernen, Zeitziele zu verlängern oder Pflichttermine zu verdrängen. Es ist keine garantierte Stundenquote. Eltern können die Notengewichtung abschalten und weiterhin eigene Themen, Lerntage, Pausen und Termine setzen. Eine einzelne Note löst weder einen KI-Aufruf noch eine Elternwarnung aus.

„Passendes Lernziel anlegen“ übernimmt nach ausdrücklicher Bestätigung ausschließlich ein tatsächlich vorhandenes bestätigtes Material desselben Fachs und gegebenenfalls Themas in einen verbindlichen Elternauftrag. Fehlt es, wird das verständlich gemeldet. Löschen der Note löscht keinen bereits angenommenen Lernauftrag. Weitere Übungen werden erst über die vorhandenen ausdrücklichen Lernaktionen reserviert.

Schulnoten und Notennotizen werden nicht automatisch an den KI-Anbieter übermittelt; nur die abgeleitete Unterstützungsstrategie wird ergänzt. Die neuen Einträge gehören zum privaten Familienexport und zur normalen Konto-/Kinderlöschung. Höchstaufbewahrung 365 Tage ab Speicherung; bestehende Backup- und Löschabgleichregeln gelten. Keine Notenprognosen, Diagnosen oder öffentlichen Ranglisten.

## Forschungsgrundlage und Grenzen

- [IES/WWC, Organizing Instruction and Study, 2007](https://ies.ed.gov/ncee/wwc/PracticeGuide/1): Abrufübungen, verteiltes Lernen sowie Wechsel zwischen gelöstem Beispiel und eigenem Problemlösen. Der Leitfaden unterscheidet die Evidenzstärke; nicht jede einzelne Empfehlung ist gleich stark abgesichert.
- [EEF, Metacognition and Self-Regulated Learning, 2. Auflage 2025](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition): Strategien im konkreten Fachstoff erklären, modellieren, unterstützen und zunehmend selbstständig anwenden lassen.
- [EEF, Teacher Feedback to Improve Pupil Learning, 2021](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/feedback): gezieltes Feedback für den nächsten Lernschritt. Schlechte Rückmeldung kann schaden; eine KI-Ausgabe ist kein unabhängiger Wirksamkeitsnachweis.

Diese Quellen wurden am 17.10.2026 tatsächlich geprüft. Sie begründen die Richtung des Lernablaufs, nicht die Wirksamkeit von SCHULPILOT oder exakt unsere Notenschwellen und Prüftagsregel. Fachliche Stichproben, Beobachtung mit Kindern und längerfristiger Vergleich realer Lernergebnisse bleiben erforderlich. Die Plattform kennt nur eingegebenen Schulstoff und erfasste Aktivitäten, weder den vollständigen Unterricht noch das Verständnis bei fehlender Nutzung.

## Kontextbezogene externe Lerntipps

Der feste Fachstamm und der versionierte Sofatutor-Navigationskatalog ergänzen
bestätigten Unterrichtsstoff. Gemeinsame Zuordnung für Heft, Einheit, Tutor und
Plan; wenige Vorschläge, korrigierbare persönliche Auswahl. Fachliche Passung
und kuratierter Stufenbeleg sind verschiedene Prüfungen. Sprachlernjahre werden
nicht aus Schulklassen abgeleitet. Details: CATALOG_INTEGRATION.md.

Ein Linkaufruf ist eine eigene gespeicherte Aktion, kein angesehener Film,
Verständnisnachweis, Attempt, Lernabschluss oder gebuchte Mindestlernzeit. Kinder
sehen vor den Links, dass ihre Eltern diese Aufrufe einsehen können. Externe
Seiten werden nicht überwacht. Ansehen/Lesen ersetzt keine spätere eigene
Abrufaufgabe; neue Übungen bleiben an bestätigte Quellen und Lernziele gebunden.

## Korrekturen aus den Kinder-/Elternprotokollen ·19.10.2026

Der verbindliche Bewertungsstand ist der gespeicherte Attempt. Inhalt, verlangte
Form, Versuchszahl und tatsächlich erfasste Hilfe sind eigene Dimensionen.
Rationale Brüche gleichen Werts gelten bei Ergebnisfragen als richtig, solange
keine andere Darstellung verlangt wird. Eng geprüfte vollständige
Sachformulierungen sind erlaubt; unbekannte freie Aussagen bleiben ausdrücklich
offen. Ein Modellkommentar ist eine zusätzliche Einschätzung, keine heimliche
Neubewertung. Kind/Eltern/Rückblick/Fortschritt lesen dieselbe Faktenprojektion.
Explizite regelgebundene Nachprüfung erhält die vorherige Bewertung in
AttemptAssessment0020 und aktualisiert abgeleitete Wiederholungen anhand des
ursprünglichen Lerntags, ohne neue Aktivität oder späteren Prüftag.

Ein Fehlerhinweis beginnt beim tatsächlich noch falschen Teil und erhält richtige
Zuordnungen. Weitere Hinweise unterscheiden sich; danach ein gemeinsamer Schritt
und ausdrücklich angefordertes neues Üben. Hilfen und spätere Versuche bleiben
unterschieden. Bausteine starten eine neue Eingabe, STT bleibt unterstützte Eingabe,
Erkennen/Schreiben/Hören/Abruf bleiben getrennte Belege. Der Client zeigt kurze
Abschnitte gespeicherter Erklärungen; Bruchbalken veranschaulichen bei geöffneter
Hilfe kleine Additionen. Das ist eine Gestaltungshilfe, kein Wirksamkeitsnachweis.
Mathematische Zahlenbrüche erscheinen im Flutter-Client als gestapelter Zähler
und Nenner. Das gilt auch für OCR-Schreibweisen mit Abstand, Unicode-Bruchzeichen
und einfache numerische LaTeX-Brüche; Datum, URL und Dezimalzahl bleiben Text.

Erkannte Aufgaben sind zunächst Vorschläge: Überschrift/Ausdruck zusammen,
Beispiel/unklar/Hausaufgabe ausdrücklich wählen. Nur bewusst bestätigte Hausaufgaben
werden verbindlich. Quellenrevision, Datum und Termin verhindern doppelte
Übernahme; Quellenänderungen lösen eine erneute Klärung aus, ohne alte Antworten
zu löschen (0021). Nicht jeder Probeaufgabentext ist eine Hausaufgabe.

Der Tutor kann ein kleines ausdrücklich kuratiertes Grundwissen als Ergänzung
verwenden, etwa die NOAA-belegten Walmerkmale. Herkunft bleibt sichtbar und wird
nicht in eine Heftquelle umgedeutet. Andere unbekannte Grundlagen dürfen weiterhin
offen bleiben. Ein echter Dialog hat eine Frage, ein direktes Antwortfeld und
einen gespeicherten Gesprächsbezug; jeder Modellschritt braucht eine eigene Aktion.
Fragebezogene externe Tipps ersetzen nicht die Antwort der App.

Eltern erhalten zuerst gespeicherte Erfolge, den vorgesehenen nächsten App-Schritt
und konkrete Hilfewünsche. Technische/OCR-/Bewertungsfragen sind keine Diagnose
einer Wissenslücke. Bloßes Elternlesen ist kein Lernen des Kindes. Freie Tage und
Auszeiten haben kein erfülltes tägliches Mindestziel; freiwillige Aktivität zählt
weiter als echte Übung. Verbindliche Ziele an Lerntagen bleiben bestehen.

Erste erzeugte Etappen gehören zur tatsächlichen Fachkette ihres Schultags.
Bei älteren Plänen ohne Fach im Erstblock wird es aus der vorhandenen Einheit
gelesen; gespeicherte Pläne und Antworten bleiben unverändert. Ein anderes
noch nicht begonnenes Fach darf eine aktive/pausierte Runde nicht verdecken.
Tagesplan, Sammlung und Lernzeitanzeige verwenden denselben Zielstatus, auch
bei freiwilliger Aktivität über dem Richtwert an einem freien oder pausierten Tag.

### Bewusster neuer Antwortversuch

Nach erfolgreich quittierter Rückmeldung beginnt eine erneute bewusste Abgabe
einen neuen Versuch, auch bei unverändertem Antworttext. Die lokale
Sendeidentität endet erst dort. Unbekanntes Transportergebnis oder fehlgeschlagene
Quittierung behalten dieselbe Kennung; Doppeltaps erzeugen keine zweite Antwort.
Der gespeicherte Feedbackpfad und der lokale Legacyablauf folgen derselben Regel.

### Abschluss nach einer gezeigten Lösung

Wenn ein gespeicherter Kurzplan nach einer tatsächlich gezeigten Erklärung
bewusst zu einer anderen Aufgabe führt, bleibt die zuvor falsch beantwortete
Aufgabe für späteres neues Üben zurückgestellt. `instructional_decisions.deferred`
bindet diesen Navigationszustand an die aktuelle Quelle; die falschen Attempts
bleiben unverändert. Ein bloßer Hinweis oder die Rückkehr zur gleichen Aufgabe
stellt nichts zurück. `learning.complete_round` schließt erst nach dem Ende des
Plans und den übrigen beantworteten Aufgaben ab. Letztes Antwortfeedback bleibt
bis zum ausdrücklichen Weiter erhalten.

Für bereits erschöpfte ältere Pläne wird der Wechsel nur aus gespeichertem
Planjob, gezeigter Erklärung und tatsächlichem Folge-Attempt abgeleitet. GETs
zeigen diesen Stand ohne Schreibzugriff; erst bewusstes Fortsetzen, Quittieren
oder Abschließen speichert ihn. Dabei entstehen weder ein zusätzlicher Attempt
noch ein neuer KI-Plan. Der reguläre Abschlussrückblick bleibt einmalig reserviert.

### Gebundene kgV-Heftübungen

`unit_multiples_common.py` ergänzt den bestehenden Einheitenpfad für bewusst
angeforderte Mathematik-Heftübungen. Die versionierte Referenz
`math.multiples.common@1` wird ausschließlich über diesen Beweisbinder angeboten.
Ein Themenwort allein genügt nicht. Die bestätigte Seite muss entweder eine
eindeutige positive kgV-Definition enthalten oder den geordneten Zweischritt
„Vielfachenmengen notieren / kleinste gemeinsame Zahl finden“ mit zwei wörtlichen,
vollständigen Anfangsfolgen. Zahlenfolgen, gemeinsamer Wert und ein eventuell
eingetragenes Ergebnis werden unabhängig rechnerisch geprüft. Quellenrevision,
Regelzitat, Referenzversion und Digests bleiben an die Ausgabe gebunden.

Vor dem Anbieteraufruf stehen zwei bis fünf kleine Aufgabenkerne fest; die KI
ergänzt Hinweise zu denselben Rechnungen. Der Einstieg verwendet ein anderes
gelöstes Beispiel, dessen gezeigte Werte keine ausstehende Antwort verraten.
Lösungsgrafiken bleiben bis zur passenden Offenlegung verborgen. Reihen und
kleinster gemeinsamer Wert stammen aus denselben geprüften Rechendaten; der
vorhandene Szenenspieler hebt sie in zwei steuerbaren Phasen hervor.

Die vollständige frühere Fragenhistorie der betroffenen Quellen und Tage wird
vor der Planung und erneut vor dem Speichern geprüft. Erschöpfte Zahlenbeispiele,
Quellenänderungen und gleichzeitig veröffentlichte gleiche Aufgaben führen zu
einem begrenzten Abbruch; daraus folgt kein automatischer neuer Modellaufruf.
Andere Bruchbinder behalten Vorrang, andere Fächer und Auftragsarten ihren Pfad.

`lcm_numeric_v1` bewertet ausschließlich eine vollständige kurze kgV-Zahlenfrage
mit zwei ausdrücklich genannten positiven ganzen Zahlen. Zuerst muss die
gespeicherte Hauptlösung mit dem unabhängig berechneten kgV übereinstimmen.
Unbekannte Schreibweisen oder widersprüchliche Hauptlösungen bleiben unklar;
Antwortvarianten können keinen falschen gemeinsamen Wert richtig machen.
Abspielen, Markieren und Zurücksetzen bleiben lokale Darstellung ohne Lernbeleg.
