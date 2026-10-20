# Heftaktionen: gezielte Abnahme am 20.10.2026

## Befund und Ursache

Bestätigt im Ausgangscode von 1.10.0+49: Die vorhandenen Löschaktionen in
Album, Kacheln und Liste wurden im Kinderzugang bei `confirmed=true` verborgen.
Die bisherige Backend-DELETE-Route verweigerte bestätigte Kinderseiten ebenfalls
mit 403. Die Icons fehlten deshalb absichtlich durch die alte Rechtebedingung;
ein Cacheproblem ist dafür kein notwendiger Erklärungsansatz.

## Eigene Prüfdaten und wiederholbarer Ablauf

`qa/notebook_actions.mjs --prepare` verwendet ausschließlich die reguläre,
über den normalen E-Mail-Weg bestätigte Familie aus
`scripts/prepare_normal_ai_smoke.py`. Sechs künstliche JPEG-Seiten wurden am
20.10.2026 über den normalen authentifizierten Upload gespeichert. Kein
Datenbankeingriff, keine echten Kinderinhalte und kein Anbieteraufruf durch
diese Vorbereitung. Zugangsdaten bleiben im ignorierten geschützten Checkpoint
`artifacts/.school-day-qa-account.json`.

Nach Bereitstellung und gesonderter ausdrücklicher OCR-Prüfung der ersten
eigenen Mathematikseite führt
`node qa/notebook_actions.mjs --verify-final --build 50` die echte öffentliche
Flutter-Oberfläche aus. Der Treiber prüft sichtbare Aktionen, Abbrechen ohne
KI-Aufruf, einzelne Löschung, Zweierauswahl, Alle auswählen und gefiltertes
Alles löschen. Die zugeordneten Mathematikquellen müssen erhalten bleiben.
Kinder- und Elternzugang sowie 320/390/1440 Pixel werden berücksichtigt.

Die KI-Neuverarbeitung selbst wird in diesem Browserlauf bewusst abgebrochen.
Ein echter Neuverarbeitungsnachweis benötigt den getrennten, normal reservierten
Operator-Prüfablauf mit künstlichem Foto. Alte Antworten werden durch gezielte
Backendtests geprüft; die bloße Existenz von Icons ist dafür kein Nachweis.

## Status

- Vorbereitung: erfolgreich, sechs echte künstliche Foto-Uploads, null KI-Aufrufe.
  Wiederholung desselben Uploadschlüssels mit demselben Foto lieferte dieselbe
  Material-ID ohne doppelte Seite.
- Gemeinsame Flutter-Aktionshelfer: 18 gezielte Tests bestanden
  (`app/test/material_actions_test.dart`). Rechte, ausdrückliche Bestätigung,
  Idempotenzschlüssel bei Wiederaufnahme, reine GET-Statusabfragen,
  Hintergrund/Resume, fremd gebundene Aufträge, späte Antworten nach Abmeldung
  und 320 Pixel mit 200-%-Textskalierung sind isoliert geprüft. Mocktests
  beweisen keine echte OCR oder Providerverfügbarkeit.
- Öffentliche Bedienabnahme des neuen Codes: ausstehend, bis der neue Stand live ist.
- Physisches Androidgerät, Audio und Screenreader: mit diesem Treiber nicht geprüft.

Keine Aussagen über eine erfolgreiche Live-Löschung oder KI-Neuverarbeitung
vor dem tatsächlichen Durchlauf. Der eigene Haushalt wird nach der Abnahme über
die normale Konto-Löschung entfernt.
