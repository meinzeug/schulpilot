# Künstlicher Nachmittag mit echter KI ·21.10.2026

## Versuchsrahmen

Regulärer, ausdrücklich künstlicher Produktionshaushalt in Klasse6; keine Antworten
oder Änderungen im echten Kinderprofil. Fotoimport, bestätigte Abschrift,
Hausaufgabenhilfe und Anschlussübungen laufen über die normalen Kinderendpunkte
und den vorhandenen Worker. Das Testkonto ist kein öffentlicher Demo-Sonderpfad.
Seine Freigabe ist auf vier Stunden,30Aufrufe und0,25USD begrenzt. Globale
Kontingente, Datenschutzrouten und Providerrevision29 bleiben unverändert.

Verwendetes Bild: `02-mathe-hefter.png` aus dem geprüften künstlichen Bildsatz
`testdata/homework_images_v1.json`; sichtbar „KÜNSTLICHER APP-TEST“. Stoff:
Brüche mit gleichem Nenner, Erweitern mit demselben Faktor; Originalaufgaben
1/3+1/6 und2/5+1/10, anschließend den ersten Schritt beschreiben. Import im
Produktionsbrowser mit Dateiauswahl und tatsächlichem Zuschnitt, keine API-Abkürzung.
Die Erkennung war vollständig und wurde über „Stimmt, weiter“ bestätigt.
Eine Blockade der Browserautomation beim Dateidialog war kein nachgewiesener
Appfehler. Browserkamerazugriff und physische Androidkamera wurden hier nicht geprüft.

## Beobachtete Hausaufgabenfolge

| Ausgang/Ereignis | Gespeicherte Beobachtung | Entscheidung/Aktion | Ergebnis |
| --- | --- | --- | --- |
| Bestätigtes Foto → Übersicht | Drei Originalaufträge, Quellenrevision2 | Ein reservierter Analyseauftrag | Zwei Rechnungen und Beschreibungsauftrag richtig getrennt |
| Eigener Versuch2/9 zu1/3+1/6 → Prüfen | Lokaler Bruchvergleich, falsch; kein Attempt | Keine Modellkosten, kein Endergebnis | Alte Formulierung „beide Brüche … nicht denselben Wert“ war für eine Summe irreführend |
| Erkläre es mir | Ausgewählter Originalauftrag und eigener Versuch | Günstige Tutorroute | Gleiche Teilgrößen und gemeinsamer Nenner verständlich erklärt, Endergebnis nicht verraten |
| Frage nach Erweitern von1/3 mit2 | Echte Kinderfrage im künstlichen Konto | Günstige Tutorroute | Gleiche Zahl an Zähler/Nenner und gleichbleibender Wert fachlich richtig erklärt |
| Eigene Antwort1/2 zu beiden Rechnungen | Zwei lokale richtige Prüfungen | Keine zusätzlichen Modellaufrufe | Als Hausaufgabenhilfe gespeichert; kein selbstständiger Kompetenzbeleg |
| Erkläre den ersten Schritt | Kurzer Bezugssatz ohne eigenen Rechenterm | Bisher nur ausgewählter Satz im Kontext | KI bat unnötig um die bereits vorhandene Rechnung; konkreter Kontextfehler gefunden |
| Zwei Selbsthäkchen → Eltern-Lernstand | Checkliste und abgegebene Hilfen vorhanden | Reine GET-Abfrage | Null bewertete Aufgaben, noch keine KI-Lernstandsauswertung zulässig; korrekt |

Die erste Erklärung und die Antwort zur Bedeutung des Erweiterns wurden zusätzlich
von einem unabhängigen Agenten fachlich geprüft. Beide blieben beim belegten Stoff
und verrieten die Originalergebnisse nicht.

Ein zweiter künstlicher Kinderzugang im Diagnosewerkzeug wurde anfangs abgemeldet.
Die ausdrücklich vorhandene Logoutbereinigung entfernte dabei die privaten
Hausaufgabenentwürfe des Kindes. Der Browser meldete den Versionskonflikt korrekt.
Die Diagnose liest seitdem ausschließlich über den Elternzugang. Beim bewussten
Laden des gespeicherten Entwurfs blieb jedoch eine alte Warnung stehen: eigener
Oberflächenfehler, korrigiert und mit dem vorhandenen Konflikt-Widgetfall geprüft.
Keine Abmelderichtlinie oder früher abgegebene Antwort wurde umgeschrieben.

