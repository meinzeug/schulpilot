# Aufgaben- und Hilfedarstellung · Abnahme 20.10.2026

Die Nutzerkorrektur ist maßgeblich: Eingelesen werden gewöhnliche handschriftliche
Schulhefter. Verbessert wurde die Darstellung in Aufgaben, Antwortmöglichkeiten,
geöffneten Hinweisen, Erklärungen, Rückmeldungen und der Heft-Hilfe. Die anfangs
erzeugten gedruckten Testvorlagen wurden nach der Korrektur nicht weiterverwendet
und nicht hochgeladen; sie sind keine App-Assets.

## Ergebnis

- Gemeinsamer lokaler Formelsatz für Brüche, Potenzen, Indizes/Ladungen, Wurzeln,
  Summen, Integrale, Vektoren/Matrizen und weitere Standard-TeX-Notation.
  Native Flutter-Widgets, keine Bild-KI, Webviews oder externen Fontdienste.
- Tabellen, Zeilen-/Codeeinrückungen und zusammengehörige Formeln bleiben direkt
  in den Lernansichten lesbar. Nicht unterstützte Notation bleibt als Text erhalten.
- Zehn neue begrenzte Grafikfamilien zusätzlich zu den 36 bisherigen Typen:
  polynomiale Funktionsgraphen, Standardkurven, Datenplots, Zellen, Bindungsschemata,
  Logiktafeln, Widerstandsnetze, Maßskizzen, Prozessgraphen und Kreisläufe.
  Wortbelege, Zahlen/Beziehungen, Fachprofil und Offenlegungsstufe werden
  serverseitig geprüft. Kein beliebiges Modell-SVG und keine erfundenen Beziehungen.
- Verschwindende Hinweisgrafiken durch Aktualisieren der führenden lokalen
  Einheit behoben. Lange Tipps öffnen am Anfang. Vorlese-/Bildbeschreibungen
  bereinigt; Prozessbeschreibungen enthalten die tatsächlichen Pfeilrichtungen.
- Im Web-Großschrifttest doppelte WidgetSpan-Skalierung gefunden.
  Regressionsprüfung scheitert vorher bei rund 3,74-facher Höhe statt zweifacher;
  nach dem Fix skalieren TeX und ältere Brüche bei 200 % genau einmal auf zweifach.
  Standalone-Formeln und normaler Text behalten ihre Vergrößerung.

## Prüfungen und Grenzen

127 künstliche Formelbeispiele und 28 neue Grafikfälle; vorhandene 48 Fachfälle
für 24 Fächer weiterhin geprüft. Das Raster für Klasse 1 bis 13 steht in
[SCIENTIFIC_CONTENT.md](SCIENTIFIC_CONTENT.md). Es ist keine automatische
Stoffzuweisung und keine vollständige Abnahme aller Länderlehrpläne,
Spezialzeichnungen oder mathematischen Antwortprüfungen.

Native Renderer mit tatsächlichen Roboto-/KaTeX-Schriften bei 320/1440 px und
100/200 % geprüft. Zusätzlicher Web-Runner mit dem echten UnitScreen. Der Browser
ignorierte die Viewport-Anforderung; deshalb wurde eine explizit 390 px breite
Flutter-Appfläche mit entsprechender MediaQuery innerhalb des tatsächlichen
1280 px breiten Browsers geprüft. Dies ist keine beobachtete Smartphone- oder
TalkBack-Abnahme. Lokale Fixtures und Mockantworten belegen keinen KI-Erfolg.

Abschließende vollständige Flutter-Suite auf Produktstand 58: **870 Tests bestanden**.
277 gezielte Fluttertests ebenfalls bestanden; Analyse ohne Befund. 294 PostgreSQL-
Integrationsprüfungen und 63 gezielte Nachprüfungen bestanden. Das sind
überschneidende Mengen, keine Summe unterschiedlicher Tests. Ruff und Diffprüfung
sauber. Beide gebauten Android-Archive und 575 Quelldateien auf den tatsächlich
verwendeten Provider-Schlüssel einschließlich Base64-Darstellung geprüft: kein
Treffer. Das ist keine allgemeine Zertifizierung der Geheimnisfreiheit.

## Tatsächliche Produktionsprüfung

Eine vorhandene künstliche Handschriftseite im normalen Kinderzugang bewusst
neu eingelesen: alle drei Themen, Formeln und fünf Zeichnungsbereiche erhalten.
Privaten Originalausschnitt vergrößert, Abschrift geprüft und ausdrücklich
bestätigt. Alte Quelle und Antworten erhalten. Zehn bestätigte Seiten danach.
Keine gedruckte neue Testseite und kein ungeprüfter Vokabelimport.

