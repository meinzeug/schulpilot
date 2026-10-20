# Erneute Menü- und Bedienprüfung · 20.10.2026

Ausbau auf Betreiberauftrag: alle Hauptmenüs und Unteransichten erneut prüfen,
Bedienung grundsätzlich hinterfragen und belegte Verbesserungen umsetzen.
Bereitgestellt: **1.13.0+59**. Die Hauptnavigation bleibt rollenbezogen und die
Lernrunde behält ihre klare nächste Hauptaktion. Normale Handschrift bleibt
Eingabe; keine weiteren gedruckten Heftbilder und keine Bild-KI für Appinhalte.

## Befunde und Umsetzung

| Bereich | Änderung und Zweck |
| --- | --- |
| Heute/Aufgabenraum | Vorhandenen Fortsetzen-/Fotoeinstieg geprüft. Begonnene Runde für die Prüfung pausiert; keine Antworten eingetragen oder überschrieben. |
| Lernen | Doppelte Statusangabe „Geplant · Geplant“ entfällt; echte Aufgaben-/Versuchszahlen bleiben unverändert. |
| Hefte | Kinder sehen ohne gespeicherte Präferenz zunächst Fächer mit vorhandenen Seiten. Der vollständige Katalog bleibt über den bestehenden Filter erreichbar; unzugeordnete Seiten bleiben sichtbar. Bewusst gespeicherte Ansicht hat Vorrang. |
| Wörter | Ladezustand und explizite Wiederholung eines fehlgeschlagenen GETs. Beim Filterwechsel keine alten Wortkarten unter der neuen Sprache/Sammlung/Suche. Leere Suchtreffer unterscheiden sich von fehlenden Schulwörtern; Filter der gewählten Sprache direkt zurücksetzen. Suchlänge an die bestehende API-Grenze gebunden, Rand-Leerzeichen entfernt. |
| Nachrichten | Direkter berechtigter Reader unter `/messages/<child_id>`, auch aus einer Glockenmeldung. Zuerst die Nachricht lesen, den Lernstoff danach ausdrücklich öffnen. Lesende Eltern erhalten keine Schreibaktion, Betriebsadmins keinen privaten Reader. Kontowechsel verwirft die Ansicht. |
| Verknüpfungen | Gelöschte oder fremde Lernstoffverweise werden beim Lesen ausgeblendet. Nachricht und ursprünglicher Kontext bleiben in der Datenbank/Export erhalten. Bis zu 100 Nachrichten stabil nach Datum/ID, Verweise und Absender gebündelt laden. |
| Glocke | Laden und leere Liste unterscheiden. Keine offene Vorbereitung zu inzwischen null Heftseiten und keine neue Prüfaufforderung zu bereits bestätigten Wortimporten. GET löscht keine Nachrichten/Lesebelege und startet keine KI. |
| Konto | Klarer Kindertitel und Geräteaktionen „Hier abmelden“/„Gerät abmelden“. Aktionen unter der Beschreibung lassen lange Gerätenamen und große Schrift zu. Rechte/Sitzungswiderruf unverändert. |
| Formeln/Tabellen | Echter Layoutfehler gefunden: intrinsische Spaltenmessung ist mit bestimmten Formelwidgets unvereinbar. Begrenzte responsive feste Spalten erlauben Formeln in Tabellen, große Schrift und horizontales Lesen. Trennzeichen innerhalb von TeX/Normen/Beträgen und maskierte Pipes bleiben Zellinhalt. |
| Erklärungen | Überschriften, Tabellen und eingerückten Code auch ohne Leerzeile trennen. Mehrzeilige Matrizen zusammenhalten. Eine neue Erklärung beginnt bei Schritt eins; eine Überschrift bleibt bei ihrem ersten inhaltlichen Schritt. Kurze TeX-Brüche und Norm-/Betragszeichen für das Vorlesen bereinigen. Nach langem Scrollen bei einem Schrittwechsel wieder den Anfang zeigen. |

Neue Clients melden `messages-v1`; ältere Clients behalten ihre bisherigen
Benachrichtigungsrouten. Das Headerfeld erteilt keine Rechte. Der Reader nutzt die
bestehende backendautorisierte kompakte Übersicht ohne ursprüngliche Aufgaben-
antworten. Keine Migration, Anbieteränderung, zusätzlichen Dienste oder höheren
Kosten-/Daten-/Zugangsgrenzen.

## Prüfung

Im angemeldeten Kinderzugang die Hauptmenüs Heute, Lernen, Wörter, Hefte, Konto,
Benachrichtigungen sowie Lernstand angesehen. Das ist keine vollständige Live-
Abnahme aller Betreiber-/Elternaktionen. Rollen, Familienrechte und große Schrift
werden zusätzlich mit künstlichen lokalen Fixtures geprüft; keine echten
Kinderinhalte an Anbieter und keine neuen Antwortbelege zum Testen.

Abschließende vollständige Flutter-Suite: **889 Tests bestanden**. Analyse und
Ruff ohne Befund. Zuvor 81 PostgreSQL-Prüfungen für Lernen, Konten, Löschungen,
Mindestzeiten und Benachrichtigungen bestanden; nach der letzten Serverkorrektur
19 gezielte Nachprüfungen. Die Mengen überschneiden sich. Gezielte Menü-/Layout-,
Kontowechsel- und Aufgabenraumprüfungen bestanden ebenfalls. Keine Testzahlen
als Anzahl unterschiedlicher Nutzerabläufe oder Lernerfolge ausgeben.

