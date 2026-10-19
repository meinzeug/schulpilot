# Zustandsbehaftete Lernbegleitung und OpenRouter

Stand: 19.10.2026, Erweiterung für 1.10.0+47, additive Migration 0023.
Tatsächliche Bereitstellung und abschließende Testergebnisse: STATUS.md und
CHATGPT_HANDOFF.txt. Ein Build oder API-Schlüssel ist keine Anbieterfreigabe.

## Komponenten und Gedächtnis

Die vorhandene Plattform bleibt erhalten: Flutter, FastAPI, PostgreSQL,
SQLAlchemy/Alembic und derselbe persistente Worker. Keine neuen Dienste.

| Verantwortung | Implementierung |
| --- | --- |
| Material verstehen | Vorhandene wörtliche OCR, Quellenbestätigung, Abschnittsrollen und Revisionen |
| Wissen strukturieren | Bestehende belegte Coach-Lernziele; `learning_controller.knowledge` ergänzt nur passende vorhandene Ziele um geprüfte Voraussetzungen |
| Lernnachweise | Bestehende Attempt/Activity, `coaching.goal_states`, Wortreviews und Lernfortschrittsledger bleiben maßgeblich |
| Planen | `learning_controller.decide`, bestehender Tagesplan mit Elternaufträgen, Notenschwerpunkten, Wiederholungen und freien Tagen |
| Ressourcen wählen | Lokaler Sofatutor-Matcher; neue Modellinhalte nur im ausdrücklich reservierten Auftrag |
| Ergebnisse prüfen | Bestehende deterministische Mathematik-/Sprachprüfung und getrennte beratende Coach-Auswertung |
| Ausführen | Bestehende DB-Jobs; `controller_jobs` für die ausdrücklich angeforderte Medien-Anschlussrunde |

`learning_memory` speichert aktuelle Entscheidung, Revision, Planrevision,
Quellenfingerabdruck, Antwortentwurf, Medienrückkehr und vorbereitete Folgeaktion.
`learning_controller_events` speichert eindeutige Ereignisse mit Verweisen auf
vorhandene Belege und die jeweilige Entscheidung. Es entstehen keine zweiten
Antworten oder zusätzlichen Kompetenzpunkte. Beobachtung und Vorschlag bleiben
getrennt. Der konkrete Nennerfehler wird nur aus einer tatsächlich falschen
Bruchantwort abgeleitet; keine allgemeine Diagnose über das Kind.

Eine kleine versionierte Voraussetzungsliste verknüpft ausschließlich schon
belegte Bruchziele. Das ist kein vollständiger Lehrplan-/Kompetenzgraph für alle
Fächer. Andere Themen verwenden weiter die vorhandenen belegten Lernziele.
Altdaten erhalten keine rückwirkenden Beherrschungsnachweise.

## Entscheidung und Ausführung

Einheit vor Kind sperren, Rechte prüfen, Ereignis deduplizieren, aktuellen
Quellenstand und gespeicherte Antworten lesen, vorhandene Aktion verwenden,
passende lokale Ressourcen suchen und erst bei Bedarf einen Auftrag reservieren.
Die Planrevision plus Quellenfingerabdruck bindet eine Generierung vor und nach
dem externen Aufruf. Eine verspätete Antwort darf einen neueren Plan nicht
überschreiben. Reine Entwurfsspeicherung invalidiert keinen fachlich gleichen
Plan. Aufruf-/Quellen-/Provider-/Sitzungsprüfungen bleiben zusätzlich bestehen.

Der endliche Aktionsvertrag enthält Art, Phase, Lernziel, Frage, Belegverweise,
kurzen Grund, erwartetes Ergebnis und zulässige Schritte bei Erfolg/Fehler.
Keine Befehle, frei ausführbaren Werkzeuge oder internen Reasoning-Protokolle.
Beim geprüften OpenRouter-Mix darf der bereits reservierte Coach-Auftrag einen
begrenzten `next_step` vorschlagen. IDs und Eignung werden geprüft. Ein Vorschlag
ändert weder Antworten noch Termine; ein akzeptierter Vorschlag beeinflusst die
Gestaltung der nächsten ausdrücklich angeforderten Anschlussrunde. Widersprüche
zu festen Ergebnissen werden als abgelehnter Vorschlag gespeichert.

Ausgangsregeln:

- Neuer Stoff ohne aktuelle Belege: erst eine vorhandene kleine Aufgabe selbst
  versuchen; die gespeicherte Erklärung bleibt erreichbar.
