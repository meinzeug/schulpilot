# Konsistente Lernwege und gespeicherte Anschlussrunden

Version1.36.37+149, 27.10.2026. Die technische Abnahme wird nach der Auslieferung in STATUS.md ergänzt.

## Belegte Ursachen

Die beiden geprüften Heftpakete vom24. und25.10. waren fertig vorbereitet und besaßen keine unbestätigten Seiten. Ihre offenen Etappen wurden dennoch als `source_changed` gesperrt. Der bisherige Hash enthielt die interne Quellenrichtliniennummer. Beide alten Hashes entsprachen exakt der **heutigen vollständigen sicheren Quellenprojektion**, ausschließlich mit der früheren Richtliniennummer. Der Hinweis bedeutete damit keine neu fehlgeschlagene Fotoerkennung.

Die Heute-Auswahl bot eine neu zu erzeugende Wiederholung vor einer bereits gespeicherten Anschlussrunde an. Die Anschlussrunde hatte reguläre UnitSource-Verknüpfungen zum ursprünglichen Paket, aber keine school_day_id. Deshalb fehlte sie in der Lernwegansicht. Antworten waren weiterhin gespeichert.

Frühere Etappen hatten zusätzlich reale Ausgabelängen- und Grafikstrukturfehler. Der Etappenpfad verwendete die schon für Heft-Einzelrunden geprüfte kgV-Komposition bisher nicht.

## Verträge

- `study_path.fingerprint`: stabile Hashes über Quellen-ID, Revision und sämtliche sicheren Inhalte, Belege, Ausschlüsse und Statusfelder. Ausschließlich die Richtlinienbezeichnung wird ausgelassen. Jeder tatsächliche Quellen- oder Sicherheitsunterschied bleibt relevant.
- Historische Hashes werden nur durch vollständige Neuberechnung gegen heutige sichere Daten akzeptiert. Kein gespeicherter alter Text wird für diese Kompatibilität verwendet. GET bleibt schreibgeschützt. Beim ausdrücklichen POST wird nur der kompatible Hash aktualisiert; Block-IDs, Fehler und vorhandene Runden bleiben erhalten.
- `learning_origins`: reine kontogebundene Projektion aus vorhandenen UnitSource-Verknüpfungen. Nur genau ein belegter Schultag gilt als Ursprung; gemischte Quellen bleiben eigenständige Runden. Keine Leistungs- oder Zeitänderung.
- Heute: ungelesene Rückmeldung und begonnene Runde zuerst, verbindliche Aufträge erhalten, danach fertige Runden vor neuer Wiederholung. Die Anleitung wird für genau diese ausgewählte Runde geladen. Herkunft und direkter Link zum Lernweg sind sichtbar.
- Lernweg: vorhandene zusätzliche Heft-/Anschlussrunden erscheinen separat mit direktem Einstieg. Ihre Aufgaben werden nicht als ursprünglich geplante Etappen ausgegeben.
- Ein-Aufgaben-Klassenarbeitsrunden behalten ihren eigenen bisherigen Vertrag; die Kompaktregel greift ausdrücklich nur bei2–5Aufgaben.
- `package_part_output.bind_schema(question_count=...)` beschränkt auch neue Lernweg-Etappen auf kurze vollständige Erklärungen und genau einen Grafikschritt. Der geplante Umfang2–5 bleibt unverändert; kein Abschneiden der Modellantwort, kein Anbieterwechsel oder automatischer Retry.
- Die vorhandene kgV-Komposition wird auch für passende Verstehen-/Anwenden-/Erinnern-Etappen verwendet. Regelbeleg, neue Zahlenpaare, Hauptantworten und animierbare Grafikzustände werden vor dem Anbieteraufruf gebunden. Die KI ergänzt kurze Erklärungen und Hilfen. Frühere Fragen bleiben ausgeschlossen; eine erschöpfte Auswahl wird nicht wiederholt. Fehlerdetektiv und andere Fachverträge behalten ihre eigenen Regeln.
- Etappenfehler speichern den gemeinsamen neutralen Fehlercode. Kosten, fehlgeschlagene Versuche und Wiederholungsgrenzen werden nicht zurückgesetzt.

## Prüfungen und Grenzen

`test_study_path_reconciliation_148.py` prüft historische Kompatibilität ohne GET-Schreibzugriff, echte Inhaltsänderungen, stabile Etappen-IDs, Quellenzuordnung, Auswahlreihenfolge und den vollständigen KI-Adapter für2/4Aufgaben. Vorhandene Lernweg-, Grafik- und Paketprüfungen ergänzen diese Fälle. Flutter prüft Navigation, Heute, Rückmeldungen und Lernweg. Künstliche Testdaten bleiben von der autorisierten Produktionsprüfung getrennt.

Die Änderung kann nicht jede mögliche fehlerhafte Modellantwort verhindern. Ungültige Ausgaben werden weiterhin verworfen. Keine Bestätigung ungelesener Quellen, keine erfundenen Ersatzaufgaben und keine Testantworten im Kindkonto. Für die Live-Abnahme ist ein regulär angemeldeter Kinderzugang erforderlich; ein Betriebsadministrator erhält dafür keinen privaten Inhaltszugang.

Schema0042 bleibt unverändert. Keine Datenmigration oder geänderte Kostenkonfiguration erforderlich. Rückweg: vorheriger Release147 mit gesicherten Betriebskonfigurationen; neu erstellte Runden und Abrechnungsbelege erhalten.