## Korrekturen und Schnittstellen

- `homework.deterministic_reply`: Bruchfeedback benennt die Summe; erkannte
  Zähler-/Nenneraddition erhält den passenden nächsten Schritt, ohne Ergebnis.
  Die allgemeine Aufgabenbewertung wurde dafür nicht gelockert.
- `homework.related_tasks`/`enrich_context`: kurze Beschreibungs-/Begründungsaufträge
  erhalten höchstens drei originale Nachbaraufgaben derselben aktuellen Analyse,
  je Zitat/Regel maximal600 Zeichen, insgesamt2400. Eigentum, Bestätigung,
  Quellenrevision und wörtliche Belege bleiben Pflicht. Ergebnis-/Lückenschutz in
  `checked_reply` gilt auch für diese Kontextaufgaben.
- `HomeworkDetailScreen.load`: bewusst abgeglichener Entwurf beseitigt den alten
  Speicherfehler; kein automatisches Überschreiben oder Wiederholen.
- `POST /materials/{id}/homework/practice`: bewusste, idempotente Kinderaktion mit
  `source_revision`; vorhandene aktuelle offene Runde/Vorbereitung wiederverwenden,
  sonst genau einen normalen `unit`-Auftrag reservieren. GET und Polling erzeugen
  keine Aufgaben. Quellen-/Sitzungs-/Familien-/Tarif-/Providerprüfung vor/nach KI.
- `practice_exclusions`/`validate_practice_output`: Originale und frühere Fragen
  nicht als neue Prüfung verwenden. Endliche lokale Text-/Rechentermsignaturen,
  keine allgemeine semantische Gleichwertigkeitsgarantie.

- `providers.request_provider` verwendet bei belegter Bruchregel auch im
  Hausaufgabenanschluss den vorhandenen `fraction_tasks`-Planer. Die imperativ
  formulierte Erweiterungsregel ist ein wörtlich belegter Alias; Negation,
  Zukunftsankündigung und feste Faktorbegrenzung werden nicht übergangen.
  Neue Fragen sind im Schema samt Hauptlösung gebunden; ihre Ziel-ID ergänzt
  der Server nach der Prüfung. Keine frei gewählte Modell-Zielzuordnung.
- `parent_insights.goal_evidence`/`facts`: Strategie `parent-review-3` übermittelt
  maximal vier tatsächlich beantwortete, eindeutig zugeordnete Teilziele pro
  ausgewähltem Thema. Fehlende und im begrenzten Kontext ausgelassene Zuordnungen
  bleiben offen. Keine Originalantworten, Fragen, Fotos oder Rückblickprosa.
  Alte Berichte bleiben lesbar; keine KI-Neugenerierung durch einen GET.
- `learning_progress._latest_attempts`: bei exakt gleichen Float-Zeitstempeln
  entscheidet zusätzlich die bereits gespeicherte Versuchsnummer. Reproduzierter
  Randfall mit gezielt gleichen Zeitstempeln, kein nachgewiesener gewöhnlicher
  Schnellantwortfehler. Ursprüngliche Daten und der Legacy-Fallback bleiben erhalten.

## Livefortsetzung und weiterer Befund

Version1.18.0+74 wurde regulär gebaut, geprüft und ausgerollt. Der bereits
vorhandene Beschreibungsauftrag wurde erneut bewusst angefragt: Jetzt nannte die
KI die beiden vorhandenen Aufgaben zur Auswahl, statt ein neues Foto zu verlangen.
Der abgegebene eigene erste Schritt wurde fachlich richtig kommentiert, ohne das
Originalergebnis zu verraten. Alle drei Hausaufgaben waren anschließend selbst
abgehakt; die neue Schaltfläche führte über genau einen gespeicherten Auftrag in
eine normale Lernrunde. Reload auf deren Vorbereitungsseite erzeugte keinen
zweiten Auftrag. Der Elternstand blieb bis zur ersten Übungsantwort bei null.

Die erste Runde prüfte4/7 mit Faktor4 und1/8 mit Faktor2. Beide Hauptlösungen
16/28 und2/16 stimmen und entsprechen genau der verlangten Darstellung. Die
Fragen waren an g2 „Brüche erweitern“ gebunden, nicht an sichere Addition.
Der erste Versuch nutzte einen Aufgabenhinweis. Die zweite Antwort blieb nach
Pause und Reload als ungesendeter Entwurf2/16 erhalten; die pausierte Zeit lief
nicht weiter. Auch das gespeicherte Antwortfeedback wurde nach Reload vollständig
angezeigt und erst mit „Weiter“ quittiert. Das letzte Feedback führte trotz
unerfülltem Zeitminimum zuerst zum Ergebnis.