- Ein Fehler: kleiner Hinweis, keine pauschale Wissenslücke.
- Wiederholt derselbe belegbare Nennerfehler: gleich große Bruchteile prüfen.
- Mehrere Fehler/Hilfen: andere Darstellung und geeignete Katalogressource.
- Nach Hilfe: neue quellengebundene Aufgabe; gezeigte Lösung ist kein freier Abruf.
- Unklare Bewertung: Klärungsweg; kein negatives Kompetenzsignal.
- Gemeldete Überforderung: kleiner Schritt beziehungsweise Pause anbieten.
- Runde fertig: Ergebnis und Beendigung auch bei offenem Minuten-Tagesziel.
- Späterer Abruf: bestehende revisions- und tagesgebundene Wiederholungslogik.

Heute/Elternübersicht erhalten eine kleine reine Leseprojektion des nächsten
vorhandenen Lernschritts. Anmeldung und Navigation erzeugen keine kostenpflichtige
Neuplanung. Elterntermine, Pausen, Quellenreihenfolge und getrennte Zeitziele
bleiben bei der vorhandenen Planung.

## Wiederaufnahme und Sofatutor

Neue Clients speichern Antwortentwürfe mit eigener Revision, Idempotenzschlüssel
und Eingabemethode. GETs verändern nichts. Zwei Geräte erhalten bei einem
Konflikt eine ausdrückliche Auswahl statt stillen Überschreibens. Zusätzlich gibt
es höchstens acht lokale Entwürfe für 24 Stunden, kontogebunden und beim Abmelden
entfernt. Entwürfe sind keine Antwortversuche und keine Lernzeit.
Beim Pausieren wird eine laufende Speicherung abgewartet und anschließend die
neueste Eingabe mit der aktuellen Revision gespeichert. Lokale Wiederaufnahme
bleibt auch während eines Netzfehlers erhalten; ein Gerätekonflikt erfordert
weiterhin eine bewusste Auswahl. Die Verlassen-Meldung unterscheidet neue
Entwurfsspeicherung von älteren Backends ohne diese Fähigkeit.

Sofatutor wird nach dem konkreten Verständnisbedarf lokal gesucht; keine neue KI
beim Öffnen einer Ansicht. Titel/Themen sind die Wissensgrundlage, keine Kenntnis
des vollständigen Videos. Höchstens drei Tipps, echte gespeicherte HTTPS-Links,
Abo-/Anmeldehinweis und Fehler-/Kopierweg bleiben erhalten.

`open`, `watched`, `skipped`, `not_helpful`, `broken` bleiben getrennte Medienbelege.
`watched` ist ausdrücklich eine Selbstauskunft. Bei der noch offenen zugehörigen
Aufgabe gilt die angesehene Erklärung als Hilfe. Frühere Antworten werden nicht
nachträglich umgeschrieben. Unpassende/defekte Inhalte werden für diesen Kontext
zurückgestellt. Videoaufrufe erzeugen weder Kompetenz noch Aktivitätszeit.

Nach Rückkehr: gespeicherte Aufgabe weiter bearbeiten oder **bewusst zwei neue
Aufgaben prüfen**. Genau ein Job je Öffnung, wiederholter POST liefert denselben
Job. Die ursprüngliche Runde wird pausiert; Entwurf/Antworten bleiben erhalten.
Ein gespeicherter Vorbereitungsstand erscheint nach Neustart direkt als nächste
Aktion; die ursprüngliche Aufgabe bleibt ausdrücklich weiter erreichbar.
Die öffentliche Demo darf diesen Pfad nicht für externe freie Eingaben nutzen.
Für allgemeine Altthemen ohne belegte Lernziele muss zuerst die bestehende Runde
mit Rückblick beendet werden. Fehlgeschlagene Vorbereitung bleibt sichtbar;
kein automatischer Retry. Diese Einschränkung wird im Dialog erklärt.

## Modellwahl und Datenschutz

OpenRouter ist der neu beauftragte Standard. Bestehende aktive Codex-Auswahl wird
bei Code-Deployment nicht heimlich umgeschaltet. Der lokale Operatorwechsel und
technische Probeweg sind unten beschrieben. Direkter OpenAI-Adapter und isolierter
Codex bleiben optional; es gibt keinen automatischen Anbieterwechsel.

