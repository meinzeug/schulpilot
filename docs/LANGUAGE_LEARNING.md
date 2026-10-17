# Sprachlernen – fortsetzbarer Arbeitsstand

Stand: 17.10.2026. Ausgangspunkt main 7dd09f4, Flutter 1.3.0+28, Alembic 0014.

## Umsetzung

1. Aufgaben/Bewertung: implementiert; genaue Varianten-/Mathematikregression lokal geprüft.
2. Wortschatz: implementiert; manuell/Text/bestätigte Seite, Prüfung, Revisionen, Sammlungen, Suche und Seitenteilung.
3. Abruf/Tagesplan: implementiert; getrennte Richtungen/Fähigkeiten, echte Attempts, transaktionale Wiederholung und Resume.
4. Sprache: Locale/Tempo/Gerätedienstprüfung und Kontext-/Satz-/Grammatikpfad implementiert; echte Audioabnahme offen.
5. Kontextwerkzeuge: 18 begrenzte Projektarten mit gespeicherter eigener Vorarbeit und 2–5 interaktiven Aufgaben implementiert.
6. Aktiviert und geprüft: 1.4.0+30 / 58f2c8c, Migration 0015. 784 PostgreSQLtests
   vollständig, danach 94 und drei Abschlussprüfungen, 70 Provider-/Sprach- und
   21 Mathematik-/Coachtests. 285 Fluttertests vollständig, zehn finale Widgets,
   Analyse/Ruff und Web/Direct-APK/Play-AAB bestanden. Öffentlicher Foto-/Wortweg,
   reale Codex-Projekte (Kontext, Grammatik, Textfeedback), Eltern-/Kinderansicht
   und Zeitminimum geprüft. Native Android-API-36-Runde nach echtem OTA auf 30:
   zwei weitere Aufgaben, Feedback und Kaltstart/Resume bestanden. Export aller
   acht Tabellen, fünf Attempts/Reviewereignisse und reale Haushaltslöschung
   einschließlich Sitzungswiderruf geprüft. Künstliche Kontodatei entfernt.

Alle Arbeitspakete haben einen nutzbaren implementierten Kern. Audioabnahme auf
physischem Telefon/Mikrofon bleibt offen; Steuerungen/Locales sind mit den
fixierten SDKs und Mocktests geprüft. Alle 18 Projektarten sind strukturell mit
künstlichem Providertransport geprüft; echte Modellprüfungen in dieser Sitzung
für Kontext, Grammatik und Textfeedback. Optionale Druck-/PPTX-Ausgabe bleibt
offen. Nächste konkrete Aktion: physische TTS-/STT-Fehler-/Berechtigungsprüfung
mit neuem eigenen künstlichen Haushalt. Kein Nachweis einer Lernwirksamkeit,
Notenverbesserung oder Audioqualität aus diesen technischen Tests.

## Verbindliche Modellentscheidungen

Eine Runde enthält höchstens fünf Aufgaben (bei einem letzten Wort auch eine).
LearningUnit/Attempt bleiben die
maßgeblichen Lernbelege; Wiederholungsereignisse referenzieren genau einen
Attempt und sind keine zusätzliche Leistung. Bedeutung, Schreibabruf und Hören
werden je Richtung und Eintragsrevision getrennt gespeichert. Intervalle
1/3/7/14/30 Tage sind eine transparente Produkthypothese, kein wissenschaftlich
optimierter Algorithmus. Maximal ein Aufstieg je lokalem Tag (Europe/Berlin bzw.
gespeicherte Familien-/Kinderzeitzone). Fehler, Hilfe und unklare Bewertungen
ergeben keinen selbstständigen Aufstieg. Ausfalltage vervielfachen keine Pflicht.

Sprache wird ausdrücklich ausgewählt. Geräte-TTS benötigt den Hörtext im
Client; dies ist kein abgeschirmter Hörtest. STT liefert ein korrigierbares
Transkript, keine Aussprachebewertung und keinen selbstständigen Schreibbeleg.
Eine fehlende Stimme wird nicht durch eine anderssprachige Stimme ersetzt.

## Daten, Bewertung und Revisionen

Migration **0015 folgt 0014**, ergänzt acht private Tabellen:
`vocabulary_collections`, `vocabulary_items`, `vocabulary_memberships`,
`vocabulary_reviews`, `vocabulary_review_events`, `vocabulary_imports`,
`vocabulary_actions`, `language_projects`. Attempts erhalten nullable
Anfrageschlüssel/-digest und Bewertungsdimensionen sowie `input_method` mit
kompatiblem Default `typed`. Ein Unique-Index vermeidet einen SQLite-Neuaufbau.

