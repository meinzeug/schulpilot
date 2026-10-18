# Fachstamm und Sofatutor-Lerntipps

## Stand 18.10.2026

Produktiv ist weiterhin **1.6.1+37 / Schema0018**, Release
`20261018T155252Z-56f1112`: feste Fächer und vollständige Bildhefter sind öffentlich
und nativ geprüft. **1.7.0+38 / Migration0019 ist lokal implementiert, noch nicht
bereitgestellt.** 43 gezielte PostgreSQLprüfungen einschließlich echter Migration
und anschließend alle907 Backendtests (495,91s) bestanden;337 vollständige
Fluttertests (115s) und Analyse erfolgreich. Nach dem abschließenden
Datenschutzhinweis neun betroffene Fluttertests/Analyse sowie öffentlicher
Datenschutztest erneut bestanden. Web/Android-Builds und Bereitstellung folgen.
Aktuelle Freigabe/Build-/Geräteergebnisse werden in STATUS/Handoff nachgeführt.

## Datenquelle und Umfang

Die übergebene ZIP `~/Downloads/Schulpilot_Sofatutor_ThemenDB.zip` wurde mit README,
INTEGRATION, normalisiertem JSON, Validierung, kombiniertem Prüfbericht und CSV-
Importsummary tatsächlich geprüft. Hauptquelle ist das normalisierte JSON1.5,
Snapshot vom18.10.2026, SHA256 der unkomprimierten Originaldatei:
`c67500bd581a16aaca394ab042c511836a91f223056445c51c4610778690b481`.

| Daten | Anzahl |
| --- | ---: |
| Katalogfächer / gesamter Fachstamm |16 /24|
| Stufen / aktive Stufen / leere Legacy-Stufen |126 /124 /2|
| Themen / Stufenplatzierungen |1.558 /4.188|
| Eindeutige Inhalte |8.227|
| Videos / Lerntexte |7.559 /668|
| Themen-Inhalts-Beziehungen / kuratiert bestätigt |9.828 /7.876|
| Bestätigte leere Hauptlisten |4|
| Quellen / öffentliche Themendokumente |3.892 /1.533|
| Öffentliche Links / zusätzliche Metadatenquellen / Sitemapseiten |12.505 /658 /5.871|
| CSV-Videozuordnungen |19.603|
| Vorliegende Validierungsfehler / Hinweise |0 /465|

Die19.603 Zeilen sind Beziehungen über Themen/Stufen, keine unterschiedlichen
Videos. Der CSV-Abgleich vergleicht die vollständige Multimenge der Zuordnungen
mit dem normalisierten Katalog. Hinweise bleiben Hinweise; der Import erklärt sie
nicht zu null Fehlern sämtlicher Quellen. Fehlende externe Prüfberichte sind
unbekannt. Der beobachtete Katalogumfang ist kein Nachweis des gesamten
Anbieterbestands oder einer Wiedergabeberechtigung.

Versionierte, komprimierte **Navigationsmetadaten** unter backend/schulpilot/reference:
`sofatutor-20261018.json.gz` und `sofatutor-20261018-review.json.gz`.
Keine Videos, Arbeitsblätter, Transkripte, Screenshots, Cookies oder Anbieterlogins.
Die Reviewdatei erhält die vollständigen gelieferten Prüfberichte; nur ihre
Prüfsummen, Zusammenfassung und die Katalogabdeckung stehen zusätzlich im
Snapshot. Der temporäre Quellpfad des gelieferten Imports wurde relativiert.

## Fächer und historische Daten

Migration0018 und subjects-v1.json liefern alle16 tatsächlichen Katalogfächer
plus Sport, Kunst, Ethik, Religion, Informatik, Technik, Wirtschaft und
Gemeinschaftskunde. Stabile interne UUIDs, explizite Alias- und Providerzuordnung.
Mathe/Mathematik konvergieren; Deutsch/DaZ und Sachunterricht/Biologie bleiben
getrennt. Allgemeine Fächer existieren ohne Konto, Material oder KI. Historische
zusätzliche Fächer bleiben familienprivat; Kinder sehen nur ihre eigenen.

Material, Auftrag, Einheit, Note und Mastery behalten ihre bisherigen IDs,
Labels, Antworten und Quellenrevisionen; additive Fachreferenzen verbinden sie.
Nur die historische Migration verwendet preserve_legacy_extras=True. Freie
Modelllabels erzeugen niemals Fächer. Die Quellenkorrektur bietet vorhandene
Fächer an. Bewusste neue Elternfächer sind privat und begrenzt.

Persönliche Stufen haben getrennte Arten klasse, lernjahr, vorschule. Ein
Sprachlernjahr wird nie aus der Schulklasse berechnet. Eltern wählen unter
Hefte > Fach > Themen entdecken > Stufe einstellen eine tatsächlich vorhandene
Stufe und bestätigen sie. Vorschule hat im Katalog keine Nummer; ihre explizite
persönliche API-Darstellung ist0. Ungültige Kombinationen werden zurückgewiesen.

