# Schulbuddy

Schulbuddy ist eine ausdrücklich gestartete, kontextbezogene Hilfe. Öffnen, Starter und Statusabfragen erzeugen weder KI-Aufträge noch Lernbelege. Ein eigener Kinderzugang oder ein berechtigter Elternzugang mit ausgewähltem Kind verwendet dessen vorhandenes Familien-/Kinderbudget. Nur leseberechtigte Eltern dürfen keinen neuen kostenpflichtigen Auftrag starten. Admins erhalten keine privaten Kinderkontexte und keinen unbudgetierten Chat.

## Kompakter Gesprächsstart · 1.24.1+95

Die beiden allgemeinen Einleitungsblöcke sind im leeren Chat sichtbar. Beim
bewussten ersten Senden verschwinden sie sofort, auch während die Anfrage
noch läuft oder ein Sendefehler angezeigt wird. Ein gespeicherter Verlauf
startet ebenfalls eingeklappt, einschließlich wartender/fehlgeschlagener Turns
und beim erneuten Öffnen. Ein reiner Entwurf startet noch kein Gespräch.

Das Info-Symbol neben „Gespräch“ blendet die Hinweise auf Wunsch wieder ein.
Ein ausdrücklicher Wechsel in einen neuen leeren Seitenkontext zeigt die
Einleitung wieder. „Neue Frage ohne bisherigen Chat“ bleibt im bestehenden
Verlauf kompakt. Konkrete Backend-Sperrgründe, unbekannte Serverhinweise,
Sendefehler und Hinweise auf geänderte Quellen bleiben sichtbar. Nur der
bekannte allgemeine Hinweis „Schulbuddy erklärt und fragt nach …“ wird mit
der Einleitung eingeklappt. Dies ändert keine Freigaben, Requests, Aufträge,
Antworten, Hilfemarker, Kosten oder Retry-Schlüssel.

## HTTP-Vertrag v1

- `GET /api/schulbuddy/context`: `page_kind` aus `today, learn, words, homework, notebooks, account, messages, progress, plan, settings, admin, general`; optionale `child_id, unit_id, material_id, day_id, question_id`. `question_id` benötigt eine passende `unit_id` und muss zur tatsächlich sichtbaren Aufgabe gehören: zur jüngsten noch ungelesenen gespeicherten Rückmeldung oder anschließend zur aktuellen offenen Frage. Antwort: `context_key,label,starters` (höchstens drei), `available,notice,model,reasoning_effort,history` (höchstens acht eigene Turns).
- `POST /api/schulbuddy/questions`: dieselben Kontextfelder, `question` (1–1.200 Zeichen), optional `reply_to`, zwingender URL-sicherer `Idempotency-Key` mit 16–80 Zeichen. Genau ein ausdrücklicher Auftrag; `202` liefert den gespeicherten Turn.
- `GET /api/schulbuddy/questions/{id}`: eigener Turn mit `id,request_key,job_id,status,question,answer,next_question,sources,starters,error,context_key,source_changed,notice`. Keine Wiederholung, kein Retry und kein Anbieterwechsel. Nach unklarer POST-Antwort zunächst eigene Kontext-History anhand `request_key` lesen. Derselbe Schlüssel mit exakt derselben Anfrage liefert denselben Vorgang; ein anderer Inhalt führt zu `409`.

Alle Rechte und IDs werden serverseitig aus Sitzung, Rolle und Familienmitgliedschaft geprüft. Mehrere Kontext-IDs müssen zusammenpassen. Inhalte, Rollen, Modellnamen oder Antwortschlüssel können nicht als freier Clientkontext eingeschleust werden. Elternchats gehören nur ihrem jeweiligen Autor; andere Eltern sehen diese History nicht. Die eigenen Kinderchats gehören zum Kinderexport, der Familienexport ergänzt ausschließlich den Chat des anfordernden Elternteils.

## Kontext und Lernbelege

