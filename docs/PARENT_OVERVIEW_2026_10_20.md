# Elternübersicht · 20.10.2026

Betreiberauftrag: Lernüberblick eines vorhandenen Kindes im angemeldeten
Elternzugang neu ordnen, Lernstand verständlich zeigen und Menüs/Unterseiten
aufräumen. Zielversion **1.14.0+60**; produktive Abnahme siehe Abschluss unten.
Keine privaten Namen, Kennungen, Fotos, Antworten oder Screenshots im Repository.

## Darstellung und Navigation

- Fachliche Übungsergebnisse zuerst: alle gespeicherten beantworteten Aufgaben,
  Versuche und geübten Runden; abgeschlossene und noch offene geübte Runden
  getrennt. Aufgaben im ersten Versuch allein richtig, mit Hilfe/erneut richtig,
  weiter üben, offene Bewertung und gegebenenfalls eigene Beiträge bleiben
  getrennt. Nullwerte sichtbar, keine erfundenen Wissensprozente.
- Gespeicherte Tages-/Wochensekunden und serverseitige Mindestziel-Erfüllung
  unverändert daneben beziehungsweise darunter. Keine geplante Zeit als gelernt
  ausgeben. Letzte Übungsaktivität nur aus dem gespeicherten Zeitstempel.
- Hilfewünsche des heutigen Tages nicht automatisch als unbeantwortet ausgeben.
  Gespeicherter Unterstützungsbedarf der Lernbegleitung bleibt als Rückmeldung
  erkennbar. Aufträge und aktuelle gespeicherte Runde direkt erreichbar.
- Fächervorschau ausdrücklich begrenzt; Gesamtsummen bleiben vollständig. Ein
  Fach führt direkt zu seinen Themen. Fach-/Themenansichten erhalten eigene
  URL-Parameter, Rückweg und Kontobindung der Filter.
- Die gemeinsame Kindnavigation verbindet Überblick, Lernstand, Plan/Termine,
  Hefte, Wörter, Noten, Verlauf und Nachrichten. Auf breiten Flächen geordnete
  Reihen, auf kleinen Flächen/großer Schrift eine beschriftete Bereichsauswahl.
  Bibliothek, Fotoalbum, Tagespakete und Elternansicht einer Runde haben ebenfalls
  den Rückweg. Kinder behalten ihren eigenen Aufgabenraum.
- Tagesplanung, Hinweise und Einstellungen stehen im Plan. Erledigte Eltern-
  aufträge erst auf Wunsch zeigen; die gespeicherten Antworten bleiben erhalten.
  Wiederholungsbelege, heutige Heftvorbereitung und ausführliche Festigung lassen
  sich im Überblick gezielt aufklappen.
- Noten und tatsächliche Einträge vor die Planungseinstellungen gestellt. Beim
  Filterwechsel alte Noten ausblenden; ein Fehler zeigt keine alten Ergebnisse
  unter dem neuen Fach. PDF-Import/Notenpflege bleiben eigene ausdrückliche
  Elternaktionen. Rollen-/Familienrechte und Revisionsregeln erhalten.
- Schmale Wochenpläne/große Schrift zeigen die geschätzte Rundendauer unter dem
  Fachtext. Keine zusammengedrückte Datums-/Fachspalte durch eine breite Zeitangabe.

## Daten und Aufwand

Vorhandene backendautorisierte kompakte Projektionen und paginierte Listen.
Keine neuen KI-Aufträge, Modelle, Dienste, Paketabhängigkeiten oder Migrationen.
Keine Lernzeit-/Antwort-/Notenänderung durch Betrachtung und Navigation.
Kontowechsel blendet auch den geladenen Elternüberblick unmittelbar aus.
Anbieterrevision, Kontingente, Grenzen und Schlüsselablage bleiben erhalten.

## Prüfung

- Künstliche Widgetdaten bei 320/390/1280–1440 px, einschließlich doppelter
  Schrift. Tages-/Wochenminimum, alle Ergebniskategorien, laufende/abgeschlossene
  Runden, spätere Festigung, Plan-Rückwege und erledigte Aufträge geprüft.
- Rollen und Leserechte: keine Änderungen/Generierung beim Betrachten; keine
  Verwaltungsaktionen für lesende Mitglieder, Konto-/Routen-/Hintergrundwechsel
  und überholte Antworten geprüft. Notenfilter einschließlich Ladefehler geprüft.
- 69 PostgreSQL-Prüfungen für Lernstand, Noten, Sammlungen und Mindestlernzeit
  erfolgreich in separater lokaler Datenbank. Kein Produktions-DB-Testlauf.
- Erster Gesamtlauf: 895 bestanden, ein Testfinder musste wegen der zusätzlichen
  Bereichsauswahl auf die eigentliche Lernliste begrenzt werden. Kein fachlicher
  Funktionsfehler. Gezielte Nachprüfung: 74 bestanden. Ein weiterer Gesamtlauf mit 896 Tests bestand vollständig. Eine gezielte
  Nachprüfung mit 14 Tests sichert zusätzlich den Rückweg eines gespeicherten
  Fachfilters ohne URL-Parameter. Analyse ohne Befund. Abschließende
  Releaseabnahme wird unten ergänzt.

Das ist keine vollständige Screenreader-/WCAG-Zertifizierung oder Messung eines
Lernerfolgs. Browseransichten dienen der Bedien-/Darstellungsabnahme. Eingescannte
handschriftliche Heftseiten und bisherige Lernergebnisse bleiben erhalten.

## Bereitstellung

Noch nicht abgeschlossen. Vor Aktivierung vollständige Tests, Analyse,
Diff-/Geheimnisprüfung und Web/Direct-APK/Play-AAB bauen. Deployment sichert die
betroffenen Konfigurationen und Datenbank. Rückweg ist das bisherige Release
1.13.0+59 (`20261020T115520Z-0720f90`), Schema 0023.
