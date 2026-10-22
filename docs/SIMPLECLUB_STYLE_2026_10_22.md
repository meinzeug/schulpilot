# Schulpilot: gemeinsame Lernoberfläche

Auftrag vom 22.10.2026: Die angemeldete simpleclub-Weboberfläche als visuelle
Referenz verwenden und die bestehende App in `~/schulpilot` weiterentwickeln.
Direkt angesehen wurden Entdecken, Mathematik, Home, Bibliothek und eine
Lektionsansicht unter https://app.simpleclub.com/search. Die Referenz wurde
über den vom Nutzer geöffneten Browser bedient.

## Gestaltung

Die eigene Schulpilot-Marke und die vorhandenen Rollen bleiben Ausgangspunkt.
Die gemeinsame Flutter-Palette verwendet im dunklen Modus eine anthrazitfarbene
Arbeitsfläche (#101E24), ruhig abgesetzte Karten (#202C34), helle Schrift und
blaue Hauptaktionen (#0866E9). Die lokale Nunito-Schrift, runde Schaltflächen,
flache Karten und eine kompakte Browsernavigation verbinden die Ansichten.
Der helle Modus bleibt als eigenständige lesbare Variante verfügbar.

Die Kinderstartseite betont den tatsächlichen nächsten Lernschritt. Abschnitts-
köpfe und Reiter folgen derselben ruhigeren Gestaltung. Öffentliche Fachschlüssel
erhalten lokale farbige Sechseck-Symbole in der Hefterliste; die vorhandenen
Hefterbilder und die Fotoansichten bleiben verfügbar.

## Umfang

Geändert wird die Darstellung der bestehenden Flutter-App, einschließlich
geteilter Kinder-, Eltern-, Verwaltungs- und Zugangsbausteine. Es kommen keine
neuen Dienste, Pakete, Schriftabfragen oder Inhaltsanbieter hinzu. Rollen,
Backendaufrufe, Quellenbestätigung, Antworten, Lernzeit, Formulare, Filter und
bewusste KI-Aktionen verwenden die vorhandene Implementierung. Lerntexte und
Medien der Referenz werden nicht als neuer Schulpilot-Lehrstoff eingebaut.

## Prüfung

Die konkreten Testergebnisse und verbleibenden Grenzen stehen in STATUS.md.
Eine lokale Browservorschau mit ausschließlich künstlichen Daten dient der
Sicht- und Navigationsprüfung. Sie kann keine KI-Anfrage, Zahlung oder andere
schreibende Anfrage ausführen und ist kein neuer öffentlicher App-Modus.
Die Änderung wird lokal gebaut; eine Veröffentlichung auf dem Produktionsserver
ist in diesem Auftrag nicht enthalten.
