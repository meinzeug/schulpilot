## 30.10.2026 · Mobiler Seitenwechsel und Listengrafiken · Version 1.38.23

Beim mobilen Alltagstest wechselte die Quellenprüfung nach einer Bestätigung
korrekt zur nächsten Seite, behielt aber die untere Scrollposition. Der
Seitenanfang der neu gewählten Kinderseite wird nun sichtbar gemacht; normale
Statusaktualisierungen derselben Seite verändern die Scrollposition nicht.
Statische quellengebundene Listen mit zwei Leseschritten zeigen direkt die
Schrittwahl; optionale Vergleichs- und Detailfunktionen stehen unter „Mehr zur
Grafik“. Andere Szenen behalten ihre Animationssteuerung. Die KI-Anweisung
fordert außerdem kurze, klare Aufgabenstellungen ohne unnötige Fachlabels.
Auch beim Vorwissenscheck ist der freiwillige Einstieg in die gespeicherte
Erklärung direkt erreichbar; das Öffnen bleibt eine ausdrückliche Aktion und
die bestehende Bewertung erfasst spätere Antworten weiterhin als unterstützt.
39 Grafiktests und 26 Prüfungen des Foto-/Seitenablaufs bestanden, darunter
kleine Ansichten und große Schrift; 30 Tests prüfen den Lernraum und den
Erklärungseinstieg. Ein weiterer künstlicher Modellaufruf
gelang (0,0396066 USD); einzelne Formulierungen können weiterhin zu lang sein.

Auf 1.38.22 wurde Junas ausdrücklich beauftragte Geschichtsetappe nach dem
erneuten Vorbereiten mit vier Aufgaben geöffnet und anschließend pausiert;
es wurden keine Testantworten eingetragen. Der laufende 30-Tage-Alltagstest
verwendet einen getrennten lokalen Testhaushalt, künstliche Bilder und eine
isoliert verstellbare Testzeit. Am ersten simulierten Tag wurden zwei Seiten
über den mobilen Browser abgegeben; beide Paketabschnitte wurden erstellt.
Eine falsch und anschließend richtig beantwortete Bruchfrage wurde als
unterstützt erfasst. Die gezielt vorbereitete Anschlussübung erklärte Zähler
und Nenner mit Grafik; zwei nach Öffnen dieser Erklärung beantwortete Fragen
wurden ebenfalls als unterstützt gewertet. Eine In-App-Fertigmeldung öffnete
die zugehörige Deutschrunde. Ein künstliches Noten-PDF lieferte vier Noten;
beim erneuten Import wurden alle vier als unverändert wiedererkannt.
Die getrennte Simulation ist damit noch nicht abgeschlossen.

## 30.10.2026 · Quellgebundene Listengrafiken für Etappen · Version 1.38.22

Ein weiterer ausdrücklich beauftragter Geschichtsversuch scheiterte nach der
Modellantwort an der Referenzprüfung. Für eine bestätigte Quellliste kann die
Etappe jetzt dieselben bereits geprüften Darstellungen und Antwortoptionen wie
die Paketerstellung verwenden. Die KI wählt aus den eng an die jeweilige
Quelle und Offenlegungsstufe gebundenen IDs; Aufgabenformulierung und Lösung
bleiben Modellantworten und durchlaufen weiterhin die normalen Prüfungen.
Ohne passende belegte Liste wird keine erfunden. Auch andere Fach-Etappen
verwenden, soweit unterstützt, die vorhandene Referenzbindung.

90 gezielte Backendfälle bestanden. Ein reservierter echter OpenRouter-Aufruf
mit festem künstlichem Geschichtsstoff erzeugte zwei geprüfte Aufgaben in
28,84 Sekunden, mit 0,0364694 USD Anbieterpreis. Ein einzelner erfolgreicher
Kunsttest belegt keine allgemeine Fehlerfreiheit aller Quellen und Fächer.

## 30.10.2026 · Szenenbelege bei Lernetappen · Version 1.38.21

Bei einem ausdrücklich beauftragten Geschichts-Liveversuch schlug die
Grafikprüfung mit `scene_label_evidence` fehl. Eine Szene darf ihren wörtlichen
Grafikbeleg nun begrenzt erweitern, ausschließlich als zusammenhängenden
Ausschnitt derselben ausdrücklich zitierten, bestätigten Quelle. Inhalte,
Beschriftungen, Pfeile, Aufgaben und Quellenzuordnungen werden nicht erfunden
oder verändert; sämtliche bisherigen Prüfungen laufen danach erneut.
Die Anbietervorgabe beschreibt außerdem die bereits geltende Pflicht zu
wörtlich belegten Szenenpfeilen genauer. Erfundenes, fremde Quellen und
umgekehrte Pfeile bleiben gesperrt.

Ein reservierter echter OpenRouter-Test mit festem künstlichem Geschichtstext
scheiterte zunächst an `visual_scene_relations` (0,0469304 USD); nach der
Präzisierung bestand eine weitere echte Etappe mit zwei Aufgaben die regulären
Prüfungen (0,0524458 USD, 59,99 Sekunden). Ein Paketvorversuch wurde vor
Anbieterversand mangels passender vorbereiteter Referenz abgebrochen. Diese
Einzelprüfungen sind keine Garantie gegen künftige Anbieter- oder Quellenfehler.

## 30.10.2026 · Vorbereitungsstatus von Lernweg-Etappen · Version 1.38.20

Der Live-Test von 1.38.19 zeigte, dass die Statusseite `study_block`-Aufträge
nicht akzeptierte. Sie liest nun auch diesen Auftragstyp und öffnet nach
Abschluss die gespeicherte Runde; reines Abfragen startet keinen neuen Auftrag.

## 30.10.2026 · Gewähltes Lernthema öffnen · Version 1.38.19

Ein ausgewählter geplanter Themenbaustein öffnet seine eigene Vorbereitung.
Die vorhandene Planung gibt pro Fach nur die jeweils erste freiwillig
verfügbare Etappe frei; eine fehlgeschlagene Etappe eines anderen Fachs
blockiert diese Auswahl nicht. Quellenprüfung, Reihenfolge innerhalb des
Fachs, Reservierungen und Wiederholungsgrenzen bleiben erhalten.

## 29.10.2026 · Begrenzter Pakettransport · Version 1.38.18

Die [Azure-Dokumentation zu strukturierten Ausgaben](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/structured-outputs)
und [OpenRouter zu Reasoning-Tokens](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
wurden geprüft. Feste Listen werden strukturell begrenzt und nach dem Empfang in
das unveränderte Anwendungsschema zurückgeführt. Echte künstliche Aufrufe,
gemessene Kosten und verbleibende Grenzen stehen in
[PACKAGE_OUTPUT_TRANSPORT.md](PACKAGE_OUTPUT_TRANSPORT.md).

## 29.10.2026 · Sol-Route für den Alltagstest

[OpenRouter: Sol-Endpunkte](https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints) meldete die alte Azure-Route als gestört und Azure/EU als verfügbar; Katalogstatus ist kein Erfolgsnachweis. Die authentifizierte ZDR-Liste und drei getrennte künstliche Echtaufrufe wurden zusätzlich geprüft. Modell und Schutzgrenzen blieben erhalten, EU-Tokenpreise liegen um 10 % höher. [Prüfung und Einschränkungen](EVERYDAY_QA_2026_10_29.md).

## 28.10.2026 · Terra als Routenkandidat

[OpenRouter: Terra](https://openrouter.ai/openai/gpt-6.1-terra) und der
[Endpunktkatalog](https://openrouter.ai/api/v1/models/openai/gpt-6.1-terra/endpoints)
weisen `azure/eu` aus. Der authentifizierte ZDR-Katalog führte den Endpunkt;
das ersetzt keine separate Produktionsfreigabe. Zwei künstliche Aufgabenproben
und zwei Fotoproben gelangen. Zehn weitere größere Bildproben wurden zunächst
vor Versand durch die bestehende Kostenprüfung gestoppt und anschließend mit
höherer Reservierung verarbeitet; ihre dokumentierten Textanker wurden gefunden.
[Prüfergebnis und Grenzen](TERRA_EVALUATION_2026_10_28.md).

## 28.10.2026 · Auslieferung152 und tatsächlicher Sol-Ausfall

Ausgeliefert und öffentlich bytegeprüft: `20261028T144255Z-6bf8784`, Quellstand `6bf87846fdc174104dda321556d44a35aca95c50`, Schema0042.210SQLite-/210PostgreSQL- und43Flutterfälle bestanden. Der Gesamt-CI-Lauf40697583737 fand einen veralteten künstlichen Inline-Grafiktest; dessen Anpassung besteht danach in allen32Fällen mit RAM-SQLite und Unix-PostgreSQL und ändert keinen ausgelieferten Laufzeitcode.

Ein einzelner auditierter realer Reparaturaufruf mit neuer Grafiktransportversion wurde normal mit0,25USD reserviert und scheiterte erneut mit Anbieterfehler502. Ursprünglicher Fehler und unbekannte Kosten bleiben erhalten. Keine neue Grafik, Runde, Antwort oder sichtbare Firebase-Zustellung als erfolgreich behauptet.

- [Offizieller Modell-Endpunktkatalog](https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints): für `azure` Status−5/0% und für `azure/eu` Status0/100% in den gelesenen Zeitfenstern, geprüft28.10.2026.
- [ZDR-Katalogdokumentation](https://openrouter.ai/docs/api/api-reference/endpoints/list-endpoints-zdr): authentifizierter GET bestätigte Azure/EU für dasselbe Modell; reine OpenAI-Route nicht unter den gelesenen passenden ZDR-Einträgen. Kein genereller Datenschutzvergleich daraus abgeleitet.
- Beobachtete Sol-Tokenpreise Azure2/10USD pro Million Eingabe/Ausgabe, Azure/EU2,2/11USD. Bisherige maximale Reservierung0,25USD und8000Ausgabetokens unverändert. Kein freigegebener automatischer Fallback.

Die Betreiberentscheidung für einen geprüften Sol-Wechsel und höchstens1USD zusätzliche Tests/eine weitere reale Vorbereitung ist angefragt und noch offen. [Details und Rückweg](GRAPHIC_TRANSPORT_RELIABILITY.md).

## 28.10.2026 · Grafiktransport und fehlgeschlagene Lernrunden (152)

Die konkrete private Diagnose wurde ausschließlich auf den beauftragten Haushalt und Fehlerauftrag begrenzt und auditierbar gelesen. Kein Foto, Prompt, Rohfehler oder Antwortinhalt wurde in Git übernommen. Lokale Rekonstruktion mit gesperrtem Anbietertransport: ursprüngliche Struktur13, neue Struktur9 JSON-Container. Die genaue ursprüngliche Anbieterbegründung ist wegen der historischen neutralen Fehlerhülle und eines nachträglichen404 nicht beweisbar; unbekannte Kosten bleiben reserviert.

- [Umsetzung, Befund und Grenzen](GRAPHIC_TRANSPORT_RELIABILITY.md)
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs): Grenze der Verschachtelung und native Schemas, gelesen28.10.2026.
- [OpenRouter Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs): Endpunktunterstützung, strenger Vertrag und Fehlerbehandlung, gelesen28.10.2026.

Quellen-/Fach-/Antwortprüfungen, Providerroute und Budgets bleiben erhalten. Die gezielte Reparatur eines konkreten Fehlerauftrags bleibt eine einzelne bewusste und regulär reservierte Handlung. Technische und produktive Abnahmebelege werden nach Auslieferung ergänzt.

Interaktiver Ausbau23.10.2026 · veröffentlicht als1.26.0+97:
Die öffentliche und ausdrücklich bereitgestellte angemeldete simpleclub-App
wurde im Browser auf Desktop und bei390×844px untersucht. Anfangs waren
Übungen gesperrt; nach der mitgeteilten Unlimited-Plus-Freischaltung wurden
sie erneut geöffnet. Neun im Profil sichtbare Fachkataloge, tatsächliche
Aufgaben aus Mathematik, Physik, Biologie, Chemie, Englisch, Informatik,
Wirtschaft und Politik/GK sowie Deutsch-Text-/Videoübersichten wurden betrachtet.
Mathematik drei und Englisch vier Aufgaben bis zur Rückmeldung bedient;
Biologie-Tippzuordnung, Chemie-Dropdown und gestartetes Physikpendel tatsächlich
beobachtet. Nicht alle Aufgaben aller Kataloge wurden vollständig geprüft.
Die36öffentlichen Fach-/Berufskataloge mit372erfassten Verweisen sind ebenfalls
keine372abgenommenen Übungen. Genaue URLs, Bedienumfang und Grenzen:
[INTERACTIVE_LEARNING_2026_10_23.md](INTERACTIVE_LEARNING_2026_10_23.md).

Die [öffentlichen Businessdemos](https://business.simpleclub.com/fur-bildungsanbieter)
zeigten beim Bedienen einen Lötprozess-Schrittwechsel und eine räumliche
Würfelebene. „rive“-Namen dort belegen keinen vollständigen App-Animationsstack.
Der [historische offizielle Produktionsbericht](https://b2b.simpleclub.com/blog/so-erstellen-wir-unsere-hochwertigen-lerninhalte-2)
beschreibt Autoren-/Designarbeit und Gegenprüfung, keine aktuelle beliebige
vollautomatische Animationserzeugung.

Offizielle technische Primärquellen:
[design_tokens_builder](https://github.com/simpleclub/design_tokens_builder),
[math_keyboard](https://github.com/simpleclub/math_keyboard),
[flutter_math](https://github.com/simpleclub/flutter_math),
[tex_to_speech_flutter](https://github.com/simpleclub/tex_to_speech_flutter).
Sie zeigen Flutter-Werkzeuge für Styles, Mathematikeingabe/-darstellung und
Sprachausgabe, keine verifizierten heutigen Produktionsschriftgrößen.
Der [Rive-Bericht über Brilliant](https://rive.app/blog/how-brilliant-org-motivates-learners-with-rive-animations)
ist ein Vergleichsbeispiel, kein Simpleclub-Nachweis. Visuelle Messungen der
Canvasoberfläche sind Schätzwerte; Schulpilots20px-Frage,17px-Absatz,
16px-Antwort und700px-Rahmen sind eigene Gestaltungsentscheidungen.
Keine fremden Assets, Lerntexte, Animationen oder Zugangsdaten übernommen.

Eigene Umsetzung: quellgebundene individuelle SceneV1-Kompositionen, lokaler
Player, Drag-and-drop mit Tipp-/Tastaturalternative und explizitem Prüfen.
Bereits geöffnete Funktions-, Messdaten- und Logikhilfen bieten lokale,
begrenzte Explorer. Quellen-/Offenlegungs-, Konten- und Budgetgrenzen bleiben
maßgeblich; keine weiteren Dienstinstanzen oder Bilddienste. Technische Bezüge:
[Flutter Draggable](https://api.flutter.dev/flutter/widgets/Draggable-class.html),
[DragTarget](https://api.flutter.dev/flutter/widgets/DragTarget-class.html),
[AnimationBehavior](https://api.flutter.dev/flutter/animation/AnimationBehavior.html),
[W3C Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html).

Die einmalige echte synthetische Modellprobe wurde wegen ungültiger Struktur
verworfen, normal mit0,001436USD abgerechnet; kein Retry und kein erfolgreicher
echter KI-Szenennachweis. Künstliche Rendererfixtures sind keine Modell-, OCR-,
Handschrift- oder Lernwirkungsabnahme. Finale Prüf-/Build-/Betriebsnachweise:
[RELEASE_97_2026_10_23.md](RELEASE_97_2026_10_23.md).

Gestaltungsfortsetzung 23.10.2026, veröffentlichte Version 1.25.0+96: tatsächliche
visuelle Primärreferenz war die auf Nutzerauftrag angemeldete
[simpleclub-Webapp](https://app.simpleclub.com/search), direkt bedient bei
1440×1000 px und 390×844 px. Angesehen wurden die Themenübersicht „Brüche“,
der Planerstellungsassistent, die Vorlagenvorschau „Mathe Abitur NRW“ und die
ersten zugänglichen Seiten von „Berechnung von Bruchteilen“ einschließlich
einer endlichen Torten-/Bruchdarstellung. „Brüche verstehen“ zeigte eine
Unlimited-Bezahlschranke; kein Kauf, keine Umgehung und kein Zugriff auf die
gesperrten Aufgaben. Daraus folgt ausdrücklich keine Abnahme bezahlter Übungen
oder der gesamten Lektion.

Übernommen werden Gestaltungsprinzipien: ruhige dunkle Flächen, Nunito,
kompakte beschriftete Lernplanzeilen, farbige Fachmarken, dünne Piktogramme,
segmentartige Fortschrittsführung und eine feste blaue Pillen-Hauptaktion.
Implementierungsquellen sind die eigene bestehende Flutter-App, eigene
Canvas-Icons in `schulpilot_icons.dart`, lokale Fachsymbole, die neuen
`PlanSectionTitle`/`PlanPill`/`PlanSubjectMark`/`PlanDateMark`/`PlanDayCard`/
`PlanRow`-Bausteine und der gemeinsame `LearningGraphicFrame`. Die Browserrail
ist ab 1050 px bei normaler Schrift 224 px breit und beschriftet, darunter ab 720 px
80 px; große Schrift verwendet die kompakte Variante. Keine simpleclub-Assets,
Lerntexte, Markenbestandteile oder Kontozugänge wurden in Schulpilot eingebaut.
Keine neuen Pakete, externen Schrift-/Bildabrufe oder Inhaltsanbieter.

Vorhandene Aufrufer behalten Callbacks, Daten, Rollen- und Kontoprüfungen,
Quellenbindung, Antwort-/Versuchsbewertung, aktive Zeit und explizite KI-Aktionen.
Fachgrafiken behalten ihre endlichen geprüften Modelle und Offenlegungsstufen;
die responsive Rahmung und lokale Zoomansicht erzeugen keine Lernbelege.
Tatsächlicher Prüfstand: 717 Flutterfälle in 26 Dateien bestanden; statische Analyse
aller 20 geänderten Dartdateien ohne Befund. Eigene Browserprobe bei1440×1000
und390×844: Planmodal, Aufgabenraum, Antwortkarten und Grafikzoom mit
künstlichen Beispielen; alle schreibenden Requests gesperrt. Build-/Deploybelege
stehen in [RELEASE_96_2026_10_23.md](RELEASE_96_2026_10_23.md). Kein bezahlter
Inhalts- oder umfassender WCAG-Nachweis. Gestaltungsregeln:
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md); fachliche Grenzen:
[SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md).

Schulbuddy23.10.2026: ausdrücklich bereitgestellter mobiler Screenshot und
bestehende gemeinsame Flutter-Implementierung. Beide allgemeinen Hinweise
nach Gesprächsstart kompakt, Abruf über Info-Symbol; echte Sperr-/Fehlerhinweise
erhalten.47Flutterfälle, lokale künstliche Browserprobe, gebundener1.24.1+95-
Build und tatsächlicher SSH-/Hashnachweis: RELEASE_95_2026_10_23.md.

Deployment23.10.2026: vorhandene fixierte Flutter-/Android-Toolchain und
projektspezifische SSH-Deployskripte tatsächlich ausgeführt. Regulärer gebundener
Build1.24.0+94, Paket-/Signatur-/Quellprüfung und öffentlicher Bytevergleich.
Serverzustand, Schema0031, Sicherungen und Produktionsbrowser direkt geprüft;
keine neuen Pakete oder Dienste. Belege: RELEASE_94_2026_10_23.md.

Gestaltung22.10.2026: visuelle Primärreferenz auf ausdrücklichen Nutzerauftrag
direkt im angemeldeten Browser geprüft: https://app.simpleclub.com/search,
Home, Fach Mathematik, Bibliothek und Bruch-Lektionsansicht. Desktop sowie
390×844 px: dunkle Arbeitsfläche, abgesetzte Karten, schmale Iconleiste bzw.
schwebende Bottomnavigation, Reiterunterlinien, farbige Fachsymbole. Umsetzung
in der vorhandenen Flutter3.47.7/Dart3.13.5-App mit lokalem Nunito, eigenen
Canvas-Navigationsicons und eigenen Fachbadges. Keine neuen Pakete oder
externen Font-/Bildabrufe; keine Übernahme von Kontozugängen oder Lernmedien.
Umfang und lokale Abnahme: SIMPLECLUB_STYLE_2026_10_22.md und STATUS.md.

Commerce93, 22.10.2026: neue ausdrücklich beauftragte PayPal-/Google-Pay-Webintegration
auf unveränderlichen vorausbezahlten Bestellungen. Tatsächlich gelesene Primärquellen:
[PayPal SDKv6](https://developer.paypal.com/checkout/integrate/),
[Google Pay mit SDKv6](https://developer.paypal.com/google-pay/integrate/),
[Orders Create](https://developer.paypal.com/api/orders/v2/orders-create),
[Orders Capture](https://developer.paypal.com/api/orders/v2/orders-capture),
[Webhooksignaturprüfung](https://developer.paypal.com/api/webhooks/v1/verify-webhook-signature-post/),
[Ereignisse](https://developer.paypal.com/api/rest/webhooks/event-names/),
[Payments-v2-Schema](https://developer.paypal.com/api/payments/v2/schema.json),
[Refunds](https://developer.paypal.com/checkout/refund-payment),
[Google-Pay-Freigabe](https://developers.google.com/pay/api/web/guides/test-and-deploy/publish-your-integration)
und [Google-Pay-FAQ](https://developers.google.com/pay/api/faq).
Gesamtpreis-/Vertragsdaten und ausdrückliche Bestellbestätigung anhand
[§312j BGB](https://www.gesetze-im-internet.de/bgb/__312j.html),
[§3 PAngV](https://www.gesetze-im-internet.de/pangv_2022/__3.html),
[Art.246a §1 EGBGB](https://www.gesetze-im-internet.de/bgbeg/art_246a__1.html)
und [§356a BGB](https://www.gesetze-im-internet.de/bgb/__356a.html).
[W3C PaymentRequest und Permissions Policy](https://www.w3.org/TR/payment-request/#permissions-policy)
und [Googles iframe-Anforderung](https://developers.google.com/pay/api/web/guides/tutorial?hl=en)
belegen den erlaubten Top-Level-Kontext und erforderliche Delegation bei Einbettung.
Keine Händlerfreigabe, echte Zahlung oder juristische Abnahme behauptet.
Konkrete Grenzen, Backendvertrag und isolierte Nachweise: [PAYMENTS.md](PAYMENTS.md).

Arbeitsstand22.10.2026 · Releasekandidat1.22.0+90: dritte zusätzliche Bedienrunde
mit300 unabhängig gezählten Maßnahmen gegenüber den vorherigen638.
Tatsächlich recherchierte Primärquellen: [W3C, klare Seitenstruktur](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o2p03-page-structure/),
[GOV.UK, Fehlersammlung](https://design-system.service.gov.uk/components/error-summary/),
[W3C, redundante Eingaben](https://www.w3.org/WAI/WCAG22/Understanding/redundant-entry.html),
[W3C, Fehlervermeidung](https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html),
[GOV.UK, Antworten vor Bestätigung prüfen](https://design-system.service.gov.uk/patterns/check-answers/),
[Flutter PopScope](https://api.flutter.dev/flutter/widgets/PopScope-class.html) und
[RFC5545](https://www.rfc-editor.org/rfc/rfc5545) für den ausdrücklich gespeicherten Kalenderexport.
Code-/Testreferenzen und konservative Entdoppelung stehen in
[UX_300_ROUND3_INDEX_2026_10_22.json](UX_300_ROUND3_INDEX_2026_10_22.json)
und den vier dort benannten Bereichsmatrizen. Dies ist keine vollständige
WCAG-/Screenreader- oder pädagogische Wirksamkeitsabnahme.

Schulbuddy: am22.10.2026 auf ausdrücklichen Auftrag die angemeldete
[Sofatutor-Lernseite](https://www.sofatutor.com/mathematik/videos/brueche-erweitern-und-kuerzen-3)
im Browser angesehen und den kontextbezogenen Vorwissenseinstieg mit einer
öffentlichen Fachfrage ausprobiert. Daraus stammen die Bedienbeobachtungen
Panel, drei Einstiegsfragen und eine Rückfrage; bestehende eigene Roboterassets
bleiben die Schulpilotdarstellung. Tatsächlicher eigener isolierter CLI0.162.1-
`model/list` meldet `gpt-6-luna/high` sowie `gpt-6.1-sol/max`. Metadaten sind noch
kein Inferenz- oder Reparaturnachweis. Konkrete Freigabe-/Testgrenzen:
[SCHULBUDDY.md](SCHULBUDDY.md).

Für den getrennten Reparaturauftrag mit Skill OpenAI Docs tatsächlich gesucht
und vollständig abgerufen:
[offizielle OpenAI-Dokumentation zu Codex im nicht interaktiven Betrieb](https://learn.chatgpt.com/docs/non-interactive-mode).
Grundlage für getrennten Credentialbroker, begrenzten Codearbeitsbereich und
prüfbares Patchartefakt. Tatsächlich installierte CLI-Hilfe entscheidet über
verwendbare Flags; keine ungeprüfte Übernahme neuerer Dokumentationsoptionen.
Der Lernworker behält seine bisherigen Rechte und Grenzen.
Für den belegten fehlenden Bubblewrap-Pfad der installierten CLI zusätzlich
die [offizielle Anleitung zur äußeren Containerisolation](https://learn.chatgpt.com/docs/agent-approvals-security#os-level-sandbox)
geprüft. Der Reparaturcontainer verwendet einen festen CLI-Modus innerhalb
seiner schreibgeschützten, netzlosen äußeren Grenze; harte Runtimeguards und
die tatsächlich ausgeführte lokale Shellprobe prüfen diese Grenze vor einem
Modellaufruf. Kein automatischer Sandboxwechsel oder Modellretry.

Weitere Bedienprüfung 22.10.2026, Version 1.19.7+86: bestehende Flutter-
Sammlungen, Eltern-Lerndetails und Kontodialoge. Recherche zu
[redundanter Eingabe und verständlicher Authentifizierung](https://www.w3.org/WAI/WCAG22/Understanding/accessible-authentication-minimum.html),
[Formularvalidierung](https://design-system.service.gov.uk/patterns/validation/),
[Formularrückmeldungen](https://www.w3.org/WAI/tutorials/forms/notifications/),
[Orientierung](https://www.w3.org/WAI/WCAG2/supplemental/objectives/o2-find/)
und [Statusmeldungen](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html).
Keine neuen Pakete, Dienste, KI-Aufträge oder Berechtigungen.
Konkrete Entscheidungen und Abnahme in [UX_REVIEW_86_2026_10_22.md](UX_REVIEW_86_2026_10_22.md).

Bedienprüfung22.10.2026, Version1.19.6+85: bestehende gemeinsame Flutter-
Arbeitsräume und Rollenrechte. Recherche zu
[klaren Controls](https://www.w3.org/WAI/WCAG2/supplemental/objectives/o1-understandable/),
[Statusmeldungen](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html)
und [verständlichen Feldfehlern](https://design-system.service.gov.uk/components/error-message/).
Keine neuen Pakete, Dienste oder KI-Aufträge. Entscheidungen, konkrete
Codepfade und Nachweisgrenzen in [UX_REVIEW_2026_10_22.md](UX_REVIEW_2026_10_22.md).

Firebaseprüfung 22.10.2026, Version 1.19.5+84: bestehende Firebase-Konsole unter dem beauftragten
Google-Konto, feste Projekt-/App-IDs über Firebase Management und Service Usage,
minimale Senderrolle über IAM und redigierte Serverbetriebsmetadaten unabhängig
abgeglichen. [API-Key-Einschränkungen](https://firebase.google.com/docs/projects/api-keys)
und [Tokenverwaltung](https://firebase.google.com/docs/cloud-messaging/manage-tokens).
Tatsächlich fixierte Quellen: `firebase_messaging 16.7.0`,
`FlutterFirebaseMessagingReceiver.java` (`goAsync`/`PendingResult.finish`) sowie
`firebase_messaging_web 4.2.5`, `firebase_messaging_web.dart` (leerer
`onTokenRefresh`-Stream). [Android-Broadcast-Lebensdauer](https://developer.android.com/reference/android/content/BroadcastReceiver#goAsync())
und [Webpermission](https://developer.mozilla.org/en-US/docs/Web/API/Notification/requestPermission_static).
Keine SDK-Aktualisierung, neue Cloudressource oder neue Anmeldedaten.
Nachweisgrenzen und Ablauf in [FIREBASE_EVALUATION_2026_10_22.md](FIREBASE_EVALUATION_2026_10_22.md).

Livehilfe22.10.2026, Version1.19.4+83: eigene gemeinsame Flutter-Oberfläche,
vorhandener kontogebundener WebRTC-Service und feste Gestaltungspalette.
Aufgabenbegleitende Liveleiste ersetzt den automatischen Wechsel auf eine
Gesprächsseite; keine neuen Pakete, Dienste, Provider oder Berechtigungen.
Darstellung und Grenzen in [FAMILY_CALLS.md](FAMILY_CALLS.md), tatsächliche
Abnahme und Bereitstellung in STATUS.md. Lokale Vorschau ausdrücklich synthetisch.

Nachmittagsbereinigung21.10.2026: nach ausdrücklicher Betreiberfreigabe genau
den künstlichen Testhaushalt mit dem vorhandenen authentifizierten DELETE /account
entfernt. Umfang vorab begrenzt, globale Kostenstände erhalten, zwei signierte
Löschjournalbelege geprüft, lokale Testzugangsdaten entfernt. Keine neuen Pakete,
Anbieteraufrufe oder Codebereitstellung; Details im Nachmittagsbericht.

Live-Abschlussprüfung21.10.2026, Version1.18.3+77: gespeicherte, quellengebundene
Zurückstellung nach einer ausdrücklich gezeigten Lösung und Wechsel auf eine
andere Prüfaufgabe. Originalantworten bleiben unverändert als Übungsbedarf.
Bestehende erschöpfte KI-Kurzpläne werden lokal anhand ihrer gespeicherten
Aktionsbelege wiederaufgenommen; kein GET startet KI oder schließt die Runde.
Verbrauchte Planfreigaben werden vor einem bewussten POST erneut geprüft.
Keine neuen Pakete, Providerfreigaben, Kontingente oder Datenbankmigrationen.
Tatsächlicher künstlicher Browserdurchlauf in AFTERNOON_EVALUATION_2026_10_21.md.

Live-Nachprüfung21.10.2026, Version1.18.2+76: bewusst erneut abgegebene gleiche
falsche Antwort nach quittiertem Feedback muss einen eigenen Versuch erhalten.
Transportwiederholungen behalten ihre Idempotenz; weder Antworten noch Hilfen
werden umgewertet. Regression und echter Browserreplay im künstlichen Haushalt
in AFTERNOON_EVALUATION_2026_10_21.md. Keine Provider-/Kostenänderung.

Live-Nachprüfung21.10.2026, Version1.18.1+75: konkreter künstlicher OpenRouter-
Durchlauf deckte ein zu weit gehendes Additionsbeispiel in einer Erweiterungsprobe
auf. Geplanter separater Erweiterungsbeleg und fokusgebundene endliche Introprüfung
begrenzen die nächste Erzeugung; bestehende Runden/Antworten bleiben erhalten.
Keine neuen Pakete, Dienste, Modellrouten oder Kontingente. Tatsächliche Ergebnisse
in AFTERNOON_EVALUATION_2026_10_21.md und STATUS.md.

Künstlicher Nachmittag21.10.2026, Version1.18.0+74: eigene Hausaufgaben-/
Lernrunden-/Jobwege. Ein bewusster Anschluss aus genau einer bestätigten Fotoquelle
verwendet normale Reservierung und gespeicherte Vorbereitung. Endliche Prüfungen
bekannter Originalfragen/Zahlenterme vor Speicherung; keine allgemeine semantische
Äquivalenzgarantie. Regelbasierter Bruchcheck erklärt Ergebnisabweichung ohne
Originalergebnis. Keine neuen Pakete, Dienste oder Providerfreigaben; Liveprobe
und tatsächliche Kosten in STATUS.md. Elternstrategie parent-review-3 erhält nur
beantwortete, gespeicherte Zielaggregate; unbekannte Teilziele bleiben offen.
Exakte Zeitstempelgleichstände im Übungsledger verwenden die vorhandene
Versuchsnummer als nachgeordneten Sortierschlüssel, keine Antwortkorrektur.

Erneute Eltern-/Kinderprüfung21.10.2026, Version1.17.3+73: eigene bestehende
Quellen-, Lernplan-, Tutor- und Gerätezustände; keine neuen Pakete, Dienste,
Modellprompts oder erhöhten Kontingente. Revisionsgebundene Hausaufgaben-Caches
und serialisierte Entwürfe, direkte Themenabschlüsse mit optionaler Revision,
ungekürzte Suche offener Runden vor begrenzter Vorschau. Historische Übung ohne
Quellenrevision bleibt sichtbar, ist kein aktueller Kompetenznachweis.
Android-Fotowiederherstellung verwendet den bestehenden image_picker und einen
kontogebundenen Zweckmarker; eine bewusste Zuschnittprüfung bleibt erforderlich.
Tatsächliche Prüfungen und Bereitstellung in STATUS.md.
Migration0025 verwendet für SQLite eine neue nullbare Spalte mit Inline-Referenz
nach dem bestehenden Muster aus0007; befüllte Auftrags-/Rundenzuordnungen bleiben
ohne Tabellenkopie erhalten. Beide Dialekte mit Hin-/Rückweg geprüft.

Eltern-Lernkompass21.10.2026, Version1.17.2+72: eigene bestehende
Attempt-/Activity-Auswertung, reservierte Jobs und begrenzter OpenRouter-
Entscheidungsauftrag. Kein zusätzlicher Anbieter, neues Paket oder Microservice.
Additive Migration0025; gemeinsame Flutter-Navigation, Themenplanung und
Eltern-Hausaufgabenansicht. Fachliche Abgrenzung und Schnittstellen in
[PARENT_LEARNING.md](PARENT_LEARNING.md); tatsächliche Freigabe in STATUS.md.
Keine aus Bildschirmlaufzeit abgeleitete KI-Kompetenz oder Wirksamkeitsbehauptung.
Die echte künstliche Aufgabenprobe deckte zusätzlich einen fehlenden lokalen
Prüffall für vollständige einfache Rechenterme auf. `subject_rules_v5` rechnet
zwei ausdrücklich gegebene Zahlen exakt rational nach, prüft die Musterlösung
und bewahrt unbekannte Sach-/Rundungs-/Darstellungsfragen als unklar. Keine
beliebige Ausdrucksausführung und keine automatische Umschreibung alter Antworten.
149 betroffene Backendtests einschließlich expliziter revisionsgebundener
Nachprüfung bestanden; tatsächliche Produktionsnachweise in STATUS.md.
Version72 erhält zudem einen ausdrücklich ausgewählten alten Bericht in der
Auswahlliste, auch wenn inzwischen mehr als zwölf neuere Auswertungen vorliegen.
19 abschließende Elternfälle bestanden; keine weitere KI dafür erforderlich.

Hausaufgabenwerkstatt21.10.2026, Version1.16.2+69: eigener Fotobereich,
quellengeprüfte Aufgabenübersicht, gestufte Lernhilfen und lokale Rechenprüfung.
Bestehender Foto-/Tutor-/Reservierungsweg, keine zusätzlichen Laufzeitpakete oder
Dienste. Pädagogische Ableitung und Grenzen in [HOMEWORK.md](HOMEWORK.md).
Primärquellen am21.10.2026 gelesen:
[EEF Metacognition and Self-Regulated Learning](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition),
[IES/WWC Organizing Instruction and Study to Improve Student Learning](https://ies.ed.gov/ncee/wwc/PracticeGuide/1).
Fünf eigene mit image_gen erzeugte künstliche Fotos, visuell geprüft, Hashes in
`testdata/homework_images_v1.json`, Originale und exakte Prompts unter
`artifacts/homework-20261021/`. Keine echten Schulbuchseiten oder Kinderfotos.

Flächenbewertung21.10.2026, Version1.15.1+66: eigene konservative, exakt mit
`Fraction` geprüfte Rechteckregel und einheitliche Behandlung bereits vorgegebener
Flächeneinheiten. Künstliche Testwerte; keine neuen Pakete, Provideraufrufe oder
angehobenen Kontingente. Regelversion `subject_rules_v4`, Umfang und Grenzen in
[AREA_ASSESSMENT_2026_10_21.md](AREA_ASSESSMENT_2026_10_21.md).

Lernsteuerung und gemeinsamer Arbeitsraum20.10.2026, bereitgestellt1.15.0+65
(20261020T184923Z-872d505, Produktcommit872d505375894ffd4e1c173af5a1d6513aff0e75):

Eigene vorhandene Attempt-/Activity-/Quellen-/Jobmodelle und gepinnte Flutter-
Darstellung. Keine neuen Dart-/Python-Pakete, Lernanbieter, Microservices oder höheren
Kontingente. Zwei Erscheinungsbilder mit lokal gebündelten Schriften und einer
aus künstlicher Beschreibung erzeugten öffentlichen Einstiegsillustration.
Kein externer Fontabruf oder neuer Bilddienst in der Anwendung.
Fachliche Regeln und Grenzen, Schnittstellen und Testspuren:
[LEARNING_CONTROLLER_2026_10_20.md](LEARNING_CONTROLLER_2026_10_20.md),
[PARENT_WORKSPACE_2026_10_20.md](PARENT_WORKSPACE_2026_10_20.md),
[ADMIN_WORKSPACE_2026_10_20.md](ADMIN_WORKSPACE_2026_10_20.md).


Schriftquellen, lokal gebündelt, OFL1.1, am20.10.2026 geprüft:
- [Nunito](https://github.com/googlefonts/nunito/tree/8c6a9bb9732545b9ed53f29ec5e1ab0ff53c4e6f),
  `Nunito[wght].ttf`, SHA256 `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`.
- [Space Grotesk](https://github.com/floriankarsten/space-grotesk/tree/03507d024a01282884232081fc6011c09ff4e849),
  `SpaceGrotesk[wght].ttf`, SHA256 `acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72`.
- Eigene synthetische Cyber-Buchdrohne über das eingebaute Bildwerkzeug;
  Prompt, Asset und Hash in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).
- Produktdokumentation von Duolingo, Khan Academy Kids, ANTON, Google Classroom,
  Todoist, Linear und Brilliant: konkrete Primärlinks, Übertragungsentscheidung
  und Grenzen in den drei Workspace-Dokumenten. Keine behauptete Studie zur
  Lernwirkung oder vollständige native Fremdproduktprüfung.

Direkt geprüfte angemeldete OpenRouter-Kontoseiten20.10.2026:
[Datenschutz](https://openrouter.ai/settings/privacy),
[Workspace-Observability](https://openrouter.ai/workspaces/default/observability).
Betreiber beauftragte Einsicht und Änderung; tatsächliche Schalter/Prüfgrenzen
in [OPENROUTER_ACTIVATION_2026_10_20.md](OPENROUTER_ACTIVATION_2026_10_20.md).
Ein zusätzlicher künstlicher normal reservierter Planungsauftrag erfolgreich,
erfasste Anbieter-Kosten0,000514USD; gesamte bisherige künstliche Abnahme
0,238013USD innerhalb0,25USD. Kein Test mit echten Kinderinhalten.

Kinder-Funktionsprüfung20.10.2026, Zielversion1.14.4+64:

Eigene bestehende Quellen-/Runden-/Nachrichtenmodelle, gepinnte Flutter-
TransformationController/InteractiveViewer und vorhandene Gerätesprachgrenze.
Keine zusätzlichen Pakete, Dienste, Modelle, Preise oder höheren Kontingente.
Prüfumfang, Fehler und Grenzen: [CHILD_AUDIT_2026_10_20.md](CHILD_AUDIT_2026_10_20.md).

Elternübersicht und Quellenlöschung20.10.2026, bereitgestellt1.14.2+62:

Eigene vorhandene serverseitige Lernstandsprojektion (`learning_progress.py`),
kompakter Überblick und gemeinsame Flutter-Palette. Keine SDK-, Anbieter-,
Preis- oder Kontingentänderung. Darstellung/Prüfung und Abnahme:
[PARENT_OVERVIEW_2026_10_20.md](PARENT_OVERVIEW_2026_10_20.md),
[SOURCE_DELETION_2026_10_20.md](SOURCE_DELETION_2026_10_20.md).

Menü- und Leseflussprüfung20.10.2026, bereitgestellt1.13.0+59:

Keine SDK-, Anbieter- oder Preisänderung. Die vorhandene gemeinsame Flutter-
Oberfläche und dieselbe gepinnte Formelengine werden weiterverwendet. Neu sind
lokale Zustands-/Lesekorrekturen, ein berechtigter Nachrichtenweg und gebündelte
Prüfungen verlinkter Quellen. Änderungen und tatsächliche Abnahme stehen in
[MENU_REVIEW_2026_10_20.md](MENU_REVIEW_2026_10_20.md). Anbieterrevision und Grenzen
der vorherigen Abnahme bleiben unverändert.

Fachliche Darstellung, geprüft20.10.2026, bereitgestellt1.12.2+58:

- [flutter_math_fork0.7.4](https://pub.dev/packages/flutter_math_fork/versions/0.7.4),
  [lokale Math-API](https://pub.dev/documentation/flutter_math_fork/0.7.4/flutter_math/Math-class.html):
  nativer Flutter/Dart-Formelsatz, Apache-2.0 laut installiertem Paket. Exakter
  Pub-Archivhash6d5f2f1aa57ae539ffb0a04bb39d2da67af74601d685a161aff7ce5bda5fa407;
  Paket/Lockfile/Toolchain gepinnt. KaTeX-Schriften mitgeliefert, keine CDN-Fonts.
- [KMK Bildungsstandards](https://www.kmk.org/bildungsministerkonferenz/bildungsthemen/bildungsstandards.html):
  Orientierung für Bereiche Primar/SekI/Abitur; keine aus dem Index abgeleitete
  einheitliche Klassenverteilung. Geöffnete Primärdokumente: MathematikAHR2012,
  Biologie/Chemie/PhysikAHR2020. Prüfraster, Implementierungsumfang und Grenzen in
  [SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md).
- Eigene endliche Vektor-/Canvas-Zeichnungen aus überprüften Parametern und
  Beziehungen. Keine fremden Schulbuchabbildungen oder privaten Heftinhalte in
  den neuen Repositoryfixtures. Bisherige Modelle/Preise/Providerlimits erhalten.

Produktive Nachweise, abschließende Tests und Grenzen:
[SCIENTIFIC_QA_2026_10_20.md](SCIENTIFIC_QA_2026_10_20.md).

# Offizielle Quellen und geprüfte Versionen

Abnahme20.10.2026, Version1.11.5+55: keine Toolchain-/SDK-Änderung; Details und
beobachtete Grenzen in [APP_AUDIT_2026_10_20.md](APP_AUDIT_2026_10_20.md).

- [OpenRouter Fehler und Diagnose](https://openrouter.ai/docs/api_reference/errors-and-debugging):
  HTTP-Fehler von Fehlern nach Annahme unterscheiden; bekannte Kostenmetadaten
  erhalten, unbekannte Kosten nicht als0abrechnen. Nur feste sichere Kategorien
  speichern, keine Anbieter-Raw-Bodies oder privaten Echos.
- [OpenRouter strukturierte Ausgabe](https://openrouter.ai/docs/guides/features/structured-outputs):
  strikte Schemas und gebundene Endpunktunterstützung. Der konkrete Azure-400er
  für Anführungszeichen im Quellen-Enum ist eine direkt beobachtete Anbieterantwort
  dieser künstlichen Abnahme, keine allgemein behauptete JSON-Schema-Regel.
  Belege durch nullbasierte Integerindizes gebunden, danach unverändert restauriert.
- [Luna-Endpunkte](https://openrouter.ai/api/v1/models/openai/gpt-6-luna/endpoints),
  [Sol-Endpunkte](https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints),
  [ZDR-Endpunkte](https://openrouter.ai/api/v1/endpoints/zdr):20.10.2026geprüfte
  Preis-/Anbieterbindung gemäß [Aktivierungsbeleg](OPENROUTER_ACTIVATION_2026_10_20.md).
  Keine erfundene kostenlose Abrechnung oder gemessene Lernwirksamkeit behauptet.

Lokale Wortschatzrunden5/10/15(Standard10) verwenden bestätigte Wörter ohne
Inferenz; serverseitige Regeln subject_rules_v3 erkennen zusätzlich den bekannten
Vorsatz Übung:/Übungsaufgabe:. Frühere Nachprüfungen versioniert erhalten.

Ausbau19.10.2026: OpenRouter-Routing, ZDR, Medium-Reasoning, Gebühren, Cache-Opt-out und Generation-Abgleich anhand der offiziellen Dokumentation geprüft. Konkrete Links, Endpunktpreise, Messwerte und Grenzen in [ADAPTIVE_OPENROUTER.md](ADAPTIVE_OPENROUTER.md). Keine SDK-/Paketaktualisierung; Flutter3.47.7/Dart3.13.5 und bestehende Backend-Abhängigkeiten bleiben fixiert. Schema0023 additiv.

Abschluss49: Das offizielle Google-bundletool1.18.3 wurde zusätzlich als externes
Prüfwerkzeug verwendet, ohne Buildabhängigkeiten zu ändern. Asset-Digest
`a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`
gegen die offizielle GitHub-Veröffentlichung geprüft; AAB49 mit `validate`,
Manifestdump und dem bestehenden Signierer geprüft. Das ist keine Play-Console-
Veröffentlichung oder Geräteabnahme. Tatsächlich bereitgestellte Quellversion,
Artefakt-Hashes, Rollensimulationen und Grenzen stehen in [STATUS.md](STATUS.md).

Praxistestkorrekturen, geprüft am 19.10.2026:

- [RHS: How plants absorb water](https://www.rhs.org.uk/advice/understanding-plants/how-plants-absorb-water):
  Wasseraufnahme an Wurzeln. [RHS Qualifikationslehrplan](https://www.rhs.org.uk/education-learning/pdf/qualifications/level-2/q-qao-qualification-specification-level-2-popg.pdf):
  Bestäubung und Befruchtung getrennt, Verschmelzung der Keimzellen. Eigene
  endliche Flutter-Vektorskizzen, keine fremden Bilder übernommen.
- Keine SDK-, Provider-, Audio- oder Datenbankmigration in Build44. Neue
  Metadaten/Capabilities sind additiv; bisherige Clients und Antworten bleiben
  erhalten. Prüfmatrix und Grenzen: [PRACTICE_REVIEW_2026_10_19.md](PRACTICE_REVIEW_2026_10_19.md).

PDF-Import, geprüft am 18.10.2026:

- [pypdf6.21.1 Textauszug](https://pypdf.readthedocs.io/en/6.21.1/user/extract-text.html),
  [Paketmetadaten](https://pypi.org/project/pypdf/6.21.1/): BSD-3-Clause,
  reine lokale Text-/Koordinatenextraktion, keine OCR. Koordinaten sind nicht
  für beliebige PDFs garantiert. Unser Import akzeptiert ausschließlich die
  vollständig erkannte Fuxnoten-Rasterstruktur und bricht bei Unklarheit ab.
  Verarbeitung in geheimnisfreiem Unterprozess mit Zeit-/Speicherlimit.
- [Offizielles Flutter file_selector1.1.0](https://pub.dev/packages/file_selector/versions/1.1.0),
  [openFile](https://pub.dev/documentation/file_selector/1.1.0/file_selector/openFile.html):
  bewusste Auswahl einer PDF über nativen Dateidialog beziehungsweise Browser;
  XTypeGroup mit PDF-MIME/Endung/UTI. Vorhandener image_picker bleibt für Fotos.
  Nur notwendige neue Paket-/Plattformabhängigkeiten, keine SDK-Migration.

## Bisherige Quellen

Sprachwerkstatt-Belegkorrektur, 18.10.2026: ausschließlich bestehende
JSON-Schema-/Workerpfade erweitert; keine Änderung der Provider-API,
SDK-Versionen, Modelle, Suchrechte oder Preis-/Zeitgrenzen. Die konkreten
Belege stammen aus den bereits bestätigten eigenen Wortpaaren. Künstliche
Adapterregressionen prüfen OpenAI Responses, OpenRouter und den isolierten
Codex-Worker getrennt; tatsächliche externe Abnahme und Grenzen stehen in
STATUS/Handoff. Anbieterantwort und serverseitige Freigabe bleiben getrennte
Prüfschritte; keine behauptete externe Validierung privater Kinderinhalte.

Oberflächengestaltung, zusätzlich geprüft am 18.10.2026:

- [W3C WCAG 2.2 – Textkontrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html):
  4,5:1 für normalen und 3:1 für großen Text; auch Hinweis-/Platzhaltertexte
  berücksichtigen. Grenzwerte nicht aufrunden.
- [W3C WCAG 2.2 – Nicht-Text-Kontrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html):
  notwendige Erkennungsmerkmale und Zustände mit 3:1. Dekorative Card-Rahmen
  nicht mit notwendigen Eingabefeldgrenzen gleichsetzen.
- [W3C – sichtbarer Fokus](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html):
  Tastaturfokus sichtbar halten. Implementierung, Flächenhierarchie und Grenzen
  der tatsächlichen Prüfung: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).
- APIs gegen den bereits fixierten Flutter-3.47.7-Quellstand geprüft:
  `button_style.dart`, `chip.dart`, `tab_bar_theme.dart`, `accessibility.dart`.
  ButtonStyle.side als Zustandswert auflösen; ChipTheme.side verwendet den
  dokumentierten WidgetStateBorderSide-Pfad. Keine SDK-/Paketmigration.

Sprachlernen, ergänzend geprüft am 17.10.2026:

- [flutter_tts 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5) und
  [API](https://pub.dev/documentation/flutter_tts/4.2.5/flutter_tts/FlutterTts-class.html):
  konkrete Sprachwahl, Stimmenliste, Verfügbarkeit, Tempo und Abbruch; vorhandene Version unverändert.
- [speech_to_text 7.5.0](https://pub.dev/packages/speech_to_text/versions/7.5.0) und
  [SpeechListenOptions](https://pub.dev/documentation/speech_to_text/7.5.0/speech_to_text/SpeechListenOptions-class.html):
  localeId gehört bei dieser fixierten Version in die Listenoptionen. Kein SDK-Update und keine Audio-API eingeführt.
- [EEF Cognitive Science Approaches](https://educationendowmentfoundation.org.uk/education-evidence/evidence-reviews/cognitive-science-approaches-in-the-classroom/):
  Abruf und verteilte Wiederholung als didaktische Muster. Unsere Intervalle sind eine Produktentscheidung, kein abgeleitetes Optimum.
- Babbel-/sofatutor-Beobachtungen stammen aus dem vom Auftraggeber bereitgestellten Prüfprotokoll.
  Keine eigene erneute praktische Prüfung von Babbel Speak und keine Übernahme fremder Kursinhalte.
- [Offizielle OpenAI-Dokumentation: Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs#supported-schemas):
  alle Objektfelder in required, keine zusätzlichen Felder und gültige anyOf-Zweige.
  Beim echten Sprachprojekttest entfernte unsere frühere Schemaaufbereitung ein
  echtes Feld `title` irrtümlich als Metadatum; Feldnamen und Schemaknoten werden
  jetzt getrennt durchlaufen. Keine Lockerung der serverseitigen Aufgabenprüfung.

Lernmodell, alle Übungen und schulische Schwerpunkte, erneut tatsächlich geprüft am 17.10.2026:

- [IES/WWC Practice Guide 1, 2007](https://ies.ed.gov/ncee/wwc/PracticeGuide/1): verteiltes Lernen, Abrufübungen und Wechsel zwischen gelöstem Beispiel und eigenem Problemlösen. Die Quelle stuft die Evidenz für diese einzelnen Empfehlungen unterschiedlich ein. Umsetzung und Grenzen: [LEARNING_MODEL.md](LEARNING_MODEL.md).
- [EEF Metacognition and Self-Regulated Learning, 2. Auflage vom 13.11.2025](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition): konkrete Strategien in fachbezogenem Unterricht, Modellieren, gestufte Hilfe und selbstständiges Anwenden. [EEF Teacher Feedback, 11.06.2021](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/feedback): nützliche Rückmeldung zum nächsten Schritt; schlechte Rückmeldung kann den Lernfortschritt auch beeinträchtigen. Keine Wirkung der konkreten SCHULPILOT-Implementierung daraus behaupten.
- [W3C – Feedback and status](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o4p10-status-feedback/): sichtbare Rückmeldung zu ausgeführten Schritten. Alle gespeicherten Übungen werden vorrangig gezeigt, langfristige Abrufbeobachtungen zusätzlich auf Anfrage. Keine Beherrschungsprozente und keine Notenprognosen.

Die Notengewichtung (höchstens fünf Einträge/90 Tage, Schwellen 0,4/0,6), Gewicht 1/2/3 und drei spätere Prüftage über sieben Tage sind ausdrücklich unsere dokumentierten Produktheuristiken, keine aus diesen Quellen belegten optimalen Grenzwerte. Flutter 3.47.7/Dart 3.13.5 und vorhandene Paketversionen bleiben fixiert; keine Abhängigkeitsmigration für diese Funktionen.

Ergänzend geprüft am 17.10.2026: [Codex app-server `model/list`](https://learn.chatgpt.com/docs/app-server#list-models-modellist), [CLI-Einstellungen](https://learn.chatgpt.com/docs/developer-settings) und [Kataloggrenzen bei angepassten Providern](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server#using-codex-app-server). Modelle und unterstützte Reasoning-Stufen werden aus der tatsächlich fixierten CLI 0.162.1 gelesen; `includeHidden` ermöglicht den vollständigen Katalog. Fehlende `inputModalities` gelten laut Dokumentation aus Kompatibilitätsgründen als Text/Bild. Der tatsächliche CLI-JSON-Schemaexport beschreibt Reasoning als dynamischen nichtleeren String, nicht als feste Auswahlliste. Katalogmetadaten beweisen keine Modellberechtigung; der vorhandene künstliche Modell-/Bildtest bleibt erforderlich. Keine SDK-, CLI- oder Modellmigration.

Ergänzend geprüft am 15.10.2026: [OpenRouter Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs) und [konkreter Free-Endpunkt](https://openrouter.ai/api/v1/models/dots-studio/dots-3-note-preview:free/endpoints). Dots/AtlasCloud meldet weiterhin Preis 0 und strukturierte Ausgaben; die vorhandene Prüfung vor jedem Aufruf bleibt erhalten. Schema-Unterstützung ersetzt keine eigene Validierung: explizite Auswahlindizes, Fach-/Gruppenbindung, Aufgabenanzahl und kurze quellengestützte Sachantworten prüfen wir im Backend. Keine SDK- oder Modellmigration.

- Regulärer Android-Release: [Versionierung](https://developer.android.com/studio/publish/versioning), [Signierung](https://developer.android.com/studio/publish/app-signing). Gleiche Paket-/Signieridentität und steigender Versionscode erhalten den Updateweg; unser zusätzlicher Deploymentcheck bindet Signierer und Quellversion.

- Firebase-Übergabe: [FCM Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [fixiertes SDK 16.7.0](https://pub.dev/documentation/firebase_messaging/16.7.0/firebase_messaging/FirebaseMessaging-class.html), [API-Key-Einschränkungen](https://firebase.google.com/docs/projects/api-keys), [HTTP-v1 einschließlich validate_only](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages/send), [FCM-IAM](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging), [eigene IAM-Rollen](https://docs.cloud.google.com/iam/docs/creating-custom-roles), [REST-Authentifizierung und explizites Quota-Projekt](https://docs.cloud.google.com/docs/authentication/rest), [Versionsarchive der Google-Cloud-CLI](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives). CLI 589.0.0, offizielles unversioniertes Linux-x86_64-Archiv SHA-256 `817026aec0adea0e2ee8ed3a1ba3eabfe9e5177581fbe16595a8fe495a601300`. REST-Prüfungen verwenden X-Goog-User-Project ausschließlich für SCHULPILOT, damit nicht das gemeinsame CLI-Projekt als API-Verbraucher verwendet wird. Neuere FlutterFire-Anleitungen ersetzen keine Prüfung der tatsächlich fixierten API.
- Firebase-Datenschutz: [Datenschutz und Sicherheit](https://firebase.google.com/support/privacy), [Nutzungsbedingungen](https://firebase.google.com/terms), [Auftragsverarbeitung](https://firebase.google.com/terms/data-processing-terms). Technische Einrichtung, Betreiberfreigabe und sichtbare Zustellung sind unterschiedliche Nachweise. Kein EU-exklusiver FCM-Verarbeitungsort behauptet; Tokenlöschung bedeutet keine sofortige Löschung aller Google-Installations-/Backupdaten.
- Banküberweisung und Bestellablauf: [§ 312j BGB](https://www.gesetze-im-internet.de/bgb/__312j.html), [§ 357a BGB](https://www.gesetze-im-internet.de/bgb/__357a.html), [§ 5 DDG](https://www.gesetze-im-internet.de/ddg/__5.html), [§ 33 UStDV](https://www.gesetze-im-internet.de/ustdv_1980/__33.html), [§ 147 AO](https://www.gesetze-im-internet.de/ao_1977/__147.html). Fester Gesamtpreis, eindeutiger Bestellbutton, Vertrags-/Bankdaten-Snapshot und ausdrücklicher optionaler vorzeitiger Beginn. Tarife sind vom Entwickler auf Nutzerauftrag festgelegte Produktpreise, keine Providerpreis-Angaben. Der Verkauf bleibt ohne echte Betreiber-/Bank-/Steuerdaten gesperrt.

Implementierte Schnittstellen wurden gegen diese offiziellen Dokumentationen geprüft. Versionsauflösung zusätzlich über Paketregister und die tatsächlich installierten Werkzeuge. Modellnamen, Fähigkeiten und Preisobergrenzen wurden für den ausdrücklich beauftragten OpenRouter-Free-Standard im offiziellen Endpunktkatalog überprüft; keine Annahme eines dauerhaft kostenlosen oder verfügbaren Endpunkts.

| Bereich | Primärquelle / Prüfung |
| --- | --- |
| Flutter | https://docs.flutter.dev/install/manual und https://docs.flutter.dev/install/archive ; offizieller `stable`-Git-Checkout: Flutter 3.47.7 / Revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5. Das JSON-SDK-Archiv lieferte beim Abruf 404; deshalb offizieller Git-Checkout statt erfundenem Download. |
| Flutter-Web | https://docs.flutter.dev/platform-integration/web/initialization ; tatsächliches `flutter build web --help`: eigene Bootstrapdatei, `--no-web-resources-cdn`, `--csp`. |
| GoRouter | https://pub.dev/documentation/go_router/latest/go_router/GoRouter/optionURLReflectsImperativeAPIs.html ; Version 18.0.2 und lokaler Paketquelltext: Webnavigation per `go`, native Detailnavigation per `push`. |
| Flutter-Pakete | Offizielles pub.dev-Register; direkte Pins in `app/pubspec.yaml`, alle transitiven Stände in `pubspec.lock`. Export: https://pub.dev/packages/file_saver . |
| FastAPI | https://fastapi.tiangolo.com/deployment/concepts/ und https://fastapi.tiangolo.com/deployment/server-workers/ ; hier ein API-Prozess hinter vorhandenem Caddy, separater persistenter Jobworker. |
| Python-Pakete | pypi.org JSON-Metadaten: FastAPI 0.143.0, SQLAlchemy 2.1.4, Uvicorn 0.54.0, Psycopg 3.3.6, Pydantic 2.14.1, Pillow 12.3.0, Alembic 1.20.0; vollständige Pins in den Lockdateien. |
| OpenAI strukturierte Ausgaben | https://developers.openai.com/api/docs/guides/structured-outputs ; Responses `text.format`, zusätzliche serverseitige Validierung. |
| OpenAI Bilder | https://developers.openai.com/api/docs/guides/images-vision ; `input_image` als private Data-URL über unser Backend. |
| Minderjährige | https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance ; zusätzliche Schutzmaßnahmen und ZDR-Anforderungen bei bestimmten personenbezogenen Kinderdaten. |
| OpenAI Datenkontrollen | https://developers.openai.com/api/docs/guides/your-data ; `store:false` ist keine pauschale ZDR-/Datenschutzfreigabe. |
| Codex | https://developers.openai.com/codex/noninteractive/ und https://developers.openai.com/codex/config-reference/ ; außerdem tatsächlich installierte CLI 0.162.1: `exec --help`, `features list`. Kein Live-Lernaufruf unter Entwicklungszugängen. |
| OpenRouter | https://openrouter.ai/docs/guides/features/structured-outputs , https://openrouter.ai/docs/guides/privacy/data-collection , https://openrouter.ai/docs/guides/get-started/sovereign-ai ; explizite Upstreambindung, ZDR und Data-Collection-Deny ersetzen keine Vertrags-/Kontoprüfung. |
| Hetzner | https://docs.hetzner.cloud/reference/cloud und https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/features-and-differences/ ; zuständige Cloud-API und bestehende Zone wurden tatsächlich authentifiziert geprüft. |
| Caddy | https://caddyserver.com/docs/caddyfile/directives/tls ; vorhandenes Caddy 2.6.2, ACME-Issuer `dir`, lokale Validierung, öffentlich geprüfter Let’s-Encrypt-Aussteller. |

Flutter-/Python-Abhängigkeiten müssen bei Aktualisierungen erneut auf Sicherheit, API-Kompatibilität und Lizenzpflichten geprüft werden. `docs/python-dependencies.json` enthält aus den installierten Distributionsmetadaten ermittelte Lizenzangaben einschließlich Entwicklungswerkzeugen; fehlende Angaben bleiben unbekannt. Flutter-Lizenzhinweise sind in der App erreichbar. Es wurde keine pauschale juristische Freigabe aller kommerziellen Betriebsbedingungen behauptet.


Zusätzliche offizielle Quellen, geprüft am 14.10.2026:

- Mehrseitiger Tagesassistent: https://pub.dev/packages/image_picker (fixiert 1.2.4, Kamera/Galerie und dokumentiertes `retrieveLostData` bei Android-Neustart) sowie https://openrouter.ai/docs/guides/features/structured-outputs (JSON-Schema-Ausgaben; zusätzlicher serverseitiger Paket-/Quellenabgleich). Keine neue Client-Abhängigkeit erforderlich.

- OpenRouter aktueller Modellkatalog: https://openrouter.ai/api/v1/models ; konkrete Endpunkte über `/api/v1/models/{author}/{slug}/endpoints`, für die oben dokumentierten kostenlosen Modelle tatsächlich abgerufen.
- Kosten- und Providerbindung: https://openrouter.ai/docs/guides/routing/provider-selection (max_price, only, allow_fallbacks, data_collection, zdr).
- FlutterFire: https://firebase.google.com/docs/cloud-messaging/flutter/client und https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages ; tatsächlich aufgelöste Pakete `firebase_core 4.15.0`, `firebase_messaging 16.7.0`, `firebase_core_web 3.12.0`, JS SDK `12.19.0`. Dieses fixierte Messaging-Paket stellt `getToken/onTokenRefresh` bereit; neuere FID-Methoden der Dokumentation wurden nicht erfunden oder vorausgesetzt.
- FCM HTTP v1 / Dienstkonto: https://firebase.google.com/docs/cloud-messaging/send/v1-api ; Payload-Schema einschließlich `PRIVATE`: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages .
- Token-Lebenszyklus: https://firebase.google.com/docs/cloud-messaging/manage-tokens .
- Android-Signierung und AAB: https://docs.flutter.dev/deployment/android .
- Google Play Familien: https://support.google.com/googleplay/android-developer/answer/9893335 ; Kontolöschung: https://support.google.com/googleplay/android-developer/answer/13327111 .

Bei echten Google-Projektzugängen sind die dann geltenden SDK-/Families-/Data-Safety-Vorgaben erneut zu prüfen. Ein gebautes AAB ersetzt keine Play-Prüfung.


Ausbau vom 14.10.2026:

- Mehrfachauswahl: https://pub.dev/packages/image_picker ; `pickMultiImage`, Version 1.2.4. Drehen: https://pub.dev/documentation/image/latest/image/copyRotate.html ; bestehende Version 4.12.0 beibehalten.
- OpenRouter Datenkontrollen: https://openrouter.ai/docs/guides/privacy/data-collection und https://openrouter.ai/docs/guides/features/zdr ; geschützte synthetische Routingprüfung gegen die tatsächlich gewählten Endpunkte. Die erteilte Betreiberfreigabe ist kein Beleg für eine technisch verfügbare Route.
- Firebase: https://firebase.google.com/docs/cloud-messaging/flutter/get-started ; reale Zustellung erst mit Projektkonfiguration und Gerätetest.
- GitHub Actions: offizielle Repositories/Release-API von https://github.com/actions/checkout/tree/v7.0.1 und https://github.com/actions/setup-python/tree/v7.0.0 ; Release-Tags und vollständige Commit-IDs über Git verifiziert. Beide verwenden Node 24 und benötigen aktuelle Runner. CI nutzt Ubuntu 24.04, Python 3.12.3 und den bereits fixierten offiziellen Flutter-Commit; keine Deploy-/Signierschlüssel in CI.
- Vorbereiteter späterer Zahlungsbetrieb: https://docs.stripe.com/api/checkout/sessions/create und https://support.google.com/googleplay/android-developer/answer/9858738 ; noch kein Checkout aktiviert, keine erfundenen Tarifpreise und kein fremdes Zahlungs-/Google-Konto verwendet.
- E-Mail-Direktlinks (14.10.2026): https://api.flutter.dev/flutter/flutter_web_plugins/PathUrlStrategy/PathUrlStrategy.html und https://pub.dev/documentation/go_router/18.0.2/go_router/GoRouterState/uri.html ; `includeHash=true` erhält das Fragment beim Kaltstart. Die Formularseite erhält die vollständige Router-URI, statt den nachträglich veränderten Browserzustand auszulesen. Bestehende Flutter-/Router-Versionen bleiben fixiert.

- OpenRouter-Free-Standard (14.10.2026): https://openrouter.ai/docs/guides/routing/provider-selection und https://openrouter.ai/docs/guides/features/structured-outputs ; feste Endpunktbindung, Preisgrenze 0, Datensammlung gesperrt, keine Fallbacks. https://openrouter.ai/docs/guides/best-practices/reasoning-tokens ; dokumentierte `reasoning.enabled`/`exclude`-Parameter tatsächlich getestet. Der kompakte Free-Standard verwendet `enabled:false`, nachdem längere Reasoning-Ausgaben Ausgabelimits erreichten. https://openrouter.ai/dots-studio/dots-3-note-preview:free ; angekündigtes Ende 31.12.2026 erfordert spätere ausdrückliche Modellmigration. Entscheidung und weitere Datenschutzquellen: [AI_STANDARD.md](AI_STANDARD.md).

- Lokaler Fotoimport im Browser (14.10.2026): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/connect-src ; `fetch` und `XMLHttpRequest` unterliegen `connect-src`. Im fixierten Flutter-Paket `cross_file 0.3.5+5` liest `XFile.readAsBytes` lokale Blob-URLs per XHR. Der öffentliche Chromium-Test reproduzierte die CSP-Sperre; die projektspezifische Caddy-Richtlinie erlaubt deshalb ausdrücklich `blob:`.

- Betreutes Lernen (14.10.2026): https://openrouter.ai/docs/guides/features/structured-outputs ; Ausgabevarianten für bekannte beziehungsweise neu vorzuschlagende Ziele, zusätzliche Backendprüfung. Der konkrete Endpunktkatalog wurde erneut auf Bild-/Text-/Schemafähigkeiten und Preis 0 geprüft. Die mehrtägigen Lernkriterien sind ausdrücklich Produktregeln und keine behauptete externe Wirksamkeitszertifizierung.

- Android-Updates, geprüft am 14.10.2026: https://developer.android.com/reference/androidx/core/content/FileProvider ; https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls() ; https://developer.android.com/guide/playcore/in-app-updates/kotlin-java (app-update 2.1.0) ; https://support.google.com/googleplay/android-developer/answer/12085295?hl=en (Play-Flavour ohne direkte APK-Installation).

- Flutter-Gestaltung und Anpassung, erneut geprüft am 14.10.2026: [Themes](https://docs.flutter.dev/cookbook/design/themes), [Material 3](https://api.flutter.dev/flutter/material/ThemeData/useMaterial3.html), [Adaptive und responsive Oberflächen](https://docs.flutter.dev/ui/adaptive-responsive), [Aufbau nach verfügbarem Platz](https://docs.flutter.dev/ui/adaptive-responsive/general). Gemeinsame `ThemeData`/`ColorScheme`, Material-Komponenten und Layoutentscheidungen nach Fenstergröße statt allein nach Gerätenamen. Material 3 ist im fixierten Framework bereits enthalten; keine neue Abhängigkeit oder Versionsanhebung nötig. Der lokale Android-Einstieg `MainActivity : FlutterActivity` bestätigt eine Flutter-App, keine WebView-Hülle.

- Android-Installer, erneut geprüft am 14.10.2026: [FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider) und [Installationsquellen](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()). Der direkte Updater übergibt eine nur vorübergehend lesbare `content:`-URI an Androids Installationsoberfläche; Android verwaltet Quellenfreigabe und Bestätigung. [ACTION_INSTALL_PACKAGE](https://developer.android.com/reference/android/content/Intent#ACTION_INSTALL_PACKAGE) ist seit API 29 veraltet; der vorhandene direkte Adapter verwendet `ACTION_VIEW` mit APK-MIME-Typ. Keine stille Installation behaupten. Direkter und Play-Flavour bleiben getrennt.

- OpenRouter-Fehlerantworten, geprüft am 14.10.2026: [Errors and debugging](https://openrouter.ai/docs/api_reference/errors-and-debugging). Auch nicht gestreamte HTTP-200-Antworten können ein Fehlerobjekt ohne choices enthalten. Wurzel-/Choice-Fehler und leere Antworten werden gesondert erkannt; nur feste Fehlerkategorien anzeigen, keine Upstreamnachrichten oder Metadaten übernehmen. Kein impliziter Wiederholungsversuch.

Google-Elternzugang, 14.10.2026: google-auth 2.62.0 bleibt fixiert; verifizierter Authorization-Code-Flow mit State/Nonce/PKCE und eigener Sitzung. Dokumentation: https://developers.google.com/identity/openid-connect/openid-connect ; https://googleapis.dev/python/google-auth/latest/reference/google.oauth2.id_token.html ; https://developers.google.com/identity/sign-in/android/backend-auth (Drittanbieter-E-Mails benötigen gegebenenfalls eigene Bestätigung); https://developers.google.com/identity/branding-guidelines (offizielles G-Asset unverändert); https://docs.flutter.dev/cookbook/navigation/set-up-app-links . Vorhandenes `crypto 3.0.7` wird direkte Dart-Abhängigkeit, keine transitive Versionsänderung.


Lernreise und freiwillige Sprache, geprüft am 15.10.2026:

- [IES Practice Guide: Organizing Instruction and Study](https://ies.ed.gov/ncee/wwc/PracticeGuide/1), [Originalleitfaden](https://ies.ed.gov/ncee/wwc/Docs/PracticeGuide/20072004.pdf): verteiltes Wiederholen, Abrufübungen und der Wechsel zwischen ausgearbeiteten Beispielen und eigenem Lösen. Unsere Etappen sind eine Produktumsetzung; keine Wirksamkeitsgarantie oder Beherrschung allein aus einer Aufgabe.
- [EEF: Metacognition and Self-regulated Learning](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition): explizite Beispiele, geführtes Üben und schrittweise selbstständiges Anwenden. Fehlerdetektiv und belegte Heftfragen geben zusätzliche Erklärwege; keine erfundenen Spielwerte.
- [flutter_tts 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5), [speech_to_text 7.5.0](https://pub.dev/packages/speech_to_text/versions/7.5.0): exakte Paketquellen/API geprüft und fest gepinnt. Android RECORD_AUDIO sowie SpeechRecognizer-/TTS-Queries, kein Bluetoothrecht; kein automatisches Initialisieren bei Widgetaufbau. Die vorhandene Gerätestimme/-erkennung kann Netzwerkdienste nutzen.
- [OpenRouter Fehler](https://openrouter.ai/docs/api_reference/errors-and-debugging): HTTP200 mit Fehlerobjekt bleibt ein Fehler, ebenso abgeschnittene Ausgabe. Kleine getrennte Schemas und entfernte unbenutzte Definitionen verkleinern den Rückblickauftrag; keine automatische Wiederholung oder Anbieteränderung.

- Wörtliche Fotoerkennung, erneut geprüft am 15.10.2026: [OpenRouter Request Schema](https://openrouter.ai/docs/api_reference/overview) dokumentiert `image_url.url`/`detail`; [Image Understanding](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding) private Base64bilder und Text-/Bildreihenfolge; [Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs) striktes Schema mit Feldbeschreibungen. [Official OpenAI documentation: Images and vision](https://developers.openai.com/api/docs/guides/images-vision) dokumentiert `input_image` und die modellabhängigen Detailstufen. OCR fordert `high` an, keine ungeprüfte Umstellung auf neue modellabhängige `original`-Fähigkeiten; Auswahl und Kostenkontrolle bleiben unverändert. Eigene geordnete Abschrift und zusätzlicher Umfangsplausibilitätscheck ersetzen keinen menschlichen Quellenabgleich.

Codex-Umstellung, geprüft am 15.10.2026: [OpenAI Docs: nichtinteraktiver Betrieb](https://learn.chatgpt.com/docs/non-interactive-mode), [CLI und `--search`](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [Anmeldung und getrennte Konto-/API-Datenregeln](https://learn.chatgpt.com/docs/auth), [Konfiguration](https://learn.chatgpt.com/docs/config-file/config-reference), [aktuelle dokumentierte Modellauswahl](https://learn.chatgpt.com/docs/models), [gehostete Websuche](https://developers.openai.com/api/docs/guides/tools-web-search), [API-Token-/Suchpreise](https://developers.openai.com/api/docs/pricing). Seiten tatsächlich geöffnet; CLI 0.162.1 `--help`, `exec --help`, `login --help` und `features list` geprüft. Das separat kopierte native Binary aus der fixierten offiziellen npm-Plattformdistribution hat SHA-256 `628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1`. Echte CLI-Transporttests mit künstlichen Kontodateien und simuliertem Upstream sind kein echter Anbieter-/Kontotest. Die fest gebundene ChatGPT-Codex-Route bleibt CLI-versionabhängig und experimentell. Details: [CODEX.md](CODEX.md).

Zusätzliche Distributionsprüfung am 15.10.2026: `@openai/codex@0.162.1-linux-x64` von registry.npmjs.org heruntergeladen, SHA-512 gegen die Registry-Integrität geprüft und das native Binary im Archiv auf denselben SHA-256-Wert wie die installierte CLI geprüft. Rootless-Hostkonto hat eine eigene Gruppe und nachweislich keinen Lesezugriff auf App-Umgebung oder App-Daten.

Geführter Kinder-Lernablauf, Recherche und Gegenprüfung am 17.10.2026:

- Vor der Umsetzung prüften vier Entwicklerperspektiven Einstieg, Aufgabenraum, Abschluss und technische Wiederaufnahme unabhängig: [W3C – Make Each Step Clear](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o1p04-clear-steps/) empfiehlt sichtbare aktuelle/erledigte/nächste Schritte; [NN/G – Children's Websites: Usability Issues in Designing for Kids](https://www.nngroup.com/articles/childrens-websites-usability-issues/) berichtet aus eigenen Kinderstudien zu überlesenen langen Anweisungen und Navigation. Unsere Ableitung: stabiler Einstieg und dieselben drei Phasen statt wechselnder Menüketten.
- Während der Diskussion: [NSW CESE – Cognitive load theory in practice](https://education.nsw.gov.au/about-us/education-data-and-research/cese/publications/practical-guides-for-educators/cognitive-load-theory-in-practice), [EEF – Metacognition and Self-regulated Learning, zweite Auflage](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition) und [IES/WWC Practice Guide 1](https://ies.ed.gov/ncee/wwc/PracticeGuide/1). Hilfen am konkreten Lernschritt, eigene Anwendung und spätere Abrufe; notwendige Informationen räumlich zusammenhalten. Keine pauschale tägliche Aufgabenzahl oder neue Mastery-Garantie aus diesen Quellen ableiten.
- Vertiefung zum Abschluss: [Roediger et al. 2011, Originalstudie mit Klasse 6](https://pdf.retrievalpractice.org/guide/Roediger_Agarwal_etal_2011_JEPA.pdf), [Cepeda et al. 2008](https://pubmed.ncbi.nlm.nih.gov/19076480/), [Koriat/Bjork 2005](https://pubmed.ncbi.nlm.nih.gov/15755238/). Übung, subjektives Verstehen und späterer eigenständiger Abruf sind verschiedene Beobachtungen. Unsere Regel drei Prüftage über sieben Tage bleibt eine dokumentierte Produktregel, keine wissenschaftliche Universalgrenze.
- Nach der Umsetzung erneut geprüft: [W3C – Consistent Help](https://www.w3.org/WAI/WCAG22/Understanding/consistent-help.html), [Focus Not Obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum.html), [Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html), [Limit Interruptions](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o5p01-minimal-interruptions/) und [Flutter – Accessibility](https://docs.flutter.dev/ui/accessibility). Konstanter Hilfezugang, eigener Platz für die Hauptaktion statt Tastaturoverlay, Ergebnis als Statusmeldung und kein sekündliches Vorlesen des Timers. [Mueller/Dweck 1998](https://pubmed.ncbi.nlm.nih.gov/9686450/) stützt die Vorsicht gegenüber Eigenschaftslob; unsere Rückmeldung nennt gespeicherte konkrete Schritte. Die Quellen ersetzen keine Nutzungsbeobachtung mit Kindern und keine pauschale WCAG-Zertifizierung. Flutter 3.47.7/Dart 3.13.5 und sämtliche SDK-Abhängigkeiten bleiben unverändert fixiert.
- Letzter Komponentenabgleich: [W3C Radio Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/radio/), [Flutter RadioGroup](https://api.flutter.dev/flutter/widgets/RadioGroup-class.html) und [EEF Scaffolding Framework](https://d2tic4wvo1iusb.cloudfront.net/production/eef-guidance-reports/metacognition/scaffolding-framework-metacognitive-strategies_practitioner-tool_v.1.0.0.pdf): exklusive Auswahl mit Tastatur, abgestufte fachliche Hilfen. [W3C Support Simplification](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o8p03-complexity/) und [NN/G Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/) stützen seltene Suchwerkzeuge auf Anfrage, während Lernrunde und Fotos sichtbar bleiben. Komponenten-/Semantiktests sind keine akustische TalkBack- oder Endgeräte-Mikrofonabnahme.

- Plattformfehler bei der öffentlichen Sichtprüfung, 17.10.2026: [Dart – Bitwise and shift operators](https://dart.dev/language/operators#bitwise-and-shift-operators) und [Number representation / bitwise operations](https://dart.dev/resources/language/number-representation#bitwise-operations) dokumentieren abweichende Bitoperationen auf Web. Zwei Dauergrenzen in der Uhr von `1 << 40` auf dieselbe portable numerische Größe umgestellt; tatsächlicher Chrome-Widgettest mit 20:00 Ziel/Rest sowie native Zeit-VMtests bestanden. Kein Rückschluss aus VMtests allein auf die JavaScript-Darstellung.

Benachrichtigungsglocke und Android-Zustellung, geprüft am 17.10.2026:

- [FCM – Nachrichten in Flutter empfangen](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages): Erlaubnis, Vordergrundstream und explizite Anzeige sowie getrennte Klickereignisse. Das gepinnte lokale Messaging 16.7.0 behält `getToken`/`onTokenRefresh`; keine Migration auf APIs anderer SDK-Versionen.
- [Android – Notification Channels](https://developer.android.com/develop/ui/compose/notifications/channels): Kanal beim Appstart anlegen, aktuellen Sperrstatus lesen und gezielt Systemeinstellungen öffnen. Eigene Kanalentscheidungen nicht überschreiben.
- [Android – Notification Permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission): Android-13+-Erlaubnis bleibt eine bewusste Entscheidung auf dem Gerät.
- [FCM – Android message priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority): Hohe Transportpriorität für echte sichtbare Meldungen. Unsere Nachrichten bleiben gebündelt, neutral, kontogebunden und höchstens 60 Sekunden gültig. Projekt-/OAuth-/Validierungsnachweis und tatsächlich beobachtete Anzeige werden getrennt dokumentiert.

## Sofatutor-Integration ·18.10.2026

- Tatsächlich übergebene lokale Quelle: Downloads/Schulpilot_Sofatutor_ThemenDB.zip,
  README/INTEGRATION, normalisiertes catalog.json1.5, validation,
  combined_coverage_report und schulpilot_import/summary/all_subjects.csv.
  SHA256/Umfang/Prüfgrenzen in CATALOG_INTEGRATION.md.8.227 unterschiedliche
  Inhalte,19.603 CSV-Beziehungen,0 vorliegende Validierungsfehler und465 Hinweise.
  Kein Nachweis des gesamten Anbieterkatalogs oder einer Wiedergabeberechtigung.
- [SQLAlchemy2.1 – PostgreSQL Upserts](https://docs.sqlalchemy.org/en/21/dialects/postgresql.html#insert-on-conflict-upsert):
  verwendete feste Version2.1.4 erhalten; Dialektinsert/excluded und atomare
  Konfliktbehandlung, keine Abhängigkeitsmigration.
- [PostgreSQL16 – Volltextindizes](https://www.postgresql.org/docs/16/textsearch-indexes.html):
  vorhandene PostgreSQL16-Instanz, GIN auf to_tsvector('german',search_text),
  keine neue Such-/Embeddinginfrastruktur. Sprachähnlichkeit ist kein Klassenbeleg.
- Vorhandener url_launcher6.3.2 und url_launcher_web2.4.3 im fixierten lokalen
  Paketquelltext geprüft: launchUrl/externalApplication, normale HTTPS-URLs,
  Webfenster mit noopener,noreferrer. Projektspezifisches Caddy enthält bereits
  Referrer-Policy:no-referrer. Keine Weitergabe privater Inhalte oder App-Zugänge.
  Tatsächlich beobachtete Link-/Geräteprüfungen getrennt in STATUS/Handoff führen.
  Offizielle Paketdokumentation zusätzlich geprüft:
  [url_launcher6.3.2](https://pub.dev/packages/url_launcher/versions/6.3.2).

## Protokollprüfung ·19.10.2026

- Beide lokalen vollständigen Testberichte einschließlich aller Details/Anhänge
  und eingebetteter JSON-Werte gelesen. Provenienz,69 Fälle und31 Befunde in
  TEST_REPORT_REVIEW.md. Absichtliche Fehler sind keine Diagnose des echten Kindes.
- [IES/WWC – Organizing Instruction and Study to Improve Student Learning](https://ies.ed.gov/ncee/wwc/PracticeGuide/1):
  verteiltes Wiederholen, Wechsel von Beispielen/selbstständigem Üben, Abruf und
  Verbindung von Grafik/Text; Belegstärke je Empfehlung unterschiedlich. Keine
  behauptete Effektprüfung unserer App oder optimale universelle Intervallregel.
- [EEF – Metacognition and Self-Regulated Learning](https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/metacognition):
  Strategien fachbezogen vormachen, stützen und schrittweise selbstständig nutzen;
  zweite Ausgabe13.11.2025. Kurze Lernschritte, konkrete Hilfe und eigene Antwort
  sind Produktentscheidungen, keine zugesicherte Notenverbesserung.
- [W3C – Understanding Error Suggestion](https://www.w3.org/WAI/WCAG22/Understanding/error-suggestion.html):
  konkrete Korrektur am Feld statt nur flüchtiger Meldung; keine vollständige
  WCAG-Konformitätsbehauptung aus einzelnen Widget-/Kontrasttests.
- [NOAA – Marine Mammals](https://www.noaa.gov/education/resource-collections/marine-life/marine-mammals):
  geprüftes Grundwissen zu Luftatmung/Lunge und Milch bei Meeressäugern. Eigene
  kurze deutsche Paraphrase in foundations.py, getrennt vom bestätigten Hefttext;
  keine fremden Bilder/Arbeitsblätter oder ungeprüfter allgemeiner Wissenskurs.
## Arbeitseinheit20.10.2026 ·1.11.1+51

- Offizielle OpenRouter-Modell-/Endpunkt- und ZDR-APIs am20.10. erneut geprüft:
  [Luna-Endpunkte](https://openrouter.ai/api/v1/models/openai/gpt-6-luna/endpoints),
  [Sol-Endpunkte](https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints),
  [ZDR-Liste](https://openrouter.ai/api/v1/endpoints/zdr).
- [Routingvorgaben](https://openrouter.ai/docs/guides/routing/provider-selection),
  [ZDR](https://openrouter.ai/docs/guides/features/zdr) und
  [Response-Caching](https://openrouter.ai/docs/guides/features/response-caching):
  konkrete Anfragevorgaben getrennt von nicht eingesehenem Konto-Logging führen.
- [ECB-Referenzkurse](https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml),
  Datenstand19.10.2026:1EUR=1,1225USD. Konservativ gerundete Umrechnung und
  tatsächliche dreiteilige Probe in OPENROUTER_ACTIVATION_2026_10_20.md.
- Neun künstliche Heftbilder mit eingebautem image_gen, je drei Abschnitte in
  Mathematik, Deutsch und Englisch. Prompts/Herkunft:
  qa/notebook_audit_images_20261020.json; Bilder außerhalb von Git in
  artifacts/notebook-audit-20261020. Alle neun vor Upload visuell durchgesehen;
  keine echten Kinderinhalte oder übernommenen Schulbuchseiten.
## Vereinheitlichung und Elternbericht-Prüfung ·21.10.2026 ·1.18.4+78

Eigene bestehende Flutter-Bausteine in child_section_ui.dart, ui.dart,
homework_screen.dart, collection_screen.dart, notebook_shelf.dart und
notebook_screen.dart geprüft und gemeinsam verwendet. Keine neuen Pakete,
Bildanbieter oder externen Designassets.130 gemeinsame Flutterfälle bestanden,
einschließlich320px/zweifacher Schrift, hell/dunkel, Rollen und verspäteter
Abmeldung. Tatsächliche Browserprüfung mit ausschließlich künstlichem lokalem
Kind/Elternzugang ohne KI-Schlüssel: Seitenköpfe, Hefterdetail, Filter, Glocke,
Alle anzeigen, explizite Lesemarkierung, Einstellungen und Abmelden.

Elternbericht: eigener parent_insights.py-/Provideradapterpfad untersucht;
Schema erlaubt nur dieselben beleggebundenen Kategorien wie validate.
33PostgreSQL- und14SQLitefälle bestanden (unterschiedliche Läufe, nicht addiert),
einschließlich aller15 nichtleeren Belegkombinationen, sieben Ablehnungsgründe,
normaler Abrechnung und einmaligem Mocktransport. Keine echten Kindereingaben
für diese Tests. Die ausdrücklich beauftragte Diagnose des konkreten Berichts
war auditiert; OpenRouter-Generationmetadaten bestätigten erfolgreichen Transport,
aber enthielten keinen Antwortinhalt. Historische Einzelursache bleibt unbekannt.
Ausgabeschema-/Validatorlücke ist durch synthetische Fälle unabhängig belegt.
Providerrevision, Modellmix, Budget und Datenschutzeinstellungen unverändert.
Nach dem geprüften Deployment ein ausdrücklich beauftragter, normal reservierter
Reparaturbericht über die bestehende gültige Elternsitzung:1Aufruf/1Jobversuch,
0,001337USD, Bericht ready und aktuelle Eltern-/Lernplanansicht bestätigt.
Alte Antworten, Fehlerbericht und0,001201USD-Verbrauch unverändert; keine neuen
Kinderantworten. Private Operatorhilfen und Diagnosekopien anschließend entfernt.
## Familienanrufe und Android-Push ·21.10.2026 ·1.19.0+79

- Eigenes bestehendes FastAPI-/Flutter-/FCM-/Sitzungsmodell; keine Video-SaaS-
  Konten, Modellaufrufe oder Firebase-Authentication. Neue additive Migration0026.
- [Flutter-WebRTC1.6.2+hotfix.4](https://pub.dev/packages/flutter_webrtc/versions/1.6.2%2Bhotfix.4)
  und dessen installierter Android-/Dart-Quellcode geprüft; exakt gepinnt,
  webrtc_interface1.5.1 im Lockfile. Keine freien UI-Bibliotheken hinzugefügt.
- [WebRTC: TURN](https://webrtc.org/getting-started/turn-server) und
  [Peer-Verbindungen](https://webrtc.org/getting-started/peer-connections):
  gezielter eigener Relay für NAT/Mobilfunk, Signalisierung über vorhandene API.
- [MDN: getDisplayMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia):
  erneute ausdrückliche Auswahl und unmittelbare Benutzeraktion, keine gespeicherte
  Erlaubnis oder behauptete vollständige Browserunterstützung.
- Offizielles Ubuntu24.04-Paket coturn4.6.1-1build4 installiert. Primärquellen:
  [Konfiguration](https://github.com/coturn/coturn/blob/4.6.1/examples/etc/turnserver.conf),
  [Adressprüfung](https://github.com/coturn/coturn/blob/4.6.1/src/client/ns_turn_ioaddr.c#L416),
  [Peer-Schutz](https://github.com/coturn/coturn/blob/4.6.1/src/server/ns_turn_server.c#L248).
  Daraus belegte Korrektur des irrtümlich unbeschränkten IPv6-Null-Denybereichs;
  private Netze und eingebaute Zero-/Loopbacksperren bleiben geschützt.
- [Hetzner-Firewalls](https://docs.hetzner.com/cloud/firewalls/faq/), vorhandene
  Firewall und Serveradresse geprüft; nach konkreter Betreiberbestätigung vier
  getrennte Regeln nur am Schulpilot-Host ergänzt, bestehende Regeln erhalten.
- Isolierter Medienprüfpartner aiortc1.15.0/aioice0.10.2 aus offiziellem PyPI,
  ausschließlich im ignorierten QA-Ordner, keine Produktabhängigkeit. Drei echte
  erzwungene Relayverbindungen UDP/TCP/TLS mit zwei künstlichen Kameras, eigener
  Bildschirmquelle, stillem Audio und Daten-Echo erfolgreich. Keine echten Fotos
  oder unbemerkte Geräteaufnahme. Details und Android-Nachweis in FAMILY_CALLS.md
  beziehungsweise STATUS.md; bloße FCM-Annahme bleibt von Anzeige getrennt.

Nachkorrektur 1.19.1+80: Im selben fixierten Plugin wurden
`rtc_video_renderer_impl.dart`, `audio_management.dart` und die Android-
`AudioSwitchManager`-Implementierung gezielt geprüft. Der native Renderer-Mute-
Setter verändert tatsächlich den AudioManager und den Audiotrack; für Remote-
Streams wirft er. Deshalb plattformgetrennte Previewsteuerung, explizite Video-
Trackbindung und bewusstes Mikrofon an. Keine automatische globale Entstummung.
Die lokale Rendererregression und vollständige Flutter-Analyse sind dokumentiert
in FAMILY_CALL_EVALUATION_2026_10_21.md. Normale FCM-Hintergrundanzeige und echte
Anrufkarte mit Annahme wurden am künstlichen Android-36-Gerät getrennt belegt.
Die QA-Uhr wurde nur dort korrigiert; Produktions-UTC wurde gegen Hetzner-NTP und
ungecachte Google-/GitHub-HTTPS-Zeit geprüft, nicht gegen das lokale Clocktool.

Nachkorrektur 1.19.2+81: Eigene Signalisierung und der reale späte Android-
Freigabeversuch zeigten, dass abgelaufene90-Sekunden-Umschläge auch den Sequenzzähler
entfernten. Zähler und begrenzter Hashindex haben nun die feste Anruflebensdauer;
private Inhalte behalten ihre 90-Sekunden-Frist mit API-Lifespan-Cleanup. Regressionen
prüfen späte Angebote, Wiederholungen, Kapazitätsgrenzen und Shutdown.
Der vorhandene Android-Service reduziert nach echtem Trackstopp ausschließlich
den MediaProjection-Typ; dafür wurde der bereits genutzte lokale Android-SDK-
Quell-/APIstand geprüft. Keine neue Bibliothek, Hintergrundaufnahme oder
Provideranfrage. Tatsächliche Abnahmen stehen im versionierten Evaluationsbericht.

Nachkorrektur 1.19.3+82: Die reale API-/Pooldiagnose und ein unabhängiger Review
identifizierten synchronen SQLAlchemy-Checkout in der asynchronen Security-
Middleware als vorhandene Blockadengefahr. Der installierte FastAPI-/Starlette-
Threadpool- und Generator-Cleanup-Pfad wurde geprüft; keine Frameworkmigration.
Gate-Sessions laufen vollständig außerhalb des Eventloops; der RAM-Cleanup
wartet dort niemals auf einen belegten Lock. Die Setup-/Familienrechte sowie Pool- und Budgetgrößen bleiben erhalten.
Der Evaluationsbericht trennt fehlgeschlagenen 81-Versuch, Wiederherstellung,
gezielte Engpassregression und tatsächliche spätere Medienabnahme.

Abschließende 82-Medienabnahme: Der isolierte aiortc-Prüfer verknüpft echte
Media-/SSRC-MSID mit dem tatsächlichen Transceiver-MID und Receivertrack. Der
Negativfall verweigert unbekannte Stream-IDs; Auflösung oder Reihenfolge ersetzen
keine Metadaten. Der tatsächliche 300s-Lauf bestätigt Kamera und Bildschirm,
spätes Angebot nach 143,36s, Bildschirmstopp und weiterlaufende Kamera/Audio.
15 periodische Healthprüfungen während des Gesprächs erfolgreich (maximal 0,029s). Die früheren
Prüferfehler bleiben unverändert in den Vorversuchsberichten erhalten.


UX-Erweiterung87 (laufende Abnahme, 22.10.2026): lokale Quellinventur und
synthetische Flutter-/PostgreSQL-Fälle. Gestaltung nach WAI
[Formularrückmeldungen](https://www.w3.org/WAI/tutorials/forms/notifications/),
[Statusmeldungen](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html),
[zugänglicher Authentifizierung](https://www.w3.org/WAI/WCAG22/Understanding/accessible-authentication-minimum.html)
und GOV.UK [Validierung](https://design-system.service.gov.uk/patterns/validation/)
sowie [Pagination](https://design-system.service.gov.uk/components/pagination/).
Die Quellen begründen einzelne Bedienregeln; sie belegen keine vollständige
WCAG-Konformität. Passworttexte werden beim Anlegen, Zurücksetzen und Bestätigen
unverändert gehasht/geprüft; die vorhandene Mindestlänge ohne Randauffüllung
bleibt erhalten. Revisionsgebundene Betreiberentwürfe und reine Prüfauftrag-
Metadaten erhalten Kosten-, Freigabe- und Rollenprüfungen. Kein Provideraufruf
wurde durch diese synthetischen Bedienprüfungen ausgelöst. Auslieferungsstand
und Gesamtnachweis werden erst nach der gemeinsamen Abnahme ergänzt.


Sofatutor-Weböffnung in UX87: fixierter Lockstand `url_launcher_web2.4.3`,
lokaler Pluginquellpfad und die [offizielle Dokumentation](https://pub.dev/documentation/url_launcher_web/latest/)
bestätigen zwei Grenzen: Nach einem asynchronen Vorbereitungsschritt kann die
Browseraktivierung ablaufen; der Rückgabewert bei erlaubtem HTTPS-Schema beweist
kein geöffnetes Fenster. Deshalb Vorbereitung und erneuter bewusster Öffnen-Klick
trennen, ohne automatische Wiederholungen oder Als-gesehen-Behauptung. Die
Abhängigkeit bleibt unverändert. Zusätzliche Eltern-Webprüfungen verwenden reine
künstliche Daten im Flutter-Chromeharness, ohne Anmeldung, KI oder echten Versand.


Zusätzliche Karten-/Bedienrunde88 (22.10.2026):
[Flutter Card](https://api.flutter.dev/flutter/material/Card-class.html)
beschreibt die ganze Karte als möglichen primären Weg zur Detailansicht;
[InkWell](https://api.flutter.dev/flutter/material/InkWell-class.html)
begründet Materialfläche, Clipping und sichtbaren Tastaturfokus.
[WAI Linkzweck](https://www.w3.org/WAI/WCAG22/Understanding/link-purpose-in-context.html)
begründet konkrete Zieltexte statt unbestimmter Klickflächen. Die
[WAI Disclosure-Karte](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/examples/disclosure-card/)
warnt ausdrücklich vor verschachtelten Aktionen und überlangen Namen; das
Beispiel wird nicht als ungeprüfter Produktionscode übernommen. Deshalb
Aktionskarten nur für einen eindeutigen Weg, Formulare und Mehrfachaktionen
weiter mit getrennten Bedienelementen. Native Tests prüfen tatsächlich
aktivierbare Karten, Semantikflags, Fokus, Kontrast und 200-Prozent-Schrift;
ein vollständiger Assistenztechnik-/WCAG-Nachweis wird daraus nicht abgeleitet.
Die Quellen wurden als Primärdokumentation geöffnet; keine neue UI-Bibliothek,
Anbieterroute oder kostenpflichtige Generierung wurde dafür ergänzt.

Release88-Nachweis: OpenJDK17.0.20.1, vorhandener bundletool1.18.3
(mit geprüftem lokalen SHA256). Für `jarsigner -strict` gilt die offizielle
[Oracle-Beschreibung der Exitcodes](https://docs.oracle.com/en/java/javase/17/docs/specs/man/jarsigner.html).
Der lokale Freigabeprüfer verweigert unsignierte Archive, bindet das AAB per Hash
an den tatsächlich kompilierten Play-Ausgang und prüft die Gültigkeitsdaten des
festgelegten Upload-Zertifikats; die selbstsignierte Zertifikatskette wird
ausdrücklich vom Fehler einer fehlenden Signatur unterschieden. Ein eigenes
künstliches unsigniertes Archiv wurde als Negativprobe verworfen.

Browsernachkorrektur89 (22.10.2026): Der fixierte Flutterquellstand setzt in
`material/progress_indicator.dart` ausdrücklich `progressBar`/`loadingSpinner`.
Die [Rollenübersetzung](https://api.flutter.dev/flutter/dart-ui/SemanticsRole.html)
und [ExcludeSemantics](https://api.flutter.dev/flutter/widgets/ExcludeSemantics-class.html)
erklären den im echten Browser reproduzierten Konflikt. Ausschließlich doppelte
dekorative Anzeigen ausblenden; genaue Zeiten, Status und Kartenaktion erhalten.
Keine neue Flutterversion, Bibliothek oder fachliche Bewertung eingeführt.

Release91 (22.10.2026): unveränderte fixierte Toolchain Flutter3.47.7,
Dart3.13.5 und go_router18.0.2. Der tatsächlich installierte Routerquelltext
setzt `optionURLReflectsImperativeAPIs=false`; native Push-Prüfungen kontrollieren
deshalb den gerenderten `GoRouterState` statt die absichtlich erhaltene
Grundseiten-URL. Webnavigation verwendet weiterhin den bestehenden `go`-Weg.
Die mobilen gemeinsamen Köpfe verwenden die vorhandene Palette,48px-Ziele und
explizite Zusatzinfos; Desktop- und200-Prozent-Fälle bleiben separat geprüft.

Trial-Schnittstellen wurden gegen den wirklichen FastAPI-Vertrag und additive
Migration0029 geprüft, einschließlich `trial_missing`, konkurrierender
Mailbestätigung, SQL-NULL-Paarprüfung und bestehender Budgetreservierung.
Öffentliche Angebote folgen allein der gespeicherten Katalogfreigabe; die
Betreiberangaben werden laut ausdrücklicher Rückmeldung später nachgereicht.
Die für die Commerce-Oberfläche gelesenen W3C-Primärquellen sind im
[Launchbericht](COMMERCE_LAUNCH_30_DAY_2026_10_22.md) direkt verlinkt.

Eine tatsächliche Produktionssichtprüfung belegte den Schulbuddy-Sendegrund im
eigenen künstlichen Testraum: Backendfreigabe `available=false`. Die UI wahrt
diese Sperre jetzt durch klare Vorschaukennzeichnung und inaktive Eingaben;
freies Demo-KI-Chatten wurde nicht freigeschaltet. Der regulär reservierte echte
Luna/high-Abnahmeaufruf90 bleibt von dieser Bedienprüfung getrennt. Technische
Zitiermarker werden ausschließlich mit serverseitig validierten Quellenchips
abgeglichen. Abnahmegrenzen, Erstfehler und gezielte Nachläufe stehen im
[gemeinsamen Releasebericht](RELEASE_91_2026_10_22.md).

## 22.10.2026 · Tatsächliche mobile Folgekorrrektur92

- Eigener Produktionsbrowser mit320×568,390×844 und1100px: kompakter
  Eltern-Kindkontext und Adminbereich wurden anhand tatsächlich gerenderter
  Kopf-/Reiterhöhen nachgebessert; Vorherbilder und enge Regressionen in
  `artifacts/ux91/`, Arbeits-/Freigabebelege in
  `docs/RELEASE_92_2026_10_22.md`. Diese Stichprobe ist keine vollständige
  WCAG-, Geräte- oder Fachqualitätsabnahme.
- Bestehende gepinnte Flutter-/Dart-/GoRouter-Versionen unverändert; keine neue
  UI-Abhängigkeit oder Providerfreigabe. Der fehlgeschlagene zweite echte
  Sol/max-Reparaturauftrag ist ausdrücklich vom erfolgreichen einzelnen
  Luna/high-Bedienchat und von den ausschließlich lokalen92-Prüfungen getrennt.

Abschluss der lokalen97-Abnahme:446Backendfälle in18Sammlungen bestanden nach
allen drei strengeren Quellen-/Offenlegungsfixes; keine weiteren Modellaufrufe.
571Flutterfälle plus13Zoom-/Referenzfälle (sechs überschneiden sich), Analyse
acht plus zwei betroffener Dateien ohne Befund. Künstliche1440px-/390px-Probe
mit Abspielen, Schrittwechsel, Reglergeste und Tippzuordnung abgeschlossen.
Physische Geräteabnahme und erfolgreiche echte KI-Szenenerzeugung bleiben offen;
Build/Deployment ausschließlich gemäß RELEASE_97_2026_10_23.md bewerten.


## 23.10.2026 · Weitere Aufgabenformen und Patch98

Die [zweite Forschungsrunde](SIMPLECLUB_ROUND_2_2026_10_23.md) unterscheidet
tatsächlich bediente angemeldete Ansichten, ausschließlich öffentliche
Beschreibungen und eigene Vorschläge. Weitere Quelllinks, konkrete Handlungen
und Grenzen stehen dort; keine vollständige Prüfung aller Fachaufgaben behauptet.
Der [Release98-Bericht](RELEASE_98_2026_10_23.md) dokumentiert die vollständige
CI39922708482, mobile Anordnung, SQLite-/PostgreSQL-Regressionen und tatsächliche
Build-/Deploymentbelege. Diese späteren Gesamtnachweise ergänzen die früheren
gezielten97-Testzahlen. Keine weiteren Modellaufrufe oder fremden Assets.


## 23.10.2026 · Zwanzig weitere Lernfunktionen99

[20-Punkte-Liste](LEARNING_ELEMENTS_20_2026_10_23.md) mit direkt bedienten
Referenzen: Lernplan-Vorlagenauswahl, Geschichte-NRW-Vorschau in Desktop/Mobil
und mobile Themeninhalte der Kieler-Matrosenaufstand-Aufgabenrunde. Kein Plan
übernommen und die dort gelesene erste Aufgabe nicht beantwortet. Die vorherige
zweite Runde liefert die weiteren tatsächlich bedienten Aufgabenreferenzen.
Gruppenlupe, explizite Vergleiche und Offen/Bearbeitet sind eigene Ausarbeitungen
dieser Muster; keine identische Referenzfunktion oder vollständige Fachabnahme
behauptet. Keine fremden Assets übernommen.

[Release99](RELEASE_99_2026_10_23.md) enthält vollständige CI, lokale SQLite-/
PostgreSQL-/Flutterproben, schreibgesperrte künstliche Browserfixtures sowie
exakte reguläre Build-, Signatur-, Hash- und SSH-Deploymentnachweise. Keine
weiteren kostenpflichtigen KI-Aufrufe; Modellmocks/Rendererfixtures getrennt
von noch ausstehender echter99-Erzeugungsabnahme.


## 23.10.2026 · Runde100 nach dem99-Deployment

Die [100-Punkte-Liste](IDEAS_100_2026_10_23.md) protokolliert erneut tatsächlich
bediente Desktop-/Mobilansichten: Home, Bibliothek und Sortiermenü, leerer
Karteikarteneditor mit mobiler Vorder-/Rückseite, Politiklesetext, Suchoverlay,
Zahlenstrahl-Aufgabe mit normaler/erweiterter Mathematiktastatur sowie Chemie-
Themen und eine Auswahlaufgabe mit Themenleiste. Keine Referenzantwort bewertet,
kein Karteikartenset gespeichert und keine fremden Assets übernommen. Die100
Funktionen sind eigene Ausarbeitungen aus diesen und den früheren beobachteten
Mustern; keine Behauptung vollständiger Untersuchung sämtlicher Fachaufgaben.

Prüf- und Veröffentlichungsstand: [RELEASE_100_2026_10_23.md](RELEASE_100_2026_10_23.md).
In dieser Runde keine zusätzliche Modellanfrage; künstliche Rendererbeispiele
und Widgettests bleiben von einem echten KI-Erzeugungsnachweis getrennt.


### Ergänzung101 ·23.10.2026

Eigene Korrektur nach der konkret gemeldeten blockierten Lernrunde und der
Materialansicht im Browser. Keine neuen Fremdassets oder Anbieteraufträge.
Der bestehende Quellen-/Darstellungsvertrag bleibt maßgeblich; Quellenblöcke
werden nur bei exakter Rekonstruktion des unveränderten Originaltexts verwendet.
Nachweise und Grenzen: [RELEASE_101_2026_10_23.md](RELEASE_101_2026_10_23.md).


### Rollenübergreifender Designumbau102 ·23.10.2026

Erneut tatsächlich im angemeldeten Browser betrachtet: Simpleclub-Home bei
1280×800 und390×844px, mobile Bibliothek und mobiler Lernplandialog. Letzterer
wurde ohne Speicherung geschlossen. Referenzen: https://app.simpleclub.com/home
und https://app.simpleclub.com/library. Kompakte Kopf-/Such-/Aktionszeilen und
offene Abschnittshierarchie dienen als Muster für eigene Komponenten; keine
fremden Texte, Icons, Schriftdateien oder Bilder in das Produkt übernommen.

[47-Routen-Inventar](COMPACT_DESIGN_102_2026_10_23.md) erfasst Kinder-, Eltern-,
Admin- und öffentliche Seiten. Quellprüfung, synthetische Browserfixtures,
Widgettests und spätere reguläre Veröffentlichung sind getrennte Belege.
Keine zusätzliche Modellanfrage oder physische Geräteprüfung in dieser Runde.


### Informationshierarchie103 ·24.10.2026

Erneut tatsächlich im angemeldeten Simpleclub-Browser betrachtet: Bibliothek
bei 390 × 844 und 1280 × 800 mit leeren gespeicherten Karteikarten sowie
Energieerhaltungsthema und sichtbarer Aufgaben-Einstieg. Der erneute Übungsstart
wurde vom automatischen Freigabecheck abgelehnt; keine Antwortprüfung dieser
Referenzrunde und kein befülltes Kartenset behauptet. Einstiegspunkte:
https://app.simpleclub.com/home und https://app.simpleclub.com/library.
Schmale Iconnavigation, kurze Detailköpfe und Inhalt vor Zusatzwerkzeugen dienen
als Muster für eigene Komponenten; keine fremden Assets, Inhalte oder
Schriftdateien übernommen.

[47-Routen-Inventar](CLEAR_LAYOUT_103_2026_10_23.md) und
[Release103](RELEASE_103_2026_10_24.md) trennen Quellprüfung, 195 neue Widgetfälle,
synthetische schreibgesperrte Browseransichten, vollständige CI und gebundene
Veröffentlichung. Nach Deployment wurde der Englisch-Fachhefter im Bestandskonto mit ausdrücklich
als künstlich beschrifteter Seite mobil und am Desktop ausschließlich lesend
geprüft; private Bilder danach gelöscht. Kein Produktionspostflight
der Wörterseite, keine inhaltliche Abnahme befüllter Sprachwerkstatt-, Lernstand-
oder Heftsammlungsansichten. Keine zusätzliche Modellanfrage, Referenzassets oder
physische Androidgeräteprüfung in dieser Runde. Persistente Lernbelege bleiben
davon getrennt.


### Gemeinsame Seitenoptionen104 ·24.10.2026

Die angemeldete Simpleclub-App wurde sichtbar bei390×844 anhand27unterschiedlicher Funktionsansichten/Bedienzustände untersucht: https://app.simpleclub.com/library, https://app.simpleclub.com/learning-plan-templates, https://app.simpleclub.com/search, https://app.simpleclub.com/topic/vwYaXbxOe0pD0CXOv8ed und Profil/Einstellungen. Tatsächliche Referenzbelege, erlaubte lesende Alternativen zu abgelehntem Speichern/Übungsstart und Grenzen führt [MOBILE_CONCEPT_104_2026_10_24.md](MOBILE_CONCEPT_104_2026_10_24.md). Keine fremden Inhalte/Assets übernommen. Eine eigene transparente PNG entstand mit dem eingebauten Bildwerkzeug; [vollständiger Prompt und Herkunft](ILLUSTRATION_104.md).

[Release104](RELEASE_104_2026_10_24.md) bindet tatsächliche CI40044265906, reguläre Artefakte, öffentliche Hashvergleiche und SSH-Nachprüfung an `e58984ebd3fc9462044264dbcaa23d9c51ba66c9`. Künstliche Browserdaten, lesender Produktionshefter, Widgettests und echte KI-Erzeugung werden getrennt; keine neuen Provideraufrufe oder physische Androidabnahme dieser Runde. Private Profil-/Produktionsbilder gelöscht, vorübergehende Viewports zurückgesetzt.


### Eigene Marke und beweglicher Schulbuddy105 ·24.10.2026

Die neuen transparenten Figuren und Headergrafiken wurden mit dem eingebauten Imagegen erzeugt beziehungsweise aus eigenen Referenzgrafiken abgeleitet. Vollständige Prompts, Referenzen, Master-/Runtimehashes und verworfene Entwürfe: [LOGO_105.md](LOGO_105.md), [HEADER_GRAPHICS_105.md](HEADER_GRAPHICS_105.md). Keine Simpleclub-Assets, fremden Schriftdateien oder persönlichen Fotos übernommen. Schulbuddy behält ausdrücklich Flügel, Buchseiten, Arme und Antrieb. Die lokale achtteilige Startupfolge läuft endlich in Flutter; kein zusätzlicher Animationsdienst.

Der tatsächliche Flutter-Webdateiimport deckte einen im gepinnten SDK nicht unterstützten ImageDescriptor-Abmessungszugriff auf. JPEG-/PNG-/WebP-Header werden nun vor Pixeldekodierung mit der bereits fixierten image 4.12.0 gelesen. Reale lokale Dateiauswahl und nicht gespeicherte Vorschau wurden im Browser bedient; erfolgreicher Serverupload ist getrennt durch Backend-/Widgettests belegt. Avatarbilder bleiben privat und werden nicht an KI gesendet.

[Release105](RELEASE_105_2026_10_24.md) bindet CI 40078603562, reguläre Artefakte, öffentliche Hashvergleiche, Schema 0032 und SSH-Nachprüfung an `7ba70c8a8bdc83aa3493b31c4cb4b9fcca02a567`. Anschließender Livebrowser: Kinder-Heute, Mathematikhefter mit bleibender Navigation, schwebender Buddy/Chat/Andocken, Logorückweg, Geräte-/Profilreiter. Temporäre Viewports zurückgesetzt, eigene Vorschau beendet, keine Produktionsfotoänderung oder neue Modellanfrage. Native JUnitressourcenprüfung und gescheiterter TCG-Emulatorlauf werden ausdrücklich von einer physischen Geräteabnahme getrennt. Diese Runde behauptet keine erneute vollständige Simpleclub-Recherche oder fachliche KI-Abnahme.

Klassenarbeiten und Schulbuddy24.10.2026 · Umsetzung1.32.0+106:
Der Ausbau folgt dem ausdrücklichen Betreiberauftrag für LK-/KA-Vorbereitung,
Fotoimport zurückgegebener Arbeiten, individuelle Aufgabenmengen und aktuellen
Schulbuddy-Seitenbezug. Keine neue Simpleclub-Inhaltsübernahme oder Behauptung
einer vollständigen Fachabnahme. Gemeinsame vorhandene Gestaltung, lokale
Nunito-Schrift und fachliche Flutter-Renderer bleiben maßgeblich.

Primäre Implementierungsbelege: [EXAMS.md](EXAMS.md),
[SCHULBUDDY.md](SCHULBUDDY.md), [NOTIFICATIONS.md](NOTIFICATIONS.md),
`backend/schulpilot/exams.py`, `exam_review.py`, `schulbuddy_exams.py` und die
entsprechenden API-/Worker-/Flutter-Gegenproben. Künstliche Browserdaten und
Provider-Mocks sind keine echte OCR-/LLM-Qualitätsprüfung. Versionsgebundene
Releasebelege werden nach ihrer tatsächlichen Ausführung ergänzt.

106-Verfügbarkeitskorrektur: Die kostenlose Statusprojektion prüft die Reserve
der tatsächlich bevorstehenden ausgewählten OCR-/Paketroute. Eine größere
Basisreserve darf weder den Wiederholungsbutton verdecken noch die kostenlose
Quellenprüfung sperren. Lernzeit-Mindestziele und finanzielle KI-Limits bleiben
getrennt; bestehende Grenzen werden durch diese Korrektur nicht angehoben.

## Release 106 – 24.10.2026

Klassenarbeitsvorbereitung, private Arbeitsanalyse und korrekt vorgeprüfte
Quellenwiederholung: Produkt `8659115f8648d6134937ccd5f63948581abad28f`;
Live-Abnahme, CI, Signaturen, Hashes und Grenzen in `docs/RELEASE_106.md`.


## Quellen, Erklärgrafiken und Kinderkosten107 · 24.10.2026

Implementierung1.33.0+107: [VISUAL_REFERENCES.md](VISUAL_REFERENCES.md) und
[CHILD_COST_CONTROLS.md](CHILD_COST_CONTROLS.md) dokumentieren Rezeptregister,
Quellenbindung, grafische Schritte, tatsächliche Lernbelege und die verbindliche
Kostenpolicy. Migrationen0035–0038 erweitern die bestehende Architektur.

Die angemeldete Simpleclub-Webapp wurde tatsächlich im Browser betrachtet:
Brüche unter https://app.simpleclub.com/topic/vwYaXbxOe0pD0CXOv8ed und Simple past
unter https://app.simpleclub.com/topic/gKTuprR1iimrnjpn5esd . Desktop- und
390×844-Ansichten zeigen große fachliche Grafiken, kleine geführte Schritte,
bleibende Antwortfeedbacks und den kontextbezogenen Tutor. Simple-past-Antworten
wurden nach ausdrücklicher Freigabe im Referenzkonto abgesendet. Fremde Texte,
Grafiken, Icons und Schriftdateien werden nicht in das Produkt übernommen.

Aktuelle Primärdokumentation für die Modell-/Bildprüfung:
https://developers.openai.com/api/docs/guides/images-vision ,
https://openrouter.ai/docs/guides/best-practices/reasoning-tokens ,
https://openrouter.ai/docs/guides/routing/provider-selection und
https://openrouter.ai/docs/api/api-reference/generations/get-generation .
Abgerufene Modellmetadaten sind kein praktischer Qualitätsnachweis.
Vor diesem Produktcommit wurden keine neuen externen Modellaufrufe durchgeführt;
Regressionen und lokale Browserfixtures sind davon getrennt.

Lokaler PostgreSQL16-Lauf:264 bestandene Fälle ohne Überspringen, einschließlich
Migration0034↔0038, Kosten, Quellen, Grafikpositionen, Einstieg und Tutorbindung.
Die unveränderte Produktionsquellmenge dieses Laufs trägt SHA256
`c4514869bed805db00009eb9b6509b30d8c271eaa0c65d2a4283594954da7fe9`,
die Testmenge `3fe33fd84da412c7a32ef4c6da14bbb0b1711d0f3fdf3478d496707512de7189`.
Vollständige CI, gebundene Builds, Liveprüfung und beobachtete Grenzen werden
nach tatsächlicher Ausführung im Releasebeleg ergänzt.


## Fotoverarbeitung und Arbeitsbesprechung108 · 24.10.2026

1.33.1+108 behält Schema0038 und alle Finanzgrenzen bei. Bild-Base64 ist ein
Transportformat und kein Texttokenstrom. Die neue optional freigegebene,
versionierte Bildzulage ist ausdrücklich eine **Betreiberschätzung**, keine
behauptete modellgenaue Tokenformel oder garantierte Rechnungsobergrenze.
Ohne exakt zum geprüften Modell und Upstream passendes Profil bleibt der alte
konservative Pfad erhalten. Tatsächliche OpenRouter-Belege und Notfallstopp bei
Überschreiten der Reservierung bleiben maßgeblich.

Am24.10.2026 tatsächlich gelesene Primärquellen:
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/image-cost-calculator
- https://developers.openai.com/api/docs/models/gpt-6.1-sol
- https://developers.openai.com/api/docs/models/gpt-6-luna
- https://openrouter.ai/docs/guides/overview/multimodal/image-understanding
- https://openrouter.ai/api/v1/models/openai/gpt-6.1-sol/endpoints

Die geladene Bildregel-Tabelle enthält keine explizite GPT-6.1-Sol-/GPT-6-Luna-
Tokenformel. Die Regel eines anderen Modells wurde deshalb nicht als ihre
Preisgarantie übernommen. Der aktuelle ausgewählte Azure-Endpunkt weist
2USD/Million Eingabe- und10USD/Million Ausgabetokens aus; dies sind Metadaten,
kein praktischer Erkennungsqualitätsnachweis.

Neue OCR-Aufträge verwenden kompakte Metadatenschlüssel und zusammenhängende
Absatz-/Listenblöcke. Öffentliche und gespeicherte Quellen bleiben im bisherigen
Format; Inhalt, Einrückung, Bruch-/Relationszeichen und sichtbare falsche
Schülerantworten werden nicht gekürzt oder fachlich ersetzt. Nachweislich nicht
versendete, kostenfreie Aufträge zählen nicht als verbrauchter Anbieter-Versuch;
ihr Verlauf und sämtliche Startzähler bleiben erhalten.

Neue Arbeitsbesprechungen liefern kleine vollständige Aufgabenauszüge statt
biszuacht langer Aufgaben in einer Antwort. Weitere Auszüge bleiben bewusstes
Handeln. Die pauschale Tutor-Begrenzung2600 schneidet eine Analyse nicht mehr
unterhalb ihrer bereits konfigurierten Obergrenze ab. Alte Berichte bleiben lesbar.

107-Abschlussbeleg: exakter Produktstand553a21d92b59a64ca2a9bfa1a72e5306e89942d5,
CI40096202033 erfolgreich mit2708Backendfällen/36übersprungen und3482Flutterfällen/
19übersprungen. Gebundener sauberer Build df6cc7f6495ff3a077be4673be770d87;
öffentliche APK107 und Web-JavaScript stimmen mit den lokal geprüften Artefakten
überein. Migration0038, fünf eigene Dienste aktiv, bestehende17geschützte
Konfigurationen und Google-Verifikation erhalten. Kein Nachweis tatsächlicher
Android-Hintergrundzustellung oder nativer Tastaturbedienung ohne echtes Gerät.

## Eltern-Lernhinweise und kleine Arbeitsauszüge109 · 24.10.2026

1.34.0+109 ergänzt persönliche Elternregeln und die additive Migration0039.
Grundlagen und Rechte stehen in [NOTIFICATIONS.md](NOTIFICATIONS.md). Der
bestehende Worker prüft tatsächlich gespeicherte Lernzeit und heutige gültige
Klassenarbeitstermine. Gerätefreigabe, Ruhezeiten und neutraler Firebase-Inhalt
bleiben getrennt von der gespeicherten In-App-Meldung. Keine neuen Dienste.

[EXAMS.md](EXAMS.md) beschreibt die begrenzten Arbeitsauszüge: klare vollständige
Teilzeilen können einzeln ausgewählt werden, ohne bei unsicheren Nachbarzeilen
den gesamten Sammelauftrag zu verwerfen. Wörtliche Quellen, alte Antworten und
belegte Lehrerrollen bleiben verbindlich. Die Änderung erzwingt weder eine
Mindestaufgabenzahl noch eine erfundene fachliche Korrektur. Schema-, Kosten-,
Versuchs- und Ausgabegrenzen bleiben erhalten.

108-Abschluss: Produkt68c6cf0c00dbb08076e5cb5c9ce0726bc350d8ea,
CI40100425016 erfolgreich mit2762Backendfällen/36übersprungen und3482Flutterfällen/
19übersprungen. Gebundener sauberer Build9fb6faa0e94d861bc97c9c095594b150;
öffentliche APK108 und Web-JavaScript stimmen mit den geprüften Artefakten
überein. Schema0038, fünf eigene Dienste aktiv,17geschützte Konfigurationen und
Google-Verifikation erhalten. Die ausdrücklich freigegebene echte Fotoverarbeitung
wurde im Browser erneut gestartet und kam zur Quellenprüfung zurück. Die
anschließende erste Arbeitsanalyse lieferte einen gültigen, aber leeren Auszug;
dies ist kein erfolgreicher Nachweis vollständiger Nacharbeit. Genau diese
beobachtete Auswahlgrenze ist der Anlass der Teilzeilenregeln in109.

Die lokalen109-Transport-/API-Tests verwenden künstliche Quellen. Modellqualität,
Desktop-/Mobilbrowser und native Zustellung werden nur nach tatsächlich erfolgter
Beobachtung als geprüft bezeichnet; die nachfolgende Veröffentlichung erhält
separate versionsgebundene Belege.

Gezielte lokale109-Abnahme:166bestandene PostgreSQL16-Fälle einschließlich
0038→0039-Migration, Arbeitsauszügen und Elternregeln;35bestandene aktuelle
Flutterfälle für Auszüge/Elternformular, zusätzlich bereits24bestehende
Glocken-/Posteingangsfälle. Flutter-Analyse und Ruff ohne Befund. Die bekannten
16geschützten lokalen Geheimnisquellen wurden vor Commit ohne Fund geprüft.
Dies ersetzt weder die vollständige CI noch die nachfolgende Browserabnahme.

Nachtrag vor109-Veröffentlichung: Entzug und unmittelbarer Wiedereintritt ohne
Workerlauf konnten eine alte Elternregel erhalten. Der Entzug deaktiviert sie
nun unter denselben Kindersperren wie ein Speicherversuch; Revisionen steigen,
historische Ereignisse bleiben erhalten. Beide neuen Regressionsfälle waren
vorher rot. Danach76SQLite- und82PostgreSQL16-Fälle bestanden.

Das Elternformular wurde im echten Browser bei390×844 und1102×884 geprüft:
bewusst gespeichert, Bestätigung sichtbar, Serverereignis in der Glocke geöffnet.
Zwei lokale Sweeps erzeugten genau ein Ereignis, ohne Providerverbrauch,
Push-Gerät oder FCM-Aufruf. Dies ist keine native Zustellabnahme.

Weitere Livegrenze bleibt getrennt offen: Nach abgeschlossener Quellenprüfung
wurde ein großer Paketauftrag vor Versand durch die bestehende konservative
Kostenvorprüfung blockiert. Dessen Anfrage enthielt131697Textbytes und lag mit
projizierten311586µUSD über der150000µUSD-Reservierung. Das ist kein Kinderlimit.
Dieser kostenfreie Nichtversand ist weder erfolgreiche Paketerstellung noch
ein Anlass, Budget-/Ausgabegrenzen stillschweigend zu erhöhen. Die Anfragegröße
wird separat untersucht.

Die tatsächliche Veröffentlichung109, vollständige CI40105765457, reguläre
signierte Artefakte, öffentliche Hashvergleiche und unveränderte geschützte
Konfiguration sind im [Release109-Beleg](RELEASE_109_2026_10_24.md) dokumentiert.

## Pakettransport110 · 24.10.2026

1.34.1+110 verwendet [package-wire-2](PACKAGE_TRANSPORT.md), ohne Migration oder
neue Abhängigkeit. Die vorhandene Startprüfung und Reservierung bleiben bestehen.
Referenzaufgelöste Schemavergleiche, drei echte Adapter-Mocks, exakte Unicode-
Quelltexte, gruppengebundene Verweise und vollständig rückführbare Eingabetabellen
werden mit künstlichen Daten geprüft. Eine OpenAI-Choice-Regression wurde im
Peerreview gefunden und vor Integration mit explizitem String-/Indexvertrag
korrigiert. Keine Antwortvalidierung wurde dafür gelockert.

Der autorisierte reale RAM-Vergleich wurde ohne Anbieteraufruf und ohne DB-Write
mit aktuellem Quellen-/Familien-/Planungsstand durchgeführt: gleicher kanonischer
Workerpayload, 131741→50569 Transportbytes, konservative Projektion
311674→149330µUSD bei unveränderter150000µUSD-Reserve. Das belegt nur die
Vorprüfung dieses konkreten aktuellen Auftrags, keinen historischen Vollreplay,
garantierten Rechnungspreis oder erfolgreichen Modelloutput. Der enge verbleibende
Spielraum und größere weiter gesperrte künstliche Fälle sind ausdrücklich erhalten.

Die Nacharbeitsansicht zeigt ihre aktuelle Aufgabenanzahl und den letzten
erfolgreichen Auszug aus gespeicherten Fakten; der erste Modellbericht bleibt
historisch erhalten. Ein leeres unverändertes Antwortfeld behauptet keinen
gespeicherten Entwurf. Lokale Prüfungen, vollständige CI, Build und anschließende
Live-Erzeugung werden als getrennte Nachweise geführt.

Der eingefrorene Transportstand bestand258SQLitefälle (ein PG-spezifischer
Fall übersprungen) und131isolierte PostgreSQL16-Fälle. Die Nacharbeitsprojektion
bestand54SQLitefälle. Im integrierten Hauptstand bestanden30Flutterfälle der
Prüfungsansicht; Flutter-Analyse und Ruff ohne Befund. Diese gezielten Prüfungen
sind kein Ersatz für die nachfolgende vollständige CI und Liveabnahme.
Die integrierten Transport-, Reparatur- und Auszugsfälle bestanden anschließend
gemeinsam96SQLiteprüfungen. Ein vorheriger Lauf im eingeschränkten lokalen
ASGI-Testtransport wurde unterbrochen; erst der erneute vollständige Lauf mit
den vorhandenen TestClient-Berechtigungen ist der96er-Ergebnisbeleg.

Tatsächlicher Volltest40114809881 auf cc6f6a1: Backend2915bestanden,
37übersprungen und2veraltete Testzugriffe auf den internen Namen
`$defs.GroundedQuestion`; die vorherigen fachlichen Match-/Ablehnungsassertions
bestanden. Flutter3511bestanden/19übersprungen, Analyse und Webbuild grün.
Der anschließende reine Testfix löst Referenzen über den bestehenden Helper auf
und erhält sämtliche bisherigen Wertebereichs-/Antwortassertions; alle37Fälle
der Szenentestdatei bestanden danach. Er ändert keine Produktdatei.

110 wurde mit unverändertemSchema0039 aus cc6f6a1 veröffentlicht; öffentliche
APK/JavaScript, Signatur und17geschützte Konfigurationen wurden nachgeprüft.
Der einmal bewusst gestartete reale Reparaturauftrag erreichte den Anbieter,
wurde aber als `invalid_output` abgewiesen. Eine erfolgreiche Paketerstellung
ist deshalb weiterhin NICHT belegt.4000gemeldete Ausgabetokens allein beweisen
weder den genauen Ablehnungsgrund noch eine tatsächlich gespeicherte Lernrunde.
Kein blinder weiterer Modellaufruf und kein Aufweichen der Aufgabenprüfung.

Ein anschließend ausschließlich lesend abgerufener OpenRouter-Generationbeleg
bestätigte für genau diesen Auftrag66870µUSD sowie `finish_reason=length` und
`native_finish_reason=max_output_tokens`. Die native Ausgabe umfasste4000Tokens,
davon1552Reasoningtokens. Damit ist die Längenbegrenzung für diesen einzelnen
Auftrag jetzt tatsächlich belegt. Der Abruf erzeugte keinen Modellaufruf und
keine Änderung an Kinder-/Lerndaten. Die bisherige Rechnungssumme dieser
Arbeitseinheit beträgt164064µUSD; weitere reale Erzeugung wurde nicht gestartet.

## Bedarfsgerechte gemeinsame Bausteine111 · 24.10.2026

Der weitere Ausbau folgt dem ausdrücklichen neuen Betreiberauftrag: öffentliche
Lernbausteine bei Bedarf erzeugen, versioniert speichern und über Konten hinweg
wiederverwenden, statt alle Referenzportalthemen manuell nachzubauen. Der Vertrag
und seine Grenzen stehen in [GENERATED_LEARNING_ASSETS.md](GENERATED_LEARNING_ASSETS.md).
Private Heftinhalte und Lernbelege werden nicht global veröffentlicht.

Die gemeinsame Flutter-Ansicht verwendet vorhandene Renderer und kontogebundene
GET-Wiederaufnahme. Vierzehn gezielte UI-Fälle bestanden einschließlich bewusster
Erzeugung, unveränderter Wiederholungskennung bei unklarem Transport, altem
Kontokontext, nachgeladenen öffentlichen Themen und320/390/800/1280Pixeln bei
200Prozent Schriftgröße. Fehlerstatus sowie überdeckte Route und Hintergrund
wurden zusätzlich geprüft. Analyse der betroffenen Oberfläche ohne Befund.
Die bestehende Workspace-Navigation bestand zusätzlich14Fälle. Der neue
Zoom-Tutor wurde mit aktiver Tutorscope auf tatsächliche Erreichbarkeit,
Bildschirmgrenzen und Klick geprüft; ein vorheriger Testfinder hatte nur seine
Existenz gezählt und wurde entsprechend präzisiert.
Diese Nachweise verwenden künstliche Daten; sie belegen keinen echten neuen
Sol-Erfolg und keine vollständige fachliche Abnahme aller Themen.

Der eingefrorene Backendpfad bestand33PostgreSQL16-Fälle einschließlich echter
Alembic0039→0040-Prüfung und109Nachbarfälle zu Provider, Routing, Referenzen,
Grafikaufträgen und Export. Der erste SQLite-Gesamtlauf hatte31Erfolge und zwei
Testfixturefehler; nach deren enger Korrektur bestanden fünf gezielt frisch
ausgeführte SQLite-Fälle. Der integrierte Hauptstand bestand vier zusätzliche
Adapter-/Vertikalprüfungen mit isolierter SQLite-Datenbank. Keine dieser
Modellantworten stammte aus einem echten externen Aufruf.

Die zusätzliche Buddy-Anbindung bestand26SQLite- und26PostgreSQL16-Prüfungen,
darunter sieben neue Fälle sowie vorhandene Kontext-/Grafikfälle. Ein separates
Zehnergate auf PostgreSQL undSQLite prüfte die Asset-Wartung und verspätete Kostenbelege:
Ein terminaler Auftrag bleibt terminal, seine Generationkennung bleibt für den
normalen Preisabgleich erhalten. Modell-/Metadatenaufrufe waren dabei gemockt.

Der erste Volltest40124457196 meldete im Flutterlauf3522bestandene,
19übersprungene und drei fehlgeschlagene Fälle: Der neue zusätzliche
Grafikeinstieg verdrängte auf kleinen Bildschirmen den ersten Inhalt und die
dritte Runde. Der Einstieg wurde deshalb in das bestehende Drei-Punkte-Menü
verlegt; die bestehenden Dichtegrenzen bleiben unverändert. Ein zusätzlicher
Test prüft den bewusst geöffneten Menüeinstieg ohne neue API-Aufträge.

Das vollständige Backendlog desselben Laufs erreichte vor dessen Abbruch
2963Erfolge und37übersprungene Fälle. Ein Migrationstest scheiterte, weil sein
Python-Unterprozess den nur pytest-intern gesetzten Importpfad nicht erbte.
Der Test setzt nun den absoluten Backendpfad ausdrücklich für den Unterprozess;
Migrations-DDL und Produktcode bleiben dabei unverändert. Lokale Prüfläufe mit
geerbtem PYTHONPATH hatten diesen Testumgebungsfehler zuvor verdeckt.
Der korrigierte tatsächliche SQLite-Upgradefall bestand anschließend mit
ausdrücklich entferntem äußerem PYTHONPATH. Die54gezielten UI-Fälle zu Dichte,
Runden und Entdecken bestanden nach Korrektur des neuen nativen
Navigationstestfinders; Flutter-Analyse ohne Befund.

Der abschließende Volltest [40126614437](https://github.com/meinzeug/schulpilot/actions/runs/40126614437)
auf `47bcc026e538bdd5bdbd5ba3615d9db0c9db5c9b` bestand2964Backendfälle
(37übersprungen) und3526Flutterfälle (19übersprungen), einschließlich Analyse
und Webbuild. Genau dieser Stand wurde als1.35.0+111 mit Schema0040
veröffentlicht. Gebundene Release-/Signatur-/Byteprüfungen liegen lokal unter
`artifacts/elements111`; Konfigurationen blieben unverändert.

Anschließend wurde der zusätzlich ausdrücklich freigegebene einzelne reale
Sol-Aufruf ausschließlich mit dem öffentlichen Bruch-Grundwissen ausgeführt.
Er erzeugte „Brüche: Teile eines Ganzen“ mit dem Beispiel3/8. Im echten
Produktionsbrowser wurden Kreis/Balken, Nennerphase, Zoom und der erreichbare
Tutor mit passendem Beispielkontext geprüft; keine Chatfrage und keine
Aufgabenantwort wurden abgesendet. Die ursprüngliche Balken-/Phasenansicht
blieb nach dem Schließen von Zoom und Tutor erhalten. Die tatsächlichen
Kosten dieses Aufrufs betrugen10930µUSD laut Generation-Kostenbeleg.
Ein zweiter bewusster Abruf derselben öffentlichen Spezifikation verwendete
denselben Build, dieselbe Referenz und denselben Kostenbeleg: genau ein
Auftrag/ein Verbrauchsbeleg, zwei private Instanzen, keine weiteren KI-Kosten.
Damit ist die Wiederverwendung im selben echten Konto belegt;
familienübergreifende Parallelität wurde ausschließlich künstlich geprüft.

Die technische Validierung ersetzt keine fachliche Redaktion: der Baustein
bleibt ausdrücklich ungeprüft und auf Erkundung begrenzt. Lokale Grafikphase
und veränderte Parameter werden derzeit noch nicht vollständig an den Tutor
übertragen oder geräteübergreifend gespeichert. Die Arbeitseinheit verbrauchte
insgesamt174994µUSD von ausdrücklich freigegebenen400000µUSD; die Erlaubnis
für genau diesen zusätzlichen realen Aufruf ist verbraucht. Daraus folgt keine
Freigabe für weitere Modellaufrufe oder ein erfolgreicher Reparaturnachweis des
zuvor an4000nativen Ausgabetokens gescheiterten privaten Lernpakets.

## Gemeinsame Integration112 · 24.10.2026

Die vorhandenen Profile, Rollenansichten und Renderer wurden gezielt ergänzt:
explizites Bundesland-/Schulformprofil, öffentliche Lehrplanmetadaten, zwei
endliche eigene Lernlabore und administrative Kontometadatenverwaltung.
Aktuelle Erinnerungs-/Push-, Kosten-, Quellen- und Shared-Assetpfade aus111
bleiben erhalten. Die additive Kette lautet0039→0040→0041→0042.
Bestand, Herkunft und erhebliche Abdeckungslücken der58Dokumente/766Zuordnungen
stehen in [CURRICULUM.md](CURRICULUM.md). Dies ist kein vollständiger Lehrplan
für alle deutschen Schularten, Fächer und Klassen und keine766Animationen.

Die eigenen Kraft-/Bewegungs- und Satzgliedlabore verwenden finite fachliche
Modelle mit Touch-/Tastaturbedienung, begrenzter Zustandswiederaufnahme und
geprüftem Tutorkontext. Vertrag, Quellenbindung, eigene Bildherkunft und Grenzen:
[LAB_VISUALS_109.md](LAB_VISUALS_109.md). Labrezepte sind im öffentlichen
Shared-Assetgenerator ausdrücklich ausgeblendet und vor einer kostenpflichtigen
Reservierung gesperrt, solange dessen eigener Ausgabevertrag sie nicht trägt.
Der reguläre quellgebundene Laborpfad bleibt erhalten.

Die neue Adminverwaltung zeigt paginierte Eltern-/Kinderverknüpfungen und
Kontometadaten; sie erteilt keinen privaten Material-, Noten-, Antwort- oder
Chat-Zugriff. Bearbeiten, Sperren, Sitzungswiderruf und gebundene Löschvorschau
verwenden frische Rollen-/Sitzungsprüfung, Revision, monotone Kontoversion,
Idempotenz, stabile Sperrreihenfolge und bestehendes Löschjournal. Auf Produktion
wurde dafür kein fremdes Konto gesperrt oder gelöscht.

Lokale gemeinsame Gates vor dem Release:163PostgreSQL16-Feature-/Rechte-/Racefälle,
zusätzlich je sieben echte additive Kettenfälle aufPostgreSQL16 undSQLite.
Erhalten wurden künstliche Altantworten, Unicode, gemessene Zeit, Erinnerungen
und nach0040eingefügte gemeinsame Bausteine; wiederholte Seedläufe blieben
idempotent. Der absolute Alembic-Unterprozessimport wurde danach auch ohne
geerbtes PYTHONPATH separat geprüft. Ein unabhängiger statischer Review fand
keinen weiteren konkreten Blocker; dies ist keine umfassende Sicherheitsabnahme.

Die gemeinsame Flutter-Integration bestand zunächst220Fälle. Nach der engen
Verdichtung geöffneter Grafikbausteine bestanden106gezielte Folgefälle für
Grafikpriorität,320/390Pixel, große Schrift, Navigation, Zoom und Kontokontext.
Ein tatsächlich gescrollter Auswahlbereich hatte beim Öffnen das Beispiel
oberhalb des sichtbaren Bereichs begonnen. Eine an Kind/Instanz gebundene
Seitenkennung setzt nur beim Instanzwechsel zurück; Aktualisieren derselben
Instanz und Zoom erhalten Scrollposition und Erkundung. Beide Regressionen sind
ausgeführt. Analyse nach enger Testklammerkorrektur ohne Befund. Ein erster
Folgelauf hatte zusätzlich zwei von Root falsch benannte, nicht vorhandene
Testdateipfade; der vollständige106er-Nachlauf verwendete die echten Dateien.

Im echten lokalen Browser mit ausschließlich künstlichen Konten wurden Profil
und Adminmetadaten gespeichert sowie beide Labore im normalen Kinderzugang
bedient. Im Kraftlabor änderte2→2,5kg bei1m/s² die Kraft2→2,5N, während bei
0,5s der Weg0,125m blieb. Die ganze Wortgruppe „am Morgen“ wechselte an den
Satzanfang; „liest“ blieb an zweiter Satzgliedposition. Der Tutor öffnete mit dem
passenden Deutschthema; mangels lokaler Providerkonfiguration wurde keine Frage
gesendet. Browserfixtures belegen keine echte KI-Erzeugung dieser Labore und
keine Reparatur von Junas Paket.

Für die tatsächlich belegte Outputbegrenzung wurde zusätzlich
[package-output-1](PACKAGE_OUTPUT_TRANSPORT.md) integriert: kürzere Feldnamen
und ausschließlich bewiesene Konstanten werden vor allen bisherigen kanonischen
Prüfungen verlustfrei rekonstruiert. Medium,4000Ausgabetokens, Quellen, Fragezahl,
Reservierung und genau ein Anbieteraufruf bleiben unverändert. Künstliche
sechsfragige Roundtrips mit zwei Fächern sanken13989→9472UTF8bytes; das ist keine
Token-, Kosten- oder Erfolgszusage für das echte Paket. Der isolierte Codec
bestand36SQLitefälle und192verschiedenePostgreSQLfälle; letztere bestehen aus
191Erfolgen im breiten Lauf und einem korrigierten alten Schema-Testfinder im
gezielten Nachlauf, keinem behaupteten einzelnen192/192-Lauf. Zusätzliche
Codec/Lab-Adapterfälle prüfen beide Rezepte und die fehlende Clientfähigkeit.
Es gab keinen neuen realen Anbieteraufruf für diesen Fix.

Der gemeinsame19-Dateien-PostgreSQLlauf erreichte347Erfolge und26Fehler:
25alte Paketfixtures hatten keinen expliziten Zugriff auf das unkonfigurierte
Schulprofil; ein alter Szenentest erwartete Labore ohne Clientfähigkeit.
Nach ausschließlich diesen beiden engen Fixturekorrekturen bestand der frische
92-Fälle-Nachlauf vollständig. Damit sind373verschiedene Fälle über beide
Läufe belegt, kein einzelner373/373-Lauf. Ein zuvor extern mitSIGTERM beendeter
Nachlauf und ein gleichzeitig beendeter Flutterbuild sind ausdrücklich keine
Erfolgsnachweise. Produkt- und Migrationshashes blieben unverändert; Ruff des
integrierten Hauptstands ist sauber.

Der erste vollständige112-CI-Lauf40131354680 auf `b56c6a4` bestand3669Flutterfälle
(19übersprungen), Analyse und Webbuild. Der Backendlauf wurde nach25Minuten
bei74Prozent abgebrochen. Vor dem Abbruch waren bereits drei Fehler markiert;
daraus wird ausdrücklich kein grüner Backendnachweis abgeleitet. Die reine
Sammlung ordnete diese den Fällen zur Mitelternlöschung, Pipeline-Migration und
öffentlichen Zahlungsformularen zu. Alle drei Fehler wurden gezielt reproduziert:
eine globale, zwischen Tests erhaltene signierte Löschhistorie; die zwei zusätzlich
gesäten Labreferenzen; eine gültige zufällige CSP-Kennung mit doppeltem Unterstrich.
Die engen Testkorrekturen prüfen nur neu hinzugekommene verifizierte Löschbelege,
weiterhin die exakte vollständige Referenzliste und tatsächlich unersetzte
Vorlagenmarker. Ein eigener Fall erhält CSP-Bindung und Eindeutigkeit bei solchen
Kennungen. Produktcode und Sicherheitsregeln werden dadurch nicht geändert.

Die Backend-Vollprüfung wird im bestehenden25-Minutenlimit auf drei deterministische
Dateigruppen verteilt. Jede Gruppe sammelt zunächst alle Tests, erhält ihre
vollständigen unveränderten Testobjekte samt Fixtures und Marken und dokumentiert
Sammlung, Auswahl und Gegenmenge. Die Gesamtfreigabe benötigt alle drei erfolgreichen
Läufe und die exakte disjunkte Vereinigungsmenge. Auswahlfilter und unvollständige
Sammlungen werden abgewiesen; ein Sammlungsbeleg ist kein bestandener Testlauf.
18datenbankfreie Prüfungen des Runners bestanden vor der echten Gesamtsammlung.
Die drei tatsächlich ausgeführten vollständigen Sammlungen enthalten identische
3209Tests in167Dateien:1064/1276/869ausgewählte Fälle, paarweise disjunkt und
zusammen exakt vollständig. Der gemeinsame Sammlungsdigest lautet
`0ab50e2c60375bc1421d829251083bf2ae33ccb13c7c8e09c0f054605c84d35a`.
Diese drei Collect-only-Läufe führen keine Tests oder Datenbankfixtures aus.

Der zweite112-CI-Lauf40134095078 auf `ae61075` bestand erneut3669Flutterfälle
(19übersprungen), Analyse und Webbuild. Die Backend-Testschritte0und2 waren
erfolgreich; Gruppe1 stoppte bei einem alten Mock des synthetischen
Tagespakettests:975bestanden,11übersprungen,1fehlgeschlagen. Die kanonisch
simulierte Antwort entsprach noch nicht dem tatsächlich angeforderten
`package-output-1`-Transport. Die nachfolgende Fixturekorrektur betrifft nur
die simulierte Anbieterantwort; unbekannte private Zusatzfelder müssen
weiterhin abgewiesen werden und dürfen in Fehlern nicht erscheinen.

Die anschließende Protokollausgabe wurde außerdem durch automatisch aus
PDF-Bytes gebildete Testnamen verzögert: ein Name enthielt6291571Zeichen.
Zwei explizite kurze ID-Listen ersetzen nur diese Namen. Alle acht
Parameterfälle, Bytes, Testkörper und Assertions bleiben identisch; der
vollständige Sammlungsbeleg kann damit weiterhin ohne zusätzlichen
Kompressions-/Transportweg exportiert und exakt verglichen werden.
Die beiden betroffenen gültigen/ungültigen Tagespaketfixtures wurden zunächst
mit zwei Fehlern reproduziert und nach der reinen Mockkorrektur gemeinsam
erfolgreich ausgeführt:2bestanden in31,94Sekunden auf isoliertemSQLite.
Der gültige Fall prüft das erhaltene Fach, die Gruppe und genau beide
Fragen/Antworten; der ungültige Fall bleibt ausdrücklich abgewiesen und
sanitisiert. Provider und Codec sind bytegleich zum bereits geprüften Produktstand.
Die erneuten drei vollständigen Collect-only-Läufe enthalten weiterhin
3209Tests/167Dateien und1064/1276/869ausgewählte Fälle, exakt disjunkt und
vollständig. Ihre nur durch kurze Testnamen geänderten Receipts sind je rund
812KB groß; gemeinsamer neuer Sammlungsdigest:
`cda5a790acd9b4ddee7d6effcc2814d0112e1243d769e320c65a6ae758d32911`.

Der dritte112-Lauf40135917063 auf `36bbba3` exportierte erstmals alle drei
vollständigen lesbaren Backendprotokolle samt exakt übereinstimmenden
Sammlungsbelegen. Gruppen1/2 bestanden1263/855Fälle mit13/14Skips. Gruppe0
stoppte nach754Erfolgen/14Skips an der kalendarischen Aufgaben-Deduplikation;
295Fälle blieben durch den frühen Abbruch ungetestet. Am tatsächlichen
CI-Zeitpunkt2026-10-24T22:03Z lag Berlin bereits am25.Oktober00:03. Wegen der
Zeitumstellung ist24Stunden später dort weiterhin der25.Oktober23:03. Die
Produktlogik dedupliziert diesen gleichen lokalen Tag korrekt. Der Test ersetzt
Sekundenarithmetik für »morgen« durch ausdrückliche lokale Kalenderdaten und
prüft normale,23- und25-Stundentage. Die vollständige Backendmatrix behält
25Minuten je Gruppe und führt künftig auch nach einem Fehler alle ausgewählten
Tests aus, damit keine Folgefehler erst in weiteren kompletten Läufen sichtbar
werden. Ein Sammlungsbeleg allein wird weiterhin nicht als Testerfolg gewertet.
Der ursprüngliche Zeitumstellungsfehler wurde mit ausschließlich im Testmodul
fixierter Zeit exakt reproduziert:1Fehler in16,96Sekunden. Die drei neuen
Kalenderfälle bestanden anschließend auf isoliertemSQLite:3/3 in46,39Sekunden.
Deduplication am gleichen Tag, getrennte Aufgaben am Folgetag, Quellenherkunft
und die bestehende409-Sperre nach Quellkorrektur werden weiterhin geprüft.
Danach wurden ausschließlich zwei Importzeilen sortiert; sämtliche
Testfunktions- und Nichtimport-ASTs blieben identisch. Der ausgeführte und der
abschließende Dateihash sind deshalb ausdrücklich getrennt dokumentiert;
die kommende vollständige CI prüft den abschließenden Stand. Produktcode und
Migrationen bleiben bytegleich zum gebauten112-Fachstand.
Die abschließenden drei echten Collect-only-Läufe enthalten3211Fälle in
167Dateien, verteilt auf1066/1276/869; Auswahlmengen disjunkt und vollständig.
Quelleninventar und Dateihashes blieben während aller drei Sammlungen gleich.
Gemeinsamer Sammlungsdigest:
`21a1006356e0c76c7ae7da4c34a126940fc67ed050c8e99c0f89e82dcd41a55c`.

### Paketausgabe: tatsächliche Routengrenze am 25.10.2026

Unter dem produktiven Release 112 (`01751d29`) wurde ein weiterer realer
Paketfehler ausschließlich anhand fest gebundener, lesender Metadaten geprüft.
Die geschlossene Fehlermeldungsklassifikation bestätigt erneut eine
Ausgabetrunkierung (`length`), tatsächliche Gebühr 0,067296 USD, keine
übernommenen Teilaufgaben. Die Basis erlaubte bereits 8000 Tokens, die
ausgewählte Sol-Route dagegen weiterhin 4000. Die wirksame Grenze ist das
Minimum von Basis und Route. Der Betreiber hat die Budgetanpassung ausdrücklich
freigegeben; bestehende Modell-, Datenschutz- und Denkstufeneinstellungen werden
dadurch nicht als neu evaluiert ausgegeben.

[OpenAI: Counting tokens](https://developers.openai.com/api/docs/guides/token-counting),
am 25.10.2026 gesucht und vollständig geöffnet: Ausgabelimits umfassen sichtbare
und nicht sichtbare Tokens; zusätzlicher Spielraum kann daher notwendig sein.
Die eigene Konfigurationsprojektion und die tatsächlichen Betreibermaßnahmen
bleiben getrennte Belege, keine aus dieser Dokumentation abgeleiteten Messwerte.

Neue künstliche Regressionen: 11 bestandene Fälle in 89,50 Sekunden prüfen
beide Routengrenzen, den unveränderten Luna-Pfad, den echten Adapter mit
8000 Tokens und `medium`, vollständige Grafikschritte und sechs Aufgaben,
sowie die abgerechnete Ablehnung einer abgeschnittenen Antwort ohne Retry.
Keine externen Aufrufe oder echten Kinderinhalte in diesen Tests. Sie erweitern
die Tests, ändern aber keinen Produktcode und keine Migration. Weitere Angaben:
[PACKAGE_OUTPUT_TRANSPORT.md](PACKAGE_OUTPUT_TRANSPORT.md).


### Mehrteilige Lernpakete am 25.10.2026 (1.36.1+113)

Ein zusätzlicher, separat freigegebener realer Paketversuch mit 8000 Tokens
endete ebenfalls mit `length`; tatsächliche Generationgebühr 0,107296 USD.
Es wurden keine unvollständigen Aufgaben übernommen und keine Kinderantworten
zu Testzwecken eingetragen. Die zuvor ausdrücklich genehmigte gemeinsame
Sol-Route verwendet jetzt 8000 Ausgabetokens und 0,25 USD Reservierung je Auftrag.
Eine Reservierung ist keine gemessene Gebühr.

Die bestehende Tagesvorbereitung teilt größere bestätigte Quellgruppen nun in
begrenzte Aufträge auf: grundsätzlich drei ganze Seiten beziehungsweise
6000 Quellzeichen, größere einzelne Seiten ungekürzt separat. Jeder Teil
erzeugt genau zwei Aufgaben und validierte Erklärgrafiken. Geprüfte Teile
bleiben privat gespeichert; erst alle zusammen veröffentlichen eine neue
Paketversion mit unveränderten bisherigen Antworten. Mehrere Aufträge können
insgesamt mehr kosten. Quellen-, Sitzungs-, Familien-, Planungs- und
Konfigurationsrevisionen gelten weiterhin. Einzelheiten und Grenzen:
[PACKAGE_PARTS.md](PACKAGE_PARTS.md). Keine neue SQL-Migration.

Bereits ausgeführte künstliche Prüfungen: 28 Teilplan-/Belegfälle (6,42 s),
2 durchgängige Workerfälle (4,96 s), 5 begrenzte Anbieterformatfälle (54,74 s),
20 Koordinatorfälle (322,74 s), 11 Ausgaberahmenfälle (89,50 s) sowie
21 Flutter-Widgetfälle; Flutter Analyze ohne Befund. Die Workerfälle prüfen
sieben Seiten in drei getrennten Aufrufen, atomare Veröffentlichung,
Fehlerstopp, expliziten Retry nur des fehlenden Teils und das Entfernen
privater Zwischenkopien. Alle Anbieterantworten dieser Tests sind künstlich;
diese Ergebnisse belegen keinen realen KI-Erfolg. Der zusätzliche gemeinsame
Regressionstest des vorhandenen Paket-/Tagesablaufs läuft separat.

Der zusätzliche gemeinsame Lauf zeigte 231 Erfolge, einen vorgesehenen Skip
und genau eine Regression: Der einfache Fortschrittsabruf lud zusätzlich das
Kind, obwohl keine Retryplanung erforderlich war. Die Korrektur verwendet die
bereits im Retryzweig berechnete Teilplanung; der normale Statusabruf bleibt
wieder bei genau einer kleinen Materialmetadatenabfrage. Die unveränderte
bestehende Queryassertion und alle 20 neuen Koordinatorfälle bestanden danach
gemeinsam: 21/21 in 17,32 Sekunden auf isolierter RAM-SQLite. Der vollständige
233-Fälle-Nachlauf prüft die abschließende Quelle separat; kein Test wurde zur
Annahme zusätzlicher Abfragen gelockert.


### Mehrteillauf und Grafikvertragsprüfung (25.10.2026)

Release113 `4c966fc` wurde mit 232 bestandenen und einem vorgesehenen
übersprungenen Fall der gezielten Backendprüfung aktiviert; Web, signierte
Direct-APK/Play-AAB, Signaturen und vollständige öffentlich ausgelieferte
APK-/JavaScriptbytes wurden separat geprüft. Der normale einmalige
Browserauftrag teilte den bestätigten Stoff in sechs Teile auf. Ein Teil wurde
validiert gespeichert, der zweite an drei Grafik-Modellprüfstellen abgewiesen;
kein Ausgabelimitfehler. Tatsächliche gemeldete Gebühren zusammen 0,089120 USD.
Die genaue verworfene Parameterkombination bleibt unbekannt. Öffentliche
synthetische Fälle belegen aber, dass das bisherige Schema mehrere solcher
fachlich ungültigen Kombinationen zuließ. Die nächste Korrektur bindet bereits
die Erzeugung an die bestehenden Grafikparameterregeln, ohne deren Prüfung
zu lockern oder einen fertigen Teil neu zu erzeugen. Siehe
[PACKAGE_PARTS.md](PACKAGE_PARTS.md).

[OpenAI: Structured model outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
am 25.10.2026 gezielt gesucht und geöffnet: verschachtelte `anyOf`-Zweige
werden unterstützt; jedes Objekt braucht vollständige Pflichtfelder und
`additionalProperties:false`. `allOf`, `not` und `if/then/else` gehören nicht
zum unterstützten Teilumfang. Das belegt den Dokumentationsvertrag, keinen
ungeprüften Anbieter- oder Modellerfolg.

Der vollständige [Checks-Lauf für Release113](https://github.com/meinzeug/schulpilot/actions/runs/40167046044)
zu `4c966fc` bestand zusätzlich alle drei Backendgruppen und Flutter. Das ist
ein Beleg für diesen Quellenstand, kein vorweggenommenes Ergebnis des
nachfolgenden Grafikvertragsfixes.

Die unabhängige synthetische Prüfung mit dem bereits lokal vorhandenen
JSON-Schema-Validator 4.10.3/Draft2020-12 bestätigt 24 kanonische Fachschemas
und 24 tatsächlich am gemockten HTTP-Eingang abgefangene Anfrageschemas.
82 gültige öffentliche Grafikinstanzen und elf ungültige Parameterkombinationen
wurden korrekt unterschieden. Der größte geprüfte Auftrag mit drei künstlichen
2000-Zeichen-Seiten umfasste 35.605 Textbytes, davon 15.083 Schemabytes.
Die bestehende konservative Kostenprojektion blieb mit 159.402 µUSD unter der
unveränderten 250.000-µUSD-Reservierung bei 8000 Ausgabetokens. Das sind
Bytemessungen und Vorabrechnungen, keine echten Token-, Preis- oder
Modellqualitätsmessungen. Null Anbieteraufrufe. Keine neue Laufzeitabhängigkeit,
keine Schema-/Choice-Decoderlockerung, keine Quellen- oder Antwortreparatur.

### Referenzkopplung und geschlossene Nachprüfung (25.10.2026, 1.36.3+115)

Der ausdrücklich erneut gestartete Teilauftrag unter Release114 kostete laut
OpenRouter 0,049308 USD und wurde mit der generischen strukturellen
Fehlermeldung abgewiesen. Seine genaue lokale Fehlerstelle ist rückwirkend
nicht belegt. Eine rein lesende Prüfung der drei betroffenen bestätigten
Quellen fand sowohl literale Bruchdarstellungen als auch Pfeilnotation und die
vorhandenen Bruch-/Szenenreferenzen; daraus folgt noch kein Nachweis, welche
Grafik tatsächlich erzeugt wurde oder fachlich geeignet war.

Neue künstliche Gegenbeispiele prüfen die bisher unverbundene Auswahl von
Referenz/Grafik und das Weglassen eines bereits festgelegten Katalogfachs.
Der neue Erzeugungsvertrag bindet diese Angaben vor dem Anbieteraufruf;
nachgelagerte Prüfungen und gemeldete Abrechnungswerte bleiben erhalten.
Geschlossene lokale Validierungsphasen ergänzen die vorhandenen begrenzten
Diagnosetags. Keine Rohantworten, Quelltexte oder privaten Fehlerargumente
werden dafür protokolliert. Umfang und Grenzen:
[PACKAGE_PARTS.md](PACKAGE_PARTS.md).

Der gezielte gemeinsame Nachlauf für die Referenzkopplung umfasst 579 bestandene
und einen vorgesehenen übersprungenen Testfall (206,90 s). Er verbindet
Teilplanung, Koordinator/Worker, Referenz-/Grafik-/Fachfähigkeit, Katalog,
Transport und Abrechnung mit künstlichen Eingaben. Dies ist kein Ergebnis der
gesamten Testsuite und kein Nachweis einer erfolgreichen realen Generierung.

Zusätzlich prüfen neun isolierte Fälle den Testdatenbank-Schutz: Die echte
Test-Fixture verweigert ihren Lösch-/Initialisierungsschritt bei abweichender
Engine-URL oder zwischengespeicherten Entwicklungseinstellungen. URL und
Zugangsdaten erscheinen nicht im Fehler. Die Testumgebung muss vor dem ersten
Appimport feststehen; diese Prüfung ist kein Wiederherstellungsmechanismus.

### Vorvalidierte individuelle Grafikparameter (25.10.2026, 1.36.4+116)

Der reale Reparaturversuch unter 115 wurde für 0,050074 USD abgerechnet und
in der visuellen Quellenprüfung abgewiesen (`visual/subject_source`). Zitat,
Zahl und Beschriftung verwendeten dabei noch denselben geschlossenen Code;
die exakte fehlerhafte Ausgabe ist nicht gespeichert. Die neuen getrennten
Codes enthalten weiterhin keine Anbietertexte oder privaten Eingaben.

Der neue private Grafik-Compiler parametrisiert vorhandene eigene Referenzen
direkt aus unveränderten bestätigten Quellliteralen und prüft die Kandidaten
vor der Erzeugung. Die Modellausgabe wählt eine vorher gebundene Darstellung
per Kennung; vor sämtlichen kanonischen Prüfungen wird genau diese Darstellung
wiederhergestellt. Antworten und Quellen werden dabei nicht ersetzt.
Aktivierung, Nachweise und Grenzen: [PACKAGE_PARTS.md](PACKAGE_PARTS.md).

### 25.10.2026 – passende Sprachgrafiken im mehrteiligen Paket (1.36.4+116)

- Rein lesende Produktionsprüfung mit dem geprüften öffentlichen Compiler,
  ohne neue Anbieteranfrage: sechs persistierte Teile, davon zwei Mathematik
  und vier Englisch. Zwei Englischteile besaßen nur ein gerichtetes
  Szenenrezept, aber keine wörtlichen Quellpfeile. Keine privaten Inhalte
  oder verworfenen Anbieterantworten werden hier gespeichert.
- Eigene zusätzliche Referenz `language.forms.original_comparison` Version1:
  zwei bis vier wortgetreue Originalausdrücke, bestätigter gemeinsamer Beleg,
  vollständiger Frageanker. Die vorhandene gemeinsame Flutter-Oberfläche
  ergänzt lokale Wortfokussierung mit Tastatur- und Kontoschutz.
- Vorbereitete Bruchgrafiken benötigen das genaue Zähler-/Nennerpaar der
  jeweiligen Frage. Ein expliziter Grafikparameterbezug ist keine allgemeine
  Prüfung sämtlicher sprachlicher oder fachlicher Aussagen durch Regex.
- Die Betreiberentscheidung erlaubt ausdrücklich kostenpflichtige Lernpakete
  für gute Grafiken. Normale Reservierungen, tatsächliche Gebühren und
  bestehende Kontoeinstellungen bleiben maßgeblich; kein zusätzlicher
  Providerwechsel und keine automatische Wiederholung fehlgeschlagener Jobs.

### Gekoppelter Frage-/Grafikvertrag (25.10.2026, 1.36.5+117)

Der reale 116-Versuch meldete 0,036372 USD und wurde mit
`prepared_graphics/prepared_graphic_binding` abgewiesen. Die genaue verletzte
Bedingung ist mangels gespeicherter Rohantwort nicht rückwirkend belegt.
Künstliche Gegenbeispiele zeigen unabhängig davon, dass ein frei formulierter
Prompt bis dahin trotz fest gebundener Grafik einen anderen Bruch nennen
konnte. Neue Fragezweige koppeln deshalb Promptmuster und gewählte Darstellung
bereits im tatsächlichen privaten Anfrageschema. Alle kanonischen Quellen-,
Antwort- und Parameterprüfungen bleiben erhalten; keine Ausgabe wird repariert.

Die am 25.10.2026 erneut gelesene
[OpenAI-Dokumentation zu Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
führt String-`pattern` und verschachtelte `anyOf`-Zweige als unterstützte
Mittel auf; `allOf` sowie `if`/`then`/`else` werden hier nicht verwendet.
Dies ersetzt keine tatsächliche Prüfung des ausgehenden OpenRouter-Vertrags.

Für den begrenzten weiteren Reparaturlauf gilt eine konservative lokale
Arbeitsgrenze von 2 USD einschließlich einer bereits belegten Vorbelastung
von 0,349586 USD außerhalb des persistierten Teilplans. Dieser feste
Arbeitsbeleg ist keine frische Gesamtkontobilanz. Die sechs historischen
Teiljobs und ihre 0,271166 USD werden separat aus den eigenen gespeicherten
Abrechnungsbelegen geprüft. Fünf noch fehlende Teile mit je höchstens 0,25 USD
Reservierung ergeben damit höchstens 1,870752 USD für diesen abgegrenzten
Arbeitsstand. Globale Providergrenzen und Kinderbudgets werden nicht verändert.

Der künstliche Maximalfall mit acht Grafikbasen und 6000 Quellzeichen wurde am
tatsächlichen ausgehenden HTTP-Mock geprüft: 39063 Bytes Schema, 67186 Bytes
Text und 222564 µUSD konservative Kostenprüfung bei 250000 µUSD Reservierung.
Dies sind Anfrage-/Vorprüfungsmesswerte, keine reale Modellabrechnung.
Unabhängiges JSON-Schema-Validieren prüft den wirklichen Wirevertrag und
weist einen falschen Fragebruch trotz ansonsten gültiger Grafikkennung ab.
100 Compilerfälle und 13 Adapterfälle bestanden; dies ist kein Ergebnis der
gesamten Testsuite oder Nachweis eines erfolgreichen erneuten Liveauftrags.

Der anschließende reale Produktionslauf unter Quellversion `515f44e`
(1.36.5+117) wurde erfolgreich abgeschlossen: sechs zusammengeführte Teile,
sechs veröffentlichte Einheiten, zwölf Aufgaben und achtzehn gespeicherte
Grafikschritte mit gültigen Referenz-Digests. Die gemeinsame Backendprüfung
bestand mit 761 erfolgreichen Fällen und einem übersprungenen Fall; vier
separate Operatorfälle bestanden ebenfalls. Tatsächliche erfolgreiche
Teilkosten: 0,234892 USD einschließlich des wiederverwendeten ersten Teils;
0,194954 USD entfielen auf die fünf fehlenden Teile. Frühere Fehlversuche sind
separat erhalten. Private Quellen, Antworten und Bildschirmkopien bleiben
außerhalb von Git. Details und Grenzen stehen in `docs/PACKAGE_PARTS.md`.

### Ruhige Statusanzeige auf Heute (25.10.2026, 1.36.6+118)

Der Kinder-Statusabruf in `dashboard.dart` rief bislang alle fünf Sekunden
denselben vollständigen Ladeweg wie eine ausdrückliche Aktualisierung auf.
`LoadView` ersetzte den bestehenden Inhalt durch seine Ladeanzeige; dadurch
ging der Elementzustand der Heute-Karten verloren. Der Timer liest den
Überblick nun still per GET und übernimmt eine gültige Antwort in den bereits
angezeigten Inhalt. Während der Anfrage sowie bei einem vorübergehenden
Lesefehler bleiben Inhalt und Scrollposition erhalten. Der nächste Statusabruf
erzeugt weder eine Lernrunde noch eine erneute KI-Verarbeitung.

Ein verspätetes Ergebnis wird nach Konto-, Familien-, Sitzungs-, Revisions-,
Kind-, Routen- oder Vordergrundwechsel nicht übernommen. Die ausdrückliche
Aktualisierung und andere Ladeansichten behalten ihren bisherigen Ablauf.
Die neue Widgetregression verwendet verzögerte künstliche GET-Antworten und
prüft den erhaltenen Elementzustand und Scrollversatz, Statuswechsel,
Lesefehler und Sitzungswechsel; sie benötigt keine neuen KI-Aufrufe.

### Belegte statt erfundene Bewertungsunsicherheit (25.10.2026, 1.36.7+119)

Eine ausdrücklich beauftragte Produktionsprüfung zeigte einen irreführenden
Klärschritt: Die gespeicherten Antwortversuche waren `incorrect`, keiner
war `uncertain`. Trotzdem durfte der KI-Kurzplan `clarify_assessment` wählen.
Die gemeinsame Oberfläche zeigte dadurch „Antwortprüfung offen“ und öffnete
mit ihrer Hauptaktion nur das allgemeine Hilfemenü. Elternkontakt ist keine
Bewertungskorrektur und konnte diese Plansperre deshalb nicht lösen.

Das private Anfrageschema und die unabhängige serverseitige Planprüfung
erlauben einen solchen Schritt nun ausschließlich für eine tatsächlich
ungeklärte letzte Antwort der angegebenen Aufgabe. Der einzelne zugehörige
Antwortbeleg ist verpflichtend. Die lesende Projektion prüft auch alte
gespeicherte Klärschritte erneut: Unbelegte, überholte oder fremde Belege
werden nicht als Handlungsblockade ausgegeben. Der gespeicherte Plan und
seine Historie werden beim Lesen nicht umgeschrieben; der vorhandene
faktenbasierte Lerncontroller übernimmt. Antworten, Bewertungen, Hilfen und
Lernzeit bleiben unangetastet. Echte Bewertungsunsicherheit bleibt sichtbar.

Die gesonderte, rein lesende rationale Prüfung der betroffenen Auswahlaufgabe
bestätigte den gespeicherten Lösungsschlüssel und genau eine passende Option
in der verlangten gemischten Darstellung. Beide gespeicherten Auswahlen
wichen rechnerisch davon ab. Ursache der Meldung war damit der unbelegte
KI-Plan, keine tatsächlich ausstehende Bewertung dieser Antworten. Achtzehn
neue Fälle und zweiundzwanzig bestehende Lernplan-/Unsicherheitsfälle bestanden
in isolierten Testdatenbanken. Die Produktionsprüfung übermittelte keine neue
Antwort und führte keine Neubewertung oder weitere KI-Erzeugung aus.

### Gespeicherte Aufgabe vor optionalem KI-Plan (25.10.2026, 1.36.8+120)

Der anschließende Live-Nachtest zeigte eine zweite Hürde: Nach Wegfall der
falschen Klärsperre war die vorhandene Auswahlaufgabe wieder sichtbar, aber
eine allgemeine Hilfewunschempfehlung ersetzte „Antwort prüfen“ durch
„Passenden Lernweg finden“. Der Server benötigte dafür keinen weiteren
KI-Auftrag. Die gemeinsame Web-/Android-Oberfläche bietet bei einer bereits
vorhandenen Frage nun die reguläre Antwortprüfung an; sie wird erst nach
vollständiger eigener Eingabe freigegeben. Ein neuer Lernplan bleibt bewusst
über die Hilfe erreichbar. Echte gespeicherte Pflichtschritte und das
Quittieren der letzten Rückmeldung behalten ihren Vorrang.

Der gezielte gemeinsame Widgetlauf bestand mit 28 Fällen. Drei Regressionen
prüfen diese Hilfewunschgründe jeweils mit zwei vorhandenen Fehlversuchen,
einer neuen künstlichen Antwort, normaler Rückmeldung und dem Wechsel zur
zweiten Aufgabe. Es entsteht dabei kein Planauftrag; der gesonderte bewusste
Planstart aus dem Hilfemenü bleibt separat geprüft.

### Aufgabenprüfung und tatsächlich bedienbarer Grafikzoom (25.10.2026, 1.36.9+121)

Die [Vorprüfung](QA_100_2026_10_25.md) trennt111 neue künstliche
Regressionsfälle von40 lesenden Prüfpunkten am ausdrücklich freigegebenen
Produktionsbestand.150 der151 unterschiedlichen Fälle bestanden; ein
unabhängiges mathematisches Orakel bleibt wegen nicht erkannter
Ganzfragenform offen. Die jeweils getrennten Schlüssel-, Gegenantwort- und
Grafikreferenzprüfungen dieser Frage bestanden. Aus einem vorhandenen
Lösungsschlüssel wird keine allgemeine fachliche Zertifizierung abgeleitet.

Der frische gemeinsame Flutterlauf bestand mit81 Fällen:31 neue Grafikfälle,
40 neue Bedienabläufe und zehn bestehende Zoomregressionen. Weitere40 neue
Backendfälle bestanden in regulär isolierten Testdatenbanken, einschließlich
vier tatsächlicher Antwort-/Idempotenzendpunktprüfungen. Der lesende
Produktionshelfer verarbeitet private Quellen nur im RAM, liest keine
Kinderantworttexte und ruft keinen Anbieter auf. Erst die später ausdrücklich
erteilte Freigabe erlaubt einen getrennten Durchlauf mit echten gespeicherten
Testversuchen; die bisherigen Tests werden nicht dafür umdeklariert.

Drei tatsächliche Fehler wurden belegt und gezielt korrigiert: Der Zoom
schließt nun auch bei einem Sitzungstokenwechsel; Originalvergleiche erhalten
bei320Pixeln und200Prozent Schriftgröße eine responsive Breite. Die echte
Browserprobe zeigte zusätzlich einen sofort wieder geschlossenen Dialog:
Der Originalvergleich entfernte auf der vom eigenen Zoom verdeckten Route
seinen Zoomknopf und zerstörte damit dessen Dialogzustand. Der Knopf bleibt
montiert, während Fokus-, Zeiger-, Routen- und Sitzungsprüfungen erhalten
bleiben. Ein zusätzlicher Regressionstest verwendet den tatsächlichen
SubjectPresentation-Pfad einschließlich Fremdüberdeckung und Sitzungsentzug.

### Allgemeine Heft-Runden: Grafikvertrag und Wiederholungen (25.10.2026, 1.36.10+122)

Der ausdrücklich beauftragte Live-Durchlauf mit gespeicherten Testversuchen
ist von der vorstehenden künstlichen und lesenden Vorprüfung getrennt.
Eine vollständige Runde zählt erst nach allen gespeicherten Antworten und
sichtbarem Ergebnis. Das freigegebene Testbudget beträgt 15 USD; bestehende
Kontolimits werden dafür nicht verändert. Geschützte, nicht eingecheckte
Belege halten Ausgangsbestand, tatsächliche Runden und Anbieterabrechnung
fest. Fehlgeschlagene Vorbereitungen zählen nicht als absolvierte Runden.

Nach der ersten vollständig abgeschlossenen Heft-Runde scheiterte deren
bewusst angeforderte Anschlussübung an `fraction_bounds` im ersten
Erklärgrafikblock. Der allgemeine Unit-/CoachPractice-Anfrageweg enthielt
nicht die strukturellen Grafikbindungen des Paketwegs. Der gemeinsame
Binder bindet jetzt auch dort zulässige Spezialfelder, Varianten und
Parameterformen vor dem Anbieteraufruf. Teilflächen dürfen nur ganzzahlige
Paare mit 0 ≤ n ≤ d ≤ 24 und d≥1 verwenden. Unechte Brüche bleiben als Aufgaben
zulässig; sie werden nicht als unmögliche Teilfläche ausgegeben. Aufgaben,
Lösungsschlüssel und nachgelagerte unabhängige Prüfungen bleiben erhalten.
Der Pakettransport berücksichtigt ausschließlich bei numerischen Array-Enums
die JSON-Schema-Gleichheit von 1 und 1.0; boolesche Werte und skalare
Integer-Auswahlantworten bleiben streng getrennt.

Eine zusätzliche isolierte Reproduktion zeigte, dass bewusst gestartete
allgemeine Materialrunden alte Fragen mit neuen IDs erneut speichern konnten.
Der Worker übergibt nun höchstens 80 vollständige frühere Fragen innerhalb
von 12000 Zeichen als Ausschlusskontext. Vor Veröffentlichung prüft er unter
der bestehenden Sperre die vollständige frische Historie des Kindes und der
passenden Quellenrevisionen einschließlich anderer fachgleicher Tagesetappen.
NFC-/Leerraumnormalisierung bewahrt Großschreibung; eng erkannte mathematische
Bruchaufgaben erhalten zusätzlich ihren bestehenden Zahlensignaturvergleich.
Die Prüfung verändert keine früheren Antworten und erzeugt keine Ersatzfrage,
automatische Wiederholung oder zusätzliche Reservierung.

Die gemeinsame Oberfläche unterscheidet bei gescheiterter Anschlussübung
sichtbar zwischen abgeschlossener Runde und noch nicht verfügbarer neuer
Übung. Antworten und Rückblick bleiben gespeichert; vorhandene Runden sind
direkt erreichbar. Interne JSON-Prüfpfade verschwinden aus der Kinderansicht.
Der separate Fortschrittslink heißt eindeutig „Lernstand aller Fächer“.

Weitere Live-Beobachtungen ergänzen diese Arbeit: Eindeutige Fragen nach
Zähler oder Nenner behandeln eine falsche numerische Antwort nicht länger
pauschal als unbekannte freie Prosa. Die neue Methode `fraction_components_v1`
erkennt ausschließlich vollständige begrenzte Frageformen zu einem sichtbaren
Bruch und prüft den gespeicherten Schlüssel unabhängig vor dem Aliasabgleich.
Ein widersprüchlicher Schlüssel bleibt unklar; historische Versuche werden
nicht nachträglich bewertet oder umgeschrieben.

`explanation-guidance-1` wird nach allen kompakten Prompt-Ersetzungen auf
neu erzeugte Erklärungen angewendet. Entscheidend ist der tatsächlich
sichtbare Schritttext: einfache Sprache zur konfigurierten Klassenstufe,
erklärte Fachwörter, konkretes Beispiel, Bedeutung der Grafik und eine passende
Merkhilfe. Einführung und geprüfte Aufgaben müssen dieselben Regeln behandeln.
Fragen nach unsichtbaren alten Wahr-/Falsch-Markierungen werden ausdrücklich
vermieden. Die Policy erhöht keine Schritte, Tokens oder Reservierungen und
schreibt beim Öffnen keine gespeicherten Inhalte um. Vergleichskarten heißen
„Beispiel“; eindeutig nummerierte Gedanken erhalten nur in der sichtbaren
Leseprojektion Absatzgrenzen. Originaltext, Zitate und Vorlesen bleiben erhalten.
Transporttests sind kein Beweis für didaktische Verständlichkeit; diese wird
zusätzlich an tatsächlich erzeugten Inhalten im Browser geprüft.

Der Heftblätterer bietet einen bewussten Einstieg in neue Übungen zur
geöffneten Seite. Weitere bestätigte Heftseiten desselben stabilen Fachs lassen
sich optional hinzufügen, die Aufgabenzahl wird individuell innerhalb einer
kleinen Runde eingegeben. Der bestehende Unit-Auftrag erhält die genaue
Seiten-/Revisionsauswahl; seine normale Reservierung, Idempotenz, Diagnose,
Referenzsuche und Veröffentlichung bleiben in Gebrauch. Alte Tagesseiten
werden nicht still zusätzlich ausgewählt. Die Auswahl ist auf zwölf Seiten
und 60000 Zeichen begrenzt; Kinder-, Familien-, Fach-, Quellen- und
Versuchsbindungen bleiben serverseitig. Die anschließende Statusseite
beobachtet nur den einen ausdrücklich gestarteten Auftrag.

Quellenabhängige Aufgaben benötigen erreichbare Originale. Der neue
Lesedialog aus Hilfe und Rundenübersicht hält die Aufgabenansicht montiert.
Revisionierte reine GETs prüfen Einheit, Kind, bestätigte Quelle und
unveränderte Version auch vor der privaten Bildauslieferung. Veraltete oder
fehlende Quellen werden kenntlich behandelt. Lesen erzeugt keine Antwort,
Lernzeitbuchung, Quellenbestätigung oder KI-Anfrage.

Bei der aktuellen Fotoabgabe scheiterten zwei Erkennungen an der
Ausgabelänge. Die vorhandene Vorauswahl berücksichtigte den dokumentierten
Fehler nur für dieselbe Seite und schickte die nächste Seite derselben Abgabe
erneut über die kurze Route. Sie berücksichtigt nun einen exakt gebundenen
Längenfehler einer weiterhin aktuellen Notebookquelle desselben Kindes und
Schultags vor der nächsten Reservierung. Die bereits konfigurierte stärkere
Route wird bewusst vor dem Aufruf ausgewählt; es entstehen kein automatischer
Wiederholungsversuch, Anbieterfallback oder neues Limit. Quellenänderung,
Entfernen, Umhängen und fremde Kinder beziehungsweise Tage invalidieren den
Beleg. Teilweise Abschriften behalten ihre Unsicherheiten. Die Oberfläche
unterscheidet unterbrochenes Lesen von gescheiterter Aufgabenerzeugung und
zeigt bereits gespeicherte Abschriften weiter an.

Abnahme der Oberfläche vor Release122: ein zusammenhängender Lauf mit 201
Flutter-Widgetfällen bestand einschließlich Heftauswahl, unverändertem
Idempotenzschlüssel beim bewussten Abgleich, Quellenlesedialog und
Erkennungsstatus bei 320/390 Pixeln sowie großer Schrift. Dabei gefundener
Pager-Überlauf wurde behoben. Die Analyse der geänderten Dart-Dateien und
Ruff für Backend, Deployment und Skripte waren fehlerfrei. Diese künstlichen
Regressionen zählen nicht als echte Kinder-Lernrunden. Die ausdrücklich
beauftragte Live-Prüfung bleibt davon getrennt dokumentiert; bisher fünf
vollständige allgemeine Heft-Lernrunden sind kein Abschluss der verlangten
100 Runden. Nicht als lesbar erkannte Fotos zählen nur als verarbeitet,
niemals automatisch als vollständig abgeschrieben oder bestätigt.

Die vollständige CI von Release122 meldete zusätzlich zu den bestandenen
gezielten Läufen eine Layoutregression: Die neue Heftaktion verkürzte lange
Fachnamen auf eine Zeile. Release123 stellt deren Lesbarkeit wieder her.
Die weitere Nacharbeit betrifft synthetische Vertragsfixtures: Ein bewusster
Lernwegauftrag liegt seit Release120 unter den Hilfen; Beobachterdaten brauchen
eine konkrete Frage und deren jüngstes Urteil, und neu erzeugte Testfragen
dürfen nicht identisch zu bereits gespeicherten Fragen sein. Die tatsächlichen
Prüfungen und absichtlich fehlerhaften Beobachterkandidaten bleiben erhalten.
Ein früherer bestandener Ausschnitt wird nicht als bestandene vollständige CI
ausgegeben.

Release123 trennt zusätzlich zwei belegte Erzeugungsfehler. Die geschützte
Produktionstelemetrie klassifiziert einen HTTP400 als `invalid_schema`; der
konkrete vom Anbieter abgewiesene Teil wurde nicht als Rohantwort gespeichert.
`native-graphic-1` projiziert daher ausschließlich die vollständig nachweisbare
eigene Grafikunion in eigenständige strikte `anyOf`-Zweige. Endliche
Bruchzahlenpaare werden nur im Anbietertransport als exakte Enum-Zeichenfolge
geschrieben und vor der unveränderten kanonischen Quellen-/Antwort-/Grafikprüfung
verlustfrei zurückgelesen. Antworten und Originalzitate bleiben opaque.
Grundlage ist die [offizielle Structured-Outputs-Dokumentation](https://developers.openai.com/api/docs/guides/structured-outputs)
(geprüft25.10.2026). Sie beschreibt die unterstützte Teilmenge und Größenlimits;
sie belegt nicht den konkreten HTTP400-Untertyp dieses Aufrufs. Es gibt weder
einen Anbieterwechsel noch höhere Kosten-, Token- oder Wiederholungsgrenzen.

Der getrennte Paketfehler `scene_label_evidence` entsteht bei der abschließenden
Prüfung von Beschriftungen. `package-source-graphics-1` erweitert den vorhandenen
Paketbinder um vorher kanonisch geprüfte Original-Pfeilfolgen. Die Modellantwort
wählt eine an Fach, Quelle, Revision, Referenzversion, Paketplan und Aufdeckstufe
gebundene ID; Titel, Objektlabels und Phasenbelege stammen gemeinsam aus derselben
vollständigen Originalfolge. Fragen brauchen die dazu passenden Originalanker.
Nur der neue Nichtmathematikpfad lässt den sichtbaren Schritttext innerhalb
der bestehenden Grenzen vom Modell verständlich erklären; die bereitgestellte
Quellenbeschriftung heißt ausdrücklich `source_caption` und ersetzt diesen
Text nicht. Die vorhandene Klassenstufen-Anleitung steuert genau dieses im
Frontend sichtbare Feld. Der Mathematikbinder behält seine festen Texte.
Die enge neue Referenz `german.word_formation.parts` verwendet den bereits
freigegebenen Satzbausteinrenderer für ausdrücklich sichtbare Plusfolgen mit
Wortbausteinrollen. Sie erfindet weder Wortzerlegungen noch Pfeilrichtungen oder
Grammatikbewertungen. Bestehende Referenzversionen und die besondere
Mathematik-/Bruchpolitik bleiben erhalten. Nicht belegbare Pfeilrezepte werden
vor dem Aufruf aus der betreffenden Auswahl entfernt; passende bestehende
fachliche Alternativen bleiben erreichbar. Lokale HTTP-Mocks und Schemafälle
sind ausdrücklich kein Nachweis eines gelungenen Produktionsauftrags.
Die neue Nichtmathematikauswahl bleibt vorab auf sechs vollständige
Grafikbasen mit allen Offenlegungsstufen begrenzt. Quellen und Zitate werden
dafür nicht gekürzt; die unveränderte Kosten-Vorprüfung bleibt maßgeblich.

Die mobile Seitenprüfung zeigt lange Fotoabgaben in einer kompakten Auswahl
statt als ständig sichtbare Chip-Liste vor dem Foto. Auswahl und Abbruch sind
reine Leseaktionen; Bestätigung und Vorbereitung bleiben ausdrücklich. Die
Lernwegansicht zeigt im Kinderzugang verständliche Fehlertexte und einen
direkten Weg zu gespeicherten Runden statt roher HTTP-/Schemahinweise.

Der normale Produktionsversuch nach Release123 passierte den bisherigen
Schemafehler, erreichte auf der kurzen Route aber die Ausgabelänge. Release124
erkennt ausschließlich einen gespeicherten Längenfehler derselben noch
unveröffentlichten Tagesetappe mit unverändertem Kind, Eigentum aller Quellen,
Quellenfingerabdruck und Plan. Der nächste ausdrücklich gestartete Auftrag
wählt vor der normalen Reservierung die bereits konfigurierte größere Route.
Modelle, Anbieter, Tokens, Kostenkonfiguration, Fehlversuche und historische
Verbrauchsbelege bleiben unverändert; es gibt keinen automatischen Retry.
Der Kindertextfilter behandelt zusätzlich Längen- und Ausgabeprüfungsfehler
über alle bestehenden Anzeige- und Fehlerpfade verständlich.

Die vollständige CI von Release123 bestand für Flutter und zwei Backendteile.
Ein synthetischer Test erwartete einen ausschließlich angebotenen Pfeilrenderer,
obwohl sein Originalstoff keinen Pfeil enthielt. Der Positivfall verwendet nun
einen tatsächlich wörtlich belegten Pfeil; ein eigener Negativfall verlangt die
Verweigerung der unbelegbaren Auswahl vor dem Anbieteraufruf.
Die erfolgreiche erste Produktionsetappe eines größeren Pakets ist noch kein
Nachweis, dass alle folgenden Etappen erfolgreich vorbereitet sind.

Die rein lesende Vorabprüfung aller sieben gespeicherten Paketteile zeigte vier
verwendbare Quellen-/Grafikschemata und drei fehlende passende Darstellungen.
Das prüft weder das spätere Modellergebnis noch die Vollständigkeit der OCR.
Im direkten Browservergleich wurden außerdem einzelne Wortersetzungen und
ausgelassene Bildbeschriftungen festgestellt, obwohl die Verarbeitung als
abgeschlossen gespeichert war. Der grobe Umfangstest ist kein Worttreuenachweis.
Die historische Bildanfrage verwendete hohe Bilddetailstufe und die gespeicherte
Auflösung von rund2400×3200Pixeln; eine Auflösungs- oder Längengrenze ist damit
nicht als Ursache dieser Wortabweichungen belegt.

Ein bewusst erneut angefordertes Einlesen einer nachweislich unsicheren
Heftseite berücksichtigt nun die Lesewarnungen der revisionsgebundenen
Originalseite. Die bisher leere Kopie verlor diese Auswahlgrundlage. Nur bei
passendem Kind, Originalrevision und identischem Bild wird die vorhandene
größere Route vor der normalen Reservierung gewählt. Originaltext, Bestätigung,
Antworten und Anbietergrenzen werden dafür nicht geändert.
Eine bereits vor dem Versand festgestellte fehlende Grafikreferenz wird als
lokaler Vorbereitungsfehler behandelt. Nur diese eng abgegrenzte Stelle erhält
einen stornierten Nullkostenbeleg; nach tatsächlichem Versand bleiben fehlende
Kostenbelege weiterhin unbekannt und reserviert.

Die zusätzliche Referenz `general.original_evidence.focused_list` besitzt eine
eigene unveränderliche Version und gilt zunächst ausschließlich für Deutsch
und Geschichte. Sie zeigt zwei bis vier vollständige aufeinanderfolgende
Originaleinträge mit zwei bewusst wechselbaren Lesefokussen. Hervorheben ist
keine behauptete zeitliche oder kausale Beziehung; Pfeile werden nicht ergänzt.
Vorhandene verwendbare Wortbaustein-/Pfeildarstellungen haben Vorrang. Nur dieser
neue Vertrag bindet Auswahlfragen an eine vorgeprüfte Liste von Originaloptionen:
ein endlicher Optionsslot wird vor dem bestehenden Indexdecoder verlustfrei
wiederhergestellt. Der Antwortindex bleibt unverändert; die richtige vollständige
Option darf nicht bereits im Prompt stehen. Die übrigen Originaloptionen werden
nicht als grammatisch falsch ausgegeben. Ein Lesefokus ersetzt weder eine
fachliche Animation noch einen Beleg vollständiger oder richtiger Fotoerkennung.
Für ungeklärte beziehungsweise falsch eingeordnete Quellen anderer Fächer wird
damit keine passende Grafik behauptet.

## 25.10.2026 – bereits geprüfte Paketteile nutzen (1.36.13)

Die bisherige Veröffentlichung wartete auf sämtliche Teilaufträge. Dadurch
blieben auch dauerhaft gespeicherte, geprüfte Runden unerreichbar, sobald ein
späterer Teil nicht sicher erzeugt werden konnte. Eine ausdrückliche Aktion
veröffentlicht nun den zusammenhängenden fertigen Anfang kostenfrei. Quellen,
Anbieterrevision, Aufgaben, Einstieg und Grafiken werden dabei erneut geprüft.
Eine versionierte Zuordnung verbindet jeden Teil mit seiner ursprünglichen
Erzeugung und genau einer Runde. Wiederholtes Absenden erzeugt keine Duplikate;
spätere Teile ersetzen weder begonnene Runden noch Antworten. Der Gesamtstatus
bleibt offen, bis tatsächlich alle Teile vorliegen. Gelöschte Teilrunden bleiben
als Löschvermerk erhalten und werden nicht neu angelegt.

Neue Lernwegaufträge binden die tatsächlich anmeldende Sitzung serverseitig
und prüfen deren Gültigkeit und Familienberechtigung vor und nach dem
Anbieteraufruf. Alte Aufträge ohne belegte Identität werden nicht nachträglich
mit einer erfundenen Sitzung ausgeführt. Nach der bestehenden Grenze erfolgloser
Starts zeigt bereits die lesende Lernwegantwort den technischen Prüfbedarf.
Gespeicherte Runden bleiben zugänglich; ein ausstehender, ausdrücklich
auditierter Reparaturauftrag wird als laufend angezeigt. Die normale Grenze
wurde nicht erhöht.

Die gemeinsame Flutter-Oberfläche bietet die Teilfreigabe auch während eines
weiteren Paketauftrags an. Alte Fehlermeldungen verdecken keinen laufenden
Ersatzauftrag. Der Heftdialog bezeichnet die ausgewählte Seite mit Thema statt
einer abweichenden Uploadnummer. Lokale synthetische Tests prüfen Idempotenz,
Quellenwechsel, getrennte Kinder, Sitzungsentzug und parallele Freigaben; diese
Tests sind keine Lernnachweise und keine Prüfung vollständiger Fotoerkennung.

Auch eine einzelne Heftseite kann einen strukturierten Grafik-/Aufgabenauftrag
benötigen, der die kleine Ausgaberoute erschöpft. Eine bewusst erneut angefragte
identische Heftauswahl verwendet nun die bereits freigegebene größere Route,
wenn ein eigener gespeicherter Auftrag nachweislich an genau diesem
Ausgabelimit scheiterte. Auswahlreihenfolge, Quellenrevisionen, sichere Inhalte,
Fach und Aufgabenanzahl müssen weiterhin übereinstimmen. Ohne diesen Nachweis
bleibt die Modellwahl unverändert. Es gibt weder einen automatischen zweiten
Aufruf noch höhere globale Token-, Wiederholungs- oder Kontogrenzen.

## 25.10.2026 – Ganze und Bruchreste gemeinsam darstellen (1.36.14)

Die bisherige Grafikprüfung verlangte für jeden im Erklärungstext genannten
Bruch einen einzelnen identischen Grafikblock. Jeder solche Block stellt aber
absichtlich höchstens ein Ganzes dar. Damit konnte eine richtige Zerlegung
eines unechten Bruchs trotz mehrerer korrekter Teilgrafiken abgewiesen werden.
Die geschlossene Produktionsdiagnose belegt einen Grafikparameterfehler; der
damalige Modelltext wurde nicht gespeichert und ist nicht rekonstruierbar.

Die neue unveränderliche Referenz `math.fraction.wholes_remainder` bindet
positive, wörtlich belegte Eingangsbrüche an eine vor dem Anbieteraufruf
berechnete Ganzes-/Restzerlegung. Quellenrevision, sicherer Quelleninhalt,
Rezeptversion, Aufdeckstufe, Text und sämtliche Grafikblöcke gehören zur selben
geprüften Kennung. Die vorhandenen Bruchrenderer zeigen bis zu drei Ganze und
einen Rest bei Nennern bis24. Die Einführung zeigt ausschließlich ein allgemeines
Ganzes; erst die Lösung zeigt die vollständige Zerlegung. Andere Darstellungen
und freie Modelltexte behalten ihre bisherigen Prüfungen.

Der vorhandene Unit-Auftrag und seine feste Einstiegsprobe bleiben erhalten.
Es entstehen weder zusätzliche Anbieteraufrufe noch geänderte Antworten,
automatische Wiederholungen oder höhere Token-/Kostenlimits. Die Referenz ist
kein frei auswählbarer Baustein für öffentliche Erkundungsgrafiken. Synthetische
HTTP-Tests verbinden ausdrücklich gewählte zwei beziehungsweise fünf Aufgaben,
Einstiegsprobe und Pflichtgrafiken und prüfen auch falsche Quellen, Reste,
Aufdeckstufen und fremde Kennungen. Sie ersetzen keine Live-Abnahme oder
vollständige Erkennungsprüfung der fotografierten Seiten.

## 25.10.2026 – Anschlussübungen und aktuelle Quellenstände (1.36.15)

Die Live-Prüfung einer abgeschlossenen Heft-Lernrunde zeigte zwei getrennte
Probleme: Die allgemeine Begründung verwies auf eine Grafik, die erst über das
Hilfemenü erreichbar war; die getrennte Anschlussübung wurde bei der Prüfung
einer Grafikbeschriftung verworfen. Der historische Modellwortlaut liegt nicht
vor. Ein weiterer anschließend gestarteter Lernweg-Auftrag wurde angenommen
und abgerechnet, erreichte aber die Ausgabelänge. Der bewusst ausgelöste nächste
Versuch verwendete nachweisbar die bereits vorhandene größere Route; dieser
scheiterte getrennt bei der Grafikparameterprüfung.
Ein solcher Fehler ist kein belegter erneuter HTTP-400-Fehler und wird getrennt
untersucht. Fehlgeschlagene Aufträge zählen nicht als abgeschlossene Lernrunden.

Die Ganzes-Rest-Referenz erhält eine neue unveränderliche Version mit korrekten
Einzahl-/Mehrzahlformulierungen. Die bisherige Version, ihre Kennungen und
gespeicherte Darstellungen bleiben gültig. Gezielte Anschlussübungen dürfen
diese Komposition verwenden, wenn ihre vorhandenen, wörtlich belegten Lernziele
vollständig die Umwandlung unechter Brüche in gemischte Zahlen beschreiben.
Vorhandene konkrete Rechenpläne, andere Ziele und andere Erzeugungswege werden
dadurch nicht überschrieben. Aufgabenanzahl, Zielzuordnung, neue Fragen,
Quellenrevisionen und Antwortprüfungen bleiben verbindlich.

Die Rückmeldung verlinkt die bereits beantwortete Frage unmittelbar mit ihrer
gespeicherten Erklärung. Der Zugriff erhält Konto-, Quellen-, Routen- und
Aufdeckungsprüfungen. Eine passende Ganzes-Rest-Komposition erscheint gemeinsam
mit einer aus denselben Zahlen gebildeten Gleichung. Der bewusste Wechsel
zwischen gebündelten Ganzen und einzelnen gleich großen Teilen verändert weder
Bruchwert noch Antwort oder Lernstand. Reduzierte Bewegung schaltet sofort um;
ansonsten bleibt der einmalige Übergang auf180ms begrenzt. Andere Referenzen
und Einführungen verwenden weiterhin ihre vorhandenen Renderer.

Nach einer Quellenkorrektur meldet der lesende Tagesstatus ausdrücklich, dass
die vorbereiteten Teile zu einer älteren Fassung gehören. Der Client zeigt
hier keinen vermeintlich aktuellen Teilfortschritt und bietet die bewusste
Neuvorbereitung mit den aktuellen Seiten an. Ein GET startet keinen Auftrag;
die bisherige Teilveröffentlichung bleibt bei veränderten Quellen gesperrt.
Ein neuer ausdrücklicher Auftrag baut den aktuellen Plan von Anfang an auf.
Historische Aufträge und Verbrauch bleiben erhalten, vorhandene Lernrunden
werden nicht ersetzt. Es gibt keine neue Datenbankmigration, automatische
Anbieterwiederholung oder Erhöhung der Anbieter- beziehungsweise Kontolimits.

Lokale Abnahme dieses Stands:510SQLite-Fälle bestanden; der eine dort
ausgelassene Fall verlangt PostgreSQL. Der separate frische PostgreSQL-Lauf
bestand79Fälle ohne Auslassung, einschließlich paralleler Veröffentlichung
und gemeinsamer Bausteinreservierung. Flutter bestand50Tagesseitenfälle und
87Grafik-/Lernablauffälle;26geänderte Fälle wurden nach den abschließenden
Analyzerkorrekturen nochmals erfolgreich geprüft. Diese Umfänge überschneiden
sich und sind keine entsprechend vielen echten Lernrunden. Die Analyse der
gesamten Flutter-App meldete keine Hinweise. Anfangs scheiterten vier neue
Widgettests am Ahem-Schriftersatz beziehungsweise Testaufbau; die endgültigen
Layoutprüfungen verwenden die tatsächlichen mitgelieferten App-Schriften.

### Quellengebundene Erweiterungsbilder und Aufgabenerklärungen128 (25.10.2026, 1.36.16+128)

Die vorangegangene Liveprüfung zeigte nach dem bereits korrigierten nativen
Ausgabeschema weitere getrennte Fehler: eine begrenzte Ausgabe, ein unvollständig
belegtes Erweiterungsbild und eine Anschlussfrage ohne den exakt benötigten
Grafikanker. Die historischen fehlerhaften Modelltexte wurden nicht gespeichert;
die geschlossenen Validierungsgründe erlauben keine Behauptung ihres Wortlauts.
Private Fotoprüfung, Korrekturpläne, Sicherungen und Auftragsbelege bleiben außerhalb
von Git. Eine korrigierte Abschrift ist weiterhin keine fachliche Freigabe.

`study_fraction_expansions.py` ergänzt den vorhandenen mathematischen Planer um
`math.fraction.expansion`v1. Bei belegter Erweiterungsregel und einer passenden
apply-/detective-Etappe werden unveränderte Aufgabenkerne vor dem Aufruf an zwei
geordnete Bruchmodelle, den gemeinsamen Faktor, Quelle und Referenzversion gebunden.
Nur diese vorab ausgewählte Darstellung beschränkt ihren endlichen Zahlenpool auf
höchstens24 sichtbare Teile. Historische Aufgaben und andere Planungswege behalten
ihre bisherigen Vorgaben. Gemischte, nicht vollständig darstellbare Pläne werden
vor dem Versand abgewiesen; es gibt keine nachträglich erfundene Ersatzaufgabe.
Die private Referenz bleibt aus dem gemeinsamen öffentlichen Bausteinkatalog
ausgeschlossen (`unit_composition_only`). Der vorhandene OpenAI-Adapter dekodiert nun
auch diesen ID-Vertrag vor der kanonischen Prüfung; die Produktionsroute ändert
sich dadurch nicht.

`fraction_practice_plan.py` bindet die zwei gezielten Umwandlungsfragen ebenfalls
vor dem Anbieteraufruf an vorhandene Originalbrüche und bestehende Lernziele.
Vollständige eigene Ketten-/Tageshistorie wird lokal auf bereits verwendete
Quellenwerte reduziert; diese kompakte Ausschlussmenge wird vor dem Speichern
unter der bestehenden Sperre erneut geprüft. Zu wenige neue Werte oder eine
nicht eindeutig zuordenbare alte Umwandlung führen zu einem lokalen Abbruch mit
null Anbietergebühr und dem Hinweis, eine andere bestätigte Seite zu wählen.
Alte v1-/v2-Grafik-Snapshots, Rückblicke und Antworten bleiben erhalten.

Flutter zeigt beim Erweitern zwei gleich große Flächen und Zähler-/Nennerrechnung.
Die ausdrückliche Unterteilung verändert nur die sichtbaren Teilgrenzen. Zoom,
Kontowechsel-/Routenprüfung, große Schrift und reduzierte Bewegung verwenden die
bestehenden gemeinsamen Bausteine. In der ausdrücklich aufgeklappten Liste
„Deine Antworten“ abgeschlossener Runden lässt sich eine gespeicherte
Aufgabenerklärung erneut öffnen. Kinder verwenden den vorhandenen expliziten
Erklärungsendpunkt samt normaler Explanation-Activity; Eltern den vorhandenen
berechtigten GET-Pfad. Der neue abgeschlossene Modus schließt ausschließlich den
Dialog und erzeugt weder neue Antwort noch Wiederaufnahme oder Modellaufruf.

Synthetische Prüfung:96 Flutterfälle für abgeschlossene Erklärungen, beide
Bruchrenderer und angrenzende Kinderführung bestanden; Flutter Analyze ohne
Hinweise.69 Backendfälle für Erweiterungsbindung, Providerdekodierung und
benachbarte Anschlussaufgaben bestanden vor der finalen Compilerintegration.
76 Fälle derselben Erweiterungs-/Quell-/Reservierungsverträge bestanden unter
frischem PostgreSQL ohne Skip; der lokale Cluster wurde anschließend entfernt.
Nach der Compilerintegration bestanden107 gezielte Backendfälle und65 Fälle
in einer weiteren isolierten PostgreSQL-Instanz, jeweils ohne Fehler; beide
PostgreSQL-Cluster wurden entfernt. Die tatsächlichen Integrations-/Releasebelege
werden revisionsgebunden geführt. Diese
Umfänge überschneiden sich und sind nicht zu einer Gesamtzahl zu addieren.
Widgetdaten und HTTP-Mocks belegen weder vollständige Handschrifterkennung noch
100 echte Lernrunden oder eine Prüfung auf einem physischen Androidgerät.

Schema bleibt0042; keine Migration und kein neuer Dienst. Vor Deployment gelten
die bestehenden Konfigurationssicherungs-, Signierer-, Quellen- und CI-Prüfungen.
Rückweg über die vorige geprüfte Releasefassung mit unveränderten privaten Daten
und unveränderter Providerkonfiguration; private Quellkorrekturen behalten ihre
Versionsgeschichte und dürfen nicht durch ein Release-Rollback zurückgeschrieben
werden.

Die erste vollständige CI dieses Builds fand acht bestehende Adapterfälle ohne
Grafikauftrag, die der neue Binder zu früh abwies. Sein Einstieg ist deshalb
zusätzlich auf einen tatsächlich erforderlichen Grafikkontext begrenzt; alte
Anfragen behalten ihren bisherigen mathematischen Vertrag.144 gezielte Fälle
für diese Kompatibilität, die neuen Proofs und die beiden Adapter bestanden
anschließend ohne Fehler. Die ursprünglich signierten Artefakte werden als
fehlgeschlagener CI-Versuch aufbewahrt und nicht aktiviert; der korrigierte
Quellstand benötigt einen neuen gebundenen Build und eine neue CI-Prüfung.


## 2026-10-25 · Heft-Runden, vollständige Aufgabenhistorie und Darstellungsgrenzen (129)

Der reguläre, ausdrücklich gestartete Heftaufgabenpfad verwendet für reine,
bestätigte Erweiterungsseiten dieselben geprüften Bruchmodelle wie der
Lernweg. Die vorhandenen vorgeschalteten Lernstandsfragen bleiben unverändert;
nur die übrigen Übungsplätze werden vor dem Anbieteraufruf aus belegten Regeln
rechnerisch festgelegt und an Grafik, Quelle und Referenzversion gebunden.
Mehrverfahrensseiten mit zusätzlichen Addier- oder Kürzregeln behalten ihren
bisherigen Vertrag. Keine künstlichen Study-Flags, keine automatisch gestartete
Runde und keine zusätzliche Anbieteranfrage durch Öffnen oder Abgleichen.

Vor der bestehenden Kürzung des Modellkontexts auf 80 frühere Fragen beziehungsweise
12.000 Zeichen wird die vollständige berechtigte Aufgabenhistorie in endliche,
private Erweiterungssignaturen verdichtet. Diese sperren bereits verwendete
Zahlen vor dem kostenpflichtigen Aufruf; die vollständige Datenbankprüfung vor
dem Speichern bleibt bestehen. Die Signaturliste wird nicht zusätzlich an den
Anbieter gesendet. Ein erschöpfter Zahlenvorrat endet ohne HTTP-Aufruf und ohne
neue Lernrunde. Quelle, Ausschlussmenge und feste Aufgabenkerne bleiben gebunden.

Technische Vorbereitungsfehler bieten Kindern gespeicherte Runden und Hefte an;
ein weiterer Versuch bleibt eine bewusste, serverseitig erlaubte Aktion.
Einwilligungs-, Zugangs- und Kontingentsperren bleiben eigenständig wirksam,
Eltern behalten die genaue Diagnose. TeX- und Unicode-Mischzahlen erhalten für
Vorlesen und Bildschirmleser einen getrennten Ganzteil; echte Hochzahlen werden
nicht als Mischzahl umgedeutet. Quelltext und Antwortparser bleiben unverändert.

Ein echter Desktop-Browsertest der gespeicherten Aufgabengrafik zeigte Kreise,
die über ihre nur in der Höhe begrenzte Zeichenfläche hinaus zeichneten. Der
Kompositionsrenderer erhält deshalb quadratische, zentrierte und beschnittene
Zeichenflächen. Bruchwerte, gespeicherte v1/v2-Belege, Aufdecken, Zoom und
Bewertung bleiben unverändert. Die Regression prüft tatsächliche RenderBox- und
Zeichenpfadgrenzen gegenüber Überschrift, Beschriftung und Bedienelementen.

186 gezielte Backendfälle bestanden sowohl mit isoliertem SQLite als auch mit
einem frischen PostgreSQL-16-Cluster, jeweils ohne Fehler oder Skip. Der
PostgreSQL-Cluster und sein temporäres Datenverzeichnis wurden entfernt;
Python-Netzwerkzugriffe waren dort auf Unix-Sockets begrenzt. Die tatsächlichen
Oberflächen-, Build-, CI- und Livebelege werden separat revisionsgebunden
geführt. Vorbereitete oder abgebrochene Läufe zählen nicht als bestandene Tests.
Keine Migration, kein neuer Dienst und keine Änderung von Modell, Tokenlimit
oder Kontobudget. Der Rückweg bleibt die vorherige geprüfte Releasefassung;
private Quellenkorrekturen und gespeicherte Antworten werden dabei erhalten.

296 gezielte Flutterfälle einschließlich echter Render-/Zeichenbegrenzungen,
320/390-Pixel-Ansichten und großer Schrift bestanden; Flutter Analyze meldete
keine Probleme. Frühere Teilmengen überschneiden sich mit diesem Lauf.


## 2026-10-25 · Gespeicherte Erklärungen im Tutor und verbindliche Einstiegsformate (130)

Ein produktiver Heftauftrag wurde nachweisbar in der Validierungsphase entry
mit entry_format abgewiesen. Das private Schema ließ in kopierten gemischten
Formatzweigen für source_probe auch andere Typen zu, obwohl der unveränderte
Nachprüfer für prior_check ausschließlich choice/short akzeptiert. Beide
Verträge stimmen nun überein: nur die kopierten Vorfragenzweige werden
eingeschränkt. Selbstständige Übungsplätze behalten Zuordnungsformate; feste
Voraussetzungsfragen behalten ihre exakten Kernfelder. Die ursprüngliche rohe
Modellantwort wurde nicht gespeichert; daraus wird kein genauerer Inhalt
rekonstruiert oder als belegt behauptet. Sechs synthetische Vorfixfälle
reproduzierten die Schema-Lücke, danach bestanden die erweiterten Adapterfälle.

Schulbuddy erhält für ausdrücklich geöffnete, gespeicherte Aufgabenerklärungen
einen serverseitig abgeleiteten Archivkontext. Voraussetzung bleiben eine
abgeschlossene Runde, ein vorhandener Antwortversuch, ein gültiger gespeicherter
Frageschritt und unveränderte berechtigte Quellen. Ungelesene aktuelle
Antwort-Rückmeldungen behalten ihren bisherigen Ablauf. Der Tutor darf den
bereits sichtbaren Erklärungsschritt direkt erklären; offene Aufgaben bleiben
geschützt. Der vollständige Schrittdigest und der historische Versuch werden
an den Kontext gebunden. Ein solcher Chat schreibt keine Hilfe in andere
laufende Runden und ändert keine gespeicherten Antworten oder Lernnachweise.
Die Abschluss-Transaktion sperrt ausschließlich die betroffene Archiv-Unit vor
dem Kind und prüft danach die bestehende Sitzung, Quellen und Konfiguration
erneut. Quellen-, Schritt- und Statuswechsel während eines Modellaufrufs
verhindern eine Veröffentlichung.

Ein weiterer produktiver Heftauftrag scheiterte in visual_parameters. Seine
vollständige Modellantwort ist ebenfalls nicht erhalten. Separat nachgewiesen
wurde, dass die vorhandene Erweiterungsregel wegen einzelner Zeilenumbrüche und
der getrennten Schreibweise „der selben Zahl“ keinen Verfahrensbeleg lieferte;
dadurch wurde die vorhandene strenge Aufgaben-/Grafikbindung nicht ausgewählt.
Die Referenzdatenbank enthielt die passende geprüfte Erweiterungsvorlage.

Nur der Erweiterungsweg erkennt nun solche Umbrüche innerhalb desselben
Absatzes. Eine zusammenhängende Aussage muss Zähler und Nenner direkt mit der
Multiplikation und demselben Faktor verbinden. Überschriften mit unabhängigen
Gleichungsbeispielen, Unicode-Leerabsätze, Negationen und eingeschränkte Faktoren
auch über Zeilenumbrüche bleiben ausgeschlossen. Originaltext und wörtlicher
Beleg werden nicht umgeschrieben. Ein privater, SQL-freier RAM-Replay des
konkret freigegebenen Materials aktiviert damit Katalog, Plan und Schemabindung;
er beweist weder die damalige verworfene Modellantwort noch eine neue gelungene
Live-Erzeugung. Synthetische Tests prüfen zusätzlich die wirkliche native
HTTP-Schemabindung vor dem Aufruf und fertige gespeicherte Grafiksnapshots.

Die Flutter-CI verteilt sämtliche Testdateien deterministisch auf drei Gruppen;
Analyse und Webbuild bleiben vollständig in einem eigenen Job. Ein abschließender
Gate prüft gleiche Quellfassung, vollständige Vereinigung und überschneidungsfreie
Dateimengen sowie die tatsächlichen Reportergebnisse. Vorhandene Plattform-Skips
und interne Lade-/Setupereignisse zählen separat. Fehlende, abgebrochene,
veränderte oder widersprüchliche Belege scheitern geschlossen. Die bestehenden
Action-/SDK-Pins und 25-Minuten-Grenzen bleiben unverändert. Mehr Jobs benötigen
mehr SDK-Setups; gleiche Dateimengen garantieren keine gleiche Laufzeit.

262 gezielte Backendfälle bestanden mit isoliertem SQLite; eine gezielte
Teilmenge von187 Fällen bestand mit frischem PostgreSQL ohne Skip und mit
anschließender Entfernung des eigenen Clusters.24 stdlib-Tests mit künstlichen
Flutterprozessen bestanden. Der neue Verteiler wurde außerdem tatsächlich mit
dem fixierten Flutter-SDK gegen den unveränderten vorigen Commit3ae1614 geprüft:
97 vollständige Testdateien,1254 bestandene Tests und12 separat ausgewiesene
Plattform-Skips, unveränderte Quellen vor/nach dem Lauf. Dieser Lauf prüft das
echte Reporterprotokoll, nicht bereits alle drei Gruppen oder den späteren
GitHub-Joboutputtransport. Die erste vollständige neue CI muss diese zusätzlich
bestätigen; eine gemessene Beschleunigung wird erst danach angegeben.

Schema bleibt0042. Keine Anbieter-, Token-, Kontobudget- oder Datenfreigabeänderung;
Rückweg über die vorherige geprüfte Version mit erhaltenen privaten Quellen,
Antworten, ursprünglichen Fehlversuchen und Verbrauchsdaten.

Die abschließende Erweiterung der Wortlautprüfung bestand119 gezielte Fälle
sowohl mit SQLite als auch mit frischem PostgreSQL16, jeweils ohne Fehler oder
Skip und mit unveränderten Backendquellen vor/nach dem Lauf. Diese Testmengen
überschneiden sich mit den zuvor genannten Teilmengen und werden nicht addiert.
Die eigene PostgreSQL-Instanz und die isolierten RAM-Testdaten wurden entfernt.
Ein lokaler Sandboxlauf blieb hängen und wurde abgebrochen; er ist kein
bestandener Test. Der identische abschließende SQLite-Lauf außerhalb dieser
Sandbox bestand mit weiterhin gesperrten Python-Netzwerkverbindungen und ohne
geerbte Anbieterzugänge. Die Versionsfelder wurden vor diesen letzten Läufen
auf1.36.18+130 gesetzt; sonstige spätere Änderungen betreffen nur Dokumentation.

Der erste Commitkandidat für Version130 wurde nicht aktiviert: Seine
vollständige CI bestand sieben Jobs, ein Backendjob meldete genau eine
Regression im unveränderten test_math_tasks.py. Bei einer handschriftlichen
Regel ohne Satzpunkt wurde eine unabhängige folgende Notiz in source_excerpt
mit aufgenommen. Die Rechnung blieb korrekt, der wörtliche Quellenvertrag war
jedoch verletzt. Der vorhandene Test wurde vor dem Nachfix isoliert rot
reproduziert; seine Assertion und alle bisherigen Testdateien bleiben erhalten.

Der eng begrenzte Nachfix prüft weiterhin zuerst die gesamte Klausel auf
Negation/Gegenbeispiele und alle Quellen auf Verfahrenseinschränkungen. Erst
danach endet das Zitat am frühesten Zeilenende mit vollständig verbundener
Erweiterungsregel. Notwendige Originalumbrüche bleiben erhalten. Acht zusätzliche
Fälle schützen neutrale Folgennotizen, LF/CRLF, späte Negation, feste Faktoren
und ein hinter einem Leerabsatz fehlendes Verb. Das konkret geprüfte private
Regelzitat bleibt gegenüber dem ersten Kandidaten bytegleich. Der Nachlauf
umfasst zusätzlich die gesamte vorhandene Mathematik-Aufgabenplaner-Testdatei;
die erste fehlgeschlagene CI und ihre gebauten Artefakte bleiben separat
aufbewahrt. Version130 war weiterhin unveröffentlicht, daher erhält der
korrigierte Quellcommit dieselbe neue Versionsnummer; kein Force-Push.

Dieser abschließende185er-Nachlauf bestand auf SQLite und PostgreSQL16 jeweils
ohne Fehler oder Skip, mit unveränderten Backendquellen und entfernten eigenen
Testdaten. Er überschneidet sich mit den zuvor genannten Tests; die Zahlen
werden nicht addiert. Die erneute vollständige CI sowie Build-/Signatur-/Live-
Belege werden für den korrigierten Quellcommit separat gebunden geführt.

## 2026-10-25 · Veraltete Tagesetappen und Tutor über Erklärdialogen (131)

Die Liveprüfung auf Version130 bestätigte zwei weitere Übergangsfehler.
„Freiwillig weiterlernen“ öffnete eine unveröffentlichte Tagesetappe, deren
vollständige Quellenbindung nach einer Quellenkorrektur nicht mehr aktuell war.
Die Etappenansicht sperrte die Erstellung korrekt; der Tagesplan hatte zuvor
jedoch nur die Quellen-IDs des einzelnen Blocks geprüft. Beide Lesewege nutzen
jetzt dieselbe vorhandene vollständige Quellen-/Fingerprintprüfung. Eine
veraltete unveröffentlichte Etappe wird nicht mehr als startbereit angeboten.
Gespeicherte Einheiten, Antworten, Elternaufträge, Abruftermine und Zeitfakten
behalten ihre bisherige Behandlung. Der neue begrenzte Prüfhinweis ist vom
Haupteinstieg getrennt; ohne andere vorrangige Arbeit führt die Hauptaktion zu
den vorhandenen Heften. Die GETs erzeugen weder Pläne noch KI-Aufträge.

Beim Öffnen des Schulbuddys aus einer gespeicherten Aufgabengrafik gingen trotz
des serverseitigen Archivkontexts aus130 die Erklärart und Schritt-ID verloren.
Ein pageless Flutter-Erklärdialog besitzt keinen eigenen GoRouterState; nach
dem Überdecken durch den Chat wurde deshalb sein Kontext verworfen. Solche
Dialoge erhalten jetzt einmalig die Hostposition, einen opaken Sitzungssnapshot
und ihre konkrete Route. Echter Routen-, Konto-, Familien- oder Tokenwechsel
entwertet diese Bindung. Eine Rückkehr zur gleichen URL reaktiviert kein altes
Modal. Die Backend-Autorisierung und Aufgaben-/Hilfenbewertung bleiben gleich.

Sieben neue verschachtelte Widgetfälle reproduzieren den echten Dialogweg.
Gegen den bisherigen Code scheiterten sechs davon; mit dem Fix bestanden sie
und ihre Nachbarfälle. Die gemeinsame Flutter-Analyse meldete keine Befunde;
126 gezielte Widgettests bestanden, darunter kleine Bildschirme mit großer
Schrift, Quellenprüfung, Elternpflichtaufträge und gespeicherte Rückmeldungen.
63 Backendfälle bestanden auf SQLite und einer frischen PostgreSQL16-Instanz,
jeweils ohne Skip. Der private Unix-Cluster und seine Testdaten wurden danach
entfernt, die gebundenen Backendquellen blieben unverändert. Das ältere
Planungsfixture erhielt ausschließlich den tatsächlich benötigten source_hash;
seine Mengen-, Reihenfolge- und GET-Nebenwirkungsprüfungen blieben erhalten.

Die fortgesetzte Liveprüfung bestätigte außerdem eine vollständig erzeugte und
beendete neue allgemeine Bruchrunde auf130. Die gespeicherte Rückmeldung
unterscheidet selbstständige Erstlösung und erfolgreichen weiteren Versuch;
ein gleichwertiger, aber nicht verlangter Erweiterungsbruch wird abgewiesen.
Die neue Grafik zeigt die passenden neun Teile, davon sieben markiert, und
passt in390px Breite. Eine neue allgemeine Simple-Past-Runde wurde erfolgreich
erzeugt; dies allein ist noch kein vollständiger Rundendurchlauf. Reale
Antwortversuche erfolgen ausschließlich im ausdrücklich freigegebenen Haushalt.
Der private Rundennachweis zählt zu diesem Zeitpunkt acht vollständige
Heft-Lernrunden, keine Wortschatzrunden; fehlgeschlagene Erzeugungen werden nicht
als Runden gezählt. Der Auftrag über100 Durchläufe ist damit noch nicht erfüllt.

Version1.36.19+131 behält Schema0042, Anbieterwahl, Reservierungen, Token- und
Kontogrenzen. Build-, Signatur-, CI- und Produktionsbelege werden erst für den
festgeschriebenen Quellcommit erzeugt; vorbereitete Helfer sind keine Abnahme.

## 2026-10-26 · Ausgabeprofil und typisierter Schulbuddy-Kontext (132)

Die fortgesetzte Produktionsprüfung beendete die zuvor nur erzeugte allgemeine
Simple-Past-Runde. Der private Nachweis zählt jetzt neun vollständige allgemeine
Heft-Lernrunden im ausdrücklich freigegebenen Konto. Fehlgeschlagene Erzeugungen
zählen nicht; der Auftrag über100 Runden bleibt offen. Der vollständige131-Build,
seine acht erfolgreichen CI-Jobs und die öffentlichen APK-/JavaScript-Hashes
sind getrennt an239fab6 gebunden. Seine komplette Flutter-Testvereinigung umfasst
4000 bestandene Fälle und19 gesonderte Plattform-Skips in292 Dateien.

Zwei weitere bewusst gestartete Vorbereitungen scheiterten ohne neue Einheit an
Ausgabelänge: eine explizite Heftauswahl auf130 und ein normaler Material-/Review-
Start von Heute auf131. Beide gespeicherten Reservierungssnapshots wählten Luna
mit4000 Ausgabetokens. Die geschlossenen Fehlermetadaten enthalten keinen
vollständigen ursprünglichen Modelloutput. Nachträglich abgeglichene Tokenzahlen
beweisen nicht, welcher Teil der Anfrage die Länge ausschöpfte. Eine pauschale
Behauptung über alle historischen HTTP400-Fehler folgt daraus ebenfalls nicht.

Die neue Auswahl berücksichtigt deshalb den tatsächlichen Ausgabevertrag vor
der normalen Reservierung: freie Grafik-/Erklärschritte benötigen auch bei
kurzem Quelltext die bereits freigegebene Sol-Route. Kleine explizite Zweier-
Heftauswahlen behalten Luna nur bei tatsächlich gebundenen, geprüften endlichen
Bruchvorlagen. Quellen-, Referenzversions-/Digest- und spätere Workerprüfungen
bleiben erhalten. Es gibt keine neuen Modellkennungen, höheren gemeinsamen
Token-/Kostenlimits, Anbieterfallbacks oder automatischen Wiederholungen.
Bereits reservierte Aufträge behalten ihren ursprünglichen Snapshot.

Die Liveprüfung des Schulbuddys auf131 zeigte einen weiteren getrennten Fehler:
Der gespeicherte Erklärkontext war im GET erreichbar, aber sein POST übertrug
graphic_index als Zeichenfolge. Das strikte Backend lehnte die Frage mit422
vor Reservierung ab. Nur die drei bekannten numerischen JSON-Felder
graphic_index/material_revision/exam_revision erhalten jetzt einen Integer;
GET-Parameter, IDs und übrige Texte bleiben unverändert. Ungültige Werte werden
weder durch0 ersetzt noch entfernt oder gerundet. Die Backendvalidierung bleibt
maßgeblich. Fünf neue Protokollfälle scheiterten gegen den bisherigen Client;
mit dem Fix bestanden sie samt Nachbarn. Die gemeinsame Flutter-Analyse ist
sauber,73 gezielte Oberflächen-/Tutorprüfungen bestanden.

Identische Quellenwarnungen werden nach tatsächlichem Grund und Wortlaut
zusammengefasst. Die Anzahl bezeichnet betroffene Textabschnitte, keine Zahl
unabhängiger OCR-Fehler; ihre gespeicherten Originalstellen bleiben aufklappbar.
Technische Vorbereitungsfehler zeigen Kindern eine ehrliche kurze Meldung und
einen reinen Navigationsweg zu gespeicherten Runden. Quellen-/Zugangs-/Kosten-
sperren behalten ihren eigenen Grund; Eltern erhalten weiterhin die konkrete
Diagnose. Anzeigen, Neuladen und Navigation erzeugen keine Wiederholungsaufträge.

Schema bleibt0042. Weitere Datenbank-, CI-, Build- und Produktionsprüfungen
werden separat für den endgültigen132-Quellcommit gebunden. Die hier genannten
Widgetprüfungen sind noch kein Beleg einer erfolgreichen neuen Live-KI-Antwort.

Eine weitere ausdrücklich beauftragte Serverprüfung auf131 bestätigte denselben
Längenfehler bei einem neuen normalen Material-/Reviewauftrag. Getrennt davon
stoppte Teilindex5 eines19-seitigen Pakets lokal vor dem Anbieteraufruf: Die
bereits vorhandene Quellenprüfung fand für seine Deutschgruppe keine passende
Einführungsgrafik. Der Aufruf wurde als cancelled mit0 Kosten und0 Tokens
abgeschlossen; dies ist kein erneuter HTTP400 und kein Kontolimit. Die fünf
vorangegangenen Teilaufträge meldeten completed; daraus allein wird kein
vollständig geprüftes Gesamtpaket abgeleitet. Alte Jobs und Ergebnisse bleiben.

Die betroffene Originalseite wurde im vorhandenen privaten Export persönlich
angesehen und ihre aktuelle bestätigte Abschrift im angemeldeten Browser gelesen.
Sie enthält unter anderem lesbare Verbformpaare, aber weder eine für das alte
Szenenrezept nötige Pfeilfolge noch eine geeignete Wortbausteinfolge. Der bisherige
Originalvergleich galt nur für Fremdsprachen/DaZ. Neu ist deshalb ausschließlich
das unveränderliche Rezept german.original_examples.comparison/1 für Deutsch:
zwei bis vier wörtlich belegte Beispiele, ohne Zahlen, Grammatikrollen, Pfeile
oder zusätzliche Parameter. Es verwendet das vorhandene sentence-Fachprofil
und denselben lokalen Wortvergleich wie die bereits vorhandene Fremdsprachen-
Darstellung. Der Decoder, Quellen-/Gruppen-/Fragebezug und Aufdeckstufen bleiben
streng; kein allgemeines forms-Fallback oder verändertes altes Rezept.

Die normale Routenauswahl bestand209 Fälle auf einer frischen PostgreSQL16-
Instanz ohne Fehler oder Skip; der eigene Unix-Cluster und Testdaten wurden
entfernt. Ein zusätzlicher SQLite-Lauf auf normalem Dateispeicher erreichte seine
600-Sekunden-Grenze und gilt ausdrücklich nicht als bestanden. Ein unveränderter
erneuter Lauf nutzt eine eigene RAM-Datenbank mit derselben Grenze. Die neue
Deutsch-Grafikbindung samt bestehenden Vergleichs-/Paketprüfungen bestand94
SQLite-Fälle mit unveränderten Backendquellen und anschließender Testbereinigung.
Diese gezielten Mengen überschneiden sich; sie werden nicht addiert.

Der unveränderte Routing-Nachlauf in RAM bestand104 SQLite-Fälle ohne Skip.
Die94 Deutsch-/Paketfälle bestanden außerdem auf einer frischen PostgreSQL16-
Instanz; Quellen und Manifest blieben unverändert, Cluster und Testdaten wurden
entfernt.22 Flutterfälle für den neuen Deutsch-Satzvergleich und die vorhandene
Vergleichskomponente bestanden, einschließlich320/390px und großer Schrift.
Die vollständige Analyse der gemeinsamen App meldete keine Befunde. Der erste
neue Renderer-Test zeigte korrekt, dass neben dem äußeren Dispatcher auch die
innere Kindprüfung der Vergleichskomponente ergänzt werden musste. Beide
akzeptieren jetzt nur die vorhandenen forms-/sentence-Klassifikationsblöcke;
Kontobindung, Aufdeckstufen, Literalgrenzen und lokale Bedienung bleiben gleich.

Der erste132-Kandidat d0edd3d wurde nicht aktiviert. Sein gebundener Build und
seine vollständige Flutter-CI bestanden4022 Fälle mit19 getrennten Plattform-
Skips in296 Dateien, aber ein Backendjob fand drei Regressionen. Die normale
Materialvorauswahl erfasste einen ausdrücklich als OCR-Neulesung markierten
Diagnoseauftrag. Dieser Spezialpfad ist nun wie Eltern-/Prüfungsaufträge aus
dem neuen Profil ausgeschlossen; die alte Diagnoseprüfung bleibt unverändert.
Die neue Deutschreferenz war außerdem ohne Suchbegriffe für jeden Deutschtext
angeboten und vergrößerte zwei schon große Mehrfachanfragen über ihre bestehende
Kostenreservierung. Sie wird jetzt nur bei passenden Originalpaar-Markern oder
belegten Themenwörtern ausgewählt. Der konkrete betroffene Quellenvergleich
bleibt abgedeckt; beliebige Prosa löst ihn nicht mehr aus. Kostenprüfung, alter
Mehrfachtransport und Reservierung wurden nicht gelockert.

Der Nachlauf bestand157 Fälle auf SQLite und einer frischen PostgreSQL16-
Instanz, jeweils ohne Skip, mit unveränderten Backendquellen und bereinigten
Testdaten. Er enthält die unveränderten fehlgeschlagenen Altprüfungen und neue
Auswahl-/Spezialpfadfälle. Der vorherige Kandidat samt tatsächlichen Binärdateien,
Signaturbelegen und fehlgeschlagener CI bleibt separat archiviert. Die erneuten
Build-/CI-/Produktionsbelege werden an den korrigierten Commit gebunden. Die
weitergeführte Liveprüfung beendete außerdem eine zehnte allgemeine Heft-
Lernrunde; eine externe Gesamtzählung wird nicht als eigener UI-Test ausgegeben.

## 26.10.2026 – reguläre Heft-Runden und verlustfreier Schematransport133

132 wurde mit4.407 bestandenen Backendfällen und44 getrennten Skips sowie
4.022 Flutterfällen mit19 Plattform-Skips veröffentlicht. APK, AAB, Webdatei,
Quellbindung, Signatur und Geheimnisprüfung bestanden. Die konkrete gestoppte
Paketverarbeitung wurde im berechtigten Kinderzugang bewusst wiederaufgenommen:
beide fehlenden Teile wurden gespeichert, alle sieben Runden sind erreichbar.
Die Metadaten aller18 zuvor vorhandenen allgemeinen Einheiten und72 vorherigen
Aufträge blieben gleich. Die zwei neuen Aufträge meldeten zusammen69.282µUSD;
unbekannte Gebühren werden dadurch nicht als bekannt oder kostenlos ausgegeben.
Eine tatsächliche Schulbuddy-Frage aus der gespeicherten Bruchgrafik erhielt eine
Antwort; beim Schließen blieb dieselbe Grafik geöffnet. Persönlich vollständig
geprüft sind inzwischen zwölf allgemeine Heft-Runden, nicht hundert.

Ein zusätzlich bewusst gestarteter normaler Heftseitenauftrag zeigte eine zweite
Grenze: Die Route war bereits korrekt Sol mit8.000 Ausgabetokens und250.000µUSD
Reservierung, wurde aber lokal mitcost_preflight gestoppt.106.011 Textbytes und
die gespeicherten Preisobergrenzen von2.000.000/10.000.000µUSD pro Million
Eingabe-/Ausgabetokens ergaben300.214µUSD. Es erfolgte kein Anbieteraufruf;
der alte fehlgeschlagene Auftrag und seine0-Verbrauchsbuchung bleiben erhalten.
Dies ist kein neues Kontolimit und kein Anlass, die Kostenprüfung zu umgehen.

133 verwendet für die beiden neuen Routen material_graphic_teaching und
notebook_graphic_teaching zusätzlich die bestehende schema_projection:
identische Schemaknoten werden über lokale JSON-Schema-Referenzen geteilt.
Ausgabefelder, Quellen, Werte und kanonische Prüfungen bleiben erhalten; es
werden weder Antwortfelder umbenannt noch neue Decoder oder Modellaufrufe
ergänzt. Die Kostenprojektion zählt diese tatsächlich versendete kompakte
Schemafassung. Alte Routen und bestehende feste Bruchkompositionen behalten
ihren bisherigen Transport. Modell, Reasoning, Reservierung, Preisobergrenzen
und Kontolimits werden nicht verändert.

Zehn künstliche SQLite-Fälle prüfen beide Routen mit kleinen und umfangreicheren
Deutsch-/Mathematikanfragen an denselben Preis- und Ausgabelimits. Auch weiterhin
zu große Anfragen müssen vor der einzigen Mock-HTTP-Grenze mit0 Anbieteraufrufen
und0 Kosten abgelehnt werden. Der isolierte RAM-Testbestand wurde entfernt;
Backendquellen blieben während des Laufs unverändert. Eine anfängliche lokale
Sandbox-Ausführung blockierte beim Testclient und wurde beendet; sie gilt nicht
als erfolgreicher Lauf. Die nachfolgenden Abnahmen verwenden den bestehenden
separaten Unix-/Mock-Netzwerkschutz. Breitere Abnahme und133-Liveprüfung folgen
auf genau den dafür eingefrorenen Quellstand.

Der erste breitere133-Lauf bestand218 SQLite-Fälle. PostgreSQL bestand217 von
218 Fällen; bei einem bestehenden Fünfer-Heft-Test brach bereits dessen lokaler
Vorbereitungshelfer vor dem Anbieteradapter ab. Drei isolierte Parameterfälle
bestanden anschließend. Der Befund wurde nicht als behoben oder als erfolgreicher
Gesamtlauf ausgegeben: feste künstliche Seeds reproduzieren einen realen Konflikt,
bei dem die Vorwissensfragen beide Originalbrüche der Einführung benötigen und
deshalb kein sicher getrenntes Erklärbeispiel übrig bleibt.

Neue ausdrücklich gewählte Erweiterungsrunden reservieren deshalb genau einen
im bestätigten Inhalt belegten Originalbruch für die Einführung. Neue Proben
verwenden ihn weder als Eingabepaar noch als Erweiterungsantwort; die eigentlichen
Übungsaufgaben schließen ihn ebenfalls als abgeleitete Antwort aus. Das ist eine
Planungsausschlussmenge, keine künstliche Übungshistorie oder Leistungsbewertung.
Eine feste zweite Regression mit dem einzigen Original2/4 und einer gezielt
kollidierenden Aufgabe1/2 mitFaktor2 zeigte denselben Abbruch und besteht jetzt
ebenfalls. Alte Proben, begonnene Einheiten, Antworten und Quellen werden nicht
umgeschrieben. Die endliche Planung und der Abbruch bei echter Erschöpfung bleiben.
Der abschließende eingefrorene Nachlauf umfasst beide Fälle sowie die bestehenden
Einstiegs-, Erweiterungs-, Transport-, Routen- und Kostenprüfungen.

Lernweg- und Workerprüfung26.10.2026 ·1.36.22+134:
Der vom Betreiber geöffnete ältere Schultag wurde tatsächlich im Browser und
anschließend über eine auf diesen Haushalt/Tag beschränkte, ausschließlich
lesende PostgreSQL-Prüfung untersucht.23 Seiten, davon sechs unbestätigt,
acht gespeicherte Runden und kein aktiver Kinderauftrag erklären die aktuelle
Sperre. Die sichtbare Aktion „Lernweg neu planen“ schlug deshalb erneut mit
„Bitte zuerst alle Heftseiten prüfen und bestätigen“ fehl. Die alten
fehlgeschlagenen Etappen sind damit kein Beleg für einen aktuell laufenden
oder neu fehlgeschlagenen Anbieteraufruf. Privater Seiteninhalt und Antworten
wurden bei dieser Metadatenprüfung weder ausgewählt noch protokolliert.

Der lesende Lernwegvertrag ergänzt Anzahl und nächste ID offener Quellen.
Die gemeinsame Flutter-Oberfläche zeigt dafür „Seiten prüfen“ und öffnet die
eigene Materialprüfung. Unmögliche Neuplanung und veraltete Etappenfehler
weichen diesem tatsächlichen nächsten Schritt. Bearbeitungszahlen und Zugang
zu gespeicherten Runden bleiben erhalten. Lesen, Navigieren und Aktualisieren
bestätigen keine Quelle und erzeugen keine Aufgaben. Nach ausdrücklicher
Quellenbestätigung kann der Lernweg wieder bewusst neu geplant werden;
Bestätigung, Quellenrevision und die vorhandenen Inhaltsprüfungen bleiben nötig.

Die133-Liveprüfung deckte zusätzlich eine unterbrochene Metadatenweitergabe
auf: Der normale Heftauftrag wurde trotz gebundener Sol-Route erneut vor dem
Versand gestoppt, mit106.029 Textbytes und300.250µUSD Kostenprojektion statt
höchstens250.000µUSD.0 Anbietertokens und0 Verbrauch wurden gespeichert.
Die direkten künstlichen Adaptertests hatten die Routenauswahl selbst angehängt;
der echte Worker kopierte dagegen nur persistente ProviderConfig-Spalten und
verlor dabei den ursprünglichen Auswahlgrund. Der kompatible Rückfallgrund
reserved_route aktivierte die in133 ergänzte kompakte Schemafassung nicht.

134 kopiert deshalb den bereits aus der reservierten Usage gebundenen
Auswahlsnapshot vor dem Rollback und hängt ihn an die nachher verwendete
Requestkonfiguration. Keine neue Modellwahl, keine zusätzliche Reservierung,
kein höheres Token-/Zeit-/Kostenlimit und kein Anbieterfallback. Die vorhandene
Kostenprüfung und sämtliche kanonischen Aufgabenprüfungen bleiben aktiv.
Die echten künstlichen API→Reservierung→Worker→Mock-HTTP-Tests prüfen nun den
vollständigen unveränderten Snapshot an dieser tatsächlichen Grenze, sowohl
für normale Heftaufgaben als auch für Rückblicke und vorhandene Einführungen.

Die134-Oberflächentests prüfen die Quellenführung auch ohne bisherigen Plan,
auf schmaler Ansicht, mit erhaltenem Rundenzugang und ohne automatische POSTs.
Backendtests prüfen unbestätigte und leere Quellen, unveränderte Pläne bei GET,
keine Jobs/Usage/Antworten/Aktivität und erneute Planung erst nach ausdrücklicher
Bestätigung. Abnahme und Veröffentlichung gelten ausschließlich für den dafür
geprüften Quellstand. Persönlich vollständig beobachtet sind14 allgemeine
Heft-Lernrunden; dies ist weiterhin keine abgeschlossene100-Runden-Prüfung.

Referenzkopplung26.10.2026 ·1.36.23+135:
134 wurde nach4.423 bestandenen Backend- und4.024 bestandenen Fluttertests
veröffentlicht;44 Backend- und19 Flutterfälle sind ausgewiesene Ausnahmen.
Die öffentlichen Web-/APK-Hashes entsprechen dem signierten Quellstand. Der
ursprünglich geöffnete ältere Schultag zeigt auf Desktop und390px mobil die
sechs offenen Quellen und die direkte Seitenprüfung. Ihr Button wurde bis zur
tatsächlich offenen Materialansicht bedient; keine Quelle wurde dabei bestätigt.

Der einmal bewusst gestartete normale Heft-Nachtest überwand den bisherigen
Kosten-Vorabbruch. Der Anbieter lieferte22.197 Eingabe- und3.011 Ausgabetokens,
mit gemeldeten74.504µUSD. Die Ausgabe wurde anschließend alsinvalid_output
mitvisual/scene_label_evidence verworfen. Kosten und alter Fehler bleiben
vollständig gespeichert. Unbekannte Gebühren gelten weiterhin nicht als bekannt.
Die private fehlerhafte Antwort wurde nicht protokolliert oder dauerhaft
aufbewahrt; welcher einzelne Titel oder welches Label betroffen war, lässt sich
aus dem bewusst begrenzten Fehlerbeleg nicht feststellen.

Codeprüfung und künstliche Regression zeigen einen Unterschied zwischen beiden
Erzeugungswegen: Kleine Paketaufträge koppeln unveränderliche Referenz, tatsächlichen
Grafiktyp/Variante, Fachquelle und Aufdeckstufe im selben Schema-Zweig. Der normale
Heftauftrag bot diese Felder bislang weitgehend unabhängig an.135 verwendet für
neue nichtmathematische normale beziehungsweise explizite Heftrunden auf den beiden
bereits freigegebenen erweiterten Routen dieselbe vorhandene Referenzkopplung.
Eine bloße Originalwortfolge erhält dadurch keine unpassende allgemeine Pfeilszene,
wenn keine vollständige belegte Pfeilfolge vorhanden ist. Quellenbelege und
kanonische Beschriftungsprüfung bleiben unverändert; eine erfundene Beschriftung
wird weiterhin verworfen. Das ist eine Einschränkung des angeforderten Vertrags
vor dem Anbieteraufruf, keine nachträgliche Korrektur einer falschen Modellantwort.

Es wird kein Paket erzeugt, keine Antwort umgeschrieben und keine feste
Zweieranzahl übernommen: Bereits gebundene Aufgabenanzahl und Vorwissensfragen
bleiben erhalten. Mathematik, Rückblicke, Klassenarbeits-/Hausaufgabenverträge,
begonnene Runden und alte Anbieterwege werden nicht umgebunden. Fehlende geprüfte
Darstellungen führen vor dem Versand zu einem ausdrücklichen Fehler mit0 Kosten;
kein Ersatzinhalt und kein automatischer Anbieterretry. Die neue gemeinsame
Hilfsfunktion nutzt denselben Quellen-/Referenzcode wie die vorhandenen Paketteile.

Auch der historische Assistentenkopf zeigt bei noch unbestätigten Seiten wieder
„Prüfen“ als aktuelle Phase, statt „Fertig“ hervorzuheben. Dies ist ausschließlich
eine lesende UI-Projektion; Schultagsstatus, Antworten und Lernplan werden beim
Lesen nicht umgeschrieben. Neue Regressionen prüfen gültige Originalvergleiche,
weiterhin abgewiesene erfundene Labels, unveränderte Aufgabenzahlen, geschützte
Spezialverträge sowie die sichtbare Phase ohne automatische Schreibanfragen.
Eine neue echte Anbieterprüfung ist erst nach dieser nachgewiesenen Korrektur
und Veröffentlichung vorgesehen; der134-Nachtest wird nicht als KI-Erfolg ausgegeben.
Der neue normale Referenzvertrag verhindert außerdem ein zweites unabhängiges
question.presentation-Panel außerhalb des gebundenen Erklärungsschritts. Die
Frage muss aus ihrem Prompt verständlich sein; ihre Erklärungsgrafik bleibt im
quellen- und stufengebundenen Schritt. Damit wird auch das sonst ungebundene
vollständige Grafikunion-Schema nicht zusätzlich angefordert. Die vorhandenen
Kostenregressionen mit40.000 künstlichen Zusatzbytes bleiben eine eigene
Abnahmegrenze; Reservierungen werden für die neue Bindung nicht erhöht.

Einheitlicher Heftseiten-Einstieg26.10.2026 ·1.36.24+136:
135 wurde nach4.438 bestandenen Backend- und4.026 bestandenen Fluttertests
veröffentlicht;44/19 Fälle sind die ausgewiesenen Backend-/Plattformausnahmen.
Die direkte Quellenprüfung und die hervorgehobene Phase „Prüfen“ wurden im
ursprünglichen echten Schultag im Browser bestätigt. Der folgende einmalige
normale Heft-Nachtest scheiterte vor dem Versand an97.203 Textbytes und einer
konservativen Projektion von282.598µUSD gegenüber250.000µUSD Reservierung.
Es wurden0 Anbieter- und0 Ausgabetokens sowie0 Kosten gespeichert. Dies ist
kein erfolgreicher KI-Test und kein Grund, die Kostenprüfung zu umgehen.

Die Ursache des unerwartet großen Umfangs ist im tatsächlichen API-Pfad belegt:
Die Materialseiten-Aktion schickte nurmaterial_id. Der unveränderte historische
Backendvertrag ergänzt dann alle bestätigten Seiten desselben Fachs und
Schultags. Bei dieser Quelle waren es18 Seiten. Der Hefter besitzt bereits
einen davon getrennten, expliziten revisionsgebundenen Auswahlvertrag. Der
zusätzlich kopierte Legacy-Einstieg verwendete ihn bislang nicht.

136 verbindet die reguläre Heftseiten-Aktion beider Rollen mit dem vorhandenen
NotebookPracticeDialog und der persistenten LearningPreparation-Statusseite.
Vorausgewählt ist ausschließlich die aktuelle bestätigte Seite. Weitere Seiten
werden bewusst hinzugefügt, die individuelle Aufgabenanzahl bleibt im vorhandenen
begrenzten Vertrag. Erst „Runde vorbereiten“ sendet genau einen idempotenten POST
mitnotebook_sources und den exakten Revisionen; danach ausschließlich Status-GETs.
Der lange API-Polling-/Sofortstartweg entfällt für reguläre Notebook-Seiten.
Der bewusste Start der fertigen Runde bleibt getrennt. Unbekannte Ausgangslagen
behalten ihren Abgleich mit demselben Schlüssel im vorhandenen Dialog.

Die berechtigte Materialantwort liefert dafür zusätzlich die gespeicherte
stabile Fach-ID, die Auswahlfähigkeit und die Kennzeichnung fester Beispiele.
Keine neue Autorisierung oder Migration; der bestehende Backendvertrag prüft
weiter Kind/Familie, Fach, Quelle, Revision, Anzahl, Sitzung und Kosten atomar.
Feste synthetische Beispiele sowie spezialisierte Nicht-Heft-Verträge behalten
bestehende Pfade. Bei einem alten Backend ohne explizite Auswahlmetadaten führt
die neue reguläre Seitenaktion in die Heftsammlung und startet keine ungefragt
vergrößerte KI-Anfrage. Sprachseiten behalten ihren vorhandenen Spracheinstieg.

Neue verbundene Flutter-Tests prüfen Kinder und berechtigte Eltern, die exakte
Einseiten-Auswahl, Quelle/Revision/Anzahl/Idempotenz, reine Vorbereitung ohne
Rundenstart, Abbruch, Kontowechsel und den alten Backendfall. Der Backendtest
prüft die ergänzten Detailmetadaten bei wiederholten GETs ohne neue Jobs, Usage,
Einheiten oder Antworten. Die vorhandenen Mehrseiten-, Kosten-, Neuheits-,
Wortschatz- und Materialleseprüfungen bleiben Teil der Abnahme. Die17 bisher
persönlich vollständig beobachteten allgemeinen Heftrunden sind weiterhin
keine abgeschlossene100-Runden-Prüfung.

136-Folgeprüfung vor Veröffentlichung: Ein unabhängiger Review fand, dass ein
Hintergrundwechsel den Auswahl-Dialog während des POST entfernt und damit dessen
nur lokalen Abgleichschlüssel verliert. Der neue NotebookRequests-Store nutzt den
vorhandenen SecureStorage ausschließlich für Account-/Familien-/Kind-/Fach-/
Quellenkennungen, Revisionen, Aufgabenanzahl, Requestschlüssel und bekannte Job-ID.
Er claimt vor dem POST dauerhaft und seriell; unbekannte Ausgänge werden weder
zeitlich gelöscht noch verdrängt. Maximal32 Einträge, nur bereits bestätigte
Jobkennungen dürfen für neue Claims weichen. Ohne speicherbaren Claim kein POST.
Späte Antworten dürfen denselben Auftrag auch nach Dialogverlust quittieren;
Kontowechsel/Logout löscht serialisiert und erhöht sofort eine Epoch. Bekannte
Jobs öffnen ohne POST, unbekannte werden ausschließlich bewusst mit demselben
Body/Schlüssel abgeglichen. Eine weitere Runde benötigt eine eigene ausdrückliche
Auswahl. Nach Dialogschluss ist Navigation nur von der wieder aktuellen
Ursprungsroute zulässig, auch im vorhandenen Hefter-Einstieg.

Die ergänzten Regressionen prüfen Hintergrund während POST, gespeicherte späte
Jobantwort ohne zweiten POST, Wiederherstellung mit neuem AppState und identischem
Schlüssel/Body, überdeckte Route während Dialogausgang, Kapazität ohne Verlust
ungewisser Aufträge und die Sperre späterer Abschlüsse nach Logout. Die erste
Testausführung enthielt eine await-auf-void-Fehlerstelle im neuen Test und fehlende
SecureStorage-Testinitialisierung; danach war ein synthetischer Lifecyclewechsel
unvollständig. Diese Testfehler wurden korrigiert, keine Providerprüfung ersetzt.
Die18. allgemeine Heftrunde wurde inzwischen persönlich mobil vollständig beendet
und getrennt mit vorhandenen Serverantwortmetadaten im privaten Prüfledger belegt.
Ein zweiter Reviewbefund wurde ebenfalls vor Veröffentlichung behoben: Ein409
nach verlorenem Antwort-ACK beweist nicht, dass der frühere Auftrag fehlt, weil
Quellenprüfung vor dem serverseitigen Idempotenzlookup erfolgen kann. Solche
Abgleichfehler behalten den ursprünglichen Body/Key. Nur ein nachweislich erster
neuer, ausdrücklich abgewiesener POST gibt den lokalen Claim wieder frei.
Der zusätzliche503→409→Wiederöffnen-Test prüft exakt diese Beibehaltung.
Lokale Folgeabnahme:44 verbundene UI-/Entwurfsprüfungen bestanden, anschließend
21 Auswahl-/Wiederaufnahmeprüfungen auf dem abschließenden Produktcode bestanden;
Flutter analyze ohne Hinweise. Die102 SQLite-/102 PostgreSQL-Prüfungen des
unveränderten Backendcodes bleiben erhalten; die vollständige CI wird an den
neuen Quellencommit gebunden, ebenso reale Web-/Direct-/Play-Buildartefakte.

Live-Abnahme136: Quelle0225e55722f1c831bf6f45237b8cda6091236a96,
Version1.36.24+136, Release20261026T113414Z-0225e55. Vollständige CI40306454827:
4439 Backendtests bestanden/44 übersprungen,4035 Fluttertests bestanden/19
übersprungen;297 Flutterdateien exakt einmal. Frische Web-/Direct-/Playartefakte,
Signatur-/Quellenprüfung und Geheimnisprüfung ohne Treffer. Alle fünf Dienste
aktiv;17 gesicherte Konfigurationsdateien unverändert, Schema0042 erhalten.
Rückweg: Release135 behalten und Zeiger mit dem vorhandenen Aktivierungsweg
zurücksetzen; keine Datenbank zurückspielen und keine Antworten löschen.

Der zuvor zu große direkte Einseiten-Einstieg wurde tatsächlich im Kinderkonto
wiederholt: Auswahlgenau1 bestätigte Deutschseite,2 Aufgaben; ein regulärer
Anbieterauftrag erfolgreich gespeichert (40862µUSD tatsächliche Generationkosten).
Vollständiger App-Neustart und Wiederöffnen derselben Seite zeigte den bekannten
Auftrag an. Öffnen führte zu derselben Statusroute; zwei unabhängige Metadaten-
Snapshots belegen identische Unit-Jobs und identischen Verbrauch. Anschließend
wurden beide Aufgaben im Browser abgeschlossen: eine selbstständig, eine mit
Hinweis und Erklärung; Hilfen waren im Ergebnis ausdrücklich ausgewiesen.
19 vollständige allgemeine Heftrunden sind persönlich belegt,100 bleiben offen.
Eine zusätzliche gespeicherte Englisch-Abrufrunde ist getrennt geprüft und nicht
als neue allgemeine Runde in diesen Zähler übernommen worden.

Eine weitere normale Mathe-Erstellung zum kgV scheiterte dagegen nach dem
Anbieteraufruf an visual/scene_label_evidence (71020µUSD, kein Längen-/Limitfehler).
Die bestehende Quellenprüfung bleibt bestehen. Der wörtliche Unterrichtsweg
„Vielfachenmengen notieren, kleinste gemeinsame Zahl finden“ wurde anschließend
im echten Heftfoto überprüft, ohne die Quelle zu ändern. Der konkrete fehlerhafte
KI-Labeltext ist mangels gespeichertem Rohoutput unbekannt. Ein Vorversand-
Grafikfehler darf nicht als behobene vollständige kgV-Lektion ausgegeben werden.

137: Eine beim Live-Vergleich beobachtete reine Wortmarkierung wird
für einzelne Wörter um exakte gemeinsame Graphem-Anfänge/-Enden ergänzt. Ganze
Sätze behalten den bestehenden Wortvergleich, reine Zahlen ebenfalls. Original-
zeichen und Screenreader-Text bleiben unverändert; diese lokale Lesehilfe trifft
kein Grammatikurteil, sendet keine Anfrage und erzeugt keinen Lernbeleg.

Der neue enge kgV-Binder verwendet die vorhandene Referenzdatenbank,
Einheitenerstellung, reguläre Reservierung und denselben Flutter-Szenenspieler.
Auf bestätigte positive Definitionen oder nachgerechnete Zweischritt-Verfahren
folgen vorab gebundene kleine Fragen; Einstieg und Aufgabenlösungen haben
getrennte Offenlegungsstufen. Quellenrevisionen, Regel- und Referenzdigests bleiben
bis zur Ausgabe nachprüfbar. Vollständige bisherige Fragen werden vor Versand
und Veröffentlichung ausgeschlossen; ein konkurrierender gleicher Auftrag,
Quellenwechsel oder erschöpfter Zahlenpool führt nicht zu automatischen Retries.
Andere Auftragsarten und bestehende Bruchpfade behalten ihre Prüfungen.

Die kgV-Zahlenbewertung prüft zuerst die gespeicherte Hauptlösung selbst gegen
`math.lcm`. Falsche größere gemeinsame Vielfache werden nicht über Textvarianten
akzeptiert. Neue Reference-Seed-Zeile `math.multiples.common@1`, keine neue
Datenbankmigration und keine Änderung an Modellrouten, Tokens oder Limits.
Ein fehlender Lehrbeleg bricht vor dem Anbieteraufruf ab; die normale Reservierung
wird dabei als abgebrochen und kostenfrei aufgelöst.

Öffentliche künstliche Renderer-Vorlage `testdata/multiples_common_v1.json`,
SHA256 `76182c1f185ef137a97a281a37f315f8b4ea0094c35940df78a7c317c6e30252`.
Die lokale Sichtprüfung verwendet echte gebündelte Schrift und SDK-Icons bei
320px/200%,390px,768px und1100px. Beobachtete Pfeilüberschneidungen wurden aus
diesem neuen Rezept entfernt; ein kurzer Titel verhindert einen unnötigen
Wortbruch. Diese künstliche Vorlage ist kein echter Modell- oder OCR-Beleg.
50 gezielte Flutterfälle bestanden; der anschließende reine Titel-Nachlauf
bestand mit7 Fällen, Analyse sauber. Der reale kgV-Test folgt erst nach Deploy.
Die endgültige137-Backendfassung bestand dieselben398 gezielten Fälle sowohl
mit RAM-SQLite als auch mit frischem Unix-Socket-PostgreSQL16, jeweils ohne
Fehler/Skips. Ein unveränderlicher Hashmanifest vor/nach beiden Läufen belegt
identische Quellen; Datenbanken und Testdateiverzeichnisse wurden entfernt.
Die Läufe enthielten neue kgV-, Transport-, Quellenwechsel-, Parallelitäts- und
Bewertungsfälle sowie bestehende Bruch-/Referenz-/Heft-/Antwortprüfungen.

Ein zusätzlicher ausdrücklich gestarteter Live-Anschlussauftrag einer bereits
fertigen Bruchrunde scheiterte weiterhin am bekannten Ausgabelängenfehler
(Luna,4000Ausgabetokens,3670µUSD gemeldet). Alte Antworten und Rückblick blieben
erreichbar. Dies ist ein getrennt beobachteter offener Anschlussroutingfehler,
kein erfolgreicher neuer Durchlauf und noch kein Beleg für den neuen kgV-Pfad.

137 ist als Commit 908395fb686538feeaa887a665642834bd3e2c31, Version 1.36.25+137
ausgeliefert. Vollständige CI 40315112207: alle 8 Jobs erfolgreich, 4.587 Backendfälle
bestanden, 44 übersprungen; 4.048 Flutterfälle bestanden, 19 übersprungen,
299 Testdateien genau einmal. Signierte Direct-APK, Play-AAB, Web-JS und Reparatur-
archiv sind an denselben Quellstand gebunden; lokale Signatur-/Geheimnisprüfung
ohne Befund. Nach Deploy alle 5 Dienste aktiv, 17 Konfigurationen unverändert und
Schema 0042 erhalten. Öffentliche APK/Webdateien wurden vollständig nachgehasht.

Die zuvor gescheiterte normale kgV-Heftauswahl wurde live erfolgreich neu
angefordert: eine bestätigte Seite, zwei Aufgaben, 42.404 µUSD gemeldete Erstellungskosten.
Absichtlich 28 statt kgV(2,7)=14 wurde eindeutig falsch bewertet; Hinweis und
Grafikerklärung geöffnet, einmaliger weiterer Versuch korrekt unterstützt.
Die zweite Aufgabe wurde ohne Hilfe korrekt gelöst. Ergebnis sichtbar, Einheit
serverseitig vollständig abgeschlossen, drei Attempts erhalten. 20 allgemeine
Heftrunden sind damit persönlich belegt, Ziel 100 noch nicht erreicht.
Desktop 1100px, Tablet 768px und Smartphone 390px wurden tatsächlich im Live-Browser
bedient; der Grafikschritt blieb beim Breitenwechsel erhalten. Private Screenshots
und Metadatennachweise liegen außerhalb der versionierten Quellen.
Der lesende Live-Nachweis bestätigt einen bereiten Grafiksnapshot, eine Einführung,
zwei Fragegrafikgruppen, eine aktuelle bestätigte Quellenrevision und das gespeicherte
`math.multiples.common@1`-Receipt mit passendem Referenzdatenbank-Digest.

138 ergänzt die getrennt beobachtete Anschlusskorrektur: Der tatsächliche
verpflichtende Grafikvertrag wird vor der bestehenden Reservierung für die
konfigurierte Sol-Route berücksichtigt. Quellen-/Coaching-Kontext und explizite
Zweitversuchsgrenze bleiben maßgeblich; kein automatischer Retry, keine neue
Route und keine Limitänderung. Neue Anschlussjobs binden außerdem die aus der
Kindersitzung stammende Sitzung/Familie. Vor und nach dem Provideraufruf gilt der bestehende
Authority-Helper, auch nach erneutem Laden des Transaktionszustands. Replays
behalten ursprüngliche Authorityfelder; Legacyjobs werden nicht reautorisiert.

Die 138-Kandidatenfassung bestand 87 Fälle auf netzgesperrter SQLite und frischem
Unix-PG16, darunter 11 gezielte Sitzungsfälle (Widerruf/Ablauf/Konto-/Familien-
wechsel und Widerruf während des Anrufs mit erhaltener realer Abrechnung).
Roots integrierte Fassung stimmt im gesamtenBackendmanifest mit 468 Dateien exakt
mit der geprüften PG-Kopie überein; eigener SQLite-Nachlauf 87/87 ohne Quelländerung.
Der getrennte 87-Fälle-Kandidatennachweis und die vollständige 137-CI sind keine
behauptete 138-CI oder Live-Abnahme. Andere ältere Jobarten sind durch diese
gezielte Ergänzung nicht pauschal auf Sessionbindung geprüft.

138 ist inzwischen als Commit afb119a18a7920065f2c78866cbeeb8ecc4ba2d7,
Version 1.36.26+138 ausgeliefert. CI 40319757423: alle acht Jobs erfolgreich,
4.632 Backendfälle bestanden/44 übersprungen sowie 4.048 Flutterfälle bestanden/
19 übersprungen; 299 Flutterdateien genau einmal. Signaturen, Quellbindung,
Reparaturarchiv und Geheimnisprüfung bestanden. Alle fünf Dienste aktiv,
Schema 0042 und 17 Konfigurationen unverändert; öffentliche APK/Webdateien
vollständig mit den lokalen Hashes verglichen. Geschützte Sicherung:
`/var/backups/schulpilot/elements138-config-20261026T122116Z`.

Der ausdrücklich wiederholte Anschlussauftrag nutzte nun nachweislich Sol,
8.000 Ausgabetokens und die bestehenden 250.000 µUSD Reservierung, mit gültiger
Sitzungs-/Familienbindung. Er lieferte 2.290 Ausgabetokens und 56.288 µUSD
gemeldete Kosten, wurde aber an `visual/visual_parameters` verworfen. Das belegt
eine zweite Grafik-Vertragslücke nach dem behobenen Längenproblem. Der konkrete
falsche Modellparameter ist ohne aufbewahrte Rohantwort nicht rekonstruierbar.
Ein separater normaler Heftauftrag wurde vom Anbieter abgebrochen; sein Preis
bleibt unbekannt und die Reservierung erhalten. Keine automatischen Retries.

139 ergänzt einen eigenen geschlossenen Coach-Adapter für die bereits belegte
Erweiterungsregel. Er verwendet vorhandene Rechenplanung, Referenzdatenbank,
Bruchrenderer und Quellen-/Historienprüfungen. Der getrennte Kandidat bestand
336 synthetische Backendfälle ohne Fehler/Skips bei unveränderten 470 Quellhashes.
Die technische Fehlerführung ergänzt eine lesende Retry-Verfügbarkeit ohne
Erhöhung der Zwei-Versuchs-Grenze; 36 Backendfälle und 26 normale Widgetfälle
bestanden (zwei versteckte Setup-/Teardown-Ereignisse sind keine zusätzlichen
Tests). HTTP200-Fehlerumschläge des Anbieters erhalten geschlossene Verfügbarkeits-
kategorien; acht echte Mock-Transportfälle prüfen genau einen Request und die
unveränderte Abrechnung bekannter und unbekannter Kosten. Dies sind Kandidaten-
nachweise, keine behauptete 139-Produktionsabnahme.

26 allgemeine Heft-Lernrunden sind persönlich im Live-Browser abgeschlossen,
74 fehlen noch zum ausdrücklich beauftragten Ziel. Zusätzliche kgV-Runden
prüften Tutor öffnen/schließen mit erhaltenem Entwurf, Smartphone-/Tabletwechsel
und Neuladen zwischen Antwort und Feedbackquittierung ohne doppelte Antworten.
Reine Wortschatzrunden, fehlgeschlagene Vorbereitungen und synthetische Tests
werden nicht mitgezählt. Private Screenshots und Zählbelege bleiben außerhalb
der versionierten Quellen.

Roots integrierte 139-Fassung bestand jeweils 380 Fälle auf netzgesperrter
RAM-SQLite und frischem Unix-PG16, ohne Fehler oder Skips. Alle 473 Backenddateien
stimmen mit der geprüften Kopie überein; Manifest und Quellen blieben während
beider Läufe unverändert, temporäre Datenbank und Verzeichnisse wurden entfernt.

Die nächste echte Bruchrunde belegte zusätzlich eine unsichtbare Einstiegshilfe:
Der Hinweis wurde gespeichert, obwohl die Einstiegsansicht ihn nicht zeigte.
Die gezielte Oberflächenkorrektur öffnet zunächst das sichtbare Hilfemenü;
erst eine ausdrückliche Wahl lädt die Erklärung. Der vorhandene Grafikdialog
führt danach zuverlässig zur ersten Aufgabe. Sechs neue und 24 benachbarte
Widgetfälle bestanden. Eine zweite Sichtprüfung belegte fehlende Pfeilglyphen
in der gebündelten Textschrift. Zwei bekannte Literale verwenden jetzt bereits
gebündelte Materialglyphen, bei unveränderten Daten, Formeln und Sprachtexten.
Acht neue und 159 benachbarte Fälle bestanden; 320/390 px bei großer Schrift
und Desktop wurden mit den tatsächlichen Schriftdateien gerendert geprüft.
Beide gezielten Analysen waren fehlerfrei. Diese lokalen Nachweise ersetzen
weiterhin keine vollständige 139-CI oder Produktionsabnahme.

Roots gemeinsamer Oberflächennachlauf nach Integration aller drei UI-Korrekturen
bestand 40 Tests; Analyse der sieben betroffenen Dartdateien ohne Befund.

139 ist als Commit b04136816357264cebbec2614633b8f092d08724 und Version
1.36.27+139 ausgeliefert. CI 40327540173: alle acht Jobs erfolgreich,
4.701 Backendfälle bestanden/44 übersprungen und 4.070 Flutterfälle bestanden/
19 übersprungen; 302 Flutterdateien genau einmal. Die drei Backendshards decken
4.745 reguläre Fälle in 229 Dateien disjunkt ab. Vier PostgreSQL-URL-Fallnamen
werden im heruntergeladenen CI-Text maskiert; deshalb lässt sich der ursprüngliche
Collection-Digest daraus nicht nochmals berechnen. Das ist keine zusätzliche
ungeprüfte Behauptung über die maskierten Inhalte. Signierte APK, Play-AAB,
Webdateien und Reparaturarchiv wurden an denselben Quellstand gebunden geprüft.
Alle fünf Dienste aktiv, Schema 0042 und 17 Betriebskonfigurationen unverändert;
öffentliche APK/Webdateien vollständig nachgehasht. Geschützte Sicherung:
`/var/backups/schulpilot/elements139-config-20261026T132513Z`.

Die fortgesetzte Liveprüfung unterscheidet drei weitere belegte Ausfälle:
Eine normale Materialrunde scheiterte an `visual/visual_parameters`, eine
explizite Runde zu gemischten Zahlen an der Bindung einer vorbereiteten Grafik
an ihre Frage, eine geplante Deutschetappe an der Ausgabelänge. Konkrete verworfene
Modellparameter werden ohne aufbewahrte Rohantwort nicht nachträglich behauptet.
29 allgemeine, aus bestätigten Heftseiten abgeleitete Runden sind tatsächlich
beantwortet und abgeschlossen, darunter eine gezielte Anschlussrunde. Reine
Vorbereitungen, Wortschatzrunden und lokale Rendererfixtures zählen nicht mit.
Ein Anbieterabbruch im zusätzlichen Rückblick verlor keine Antworten; genau ein
bewusst angeforderter weiterer Rückblick war erfolgreich. Das Ziel 100 bleibt offen.

140 ergänzt die vorhandenen, getrennten Erstellungspfade gezielt:
Normale Materialrunden erhalten für ausdrücklich belegtes Erweitern vor dem
Transport feste Rechenkerne und den geprüften Bruchrenderer. Ihre bestehenden
zwei beziehungsweise vier/fünf Plätze und kuratierten Einstiegsfragen bleiben
erhalten. Explizite Heftrunden zu gemischten Zahlen binden vorbereitete
Grafikkandidaten vor dem Transport an die unveränderten Aufgabenkerne. Beide
Pfade verwenden vollständige private Neuheitshistorie auch außerhalb des
begrenzten Modellkontexts und prüfen sie vor Veröffentlichung erneut. Reine
Begriffsfragen verbrauchen keine Zahlenkombination; mehrdeutige Zahlenangaben
bleiben geschlossen. Der globale alte Faktorparser wird dafür nicht gelockert.

Geplante Lernetappen prüfen ihren echten Grafikbedarf vor der vorhandenen
Routenwahl. Der Worker bewahrt die bereits reservierten Routenmetadaten;
der Transport verwendet in diesem eng geprüften Fall die schon freigegebenen
8.000 Ausgabetokens statt einer zusätzlichen versteckten 4.500er Begrenzung.
Andere Routen behalten ihre Grenze. Modell, Reasoning, Kostenreservierung,
Providerrevision, Quellenrechte und ausdrückliche Wiederholungsgrenzen werden
nicht geändert. Einzahltexte von Einstiegsfragen sind korrigiert; die alte
Formulierung bleibt ausschließlich als Neuheitsalias erhalten.

Der öffentliche Backendcode wird künftig beim Deployment als root-eigener,
nicht gruppen-/weltbeschreibbarer Bestand übertragen. Auf 139 wurde der bereits
ausgelieferte öffentliche Bestand mit 462 Dateien und sechs Verzeichnissen
bei identischen Inhalts-Hashes entsprechend geschützt. Geschützte Metadaten-
sicherung: `/root/schulpilot-qa139/public-code-139-7e4c76ad3fe5de461300e2808471b4fd`.
Appdaten, virtuelle Umgebung, Dienste und Einstellungen wurden dabei nicht
geändert. Ein ungeprüfter zusätzlicher Providerauftrag wurde daraus nicht abgeleitet.

Roots integrierter 140-Backendstand stimmt in allen 480 manifestierten Dateien
mit dem isoliert geprüften Verbund überein: 873/873 RAM-SQLite und 873/873
Unix-PostgreSQL16, ohne Fehler oder Skips. Die konkreten JUnit-Fallmengen sind
identisch, alle bisherigen 751 Fälle enthalten; 122 weitere Fälle prüfen die
Material-, Historien- und Routenübergänge. Ein unterbrochener PG-Erstlauf wurde
als unvollständig verworfen, bereinigt und auf unverändertem Stand wiederholt.
Sämtliche temporären Testdaten und Cluster wurden entfernt.

Ein davon getrennter UI-Nachlauf bestand 101 Widgetfälle in acht Dateien;
Analyse der drei geänderten Dateien ohne Befund. Lange unnummerierte Grafik-
Erklärungen erhalten ausschließlich zusätzliche sichtbare Absatzabstände an
sicheren Prosegrenzen. Originaltext, Suche, Vorlesen, Tutor-Kontext und gespeicherte
Schrittzahl bleiben erhalten; mehrdeutige Formeln, Code, Tabellen und Zitate
werden nicht aufgeteilt. Vollständige Originalbeispiele ohne gemeinsames Wort
beginnen ohne pauschale Unterstreichung; explizite Vergleichsschalter sowie
der vorhandene Buchstabenvergleich passender kurzer Formen bleiben verfügbar.
Dies sind lokale Nachweise; eine 140-Live-Abnahme wird damit nicht vorweggenommen.

## 26.10.2026 – Aktualisierung ohne Seitenverlust und weitere Bruchbeispiele (141)

140 wurde als `5e9854e`, Version 1.36.28+140, tatsächlich ausgeliefert.
Alle acht CI-Jobs waren erfolgreich: Backend 4.838 bestanden / 44 übersprungen,
Flutter 4.084 bestanden / 19 übersprungen. Öffentliche APK und Web-JavaScript
wurden vollständig geladen und mit dem gebauten Bestand verglichen; Signatur,
Quellversion, geschützte Konfigurationen und Dienste wurden geprüft. Ein neues
Live-Vorbereiten einer Heftrunde scheiterte danach vor dem Anbieteraufruf:
Der endliche Pool verwendeter Originalbeispiele war ausgeschöpft, Verbrauch null.
Eine getrennte lesende Diagnose bestätigte die ausdrücklich geschriebene
allgemeine Umwandlungsregel und das richtige Divisionsbeispiel in der Quelle;
ein unbekannt formulierter alter Umwandlungsauftrag war nicht die Ursache.

141 ergänzt deshalb ausschließlich bei dieser belegten Regel einen endlichen
Pool kleiner neuer unechter Brüche. Division, Ganzzahl, Rest, Antwort und
Grafikparameter werden vor dem Modellaufruf lokal berechnet. Die Regel und ihr
korrektes Originalbeispiel müssen aus derselben sicheren Quellenfassung stammen.
Ein Themenname oder ein einzelnes abgeschriebenes Zahlenbeispiel genügt nicht.
Werte sind bis auf Gleichwertigkeit eindeutig; vollständige eigene Historie
und die erneute Prüfung nach dem Aufruf bleiben verbindlich. Nur die ausgewählten
geschlossenen Aufgabenkerne erreichen das Modell, nicht der gesamte neue Pool.
Normale ungeplante Runden behalten ihre vorherige Kandidatengrenze.

Der Eltern-Lernüberblick benutzte alle 15 Sekunden den vollständigen Ladezustand.
Ein künstlicher Vorfix-Test reproduzierte das Entfernen der sichtbaren Übersicht.
Der Timer aktualisiert nun ausschließlich die Daten im vorhandenen Widgetbaum;
Entwürfe, Fokus, aufgeklappte Bereiche und Scrollposition bleiben bestehen.
Verdeckte oder pausierte Ansichten pollen nicht, überholte Antworten werden
verworfen, entzogene Zugriffe entfernen die alte Ansicht. Ein bewusster Refresh
bleibt möglich. Timer und Rückkehr lösen keine KI und keine Schreibaktion aus.

Nach einem erfolgreichen ausdrücklichen „Stimmt, weiter“ lädt die einzelne
Quellenansicht den ursprünglichen Schultag lesend neu und öffnet dessen nächste
noch zu prüfende Seite. Nach der letzten Seite folgt die Tagesübersicht.
Ein fehlgeschlagener Folge-GET wiederholt niemals die Bestätigung; neue Seiten
werden weder automatisch bestätigt noch verarbeitet. Andere Korrekturentwürfe,
Vokabelvorschauen, Klassenarbeitsquellen und gespeicherte Antworten bleiben erhalten.
Die Ergebnis-Hauptkarte zeigt außerdem keinen doppelten langen Rückblickabsatz
mehr; der bisherige Vollbericht bleibt erreichbar. Eine umfassendere kompakte
Lernbegleitung ist ein eigener anschließender Umbau.

Lokale integrierte Nachweise: 135 identische Fälle erfolgreich in isolierter
RAM-SQLite und Unix-PostgreSQL16, ohne externe Aufrufe; Testdaten und Cluster
wurden entfernt. Anschließend wurde nur die Backend-Versionszeichenfolge erhöht.
73 Flutter-Widgetfälle aus fünf Dateien bestanden gemeinsam, darunter 48 neue
Fälle; Analyse der sechs geänderten UI-/Testdateien ohne Befund. Die drei
isolierten UI-Nachbargates bestanden vorher 108, 82 beziehungsweise 40 Fälle;
überlappende Fälle sind keine zusätzlichen Live-Lernrunden.
Der Betreiber hat die 100-Runden-Testserie am 26.10. ausdrücklich beendet.
Ihr Abschlussstand sind 29 abgeschlossene allgemeine Heftrunden; die letzte
Testrunde war bereits beendet. Der anschließende fehlgeschlagene
Vorbereitungsauftrag hat keine weitere Runde erzeugt und zählt nicht mit.
Weitere Runden dieser Testserie werden nicht begonnen. Automatische Quellenprüfung, neue
Elternübersicht, kompakte Einzelrückmeldungen und Schulbuddy-Lesekontext werden
getrennt weiterentwickelt und sind durch diese 141-Nachweise nicht abgenommen.

## 26.10.2026 – Vorbereitungswege, Quellenprüfung und sichtbare Neuigkeiten (142)

Die live untersuchte Wiederholungsrunde verband zwei gespeicherte Ziele:
unechte Brüche als gemischte Zahlen darstellen und einen Bruch mit Zähler und
Nenner notieren. Der bisherige Ganzes-Rest-Compiler verlangte ausschließlich
Umwandlungsziele; der allgemeine Rechenplan unterstützte diese Kombination
ebenfalls nicht. Dadurch erzeugte das Modell Texte und Grafikparameter frei.
Zwei untersuchte Fehlversuche scheiterten nach dem Anbieteraufruf am
Zahlenvergleich zwischen Erklärtext und Grafik (`visual_parameters`).
Die verworfenen ursprünglichen Grafikparameter waren nicht gespeichert.

Der neue private Wiederholungsplan erhält beide tatsächlichen Aufgaben- und
Lernzielkennungen. Er kombiniert einen vorab berechneten Ganzes-Rest-Kern mit
dem bestehenden Bruchnotationsbeispiel aus `math.fractions.meaning`.
Diese versionierte eigene Grundlagenquelle bleibt als Zusatzwissen erkennbar;
sie wird weder zum Heftzitat noch zu einer weiteren Einstiegsdiagnose erklärt.
Fragen, Lösungen, Referenzen, Erklärschritttexte und Grafikparameter sind vor
dem Aufruf gemeinsam gebunden. Vollständige eigene Lernkette und Tagesfragen
schließen alte Werte aus; Quellen, Ziele, Referenzen und Historie werden nach
dem Aufruf erneut geprüft. Andere Verfahren behalten ihre bisherigen Verträge.
Modell, Denkstufe, 8.000 Ausgabetokens und vorhandene Reservierung bleiben erhalten.
Eine rein lesende Prüfung mit der freigegebenen aktuellen Quelle und Historie
ergab zwei neue, vollständig gebundene Kerne für beide ursprünglichen Ziele;
dabei wurde kein Anbieter aufgerufen und kein Lernnachweis verändert.

Die Glocke besitzt einen eigenen begrenzten Scrollbereich für alle geladenen
Neuigkeiten statt vier fester Vorschauen. Popup und Gesamtansicht bestätigen
nur tatsächlich gezeichnete, ausreichend sichtbare, unverdeckte Karten im
Vordergrund durch den bestehenden berechtigten POST. Vorgeladene und außerhalb
des Ausschnitts liegende Einträge bleiben ungelesen. Parallele Bestätigungen
werden geteilt, alte GET-Antworten können eine Lesemarkierung nicht zurücksetzen.
Im Ungelesenfilter bleiben soeben gelesene Karten bis zur nächsten bewussten
Filterwahl stehen; dadurch rutschen keine ungesehenen Einträge automatisch nach.
Fehler werden angezeigt und lösen keine Wiederholungsschleife aus.

Die automatische Heftprüfung verwendet einen getrennten persistenten zweiten
Foto-Lesedurchgang mit eigener normaler Reservierung. Unsichere Stellen und
sichtbare Schülerfehler bleiben erhalten; verwendbare Abschnitte können weiter
genutzt werden. Betriebsadministratoren wählen manuell/automatisch über eine
eigene revisionsgebundene Einstellung. Neue Installationen bleiben manuell.
Die kompakte Elternübersicht erhält Entwürfe und Scrollposition; kurze
Ergebniskarten beruhen auf gespeicherten Antworten statt einer neuen Bewertung.
Schulbuddy erhält in der ausdrücklich geöffneten bestätigten Heftseite deren
Wortlaut, vorhandene Markierungen und Unsicherheiten. Dies ist vom strengeren
Lehr- und Bewertungsfilter getrennt; ein Zugriff auf Originalpixel wird nicht
behauptet. Fertige Runden erhalten einen gespeicherten neutralen Hinweis mit
geprüftem direktem Rundenverweis. Geräte-Push bleibt freiwillig und getrennt von
In-App-Neuigkeiten; FCM-Annahme ist kein sichtbarer Android-Zustellbeleg.

Integrierte Backendabnahme: dieselben 213 Fälle unter isoliertem PostgreSQL16
vollständig erfolgreich; RAM-SQLite 209 erfolgreich und vier ausschließlich
für PostgreSQL geeignete Fälle übersprungen. Darunter ein tatsächlicher
API-/Reservierungs-/Worker-/Grafik-/Bereitschaftsmeldungsablauf mit künstlichen
Quellen und ausschließlich gemocktem HTTP. Quellbestände blieben unverändert,
Testdatenbanken wurden entfernt, externe Aufrufe waren gesperrt. Getrennte
vorherige Gates für automatische Prüfung, Tutor und Benachrichtigungen werden
nicht als zusätzliche Live-Lernrunden gezählt. Die beendete 100-Runden-Serie
bleibt bei 29 abgeschlossenen Runden.

Flutter: vollständige Analyse ohne Befund. Der gemeinsame Lauf umfasste 470
Fälle; 463 bestanden, sieben bestehende Erwartungen an die alte Vierervorschau
und ausschließlich klickbasierte Lesemarkierung passten nicht mehr zum neuen
Auftrag. Ausschließlich diese beiden Testdateien wurden angepasst. Der gezielte
Nachlauf aller betroffenen Header-/Downloadfälle zusammen mit Sichtbarkeit und
Inbox bestand 47 von 47 Fällen; die Produktdateien blieben unverändert.
Die neuen Fälle prüfen auch doppelte Schriftgröße, kleines Querformat,
abgeschnittene Karten, Überlagerung, Hintergrund, Kontowechsel, Scrollen,
Parallelität und fehlgeschlagene Lesemarkierungen. Lokale Tests ersetzen keine
nachfolgende Live-Abnahme oder sichtbare native Push-Zustellung.

Auslieferung142 tatsächlich erfolgt: Release `20261026T184440Z-e9b6f11`,
Produktcommit `e9b6f11b35e8af36bb8658ab7dc7f002afe89f3f`, Version
`1.36.30+142`, unverändertes Schema `0042`. Fünf Dienste aktiv; 17 frische
Konfigurationskopien und Google-Dateien erhalten. Signierte Direct-APK:
137178816 Bytes, SHA256
`6b733b822a2fc3c77a5bd1730ca05c504f5999e2eaced583f606f350c1e3328c`;
Play-AAB: 110873000 Bytes, SHA256
`e02a568d461bb47f15b8ffb57e3b76c26a2cee8df347882c47968ef4e9481afe`.
Öffentliche APK und Web-JavaScript wurden bytegenau abgeglichen. Die unmittelbar
vorherige Version141 bleibt als dokumentierter Rückweg vorhanden.

Nach dem Rollout wurde genau eine neue reguläre Wiederholungsrunde im konkret
freigegebenen Kinderzugang angefordert. Die Vorbereitung wurde erfolgreich
abgeschlossen; der neue In-App-Bereithinweis erschien. Öffnen der Glocke änderte
ihn von ungelesen zu gelesen, Anklicken öffnete direkt die eigene fertige Runde.
Das mobile Menü enthielt zwölf geladene Meldungen und ließ sich bis zu den
ältesten Einträgen scrollen; „Alle anzeigen“ führte zur scrollbaren Gesamtseite.
Nach dem Start ist die nicht-mehr-startbereite Runde erwartungsgemäß kein neuer
Bereithinweis mehr. Das Desktopmenü wurde zusätzlich mit elf älteren Meldungen
geprüft. Eine Ansicht mit neun einzelnen Vierteln ließ sich in zwei Ganze und
ein Viertel umschalten und zurück. Screenshots wurden außerhalb von Git abgelegt.
Es wurden keine Antworten abgegeben; die Einheit wurde pausiert. Die vorher
abgebrochene allgemeine Testserie bleibt bei 29 abgeschlossenen Runden.

Die automatische Heft-Gegenprüfung wurde danach mit einem ausschließlich lokal
verfügbaren, quellversionsgebundenen Operatorhelfer aktiviert: geschützte
Installation Revision4→5, nur der JSON-Wert `material_review_mode`, eigener
Auditbeleg und sofortiger erneuter Abgleich. Beide vorhandenen Providerzeilen
blieben im Datenbankvergleich unverändert, ebenso die übrigen Einstellungen.
Der erste geschützte Versuch verweigerte die Änderung wegen einer zu engen
Ein-Zeilen-Annahme und wurde vollständig zurückgerollt. Der minimale Nachtrag
prüft genau eine primäre Konfiguration und die Unverändertheit sämtlicher
vorhandener Zeilen. 25 lokale PostgreSQLfälle bestanden, darunter zusätzliche
Konfiguration, fehlende Primärzeile und vollständiger Rollback bei Änderung einer
Nebenzeile. SQLite: 16 erfolgreich/neun ausdrücklich PostgreSQL-exklusiv
übersprungen. Keine Produktdatei geändert; kein Bestandslauf oder Anbieteraufruf
durch Aktivierung.

Die vollständige CI40370452856 des Produktcommits endete mit fünf weiteren alten
UI-Erwartungen und einer alten Tutor-Erwartung als Fehlern. Die Nachträge ändern
ausschließlich Tests und Dokumentation: verschobene Erklärung vor Klick sichtbar
machen, sichtbare Inbox-Lesebestätigung zulassen und eng auf ihre IDs prüfen,
unbekannte und tatsächliche Nullnachweise in der kompakten Elternansicht weiterhin
unterscheiden sowie wörtliches Lesen strikt von Bewertungsgrundlagen trennen.
Die drei Flutterdateien bestanden 46/46 Fälle mit Analyse ohne Befund. Beide
Tutor-Dateien bestanden anschließend dieselben 20/20 Fälle jeweils unter
RAM-SQLite und PostgreSQL16, ohne externe Verbindungen; die künstlichen
Datenbanken wurden entfernt. Diese Nachläufe sind überlappende Regressionen und
werden nicht zu einer angeblich vollständig grünen ersten CI addiert.


## Alltagstest143 · 26.10.2026

Eigener regulärer künstlicher Haushalt, Klasse6, vier eigens erzeugte und visuell geprüfte Fotos (Mathematikheft, seitliches Arbeitsblatt mit roten Korrekturen, Deutsch/Satzglieder, Englisch/Simple past). Keine echten Kinderantworten. Nutzerfreigabe15USD für diesen Test; bestehende Anbieter-/Familiengrenzen bleiben aktiv. Erstlauf: sieben OCR-/Gegenprüfungsaufträge und ein Paketauftrag,257Sekunden vom ersten Claim bis zum Paketabschluss; eine Seite scheiterte an Markierungsmetadaten. Gemeldete Kosten0,124230USD, keine offene Reservierung zu diesem Zwischenstand. Kein vollständiger Vierseiten-Erfolg behauptet.

143 erhält den wörtlichen OCR-Text bei unzuverlässigen Zusatzannotationen: unbelegte Autorenschaft wird unbekannt, nicht verankerte Zitate werden entfernt und der betroffene Abschnitt ausdrücklich unsicher/vom bewerteten Lernen ausgeschlossen. Der bestehende Zweitleseauftrag kann ihn am Original klären. Quell- und Aufgabenvalidierung bleiben streng. Fertigmeldungen nennen bei offenen Fotos den tatsächlich bestätigten Teilumfang. Schulbuddy verwendet das aktuelle Betreiber-Systembudget statt einer veralteten Kopie der Modellbindung; keine Budgetkonfiguration geändert.

Fotoauswahl ohne doppelten Bestätigungsdialog; Zuschnitt zeigt das Foto vor optionalen Werkzeugen; Abgabe liegt vor der Fotoliste. Ausbleibende Browserfreigabe bleibt abbrechbar, verspätete Zustimmung registriert kein Gerät. Lokale Nachweise:55SQLite- und164Unix-PostgreSQL16-Fälle;77betroffene Flutterfälle plus21erneute Fotoassistentfälle einschließlich sichtbarer Hauptaktion bei vier Fotos; Flutteranalyse ohne Befund. PostgreSQL-Runner übernahm lediglich ein historisches base_commit-Textlabel; die tatsächlichen unveränderten Quelldateien sind durch Manifest1b7e6de3e39c76ec644a6ccc34ebb819043fe47f04564498692e900cf6541830 gebunden. Native Zustellung auf einem Smartphone ist damit nicht abgenommen.

Private Testzugänge, künstliche Fotos, genaue Prompts, Hashes, Messungen und Screenshots liegen außerhalb von Git unter artifacts/elements143/everyday. Der lokale Testhaushalt ist auf24Stunden,30Aufrufe und15USD begrenzt. Laufende Alltagstest-Abnahme und tatsächlicher Produktionsstand werden nach dem Deployment ergänzt; diese Zeilen behaupten noch keine143-Auslieferung.


Zusätzlicher belegter Alltagstest-Befund143: Die erste KI-Abschrift hatte gewöhnliche blaue Tinte flächendeckend als annotations.kind=unknown geliefert. Der unverändert konservative Quellenfilter schloss dadurch Mathematik und Deutsch vollständig aus. Das erweiterte endliche Schema unterscheidet nun ink (nur Schriftfarbe) von wirklichen Sondermarkierungen; die OCR-/Gegenprüfungsanweisung benennt diesen Unterschied ausdrücklich. Quellenpolicy literal-safety-2 lässt ink nicht als Korrektur gelten, behält unbekannte echte Markierungen, Schülerantworten und falsche Gleichungen weiterhin gesperrt. Alte unknown-Angaben werden nicht ungeprüft umetikettiert; ihre erneute Bildlesung bleibt eine ausdrückliche Aktion. Der erste143-Build wurde vor Auslieferung gestoppt, um diesen Befund gemeinsam zu korrigieren.

Der zusätzliche Tintenfix wurde mit131SQLitefällen (zwei ausschließlich aufPostgreSQL laufende Fälle übersprungen) und92PostgreSQLfällen geprüft. Normale Tinte in drei Fächern bleibt verwendbar; echte unbekannte Markierungen, Schülerantworten und falsche Gleichungen bleiben gesperrt. Fertigmeldungen sagen nur „Lernpaket bereit · n von m Fotos noch offen“, ohne alle bestätigten Fotos als tatsächlich verwendete Lernquellen auszugeben.


## Alltagstest144 · nächste Korrekturstufe

143 wurde als20261026T202130Z-560985c (Produktcommit560985cdb8f080527cbe599bb45eaef8ade7b23d) ausgeliefert und öffentlich gegen die tatsächlich gebauten Web-/APK-Bytes geprüft. Alle fünf Appdienste aktiv, Schema0042,17Konfigurationen erhalten. Direct-APK137162432Bytes/SHA2564b17c7fc3ab9afaec2ba5ea83a79836dc2c6e88674d236d2af8e1b8ea96cb533; Play-AAB110871784Bytes/SHA256aa11defda8cb02f35172f221a1d577e1233011f06634457b6e000e7d8531c79b.

Der erneute echte Leseauftrag des seitlichen künstlichen Arbeitsblatts lieferte einen vollständigen ersten und zweiten Durchgang (je348Zeichen/8Blöcke). Die lokale Schutz-Zusammenführung verkürzte dies jedoch auf201Zeichen/5Blöcke: spätere grobe Bildüberlappungen entfernten bereits erhaltene frühere Abschnitte.144 sammelt geschützte Repräsentanten getrennt und fügt sie erst nach dem Vergleich ein. Bildkoordinaten allein löschen keinen Abschnitt mehr; lediglich eindeutige sichtbare Aufgabennummern können einen Ersatzblock zuordnen. Unzuordenbare Alternativen bleiben unsicher. Beide Rohlesungen und der ursprüngliche Wortlaut bleiben erhalten, check_contract_revision wird literal-image-countercheck-2. Bloße Tintenmetadaten frieren normale Lesefehler nicht ein.

Die Quellenansicht hatte außerdem gestrichene60und ergänzte40nebeneinander als6040angezeigt.144 stellt solche Originalmarkierungen mit ausdrücklich beschrifteten Karten dar, streicht das Zitat sichtbar durch und nennt Ergänzungen nicht pauschal richtig. Die vollständige unveränderte Abschrift bleibt separat aufklappbar. Wiederholte Zahlen werden keiner geratenen Textposition zugeordnet. Gewöhnliche Tinte erhält keine Korrekturkarte; veraltete Blockstruktur wird weiterhin verworfen.

Der offene Materialscreen beobachtet ausschließlich seine bereits laufende automatische Gegenprüfung mit GET, ohne Route-/Dokumentneuladen oder erneute KI. Aktualisiert wird der bestehende Editor; ein eigener Entwurf wird bei neuer Quellrevision erhalten und als Konflikt gezeigt. Beobachtung endet bei Fertigstellung, verdeckter Route, Hintergrund, Abmeldung oder Dispose. Der weitergehende SSE-/Lazy-Ausbau bleibt auf ausdrücklichen Prioritätswechsel hin pausiert.

Vorbereitende lokale Abnahme:92SQLitefälle bestanden, zwei PostgreSQLfälle dort übersprungen;81PostgreSQLfälle bestanden.42integrierte UI-Fälle und drei zusätzliche Entwurfs-/Statusfälle bestanden; drei Korrektur-Kartenfälle auf320/1024px bestanden. Die bereits bestandenen weiteren Formelsatz-/Quellenfälle wurden getrennt ausgeführt; erste Testlocatorfehler sind in den lokalen Logs erhalten. Flutteranalyse ohne Befund. Tatsächliche144-Auslieferung und neue Foto-Abnahme werden erst nach Prüfung ergänzt.


144 tatsächlich ausgeliefert: `20261026T205002Z-70225d4`, Quellcommit `70225d43fcb084c8e5bf274438de36b87accd74b`, Version1.36.32+144, Schema0042. Fünf Dienste aktiv,17Konfigurationen erhalten, öffentliche Web-/APK-Bytes abgeglichen. Direct-APK137178832Bytes/SHA256442244391c3491609abe0e38f904a94f932c53827b96228e752245cfbe494e1d. Vollständige CI40389201927 erfolgreich; ebenso die vorherige143-CI40385119478.

Drei echte Browserimporte der künstlichen Mathematik-/Deutschfotos mit Drehung und Zuschnitt wurden unter144 erneut normal abgegeben. Alle drei OCR-/Zweitlesungen erfolgreich; ein zeitweise auf about:blank geschlossenes Appdokument hielt den Serverablauf nicht an. Das seitliche Arbeitsblatt behält8Blöcke/348Zeichen einschließlich der geprüften Originalgleichungen und getrennten Korrekturmarkierungen. Keine stillen Ersatzgleichungen. Die leistungssichere Projektion schließt weiterhin unleserliche/markierte Schülerantworten aus. Screenshot14-korrekturkarten-mobil.png und eigene Quellenprojektionen liegen unter artifacts/elements143/everyday; keine echten Kinderdaten in diesen Testbelegen.

## Alltagstest145 · feste Vorwissensfrage und Grafik

Der erste neue Mathematik-Teilauftrag brach nach einer Sekunde lokal vor dem HTTP-Versand ab. Ein ausschließlich lesender Replay des eigenen künstlichen Auftrags, PostgreSQL-Schreibschutz und gesperrtem externem Transport, belegte den Konflikt: Die feste Frage „2von3Teilen“ enthält absichtlich nicht ihre Antwort2/3; der allgemeine Grafikvertrag verlangte jedoch einen ausdrücklichen n/d-Anker im Fragetext. Eine Komponentenfrage konnte zusätzlich hinter acht früheren Foto-Beispielen ihre einzige Grafik verlieren. Dies war kein unvollständiger Modelloutput.

Die Korrektur bindet solche festen Fragen über vollständigen unveränderten Kern, kuratierte Regelversion/-digest, Beispiel-ID/-digest, Fach und Gruppe an ihr vorhandenes servergeprüftes Beispiel. Diese Grundlagenkandidaten werden vor allgemeinen Foto-Beispielen berücksichtigt; Antwortgrafiken werden nur als Lösung angeboten. Andere Fragen behalten den ausdrücklichen Bruchanker. Keine Frage, Lösung, Quelle oder alte Runde wird umgeschrieben, keine grafische Qualitätsprüfung entfernt, kein automatischer Anbieterretry eingeführt. Die tatsächliche neue Auslieferung und erfolgreiche Paketwiederholung sind noch separat zu prüfen.

Lokale145-Abnahme:231Fälle auf isoliertem RAM-SQLite bestanden, darunter der echte Adapter mit vollständiger künstlicher Antwort sowie ein Versandgrenzen-Replay des exakt gescheiterten eigenen Payloads.55betroffene Fälle zusätzlich auf einem separaten Unix-PostgreSQL16 bestanden. Keine externe KI, keine übernommenen Anbieterumgebungen, beide temporären Datenbanken entfernt, Quellmanifest während der Läufe unverändert. Ruff und Diffprüfung ohne Befund. Ein anfänglicher Sandboxlauf hing beim ASGI-Teststart und wurde abgebrochen; der isolierte Nachlauf außerhalb der Sandbox ist der erfolgreiche Nachweis.


145 tatsächlich ausgeliefert:20261026T211952Z-7d1f842, Quellcommit7d1f842e795dbb4a75608eef788f3db2b54d866e, Version1.36.33+145. Öffentliche Direct-APK137178832Bytes/SHA256f0ed8d547d6df64edf8c5f75ebc4b59633c820879eec3832c23389110415fc87 und Web-JavaScript bytegenau geprüft.17Konfigurationen erhalten, fünf Dienste aktiv, Schema0042 unverändert. Der reale künstliche Mathematik-Teilauftrag wurde in22Sekunden erfolgreich gespeichert. Die vorhandene ausdrückliche Teilfreigabe erzeugte ohne weiteren Provideraufruf die Runde; die zunächst als fragwürdig eingeschätzte Schaltfläche funktioniert wie vorgesehen. Die echte Kreis-/Balkenansicht und der Nennerfokus wurden im Browser bedient und fotografiert.

## Alltagstest146 · Originalsatz-Darstellung

Der getrennte Deutschauftrag erreichte die visuelle Prüfung und wurde verworfen;49,205Sekunden Anbieterzeit und0,043432USD gemeldet. Der alte genaue Modellinhalt wurde aus Datenschutzgründen nicht gespeichert. Aus dem generischen Diagnosecode darf keine bestimmte einzelne falsche Modellmarkierung als bewiesen behauptet werden. Der unveränderte eigene Payload wurde rein lesend mit gesperrtem Transport nachgebaut: Es war noch kein vorbereiteter Satzgrafik-Pfad verfügbar. Die normale Rollen-Grafik erlaubt nur ausdrücklich im Quellenzitat belegte Markierungen; ein Aufgabenheader allein belegt keine solche Zuordnung.

146 ergänzt für ausdrücklich belegten deutschen Satzgliederstoff vollständige kurze Originalsatz-Zeilen als wortgetreue, unmarkierte Wortkästen im vorhandenen Renderer. Ein Wortkasten wird ausdrücklich nicht als automatisch bestimmtes Satzglied ausgegeben. Keine Rollen, Umstellungen oder zusätzlichen Quellen werden erfunden. Jede Frage nennt ihren vollständigen Originalsatz; Quelle, Referenzversion, Plan, Stufe und Frage bleiben gemeinsam gebunden. Alte Wortbaustein-/Pfeil-/Listenpfade bleiben erhalten. Geschlossene Diagnosetags für fehlende Rollenbelege und ungültige Listenfokusse enthalten keinen Originaltext und ändern keine Abrechnung.

Abnahme:143betroffene Fälle auf isoliertem RAM-SQLite,30Fälle auf separatem Unix-PostgreSQL16 einschließlich Teilfreigabe, ein weiterer gesperrter Versandgrenzen-Replay des exakt betroffenen künstlichen Deutschpayloads. Der Replay prüft ausdrücklich, dass nun package-original-sentence-1 angefordert wird. Alle erfolgreich; temporäre Datenbanken entfernt, Quellmanifeste unverändert, keine externe KI durch diese Tests. Tatsächliche146-Auslieferung und Deutschwiederholung bleiben anschließend zu prüfen.


146 tatsächlich ausgeliefert:20261026T214016Z-d938b18, Produktcommitd938b182608bc9ff96537cdd558a15d761cfbf2f, Version1.36.34+146, Schema0042. Signaturen, unabhängiger Geheimnisscan,17gesicherte Konfigurationen, fünf aktive Dienste und öffentliche Web-/APK-Bytes geprüft. Direct-APK137178832Bytes/SHA256f53a4869b59bbd529642c087eee5a6630331c15632e1720cbd16d4292da59d9e. Der erste Build wurde nach den Kompilierungen mitSignal143 beendet; kein vollständiger Abschlussbeleg, nicht ausgeliefert. Der quellgleiche vollständige Nachlauf bestand und ist der Auslieferungsnachweis. Vollständige CI40396523859 erfolgreich; auch145-CI40393795516 erfolgreich.

Der eigene künstliche Deutsch-Teilauftrag wurde nach dem Fix in40Sekunden erfolgreich abgeschlossen. Die neue Fertigmeldung führte direkt zur noch offenen Deutschrunde statt zur schon abgeschlossenen Mathematik. Die erste Frage verlangt ausdrücklich das vollständige Subjekt in „Der Hund schläft.“; die absichtliche Auswahl „Hund“ wurde als unvollständig erkannt. Eine weitere gezielte Mathematikrunde entstand in31Sekunden; ihre In-App-Fertigmeldung zeigte einen ungelesenen Eintrag, wurde beim Öffnen als gelesen bestätigt und öffnete direkt die passende Einheit. Beide Mathematikrunden und Englisch wurden abgeschlossen. Eltern-GET:6Aufgaben/6Versuche,3selbstständig,2unterstützt,1unklar; bloßes Erkunden erzeugte keine zusätzlichen Antworten.

## Alltagstest147 · Grafik beim bewussten Erklärabruf

Die echte Deutsch-Erklärung lieferte zunächst nur Text. Der gespeicherte Grafikstatus war ready; die eigene erste Frage besaß eine geprüfte hint1-Grafik, die zweite eine hint2-Grafik. Der ausdrückliche Erklärendpunkt rief die geschlossene Fragenprojektion mit hints=0 ab und blendete dadurch auch zulässige Hinweisgrafiken aus. Die147-Korrektur fordert bei genau diesem ausdrücklichen Einzelaufgaben-Abruf hints=3 an. Normale GETs und fremde Fragen erhalten keine zusätzliche Freigabe; Quellen-/Versionsschutz bleiben erhalten. Die Hilfe wird weiterhin vor einer neuen Antwort erfasst und erzeugt weder Attempt noch KI-Aufruf. Keine gespeicherte Antwort oder Grafik wird umgeschrieben.

79betroffene RAM-SQLitefälle und66Unix-PostgreSQL16-Fälle bestanden. Die echten lokalen API-Fälle prüfen hint1/hint2/hint3/solution einschließlich Grafikblock, unveränderte Originalfragen, verborgene zweite Aufgabe,0neue Attempts/Usage durch Öffnen, unterstützte anschließende Antwort und Quellrevisionen. Beide Testdatenbanken wurden entfernt, Quellmanifeste blieben unverändert. Auslieferung147 und erneute Live-Abnahme folgen separat.


147 tatsächlich ausgeliefert: `20261026T220259Z-670f1b0`, Produktcommit `670f1b09f5eea2056c2cf89bfbf456ec140ae8b3`, Version1.36.35+147, Schema0042. Die unveränderten Release-Skriptbefehle wurden mit exakter Quell-/Skriptbindung in getrennten Stufen ausgeführt; alle fünf echten Stufen-Exitcodes0, vollständiger Abschlussbeleg. Web, Direct-APK und Play-AAB unabhängig signatur-/versions-/geheimnisgeprüft. Öffentliche APK137178832Bytes/SHA256a8eaa6c0c0eb3ce670ba03dd3d6e24d2fe882a1f94f308285407e65211b8937d und Web-JavaScript bytegenau abgeglichen.17Konfigurationen erhalten, fünf Dienste aktiv, Google-Nachweise und Sicherung erhalten. Rückweg146 ohne Datenbankrestore.

Die laufende künstliche Deutschrunde wurde vor dem Deploy pausiert. Danach unverändert7Aufgaben/7Versuche/548Aktivsekunden; kein Zeitnachtrag. Beide gespeicherten hint1-/hint2-Grafiken erschienen anschließend beim bewussten Erklärabruf tatsächlich im Browser, ohne neuen Modellaufruf. Die erste falsche Auswahl „Hund“ und der unterstützte richtige zweite Versuch „Der Hund“ bleiben beide gespeichert. Die zweite richtige Antwort „spielt“ bleibt selbstständig, obwohl danach ihre Erklärung geöffnet wurde. Der Abschluss trotz offenem Tagesminimum funktionierte; der reguläre Rückblickauftrag wurde erfolgreich gespeichert.

Abschlussbeleg:4Runden/8Aufgaben/9Versuche,4selbstständig,3unterstützt,1unklar,0laufendeRunden. Alle vier Grafiksnapshots ready.26reservierteAufträge, davon ein belegter lokaler Vorversand-Abbruch;24OpenRouter-Generierungsbelege mit insgesamt0,540366USD.0,40USD konservativ offen reserviert, nicht als tatsächliche Abbuchung ausgegeben. Endgültiger Gerätestatus:0autorisierte/0unautorisierteAndroidgeräte; keine native Zustellung behauptet. [Ausführlicher Bericht](EVERYDAY_TEST_2026_10_26.md).147-CI-Abschluss folgt im nächsten Absatz.


Vollständige147-Produkt-CI [40399816000](https://github.com/meinzeug/schulpilot/actions/runs/40399816000) für exakt670f1b09f5eea2056c2cf89bfbf456ec140ae8b3 abgeschlossen und erfolgreich. Alle Backend-/Flutter-Shards, Analyse/Webbuild und aggregierten Gates grün. Der abschließende Dokumentationsnachtrag ändert ausschließlich README, Quellen-/Statusbericht und den neuen Alltagstestbericht; kein weiterer Laufzeitcode oder Buildartefakt wird dadurch verändert. Browsergröße auf den tatsächlichen Standard1101×884zurückgesetzt; der eigene künstliche Gesamtlernstand bleibt als Ergebnis geöffnet.


27.10.2026 · Lernweg-Konsistenz148: auditierte, auf den ausdrücklich genannten Haushalt begrenzte Produktionsdiagnose. Beide alten Quellenhashes ließen sich exakt aus der heutigen vollständigen sicheren Projektion rekonstruieren, wenn ausschließlich `policy_version` auf `literal-safety-1` gesetzt wurde. Kein abweichender Inhalt oder alter Quarantänestand wurde übernommen. Ursache und neue Verträge: [STUDY_PATH_RELIABILITY.md](STUDY_PATH_RELIABILITY.md). Keine neuen Modellkennungen, Anbietergrenzen oder Preisannahmen.

27.10.2026 · Freigegebener Produktions-Reparaturversuch unter148: vier kgV-Aufgaben, vier gespeicherte Erklärgrafiken, Grafikstatus bereit, eine neutrale In-App-Bereitmeldung. Serverseitige Auftragslaufzeit38Sekunden, OpenRouter-Kostenbeleg57.676Mikro-USD (0,057676USD), Reservierung250.000Mikro-USD. Antworten und gespeicherte Lernsekunden unverändert.149 begrenzt den neuen Kompaktvertrag auf2–5Aufgaben, nachdem die vollständige CI den unverändert zu unterstützenden Ein-Aufgaben-Klassenarbeitsfall aufgedeckt hatte. Kein zusätzlicher bezahlter Wiederholungsaufruf dafür. Die Browser-Abnahme im echten Kinderkonto wartet auf dessen normale Anmeldung; technische Produktionstests sind kein Ersatz für eine behauptete sichtbare Android-Zustellung.

27.10.2026 · Gesamt-CI149: Der feste Rechenauftrag ohne Grafikvertrag muss seine bisherige Zweiblock-Darstellung behalten. Der grafische Etappenpfad erhält weiterhin einen kompakten Schritt und danach einen Schema-konformen Darstellungskatalog. Der zweite Fehler war eine vorab geplante Vorwissensprobe, die noch nicht als numerisches Ausschlussbeispiel für neue Erweiterungsaufgaben galt.150 korrigiert Material- und Heftauswahlpfad vor dem Provideraufruf, erhält die späte Wiederholungsprüfung und prüft64gesteuerte Seeds je Pfad.

27.10.2026 · Produktionsabgleich150: Beide autorisierten Lernwege aktuell/fortsetzbar, keine falschen Prüfhinweise, vorhandene Bruch-Anschlussrunde mit eindeutiger Quellenherkunft. Vorhandene vier kgV-Aufgaben und Grafiken bleiben bereit; eine In-App-Bereitmeldung, Antworten und Lernsekunden unverändert.290 RAM-SQLite- und101 Unix-PostgreSQLfälle bestanden. Öffentliche Web-/APK-Bytes gegen den quellgebundenen signierten Build geprüft;17 Konfigurationen unverändert. Die sichtbare Browser-Abnahme wartet auf normale Anmeldung; vollständige Gesamt-CI zum Berichtszeitpunkt noch offen.

27.10.2026 · Abschluss-CI und sichtbare Abnahme150: [40472929059](https://github.com/meinzeug/schulpilot/actions/runs/40472929059) für `dd99881f3ae828df5164b39a5721fbc2f680e50c` erfolgreich; alle Backend-/Flutter-Shards, Analyse/Webbuild und aggregiertes Gate. Gegen Produktcommit `01644af7608129f50374de52d248d83e86488c85` ausschließlich Dokumentationsunterschiede. Nach normaler Kinderanmeldung und Neuladen reale Browserprüfung bei1101×884und390×844: keine falschen Quellen-Prüfhinweise, korrekte Herkunft/Verknüpfung der gespeicherten Anschlussrunde, beide Lernwege erreichbar. Die echte kgV-Etappe mit vier Aufgaben ließ ihre Erklärung und Grafik öffnen; Vorwärtswechsel und Zurücksetzen geprüft. Ohne Antworten wieder pausiert, danach öffnet Heute genau diese Runde. Aktive Sichtprüfung zählt reguläre Lernsekunden; kein Leistungsnachweis und kein weiterer KI-Auftrag dadurch. Screenshotbelege ausschließlich lokal im ignorierten Artefaktverzeichnis, keine privaten Seiten oder Inhalte im Repository.

Eine korrekte kgV-Bereitmeldung ist serverseitig belegt. Ihre Ausblendung nach dem Rundenstart entspricht dem bestehenden Vertrag für noch nicht begonnene Runden. Ein anderer sichtbarer Glockeneintrag öffnete seine eigene ältere Anschlussrunde korrekt. Im zweiten Lernweg bleibt ein historischer Deutsch-Erzeugungsfehler sichtbar; ein erfolgreicher neuer Lauf ist noch nicht belegt. Der automatische Freigabecheck lehnte den weiteren regulären kostenpflichtigen Versuch wegen der auf einen Reparaturaufruf begrenzten konkreten Freigabe ab. Separate Nutzerfreigabe angefragt; kein alternativer Aufruf, keine gelockerten Limits, keine Testantworten und keine behauptete Android-Zustellung.


28.10.2026 · Fachbezogenes Lernen151: bestehende Hefte-Fachzeilen, Fachpiktogramme und optionale Cover wiederverwendet. Der vorhandene individuelle Plan bleibt die Datenquelle. Stabile Fach-IDs und bestehende Aliase filtern die neue Themenansicht; keine Ableitung neuer Fächer aus Fotos oder KI-Ausgaben. Themen vor der Seitenteilung bündeln, eine Metadatenvorschau je Karte und getrennte begrenzte Einzelrundenliste mit erhaltenem Reiter. Zufallsauswahl gleichverteilt über alle aktuell startbaren Themen, nicht über die sichtbare Seite oder die Anzahl vorhandener Runden. Normaler Rundenstart und idempotenter Etappenauftrag erhalten; reine GET-Auswahl ohne Reservierung oder Leistungsbeleg. Verträge: [LEARNING_SUBJECTS.md](LEARNING_SUBJECTS.md).

79 RAM-SQLitefälle und dieselben79 Unix-PostgreSQL16-Fälle mit unveränderten Quellmanifesten bestanden; beide Wegwerfdatenbanken entfernt.94 Flutterfälle einschließlich320px/großer Schrift, Fach-/Themenwechsel, Zufallsstart, Statusnavigation, Sessionwechsel und bestehender Workspace-Navigation bestanden. Vollständige Produkt-CI [40642924278](https://github.com/meinzeug/schulpilot/actions/runs/40642924278) für `d7ef7e3776036d04327d640c1340f10029c43301` erfolgreich. Ein äußerlich unterbrochener APK-Build wurde regulär erneut abgeschlossen; nur der vollständige erfolgreiche Fünfstufenbeleg bindet die veröffentlichten Artefakte.

Release `20261028T072845Z-d7ef7e3`, Version1.37.0+151, Schema0042 tatsächlich ausgeliefert. Fünf Dienste aktiv,17 gesicherte Betriebskonfigurationen und Google-Nachweise unverändert, vorheriger Release150 erhalten. Direct-APK, Play-AAB und Web aus demselben sauberen Produktcommit; Signaturen/Manifest/Geheimnisse geprüft. Öffentliche vollständige APK und JavaScript bytegenau abgeglichen. Tatsächlicher Browser-Zufallsstart nur im künstlichen lokalen Konto,0Providerjobs/0Usage/0Antworten; regulär wieder pausiert. Produktion zusätzlich lesend bei Desktop und390×844 geprüft, einschließlich gebündeltem Verlauf und passendem Einzelrundenfilter. Temporäre künstliche Datenbank/Zugangsdaten entfernt, Screenshots nur im ignorierten lokalen Artefaktverzeichnis. Keine Kinderdaten oder privaten Fallkennungen neu im Repository; keine sichtbare native Geräteabnahme behauptet.

29.10.2026 · OpenRouter-Generierungsmetadaten: [Generation API](https://openrouter.ai/docs/api/api-reference/generations/get-generation) dokumentiert getrennte native und allgemeine Tokenzähler sowie Abschlussgründe. Zwei ausdrücklich künstliche Fehlversuche wurden anhand ihrer eigenen Generierungsbelege überprüft; Ergebnisse und Grenzen stehen in [EVERYDAY_QA_2026_10_29.md](EVERYDAY_QA_2026_10_29.md). Keine privaten Antworttexte oder Denkinhalte gespeichert.
# 29.10.2026: Selbstständigkeit nach geöffneter Erklärung

Die serverseitigen, bereits vorhandenen Öffnungsbelege werden für neue
Antworten derselben Einheit berücksichtigt. Der Unterschied zwischen einem
belegten Treffer und einem lediglich möglichen Zusammenhang sowie die Grenzen
der Erfassung sind in [EXPLANATION_EVIDENCE.md](EXPLANATION_EVIDENCE.md)
beschrieben. Historische Antworten werden nicht umgeschrieben. Die weiterhin
offene allgemeine Ursache der abgeschnittenen KI-Ausgaben wird hierdurch nicht
als behoben behauptet.

30.10.2026 · Isolierter mobiler Alltagstest: Eine künstliche englische Seite wurde vom
Erkennungsmodell mit dem Fachlabel `English` versehen. Dieses Label fand keine
passende bestehende Grafikreferenz; der folgende künstliche Paketaufruf scheiterte
mit HTTP 400 und der geschlossenen Anbieterkategorie `invalid_json_schema`.
Auch eine flachere Grafikstruktur allein beseitigte diesen Fehler im erneuten
künstlichen Diagnoseaufruf nicht. Mit demselben künstlichen Inhalt und dem
Katalogfach `Englisch` lieferte ein regulär reservierter OpenRouter-Aufruf eine
vollständig validierte Paketantwort (HTTP 200, gemeldete Kosten 0,040076 USD).
Die beiden Fehlantworten besitzen keine bestätigten Kostenbelege und bleiben
entsprechend reserviert; sie sind nicht als kostenlos nachgewiesen.

Die eindeutige OCR-Fachbezeichnung `English` wird künftig bei Erkennung und
Bestätigung auf den Titel des vorhandenen versionierten Fachkatalogs abgebildet;
Inhalt und unbekannte Fachbezeichnungen bleiben unverändert. Bereits bestätigte
Quellen werden nicht nachträglich umgeschrieben. Für eine ausdrücklich gemeldete
Schemaablehnung liefert der Adapter eine technische Fehlerkategorie statt der
unbelegten Behauptung, Schlüssel oder Kontingent seien falsch. Dies behebt nicht
allgemein alle möglichen Anbieter-Schemafehler und ersetzt keinen vollständigen
monatlichen Alltagstest. Die beiden diagnostischen Fehlversuche und der Erfolg
verwendeten ausschließlich künstliche Materialien; alle Aufrufe sind in der
isolierten Testkostenrechnung erfasst.

Beim tatsächlichen Fortsetzen nach einer ausdrücklichen Quellenkorrektur zeigte
sich im 390-Pixel-Browser außerdem: Die historische Fehlerkategorie konnte die
Hauptaktion trotz serverseitig erlaubter neuer Planung verdecken. Die Kinderansicht
bietet bei geänderter Quelle nun den bewussten Neustart an, sofern der Server
`can_retry` meldet und keine aktuelle Sperre übermittelt. Aktuelle Sperren,
Quellenrevisionen, Versuchsgrenzen und der explizite einzelne POST bleiben erhalten.
Die mobile Prüfung verwendet ausschließlich die getrennte künstliche Familie;
die simulierte Uhr gilt nur für deren Testprozesse.

30.10.2026 · Geschichtsprobe im isolierten 390-Pixel-Alltagstest: Bei einer
bestätigten künstlichen Quelle ohne Datumsangaben wurde eine leere Kalendergrafik
mit dem Status bereit gespeichert; die App zeigte keine brauchbare Darstellung.
Die beiden dazugehörigen Fragen blieben quellengerecht, die Grafik war es nicht.
Ein neuer Kalender-Erklärschritt benötigt mindestens zwei unterschiedliche, im
wörtlichen Beleg geordnete Einträge. Bestehende unvollständige Kalendergrafiken
werden im Client mit einem Hinweis statt einer leeren oder abstürzenden Grafik
gezeigt; gespeicherte Antworten und Quellen bleiben erhalten.

Ein neues versioniertes eigenes Geschichtsrezept erlaubt außerdem den Vergleich
von zwei bis vier vollständigen, aufeinanderfolgenden Originalsatzzeilen ohne
hinzuerfundene Pfeile oder Chronologie. Quelle, Reihenfolge und auswählbare
Originalaussagen werden vor und nach dem KI-Transport geprüft. Die erste echte
künstliche Probe wurde wegen einer falschen Referenzzuordnung zurückgewiesen
(0,032171 USD gemeldet); nach der Codekorrektur lieferte ein separater regulär
reservierter künstlicher Auftrag eine validierte Satzszene und zwei Fragen
(0,030512 USD gemeldet). Der Test beweist nicht, dass beliebige Seiten oder
alle zukünftigen Modellantworten gelingen. Einfache Zweischritt-Grafiken mit
unveränderter Position und Beziehung zeigen die Schritte direkt; Wiedergabe und
weitere Werkzeuge bleiben bei Bedarf erreichbar.

30.10.2026 · Neuerkennung einer ungeprüften Tagesseite: Der mobile Alltagstest
zeigte, dass „Mit KI neu lesen“ bisher eine separate Kopie anlegte. Die
ursprüngliche Seite blieb dadurch im Schultag ungeprüft, obwohl die Kopie
bestätigt wurde. Für noch unbestätigte Tagesseiten ohne verknüpfte Lernrunden
oder Aufträge aktualisiert ein ausdrücklich gestarteter, regulär reservierter
Leselauf nun dieselbe Seite. Die bestehende Quellenhistorie bleibt erhalten;
Sitzung, Anbieter, Seitenrevision, vollständiger Seitenstand und neue
Verknüpfungen werden vor und nach dem Aufruf geprüft. Bei konkurrierender
Änderung wird keine alte Abschrift überschrieben. Bestätigte oder bereits
verknüpfte Seiten behalten den bisherigen geschützten Kopierweg.

Die erste Bruchabschrift im künstlichen Test enthielt beide lesbaren Gleichungen
bereits; ihre Darstellung in der aufgeklappten Ansicht war beim ersten Ablesen
noch nicht vollständig geladen. Ein erneuter echter künstlicher Leselauf
verwendete mit der Korrektur dieselbe Tagesseiten-ID und erzeugte keine weitere
Kopie; nach ausdrücklicher Bestätigung führte die App zurück zum Tagespaket.
Diese Beobachtung ist kein allgemeiner Nachweis vollständiger Bilderkennung.

30.10.2026 · Biologieprobe: Ein echter künstlicher Paketauftrag fragte nach
„Fotosynthese“, obwohl der Begriff in der bestätigten Seite und der sichtbaren
Einführung fehlte. Ursache war ein Widerspruch im vorbereiteten Grafikvertrag:
Er verlangte das Fachwort unabhängig vom Quelltext. Für die exakt belegte
Pflanzen-Darstellung bindet der Vertrag Fragen nun an das tatsächliche Vorkommen
des Begriffs; ohne Beleg muss die Frage verständlich von Pflanzen sprechen.
Eine zusätzliche Prüfung verwirft diesen konkret beobachteten unvorbereiteten
Begriff auch außerhalb dieses Grafikvertrags. Sie ist keine allgemeine Garantie
für die Verständlichkeit aller Fachbegriffe.

Der erste separat reservierte künstliche Kontrollaufruf wurde durch die neue
Prüfung zurückgewiesen (0,025941 USD gemeldet). Nach Beseitigung des widersprüchlichen
Grafikvertrags lieferte ein weiterer regulär reservierter Aufruf eine validierte
Einführung und zwei Fragen ohne das fehlende Fachwort (0,025276 USD gemeldet).
Bestehende Aufgaben und Antworten werden nicht verändert. Zweistufige Grafiken
ohne Abspielbewegung zeigen außerdem keine deaktivierten Wiedergabeknöpfe mehr;
beide Schritte und weitere Werkzeuge bleiben erreichbar.

30.10.2026 · Mobiler Alltagstest mit ausschließlich künstlichem Material:
Eine kurze Seite „Brüche vergleichen“ führte zuerst zu zwei Vorwissensfragen
und danach fälschlich zur Meldung, alle Etappen seien bearbeitet. Der Lernweg
ergänzt jetzt bei serverseitig belegten reinen Vorwissensrunden eine begrenzte
Anwendungsetappe pro Fach. Bei bereits bestehenden Plänen erfolgt die
Ergänzung nach ausdrücklicher Auswahl; gespeicherte Runden und Antworten bleiben
unverändert. Eine Etappe wird weiterhin erst nach eigener Aktion erzeugt.

Der Mathematikplaner verwechselte darüber hinaus ein Vergleichsthema mit
dem Benennen von Zähler und Nenner. Für das ausdrücklich erkannte Thema
verwendet er korrekte, wörtlich belegte Vergleichspaare, einschließlich der
bei der OCR verwendeten LaTeX-Bruchschreibweise. Er leitet daraus keine
unbelegte allgemeine Rechenregel ab. Eine zusätzliche Prüfung hält Aufgaben
zurück, die bei dieser belegten Anwendung keine Vergleiche oder keine
passende Lösung enthalten. Ein echter, separat reservierter künstlicher
Modellaufruf erzeugte zwei geprüfte Vergleichsfragen; gemeldete Kosten:
0,049122 USD. Eine vorherige Probe ohne LaTeX-Erkennung erzeugte zwar
Vergleichsfragen, belegte aber die neue feste Zuordnung noch nicht
(0,052710 USD). Das ist keine Garantie für andere Themen oder Anbieterantworten.
Für den festen Fragetyp werden die beiden angebotenen Brüche und der
gespeicherte Lösungsschlüssel außerdem rechnerisch geprüft: Die falsche Wahl
erhält eine kindgerechte Rückmeldung; andere Eingaben bleiben unklar.

Bei einer weiteren künstlichen Geschichtsseite wurde ein ungeeigneter
Zeitstrahl zurückgewiesen. Die belegten Sätze waren innerhalb von Absätzen
über mehrere OCR-Zeilen umgebrochen und wurden deshalb nicht als Vorlage
angeboten. Der bestehende Originalsatz-Renderer erkennt diese Umbrüche nun,
ohne Sätze oder Beziehungen hinzuzuerfinden. Ein gesonderter, regulär
reservierter Kontrollaufruf mit demselben künstlichen Inhalt bestand die
Grafikprüfung; gemeldete Kosten: 0,032758 USD. Der ursprüngliche fehlgeschlagene
Testauftrag bleibt erhalten. Der Fotoeinstieg führt bei bereits fertigem
Tagespaket wieder zum Lernweg. Doppelte Rundenlinks stehen dort platzsparend
hinter „Weitere Runden“; die Beschriftung des Rückblicks berücksichtigt, ob
die Aufgaben bereits selbstständig gelöst wurden.

30.10.2026 · Ausgabelänge der Luna-Route: Ein künstlicher Paketauftrag
scheiterte mit `finish_reason=length`; alle 4.000 angeforderten Ausgabetokens
waren laut Anbieter-Telemetrie Reasoning-Tokens. Mit demselben Modell, derselben
Denkstufe und dem vorhandenen Azure-Endpunkt gelang ein separat reservierter
künstlicher Kontrollaufruf mit 8.000 Ausgabetokens. Danach wurde derselbe
künstliche Schultag über den Fotoassistenten erneut vorbereitet und das Paket
bereitgestellt. Die produktive Luna-Routenobergrenze wurde auf 8.000 erhöht;
Modell, Denkstufe, Upstream und Reservierungen wurden nicht verändert. Eine
Operator-Sicherung der vorherigen Routingkonfiguration liegt außerhalb des
Repos. Die reguläre produktive Prüfung mit festen künstlichen Bild-, Aufgaben-
und Paketaufrufen bestand, und die technische Sperre wurde aufgehoben. Die
Beobachtungen garantieren keinen Erfolg beliebiger zukünftiger Anfragen.

Der anschließende mobile Test einer Vergleichsetappe verwendete eine echte
künstliche KI-Ausgabe. Der kleinere Bruch wurde als falsch zurückgemeldet, der
richtige zweite Versuch als erneuter Versuch und die zweite selbstständige
Antwort separat erfasst. Der Fotoeinstieg führte bei einem bereits vorbereiteten
Tag ohne neuen KI-Auftrag zurück zum Lernweg. Der 30-Tage-Alltagstest ist zum
Zeitpunkt dieses Eintrags noch nicht abgeschlossen.

30.10.2026 · Weitere künstliche Tests: Eine Englisch-Kurzantwort `ed` wurde
zurückgewiesen, weil die Endung nur innerhalb eines Wortes in der Quelle stand.
Die sachlich richtige Ablehnung wurde wegen des Wortes „belegt“ irrtümlich als
beschäftigter Anbieter angezeigt; neu und für gespeicherte Altfehler wird diese
Kategorie richtig dargestellt. Für ausdrücklich durch einen Pfeil verbundene
Sprachbeispiele bindet der versionierte Grafikvertrag die Frage an einen
vollständigen Originalausdruck im Fragesatz und begrenzt kurze Antworten auf
wörtliche Wörter des dargestellten Beispiels. Eine zusätzliche Prüfung weist
beobachtete interne Modellanweisungen und unsichtbare Richtungssteuerzeichen
in generierten Texten zurück. Sie ist eine begrenzte Prüfung, kein Nachweis,
dass alle denkbaren unverständlichen oder falschen Ausgaben erkannt werden.

Eine weitere künstliche Biologieseite trennte die Aufnahme durch Blätter und
Wurzeln in eigene Sätze. Die bestehende, quellengebundene Pflanzengrafik
unterstützt nun auch diese ausdrücklich belegte Satzform. Im isolierten
390-Pixel-Browsertest wurde das zuvor zurückgewiesene Paket nach einem bewusst
angestoßenen neuen Versuch mit einem echten Anbieteraufruf erstellt. Beide
Grafikphasen und die beiden quellengebundenen Fragen waren bedienbar; nach
vorher geöffneter Erklärung wurden die Antworten als unterstützt ausgewiesen.
Der Test nutzt ein künstliches Konto und eine isolierte Testuhr, nicht Junas
Lernstand oder eine veränderte Uhr des Produktionsservers. Die sichtbare
In-App-Benachrichtigung für das vorherige Englischpaket führte zum passenden
Schultag; eine native Firebase-Zustellung ist damit nicht belegt.
Eine spätere separate Englischprobe wurde vom Anbieter mit einem internen
Anbieterfehler abgebrochen; ein anderer Kontrollaufruf wurde wegen eines in
fremden Fragetext eingefügten Grafikausschnitts verworfen. Der sichere
Englisch-Erzeugungsweg ist damit nicht für beliebige Antworten nachgewiesen.

30.10.2026 · Der isolierte Alltagstest einer selbst erzeugten Geografieseite
„Kontinente und Ozeane“ erreichte zunächst wegen fehlender geprüfter Grafik
keinen Anbieteraufruf. Eine neue versionierte Referenz stellt den ausdrücklich
belegten Fall „Der Atlantische Ozean liegt zwischen Amerika und Europa“ als
schematische räumliche Anordnung dar, ohne Himmelsrichtungen oder weitere
Beziehungen zu ergänzen. Die drei Elemente bleiben auch bei 320 Pixeln und
doppelter Schrift nebeneinander. Das wurde mit einem Widgettest und bei
390 Pixeln im Browser geprüft. Die Darstellung ist keine geografische Karte.

Ein erster echter Modellaufruf erstellte eine geografisch zum Blatt passende
Auswahlfrage, verknüpfte sie aber mit einer fachlich anderen Grafik. Die
anschließend verschärfte lokale Bindung verwirft den dokumentierten Fall und
lässt eine eindeutig auf die Lage bezogene Paarfrage zu. Ein weiterer echter
Test wurde wegen erneut unpassender beziehungsweise unverständlicher Fragen
abgewiesen; die erfolgreiche zuverlässige Paketgenerierung ist für diesen
Fall deshalb noch nicht belegt. Die Sicherheitsprüfung darf kein falsches
Lernpaket als Erfolg ausgeben. Der 30-Tage-Alltagstest bleibt offen.

30.10.2026 · Im simulierten Physiktag wurde eine künstliche Stromkreisseite
richtig abgeschrieben, aber die generierte Grafik zunächst wegen fehlender
wörtlicher Beschriftung abgewiesen. Eine neue versionierte Vorlage bindet die
bereits vorhandene Stromkreiszeichnung für offene und geschlossene Schalter an
vollständig und ausdrücklich belegte Quellsätze. Ein bewusst gestarteter
erneuter Testauftrag erzeugte mit echtem Anbieteraufruf die Runde; das
Schaltbild und zwei inhaltlich passende Fragen wurden im 390-Pixel-Browser
geprüft. Die Vorlage unterstützt ausschließlich diese präzise belegte
Quellform, nicht beliebige Schaltungen. Eine sinngemäß richtige freie Antwort
„Er unterbricht den Stromkreis“ blieb bei der hinterlegten Kurzlösung
„unterbricht“ unklar. Sie wurde nicht als falsch bewertet, bedarf aber einer
besser verständlichen und verlässlichen Klärung. Der 30-Tage-Test bleibt offen.

30.10.2026 · Die geschilderte Physikantwort wird für die konkrete Frage und
die versionierte, quellengebundene Darstellung des geöffneten Stromkreises
nun anhand weniger vollständig übereinstimmender Satzformen geprüft. Andere
Formulierungen, Verneinungen und Zusätze bleiben ungeklärt. Im isolierten
Mobilbrowser wurde die zuvor gespeicherte Antwort ausdrücklich erneut geprüft
und als richtig mit Hilfe ausgewiesen; bisherige Hilfen und Versuche blieben
erhalten. Dies ist keine allgemeine semantische Freitextbewertung.

Beim folgenden künstlichen Deutsch-Foto scheiterte der Leseauftrag zweimal mit
einem Verbindungsfehler. Die gespeicherten Versuche bleiben erhalten. Die
Kindermeldung unterscheidet nun diese Verbindungslage von einer fehlerhaften
Aufgabe; die Ursache des Verbindungsabbruchs und eine zuverlässige Verarbeitung
dieses Fotos sind damit noch nicht nachgewiesen. Keine automatischen erneuten
Anbieteraufrufe wurden ergänzt. Der 30-Tage-Alltagstest bleibt unvollständig.

30.10.2026 · In einem weiteren isolierten 390-Pixel-Alltagstest wurde eine
künstliche Geschichteseite zum Nil erkannt. Ein zunächst falsch zugeordnetes
Fach ließ sich vor Bestätigung ändern. Die beschriftete Fachauswahl hat nun
eine direkt ausführbare Bedienhilfe-Aktion für Screenreader; bestehende
Tastatur- und Touchbedienung bleiben erhalten.

Die erste Anschlussübung scheiterte an einer Kombination aus falschem
Grafiktyp und Referenz. Ein erneuter Versuch verwendete den passenden Typ,
veränderte jedoch die geforderte Originaldarstellung. Für geeignete deutsche
und historische Quellen können ausdrücklich angeforderte Anschlussübungen nun
die bereits geprüfte Originalgrafik auswählen. Ihre zwei festen Aufgaben- und
Lernzielpaare bleiben gebunden, und die jeweilige Grafik muss den Beleg des
Lernziels enthalten. Andere Pfade und alle Quell- und Antwortprüfungen bleiben
bestehen. Eine zusätzliche einzelne Fragegrafik wird für diesen vorbereiteten
Vertrag ausgeschlossen; sie hatte zwei inkompatible Grafiktransporte aktiviert.

Eine zweite künstliche Seite enthielt drei von der Erkennung zu einer Zeile
verbundene Sätze. Der Compiler erkennt solche vollständigen, einfachen Sätze
nun auch in einer Zeile; mehrdeutige Punkte wie bei Abkürzungen, Zahlen und
Klassenangaben werden nicht erraten. Das echte Lernpaket wurde erstellt; nach
einem abgelehnten Anschlussauftrag gelang der ausdrücklich gestartete erneute
Versuch und beide Aufgaben ließen sich im Smartphone-Browser beantworten.
Die neue Erklärung nannte den Inhalt der Seite. Die Anschlussfragen waren
allerdings vor allem Umformulierungen der vorherigen Fragen. Damit ist eine
anspruchsvolle adaptive Förderung nicht nachgewiesen. Der Fehler bei der
Dezimalzahlen-Grafik und die generelle Vermeidung von Ausgabelängen-Abbrüchen
sind weiterhin offen; der 30-Tage-Alltagstest ist nicht abgeschlossen.

30.10.2026 · Ein künstliches Englischfoto enthielt einen absichtlich verdeckten
Wortteil. Das Modell kennzeichnete ihn als unlesbar, interpretierte den Fleck
aber fälschlich als Streichung. Der umgebende Wortlaut blieb im Bearbeitungsfeld
erhalten; die Markierungsansicht verbarg ihn zunächst hinter einer Aufklappung.
Bei Texten mit explizit unleserlicher Stelle zeigt diese Ansicht nun den
vollständigen umgebenden Wortlaut direkt und behält die Markierungskennzeichnung.
Andere markierte Texte behalten ihre bisherige Darstellung, damit etwa
durchgestrichene falsche Rechnungen nicht unkommentiert als gültig erscheinen.
Der Leseauftrag unterscheidet nun ausdrücklich Flecken von Streichlinien.

Ein weiterer echter KI-Leseauftrag mit einem anderen künstlichen Tintenfleck
erhielt die lesbaren Sätze und „She [unleserlich] a cake.“ und benannte den
Fleck als unleserlich. Diese Einzelbeobachtung ist kein allgemeiner Nachweis
für die Erkennungsqualität oder für jede Markierung. Das Foto wurde im
isolierten 390-Pixel-Browser geprüft; es wurden keine echten Kinderangaben oder
die Uhr des Produktionsservers verwendet. Der 30-Tage-Test bleibt offen.

30.10.2026 · Isolierter Alltagstest, simulierter 20.11.: Das künstliche
Biologiefoto zum Herzen wurde vollständig gelesen und bestätigt. Der erste
Paketversuch endete vor Anbieterversand, da für den belegten Zusammenhang
keine passende Grafikreferenz angeboten wurde. Die neue versionierte Referenz
`biology.heart.pump` bindet ein bewusst vereinfachtes eigenes Herzschema an
den vollständigen ausdrücklich bestätigten Satz „Das Herz pumpt Blut durch
den Körper.“ Zwei manuell wählbare Ansichten zeigen Herz beziehungsweise
Körper; das Schema behauptet weder Anatomiedetails noch einen vollständigen
Kreislauf. Verneinte oder anderslautende Quellen qualifizieren nicht.

Nach einem ausdrücklichen erneuten Versuch erzeugte ein echter Anbieteraufruf
in 31 Sekunden eine Runde mit zwei Aufgaben. Im mobilen Browser wurde die
Grafik bedient und die Runde abgeschlossen. Die korrekte freie Antwort
„durch den Körper“ blieb zunächst unklar, weil die Musterantwort „Körper“
lautete. Eine eng an diesen belegten Fragetyp und die unveränderte Referenz
gebundene Regel erkennt diese genaue Formulierung; die ausdrücklich ausgelöste
Nachprüfung änderte das Ergebnis unter Erhalt des Unterstützungsnachweises.
Auch eine bewusst angeforderte Anschlussrunde wurde mit einem echten
Anbieteraufruf erstellt und abgeschlossen. Ihre Aufgaben wiederholten jedoch
denselben kurzen Heftsatz; ein belastbarer Transfer auf neue Beispiele ist
damit nicht belegt. Die längste getestete Quellenaufnahme überschritt schon
vor diesen Änderungen die konservative Auftragsreservierung. Höchstens vier
statt sechs vorbereitete Grafikbasen halten diesen Test unter der bestehenden
Grenze; Quelltext, Aufgaben und Preisgrenze werden nicht gekürzt oder geändert.
Ein zuvor unvollständiger Strukturtest wurde an die vier festen Pflanzenlabels
angepasst. Der 30-Tage-Test, der Dezimalzahlenfall und die allgemeine Qualität
adaptiver Aufgaben bleiben offen. Eine Android-Zustellung wurde nicht geprüft.

30.10.2026 · Isolierter Alltagstest, simulierter 23.11.: Eine künstliche
Dezimalzahlen-Heftseite enthielt 0,5 = 5/10, 0,25 = 25/100 und eine
Zehnerleiste. Die echte Fotoerkennung übernahm den Text, ließ die unbeschriftete
Zeichnung jedoch aus. Ihre Beschreibung wurde vor Quellenbestätigung im
Testkonto manuell ergänzt. Der erste Paketaufruf wurde nach Modellantwort
wegen `scene_label_evidence` verworfen. Ursache: Die Referenzsuche bot die
vorhandene Bruchvorlage bei einer ausdrücklichen Formel ohne das Wort „Bruch“
nicht an. Im vorbereiteten Paketpfad darf sie nun die bereits vorhandene
Vorlage anbieten, wenn der bestehende strenge Compiler einen tatsächlich
darstellbaren Originalbruch findet. Quellen, Bruchparameter und die
nachgelagerten Prüfungen bleiben unverändert; 25/100 liegt weiterhin außerhalb
des unterstützten Bruchmodells.

Ein ausdrücklicher weiterer künstlicher Anbieteraufruf erzeugte nach 30
Sekunden eine Runde (gemeldeter Anbieterpreis 0,0024162 USD), die im mobilen
Browser bearbeitet wurde. Das Modell zeigte 5/10 korrekt, die Einführung
erklärte aber den Vergleich zu 0,25 nicht; eine Auswahloption in der zweiten
Frage war sprachlich unpassend. Dieser Einzelfall behebt weder die allgemeine
didaktische Auswahl noch Hundertstelgrafiken oder die Erkennung unbeschrifteter
Zeichnungen. Der 30-Tage-Test ist weiterhin nicht abgeschlossen.

30.10.2026 · Isolierter Alltagstest, simulierter 24.11.: Eine künstliche
Deutschseite mit farbig unterstrichenen Satzgliedern führte beim ersten echten
Erkennungsauftrag zu einem Schemafehler in strukturierten Daten; die genauen
Modellwerte dieses ersten Fehlers sind nicht erhalten. Ein bewusst ausgelöster
zweiter Auftrag las den Text richtig. Ungültige optionale Markierungsmetadaten
werden nun getrennt abgefangen: Der Wortlaut bleibt erhalten, der betroffene
Abschnitt wird als unsicher gekennzeichnet und vor der Überprüfung nicht als
verlässlicher Lernstoff behandelt. Andere Schemafehler bleiben Fehler. Die
Regression deckt unter anderem ungültige Farben, Markierungstypen und
Bildbereiche ab; sie beweist nicht, dass eine bestimmte Variante den ersten
Abbruch ausgelöst hat.

Reine Hervorhebungen verdecken den vollständigen Text auf schmalen Displays
nicht mehr; die Details bleiben auf Wunsch erreichbar. Streichungen und
Korrekturen werden weiterhin gesondert kenntlich gemacht. In der erzeugten
Deutschübung bestand der sichtbare Grafikschritt nur aus „1“, obwohl eine
ausführlichere Erklärung gespeichert war. Für genau einen nichtsprachlichen
Schritt zeigt die lesende Projektion jetzt den separat gespeicherten Text,
ohne den ursprünglichen Schritt zu ändern. Ungeöffnete Fragehinweise erhalten
keinen Lösungstext; gezeigte Einführungen bleiben bei der Bewertung als
mögliche Hilfe berücksichtigt. Eine lokale, ausdrücklich als Testkopie
gekennzeichnete Runde zeigte diese Korrektur im 390-Pixel-Browser. Die zwei
Aufgaben der ursprünglichen künstlichen Runde wurden korrekt mit Unterstützung
bewertet. Die Grafik zerlegt den Satz aber lediglich in einzelne Wörter und
erklärt Satzglieder damit noch nicht ausreichend. Die didaktische Qualität,
das Erkennen unbeschrifteter Zeichnungen und der 30-Tage-Alltagstest bleiben
offen. Ein physischer Android-Test wurde nicht durchgeführt.

30.10.2026 · Isolierter Alltagstest, simulierter 25.11.: Eine eigene englische
Simple-past-Heftseite wurde über den mobilen Fotoassistenten abgegeben. Die
Abschrift übernahm alle lesbaren Sätze. Zwei reguläre Paketversuche scheiterten
mit einem OpenRouter-Fehler 502; ein gesonderter künstlicher Diagnoseaufruf
ergab die Anbieterangabe, das Modell habe ungültigen Inhalt erzeugt. Die
genaue interne Ursache nennt der Anbieter nicht. Für denselben künstlichen
Stoff wurden zwei Diagnoseaufträge mit einer und zwei mit zwei angebotenen
Grafikbasen erfolgreich validiert. Bei vier Basen scheiterte auch der dritte
Diagnoseaufruf. Das belegt den beobachteten Fall, keine allgemeine Zusage zur
Anbieterverfügbarkeit.

Englische Paketaufträge bieten nun höchstens zwei vollständige, weiterhin an
Quellen und Offenlegungsstufen gebundene Grafikbasen an. Der vollständige
Quelltext und alle fachlichen Prüfungen bleiben erhalten. Der regulär
reservierte einmalige lokale Reparaturauftrag im künstlichen Testkonto
erstellte daraufhin den Lernweg; die zwei alten Fehler und ihre Kostenbelege
blieben erhalten. Die erste Aufgabe wurde erst falsch, dann nach einem Hinweis
richtig gelöst. Die zweite verlangte korrekt „visited“, verwies aber auf eine
Grafik, die im Aufgabenraum noch nicht sichtbar war. Diese irreführende
Formulierung bleibt ein offener Qualitätsmangel. Eine vom Modell exakt als
„Die belegte Pfeilfolge: [Originalbeleg]“ ausgegebene bloße Bildunterschrift
kann nun bei einem einzelnen Grafikschritt durch die separat gespeicherte
Erklärung in der Leseprojektion ergänzt werden; Quelle, gespeicherter Schritt
und Hilfebewertung bleiben erhalten.

Während des Tests startete der isolierte lokale Server neu; seine Testuhr
sprang unbeabsichtigt zurück. Der letzte Antwortbeleg wurde dadurch zeitlich
vor den vorherigen Versuch sortiert und seine Rückmeldung nicht regulär
angezeigt. Das ist kein Nachweis für einen Produktionsfehler; der synthetische
Testablauf ist an dieser Stelle eingeschränkt. Die lokale Testuhr wurde für
weitere Tests so angepasst, dass sie nach Neustarts vorwärts läuft. Keine
gespeicherte Antwort wurde nachträglich umgeschrieben.

Die anschließend ausdrücklich angeforderte Anschlussrunde fragte nach der
Bedeutung von „did not“ und nach dem Vergangenheitswort „played“. Beide
Antworten wurden im künstlichen Konto ohne neue Hilfe richtig bewertet. Bei
dieser Runde blieb auch die letzte Rückmeldung sichtbar, bis im Browser das
Ergebnis ausdrücklich geöffnet wurde. Die Beispiele verwenden allerdings
weiterhin Sätze der fotografierten Seite; ein Transfer auf unbekannte Verben
ist dadurch nicht belegt.

30.10.2026 · Isolierter Alltagstest, simulierter 26.11.: Eine selbst erzeugte
Physikseite behandelt Licht und Schatten. Das Landesinstitut ordnet „Schatten
und Bilder untersuchen“ dem sechsten Schuljahrgang der Sekundarschule zu:
[Fachliche Orientierungen Physik](https://www.bildung-lsa.de/files/0cf06e8b1aa571c799b255202ea18103/Fachliche_Orientierung_Physik.pdf).
Die Fotoerkennung erfasste Text und Bildbeschriftungen, jedoch keine räumliche
Beschreibung der Zeichnung. Die erste Paketvorbereitung scheiterte vor dem
Anbieteraufruf, weil für den belegten Sachverhalt keine Grafik angeboten wurde.

Die neue versionierte Referenz `physics.shadow.size` zeigt ein vereinfachtes
Lichtmodell mit fester Lampe und Wand und zwei bewusst wählbaren Positionen des
undurchsichtigen Gegenstands. Die geometrische Projektion vergrößert den
Schatten bei kleinerem Lampenabstand; sie nennt keine erfundenen Messwerte.
Die Referenz wird nur bei der exakt nachweisbaren Folge der drei Quellsätze
angeboten; widersprüchliche oder unvollständige Aussagen werden abgewiesen.
Die Darstellung ist per Touch und Screenreader zugänglich und bleibt ein
vereinfachtes Modell, keine vollständige optische Simulation. Sie ist auch für
ausdrücklich angeforderte quellengebundene Folgeübungen vorgesehen.

Ein realer künstlicher Folgeaufruf lieferte unsichtbare Steuerzeichen und wurde
von der bestehenden Prüfung verworfen. Die Schutzprüfung blieb unverändert;
der Fragevertrag akzeptiert nun mehrere im Zusammenhang tatsächlich belegte
Begriffe im eigentlichen Fragesatz. Ein weiterer künstlicher Diagnoseaufruf
und der einmalig auditierte, normal reservierte Reparaturauftrag wurden danach
gültig abgeschlossen. Im 390-Pixel-Browser änderte sich die Schattengröße bei
der Bedienung sichtbar. Zwei Aufgaben und ihre unterstützten Rückmeldungen
wurden durchlaufen. Beide fragen vorwiegend Grundbegriffe ab und belegen noch
nicht, dass das Kind den Größenvergleich selbstständig beherrscht. Die
In-App-Fertigmeldung wurde gespeichert; eine Android-Pushzustellung wurde
nicht getestet. Der 30-Tage-Test bleibt offen.

Die zusätzlich ausdrücklich angeforderte Anschlussrunde wurde ebenfalls
erzeugt und im Smartphone-Browser abgeschlossen. Ihre Fragen überprüften
erneut, dass ein beleuchteter undurchsichtiger Gegenstand einen Schatten wirft
und Lampe und Wand fest stehen. Auch sie fragte nicht nach der Veränderung
der Schattengröße. Die sichtbare Interaktion hilft beim Erkunden, aber eine
gezielte selbstständige Prüfung dieses Zusammenhangs bleibt damit offen.

30.10.2026 · Isolierter Alltagstest, simulierter 27.11.: Eine selbst erzeugte
Geschichtsseite über das alte Ägypten, den Nil und die Arbeit von Schreibern
und Handwerkern wurde im mobilen Fotoassistenten vollständig erkannt. Das
Thema „Das Alte Ägypten“ ist im
[Fachlehrplan Geschichte der Sekundarschule](https://www.bildung-lsa.de/files/164f3f97e3adf65ff6f44685dd9e1ced/lp_sks_gesch_01_08_2019.pdf)
für die Schuljahrgänge 5/6 aufgeführt. Ein echtes Paket wurde erstellt und
die beiden passenden Auswahlaufgaben wurden nach der Erklärung richtig
beantwortet. Die sichtbare Einführung blieb allerdings allgemein und erklärte
vorwiegend, dass die Sätze unterschiedliche Informationen enthalten. Nach
einem Neustart des isolierten Servers blieb die Auswahl erhalten und die
letzte Rückmeldung wurde nach erneuter Übermittlung korrekt angezeigt.

Der bestehende KI-Auftrag für den Originalsatz-Lesefokus fordert nun
ausdrücklich eine konkrete Quellaussage und ihre verständliche Bedeutung.
Ein künstlicher Diagnoseaufruf lieferte eine konkretere separat gespeicherte
Gesamterklärung, verwendete als sichtbaren Schritt aber nur die feste
Bildunterschrift „Vergleiche die vollständig belegten Originaleinträge.“.
Für genau diese unveränderte Standardunterschrift und die zugehörigen
Lesefokus-Referenzen zeigt die Leseprojektion den gespeicherten Erklärungstext;
der ursprüngliche Modellschritt bleibt erhalten. Hinweise bleiben geschützt,
und die Einführung wird weiterhin auf eine mögliche Antwortvorlage geprüft.
Der einzelne Test belegt keine generell kindgerechte Erklärung aller Themen;
die bereits vorhandene allgemeine Ägypten-Einführung wurde nicht umgeschrieben.
Die Anzeige des Diagnoseergebnisses wurde zusätzlich in einer ausdrücklich
gekennzeichneten lokalen Testkopie im 390-Pixel-Browser kontrolliert; daraus
wurden keine Antworten eingetragen und kein neuer KI-Erfolg behauptet.

30.10.2026 · Isolierter Alltagstest, simulierte Schultage 30.11. und 01.12.:
Zwei selbst erzeugte Mathematikseiten zeigten Regeln und Beispiele zur Addition
gleichnamiger Brüche. Bei beiden stimmten die erkannten Gleichungen mit den
Fotos überein; von der jeweiligen Zeichnung wurde die Beschriftung erkannt,
nicht jedoch ihre vollständige räumliche Beschreibung.

Im ersten Paket belegten zwei fest geplante Vorwissensfragen sämtliche Plätze
der ersten Runde. Die Einführung zeigte die Bedeutung eines Bruchs, erklärte
aber die Addition nicht. Der anschließende KI-Rückblick scheiterte, weil die
Vorwissensfragen keinem passenden fachlichen Lernziel zugeordnet waren. Die
Antworten blieben gespeichert. Bei neuen Planungen erhält eine kurze Runde nun
mindestens einen Platz für die Anwendung des Themas; bereits reservierte
Aufträge behalten ihre ursprüngliche Planung. Ein Rückblick ordnet eine anhand
der eigenen Quellenrevision und Aufgabenidentität überprüfte Vorwissensfrage
nicht automatisch einem anderen Rechenziel zu. Sie bleibt eine beobachtete
Antwort, ist aber kein Nachweis für dieses Rechenziel. Gespeicherte Berichte
mit solchen bewusst offenen Zuordnungen lassen sich auch für getrennt und
ausdrücklich angeforderte Anschlussübungen wieder einlesen; das Anbieterformat
für neu erzeugte Zuordnungen bleibt unverändert streng.

Im künstlichen Konto gelang ein ausdrücklicher erneuter KI-Rückblick. Eine
anschließend angeforderte Übung scheiterte zunächst beim Einlesen des Berichts;
nach Korrektur und einem ausdrücklich ausgelösten weiteren Versuch entstand
eine Runde mit einer Zählerfrage und einer Additionsaufgabe. Beide wurden im
390-Pixel-Browser richtig beantwortet. Die Addition wiederholte allerdings ein
Beispiel der Quellseite; ein Transfer auf unbekannte Zahlen ist dadurch für
diese Anschlussrunde nicht belegt.

Am folgenden simulierten Schultag wurde nach einem echten neuen KI-Aufruf eine
Runde mit einer Vorwissensfrage und anschließend einer Additionsaufgabe erzeugt.
Die textliche Erklärung nannte die Regel und ein belegtes Beispiel; die
Additionsaufgabe verwendete neue Zahlen und wurde nach der Erklärung richtig als
unterstützt bewertet. Der KI-Rückblick ordnete die Vorwissensfrage keinem
Additionsziel und die Rechenaufgabe dem Additionsziel zu. Die passende Grafik
war in diesem Durchlauf noch nicht verfügbar und muss gesondert verbessert
werden. Ein ausdrücklich ausgelöster zusätzlicher Auftrag zur grafischen
Erklärung scheiterte an der visuellen Zahlenbelegprüfung (`number_evidence`);
die konkrete Stelle der Modellausgabe ist damit noch nicht geklärt. Aufgaben, Antworten und Rückblick
blieben erhalten. Das sind künstliche lokale Tests; keine Android-Zustellung
wurde geprüft.

30.10.2026 · Isolierter Alltagstest, simulierter 02.12.: Eine neue künstliche
Biologieseite zu Wasseraufnahme, Kohlenstoffdioxid und Zuckerbildung wurde im
Fotoassistenten mit sämtlichen Sätzen und den drei Bildbeschriftungen erkannt.
Der erste Paketauftrag scheiterte vor dem KI-Aufruf, weil die bereits geprüfte
Pflanzengrafik nur zwei andere, sehr enge Formulierungen akzeptierte. Das
versionierte Auswahlverfahren unterstützt nun zusätzlich die vollständig
belegte vierteilige Formulierung; Negationen, fehlende Aussagen und vertauschte
Stoffe werden weiterhin abgewiesen. Eine ausdrückliche Wiederholung erzeugte
mit echtem Modellaufruf ein Paket mit zwei Fragen und der vorhandenen Grafik.

Die Seite sagt, dass Sauerstoff entsteht, nicht dass er abgegeben wird. Für
diesen geprüften Quellenfall zeigt die Grafik daher „Bildung“ und verwendet
keinen Abgabepfeil. Der Server überträgt dafür nur ein abgeleitetes Merkmal;
der private Quellenwortlaut bleibt aus der Grafikprojektion entfernt. Beide
Grafikzustände wurden im 390-Pixel-Browser geprüft. Eine absichtlich falsche
Antwort wurde nach einem lokalen Verbindungsabbruch wiederhergestellt, beim
zweiten Versuch richtig beantwortet und als unterstützt gezählt; die zweite
Aufgabe zur Sauerstoffentstehung wurde nach geöffneter Erklärung ebenfalls als
unterstützt bewertet. Beide Fragen sind auf der künstlichen Seite belegt. Ein
selbstständiger Transfer auf unbekannte Beispiele ist damit nicht nachgewiesen.
Die ausdrücklich angeforderte Anschlussrunde griff die zuvor verwechselte
Wasseraufnahme sowie die Sauerstoffentstehung erneut auf; beide Antworten wurden
ohne zusätzliche Hilfe richtig bewertet. Die Fragen bleiben eng an den Sätzen
der Quelle und belegen deshalb noch keinen breiten fachlichen Transfer.

30.10.2026 · Isolierter Alltagstest, simulierter 03.12.: Eine künstliche
Geografieseite über Sachsen-Anhalt wurde einschließlich der Kartenbeschriftungen
erkannt. Die Skizze wurde nicht als maßstabsgerechte Karte interpretiert. Die
Erkennung gab das Fach als „Geografie“ aus, während die Grafikprofile bisher
„Geographie“ erwarteten. Der Anbieter lehnte das daraufhin übermittelte Schema
zweimal als `invalid_json_schema` ab. Seine Fehlermeldung nannte keinen genaueren
Teil des Schemas. Ein künstlicher Offline-Nachbau ergab für die konkrete Anfrage
38.487 Bytes; nach der Profil- und Referenzkorrektur waren es 19.536 Bytes.
Microsoft dokumentiert für Azure Structured Outputs unter anderem Grenzen für
Objektfelder und Verschachtelungstiefe: [Azure Structured Outputs](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/structured-outputs).
Ein einzelner auditierter und regulär reservierter Reparaturauftrag wurde vom
Anbieter angenommen und erfolgreich geprüft. Daraus allein lässt sich nicht
beweisen, welche einzelne Azure-Schemaregel vorher die Ablehnung ausgelöst hat.

Öffentlich definierte Fachaliasse aus dem versionierten Fachkatalog erhalten
nun dasselbe Darstellungsprofil; gespeicherte Fachnamen bleiben unverändert.
Für Geografie gibt es eine eigene versionierte Originalsatz-Referenz. Sie zeigt
zwei vollständige Quellaussagen zum bewussten Lesen, ohne eine Karte, räumliche
Relationen oder zusätzliche Fakten zu erfinden. Der 390-Pixel-Browser zeigte
beide wählbaren Lesefokusse. Zwei passende Auswahlfragen wurden nach Öffnen der
Erklärung richtig und als unterstützt bewertet. Die Lesekarten sind keine
geografische Karte und belegen keinen Transfer auf neue Orte.

30.10.2026 · Isolierter Alltagstest, simulierte Schultage 04., 07. und
08.12.: Bei einer künstlichen Deutschseite enthielt eine erzeugte Frage
unnötige Wiederholungen und eine abgebrochene Formulierung. Neue Fragen für
die versionierte Satzdarstellung sind nun längenbegrenzt und müssen den
Originalsatz, geschlossene Anführungszeichen und die regulären Quellenprüfungen
enthalten. Bestehende Aufgaben und Antworten werden nicht umgeschrieben. Ein
echter Modellaufruf zur nächsten künstlichen Seite erzeugte zwei kurze,
passende Fragen; eine selbstständige und eine nach Erklärung unterstützte
richtige Antwort wurden im 390-Pixel-Browser entsprechend unterschieden.

Die Erklärung zeigte dort aber „Wer oder was?“ als zerlegte Satzgrafik. Diese
Textzeile war durch den Zeilenumbruch der Erkennung als Beispielsatz angeboten
worden. Fragefragmente werden nun ausgeschlossen und vorhandene belegte
Beispielsätze gegenüber Definitionen bevorzugt. Bei einer weiteren künstlichen
Seite wurde „Der Vogel baut ein Nest.“ vollständig erkannt. Der erste echte
Paketauftrag scheiterte nach Modellantwort an einer Strukturprüfung; die
gespeicherte Diagnose benennt die genaue verletzte Regel nicht. Eine einmalige
ausdrückliche Wiederholung gelang. Die mobile Erklärung zeigte anschließend
den tatsächlichen Satz in Wortkästen, und zwei richtige freie Antworten wurden
nach geöffneter Erklärung als unterstützt erfasst. Der erfolgreiche
Wiederholungsversuch beweist keine allgemeine Behebung des ersten Fehlers.

30.10.2026 · Dezimalzahlen im isolierten Alltagstest: Ein echter Luna-Auftrag
für eine künstliche Heftseite endete bei 8.000 Ausgabetokens mit `length`;
7.094 Tokens waren laut Anbieter Reasoning-Tokens. Ein neuer ausdrücklich
gestarteter Auftrag für genau dieselbe weiterhin gültige Paket-Teilrunde kann
nun anhand dieses belegten Fehlers vor der regulären Reservierung die vorhandene
stärkere Route wählen. Dazu müssen Kind, Quelleninhalt und -revision,
Paketplan, Teilnummer, Elternplanung und abgerechneter Luna-Längenfehler
übereinstimmen. Es gibt keinen automatischen Neuversuch, keinen Wechsel eines
bereits reservierten Auftrags und keine Änderung bestehender Kontingente.
Im künstlichen Test wurde die stärkere Route tatsächlich gewählt und lieferte
eine vollständige Antwort; diese fiel anschließend an einer anderen
Grafik-/Frageprüfung durch. Das ist kein Beweis, dass Längenabbrüche generell
ausgeschlossen sind.

Bei der Untersuchung zeigte ein experimenteller Dezimalzahlen-Renderer ein
belegtes Beispiel mit lesbaren Kommas; eine echte Anbieterantwort enthielt
jedoch interne Modellnotizen in einer Frage. Ein späterer künstlicher Test mit
fest gebundenen Fragen und Antworten gelang technisch im 390-Pixel-Browser,
verwendete aber bereits vorgerechnete Beispiele aus der Heftseite. Deshalb
wurde diese experimentelle Darstellung nicht freigegeben: Neue selbstständige
Aufgaben bleiben offen. Die
Sicherheitsprüfung für unbelegte Grafiken wird nicht gelockert. Bei einem der
Tests musste die falsch gelesene Überschrift vor der Bestätigung korrigiert
werden. Die ursprünglichen Fehlversuche und Gebühren bleiben erhalten.

Die im künstlichen Test tatsächlich beobachtete englische Selbstkorrektur des
Modells wird für neue Paketaufgaben nun gezielt abgewiesen. Ein normaler
englischer Beispielsatz mit „Oops“ bleibt erlaubt. Diese konkrete Prüfung ist
keine Garantie gegen alle anderen Arten unverständlicher Modelltexte.

30.10.2026 · Version1.38.46: Neue Dezimalaufgaben werden vor dem Anbieteraufruf
an eine ausdrückliche bestätigte Kommaregel und ein korrektes Originalbeispiel
gebunden. Das Original dient als Einführung, eigene neue Zahlenpaare als Übungen.
Paket, Vorwissens-IDs, Etappenumfang und Anschluss-Lernziele bleiben verbunden;
ganze Summanden werden auch im Veröffentlichungsschutz erkannt. Die gemeinsame
Flutter-Stellenwertgrafik bietet eigene Spaltenschritte, Zurücksetzen und
Tutorzustand. Gezielte Stellenwerthinweise ändern keine gespeicherten Lösungen.
Grenzen, Prüfweg und tatsächliche lokale Screenshots: [DECIMAL_ADDITION.md](DECIMAL_ADDITION.md).

Der echte isolierte Uploadtest und die nachfolgende zielgebundene Übungsrunde
wurden abgeschlossen. Die absichtlich falschen Antworten, Hilfen und späteren
selbstständigen Erstlösungen blieben getrennt. Der Paketaufruf benötigte laut
Anbieterbeleg14.977ms, die Anschlussvorbereitung15.570ms; verbuchte Kosten
0,001697USD beziehungsweise0,031870USD. Diese Einzelmessungen sind keine
allgemeine Latenzzusage. Sichtbare In-App-Fertigmeldung und kontogebundene
Lesemarkierungen wurden im390px-Browser geprüft; keine native Firebase-Zustellung
behauptet.

Zusätzlich belegte ein unveränderter Vergleich mit Commit0b67d6d, dass der
Acht-Bruch-Vertrag bereits vor dieser Änderung an der250.000-Mikro-Reservierung
scheiterte. Identische Schemateile werden nun über gemeinsame lokale Referenzen
übertragen. Die unabhängige JSON-Schema-Prüfung erhält Pflichtfelder, Reihenfolge,
Bereiche und Ablehnungen. Im selben Test sank die konservative Projektion von
268.636 auf246.318MikroUSD. Anbieterroute, Modell, Ausgabelimit und Kostenfreigaben
wurden dafür nicht erhöht. Die vollständige Monatsabnahme und frühere offene
Testtage bleiben offen; fehlgeschlagene Läufe wurden nicht überschrieben.

30.10.2026 · Version1.38.47: Die Monatsprüfung belegte fehlende Auftragsdatensätze
nach regulärer30-Tage-Wartung trotz offener Schultage. Aktuelle eigene
Vorbereitungs-/Teilplanbelege bleiben nun innerhalb der365-Tage-Grenze verfügbar;
normale30/90-Tage-Fristen anderer Vorgänge und Fehlversuchszähler bleiben erhalten.
Ein bereits fehlender laufender Beleg führt zu einer Unterbrechung ohne erneuten
Anbieteraufruf. Die reine Statusanzeige schreibt weiterhin nichts.

Der künstliche Deutsch-Schultag12.11. wurde im390px-Browser über normale
Fotoerkennung, Bestätigung und bewusste Paketvorbereitung wieder nutzbar:
11.403ms/0,000853USD OCR und24.558ms/0,002462USD Paket laut tatsächlichen
Generierungsbelegen. Der Aufgabenrückblick erhält einen direkten Zugang zu
seiner gespeicherten Grafik; Satzwörter werden kompakt in Leserichtung dargestellt.
Originalbelege und Grenzen: [EVERYDAY_QA_2026_10_30.md](EVERYDAY_QA_2026_10_30.md).

30.10.2026 · Version1.38.48: Der reale künstliche Deutsch-Folgeauftrag zeigte
einen vollständigen belegten Subjektausdruck in zwei getrennt markierten
Wortkästen. Die Rollenprüfung betrachtet nun die vollständige zusammenhängende
Wortgruppe; Teilwortpräfixe, widersprüchliche Rollen und verneinte Angaben werden
nicht als Nachweis akzeptiert. Originalantworten und Modelloutput bleiben
unverändert.171 betroffene Backendfälle und53 Flutterfälle bestanden. Nach einer
rein lesenden Prüfung des tatsächlichen Fehloutputs gelang der reguläre bewusste
Neuversuch: zwei zielgebundene Aufgaben g1/g2 mit belegten Rollen,27.217ms
Anbieterzeit, gemeldete Kosten0,044196USD. Keine Änderung von Modell, Route,
Reservierung oder Wiederholungskontingent. Die Gesamt-CI des Zwischenstands202
war wegen Importformatierung und veralteter UI-Erwartungen nicht grün; deren
gezielte Korrektur wird vollständig erneut geprüft.

### Alltagstest-Fortsetzung 30.10.2026: Tagesfolge und Offenlegung

Eigene künstliche 390px-Browserbeobachtung am isolierten Geschichte-Testtag:
Die vorhandene Runde war bereit, wurde aber hinter einer geplanten Erzeugung
angeboten. Enge Tagespriorisierung, kompakte Lesefokuskarten sowie neue endliche
Rechen-Offenlegungsbelege sind in `docs/EVERYDAY_QA_2026_10_30.md` dokumentiert.
Gezielte lokale Serien: 416, 33 und 88 bestandene Backendtests. Keine Änderung
an Produktionsbudgets, Modellrouten oder gespeicherten Kinderantworten.

### 1.38.49+204 · Endlicher Dezimal-Zahlenstrahl

Eigene künstliche Originalseite des simulierten13.11., tatsächliche isolierte
OpenRouter-Ausgabe und390px-Browserprüfung. Neue Quelle/Referenz
`math.decimal.number_line_midpoint@1`; vollständige Originalaussage und
Decimal-Mittelwertprüfung vor der Geometrie. Kein fremdes Bild oder Modellcode.
Echter Reparaturauftrag:22.175ms,0,002125USD zunächst gemeldet,2Aufgaben,stop.
221 gezielte Backend- und28 Flutterfälle erfolgreich; Details/Grenzen in
`docs/EVERYDAY_QA_2026_10_30.md`. Releasekandidat, kein vorweggenommener
Deployment- oder vollständiger Monats-Abnahmebeleg.