Höchstens sechs eigene bestätigte Quellen mit zusammen 18.000 Zeichen, vier vorausgehende eigene Antworten derselben Quellenfassung und der kompakte `learning_knowledge.buddy_context` mit höchstens zwölf Wissensgebieten. Dieser unterscheidet gespeicherte selbstständige, unterstützte, unklare, historische und spätere Abrufbelege sowie tatsächlich kuratierte Voraussetzungskanten. Keine privaten Schulnoten, Notizen, Namen, ungeprüften Antwortentwürfe oder ungesehenen Lösungsschlüssel. Nichtfachliche Zugang-/Einstellungs-/allgemeine Bedienhilfe erhält keinen Lernstand.

`schulbuddy_pages.page_context` ergänzt für Heute, Lernen, Wörter, Hausaufgaben,
Hefte und Planung einen erneut berechtigten, lesenden Bestandsauszug bis4.000
JSON-Zeichen: echte Summen, höchstens fünf Runden-/Material-/Auftragsmetadaten
beziehungsweise zwölf vollständige bestätigte Wortpaare mit Sprache und Revision.
Er enthält weder Aufgabenlösungen noch OCR, private Notizen oder Nachrichten.
Der Auszug ist ausdrücklich keine vollständige gefilterte Seitenansicht.
Seine ganze Projektion ist Teil der vor/nach dem Auftrag geprüften Signatur.

Die Antwort enthält keine ausführbare Aktion, Kompetenzzahl oder Bewertung. Verständnisfragen im Chat bleiben ungeprüft. Eine erfolgreiche Hilfe zur tatsächlich aktuellen Frage einer aktiven/pausierten Runde zählt im eigenen Kinderzugang als vorhandene `explanation`-Hilfe. Unit wird vor Child gesperrt; Sitzung, Rolle, Familie, Frage, Quelle, Lernbelege und Modellbindung werden erneut geprüft. Bereits gespeicherte Antworten und abgeschlossene Runden bleiben unverändert. Elternberatung sowie Öffnen, GETs, Starter und Fehler erzeugen keinen Kinder-Hilfemarker.

Gespeicherte Antworten zu geänderten Quellen werden mit `source_changed=true` und ausdrücklichem Hinweis auf die alte Fassung geliefert; eine neue Frage darf diese History nicht als unveränderten Quellenkontext übernehmen. Quellen-/Rundenlöschung entfernt die zugehörigen beziehungsweise davon abgeleiteten fachlichen Chats. Offene, sicher noch ungesendete Reservierungen werden freigegeben; bereits verbrauchte oder unklare Kosten bleiben erhalten. Private Turns werden nach 365 Tagen entfernt. Migration `0027` ergänzt ausschließlich die neue private Tabelle.

Während einer gespeicherten ungelesenen Aufgabenrückmeldung berät Schulbuddy
genau zu diesem Rückkehrpunkt. Er überspringt weder die Rückmeldung noch bindet
er schon die nächste Frage. Diese Beratung ändert keine gespeicherte Antwort
und setzt keinen rückwirkenden Hilfemarker. Wird die Rückmeldung während eines
laufenden Auftrags quittiert, passt dessen Kontextsignatur nicht mehr; alte
Antworten außerhalb dieses Rückkehrpunkts bleiben gesperrt.

## Eigene Modellbindung und Freigabe

Bei der Vorbereitung vor Release 90 am 22.10.2026 wurde rein lesend geprüft: normaler Lernprovider OpenRouter, Revision29, Sol-/Luna-Mix mit medium. Der eigene isolierte Codex-Worker meldete CLI0.162.1 und bot im tatsächlichen `model/list` GPT-6-Luna (`gpt-6-luna`) mit high an. Dieser Katalogabgleich war ausschließlich ein Metadatenbeleg. Die späteren echten 90- und 91-Proben sind unten getrennt dokumentiert. Auch GPT-6.1-Sol mit max war im selben Katalog vorhanden; daraus folgt keinerlei Reparatur- oder Hostberechtigung.

