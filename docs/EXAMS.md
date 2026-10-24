# Klassenarbeiten und Leistungskontrollen

Der Bereich `/exams/:childId` bündelt **Vorbereiten** und **Nacharbeiten**.
Er ist im Kinderbereich unter „Mehr“ und im Elternbereich beim jeweiligen
Kind erreichbar. Die gemeinsame Flutter-Oberfläche gilt für Web und Android.
Administratoren erhalten dadurch keinen Zugriff auf private Arbeiten.

## Vorbereitung

Eine Arbeit hat einen Titel, ein bestätigtes Fach, die Art Klassenarbeit/KA
oder Leistungskontrolle/LK und optional einen Prüfungstermin. Bis zu acht
Themen verweisen auf eigene bestätigte Heftquellen. Je Thema und zugeteiltem
Lerntag ist eine frei eingegebene Anzahl von **1 bis 50 Aufgaben** möglich;
3/5/10 bleiben Schnellwerte. Ein Termin kann offen bleiben.

Der Kalender speichert 1–30 konkrete Lerntage. Einzelne Tage und eine Auswahl
nach Wochentagen sind möglich. Tage nach dem bekannten Prüfungstermin werden
abgewiesen. 5–60 Minuten sind eine Empfehlung je Sitzung, keine Lernzeitgrenze.
Ausgelassene Termine erzeugen keinen automatisch anwachsenden Aufgabenberg.

Bei weniger Tagen als Themen werden alle Themen auf diese Tage verteilt.
Bei mehr Tagen wird die Themenfolge wiederholt; Fragen müssen jeweils neu
sein. Jede Tages-/Themenmenge wird ausgewogen auf Runden mit höchstens fünf
Aufgaben verteilt: 6 → 3+3, 11 → 4+4+3, 17 → 5+4+4+4. Die ausdrücklich gewählte
Gesamtmenge eins ist ein einzelner enger Exam-Anwendungsfall; allgemeine neue
Lernrunden behalten ihren bisherigen Vertrag.

Speichern erzeugt weder Aufgaben noch Anbieteraufrufe. Nur das Kind kann eine
Runde bewusst vorbereiten/starten. Es gelten die vorhandene atomare
Kontingentreservierung, höchstens ein offener Kinderauftrag, Anbieterbindung
und Prüfung vor und nach dem Aufruf. Jede Runde ist eine normale LearningUnit
mit den vorhandenen fachlichen Darstellungen, Hilfen, Antworten und Belegen.
Frühere Fragen werden sowohl im Modellkontext ausgeschlossen als auch gegen
sämtliche gespeicherten Fragen des Themas geprüft. Eltern können nach ihren
vorhandenen Familienrechten planen oder lesen; sie erzeugen keine Kinderzeit.

`revision` schützt Änderungen der gesamten Arbeit per CAS. `plan_revision`
bindet den Lernplan und seine Sitzungen getrennt. Fotos einer später
zurückgegebenen Arbeit ändern daher keine geplanten oder begonnenen Runden.
Eine bewusste Planänderung erhält vorherige Sitzungen als Historie.

Auf Heute erscheint nur bei einem tatsächlichen offenen Lerntermin eine
kompakte Karte. Öffnen ist rein lesend; der Termin erzeugt keine KI-Aufträge.

## Geschriebene Arbeiten

Eine Vorbereitung kann anschließend mit ihrer zurückgegebenen Arbeit
verbunden werden. Eine geschriebene Arbeit lässt sich ebenso ohne früheren
Lernplan anlegen. Bis zu zwölf Bilder je höchstens 10 MiB verwenden den
bestehenden privaten Fotoimport mit Zuschnitt, Normalisierung und Entfernung
von EXIF-Metadaten. Der Request bleibt einschließlich Multipart begrenzt.

Die bewusste Fotoabgabe speichert einen endlichen Scanauftrag. Der vorhandene
Worker reserviert pro Transaktion höchstens eine normale OCR-Verarbeitung
und nach deren Ende erst die nächste. Schließen/Neuladen und Status-GETs
starten keine Verarbeitung. Fehler halten den Ablauf an; ein weiterer Versuch
ist ausdrücklich, begrenzt und normal zu reservieren. Quellen, Sitzung,
Familienrechte und Anbieterfassung werden vor und nach OCR erneut geprüft.
Erkannte Texte bleiben Vorschläge, die vor der fachlichen Besprechung zu
prüfen und zu bestätigen sind.

Die KI-Besprechung ist ein **Aufgabenauszug, kein Vollständigkeits- oder
Benotungsnachweis**. Je bewusstem Auftrag werden einzelne Aufgaben aus
gewählten bestätigten Seiten besprochen. Neue kompakte Anbieterantworten sind
bei weniger als8000 konfigurierten Ausgabetokens auf zwei, sonst auf vier
vollständige Aufgaben begrenzt; ältere gespeicherte Berichte mit bis zu acht
Aufgaben bleiben lesbar. Weitere begrenzte Auszüge dürfen
vorherige Aufgaben, Entwürfe und Berichtigungen nicht überschreiben. Es gelten
höchstens zwölf Analyseabschnitte und alle Familien-/Kinder-/Systembudgets.
Je Auswahl und bisherigem Aufgabenstand sind höchstens zwei fehlgeschlagene
Versuche erlaubt; ein erfolgreicher Auszug eröffnet ein neues begrenztes Fenster.
Jeder gewählte Quellenauszug bleibt auf 60.000 Zeichen begrenzt. Längere OCR
bleibt lesbar und kann durch eine kleinere Seitenauswahl besprochen werden. Keine automatische Fortsetzung oder Anbieterwiederholung.