`language.version=1` enthält UI-/Anleitungs-/Ziel-/Antwort-/Beispielsprache,
Aufgabenziel, Fähigkeit, Richtung, Eintrags-/Quellenrevisionen und eine private
Bewertungspolitik. `choice/gap/short` bleiben Renderer; Satzbau nutzt tippbare
Bausteine im kurzen Eingabefeld. Alte Mathematik-/Sachaufgaben ohne Metadaten
behalten ihre Bewertungsregeln. Auch bestehende Englisch-Sachpakete werden
nicht nachträglich als Sprachtests umgedeutet. Neue Sprachaufgaben entstehen
nur durch bewusste Wortschatz-/Sprachwerkstattaktionen.

Locale-Auswahl: en-GB/en-US/fr-FR/es-ES für eigenen bestätigten Wortschatz;
keine mitgelieferten Kurse. Englisch-Grammatik benötigt die ausdrückliche
Themenauswahl und einen passenden Beleg im bestätigten Heft. `Simple Present`,
`Simple Past` und `Progressive` werden niemals aus Klassenstufe allein aktiviert.
Neue Kontextbeispiele sind als erzeugte Übungen markiert; belegte Formen und
Antwortvarianten werden nicht still erweitert.

Sprachbewertung normalisiert NFC und Zwischenraum, keine Akzententfernung,
Levenshtein-Grenze, globale Artikelentfernung oder Komma-/Dezimalersetzung.
Großschreibung ist beim Zielwort relevant; deutsche Bedeutungsabfrage prüft
den Inhalt ohne Großschreibungsprüfung. Typografische Apostrophe können
ausdrücklich gleichgestellt werden. Satz-/Grammatikziele dürfen terminale
Satzzeichen ignorieren; andere Unterschiede benötigen bestätigte Varianten.
Zielwort- und Bedeutungsvarianten sind getrennt gespeichert. `were/where`,
`your/you're`, `He go/He goes` bleiben verschieden. Unbekannte freie Sätze sind
`uncertain`; spätere beratende KI-Kriterien ändern diese Attempts nicht.

Identität umfasst Kind, Locale, Wort, konkrete Bedeutung, Kontext und Wortart.
Mehrere Sammlungen können denselben Eintrag benutzen. Korrektur/erneute
Quellenbestätigung erzeugt eine neue Revision mit bisherigem Snapshot;
begonnene Aufgaben und Antworten bleiben unverändert. Noch nicht begonnene
Runden mit veralteten Wörtern werden gesperrt. Geänderte/gelöschte Heftquellen
verhindern neue Übernahmen. Manuell ergänzte, nicht im bestätigten Text
vorhandene Bedeutungen werden als eigene Bestätigung gekennzeichnet.

## Verarbeitung und Fortschrittsbelege

`vocabulary_import` ist ein eigener reservierter Auftrag **nach** der wörtlichen
Fotoerkennung. Er übernimmt nur Textbelege; fehlende Bedeutungen bleiben offen.
Wort und Bedeutung müssen im bestätigten Text vorkommen; uneindeutige
zeilenübergreifende Zuordnung erzwingt eine Klärung. Kein Wörterbuch-/Webinhalt
wird als Fotoabschrift ausgegeben. Codex-Websuche ist für diesen reinen Import
auf Auftragsebene aus. Der aktive Provider und seine übrigen Freigaben bleiben.

Reine Wortabrufrunden werden deterministisch aus bestätigten Paaren gebaut,
ohne Modellaufruf und ohne vorgetäuschte KI. `language_project` reserviert für
jede bewusste Erzeugung genau einen bestehenden DB-Auftrag. Sitzung, Familie,
Quellen, Wörter, Elternplanung und Providerrevision werden vor und nach der
externen Verarbeitung geprüft. Fehler bleiben sichtbar; GETs erzeugen weder
Aufträge noch Fortschritt. Idempotenzkonflikte sind 409; neue Sprachantworten
benötigen einen Anfrageschlüssel. Unit wird vor Child gesperrt; Child
serialisiert Review-Erzeugung und -Änderung. Das eindeutige Reviewereignis
referenziert einen Attempt. Wiederholungen zählen im allgemeinen Lernverlauf
als tatsächliche Übung, nicht als zusätzliche Langzeitbestätigung.