Beide Antworten zählen hier als unterstützt: „Erst die Erklärung ansehen“ ruft
bewusst eine Rundenerklärung auf. Die bestehende konservative Regel zählt sie für
alle späteren Fragen derselben Einheit. Q1 hatte Hinweis+Erklärung, Q2 nur die
Erklärung; Q2 brauchte keinen eigenen Aufgabenhinweis. Es wurde kein Hilfemarker
entfernt, um bessere Statistiken zu erhalten. Eine neue Runde übernimmt diese
Unterstützung nicht. Der echte KI-Rückblick empfahl gezieltes Nachlernen und
behielt ausschließlich das tatsächlich geprüfte Ziel Erweitern. Die Elternfakten
zeigten zwei unterstützte Aufgaben, null selbstständige, keine Fehl-/offenen
Bewertungen und null unbekannte Zielzuordnungen; für einen Eltern-KI-Bericht
fehlte korrekt noch die dritte beantwortete Aufgabe.

Ein weiterer echter KI-Befund: Die Einführung dieser ersten Runde zeigte zusätzlich
den vollständigen Additionsweg1/4+1/8=3/8. Er ist rechnerisch richtig und verrät
keine Original-/Prüfantwort, überschreitet aber den belegten Voraussetzungenfokus.
Unabhängige fachliche Gegenprüfung bestätigte den Änderungsbedarf. Version75
plant deshalb ein anderes Erweiterungsbeispiel vorab; der Prompt bleibt bei
Erweitern, ein endlicher lokaler Fokusprüfer verwirft den beobachteten Additionsweg
und erkennbare Kürzbeispiele. Die vorhandene erste Runde samt Antworten und Kosten
bleibt unverändert; die Korrektur wird an einer neuen Folgegeneration geprüft.

Die echte Folgegeneration nach Version75 blieb im Fokus:3/4 mit Faktor3 ergibt
9/12 als anderes Beispiel; neue Fragen5/9 mit Faktor4 und7/8 mit Faktor2,
beide weiter g2. Das Beispiel ist fachlich richtig und nimmt keine Prüflösung
vorweg. Die neue Runde wurde bewusst ohne Erklärung oder Hinweis gestartet.
20/36 zur ersten Frage wurde als selbstständiger Erstversuch gespeichert
(`subject_rules_v5`, keine Unterstützung). Die zweite Antwort14/8 war ein bewusst
synthetischer Fehler; die App verlangte das Multiplizieren beider Zahlen und
verriet zunächst keine fertige Lösung.

Dabei wurde ein echter weiterer Bedienfehler gefunden: Die identische falsche
Antwort nach „Noch einmal versuchen“ verwendete denselben Idempotenzschlüssel wie
der bereits quittierte erste Versuch. Der Server deduplizierte korrekt; im
Browser fehlten neuer Versuch und neue Rückmeldung. Der geschützte Serverstand
bestätigte nur einen gespeicherten Versuch trotz der zweiten bewussten Abgabe.
Version76 beendet deshalb die lokale Sendeidentität erst nach erfolgreich
bestätigtem Feedback beziehungsweise bewusstem Legacy-Weiter. Ein unklarer
Antworttransport oder fehlgeschlagenes Quittieren behält die ursprüngliche
Kennung. Neue deduplizierende Widgettests prüfen beide Wege sowie Doppeltaps.
Der Live-Replay wird mit den vorhandenen Antworten fortgesetzt; keine Antwort
wurde gelöscht oder umgewertet.

Ein bei sehr schneller Browserautomation fehlendes erstes Zeichen in einem
Bruchfeld wurde vor dem Absenden sichtbar korrigiert. Die unabhängige Codeprüfung
fand keinen belegten Entwurfs-/Wiederherstellungsfehler; daraus wird kein behobener
Produktbug behauptet.

## Unveränderter Fehlversuch und begrenzter KI-Kurzplan

Der tatsächliche Browserreplay mit Version76 erfolgte ohne Reload und ohne
Änderung des Antworttexts:4/10 mit Faktor2 wurde zweimal bewusst als8/10
abgegeben, jeweils mit bestätigtem Feedback dazwischen. Zwei unterschiedliche
Attempt-IDs und eine neue zweite Rückmeldung belegen die reparierte
Sendeidentität. Die mathematische Prüfung blieb beide Male falsch;8/10 ist
nicht die geforderte Erweiterung8/20. Kein künstliches „richtig“ wurde erzwungen.