Lokale Sichtprüfung im echten Web-Runner mit künstlichen Mockantworten: Tabelle
mit Beträgen/Normen/Brüchen und mehrzeilige Matrix im regulären Aufgabenraum-
Erklärungsdialog lesbar. Die Appfläche ist ausdrücklich auf 390 logische Pixel
begrenzt; der tatsächliche Browser ist breiter. Keine physische Smartphone-,
TalkBack- oder vollständige WCAG-Abnahme und kein Nachweis neuer KI-Aufgaben.
Die partielle Formelvorlesehilfe ersetzt keine vollständige mathematische Sprache.

Keine eigenen neuen Inferenzaufträge für diese Menüprüfung. Bisherige gemeldete
Kosten und unbekannte Reservierungen bleiben erhalten. Das Öffnen der zuvor vom
Nutzer begonnenen Runde hatte noch Aktivitätszeit erfasst; sie wurde pausiert,
diese Zeit nicht rückwirkend umgeschrieben. Keine Prüfung dieser Einheit durch
Testantworten.

## Tatsächliche Live-Nachprüfung

Auf Version 59 im normalen angemeldeten Kinderzugang:

- Leere Wortsuche: alte Karten verschwinden, passende Leermeldung, mit
  „Filter zurücksetzen“ wieder alle neun vorhandenen Wörter erreichbar.
- Hefte zeigt die drei belegten Fächer mit 3/3/4 Seiten; der volle Katalog bleibt
  erreichbar. Pausierte Runde unter Lernen weiter vorhanden; kein doppeltes
  „Geplant“. Singular „1 Lernmodus“ korrekt.
- Direkten Nachrichtenreader über Heute → Nachrichten geöffnet und gespeicherten
  Verlauf gelesen. Keine Nachricht gesendet, keine Lernrunde dabei gestartet.
- Im Konto „Hier abmelden“/„Gerät abmelden“ gesehen, keine Sitzung widerrufen.
  Neuigkeiten ohne die frühere Meldung „0 Heftseiten“; Zähler aktualisiert.
- Sprachwerkstatt und Lernstand lesend geprüft, keinen neuen Auftrag vorbereitet.

Endbestand: zehn bestätigte Seiten, sechs Einheiten (fünf abgeschlossen, eine
pausiert), 21 Antwortversuche, keine laufende Verarbeitung. OpenRouter/Revision 29
unverändert. Browserbelege liegen privat unter `artifacts/science-browser/`:
`menu59-empty-search.png`, `menu59-notebooks.png`, `menu-step-scroll-after.png`
und `menu-table-200-horizontal.png`. Keine privaten Screenshots im Repository.

Der neue Scrolltest scheiterte vor dem Fix bei 530 statt 0 Pixeln. Nach dem Fix
besteht er; im neu gebauten Web-Runner bei 200 % tatsächlich vom Ende der Matrix
zur Tabelle gewechselt: neuer Schrittanfang sichtbar, zweite Spalte durch
Seitwärtsscrollen erreichbar. Überschrift und erster Inhalt sind derselbe Schritt.

## Release und Rückweg

Live-Release `20261020T115520Z-0720f90`, Produktcommit
`0720f9093ceb6768135db799097a794f53b13b2b`, Version **1.13.0+59**.
Beide Produktcommits und der abschließende Dokumentationscommit sind zum
bestehenden main gepusht. Der Dokumentationscommit ändert keine gebaute Quelle.
Öffentlicher Healthcheck status=ok und passende Version/Quellrevision; API,
Worker und Caddy aktiv. Sicherungsdienst Result=success/ExecMainStatus=0.
Konfiguration und Datenbank vor Aktivierung gesichert, Caddy validiert.
Schema 0023 unverändert, keine neue Migration oder Anbieterumschaltung.

Web, Direct-APK und Play-AAB aus derselben finalen Revision gebaut. Ein Lauf
meldete beim Abschluss Status 143; die Ursache ist nicht belegt. Der vollständige
Wiederholungsbuild endete mit Status 0. Danach Versions-/Paket-/Signiererprüfung,
JAR-Signaturprüfung und offizielle Bundletool-Validierung erfolgreich. Play-Paket
Version 59 ohne APK-Installerberechtigung, Signierer entspricht Release-Policy.
Die bekannten Signaturhinweise zum selbst signierten Zertifikat/fehlenden
Zeitstempel/JAR-Streamingformat bleiben dokumentiert; kein Play-Upload oder
vollständige native Geräteabnahme behauptet.

APK: **72.284.767 Bytes**, SHA256
`8b5c2065cffbde69b5de4a5a61bb1f4bdcf2f288e4038e0ff4b409b9ddf92bbb`.
Vollständiger [öffentlicher APK-Download](https://schulpilot.dorfspy.de/downloads/schulpilot-android.apk),
Serverdatei und lokales Manifest nach Größe/Hash identisch.
AAB: **68.077.470 Bytes**, SHA256
`f832f2bcce22e2bddcf55ab72b052157c7c70bd10ff42927962e1ff53074b694`.
445 getrackte Text-/Quelldateien und 334 Einträge der beiden Android-Archive
auf den tatsächlich verwendeten Provider-Schlüssel und Base64-Darstellung geprüft:
kein Treffer. Das ist keine allgemeine Sicherheitszertifizierung.

Kompatibler vorheriger Release: `20261020T104607Z-f3a631a` (1.12.2+58).
Vor Rückweg neue KI-Aufträge anhalten und aktive abarbeiten; vorhandenes
`deploy/activate.py <release> --rollback-compatible` verwenden. Kein DB-Restore
über neue Antworten oder das Löschjournal. Dieser Rückweg verliert die neuen
Menü-/Lesekorrekturen; Quellen, Antworten und bestehende Providergrenzen erhalten.