## Additives Modell und Import

Migration0019 folgt der tatsächlich letzten0018 und enthält eingefrorene DDL,
keinen Aufruf zukünftiger ORM-Metadaten. Elf neue Tabellen:

- catalog_snapshots/state: Dateifassung, Importzeit, Abdeckung, Prüfbericht,
  aktiver Anbieterstand; erster Importzeitpunkt bleibt erhalten.
- catalog_levels/topics/placements/contents/memberships/provenance: alle
  stabilen Katalogkennungen, Titel, Typen, URLs, Fach-/Stufenbeziehungen,
  Rohmetadaten und Herkunft. Mehrfachbeziehungen bleiben erhalten.
- catalog_refreshes: begrenzte lokale Aufträge mit Lease und Checkpoint.
- learning_tip_contexts/interactions: private, kindgebundene Zuordnungen,
  bestätigte Auswahl, Rückmeldungen und separat gespeicherte Linkaufrufe.

Upserts in kleinen Batches; Import auf PostgreSQL gegen parallele Imports
serialisiert. Wiederholter identischer Import erzeugt weder Dubletten noch einen
weiteren Backfill. Inaktive alte Katalogkennungen bleiben für persönliche
Referenzen erhalten. Rückmeldungen/Bestätigungen werden bei Updates nicht gelöscht.
PostgreSQL-GIN-Index auf deutscher Volltextsuche plus Fach-/Stufen-/Kontextindizes.
Keine neue Datenbank, Vektorplattform oder Microservices.

## Gemeinsame Zuordnung

catalog_search.py trennt Kandidatensuche, konservative lokale Themenbewertung und
Klassenbeleg. Titel, Themenpfade, Überschriften und Absätze liefern mehrere
Kontextreferenzen. Zu schwache Treffer bleiben leer. Brüche erweitern/addieren
und Simple Past/Present Perfect besitzen ausdrückliche Abgrenzungen. Passende
bekannte Stufen werden bevorzugt; sie ersetzen keine inhaltliche Übereinstimmung.

In bereits reservierten OCR-, Paket-, Einheits-, Coach-, Tutor- und
Sprachprojektaufrufen ergänzt catalog_ai.py denselben Auftrag um vorhandene
Fach-IDs und höchstens zwölf lokale Themenkandidaten. Kein weiterer Modellaufruf,
keine größere Quote, kein Fallback, keine privaten Geschwisterfächer. Fotoerkennung
bleibt wörtliche Transkription; die Klassifizierung folgt danach. Modell-IDs,
Kontextreferenzen und Fachzugehörigkeit werden auch nach dem Transport geprüft.
Falsche IDs werden abgewiesen. Freie Modellgründe/Lernziele werden nicht als
sichtbare Erklärung oder Quelle gespeichert. Titel/Links stammen allein aus der DB.
Bestehende Aufgaben-, Sprach-, Quellen-, Sitzungs- und Providerprüfungen bleiben.

Genauer Stufenbezug verlangt **sowohl** passende Themenplatzierung in der bekannten
Stufenart/Nummer **als auch** curated_class_membership_verified=true. Öffentliche
Verweise mit identischer Themen-ID sind nur allgemeine Ergänzungen. Ungeprüfte
Einstiegs-/verwandte Links werden nicht automatisch empfohlen. Video/Lerntext wird
über content_type unterschieden, niemals über /videos/ im URL-Pfad. Die vier
bestätigten Leerlisten erhalten keine ersatzweise eingefüllten Klassenvideos.

## Worker, Revisionen und Nebenläufigkeit

Quellenänderungen legen deduplizierte lokale Aufträge im vorhandenen DB-Worker
an. Sie benötigen keine KI-Reservierung. Ein Import ergänzt einen globalen
Backfill für bereits vorhandene Texte. Je Aufruf höchstens20 Ressourcen, mit
Checkpoint je atomar übernommener Ressource; reguläre Lernjobs haben Vorrang.

Queue-Claim ist eine eigene kurze Transaktion. Anschließend Einheit vor Kind,
Kontext und Checkpoint sperren. Keine Kindersperre unter einer bereits gehaltenen
kaskadierenden Queuezeilensperre. Belegte Zeilen werden zurückgestellt;
abgelaufene **lokale** Leases dürfen fortsetzen, ohne Providerjobs automatisch
zu wiederholen. Neue Quellenänderungen ersetzen die alte Lease. Fehler bleiben
sichtbar, kein Dummy-Ergebnis. Unterbrechung/mehrere Worker erzeugen keine
zweite Zuordnung oder Lernleistung.

Zuordnungen enthalten Quellenfingerprint, Katalog- und Matcherfassung. Bestätigte
Themen bleiben erhalten; geänderte Quellen verlangen erneute Bestätigung. Alte
begonnene Einheiten/Antworten werden nicht überschrieben. Veraltete oder gelöschte
Quellen liefern keine aktuellen Tipps. Öffnen/Lesen einer Heftseite hängt nicht
vom Erfolg der optionalen Empfehlung ab.