Review-Schlüssel: Eintrag + Revision + Richtung + Fähigkeit; Grammatik zusätzlich
Thema. Stufe 0 hat noch keinen unabhängigen Aufstieg. Richtige Erstantwort ohne
Hilfe erhöht höchstens einmal je lokalem Lerntag auf 1/3/7/14/30 Tage. Falsche,
unterstützte oder unklare Antworten setzen zeitnahe Wiedervorlage ohne
Erfolgsaufstieg; unklar bleibt zur Klärung markiert. Eigenes Aufdecken,
Wortbausteine, Quellen-/Wortkorrektur und sichtbare Antwortlösung werden als
Vorlage erfasst. Für zehn Minuten verhindert eine bekannte Lösungseinblendung
einen neuen unabhängigen Abruf desselben Eintrags. Dies ist eine vorsichtige
Produktregel, kein abgeschirmter Test oder lückenloser Blick-/Gerätenachweis.
Nach gerade bestätigten Wörtern übt das Kind zunächst mit Vorlage; spätere
eigene Abrufe sind getrennt sichtbar. STT zählt konservativ als Unterstützung.
Ein Hörstimulus ist dagegen Aufgabenbestandteil und erzeugt allein keine Hilfe.
Beim Satzbau sind die vorgegebenen ungeordneten Wörter Teil des ausdrücklich
geprüften Satzordnungsziels, kein Nachweis freien Schreibabrufs. Zusätzlich
angeforderte Buchstabenbausteine beim Schreibziel werden als Hilfe gespeichert.

Fällige und noch nicht geprüfte Fähigkeiten gelangen je ausgewählter Sprache
als **eine kleine Portion** in die bestehende Planung. Schulische Schwerpunkte,
Prüfungstermine, Elternpflichtaufträge, Lerntage/Pausen und tatsächlich gemessene
Zeitminima bleiben erhalten. Keine Aufgabe wird durch Listenabruf angelegt;
kein automatisch wachsender Nachholberg. Zusätzliche Runden erfordern eine
bewusste Aktion. Unvollendete Runden werden gespeichert und wieder angeboten.

Kind und Eltern sehen den gleichen Wort-/Fähigkeitsstand. Der allgemeine
Fächer-/Themenfortschritt zählt weiter ausschließlich echte Attempts. Projekte,
Vorschläge, eigene Entwürfe, vorbereitete Aufgaben und abgegebene Antworten
sind getrennt. Keine Prozent-Mastery oder Notenversprechen.

## Audio und Clientkompatibilität

`X-Schulpilot-Capabilities: language-v1` erlaubt neue Sprachrunden; Kinderclients
ohne Capability erhalten bei Detail/Start/Antwort 426 mit Updatehinweis. Die
öffentliche Kinderprojektion entfernt Lösungsschlüssel, Varianten,
Bewertungspolitik, Hinweise und Erklärung bis zur jeweils erlaubten Rückmeldung.
Satzbausteine sind ungeordnetes Aufgabenmaterial. Geräte-TTS benötigt den
Hörstimulus im Payload; er wird nicht als unsichtbarer Prüfungsschlüssel
bezeichnet oder als verborgener Text im Widgetbaum gerendert. Ein Client-Signal
nach erfolgreichem Abspielen ist Voraussetzung für eine Hörantwort, kein
akustischer Zustell-/Wahrnehmungsbeweis.

TTS prüft die konkrete Sprachvariante, bevorzugt bekannte lokale Stimmen ohne
Offlinegarantie und bricht bei fehlender passender Stimme ab. Anleitung und
Beispiel sind getrennte Segmente. Aufnahme nach Datenschutzhinweis und eigener
Aktion, Transkript korrigierbar, kein automatisches Absenden. Aufnahme und
Wiedergabe teilen eine Sitzung und stoppen bei Sprach-/Routen-/Kontowechsel,
Hintergrund, Logout und Dispose. Tippen/Lesen bleiben ohne Audiogerät verfügbar;
ein sichtbarer Text wird nicht als erfolgreiche Hörübung verbucht.

## Rechte, Aufbewahrung und Rückweg