Nach diesen zwei gleichartigen Fehlern wurde genau ein weiterer bewusster
Entscheidungsauftrag normal reserviert. Der gespeicherte KI-Kurzplan wählte eine
Erklärung zum Multiplizieren beider Bruchzahlen.8/20 wurde jetzt ausdrücklich
als vorgerechnete Lösung gezeigt. Anschließend wechselte der Plan zu einer
anderen Aufgabe:7/8 mit Faktor4. Die eigene Antwort28/32 wurde im ersten
Versuch ohne aufgabenspezifischen Hinweis als selbstständig richtig gespeichert.
Die gezeigte Lösung zu4/10 ist kein Erfolg für die zurückgestellte Aufgabe und
zählt nicht als Unterstützung der anderen Frage.

Hier deckte der vollständige Nachmittag einen weiteren Controllerfehler auf:
Nach dem letzten Feedback kehrte die Oberfläche zur zuvor erklärten Fehlerfrage
zurück. Der KI-Kurzplan hatte den Wechsel gespeichert, jedoch keine dauerhafte
Zurückstellung für die gemeinsame Rundenabschlussprüfung. Die Runde wurde
bewusst pausiert; es wurde keine erneute kostenpflichtige Planung ausgelöst.
Version77 speichert die Zurückstellung getrennt von Antworten im vorhandenen
`LearningMemory.working`, gebunden an die aktuelle Quellensignatur. Ein kleiner
Hinweis oder die Rückkehr zur gleichen Frage genügt nicht. Für den schon
vorhandenen Altplan verlangt die lokale Ableitung einen abgeschlossenen eigenen
Planjob, den tatsächlichen Erklärungsbeleg und einen gespeicherten Antwortversuch
auf der direkt folgenden anderen Frage. Geänderte Quellen oder fremde
Antwortreferenzen verhindern diese Ableitung.

`instructional_decisions.deferred` ist eine reine Projektion;
`persist_deferred` schreibt ausschließlich innerhalb vorhandener Mutationen.
`learning.completion_ready`/`complete_round` vereinheitlichen die Abschlussprüfung
für neue Antworten und wiederaufgenommene Pläne. `recover_instructional_round`
läuft nur bei bewusstem Start, Feedbackquittieren oder Controlleraktion und
verlangt, dass keine ungelesene Rückmeldung offen ist. Einheit vor Kind sperren,
Quellen erneut prüfen, Originalversuche erhalten. Der normale Abschluss darf
anschließend genau den regulären idempotenten KI-Rückblick reservieren; das ist
kein weiterer Reparaturplan und wird in den realen Kosten mitgezählt.

Im Client prüft `prepareInstructionalPlan` die frisch gelesene Freigabe vor dem
POST. Ein echtes `false` lädt nur den gespeicherten Stand. Ein fehlendes Feld
alter Backends behält den bisherigen ausdrücklichen Ablauf. Bereits gespeicherte
Hilfe bleibt erreichbar; ein verbrauchter Plan wird nicht erneut angefordert.
Der reale Wiederaufnahmetest und die Elternprüfung folgen unten.

## Tatsächlicher Abschluss und Elternprüfung

Version1.18.3+77 wurde nach Commit/Push regulär bereitgestellt. Der erste reine
GET zeigte weiterhin `paused`, keinen Feedbackrest, `finish_round` und q1 als
zurückgestellt. Erst der Browserklick „Lernen fortsetzen“ schloss die vorhandene
Runde. Ein Vorher-/Nachhervergleich aller drei Attempt-IDs, Antworten, Ergebnisse
und Unterstützungsmerkmale war identisch. Kein neuer Versuch und kein weiterer
Entscheidungsplan: Nur der normale, einmalige Abschlussrückblick kam hinzu.
Dieser ordnete beide Aufgaben korrekt g2 zu und empfahl bei wiederholtem offenem
Schritt zusätzlich einen gemeinsamen Blick, ohne falsche Lernerfolge zu buchen.

