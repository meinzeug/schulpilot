# Fachstamm, Sofatutor-Katalog und Bildhefte

## Fortsetzbarer Stand18.10.2026

Produktiv:1.5.0+35, Commit87f9cf6, Release20261018T132538Z-87f9cf6,
Schema0017. PDF-Notenimport vollständig öffentlich und nativ geprüft.
Dokumentations-/Prüfcommit7f48c42 enthält die Abnahme. Katalog-/Hefterausbau
anschließend in Arbeit, noch nicht produktiv aktiviert.

Die bereitgestellte ZIP unter `~/Downloads/Schulpilot_Sofatutor_ThemenDB.zip`
wurde tatsächlich gelesen: README, INTEGRATION, normalisiertes catalog.json,
validation, combined_coverage_report und Importsummary. Arbeitskopien der
Metadaten in artifacts/sofatutor-input, kein privates Kindermaterial.

Bestätigter Snapshot1.5 vom18.10.2026:

| Daten | Anzahl |
| --- | ---: |
| Referenzfächer |16|
| Stufen insgesamt |126|
| Aktive Stufen mit Themen |124|
| Zusätzliche leere Legacy-Stufen |2|
| Themen |1.558|
| Themen-/Stufenplatzierungen |4.188|
| Eindeutige Inhalte |8.227|
| Davon Video/Lerntext |7.559/668|
| Themen-/Inhaltsbeziehungen |9.828|
| Mit kuratiertem Klassenbeleg |7.876|
| Bestätigte leere Themenhauptlisten |4|
| CSV-Videozuordnungen über Stufen |19.603|
| Validierungsfehler/Hinweise |0/465|

Die19.603 Beziehungen wurden unabhängig aus Topic-Platzierungen und kuratierten
Videozuordnungen berechnet; es sind keine19.603 unterschiedlichen Videos.
Beobachteter Umfang und Wiedergabeberechtigung bleiben getrennte Aussagen.
Die Originaldaten enthalten nur Navigationsmetadaten/Verweise, keine Medien,
Arbeitsblätter, Transkripte, fremden Übungen oder Zugangsdaten.

## Fachidentität – implementierte Grundlage

Migration0018 folgt0017. `subjects`, `subject_aliases`, `subject_providers` und
`child_subjects` trennen Definition, eindeutige Aliasnamen, Anbieterzuordnung
und persönliche Auswahl/Stufe. `subjects-v1.json` übernimmt **alle16** Fächer
aus dem normalisierten Katalog, unabhängig von Videozeilen. Zusätzlich acht
allgemeine Fächer:Sport/Kunst/Ethik/Religion/Informatik/Technik/Wirtschaft/
Gemeinschaftskunde. Stabile interne IDs, wiederholbarer Seed beim normalen
Start, kein Konto/Upload/Anbieteraufruf nötig.

Materialien, Aufgaben, Einheiten, Noten und vorhandene Mastery-Zeilen erhalten
additive `subject_id`-Referenzen. Aliasnamen wieMathe/Mathematik konvergieren;
Deutsch/DaZ und Sachunterricht/Biologie bleiben getrennt. Historische Texte,
Antworten, IDs, ursprüngliche Fachlabels und Quellenrevisionen bleiben als
Snapshots erhalten. Es gab vorher keine zu ersetzenden internen Fachtabellen.
SQLite bekommt nullable REFERENCES-Spalten ohne Tabellenneubau, damit keine
Attempts/Quellen durch DROP/CASCADE verloren gehen. PostgreSQL normale additive
FKs. Bestehende zusätzliche unbekannte Fachnamen der historischen Migration
bleiben **familienprivat**, statt sie global anderen Familien offenzulegen.

Nur die historische Migration darf `preserve_legacy_extras=True` verwenden.
Normales Bind-/Rematching erzeugt keine Fächer aus KI-Text. Unbekannte
Modelllabels bleiben unzugeordnet. Neue eigene Fächer benötigen eine bewusste
berechtigte Elternaktion; sie bleiben in der Familie und sind für Kinder nur
bei eigener Zuordnung sichtbar. Profilanlage/-änderung verwendet denselben
Fachstamm. Export und Kinder-/Familienlöschung sind zu berücksichtigen.

