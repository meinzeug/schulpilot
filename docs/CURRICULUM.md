# Schulprofil und Lehrplanorientierung

Die Elternansicht speichert Bundesland, eine angebotene Schulform und Klasse1–13
pro Kind. Das ist eine ausdrückliche Zuordnung: Alte freie Schulangaben werden
nicht still einer amtlichen Schulform zugeordnet. Nach einer Änderung außerhalb
dieses Profils bleibt die frühere Zuordnung sichtbar als erneut zu prüfen.

`curriculum.py` liefert den öffentlichen Katalog und die getrennten privaten
Kinderprofile. Schreibzugriff erfordert die aktuelle berechtigte Elternsitzung,
Familienmitgliedschaft, Kontobindung, Profilrevision und Idempotenzschlüssel.
Kinder können ihr eigenes Profil lesen; Betriebsadministratoren erhalten dadurch
keinen Zugriff auf private Lerninhalte. Profiländerungen werden auditiert und
exportiert; die neuen kindgebundenen Tabellen folgen der bestehenden Löschung.

## Daten und tatsächliche Abdeckung

Die versionierten Dateien `reference/curriculum-sources-v1.json` und
`reference/curriculum-topics-v1.json` enthalten58Dokumente und766Zuordnungen
mit23Fachschlüsseln aus16Bundesländern. Dokumente behalten amtlichen Verweis,
Fassung, Status und Digest; Themen behalten Abschnitt, gegebenenfalls Seite,
Klassenband oder Originalphase. Ein Band wird nicht als amtlich festgelegte
Einzelklasse ausgegeben. Vorgeschlagene kanonische Themenkennungen sind noch
keine geprüften Kompetenzzuordnungen.

Der Bestand ist ausdrücklich unvollständig:20Dokumente/309Zuordnungen sind als
aktuell geprüft markiert,38Dokumente/457Zuordnungen als Fassung ungeprüft.
Enthalten sind auch amtliche Indizes, Handreichungen und historische Dokumente.
48schulformübergreifende Zuordnungen besitzen derzeit keine konkret nutzbare
Schulformbeziehung. Für Klasse12 fehlen Zuordnungen; Klasse11 und13 haben
nur fünf beziehungsweise vier. Dies ist weder ein vollständiger deutscher
Lehrplanbestand noch eine Sammlung von766Grafiken oder Animationen.

Der Import prüft erlaubte amtliche Hosts, Schema, eindeutige Kennungen,
Fachstamm und echte Geltungsbereiche. Wiederholtes Einspielen desselben
Bestands ist idempotent. Neue geprüfte Dokumente und Zuordnungen können über
den bestehenden administrativen Import ergänzt werden; keine externe Suche
oder KI läuft bei einem Katalog-GET.

## Verwendung bei der Vorbereitung

Ein bestehender Einheiten- oder Paketauftrag bekommt höchstens acht lokale
Lehrplanmetadaten zu ausdrücklich konfiguriertem Bundesland, Schulform,
Klassenbezug und ausgewählten Fächern. Das ist Planungsorientierung; bestätigter
Heftstoff, Elternziele und Quellenbelege bleiben maßgeblich. Lehrplanüberschriften
sind keine Antwortquelle, kein zusätzlicher Lernstoff und kein Leistungsbeleg.
Die bestehende Reservierung und Anbieterzahl ändern sich nicht. Quellen und
Profilbindung werden nach der Vorbereitung erneut geprüft.

Migration0041 ergänzt vier Tabellen nach0040, ohne bestehende Quellen,
Antworten, Erinnerungen oder gemeinsame Grafikbausteine umzuschreiben.
Migration0042 ergänzt anschließend die zwei Tabellen der Benutzerverwaltung.
Die tatsächliche additive Kette wurde in isoliertem PostgreSQL16 und SQLite
mit erhaltenen Altantworten, Unicode, Lernzeit und gemeinsamen Bausteinen
geprüft. Das ersetzt keine fachliche Abnahme der fehlenden Lehrplanbereiche.
