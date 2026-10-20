# Erneute Menü- und Bedienprüfung · 20.10.2026

Ausbau auf Betreiberauftrag: alle Hauptmenüs und Unteransichten erneut prüfen,
Bedienung grundsätzlich hinterfragen und belegte Verbesserungen umsetzen.
Zielversion **1.13.0+59**. Die Hauptnavigation bleibt rollenbezogen und die
Lernrunde behält ihre klare nächste Hauptaktion. Normale Handschrift bleibt
Eingabe; keine weiteren gedruckten Heftbilder und keine Bild-KI für Appinhalte.

## Befunde und Umsetzung

| Bereich | Änderung und Zweck |
| --- | --- |
| Heute/Aufgabenraum | Vorhandenen Fortsetzen-/Fotoeinstieg geprüft. Begonnene Runde für die Prüfung pausiert; keine Antworten eingetragen oder überschrieben. |
| Lernen | Doppelte Statusangabe „Geplant · Geplant“ entfällt; echte Aufgaben-/Versuchszahlen bleiben unverändert. |
| Hefte | Kinder sehen ohne gespeicherte Präferenz zunächst Fächer mit vorhandenen Seiten. Der vollständige Katalog bleibt über den bestehenden Filter erreichbar; unzugeordnete Seiten bleiben sichtbar. Bewusst gespeicherte Ansicht hat Vorrang. |
| Wörter | Ladezustand und explizite Wiederholung eines fehlgeschlagenen GETs. Beim Filterwechsel keine alten Wortkarten unter der neuen Sprache/Sammlung/Suche. Leere Suchtreffer unterscheiden sich von fehlenden Schulwörtern; Filter der gewählten Sprache direkt zurücksetzen. Suchlänge an die bestehende API-Grenze gebunden, Rand-Leerzeichen entfernt. |
| Nachrichten | Direkter berechtigter Reader unter `/messages/<child_id>`, auch aus einer Glockenmeldung. Zuerst die Nachricht lesen, den Lernstoff danach ausdrücklich öffnen. Lesende Eltern erhalten keine Schreibaktion, Betriebsadmins keinen privaten Reader. Kontowechsel verwirft die Ansicht. |
| Verknüpfungen | Gelöschte oder fremde Lernstoffverweise werden beim Lesen ausgeblendet. Nachricht und ursprünglicher Kontext bleiben in der Datenbank/Export erhalten. Bis zu 100 Nachrichten stabil nach Datum/ID, Verweise und Absender gebündelt laden. |
| Glocke | Laden und leere Liste unterscheiden. Keine offene Vorbereitung zu inzwischen null Heftseiten und keine neue Prüfaufforderung zu bereits bestätigten Wortimporten. GET löscht keine Nachrichten/Lesebelege und startet keine KI. |
| Konto | Klarer Kindertitel und Geräteaktionen „Hier abmelden“/„Gerät abmelden“. Aktionen unter der Beschreibung lassen lange Gerätenamen und große Schrift zu. Rechte/Sitzungswiderruf unverändert. |
| Formeln/Tabellen | Echter Layoutfehler gefunden: intrinsische Spaltenmessung ist mit bestimmten Formelwidgets unvereinbar. Begrenzte responsive feste Spalten erlauben Formeln in Tabellen, große Schrift und horizontales Lesen. Trennzeichen innerhalb von TeX/Normen/Beträgen und maskierte Pipes bleiben Zellinhalt. |
| Erklärungen | Überschriften, Tabellen und eingerückten Code auch ohne Leerzeile trennen. Mehrzeilige Matrizen zusammenhalten. Eine neue Erklärung beginnt bei Schritt eins; eine Überschrift bleibt bei ihrem ersten inhaltlichen Schritt. Kurze TeX-Brüche und Norm-/Betragszeichen für das Vorlesen bereinigen. Nach langem Scrollen bei einem Schrittwechsel wieder den Anfang zeigen. |

Neue Clients melden `messages-v1`; ältere Clients behalten ihre bisherigen
Benachrichtigungsrouten. Das Headerfeld erteilt keine Rechte. Der Reader nutzt die
bestehende backendautorisierte kompakte Übersicht ohne ursprüngliche Aufgaben-
antworten. Keine Migration, Anbieteränderung, zusätzlichen Dienste oder höheren
Kosten-/Daten-/Zugangsgrenzen.

## Prüfung

Im angemeldeten Kinderzugang die Hauptmenüs Heute, Lernen, Wörter, Hefte, Konto,
Benachrichtigungen sowie Lernstand angesehen. Das ist keine vollständige Live-
Abnahme aller Betreiber-/Elternaktionen. Rollen, Familienrechte und große Schrift
werden zusätzlich mit künstlichen lokalen Fixtures geprüft; keine echten
Kinderinhalte an Anbieter und keine neuen Antwortbelege zum Testen.

Zwischenstand: vollständige Flutter-Suite mit 885 bestandenen Tests. Nach den
letzten Text-/Erklärungskorrekturen 174 gezielte Aufgabenraum-/Formel-/Menüprüfungen
bestanden, Analyse und Ruff sauber. 81 PostgreSQL-Prüfungen für Lernen, Konten,
Löschungen, Mindestzeiten und Benachrichtigungen bestanden; anschließend 19
gezielte Nachprüfungen für die letzten Lesepfade. Mengen überschneiden sich.
Endgültige Release-/Abnahmezahlen werden nach der Bereitstellung ergänzt.

Lokale Sichtprüfung im echten Web-Runner mit künstlichen Mockantworten: Tabelle
mit Beträgen/Normen/Brüchen und mehrzeilige Matrix im regulären Aufgabenraum-
Erklärungsdialog lesbar. Die Appfläche ist ausdrücklich auf 390 logische Pixel
begrenzt; der tatsächliche Browser ist breiter. Keine physische Smartphone-,
TalkBack- oder vollständige WCAG-Abnahme und kein Nachweis neuer KI-Aufgaben.
Die partielle Formelvorlesehilfe ersetzt keine vollständige mathematische Sprache.

Keine eigenen neuen Inferenzaufträge für diese Menüprüfung. Bisherige gemeldete
Kosten und unbekannte Reservierungen bleiben erhalten. Das Öffnen der zuvor vom
Nutzer begonnenen Runde hatte noch Aktivitätszeit erfasst; sie wurde pausiert,
diese Zeit nicht rückwirkend umgeschrieben. Keine Prüfung dieser Einheit durch
Testantworten.

## Bereitstellung

Web, signierte Direct-APK und Play-AAB werden aus derselben Produktrevision gebaut.
Tatsächlicher Healthcheck, APK-Hash, Dienste, Sicherungsstand und kompatibler
Rückweg werden nach dem Deployment hier und in STATUS/Handoff dokumentiert.
Privates Bildmaterial und Browserbelege verbleiben außerhalb von Git.

Nachprüfung im Web bei 200 %: Ein langer Erklärungsschritt hatte seinen alten
Scrollversatz auf den nächsten übertragen. Der neue Regressionstest scheitert
vor dem Fix und prüft danach einen sichtbaren Schrittanfang. Dieser letzte
Darstellungsfix wird vor der ersten Bereitstellung von Version 59 eingebaut.