## Oberflächen und Links

Gemeinsame LearningTips-Komponente in Heftfotoalbum, Quellenansicht, Verstehen und
Rückblick der Lernrunde, Tutor, Elternaufträgen und Tages-/Wochenplan. Keine Tipps
mit Lösungshinweisen im laufenden Aufgabenraum. Zunächst maximaldrei Inhalte,
weitere auf Aktion. Lerntexte ausdrücklich erkennbar, allgemeine Tipps getrennt,
unsichere Zuordnung als Vorschlag. Passt nicht ändert nur den eigenen Kontext.
Themenauswahl mit stabiler Pagination, Fachsuche und optional Meine Stufe.
Auch ein leeres Fach bietet bewusste Themensuche ohne erfundene persönliche Tipps.

Nur gespeicherte HTTPS-URLs auf sofatutor.com/www.sofatutor.com. Kein erfundenes
App-Schema, keine Wiedergabe-/App-Startzusage. Reguläre externe Öffnung, Wiederholen
und Kopieren bei Problemen. Anmeldung/Abo können nötig sein. Der fixierte
Weblauncher setzt noopener/noreferrer; Caddy zusätzlich Referrer-Policy:no-referrer.
Keine Hefttexte, Schulpilot-Zugänge oder privaten Kennungen an Sofatutor.

Linkaufrufe sind eigene idempotente Ereignisse, **keine** Attempts, angesehene
Videos, Lernabschlüsse oder gebuchten Lernminuten. Eltern sehen gespeicherte
Aufrufe am Lernstoff. Fehlende Aufrufe sind kein Beleg fehlenden Lernens.
Keine Benachrichtigung bei jedem Klick. Native Aufnahme/TTS unverändert ausdrücklich.

## Rechte, Aufbewahrung und Rückweg

Gemeinsame Referenzdaten; private Kontexte/Interaktionen nur beim eigenen Kind
oder berechtigten Eltern. Betriebsadmins bleiben ausgeschlossen. view-Eltern
lesen/öffnen, ändern aber weder Stufe noch Zuordnung oder Familienfeedback.
Backend erzwingt alle Rechte. Familienexport enthält neue private Daten;
Kinder-/Familien-/Quellenlöschung und authentifiziertes Wiederherstellungsjournal
verwenden die bestehenden Kaskaden. Private Zuordnungen/Linkereignisse höchstens365
Tage, erledigte kindgebundene technische Katalogaufträge30 Tage. Öffentliche
Katalogmetadaten haben keine persönliche Lernaufbewahrung.

Vor Release reguläre Sicherung, Migration und Healthchecks. Ein kompatibler
Code-Rückweg auf1.6.1 lässt0019 additiv stehen; alte Jobs/Einheiten/Clients bleiben
bedienbar. Alte Worker ignorieren die getrennte lokale Queue. Kein produktives
Schema-Downgrade oder Restore über neuere Antworten. Installierte APKs werden
nicht heruntergestuft. Downgrade verweigert das Löschen privater Tippkontexte.

## Befehle und Abnahme

Mit der bestehenden geschützten Backendumgebung:

```sh
PYTHONPATH=backend .venv/bin/python -m schulpilot.migrate
PYTHONPATH=backend .venv/bin/python -m schulpilot.catalog_import --validate-only
PYTHONPATH=backend .venv/bin/python -m schulpilot.catalog_import
PYTHONPATH=backend .venv/bin/python -m schulpilot.catalog_import --rebuild-tips
TMPDIR=/dev/shm .venv/bin/python scripts/test_postgres.py
```

Migration/normaler Start importieren die gebundelte Fassung einmalig. Der letzte
Importbefehl fordert ausdrücklich einen lokalen erneuten Backfill an, keine KI.
Optional --catalog mit normalisiertem JSON/Gzip und --csv mit entpackter
all_subjects.csv; nie die ZIP oder allein Video-CSV als Fachstamm importieren.

Geprüfte Teilkette: tatsächlicher voller Katalog zweimal in PostgreSQL, stabile
IDs/Beziehungszahlen, Klassen-/Sprachjahrsgrenzen, vier Leerlisten, Typprüfung,
getrennte Ziele, unbekannte KI-IDs, reine GETs, parallele Ereignisse/Worker,
Sperrkonflikte/Leasefortsetzung, Quellenkorrektur, Rechte/Export/Löschung und
vorhandene Antworten durch reale Migration. Neun neue Fluttertests einschließlich
320px/200%-Text/Tastatur, Themenpagination, Logout bei laufendem GET und Fachwahl.
Vollständige Test-, Build-, öffentliche und native Nachweise nach Abschluss in
STATUS/Handoff. Komponenten-/Mocktests sind keine echte Provider-/Geräteabnahme.