Nur Schulbuddy verwendet `ProviderConfig`-Zeile2; Zeile1 und ihr Lernmix bleiben unverändert. Der lokale Operator wählt ein tatsächlich im Katalog vorhandenes, nicht verborgenes Luna-Textmodell mit high und dokumentiert die eigene Datenschutzentscheidung. Ein fester künstlicher Schema-/Zitattest wird über den bestehenden globalen Kostenbucket mit zusätzlicher Obergrenze0,25USD einmal pro ausdrücklicher Aktion reserviert. Erst ein passender abgeschlossener Prüfbeleg plus Audit aktiviert diese genaue Modellrevision. Kein automatisches Aktivieren, kein Fallback und kein API-Abrechnungswechsel.

Jeder reguläre Job speichert Provider, Modell, high, eigene Bindingrevision, globale Providerrevision und Budgetstand. Vor und nach dem Aufruf werden sie mit Sitzung und Quellen geprüft. Der globale Notfallstopp, bestehende Reservierungs-, Aufruf-, Familien- und Kindergrenzen bleiben wirksam. Bei Codex-Konto sind USD-Kosten unbekannt; die volle bestehende Reservierung bleibt erhalten. Schulbuddy setzt im tatsächlichen Workerauftrag `web_search=false`; der vorhandene isolierte Gateway erstellt dafür `tools=[]` und `tool_choice=none`, auch wenn die allgemeine Betreiber-Suchfreigabe aktiv ist.

Einmalige Ersteinrichtung nach Deployment der passenden Quellen und Migration,
im vorhandenen Dienstkonto-Environment und aus dem Backend-Verzeichnis
(keine Secrets in Argumenten oder Ausgabe). Dies ist kein automatischer Schritt
bei jedem Update; die vorhandene geprüfte Bindung wurde für 91 erhalten:

```sh
cd /opt/schulpilot/current/backend
/opt/schulpilot/current/venv/bin/python -m schulpilot.schulbuddy_setup select --model gpt-6-luna --privacy-evidence 'Betreiberauftrag 22.10.2026: eigener kontextbezogener Schulbuddy über isolierten Codex-Kontozugang, Luna/high, ohne Websuche; bestehende Datenschutzgrenzen erhalten.'
/opt/schulpilot/current/venv/bin/python -m schulpilot.schulbuddy_setup probe
```

`select` allein lässt den Chat gesperrt. `probe` verarbeitet ausschließlich die feste serverseitige künstliche Vorlage und gibt nur neutrale Modell-/Kosten-/Prüfmetadaten aus. Bei nicht passendem Katalog, fehlender Anmeldung, fehlender Freigabe oder ungültigem Schema bleibt er gesperrt. Während dieser historischen Vorbereitung blieb die damalige 89-Installation unverändert. Die inzwischen tatsächlich veröffentlichte 91-Version ist separat unten belegt.

## Historische lokale Nachweise bis Release 90

Erster isolierter PostgreSQL-Zielblock:17 Tests grün (`artifacts/ux90/schulbuddy-pg-recheck.log`), ausschließlich MockClient/Mockadapter und künstliche Daten. Der vorangegangene direkte Fehler im Helper-Schlüssel wurde korrigiert; abgebrochene langsame SQLite-DDL-Läufe sind keine Testnachweise. Abschließender erweiterter PostgreSQL-Regressionslauf:123 Tests grün, darunter20 eigene Schulbuddyfälle sowie Tutor-/Codex-Provider-/isolierte Workerregressionen (`artifacts/ux90/schulbuddy-regressions-final.log`). Die Läufe werden nicht addiert; Ruff und Diffcheck sauber. Keine zusätzliche AK- oder UX-Zählung für Schulbuddy.

Nach unabhängiger Gegenprüfung: finaler gemeinsamer PostgreSQL-Block mit82
Schulbuddy-, Seitenkontext-, Vorwissens- und gespeicherten Rückmeldungsfällen
grün (`buddy-final-integrated-pg.log`). Der echte UnitScreen/Workspace-Buddy
bestand gemeinsam mit Wissens- und Operatoransicht25 Widgetfälle; insbesondere
bleibt die sichtbare Rückmeldung stehen, bis das Kind bewusst weitergeht.
Die damalige vollständige eingefrorene 90-Flutter-Serie bestand mit2.385 Tests
und zehn plattformbedingten Überspringungen. Mocktests belegen keinen
Modelltransport. Unter 90 bestand anschließend die regulär reservierte feste
künstliche Luna/high-Operatorprobe mit korrekter Nennererklärung und geprüftem
Quellenzitat. Der dabei gefundene technische Zitiermarker wurde eng korrigiert
und offline gegen dieselbe Antwort geprüft; dafür gab es keinen zweiten
Modellaufruf. Diese historische Probe ist keine 91-UI-Abnahme.