Heft-Hilfe zu Umfang und Fläche des belegten Rechtecks mit 6 cm × 4 cm tatsächlich
angefordert: richtige Formeln, 20 cm Umfang und 24 cm² Fläche, Einheiten gesetzt.
Zwei wörtliche Quellenbelege geöffnet. Gespeicherte Antwort nach App-Neuladen
zuletzt auf Version 1.12.2 über reine GETs wieder geöffnet, ohne neuen KI-Auftrag.
Privater Screenshot: `artifacts/science-browser/production58-formula-help.png`.

Abschließender Serverabgleich: zehn bestätigte Seiten, fünf abgeschlossene Runden,
18 beantwortete Aufgaben und 21 Antwortversuche; keine aktive Verarbeitung.
Keine Kinderantwort zum Testen neuer Fachinhalte eingetragen und kein früherer
Lernerfolg umgeschrieben. Die frühere Übungsprüfung ist in
[APP_AUDIT_2026_10_20.md](APP_AUDIT_2026_10_20.md) getrennt dokumentiert.

## Tatsächliche OpenRouter-Kosten

| Auftrag | Modell | Input/Output | Anbieterangabe USD |
| --- | --- | --- | ---: |
| Handschrift-OCR | openai/gpt-6-luna | 4766/1669 | 0,001312 |
| Heft-Hilfe | openai/gpt-6-luna | 3704/387 | 0,000564 |
| Zusätzlich berichtet | | | 0,001876 |

Providerrevision 29 unverändert, keine erhöhten Kontingente oder neuen Proben/
Fallbacks. Alte Reservierungen und unbekannte Gebühren bleiben bestehen.
Mit der vorherigen Abnahme: 0,225889 USD berichtet, plus konservativ höchstens
0,013486 USD für die drei früheren ungeklärten 400er; insgesamt höchstens
0,239375 USD unter der bisherigen Inferenzgrenze von 0,25 USD. Das ist keine
Angabe über Bildgenerierungs-/Codex- oder unbekannte Kontogebühren. Die Darstellung
selbst benötigt keinen zusätzlichen Modellaufruf; Zusatzregeln nur für gewählte
Fächer, reine Rückblicke ohne Grafikauftrag. Die zwei Aufträge sind im
abschließenden Usage-Abgleich weiterhin die einzigen neuen Inferenzaufrufe.

## Release und Rückweg

Live: **1.12.2+58**, Release `20261020T104607Z-f3a631a`, Produktcommit
`f3a631ac6e7876e8cbd4a7bb755e2385cda449f6`. Alle Produktcommits nach main gepusht.
Der nachträgliche Dokumentationscommit ändert die gebauten Clientquellen nicht.
Öffentlicher `/api/health` meldet status=ok, dieselbe Version und Quellrevision.
API, Worker und Caddy aktiv; Sicherungsdienst Result=success, ExecMainStatus=0.
Vor Aktivierung Konfiguration/Datenbank gesichert und Caddy validiert.

Web, signierte Direct-APK und Play-AAB gebaut. APK: 72.284.703 Bytes, SHA256
`7a3f2e082573174e07b2f3ac0feb70a36ce7478cbcaf5f7be81c5fc3dbb9a7bf`.
Vollständiger [öffentlicher APK-Download](https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk)
stimmt nach Größe/Hash mit Manifest und Serverdatei überein; bestehende
Paket-/Signierer-/Quellversionsprüfung im Releaseweg bestanden. Play-AAB:
68.025.009 Bytes, JAR-Signaturprüfung erfolgreich. Die Prüfausgabe enthält die
bekannten Hinweise zum selbst signierten Zertifikat, fehlendem Zeitstempel und
unterschiedlichem JAR-Streamingverhalten; keine Play-Veröffentlichung oder
vollständige native Geräteabnahme behauptet.

Kompatibler vorheriger Release: `20261020T102707Z-79c80ff` (1.12.1+57).
Schema 0023 unverändert. Neue KI-Aufträge vor einem Rückweg anhalten, aktive
abarbeiten, dann vorhandenes `deploy/activate.py <release> --rollback-compatible`
verwenden. Der Rückweg verliert den letzten Formelskalierungsfix. Kein
DB-Restore über neue Antworten oder das Löschjournal. Quellen, Daten und Secrets
bleiben außerhalb der Releases; KI-Anmeldung/Providerrevision unverändert.