`model_routing.py` bindet die Auswahl einmal je Reservierung. Klare Abschrift und
begrenzter Rückblick beginnen auf Luna; neue Unterrichtsaufgaben, Pakete, Tutor
und anspruchsvolle Erklärungen auf Sol. Dokumentierte wiederholte Unklarheit kann
Astra verlangen. Fehlt dafür eine geprüfte Route, wird kein anderes Modell
erraten. Es wird keine künstliche 70/28/2-Quote erzwungen.

Verifizierter Katalog am 19.10.: die drei gewünschten Modellkennungen existieren.
Azure-ZDR-Endpunkte sind gelistet; folgende Standard-Preise wurden über die
Endpunkt-API gelesen (USD je Million Tokens):

| Modell | Input | Completion einschließlich Reasoning |
| --- | ---: | ---: |
| openai/gpt-6-luna | 0,10 | 0,50 |
| openai/gpt-6.1-sol | 2,00 | 10,00 |
| openai/gpt-6-astra | 10,00 | 50,00 |

Jeder bezahlte Mix-Aufruf: `/api/v1/chat/completions`, explizites Modell und
Upstreamliste, `require_parameters=true`, `allow_fallbacks=false`,
`data_collection=deny`, `zdr=true`, dokumentierte Preisobergrenzen und
`reasoning.effort=medium`. Keine Werkzeuge, Plugins, Websuche oder Audioerzeugung.
Kein ungeprüftes Responses-Umbiegen. Der bestehende Worker verwendet vollständige
JSON-Antworten; Streaming ist nicht implementiert und wird nicht vorausgesetzt.
GPT-6-Promptcache wird ohne Breakpoints explizit betrieben; keine automatische
Cacheersparnis kalkuliert. Kein familienübergreifender Inhaltscache.

ZDR gilt für den tatsächlichen Upstream; OpenRouter-eigene Inhaltsprotokollierung und Datenfreigabe müssen separat
geprüft werden. Response-Caching wird per dokumentiertem
`X-OpenRouter-Cache: false` auch gegen Presets ausgeschaltet. Der Inferenzschlüssel kann
diese Workspace-Einstellungen nicht nachweisen. Diese Prüfung ist noch offen.
OpenAI verlangt für personenbezogene Daten unter 13 beziehungsweise unter dem
anwendbaren Einwilligungsalter ZDR. Keine EU-Verarbeitung behauptet: regionale
OpenRouter-Hosts erfordern nach aktueller Dokumentation Business/Enterprise und
einen eigenen Nachweis; es wurde kein Upgrade gebucht.

## Abrechnung, Gebühren und Budgets

Geldwerte sind Integer-Mikrobeträge beziehungsweise Decimal, nicht Float für
Budgetentscheidungen. Reservierungen laufen atomar gegen bestehende globale und
Familiengrenzen sowie das neue monatliche Kinderbudget. Noch strengere Grenzen
bleiben bestehen. Standardwerte: Ziel7 €, Warnung9 €, hart12 €; Monat UTC,
Lern-/Wiederholungstage weiterhin Elternzeitzone. FX-Kurs, Quelle und Datum müssen
ausdrücklich konfiguriert und höchstens31 Tage alt sein. Modell-/Preisprüfung
verfällt ebenfalls nach31 Tagen.

Usage speichert gebundene Route/Promptversion, tatsächliches Modell/Upstream,
Generation-/Requestkennung, Tokens, Cache, Reasoning als Teilmenge, Laufzeit,
Status und Abrechnungsherkunft. Ungültige kostenpflichtige Ausgaben werden auch
bei fehlgeschlagener Fach-/Schemaprüfung abgerechnet. Fehlende Usage hält die volle
Reservierung. Metadaten-Abgleich höchstens dreimal per Generation-ID, ohne neue
Inferenz. Sicher vor Transport abgewiesene Größenüberschreitung ist als nicht
gesendet erkennbar. Settlement ist idempotent.

Echte Guthabenbelege separat im Admin-Kostenbereich erfassen: erworbenes Guthaben
und tatsächliche Kaufgebühr. Es erfolgt **kein Kauf**. Die Gebühr wird FIFO und
anteilig nur auf verbrauchtes Guthaben verteilt. Unverbrauchtes Guthaben ist kein
Monatsaufwand. Ohne Beleg bleiben Gebühren unbekannt und die konservative
EUR-Reservierung bestehen. 5,5% Standard/8% Business sind Kalkulationsszenarien aus
der Preisübersicht, keine erfundene Rechnung dieses Kontos.

