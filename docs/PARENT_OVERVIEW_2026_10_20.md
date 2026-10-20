# Elternübersicht · 20.10.2026

Betreiberauftrag: Lernüberblick eines vorhandenen Kindes im angemeldeten
Elternzugang neu ordnen, Lernstand verständlich zeigen und Menüs/Unterseiten
aufräumen. Bereitgestellt **1.14.2+62**; produktive Abnahme siehe Abschluss unten.
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

## Live-Nachprüfung der ersten Bereitstellung

1.14.0+60 / `20261020T124231Z-8bbd152`, Quelle
`8bbd152080c854d66946e9f74d82788ecd13e7d8`, wurde technisch erfolgreich geprüft.
Alle acht Elternbereiche und der Fach-/Themen-/Rundenrückweg im Browser erreichbar.
897 Fluttertests vollständig bestanden. Public-APK-Bytes/Hash stimmen, Sicherung
und Dienste gesund. Keine neue Antwort, Nachricht oder Lernplanung eingetragen.

Die vorhandenen freiwilligen Aufträge zeigten eine sprachliche Unklarheit in der
Übersicht: Die Zahl offener Aufträge war schon vorher nur auf Pflichtaufträge
bezogen. 1.14.1 benennt das ausdrücklich und zeigt freiwillige Aufträge getrennt.
Rundensummen sind ausdrücklich Runden mit gespeicherten Antworten; eine noch
unbeantwortete vorbereitete/pausierte Runde wird damit nicht als geübt ausgegeben.
Ein zusätzlicher GET-only-Regressionsfall sichert die Trennung. Der leere
Tagesplan benennt vor dem offenen Mindestziel Weiterlernen als nächsten Schritt;
er verwendet dort nicht den Begriff freiwillig.

## Abschließende Bereitstellung

1.14.2+62 / `20261020T132931Z-091b791`, Produktquelle `091b791130abc898585aec0fbedf9d84284251cb`,
main gepusht. 898 Fluttertests vollständig bestanden; nach letzter rein
sprachlicher Plan-Korrektur 22 passende Elternprüfungen erneut erfolgreich.
Flutteranalyse und Ruff ohne Befund. 130 PostgreSQL-Prüfungen zur Quellenlöschung
zusätzlich zur oben dokumentierten Elternabnahme bestanden.

Vollständiger Web-/Direct-APK-/Play-AAB-Build Status 0. Ein vorheriger Zwischenlauf
endete mit 143 und wurde nicht bereitgestellt. Finaler Stand vollständig neu
gebaut. Androidversion, Signierer, ZIP-Ausrichtung und AAB mit Bundletool geprüft;
Play ohne APK-Installerberechtigung. Keine Play-Veröffentlichung. Bekannter
Provider-Schlüssel in 451 Quelldateien, 334 Android-Archiveinträgen und
93 Webdateien nicht gefunden.

Live: Health status=ok/1.14.2, API/Worker/Caddy aktiv, aktuelle Sicherung
erfolgreich. Öffentlicher APK-Download mit Manifest/Build identisch. Alle acht
Bereiche und Fach-/Themen-/Rundenrückweg auf der ersten Bereitstellung geprüft;
finale Übersicht/Plan erneut bei 390 px und Desktop 1101 px angesehen. Neue
Rundenbezeichnung, Pflichtauftragstext und Mindestziel-Weiterlernen live sichtbar.
Vier alte quellenlose Testaufträge auf ausdrücklichen Zusatzauftrag bereinigt,
keine Heftseite, Lernrunde oder Antwort dabei entfernt. Journal publiziert und
Bestand anschließend ohne weitere verwaiste Aufgaben. Keine neuen Antworten,
Nachrichten, Noten oder KI-Aufträge für die Abnahme eingetragen.

Private Screenshots ausschließlich als ignorierte lokale Ergebnisartefakte.
Keine neue physische Android-/TalkBack-/WCAG-Zertifizierung.

Rückweg: 1.14.0+60 (`20261020T124231Z-8bbd152`), Schema 0023. Vor Code-Rollback
neue KI-Aufträge anhalten/aktive abarbeiten, Journalpublikation prüfen.
Wiederherstellungen benötigen mindestens 1.14.2; Details in
SOURCE_DELETION_2026_10_20.md. Keine Rücksicherung über neuere Antworten/Löschungen.
