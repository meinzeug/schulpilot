# Sprachlernen – fortsetzbarer Arbeitsstand

## Belegbindung der Sprachwerkstatt · Korrektur 18.10.2026

Ein gezielt freigegebener Prüfauftrag scheiterte nach abgeschlossener
KI-Antwort: Der frei erzeugte `source_excerpt` war kein wörtlich passender
Beleg. Es wurde keine Einheit angelegt. Nicht mit einer Anbieterunterbrechung,
einer falschen Kinderantwort oder fehlendem Wortschatz gleichsetzen.

`providers.bind_language_project_sources` bindet vor dem einzigen Aufruf
Projekt-/Aufgabenbelege an die ausdrücklich bestätigten Paare `word = meaning`.
Diese kanonische Darstellung belegt den bestätigten Wortschatz, nicht das
Tabellenlayout eines Fotos. Auswahl der Wort-ID, Ziel-/Beispielsprache und
ausdrücklich gewählter Aufgabenart ebenfalls im privaten Schema begrenzen.
Nach dem Transport passende Beleg-/Wortzuordnung erneut prüfen; anschließend
gelten sämtliche bisherigen Workerprüfungen für Quellenrevision, Sitzung,
Lösung, Hilfe, Grammatik und Providerrevision. Keine gelockerte Sach-/Mathe-
Bewertung und keine Ersatzaufgaben nach einem KI-Fehler. Bestehende gespeicherte
Einheiten/Antworten behalten ihre Belege und Bewertung.

Die bewusste Aktion „Erneut vorbereiten“ verwendet
`POST /children/{child}/language-projects/{project}/retry` mit aktuellem
Kinderlogin und ursprünglicher Fehlerauftrag-ID. Kein Öffnen, GET oder Reload
startet die KI. Ein nach Abmeldung widerrufener Zugang bleibt widerrufen;
ausschließlich diese neue ausdrückliche Aktion bindet die aktuelle eigene
Sitzung. Eltern, Geschwister, andere Familien und Betriebsadmins können den
Kinderauftrag nicht starten. `can_retry` ist eine reine Leseprojektion.

Nur lokaler Operator: `python -m schulpilot.language_repair --project <id>
--failed-job <id> --confirmed-code-fix` ist ein getrennter auditierter Weg nach
beauftragtem Codefix. Mit produktiver Dienstumgebung als Benutzer `schulpilot`
ausführen; niemals Umgebungsdatei/Schlüssel ausgeben. Keine ungeschützte
Operatorschnittstelle. Beide Wege zusammen erlauben höchstens einen zusätzlichen
normal reservierten Auftrag je fehlgeschlagenem Projekt. Child-Sperre,
deterministische Job-ID und Audit serialisieren mehrere Geräte; wiederholte
Anfragen lesen das vorhandene Resultat. Fehlender Tarif, geänderte Quellen,
gelöschte Wörter, laufender Auftrag oder widerrufene neue Sitzung sperren die
Übernahme. Alte Fehler/Versuchszähler/Verbrauch und vorhandene Antworten bleiben
erhalten; keine automatische Wiederholung oder Ersatzübung.

Tatsächliche öffentliche Abnahme des Belegfixes: eigener regulärer künstlicher
Haushalt, zehn manuell bestätigte Wörter, genau ein Codex-Auftrag mit fünf
Prüfaufgaben. Erste Antwort im Web, vier weitere in nativer Flutter-APK33 auf
API36; Feedback nach Reload/Neustart, fünf identische Eltern-/Kinderaufgaben,
ein Reviewereignis je Attempt. Lösungen nicht vorab ausgeliefert. Export und
Löschung des eigenen Haushalts bestanden, alte Sitzungen danach 401, private
Kontodatei entfernt. Kein physisches Telefon und keine Audioabnahme.
Das beauftragte echte Projekt ist wegen zwischenzeitlicher Abmeldung noch
nicht erneut erzeugt: keine Sitzung heimlich reaktivieren. Frisch anmelden und
am ursprünglichen Link ausdrücklich „Erneut vorbereiten“ wählen.
Aktivierte Releases und abschließende Regressionen: STATUS/Handoff.

## Foto → Wortschatz · Ausbau 18.10.2026

Mit 1.4.3+33 bereitgestellt und mit ausschließlich künstlichen Inhalten geprüft:
Der normale Fotoassistent zeigt erkannte wörtliche Wortpaare vor „Stimmt,
weiter“ und lässt die Lernsprache/Variante bestätigen. Dieselbe Transaktion
bestätigt die Quelle und übernimmt die sichtbaren Paare in die bestehenden
Wortschatztabellen. Keine zusätzliche KI, kein Wörterbuch und kein Lernbeleg
durch bloßes Speichern. Fehlende/mehrdeutige Bedeutungen bleiben als offener
Import zum Prüfen erhalten. Nicht zugeordnete Zeilen werden ausgewiesen.
Bei Textkorrektur zuerst eine neue reine Vorschau prüfen, dann bestätigen.