Eigene Kinder bzw. berechtigte Eltern (view/manage), kein privater Adminzugriff.
Neuer Wortschatz und Projekte sind im Familienexport enthalten; Kinder-/Familien-
FKs löschen sie einschließlich Reviewereignissen. Quellenlöschung entfernt
zugehörige Wort-/Import-/Projektsnapshots. Bereits erzeugte private Runden und
unveränderte Antworten bleiben wie bisher bis zur Lernverlaufs-/Kontolöschung
oder Aufbewahrungsgrenze erhalten; eine gelöschte Quelle sperrt weitere Antworten.
Wort-/Projekt-/Import-
Aufbewahrung 365 Tage, Jobmetadaten 30 Tage, bestehender Backup-/Löschjournalweg
unverändert. Geheimnisse liegen weiterhin außerhalb von Git und Client.

0015 ist additiv, dennoch kennt Code vor dieser Erweiterung neue Aufträge und
Sprachbewertung nicht. **Kein blinder kompatibler Rückweg auf 0014-Code nach
Sprachbenutzung.** Erst Schreibzugriffe anhalten, neue Jobs vollständig beenden
oder sicher abbrechen und einen weiter kompatiblen Korrekturrelease einsetzen.
Ein Datenbank-Downgrade löscht neue Belege und ist kein regulärer Rückweg.
Vor Freigabe ohne neue Sprachdaten ist der bestehende gesicherte Rückweg
möglich; andernfalls getrennte Wiederherstellungsprüfung mit Löschjournal.

## Werkzeugzuordnung

| Nr. | Kontext | Stand |
|---|---|---|
|01|Tages-/Wochenplan mit Wortfälligkeiten|bestehender Plan erweitert|
|02|Probe mit zunächst verdeckten Lösungen|`exam`: 2–5 Aufgaben, Einzelrückmeldung nach Antwort, Gesamthilfe erst nach Abschluss; kein beaufsichtigter Prüfungstest|
|03|Eigener Text, kriteriengebundenes Feedback|`writing_feedback`, eigener Entwurf, beratende Kriterien|
|04|Modellbeispiel nach eigener Vorarbeit|`model_text`; kein eigener Leistungsbeleg|
|05|Gliederung, Satzanfänge, gestufte Schreibhilfe|`writing_help`, danach interaktive Aufgaben|
|06|Einfachere Erklärung bei erhaltenem Inhalt|Tutor und `simplify`|
|07|Erklären im Verstehen/Tutor|vorhanden|
|08|Präsentationsgliederung, Folieninhalte, Vortragsfragen|`presentation`: Textvorbereitung und Übungen, kein PPTX-Export|
|09|Referat und anschließender Inhaltsabruf|`speech`: Vortragsvorbereitung und Aufgaben|
|10|Quellengebundener Lernzettel|`study_notes`|
|11|Wortkarten mit echtem Abruf|eigener Wortschatz, separate Reviewfähigkeiten|
|12|Wörter/Fachbegriffe mit Bedeutung und Kontext|bestätigte private Einträge/Sammlungen|
|13|Strukturierte Übungen, optionaler Druck|`worksheet` interaktiv; optionaler Druckexport offen|
|14|Sprachaufgaben aus bestätigtem Text|`context_gap`, `sentence_order`, bestätigtes `grammar`|
|15|Quellgebundene Themenübungen|bestehende Lernreise und `topic_practice`|
|16|Begrenzte Argumentation/Perspektivwechsel|`debate`; `dialog` maximal 4 bewusste Schritte ohne Verzweigung|
|17|Eigener Übersetzungsversuch und Vergleich|`translation`, eigener Entwurf und Kriterien|
|18|Zusammenfassung und Verständnisfrage|`summary`, danach 2–5 echte Aufgaben|
|19|Stichpunkte aus Text, gemeinsame Lernzettelfunktion|mit 10 als `study_notes` zusammengeführt|
|20|Adressatengerechtes E-Mail-Schreiben ohne Versand|`email`, eigener Entwurf und Kriterien, kein Versandpfad|

## Fachliche Grundlage und Grenzen

Abruf mit anschließender Rückmeldung und zeitlich verteilte Wiederholung sind
didaktische Muster. Ihre konkrete Umsetzung muss beobachtet und verbessert
werden; keine Notenversprechen. Quellen:
[EEF Cognitive Science Approaches](https://educationendowmentfoundation.org.uk/education-evidence/evidence-reviews/cognitive-science-approaches-in-the-classroom/),
[EEF Feedback](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/feedback).
Babbel- und sofatutor-Beobachtungen sind Anregungen zu Interaktionen, keine
Behauptung über deren interne Algorithmen oder kopierte Kursinhalte.