Die Testeltern wurden regulär im Produktionsbrowser angemeldet. Übersicht,
Hausaufgabenliste, authentifiziertes Originalfoto, abgegebener erster Schritt und
zugehörige Hilfen waren sichtbar. Die Elternansicht enthält keine ungesendete
Texteingabe. Drei Selbsthaken sind ausdrücklich Angaben des Kindes, keine
geprüften richtigen Lösungen. Ein eigener bewusster Eltern-KI-Auftrag wertete
anschließend die gespeicherten Übungsnachweise aus.

| Gespeicherter Abschlussstand | Wert |
| --- | ---: |
| Selbst abgehakte Original-Hausaufträge | 3 |
| Neue tatsächlich beantwortete Prüfaufgaben | 6 |
| Gespeicherte Antwortversuche | 9 |
| Im ersten Versuch selbstständig richtig | 2 |
| Mit Unterstützung oder erneut richtig | 2 |
| Weiter üben | 2 |
| Unklare Bewertung | 0 |
| Abgeschlossene Lernrunden / laufende Runden | 3 / 0 |
| Fachlich zugeordnete Aufgaben / unbekannte Zuordnung | 6 / 0 |
| Tatsächlich gespeicherte Aktivitätszeit | 12:56 Minuten |

Alle sechs Aufgaben gehören zum belegten Teilziel „Brüche erweitern“. Der echte
Elternbericht grenzt ausdrücklich vom Addieren ab und behauptet weder dauerhafte
Beherrschung noch eine pädagogische Diagnose. Beobachtung und Einschätzung stehen
getrennt; der vorgeschlagene Plan lautet: Erweitern verstehen → neue Aufgabe
selbst anwenden → später erneut abrufen. Keine Erhöhung der Mindestminuten, kein
automatischer Folgeauftrag. Ein unabhängiger Agent bestätigte abschließend die
mathematischen Ergebnisse, die sechs Originalbewertungen und den Elternbericht.

Auch bei390px Browserbreite waren Navigation, Bericht und Ergebniskarten lesbar;
die ursprüngliche Browsergröße wurde wiederhergestellt. Screenshots liegen unter
`artifacts/afternoon-live/`, insbesondere `parent-final-results77.png`,
`parent-plan77.png`, `parent-homework77.png` und `round-recovery77.png`.

## Wirklicher KI-Verbrauch

OpenRouter-Providerrevision29 und der freigegebene Paid-Modellmix blieben erhalten.
Keine Kontingent-/Datenschutzlockerung, kein Anbieterfallback, keine Tests mit
echten Kinderinhalten. Alle16 erfassten Aufrufe sind fertig abgerechnet,
**0,088137USD**, null unbekannte Kosten. Einschließlich der vor dem Fix
unbefriedigenden Antworten und aller drei Rückblicke; nichts herausgerechnet.
Die lokalen Bruchprüfungen und alle Listen-/Status-/Reloadaufrufe verursachten
keine zusätzlichen Modellaufträge. Nach den Eltern-/Mobilansichten blieb es bei16.

| Funktion / Modell | Aufrufe | USD |
| --- | ---: | ---: |
| Fotoabschrift /gpt-6-luna | 1 | 0,000896 |
| Hausaufgabenbegleitung /gpt-6-luna | 6 | 0,002033 |
| Erste neue Runde /gpt-6-luna | 1 | 0,001389 |
| Rückblick /gpt-6-luna | 1 | 0,000986 |
| Anschlussrunde /gpt-6-luna | 1 | 0,001413 |
| Anschlussrunde /gpt-6.1-sol | 1 | 0,024384 |
| Gezielter Entscheidungsplan /gpt-6.1-sol | 2 | 0,024848 |
| Rückblick /gpt-6.1-sol | 2 | 0,031674 |
| Elternbericht /gpt-6-luna | 1 | 0,000514 |
| **Gesamt** | **16** | **0,088137** |

Vollständige Modell-IDs: `openai/gpt-6-luna`, `openai/gpt-6.1-sol`.
Die stärkere Route wurde bei wiederholten Schwierigkeiten im vorhandenen
Routing verwendet. Das ist eine einzelne beobachtete Sitzung samt Fehlersuche,
keine allgemeine Kostenprognose pro Kind oder garantiertes Lernergebnis.

## Prüfungen und Bereitstellung

- Vorangehende Hausaufgaben-/Mathematik-/Rückblickintegration:145 bestandene
  Backendfälle. Eltern-Zielaggregate zusätzlich34 PostgreSQL- und15 SQLitefälle.
  Frühere beziehungsweise überlappende Läufe nicht zu einem Gesamtergebnis addieren.
