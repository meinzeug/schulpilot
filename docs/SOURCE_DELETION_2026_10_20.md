# Quellen und zugehörige Übungen · 20.10.2026

Zusatzauftrag: Beim Entfernen einer Heftseite müssen die zugehörigen Übungen
unter Lernen verschwinden; vorhandene Aufgaben ohne Heftquellen bereinigen.
Bereitgestellt 1.14.2+62, Schema 0023 unverändert.

## Verhalten

Die Heftsammlung konnte verknüpfte Runden bereits seit 1.11.1 gezählt entfernen.
Die Prüfung unbestätigter Tagesseiten verwendete jedoch noch einen separaten
Löschweg, der gespeicherte Antworten erhielt. Alle aktuellen Foto-/Prüfwege
verwenden jetzt die gemeinsame Vorschau mit Seiten-, Runden- und Versuchszahl.
Erst die ausdrückliche Bestätigung führt die atomare Löschung aus. Der alte
Tages-DELETE sperrt Auswahlen mit gespeicherten Runden und fordert ein Update.

Direkte Quellen, Mehrquellenrunden, Folge-/Abrufrunden und historische explizite
Bindungen über Aufträge/Sprachprojekte werden berücksichtigt. Wortaufgaben lesen
die genaue gespeicherte Wortrevision einschließlich ihrer Quellenhistorie;
spätere Wortänderungen verknüpfen alte Übungen nicht mit einem anderen Foto.
Antworten, Hilfen, Rückblicke und abgeleitete Belege der gelöschten Runden werden
mit entfernt beziehungsweise aus den verbleibenden Daten neu berechnet. Andere
Fotos und ihre unabhängigen Übungen bleiben erhalten. Normaler Seitenlöschweg
erhält Elternplanung; deren separate Altbereinigung ist ausdrücklich wählbar.

Sitzungs-/Familienrechte, revisionsgebundene Vorschau, aktive Auftragsprüfung,
Sperrreihenfolge Einheit vor Kind und Löschjournal bleiben verbindlich. Keine
KI bei Vorschau/Löschung; keine Erstattung historischer Kosten oder Freigabe von
Idempotenzschlüsseln. Feste künstliche Demo-Vorlagen bleiben geschützt.

Die Aufbewahrungsbereinigung entfernt Runden auch dann, wenn sie jünger als ihre
abgelaufene Heftquelle sind. Aktive Aufträge verschieben diese lokale
Seitenbereinigung auf den nächsten Durchgang. Restore eines alten reinen
Materialjournals führt dieselbe abhängige Rundenbereinigung aus.

## Lokale Altbereinigung

Nur für den konkret beauftragten Haushalt lokal ausführen:

```sh
python -m schulpilot.source_cleanup --child-id <id>
python -m schulpilot.source_cleanup --child-id <id> --apply-digest <vorschau-digest>
```

Standardausgabe ausschließlich Zahlen und SHA256-Bestandsdigest. Zuerst Vorschau,
vor Anwendung aktuelle Sicherung und ausgewählte Zahlen prüfen. Ein veränderter
Bestand oder laufender Auftrag bricht vor der Löschung ab. Anwendung sperrt alle
Einheiten stabil nach ID vor Kind und Aufträgen, prüft neu, entfernt mit den
bestehenden Routinen und auditiert `operator.source_orphans_removed`. Keine
öffentliche Route, keine privaten Inhalte für Betriebsadmins.

Gültige manuelle Elternaufträge und bestätigte manuelle Wörter mit ihren
Übungen bleiben standardmäßig erhalten. `--include-manual-assignments` erweitert
die ausdrücklich beauftragte Auswahl um Aufträge ohne Quelle;
`--include-manual-vocabulary` würde zusätzlich gültige reine Wortrunden einbeziehen
und wird für diesen Auftrag nicht verwendet. Quellgebundene oder über gültige
Runden belegte Aufträge werden weiterhin erhalten. Jobtombstones, Verbrauch und
Reservierungen bleiben erhalten, Inhaltsverweise werden bereinigt.

## Journal und Rückweg

Auftragslöschungen erhalten einen signierten Journalbeleg mit vorhandenem
`scope=unit` und ausdrücklich signiertem `resource_kind=assignment`. Aktuelle
Werkzeuge lösen den Typ vor dem Datenbankzugriff auf. Die Live-Journalprüfung
von 1.14.0 akzeptiert und erhält diesen zusätzlichen Typ; ein Code-Rollback auf
dieses Release ist nach vollständig publiziertem Outbox-Lauf möglich.
**Wiederherstellungen müssen dagegen mindestens 1.14.2 verwenden**, damit gelöschte
Aufträge nicht zurückkehren. Keine alten Restorewerkzeuge einsetzen. Die lokale
CLI publiziert das Journal vor ihrer Erfolgsausgabe. Keine neue Datenmigration.

## Prüfung und Bereitstellung

898 Fluttertests vollständig bestanden, darunter Vorschau/Abbruch, verknüpfte
Antworten, Folgeseite und letzte archivierte Seite. 130 PostgreSQL-Prüfungen
in einer separaten lokalen Datenbank bestanden (Löschung, Altbestand,
Wiederherstellung, Aufbewahrung, Wort-/Tutorquellen). Ruff und Flutteranalyse ohne
Befund. Tatsächliches Bereinigungsergebnis siehe unten.
Kein Produktions-Testantwortversuch, kein Provideraufruf für diese Prüfung.

Rückweg: 1.14.0+60 / `20261020T124231Z-8bbd152`, kompatibles Schema 0023.
Vor Code-Rollback neue KI-Aufträge anhalten und aktive Aufträge abarbeiten lassen;
Journalpublikation prüfen, keine Datensicherung über neuere Antworten/Löschungen
zurückspielen. Die Löschverbesserungen entfallen auf dem alten Clientstand.

## Produktive Abnahme

Release `20261020T132931Z-091b791`, Quelle `091b791130abc898585aec0fbedf9d84284251cb`.
Vorherige Konfiguration und Datenbank gesichert; Sicherung erfolgreich. Lokale
Vorschau mit `--include-manual-assignments` zeigte genau vier alte quellenlose
Testaufträge und null verwaiste Runden/Antworten. Anwendung an den exakten Digest
gebunden, vier Aufträge entfernt, Audit gespeichert, Journal vollständig
publiziert (null unveröffentlichte Auftragslöschungen). Erneute Auswahl: null
quellenlose Runden und null unverbundene Aufträge. Keine Erweiterung auf reine
manuelle Wortrunden, keine anderen Haushalte bereinigt.

Zehn Heftseiten und sechs gültige Lernrunden erhalten. Keine Produktivantwort
eingetragen oder gelöscht; kein Provideraufruf für diese Prüfung. Live-Plan zeigt
keine alten Testaufträge mehr; neue Übersichts-/Planfassung geprüft. Die
Seitenkaskade selbst wurde mit künstlichen Daten in isolierten Tests geprüft,
keine echten Fotos zum Nachweis gelöscht. Öffentliche Version und Artefakte
stehen in STATUS.md.