Pro Aufgabe werden getrennt angezeigt:

- die wörtliche Originalaufgabe,
- die alte Antwort des Kindes,
- sichtbare Rückmeldungen/Punkte der Lehrkraft,
- ein ausdrücklich als solcher ausgewiesener KI-Vorschlag,
- der eigene neue Verbesserungsversuch und bewusst angeforderte Hilfe.

Originalangaben brauchen wörtliche Belege in den gewählten Quellen. Die KI
behandelt unabhängig lesbare Teilzeilen einer Sammelaufgabe einzeln. Unsichere
Nachbarzeilen dürfen klare Zeilen nicht pauschal ausschließen. Dabei bleibt die
Aufgabenzeile wörtlich erhalten; eine gemeinsame Überschrift ist Kontext oder
zusätzlicher Quellenbeleg. Sichtbare alte Antworten werden nicht korrigiert.
Lehrerrückmeldungen brauchen eine ausdrücklich belegte Zuordnung zur Lehrkraft;
Farbe oder Handschrift allein genügen nicht. Fehlende Zuordnungen bleiben offen.
Die KI
ändert keine Lehrernote und erzeugt aus Papierantworten oder ihren eigenen
Urteilen keine Attempts, Lernerfolge oder Kompetenznachweise. Neue Übungen
verwenden bestätigte **Heftgrundlagen** desselben Fachs und den ausgewählten
Lernbedarf; alte falsche Antworten werden keine Lehrquelle. Allgemeine
Heft-/Wortübernahme und generische Aufgabengenerierung bleiben für
`Material.purpose=exam` gesperrt.

Eigene noch nicht eingereichte Berichtigungsentwürfe gehören zur
Kindersitzung: höchstens acht je 24 Stunden und 2.000 Unicodezeichen. CAS und
Kontextrevision verhindern veraltete Überschreibungen. Andere Geräte und
Eltern lesen diese Entwürfe nicht. Logout, Sitzungswiderruf und Quelllöschung
bereinigen sie. Eltern lesen eingereichte Besprechungen gemäß Familienrecht.

## Erinnerungen und Betrieb

Gespeicherte Lerntermine können eine lokale Erinnerungszeit erhalten. In der
Glocke werden Meldungen nur aus aktuellen gespeicherten Fakten abgeleitet;
GETs erzeugen keine Meldungszeilen oder KI. Push benötigt weiterhin
Geräte-Opt-in, Elternfreigabe und beide Ruhezeiten. Explizite Exam-Erinnerungen
sind unabhängig vom allgemeinen Tageserinnerungsschalter. Pro Gerät, Kategorie
und lokalem Tag gibt es höchstens ein neutrales Bundle.

Neue Clients melden `exams-v1` und öffnen den passenden gespeicherten Termin.
FCM behält für ältere Clients `route=/app`; `exam_path` ist ein zusätzliches,
streng lokal begrenztes Ziel ohne Namen, Fach, Note, Frage oder Antwort.
Rechte und Revisionen werden unmittelbar vor dem Versand erneut geprüft.

Migrationen **0033** (Planung) und **0034** (Nacharbeit/Fotoabgabe) sind additiv.
Export, Quelllöschung, private Dateien und 365-Tage-Aufbewahrung werden
mitgeführt. Noch nicht eingereichte Entwürfe gehören nicht in den Elternexport.
Das signierte Löschjournal bleibt auch bei Offline-Wiederherstellung führend.

Nach ersten neuen Daten/Jobs ist Release105 kein vollständig kompatibler
Reader/Worker. Schema0034 nicht herunterstufen und laufende Familien nicht mit
einer älteren Sicherung überschreiben. Einen kompatiblen Vorwärtsfix mit den
neuen Readern, Jobprüfungen und Bereinigungen verwenden. Die vorhandene
Aktivierung hält mögliche neue Writer bei Fehlern an, statt inkompatiblen
Altcode automatisch zu starten.

## Code und Prüfgrenzen

Backend: `exams.py`, `exam_schemas.py`, `exam_models.py`, `exam_review.py`,
`exam_review_schemas.py`, `exam_review_models.py`, `exam_notifications.py`.
Frontend: `exams_screen.dart`, `exam_plan_editor.dart`, `exam_review_panel.dart`,
`exams_scope.dart`, `exam_landing.dart`. Schulbuddy bindet zusätzlich den
sichtbaren Plan/die sichtbare Originalaufgabe ohne private Entwürfe.

Lokale Prüfungen verwenden künstliche Inhalte und gemockte Providertransporte.
Diese belegen API-/Worker-/Rendererverträge, keine echte OCR- oder LLM-Qualität.
Die abschließenden Builds, Browserbeobachtungen, CI-Ergebnisse und tatsächliche
Produktionsaktivierung werden im Releasebericht separat festgehalten.