Admin zeigt Modellanteile, unbekannte Kosten, unbrauchbare Ausgaben, pseudonyme
Kostenstellen, Kinderbudgetzustand, P50/P95, Spitzenlast und Eskalationen. Kosten
abgeschlossener Runden werden nur für eindeutig zugeordnete Jobs ausgewiesen;
OCR und nicht mehr zuordenbare alte Jobs fehlen darin ausdrücklich. Ein Preis
pro sicher beherrschtem Lernziel kann daraus noch nicht belastbar abgeleitet werden.

## Gemessene kleine Evaluation

Bereinigte Messwerte: OPENROUTER_EVALUATION_2026_10_19.json. Private vollständige
künstliche Antworten bleiben außerhalb von Git unter
`~/.local/share/schulpilot-evaluation/`. Reproduzierbar mit
`scripts/evaluate_openrouter_mix.py --full`; gespeicherte Fehl-/Erfolgsjobs werden
nicht automatisch erneut aufgerufen. Gesamtes isoliertes Prüfbudget0,25USD.

25 verwertbare Bild-/Aufgabenantworten,0,065440USD erfasste Inferenzkosten;
inklusive zwei konservativ offener Reservierungen0,195440USD gebunden. Eine
abgebrochene Sol-Antwort und ein älterer vor Transport abgewiesener Vorgang werden
nicht heimlich als kostenfrei ausgebucht. Neun von zehn künstlichen Bildquellen
wurden tatsächlich erkannt; alle zehn Referenztexte ergaben Luna-Aufgaben.
Ein Sol-Vergleich gelang bei drei dieser Quellen, ein weiterer brach ab, sechs
wurden vom Prüfbudget gar nicht gestartet. Hinzu kommen drei erste Bruchproben.
Mathematik, Deutsch, Englisch, Biologie und Geografie sind damit **keine fünf
vollständig live abgenommenen Lernketten**. Astra nur Metadaten, kein Inferenztest.

Die geprüften synthetischen Aufgaben/Lösungen wurden zusätzlich durchgesehen.
Die Stichprobe ergab keine offensichtlich falsche Hauptlösung, ist aber zu klein
für eine belastbare Fehlbewertungsquote oder allgemeine Modellfreigabe. Luna
lieferte bei ähnlichen Aufgaben deutlich günstigere Antworten; das beweist noch
keine Gleichwertigkeit bei Rückblick, schwieriger OCR oder Sprachprojekten.

Hypothese4.000 Input+1.500 Completion-Tokens einschließlich Reasoning,70/28/2:
480 Aufrufe/24Lerntage4,5816USD Inferenz beziehungsweise4,833588USD bei5,5%-Gebühr;
680Aufrufe mit zehn intensiven Tagen6,847583USD einschließlich dieser Gebühr;
960Aufrufe9,667176USD. Keine gemessenen EUR-Monatskosten oder garantierte7€.
Die kleinen Tests verwendeten im Mittel erheblich weniger Tokens. Bildnutzung
ist in den tatsächlichen OCR-Usage-Werten enthalten; kein zusätzlicher erfundener
Pauschalpreis. Cachekosten, unbekannte Abbrüche, tatsächlicher Mix, Gebühren,
Wechselkurs und Qualität müssen im regulären Verlauf weiter geprüft werden.

## Operator: Konfiguration und Rückweg

1. `/etc/schulpilot/environment`: `OPENROUTER_API_KEY`, root:schulpilot0640.
   Lokale Quelle `~/or.txt`; niemals Key als Argument oder in einer Ausgabedatei.
   Dieser Schlüssel wurde sicher per SSH-stdin hinterlegt. Kein Neustart allein
   durch das Hinterlegen, kein Wechsel des aktiven Providers.
2. Unter Admin → KI-Anbieter → Modellmix die versionierte RoutingPolicy pflegen
   (Schema `model_routing.RoutingPolicy`). Konkrete Modelle, Upstreams, Preis-/
   Fähigkeits-/Datenschutzbelege, FX, Prüfdatum und individuelle Freigaben setzen.
3. Alternativ lokal `sudo python3 /opt/schulpilot/current/deploy/admin.py
   configure-openrouter-mix < /geschuetzter/pfad/operator-policy.json`.
   JSON enthält nur `policy` und dokumentierte `evidence`, keinen Schlüssel.
   Vorher den früheren Providerstand geschützt sichern. Bestehende Limits und
   Notfallstopp werden nicht gelockert. Neue Konfiguration zunächst gesperrt.