## Produktionsnachweis91

Live: **1.22.1+91**, Release `20261022T204523Z-b42447c`, Produktcommit
`b42447cb61a53d2249a0eddd09cd31f51e67b50a`, Schema 0029. Build und öffentliche
APK-/JavaScript-Hashes sind gegen denselben sauberen Quellstand geprüft; Details
und Grenzen im [Releasebericht](RELEASE_91_2026_10_22.md).

Die Verfügbarkeitsgrenze ist zusätzlich an den tatsächlichen Serverstatus
gebunden: Fehlende oder nicht ausdrücklich bestätigte Verfügbarkeit sperrt
Starter, Eingabe und Senden. Der künstliche Testraum zeigt „Testraum · Vorschau“
und den konkreten Hinweis. Andere gesperrte Kontexte heißen „Chat nicht
verfügbar“. Private Entwürfe und gespeicherte History bleiben erhalten.
34 native Schulbuddy-/Integrationsfälle und neun Sperrfälle im echten
isolierten Chrome-Runner sowie die vollständige Flutteranalyse bestehen;
Belege unter `artifacts/ux91/buddy-availability-final-{native,chrome}.log` und
`buddy-availability-full-analyze.log`. Dies sind ausschließlich synthetische
API-Antworten, getrennt von der folgenden echten UI-Probe.

Für die tatsächliche 91-Probe wurde eine neue eigene Familie regulär registriert
und über ihre Gmail-Plusadresse verifiziert, mit genau einem künstlichen Kind.
Eine ausdrücklich beauftragte, einmalige und eng begrenzte auditierte
QA-Freigabe ersetzte weder einen Trial-/Zahlungsbeleg noch setzte sie das
Demo-Flag. Globale, Familien-, Kinder- und Anbietergrenzen blieben erhalten.

Im echten Kinderbrowser auf der Hausaufgabenseite wurde genau einmal der
Starter **„Wie fange ich an, ohne die Lösung zu sehen?“** gesendet. Die sichtbare
`gpt-6-luna`/`high`-Antwort gab einen Denkschritt ohne Lösungsverrat. Nach
Schließen und Wiederöffnen blieb die History sichtbar, ohne einen weiteren
Auftrag auszulösen. `buddy-regular-ready.png`, `buddy-regular-answer.png` und
`regular-buddy-after-ui.json` unter `artifacts/ux91/` belegen UI und neutralen
Serverabgleich: genau ein Job/Turn/Verbrauchsbeleg, `completed`/`ready`, passende
Reservierungsverknüpfung und Settlementversion 1. Die volle Reservierung von
**150000 USD-Mikroeinheiten bleibt angerechnet**; tatsächliche Codex-Kontokosten
sind **unbekannt**. Die Bedienfrage ist kein Kompetenzbeleg und keine allgemeine
fachliche Qualitätsabnahme.

Die separate zweite Sol/max-Reparaturprobe endete mit `empty_patch`, ohne
Reparaturartefakt oder erfolgreichen Nachhertest. Die normale Buddy-Prüffamilie
wurde über den regulären Kontolöschweg vollständig bereinigt; Löschjournal,
Audit, entfernte Identitäten, widerrufene Sitzung und Kinderlogin401 sind in
`artifacts/ux91/regular-buddy-cleanup.json` belegt. Weder
alle Browsermenüs noch die verbleibende 320px-Elternnavigation gelten durch
diese einzelne Schulbuddy-Probe als vollständig abgenommen. Spätere 92-,
Reparatur- und Cleanup-Belege werden gesondert ergänzt.
