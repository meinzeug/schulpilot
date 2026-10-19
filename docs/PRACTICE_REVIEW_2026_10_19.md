# Praxistest Build 42/43 – Arbeits- und Abnahmeprotokoll

Ausgangspunkt: `main b1c3d35`, produktiver Code `9131cce`, App `1.9.0+43`.
Auftrag: aktueller Desktop-Praxistest vom 19.10.2026, acht Aufgaben, zehn
Prüfungen, drei Runden. Antworten des Testers sind keine Fähigkeitsdiagnose.
P01–P11 entsprechen den nummerierten Abschnitten dieses Nutzerprotokolls;
P12 ist der anschließend gemeldete PDF500.
Die drei historischen HTML-Dateien liegen in Downloads und wurden lokal
eingelesen; historische Zuordnungen stehen in TEST_REPORT_REVIEW.md und
FACHTEST_2026_10_19.md. Keine echten Kinderantworten zu Testzwecken geändert.

| ID | Beobachtung / aktueller Befund | Ursache / Änderung | Abnahme / Stand |
|---|---|---|---|
| P01 hoch | `Swimming pool` falsch, `swimming pool` richtig. Im aktuellen Regelpfad bestätigt. | Zielbezogene englische Anfangsbuchstabenregel; ausdrückliche Großschreibziele bleiben strikt. NFC, Whitespace und freigegebene Varianten erhalten. Konkrete Großschreibungsdimension und passender Hinweis. | Sprachmatrix bestanden: Englisch/Deutsch/Französisch, Varianten, Apostrophe, Akzente und absichtlich falsche Wörter. Alte Attempts bleiben erhalten. |
| P02 hoch | Bruchnotation funktioniert bereits. Lange Erklärungen und fehlende Biologiegraphik sind im bisherigen Renderer nachvollziehbar. | Kleinere Textschritte; drei bewusst gesteuerte Bruchbalkenschritte. Bestehende versionierte Fachdaten um endliche Wurzel-/Bestäubungsschemata ergänzen, solution bleibt vor Antwort/Hilfe verborgen. | 320/1280px,200% Text und Solution-Gating bestanden. Grafiken mit echter Roboto-Schrift geprüft und Bodenlabel korrigiert. Kein Live-KI-Nachweis aller Biologiethemen. |
| P03 hoch | Hilfedialog lädt bisher Rundenprosa, kombiniert aber Grafik der aktuellen Frage. Codefehler bestätigt, unabhängig vom unbekannten ursprünglichen Zustand. | Optionaler validierter Aufgabenbezug am bestehenden Erklärendpunkt; aktuelle Aufgabe und Zahlen liefern. Legacy-Endpunkt bleibt bedienbar. | API-Matching bestanden: `1/3+1/6` statt fremdem Beispiel; Hilfe verändert die zweite Frage nicht. |
| P04 hoch | Generische Falschantwort bei falsch addierten Nennern bestätigt. | Deterministische Fehlererkennung mit geprüftem Lösungsschlüssel und unterschiedlichen Folgetipps. Keine Ähnlichkeitsakzeptanz. | `3/9` bei `1/3+1/6`, unterschiedliche Tipps, `6/16=3/8` sowie Inhalts-/Formtrennung bestanden. |
| P05 mittel | Vorgeschichte der Originalrunde unbekannt; widersprüchliche Beschriftung ist kein Nachweis falscher Speicherung. | Gespeicherte support_reasons in Kinder-/Elternrückblick zeigen; weitere Versuche, Hinweise, Erklärung, Vorlage und STT getrennt. Keine nachträgliche Umwertung. | Synthetische Gründe, API-Idempotenz, Elternlesen ohne Aktivitäten und Verlauf bestanden. Originalrunde ohne konkrete ID nicht geprüft. |
| P06 hoch | Aktueller Code enthält bereits einen internen Dialog; `about:blank`-Ursache noch nicht reproduziert. Vorschaufehler blieb bisher ein stummes Symbol. | Authentifizierte NotebookPhoto-Ansicht mit Retry/Zoom/Zurück wiederverwenden; lokale Entwürfe sichtbar vorsehen. Gespeichert/vorgemerkt/frei gemeinsam anzeigen. Zuschnitt/Drehen vor Upload existiert bereits. | 21+3-Entwurfsprüfung bestanden; zusätzliche25 Foto-/Cache-/Kontrastregressionen bestanden. Regulärer ursprünglicher21-Seiten-Browserfall ohne neue Fotos nicht live reproduziert. |
| P07 mittel | Fachtexte und Satzanleitung bei Buchstabenhilfe bestätigt. | Vertraute Wörter, Einzelentscheidung, zurückgestellte Importpaare persistent im vorhandenen Importmodell. Sichtbarer Baustein-Rückschritt; Quelle bleibt erhalten. | Teilbestätigung, Replay nach späterer Bestätigung, Abwahl/Zurückstellen und Rückschritt der Buchstabenhilfe bestanden. |
| P08 mittel | Startseitenhilfe öffnet bisher sofort Elternnachricht. Fehlende Meldungsarten bestätigt. | Erst Erklärung/Aufgabe/Technik/Eltern wählen. Empfängergruppe und Nachricht vor Versand sichtbar. Neue Meldungsarten mit geprüftem Fragebezug. | Widget/API: kein Versand vor ausdrücklicher Elternauswahl; Empfänger sichtbar; neue Kategorien und fremde Frage404 geprüft. Keine echte Nachricht gesendet. |
| P09 mittel | Wiederholungen können eigenständige Runden mit gleicher Thematik sein. Keine Historie löschen. | Opt-in-Leseprojektion gruppiert vor Pagination; alle ursprünglichen Runden/Termine bleiben erreichbar. Pflichtaufträge und begonnene Runden separat. Mengen/Datum verständlicher. | 26 Runden bleiben in einer Themengruppe erhalten; aktive Runde und Pflichtauftrag separat. Bibliotheksregressionen und öffentliche Lernübersicht bestanden. Original26 Einträge nicht verändert. |
| P10 hoch | Uhr bereits in +43 als Klartext behoben. Ursprünglicher unlesbarer Serverbody nicht reproduziert. | 204 ohne JSON korrekt behandeln; unterbrochene/ungültige Antworten mit Wiederaufnahmepfad melden. Keine automatische POST-Wiederholung. Technischen Tagesfehler im Kinderbereich übersetzen. | API-/Zeit-/Feedbackregressionen bestanden; öffentlich zwei Wortantworten je Runde genau einmal, Feedback nach Reload erhalten. HTML-Gateway und204 synthetisch geprüft; ursprünglicher500-Body weiterhin nicht reproduziert. |
| P11 | Desktopbericht ist keine native Audio-/Smartphone-/Screenreaderabnahme. | Gezielte Widget-, Semantik-, Tastatur-, TTS-Steuerungs- und Emulatorprüfungen. | Native APK44 auf API36: Kinderlogin, vier Aufgabentypen über Unterbrechungen, vier Elternantworten und Logout bestanden. Drei Start-/Vordergrund-Updatechecks bestanden. Systemschrift200% sichtbar geprüft; physisches Gerät, hörbares Audio und TalkBack nicht geprüft. |
| P12 kritisch | Nachgereichter Eltern-PDF-Upload liefert500. Mit eigener künstlicher249.521-Byte-PDF öffentlich reproduziert. Journald meldet zweimal ProgrammingError. | Seit `aefbe4a` irrtümliche `GradeImport.source_blocks`-ORM-Spalte, die Migration0022 nur an materials anlegt. Produktionsmetadaten bestätigen das Fehlen bei grade_imports. Unbenutzte ORM-Spalte entfernt; kein ALTER/DROP und keine Notenänderung. | 55 Noten-/PDF-/Migrationsregressionen bestanden, einschließlich aller ORM-Spalten gegen Alembic head und Upload über234KB. Öffentlich nach Deployment:201, drei künstliche Noten; Replay derselben Datei und neuer Upload erkennen drei vorhandene Noten, null Dubletten. Eigene Testfamilie anschließend über den normalen Account-Löschweg gelöscht. |

## Fortsetzung

- Implementiert: Kernänderungen P01–P10; keine Schema-Migration, keine neuen
  Provideraufrufe und keine Änderung an Kontingenten oder echten Familien.
- Bestanden:268 isolierte PostgreSQL-Regressionen und323 Fluttertests;
  zusätzlich39 Fluttertests nach genauerer Unterstützungsdarstellung. Analyse und
  Ruff ohne Befund. Neun neue Renderer-/Interaktionstests nach visueller Korrektur
  erneut bestanden. Bekannte Starlette/httpx-Warnung, keine Paketmigration.
- Erledigt: PDF-/Migrationsregression, signierter Release44, öffentliche
  Browser-/Android-Emulatorabnahme und PDF-Wiederholungstest. Beide künstlichen
  Testfamilien normal gelöscht. Keine echten Konten oder Quoten geändert.
- Zusätzlich26 Sprach-/Wortschatzregressionen nach ausdrücklichem Case-Ziel und
  dem Gegenbeispiel „Englisch (Großbritannien)“ bestanden. Letzter Serverrollout
  übernimmt diese Regeln; Flutter und Artefakthash bleiben unverändert.

## Fachdarstellungen

Die zusätzlichen lokalen Schemata sind erklärende App-Bausteine, keine neuen
Fotoinhalte oder automatisch aktivierten Kurse. Sie erscheinen nur bei passenden
gespeicherten Fachbelegen und nur nach absichtlicher Hilfe/abgeschlossener Antwort.
Bestäubung (Pollen auf Narbe) und Befruchtung (Verschmelzung männlicher Keimzelle
mit Eizelle) bleiben getrennte Schritte. Quellen: [RHS Wasseraufnahme](https://www.rhs.org.uk/advice/understanding-plants/how-plants-absorb-water),
[RHS Lehrplan: Bestäubung und Befruchtung](https://www.rhs.org.uk/education-learning/pdf/qualifications/level-2/q-qao-qualification-specification-level-2-popg.pdf).
Keine fremden Abbildungen oder Kursinhalte übernommen.

## Öffentliche Abnahme Build44

- Release `20261019T174227Z-1812f15`, Produktcode
  `1812f1510d6ccfc540761fecf7edf2113412fa31`; HTTPS-Health und
  APK-Metadaten geprüft. Web-JavaScript und vollständiger APK-Download
  bytegleich mit lokalen Builds. APK67.664.730Bytes, SHA256
  `827b65247e17e0964670d1ca2b7e0d5e3f2352444e6e3c6101a6f8e32776dcfc`.
- Web, signierte Direct-APK und Play-AAB erfolgreich gebaut; Paket/Signierer/
  Versionscode/16-KB-Zipausrichtung geprüft. Bekannte Wasm-Trockenlaufhinweise
  des unveränderten TTS-Pakets und Kotlin-Pluginhinweise; keine SDK-Migration.
-24 öffentliche Browserprüfungen aller Rollen bei320/390/960/1440px bestanden,
  null JavaScriptfehler und fehlgeschlagene Leseanfragen. Admin bleibt in der
  Betriebsansicht ohne private Inhalte. Eigene künstliche Familie verwendet.
- Reguläre isolierte Testfamilie per echter Mailverifikation angelegt. Manuelle
  künstliche Wörter im normalen Wortschatz bestätigt und zwei Abrufrunden im
  Web bearbeitet. `Swimming pool` richtig; gespeicherte Antworten nach Reload
  und genau ein Attempt je Aufgabe. Kurz zuvor geprüfte Wortpaare zählen
  erwartungsgemäß als Vorlage, nicht als selbstständiger Langzeitabruf.
  Wörterseite bei320/1440px und Tab/Prüfen bedient. Familie anschließend normal
  gelöscht. Null externe KI-Aufrufe, keine Kontingentänderung.
- Noten-PDF ausschließlich künstlich:249.521Bytes; vor Fix500, danach201.
  Bestätigung, gleicher Uploadschlüssel und erneuter Upload ohne doppelte Note.
- Native Direct-APK44 auf Android36 tatsächlich bedient: eigener Kinderlogin,
  Glocke ohne Push-Opt-in, Heftansicht und alle vier Aufgabentypen. Auf mehrere
  unterbrochene Läufe verteilt; genau eine richtige Antwort je Aufgabe, spätere
  Antworten und Elternansicht4 konsistent. Frühere bestätigte Antwort nach
  Neustart nicht nochmals beantwortet. Elternlogin und Logout bedient. Drei
  automatische Start-/Vordergrund-Updatechecks sowie200% Systemschrift geprüft.
  Gboard-Stift-Tutorial, veraltete Selektoren und neue Bruchfelder erforderten
  Anpassungen des QA-Skripts; das waren keine zusätzlichen KI-Versuche.
  Reale Smartphone-, Audio-/Mikrofon- und gesprochene Screenreaderprüfung bleiben offen. Semantik-/Sprachadapter-
  tests sind kein Hör- oder TalkBack-Nachweis. Beide privaten Kontocheckpoints
  nach normaler Löschung entfernt; Emulator-Appdaten bereinigt und eigener
  Emulator beendet.

## Wiederholbarer Nachtest

1. `python qa/prepare_design_review.py`, dann `node qa/design_review.mjs`.
2. Aktuelle signierte APK auf den dedizierten Emulator5580 installieren;
   dort System-Stift-Onboarding schließen, normale Bildschirmtastatur benutzen.
   `python qa/android_design.py` verwendet ausschließlich die eigene feste
   synthetische Familie. `python qa/grade_preview_smoke.py` nur vor deren
   Bereinigung ausführen; der Test übernimmt ausschließlich künstliche Noten.
3. Für normale Wörter `python qa/prepare_practice_words.py`, dann
   `node qa/practice_words.mjs`; benötigt den bestehenden geschützten
   Test-Mailzugang. Anschließend `python qa/prepare_practice_words.py --cleanup`.
4. `python qa/prepare_design_review.py --cleanup`; private Checkpoints nicht
   weitergeben. Die Schritte sind bewusste QA-Aktionen, keine Hintergrund-KI.
5. Eigener manueller Nachtest: Englischwort mit großem Anfangsbuchstaben,
   konkrete Großschreibaufgabe,3/9 bei1/3+1/6 und zwei verschiedene Tipps;
   Fotovorschau/Zuschnitt mit eigenen künstlichen Seiten; Wörter zurückstellen
   und später bestätigen; Eltern lesen Aufgabe samt Hilfengrund. Reales
   Mikrofon, Vorlesen und Screenreader zusätzlich auf einem Smartphone prüfen.

## Gezielte Grenzen

- Keine neue Foto-OCR oder externe Fachgenerierung im Live-Nachtest; neue
  Bruch-/Biologiebausteine sind lokal an künstlichen Quellen/Renderern geprüft.
  Keine vollständige Live-Abnahme der24 Fächer und keine Lernwirksamkeitsstudie.
- Ursprüngliches about:blank, ursprünglicher unlesbarer Serverbody und
  Vorgeschichte der gemeldeten Mathe-Runde mangels konkretem reproduzierbarem
  Zustand nicht als bewiesene aktuelle Ursachen ausgegeben. Abhilfen und
  Regressionen sind getrennt dokumentiert.
- Testdaten ergeben keine Aussage über tatsächliche Fähigkeiten eines Kindes.
- Keine neue Datenbankrevision:0022 bleibt gültig; nur falsche, ungenutzte
  ORM-Spalte entfernt. Bereits gespeicherte Antworten und Noten bleiben erhalten.
- Nächste konkrete Aktion: derselbe kleine Nachtest auf einem echten Smartphone
  mit Ton/Mikrofon und TalkBack sowie der ursprüngliche Fotovorschaufall mit
  ausschließlich künstlichen Bildern. Keine zusätzlichen Betreiberzugänge
  oder Freigaben für die abgeschlossenen lokalen/öffentlichen Prüfungen nötig.

Letzter bestätigter Serverstand: `20261019T180543Z-55533ec`, Code
`55533ec034a6e462472a6f5b05fb72a71fbd4168`. Die letzte Änderung grenzt ausdrückliche
Großschreibziele gegen die Sprachvariante „Großbritannien“ ab;26 Regressionen
bestanden. Clientartefakte und deren öffentlicher Hash bleiben unverändert.
Sicherung erfolgreich, Schema0022, kompatibler vorheriger Release erhalten.