4. Geschützten Admin-Button für Bild-/Aufgaben-/Paketprüfung verwenden. Drei feste
   künstliche Vorlagen, derselbe DB-Worker, globale Reservierung und zusätzlich
   höchstens0,25USD je Prüfauftrag. Kein Retry beim GET. Nur unveränderte
   Konfiguration und wirklich erfolgreiche Antworten heben die technische Sperre
   auf. Das ersetzt nicht die getrennten Kinder-/Datenschutz- und Qualitätsbelege.
5. Konto-Logging/Response-Caching und tatsächliche Route dokumentieren. Nur
   evaluierte, altersgerecht freigegebene Routen zulassen. Astra bleibt ohne
   eigene Evaluation gesperrt. Kein Fallback zur Umgehung.
6. Belege im Admin-Kostenbereich erfassen, Warnungen/Fehler prüfen; Notfallstopp
   bleibt unabhängig vom Providerstatus erreichbar.

Migration: vorhandenen Backup-/Deployweg benutzen, `alembic upgrade head` auf0023.
Neue Tabellen/Spalten sind additiv; alte Antworten und Materialien bleiben.
Löschung/Export enthalten Gedächtnis, Ereignisse und Kinderkosten. Lerndaten
365Tage, Usage90Tage; alte Kinderkostenmonate passend bereinigt. Keine privaten
Daten in technische Logs. Rückweg über den vorhandenen vorherigen Release ohne
Schema-Downgrade; neue Tabellen bleiben erhalten. Vorwärtskorrektur bevorzugen.
Vor Rückkehr auf älteren Code zunächst den KI-Notfallstopp aktivieren und die
frühere Anbieterwahl geschützt wiederherstellen; alte Versionen kennen die neuen
Kinderbudget-/Demogrenzen nicht. Kein altes Datenbankbackup über neuere Antworten
oder Löschjournale schreiben.

## Zehn Controller-Szenarien

`test_learning_controller.py`, `test_controller_media.py`, vorhandene Coaching-/
Tagesplan-/Wortreviewtests; ausschließlich künstliche Profile und gemockte Modell-
antworten. Das sind Implementierungsnachweise, keine Lernwirksamkeitsstudie.

| Ausgang/Ereignis | Entscheidung/Aktion | Gespeicherter und geprüfter Zustand |
| --- | --- | --- |
| Neues Ziel, Vorwissen vorhanden | Erst selbst versuchen, dann fertig | Zwei erste selbstständige Antworten; kein pauschales Beherrscht |
| Einzelner Rechenfehler | Kleiner Hinweis | Falscher Attempt bleibt, keine Diagnose |
| Wiederholt Nenner addiert | Voraussetzung prüfen/andere Darstellung | Konkrete Attemptverweise und Zahl betroffener Aufgaben |
| Lerntipp geöffnet/zurück | Neue bewusste Zweierprobe | Ein reservierter Job, alte Runde pausiert, Entwurf erhalten |
| Lerntipp nicht hilfreich | Ressource zurückstellen, anderer Weg | Keine Kompetenzänderung, Kontext-Rückmeldung erhalten |
| Erst nach Hilfe richtig | Später ohne Vorlage prüfen | Unterstützter Attempt, kein selbstständiger Ersttreffer |
| Verzögerter Abruf scheitert | Bestehende Wiederholungsplanung | Abstand/Fälligkeit aus echten Antworten, keine Erfolge geraten |
| Quelle korrigiert | Neue Quelle bestätigen | Alter Attempt erhalten, alter aktueller Plan ungültig |
| Unterbrechung/zwei Geräte | Entwurf wieder aufnehmen/Konflikt klären | CAS+Idempotenz; keine zusätzliche Antwort oder Lernzeit |
| Budget/Provider begrenzt | Bestehende Runde nutzbar, neuer Job offen/fehlt | Kein Dummy, kein automatischer Retry, unbekannte Kosten gehalten |

## Offizielle Prüfbasis

Geprüft am19.10.2026:

- https://openrouter.ai/docs/guides/routing/provider-selection
- https://openrouter.ai/docs/guides/features/zdr
- https://openrouter.ai/docs/guides/best-practices/reasoning-tokens
- https://openrouter.ai/docs/guides/best-practices/prompt-caching
- https://openrouter.ai/docs/api/api-reference/generations/get-request-&-usage-metadata-for-a-generation
- https://openrouter.ai/pricing
- https://openrouter.ai/openai/gpt-6-luna
- https://openrouter.ai/openai/gpt-6.1-sol
- https://openrouter.ai/openai/gpt-6-astra
- https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance
