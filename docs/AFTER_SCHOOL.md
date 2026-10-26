# Nach der Schule

Im eigenen Kinderzugang „Nach der Schule starten“ öffnen. Der Assistent speichert pro Kind und lokalem Datum genau einen Schultag. Direktlink: `/after-school/<eigene-Kind-ID>`. Ein Neustart oder zweites Gerät öffnet die gespeicherten Seiten und den aktuellen Schritt. Standard bleibt die manuelle Seitenprüfung. Der optionale automatische Fotoabgleich wird im Abschnitt „Seitenprüfung ab 1.36.30+142“ beschrieben.

1. **Seiten sammeln:** Heftseiten fotografieren oder bis zu acht Galeriebilder gemeinsam wählen. Jedes Bild vor dem Upload lokal drehen und persönliche Angaben abschneiden. Gespeicherte Fotos erscheinen mit Vorschau und sortierbarer Seitennummer. Kleine, detailarme und identische Fotos erhalten Prüfhilfen; die Heuristik ist keine garantierte Unschärfeerkennung. Unbestätigte Seiten lassen sich entfernen und neu aufnehmen. Maximal 24 Seiten pro Tag, Einzelbild maximal 10 MB/16 Megapixel vor serverseitiger Verkleinerung.
2. **Stoff prüfen:** Nach „Alle Seiten sind da“ alle Bilder nacheinander erkennen lassen. Der dauerhafte Worker verarbeitet jede Seite mit einem kontingentierten KI-Aufruf. Ein eigener Abschreibauftrag fordert alle lesbaren Überschriften, Absätze, Tabellenbeschriftungen und Rechenbeispiele in Reihenfolge an; er enthält weder Lernhistorie noch Aufgabenregeln. Die tatsächlichen Textblöcke werden unverändert zusammengefügt. Eine konservative Bildprüfung weist offensichtlich bloße Kurzbeschriftungen dichter Textseiten zurück; sie ist kein Vollständigkeitsnachweis und verlangt keine Mindestwortzahl für kurze Notizen oder Zeichnungen. Fach, Thema, Text, Unsicherheiten und ausdrücklich notierte Hausaufgaben werden je Seite geprüft. Die Vorschau lässt sich vergrößern. Vollständig unleserliche Seiten bekommen den Status `unreadable`, dürfen keinen erfundenen Stoff/Hausaufgaben enthalten und lassen sich ohne Bestätigung ersetzen. Ein Abbruch erhält erkannte Seiten; laufende Aufträge werden angezeigt und nicht erneut gestartet. Noch nicht verarbeitete Seiten lassen sich danach fortsetzen.
3. **Lernen und festigen:** Im manuellen Modus erlauben erst vollständig bestätigte Seiten die Paket-Erstellung. Im automatischen Modus gilt der unten beschriebene sichere Abschluss je Seite. Zusammengehörige Seiten werden nach Fach gebündelt und gemeinsam an den Aufgabenprovider übergeben. Eine strukturierte Antwort enthält höchstens drei kurze Einheiten mit Erklärung und je zwei bis fünf Aufgaben; der Free-Standard bestimmt zwei bis fünf Aufgaben je Einheit anhand der bestätigten Themen und verfügbaren Zeit. Diese Einstiegsrunde ist nicht der gesamte Lernweg. Je Einheit etwa acht Minuten, bei kürzerer verfügbarer Zeit mindestens fünf; Elternvorgaben begrenzen die Auswahl zusätzlich. Der Paketaufruf reserviert einen weiteren KI-Aufruf. Fehler erzeugen keine Ersatzübungen oder versteckten Wiederholungen.

Bereits eingeplante Einheiten und verbindliche Eltern-/Hausaufgabenaufträge behalten ihre Zeit. Schwerpunkte, Fach-Lerntage, Lernpausen und Tages-/Wochenumfang begrenzen das Paket. Nicht passende Themen bleiben sichtbar gespeichert. Sie werden weder als gelernt markiert noch täglich zu einem Pflichtberg addiert. Ein Foto belegt nur den gezeigten Ausschnitt; erzeugte Übungen behaupten keine vollständige Hausaufgabenerledigung. Bestätigter Text ist auf insgesamt 60.000 Zeichen begrenzt.

Jede neue Einheit beginnt mit der gespeicherten Erklärung, danach folgen Übungen und eine letzte Aufgabe zum selbstständigen Erinnern. Der bestätigte Leseschritt bleibt bei einem Gerätewechsel erhalten; daraus wird keine Beherrschung abgeleitet. Spätere Wiederholungen übernehmen ebenfalls alle noch verfügbaren bestätigten Quellseiten, nicht nur das erste Foto. Antworten, Hinweise, ungefähre Aktivität und Wiederholungen verwenden dieselbe Speicherung wie andere Einheiten. Die Elternübersicht verlinkt das heutige Paket; alle Heftseiten bleiben erreichbar. Quellenrevisionen und eine Prüfsumme der Elternplanung werden vor/nach dem KI-Aufruf verglichen. Änderungen verwerfen die veraltete Ausgabe vollständig. Kinder-/Familienrechte werden bei jedem API-Zugriff geprüft. Ein fertiges Paket lässt sich am selben Tag ergänzen. Neue bestätigte Quellenrevisionen erzeugen zusätzliche Einheiten mit einer neuen Paketversion; ältere Einheiten und Antworten bleiben unverändert. Bereits verarbeitete Quellen werden als solche erkannt. Für neue Seiten desselben Fachs werden alle zusammengehörigen bestätigten Seiten als Kontext verwendet. Die Ergänzung lässt sich auch ohne weiteren KI-Aufruf für später speichern. Eltern können gespeicherten Stoff mit einem frühesten Lernbeginn als eigenen Auftrag einplanen; die spätere Einheit verwendet zusammengehörige bestätigte Seiten gemeinsam.

## Daten und Betrieb

Migration `0004` ergänzt `school_days`, Seitenzuordnungen, Zeitangaben für Einheiten sowie `unit_sources`. Quellenverknüpfungen enthalten IDs/Revisionen, keine zusätzlichen Fotokopien. Export/Löschung umfassen die neuen Datensätze; der 365-Tage-Job bereinigt Schultage. Ein kompatibler Code-Rollback kann zusätzliche Tabellen/Spalten stehen lassen. Vor Migration sichern; ältere Release-Migrationen beim Code-Rollback nicht erneut ausführen.

Android verwendet den Kamera-/Galerie-Picker. Nach systembedingter Beendigung während der Aufnahme wird `retrieveLostData` beim Start geprüft. Wiederaufnahme nur für das zuvor im sicheren Gerätespeicher vermerkte und weiterhin angemeldete Kind. Vor dem Upload Foto erneut prüfen. Keine automatischen Foto-Uploads; Abmelden verwirft die Wiederaufnahme.

## Freigabe und Tests

Die Betreiberfreigabe für OpenRouter Free ist dokumentiert. Reguläre Kinderzugänge verwenden die zusätzlich technisch geprüfte Route mit gesperrter Datensammlung; ungeprüfte oder ungültige Anbieterantworten bleiben gesperrt. Einzelheiten: [AI_STANDARD.md](AI_STANDARD.md). Der synthetische Testraum bietet zwei unterschiedliche serverseitig erzeugte Bruchrechnungsseiten. Erkennung und Paket-Erstellung verwenden echte kostenlose OpenRouter-Aufrufe. Der Adapter ersetzt sämtliche freien Aufrufdaten durch feste Testinhalte; Demo-Markierungen erlauben keine externen privaten Eingaben.

- Backend: `backend/tests/test_school_day.py` prüft mehrere Fächer/Seiten, Wiederaufnahme, Bestätigung, Quellen, Elternzeit, Antworten/Hinweise, Export/Löschung, Geschwisterschutz, Datenschutzsperre, Parallelität und atomaren Abbruch bei geänderten Quellen/Vorgaben oder ungültiger Ausgabe.
- Flutter: `app/test/school_day_test.dart` prüft seitenweise Bestätigung auf 390/1280 Pixeln und Wiederaufnahme laufender Aufträge ohne erneuten POST.
- Öffentlicher KI-Test: `.venv/bin/python scripts/public_school_day_smoke.py` (drei mitgezählte kostenlose Aufrufe, ausschließlich feste Testbilder/-texte).
- Regulärer Kinderzugang ohne Demo-Markierung: `.venv/bin/python scripts/prepare_normal_ai_smoke.py`, dann `cd qa && node school_day.mjs --keep-for-native`. Dieser Ablauf wählt zwei neue künstliche Fotos im echten Browser aus, schneidet sie zu, bestätigt die erkannten Seiten und bearbeitet das echte KI-Paket. Danach optional `.venv/bin/python qa/android_school_day.py`; Aufräumen mit `.venv/bin/python scripts/prepare_normal_ai_smoke.py --cleanup`.
- Alternativer Demo-API-/Browsertest: zunächst obigen Befehl mit `--keep-for-browser`, dann `cd qa && node school_day.mjs`. Private ignorierte Fortsetzungsdatei unter `artifacts/` und eigene Testfamilie werden nach erfolgreichem Browsertest gelöscht.


## Zuverlässige Uploads und Verlauf

Zugeschnittene, metadatenfreie Fotos werden vor dem Senden in einer begrenzten lokalen Warteschlange gespeichert: höchstens acht Fotos und 3 MB. Innerhalb von 24 Stunden fortsetzbar; ältere Einträge werden beim nächsten Appstart oder Öffnen des Assistenten bereinigt. Abmelden und ausdrückliches Entfernen löschen sie lokal. Browser-Speichergrenzen können früher greifen; ein Speicherfehler wird angezeigt und nicht als erfolgreicher Upload ausgegeben. Ein gestörter lokaler Speicher lässt sich ausdrücklich leeren.

Senden ist eine sichtbare Aktion. Jede gespeicherte Aufnahme besitzt einen zufälligen Upload-Schlüssel. Der Server serialisiert Wiederholungen pro Kind, vergleicht den bereinigten Bildinhalt und gibt bei identischer Wiederholung denselben Datensatz zurück, auch wenn der Assistent inzwischen einen Schritt weiter ist. Anderer Inhalt mit demselben Schlüssel wird abgelehnt. Bloßes Öffnen oder erneutes Laden startet keine KI-Verarbeitung. Die ausdrücklich abgegebenen Fotos folgen dem gespeicherten Verarbeitungsauftrag; Netzfehler lösen keine versteckten Wiederholungen aus. Die lokale Warteschlange ist kein vollständiger Offline-Lernmodus.

„Tagespakete“ öffnet den paginierten Verlauf. Ein bestimmter Tag ist über `/after-school/<Kind-ID>?day=<Schultag-ID>` erreichbar. Vergangene Fotozusammenstellungen sind dort schreibgeschützt; Einheiten bleiben fortsetzbar. Die Backend-Prüfung beschränkt auch Historie, Sortierung und Ergänzung auf berechtigte Accounts.

Migration `0005` ergänzt Paketversionen, Upload-Schlüssel/Prüfsummen, Lesbarkeit, den bestätigten Einführungsschritt, frühesten Auftragsbeginn sowie Betriebs-/Löschprotokolle. Der Bestand einer begonnenen Einheit einschließlich Antwort und Paket bleibt bei Migration erhalten. Betreiberfreigabe und technischer KI-Routingbefund: [APPROVALS.md](APPROVALS.md). Breiterer künstlicher Prüfkatalog: [QUALITY.md](QUALITY.md).


## Größere Stoffmengen ab 1.1.0

Die kleine Einstiegsrunde begrenzt den gesamten Lernumfang nicht mehr. Alle bestätigten Seiten ergeben einen dauerhaften Lernweg mit dem Stoffumfang entsprechenden geplanten Aufgaben; weitere 2–5-Fragen-Etappen entstehen auf ausdrückliche Aktion. Elternzeit und Pausen begrenzen den Tag, ohne Stoff zu löschen oder versäumte Tage aufzuhäufen. Geplante, tatsächlich erzeugte und bearbeitete Fragen bleiben getrennt sichtbar. Heftfragen mit Textbelegen und freiwillige Sprachfunktionen: [STUDY_PATH_TUTOR.md](STUDY_PATH_TUTOR.md).


## Seitenprüfung ab 1.36.30+142

Der Installationsstandard ist `manual`. Betriebsadministratoren können unter
KI → „Prüfung neuer Heftseiten“ ausdrücklich `manual` oder `automatic` speichern.
`GET /admin/installation/material-review` liefert `{mode, revision}`;
`PUT` benötigt `{mode, expected_revision}`. Eine veraltete Revision wird mit HTTP 409
abgewiesen; der lokale Entwurf bleibt bis zum bewussten Abgleich erhalten.
Ein unveränderter Modus erzeugt keine zusätzliche Änderungsrevision. Die
Einstellung wird verschlüsselt gespeichert und ihr Lesen/Ändern auditiert.
Das Umschalten bestätigt keine vorhandene Seite und erteilt keine neue
Anbieter-, Datenschutz- oder Kostenfreigabe.

Im automatischen Modus bindet eine neue ausdrückliche Fotoabgabe den Ablauf an
Sitzung, Familie und Richtlinienrevision. Nach erfolgreicher erster Erkennung
reserviert der bestehende Worker genau einen eigenen zweiten Bild-/Abschrift-
Abgleich je gebundener Seitenrevision. Er erhält das unveränderte Foto und die
erste gespeicherte Abschrift, liest das Foto erneut und vergleicht beide.
Das ist ein eigener begrenzter `extract`-Auftrag mit eigener regulärer
Kontingentreservierung, kein Providerretry. Bildprüfsumme, erste Quellversion,
Sitzung, Familie, Richtlinie und reservierte Anbieterroute werden vor und nach
dem Aufruf erneut geprüft. GETs und Browserpolling starten keinen Aufruf;
ein Neustart setzt denselben gespeicherten Ablauf fort. Allein ein Moduswechsel
oder Neustart erzeugt weder eine weitere Erkennung noch eine zusätzliche Wiederholung.
Alte Aufträge ohne gespeicherte automatische Herkunft werden nicht nachträglich
in diesen Ablauf übernommen.

Der zweite Durchgang darf belegte Lesefehler korrigieren, keine falsche sichtbare
Schülerrechnung durch eine richtige Ersatzaufgabe ersetzen. Beide vollständigen
Abschriften sowie die Herkunft der zusammengeführten Fassung bleiben in
`SourceRevision` erhalten. Widersprüchliche Schüler-/Korrekturbereiche werden
konservativ mit Originaltext und konkreter Unsicherheit bewahrt. Die
zusammengeführte Fassung durchläuft dieselben begrenzten Schema- und
Plausibilitätsprüfungen; sie wird nicht passend gekürzt. Eine erkennbare Lücke
bleibt eine Lücke und wird nicht durch erfundenen Stoff ersetzt.

Materialdetail und Schultagsseiten können `material_review` mit
`mode="automatic"`, `status`, `message` und optional `snapshot_id` liefern.
Die Zustände bedeuten:

- `checking`: Der zweite Abgleich läuft; die erste Abschrift bleibt gespeichert.
- `checked`: Der Abgleich ist abgeschlossen.
- `checked_with_gaps`: Der Abgleich ist abgeschlossen, aber Lesestellen bleiben
  offen. Auch eine vollständig unleserliche Seite kann so mit leerem Lerninhalt
  gespeichert bleiben.
- `failed`: Der Abgleich ist fehlgeschlagen; Foto und erste Abschrift bleiben
  erhalten. Die Seite wird vorerst nicht für bewertete Aufgaben verwendet.

Bei erfolgreichem Autoabgleich erhält die gespeicherte Fassung eine neue
Revision und technisch `confirmed=true`; `confirmation_digest` bleibt leer.
Das kennzeichnet eine automatisch übernommene Abschrift, keine menschliche
Bestätigung und keine Garantie fachlicher Richtigkeit. Die Oberfläche nennt
entsprechend „Automatisch abgeglichen“ und erhält die Hinweise zu offenen
Lesestellen. Bestehende Korrekturentwürfe werden bei einer Auto-Revision nicht
überschrieben: Ein Quellenkonflikt sperrt die Übernahme; ein älterer Entwurf
bleibt im selben angemeldeten Konto auch nach Schließen/Wiederöffnen erhalten.
Sein Verwerfen zugunsten der neuen gespeicherten Fassung erfordert eine
Rückfrage. Kontowechsel darf den Entwurf nicht an ein anderes Konto binden.

Ein technischer Fehler erzeugt keinen automatischen weiteren KI-Versuch. Die
betroffene Seite bleibt außerhalb der sicheren Lernbasis; andere verwendbare
Seiten desselben bewusst abgegebenen Tages können weiter vorbereitet werden.
Scheitert bereits die erste Erkennung, wird das nicht als erfolgreicher
Zweitcheck ausgegeben. Wenn gar keine verwendbare Quelle übrig bleibt, heißt
der Abschluss „für später gespeichert“ und enthält keine vorgetäuschte
Lernrunde. Fachliche Unsicherheit, Lesen und Lernnachweise bleiben getrennt.

Im manuellen Modus bleibt „Stimmt, weiter“ die ausdrückliche Quellenbestätigung,
ohne weitere Prüfcheckbox. Die einzeln geöffnete Materialansicht lädt danach
per GET die nächste ungeprüfte Seite in der Reihenfolge des ursprünglichen
Schultags; erst nach dessen letzter Prüfseite führt sie zur Tagesübersicht.
Dies startet keine zusätzliche KI und übernimmt keine weitere Seite automatisch.
Fertigmeldungen und ihre tatsächlichen Rundenziele sind in
[NOTIFICATIONS.md](NOTIFICATIONS.md) beschrieben.

Für 142 sind diese Verträge bislang lokal mit künstlichen Backend-, Transport-
und Widgetfällen geprüft, insbesondere `test_material_auto_review.py`,
`material_auto_review_142_test.dart` und `material_confirm_next_141_test.dart`.
Dies ist noch kein Deployment- oder Live-Erkennungsbeleg. Die Abnahme der
veröffentlichten Version und gegebenenfalls der echten Geräte erfolgt gesondert.


### Kompakter Fotoeinstieg143

„Fotos auswählen“ öffnet unmittelbar die normale Geräteauswahl. Tages- und Zwischenspeichergrenzen werden weiterhin durchgesetzt; nicht übernommene Fotos behalten ihren einzelnen Beleg. Im Zuschnitt steht das Originalbild vor optionalen Ansichts-/Drehwerkzeugen; Randregler, Rückgängig und Vorschau bleiben erreichbar. Sobald Fotos vorhanden sind, steht „Fotos abgeben“ oberhalb der Vorschauen. Ein lokaler Widgetfall mit vier Seiten prüft die sichtbare Hauptaktion auf390px.

Unzuverlässige Markierungsmetadaten einer OCR-Antwort dürfen lesbare Abschrift nicht verwerfen: ein nicht exakt verankertes Annotationszitat wird nicht geraten, sondern entfernt und der ganze Abschnitt unsicher markiert. Farbe allein ergibt weiterhin keine Lehrerzuordnung. Das ist keine Quellenbestätigung oder fachliche Korrektur; der gesondert reservierte Gegencheck und die bestehende Quellenprojektion bleiben erforderlich.