Neue Lesepfade:`GET /api/subjects` für ausschließlich allgemeine Definitionen,
`GET /api/children/{id}/subjects` für berechtigte Anzahl/Auswahl je Kind.
Leere Fächer sind vorhanden. GET erzeugt keine KI oder Lernleistung.
Eigene Verwaltung über dieselbe Kinder-/Familienautorisierung; kein Adminzugang
zu privaten Fachnamen oder Lerninhalten. Elternstufen explizit mit Typ und
Nummer bestätigen, niemals ein Sprachlernjahr aus der Schulklasse raten.

## Nächste konkrete Implementierung

1. Grundlagenregression fertigstellen und eigenen Stand committen/pushen.
2. Additive Katalogtabellen an0018 anschließen; normalisierte Metadaten und
   alle Herkunfts-/Prüfkennzeichen idempotent importieren. Validierte CSV als
   zusätzlichen Beziehungsabgleich verwenden, nicht als Fachstamm.
3. Gemeinsamer lokaler Matcher: Fach, konkrete Lernziele und bekannte Stufe;
   mehrere Abschnitte/Themen, konservative Treffer. Exakte Klassenlisten nur
   mit `curated_class_membership_verified=true`, allgemeine Empfehlungen
   getrennt. Vier bestätigte Leerlisten nicht auffüllen.
4. In vorhandenen KI-Aufträgen begrenzte Kandidaten/IDs anbieten und
   serverseitig prüfen. Keine weiteren Modellaufrufe auf GET/Seitenöffnung.
5. OCR-/Quellen-/Einheitsänderungen lokal im bestehenden Pfad zuordnen;
   Katalogbackfill als deduplizierten globalen DB-Workerauftrag ohne Provider
   ausführen. Ein globaler Auftrag mit `child_id=NULL` blockiert keine
   kostenpflichtigen Kinderaufträge. Ergebnisse mit Quellenhash/Katalog- und
   Matcherfassung, manuelle Bestätigung/Feedback erhalten.
6. Gemeinsame Lerntippkomponente in tatsächliche Material-/Lern-/Tutor- und
   Fachansichten, maximaldrei erste Treffer. Nur gespeicherte HTTPS-Hosts
   sofatutor.com/www.sofatutor.com, reguläre externe Öffnung/Kopieren/Wiederholen.
   Linkaufruf getrennt von Übungsfortschritt; keine Zusage zu Abo/App-Weiterleitung.
7. Bildhefter im vorhandenen Hefte-Bereich: Fachcards, paginiertes echtes
   privates Fotoalbum, Listenschalter, Zoom und reduzierte Bewegung beachten.
   Kein unbegrenztes Vorladen oder öffentliches Speichern privater Fotos.
8. Tests/Builds, echte künstliche Browser-/Android-Kette, Migration/Import auf
   Server und regulärer gesicherter Release. Keine Abnahme aus Buttons ableiten.

## Erzeugte Bildassets

Mit dem ausdrücklich eingesetzten eingebauten Imagegen-Skill sind alle16
Referenzfach-Cover als reale A4-Papphefter mit handschriftlichem Fachnamen
erzeugt. Originale und optimierte WebP liegen in artifacts/folder-covers;
generation-manifest.json enthält die tatsächlich verwendeten Prompts und
geschützten Entwicklungsquellenpfade. Originale bleiben erhalten. Die16
640px-WebP benötigen zusammen etwa528KB. Noch nicht im Produkt eingebunden.
Beim Einbinden finale Assets nach app/assets/folders und öffentliche
Prompt-/Herkunftsdokumentation ohne lokale Entwicklungszugänge übernehmen.
Weitere vorhandene Standardfächer erhalten eigene Bilder; unbekannte eigene
Fächer brauchen einen erkennbaren allgemeinen Ersatz ohne erfundene Beschriftung.

Aktuelle Prüfzahlen/Aktivierung in STATUS/Handoff nachführen. Keine privaten
PDF-/Kinderinhalte oder Zugangsdaten in Katalog, Assets, Logs oder Git.
