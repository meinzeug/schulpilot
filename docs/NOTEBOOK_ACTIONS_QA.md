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

## Tatsächlicher Abschlussstand vor Bereitstellung

- 192 isolierte PostgreSQL-Tests bestanden, einschließlich31 neuer Heftaktionsfälle.
- Vier zusätzliche SQLite-Kompatibilitätsfälle bestanden.
- Vollständiger Flutterlauf:610 bestanden; Analyse ohne Befund. Darunter18
  Heftansichts- und18 gemeinsame Aktions-/Statusprüfungen sowie die erhaltenen
  Fotoassistenten-Regressionsfälle. Bekannte Starlette-Warnung bleibt.
- Sechs eigene künstliche Fotos normal hochgeladen; ein identischer Upload
  idempotent wiederholt. Genau ein normal reservierter Codex-OCR-Auftrag noch
  auf Version49 erfolgreich. Vorlage geprüft und bestätigt, keine Hausaufgaben
  oder Kinderantworten angelegt. Tatsächliche USD-Kosten unbekannt.
- Danach ausdrückliche Nutzersteuerung: **nur bauen und ausrollen; weitere
  Funktionstests übernimmt der Nutzer**. Deshalb weder Browser-Delete/Bulk noch
  echtes Reprocess50 oder native Heftaktionen50 ausgeführt. Die vorbereiteten
  Treiber sind kein Nachweis dieser Abläufe. Auch kein zusätzlicher Bundletool-
  oder Play-Console-Test von AAB50 nach dieser Steuerung.
- Eigene reguläre Testfamilie mit dem bestehenden normalen Cleanupweg gelöscht;
  privater Kontocheckpoint entfernt. Eigene Emulator-Appdaten bereinigt und den
  dedizierten Emulator beendet. Keine echte Familie verändert.

Die erforderliche Build-/Signierer-/Versionsprüfung und der Healthcheck des
bestehenden Deployments bleiben Teil des Ausrollens. Release1.11.0+50 ist als20261020T053724Z-82a6078 bereitgestellt; der öffentliche
Deployment-Healthcheck meldet status=ok. APK und Rückweg stehen in STATUS.md
und CHATGPT_HANDOFF.txt. Das ist keine zusätzliche Funktionsabnahme.

## Manueller Nachtest für den Nutzer

1. Im Kinderzugang Hefte öffnen, einen vorhandenen Hefter wählen. Über dem Foto
   stehen Papierkorb und „Mit KI neu lesen“; dieselben Aktionen in Kacheln/Liste.
2. In der Liste Seiten auswählen oder Alle auswählen. Die genaue Auswahl im
   Löschdialog prüfen; zuerst Abbrechen ausprobieren. Alles löschen bezieht sich
   auf den aktuellen Hefter/Filter einschließlich weiterer Listenseiten.
3. Bei einer geeigneten eigenen Seite „Mit KI neu lesen“ bestätigen. Nach der
   Statusseite „Seite prüfen“, den Text bestätigen und anschließend bewusst
   die neue Lernrunde anfordern. Die bisherige Quelle/Antworten bleiben erhalten.
4. Dasselbe nach Installation der neuen regulären APK prüfen. Reine Lese-Eltern
   und Betriebsadministratoren dürfen weiterhin keine privaten Seiten verwalten.

Automatisierte Treiber für eine spätere eigene künstliche Abnahme bleiben im
Repository: qa/notebook_actions.mjs, qa/notebook_reprocess_smoke.mjs und
qa/android_notebook_actions.py. Für erneute Ausführung zuerst eine neue eigene
normale Testfamilie mit scripts/prepare_normal_ai_smoke.py anlegen; alte private
Zugänge wurden entfernt. Kein physischer Geräte-/Audio-/Screenreader-Nachweis.