`material_vocabulary.py` verarbeitet `=`, Tabulator, Markdown-Tabellen,
ausgerichtete Spalten, Doppelpunkt und getrennten Gedankenstrich. Deutsche
Spaltenreihenfolge wird anhand eindeutiger Überschriften erkannt; Wortart/
Kontext nur aus ausdrücklich beschrifteten Zusatzspalten übernehmen. Keine
erratene Zuordnung aus drei unbekannten Spalten. Erkannte Grammatikabschnitte
einer gemischten Seite nicht als Vokabelpaare speichern; eine Regel wie
„he, she, it: -s am Verb“ ist keine Übersetzung. Nicht eindeutig strukturierte
Seiten behalten den bisherigen bewussten KI-Import mit Reservierung/Prüfung.
GETs und der reine Vorschau-POST speichern keine Daten und starten keine KI.

Bereits bestätigte Seiten bieten „Wörter übernehmen“. Der deterministische
Schlüssel enthält Quelle, Revision, Locale, Richtung, Prüfstatus und Portion;
Child-Sperre und bestehende Constraints serialisieren Wiederholungen und
mehrere Geräte. Große Seiten bis 400 Paare in vorhandene 80er-Importe teilen;
größere Seiten mit sichtbarem Fehler zurückweisen, nichts abschneiden.
Eintrag, Identität, Revisionen, Quellenlöschung und Export benutzen unverändert
die vorhandene Infrastruktur. Schema bleibt 0016, keine neue Migration.

„Wörter“ ist ein regulärer Navigationspunkt in Seitenleiste, Rail und nativer
unterer Navigation. Eltern wählen dort ein eigenes Kind; Betriebsadmins
erhalten keinen privaten Wortschatzzugriff. Der alte Materiallink öffnet jetzt
den passenden Quellenimport oder die schon vorhandene Sammlung.

309 Fluttertests, 35 gezielte PostgreSQLtests und abschließend alle 806
Backendtests bestanden. Ein vorheriges 503 des bestehenden echten
Codex-Katalogtests separat, im Modul und im erneuten Gesamtlauf nachgeprüft;
Limits unverändert. Analyse/Ruff, Web, signierte Direct-APK und Play-AAB,
Signatur/Zipalign, bundletool und Geheimnisprüfung bestanden.
Produktcommit 48add35, Release 20261018T112557Z-48add35, Schema 0016.
Sicherung und HTTPS/Downloadhashes tatsächlich geprüft.

Öffentlicher normaler Fotoassistent: echtes Codex-OCR eines künstlichen Bildes,
fünf Wortpaare gemeinsam mit Quelle gespeichert, drei reale Webantworten,
Netzverlust/Reload, Zeitminimum, vier Browserbreiten und Elternabgleich.
Genau eine OCR-Reservierung, keine weitere KI für Übernahme/Runde.
Native APK33 nach echtem OTA: Wörter-Menü in Kinder-/Elternbereich,
drei weitere Bedeutungsaufgaben, Feedback nach Kaltstart und Logout.
Export enthält genau fünf Wörter, einen Import und sechs Attempts mit sechs
Reviewereignissen. Eigener Haushalt normal gelöscht, Sitzungen401, private
Kontodatei entfernt. Reproduzierbarer Weg: scripts/prepare_language_smoke.py,
qa/material_words.mjs --run, qa/android_update.py --upgrade/--check-starts,
qa/android_material_words.py, qa/material_words_cleanup.py --run.
Keine physische Telefon-/Audio- oder Lernwirksamkeitsabnahme. Optionale nächste
Aktion: neue eigene künstliche Testfamilie auf einem physischen Telefon prüfen.

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
## Praxistestkorrektur · 19.10.2026 · Build 44

Englische Einzelwörter mit kleinem Anfangsbuchstaben dürfen bei Schreib- und
Abrufaufgaben auch wie ein Satz groß beginnen (`Swimming pool`). Diese begrenzte
Regel verändert weder innere Großbuchstaben noch Eigennamen, Akzente oder deutsche
Nomen. `sentence_initial_optional=false` hält ein ausdrückliches Schreibziel
streng; die Rückmeldung nennt dann den tatsächlich abweichenden Buchstaben.
Bestehende gespeicherte Antworten werden nicht umgeschrieben. Neue Antworten
tragen `language_rule_v2`; ursprüngliche Bewertungen und Hilfen bleiben erhalten.

Die Einzelprüfung unterscheidet Stimmt, Korrigieren, Nicht übernehmen und Weiß
ich noch nicht. Zurückgestellte Importpaare bleiben als eigener privater
Prüfentwurf mit denselben Quellenrevisionen erhalten. Bestätigen ist atomar und
wiederholbar, keine zusätzliche KI. Neue Capability `supports_deferred_pairs`
verhindert stillen Verlust bei einem alten Backend. Foto-Paare bleiben ohne
Übernahme auf ihrer gespeicherten Seite erreichbar.