- Abschluss77:79 gemeinsame PostgreSQLfälle zu Lernen, Feedback, Controller,
  Medienrückkehr, adaptivem Plan, Wortschatz und Mindestzeit bestanden. Im
  Entscheidungsplan-Testmodul21 verschiedene PostgreSQLfälle über19 vollständige
  und3 ergänzende Prüfungen (ein überlappender Fall) bestanden. Dasselbe aktuelle
  Modul anschließend vollständig unter SQLite:21 bestanden.
- Abschließende35 Flutterfälle zu Planfreigabe, adaptivem Raum, identischen
  Wiederholungsantworten und gespeichertem Feedback bestanden. Frühere54
  Hausaufgaben-/Eltern-/Fortsetzungsfälle separat bestanden. Flutteranalyse,
  Ruff und Diffprüfung ohne Befund. Kein behaupteter neuer Gesamt-App-Testlauf.
- Web, signierte Direct-APK und Play-AAB77 gebaut. Bundletool, Paket, Version,
  Signierer und Play ohne APK-Installerberechtigung geprüft. Bekannte Secrets:
  649 Quellen/Assets,344 Archiveinträge,16 Secretquellen, null Treffer. Zusätzlich
  Provider-Key/Base64-Abgleich ohne Treffer. Kein Play-Upload.
- Produktion: `20261021T150342Z-14fe339`, Produktcommit
  `14fe339f579b84c85d54ee31cbb4f33d49d98569`, main gepusht.
  API/Worker/Caddy aktiv, reguläre Sicherung erfolgreich, Schema0025 und
  Providerrevision29 unverändert. Öffentliche Health-/Versionsantwort und der
  vollständige öffentliche APK-Download stimmen mit dem gebauten Artefakt überein.
- APK75236762Bytes, SHA256
  `55d7cff65a4b86c6ecce83eab71e22b7ff7f990a8bf26f4234ea91ac94999238`.
  AAB70583093Bytes, SHA256
  `d0e5cdf0a8ee2e4b1cb55e41934a51434fb9bf37b934da9debc0703a32436d93`.
  Rückweg:76 (`20261021T142904Z-d8e78c4`), dasselbe Schema0025;
  keine Datenbankrücksetzung für diesen Coderückweg.

## Grenzen und Testdaten

Das15-Minuten-Mindestziel blieb korrekt offen:12:56 gespeichert, noch2:04.
Die Browser-/Build-/Wartezeit wurde nicht als Lernzeit gebucht. Keine künstliche
Uhrverstellung, kein behaupteter späterer Abruf über mehrere Tage. Der Test
belegt einen ganzen Funktionsweg vom Foto bis zur Elternauswertung; er belegt
keine langfristige Lernwirkung, vollständige WCAG-Konformität oder physische
Androidkamera. Die App darf nach wiederholtem Unterstützungsbedarf Elternhilfe
empfehlen; dieser künstliche Durchlauf beweist keine vollständige menschliche
Aufsicht oder alleinige Betreuung jeder denkbaren Schwierigkeit.

Nach der ausdrücklichen Betreiberantwort „Ja, den künstlichen Testhaushalt
löschen“ wurde die Bereinigung über den regulären authentifizierten Endpunkt
`DELETE /account` durchgeführt. Zuvor wurden die gepinnte künstliche Kind-ID,
Familien-/Benutzerzuordnung und der genaue Umfang geprüft: ein Elterninhaber mit
exakt einer Familie und einem Kind. Die frühere automatische Ablehnung wegen
fehlender ausdrücklicher Löschfreigabe wurde nicht umgangen.

Nachweis nach der Löschung: Familie, Kind, beide Testbenutzer, Aufgabenfoto,
alle drei Lernrunden, Elternberichte und private Usage-Zeilen jeweils nicht mehr
vorhanden. Die globalen Aufruf-/Kostenstände blieben erhalten; private Usage
entfällt gemäß der bestehenden FK-Löschregel und wird nicht als weiter bestehend
ausgegeben. Der veröffentlichte Löschauftrag sowie zwei signierte Journalbelege
für Familie und Kind wurden geprüft; ihre HMAC-Signaturen sind gültig. Die lokale
Datei mit den Testzugangsdaten wurde ebenfalls entfernt. Ergebnis:
`artifacts/afternoon-live/cleanup.json`. Die abschließende Bereinigung benötigt
keine Änderung oder erneute Bereitstellung des produktiven Anwendungscodes.
