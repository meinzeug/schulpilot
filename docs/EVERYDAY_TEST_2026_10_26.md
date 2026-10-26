# Alltagstest: vom Heftfoto zur gespeicherten Lernrunde

Stand: 26.10.2026. Dieser Test verwendet einen **eigenen regulären künstlichen Haushalt**, Klasse 6. Er ist keine Leistungsprüfung von Juna Fee. Die frühere 100-Runden-Serie bleibt auf Nutzerauftrag bei 29 abgeschlossenen Heft-Lernrunden beendet.

Vier eigens mit dem eingebauten Bildgenerator erzeugte und visuell geprüfte Fotos wurden im normalen Browser-Fotoassistenten ausgewählt, zugeschnitten und abgegeben. Handschrift, Schatten, unleserliche Randstellen, rote Korrekturen und ein absichtlich seitliches Arbeitsblatt gehören zum Test. Drei Fotos wurden nach den OCR-Fixes ausdrücklich erneut eingereicht; deshalb enthält die Testsammlung sieben gespeicherte Seiten. Die Seiten verteilen sich einschließlich Wiederholungen auf drei Fächer.

## Was tatsächlich geprüft wurde

| Ablauf | Beobachtung |
| --- | --- |
| Mathematikheft | Zähler/Nenner, unechte Brüche, gemischte Zahlen, Kürzen/Erweitern; unleserlicher Rand wird nicht als sicherer Lernstoff verwendet. |
| Seitliches Mathematikarbeitsblatt | Alle acht Textblöcke erhalten; 1 km = 1000 m, 27 t = 27000 kg, 3/7 sowie gestrichene 60 / ergänzte 40 separat nachvollzogen. |
| Deutschheft | Satzglieder, Originalbeispiele und Korrekturen. Falsche oder unklare Schülermarkierungen werden nicht zur sicheren Aufgabenbasis. |
| Englischblatt | Simple past, Verbformen und did+Grundform; Bildkorrektur und unleserliche Stelle bleiben unterscheidbar. |
| Abgabe | Auswahl ohne doppelten Dialog, großes Foto beim Zuschnitt und sichtbare Abgabe vor den Vorschauen tatsächlich bedient. |
| Hintergrund | Das Appdokument wurde während echter Verarbeitung auf about:blank geschlossen. Der Server arbeitete weiter. Öffnen erzeugte keinen weiteren KI-Auftrag. |
| Lernpaket | Mathematik und Deutsch wurden in getrennten Aufrufen erstellt. Der erfolgreiche Mathematik-Teil ließ sich ausdrücklich und ohne neue KI freigeben, während Deutsch noch offen war. |
| Benachrichtigungen | Neue In-App-Meldungen für Anschlussrunde und fertiges Paket erschienen, wurden beim Anzeigen gelesen und öffneten direkt die jeweils noch passende gespeicherte Runde. |
| Hilfe und Grafik | Bruchkreis/Balken und Nennerfokus tatsächlich bedient. Eine eingegebene Antwort überstand echtes Neuladen; die nach Hilfe richtige Antwort blieb unterstützt. |
| Bewertung | Selbstständig, unterstützt/erneut und unklar werden getrennt angezeigt. Eine absichtlich unvollständige Subjektantwort wurde zurückgewiesen; der weitere Hilfeweg wurde geprüft. |
| Responsive Darstellung | Quellenansicht bei 390 × 844, 768 × 1024 und 1440 × 900 px tatsächlich betrachtet und fotografiert. Die temporäre Viewportänderung wurde nach der Prüfung zurückgesetzt. |

Der abschließende Browserlauf ist beendet: **vier abgeschlossene Runden, acht geübte Aufgaben, neun Versuche**. Vier Aufgaben sind selbstständig gelöst, drei unterstützt/erneut und eine bleibt unklar. Die beiden Deutsch-Erklärgrafiken erscheinen nach dem Fix bei bewusstem Abruf. Der falsche Erstversuch „Hund“ und der später unterstützte richtige Versuch „Der Hund“ bleiben getrennt gespeichert. „spielt“ bleibt selbstständig richtig, obwohl danach die Erklärung geöffnet wurde. Beim Wiederaufnehmen der pausierten Runde blieben Fehlerstand und 548 gespeicherte Lernsekunden unverändert; während des Deployments kam keine Lernzeit hinzu.

## Belegte Fehler und Änderungen

1. Schulbuddy las eine veraltete Kopie des globalen Systembudgets statt der aktuellen maßgeblichen Einstellung. Die Modellbindung verwendet wieder die zentrale Grenze. Kein Budget wurde dafür angehoben.
2. Ungültige Zusatzannotationen verwarfen vollständigen OCR-Text. Der Originalwortlaut bleibt jetzt erhalten; unzuverlässige Markierungen machen ihren Abschnitt ausdrücklich unsicher.
3. Gewöhnliche blaue Schrift war als unbekannte Sondermarkierung ausgeschlossen. Ein eigener endlicher ink-Typ unterscheidet normale Tinte von Korrekturen. Alte Unsicherheiten werden nicht blind umetikettiert.
4. Beim Zweitlesevergleich entfernten grobe Bildüberlappungen zuvor erhaltene Textblöcke. Geschützte Originalblöcke werden getrennt gesammelt; Koordinaten allein löschen keinen Abschnitt.
5. Gestrichene 60 und ergänzte 40 erschienen als 6040. Beschriftete Originalmarkierungs-Karten zeigen beide Rollen getrennt, ohne eine fachliche Richtigkeitsgarantie zu erfinden.
6. Der mobile Fotoassistent versteckte Foto und Abgabe hinter Werkzeugen bzw. Vorschauen. Foto und Hauptaktion stehen jetzt vorne; der redundante Auswahl-Dialog entfällt.
7. Eine geöffnete Quellenansicht behielt alten Verarbeitungsstatus. Stille Status-GETs aktualisieren den bestehenden Editor, ohne Route, Dokument oder eigenen Entwurf zu ersetzen.
8. Eine feste Bruch-Vorwissensfrage enthielt absichtlich nicht ihre Antwortn/d, kollidierte aber mit dem allgemeinen Grafikanker. Vollständiger Fragekern, Regelversion, Beispiel und Grafik werden jetzt direkt miteinander gebunden; Fragen und Antworten werden nicht umgeschrieben.
9. Für den untersuchten deutschen Satzgliederstoff fehlte ein vorbereiteter Originalsatz-Pfad. Der neue begrenzte Pfad stellt ausschließlich vollständige Originalwörter ohne erfundene Rollenmarkierungen bereit. Ein Wortkasten ist ausdrücklich kein automatisch bestimmtes Satzglied. Die genaue erste verworfene Modellantwort wurde nicht gespeichert; eine bestimmte einzelne fehlerhafte Markierung lässt sich daraus nicht nachträglich beweisen.
10. Beim ausdrücklichen Erklärabruf wurde eine vorhandene hint1-/hint2-Grafik wegen hints=0 ausgeblendet. Dieser Einzelaufgaben-Abruf öffnet jetzt alle gespeicherten Hinweisstufen derselben Aufgabe. Normale GETs, andere Aufgaben und Quellschutz bleiben unverändert.

## Messungen und Nachweise

- Erster Vierfoto-Durchlauf:257 Sekunden bis zum ersten Teilpaket; damals blieb eine Seite offen. Dies war kein vollständiger Vierseiten-Erfolg.
- Drei neue Fotoimporte nach den Lesefixes:170 Sekunden für sämtliche Erst- und Zweitlesungen.
- Mathematik-Teil nach Grafikbindungsfix:22 Sekunden.
- Erster Deutschversuch:49,205 Sekunden Anbieterzeit, danach verworfen;0,043432 USD gemeldet. Wiederholung mit Originalsatz-Pfad:40 Sekunden, erfolgreich.
- Gezielte mathematische Anschlussrunde:31 Sekunden, erfolgreich; In-App-Direkteinstieg geprüft.
- 26 reservierte Aufträge, davon ein belegter lokaler Abbruch vor Versand. 24 OpenRouter-Generierungsbelege ergeben **0,540366 USD**; weitere **0,40 USD** bleiben konservativ reserviert: 0,15 USD für die nicht in USD bezifferte Codex-Lesehilfe und 0,25 USD beim historischen lokalen Abbruch. Reservierung bedeutet keine nachgewiesene Abbuchung. Abschluss: acht Aufgaben, neun Versuche, vier abgeschlossene Runden, keine offene Runde.

Die Kostenwerte sind bekannte Anbieterbelege; unbekannte Kosten bleiben konservativ reserviert. Freigegeben waren 15 USD für diesen Alltagstest. Das eigene Testkonto ist zeitlich und auf 30 Aufrufe begrenzt. Es wurden keine Produktionsbudgets anderer Haushalte oder Sicherheitsfreigaben gelockert.

Backendregressionen wurden ohne externe KI und ohne übernommene Anbieterschlüssel ausgeführt:Version 145 mit 231 RAM-SQLitefällen und 55 Unix-PostgreSQLfällen, Version 146 mit 143 bzw. 30 Fällen, Version 147 mit 79 bzw. 66 Fällen. Diese Gruppen überlappen und werden nicht als eindeutige Gesamtsumme addiert. Die API-Fälle der Version 147 prüfen alle vier Grafikstufen, unveränderte Fragen, verborgene andere Aufgaben, unveränderte Usage/Attempts beim Lesen, Hilfe bei der nächsten Antwort und den Quellrevisionsschutz. Temporäre Datenbanken wurden entfernt, Quellmanifeste blieben während der Läufe unverändert.

Release 144 enthält die lokalen Flutterprüfungen für Zuschnitt, Abgabe, Markierungskarten und stillen Quellenstatus einschließlich Entwurferhalt. Die vollständigen Produkt-CIs 145 und 146 bestanden. Die vollständige [Produkt-CI 147 für Commit 670f1b0](https://github.com/meinzeug/schulpilot/actions/runs/40399816000) ist ebenfalls erfolgreich.

Private Testzugänge, Originalfotos, genaue Bildprompts, Hashes, erwartete Lesefakten, Messbelege und echte Browser-Screenshots liegen außerhalb von Git unter artifacts/elements143/everyday. Die fachlichen Bilder wurden selbst erzeugt; Simpleclub-Bilder wurden nicht kopiert. Produktionsquellen und Auslieferungsbelege stehen in [SOURCES.md](SOURCES.md).

## Grenzen

Es war kein eigenes Android-Testgerät verbunden. Eine sichtbare Firebase-Hintergrundzustellung, die Bildschirmtastatur oder das Verhalten auf echter Androidhardware sind durch diesen Browserlauf nicht abgenommen. In-App-Meldung, Gerätefreigabe, FCM-Annahme und native Anzeige bleiben getrennte Nachweise. Die Browser-Berechtigungsfreigabe war im verwendeten In-App-Browser nicht abschließbar. Das Abbruchverhalten wurde lokal geprüft; daraus wird keine sichtbare Pushzustellung abgeleitet.

Vier künstliche Fotos aus drei Fächern sind kein Vollständigkeitsnachweis für jedes Fach, jede Handschrift oder jeden Lehrplan. Unleserliche Inhalte werden weiterhin als unsicher behandelt. Das Öffnen von Fotos, Erklärungen, Medien oder Grafiken erzeugt keine Beherrschung. Dauerhafte Kompetenz braucht weiterhin getrennte, datierte Antwortbelege. Es wurde keine Notenverbesserung oder Fehlerfreiheit sämtlicher KI-Ausgaben zugesichert.

## Auslieferung und Belege

Produktversion **1.36.35+147**, Release `20261026T220259Z-670f1b0`, Produktcommit `670f1b09f5eea2056c2cf89bfbf456ec140ae8b3`, unverändertes Schema `0042`. Fünf Dienste aktiv, 17 unmittelbar gesicherte Betriebskonfigurationen erhalten. Web, signierte Direct-APK und Play-AAB wurden aus derselben sauberen Quelle gebaut. Die unveränderten Befehle des bestehenden Release-Skripts liefen in einzeln protokollierten Stufen, jede mit tatsächlichem Exitcode 0. Signaturen, Versionen, Geheimnisscan und öffentliche Web-/APK-Bytes wurden unabhängig abgeglichen. Direct-APK: 137.178.832 Bytes, SHA-256 `a8eaa6c0c0eb3ce670ba03dd3d6e24d2fe882a1f94f308285407e65211b8937d`.

Ausgewählte lokale Screenshots unter `artifacts/elements143/everyday/screenshots/`:

- `11-zuschnitt-gross-neu.png`, `12-abgabe-sichtbar.png`: tatsächlicher neuer Fotoassistent.
- `14-korrekturkarten-mobil.png`, `16-heftkorrektur-tablet.png`, `17-heftkorrektur-desktop.png`: getrennte Originalmarkierungen.
- `19-bruchgrafik-echte-runde.png`, `20-mathe-antwort-nach-neuladen.png`, `21-mathe-rueckblick.png`: Grafik, Entwurf und Ergebnis.
- `22-anschlussrunde-benachrichtigung.png`, `24-lernpacket-fertigmeldung.png`: echte In-App-Meldungen und direkte Ziele.
- `25-deutsch-erklaerung-vor-fix.png`, `26-deutsch-erklaerung-mit-grafik.png`, `27-deutsch-zweite-erklaergrafik.png`: gleicher gespeicherter Inhalt vor und nach der Korrektur.
- `28-deutsch-rueckblick-abgeschlossen.png`, `29-gesamtlernstand-mobil.png`: Abschluss und korrekte Gesamtsummen.

Die erzeugten Testfotos liegen in `artifacts/elements143/everyday/fixtures/`; genaue Prompts und Quellpfade sind im Testverzeichnis dokumentiert. Diese Bilder und private Testzugänge werden nicht ins Repository aufgenommen. Der Server bleibt für neue Arbeit auf der regulären Reservierungs-, Quellen- und Rechteprüfung. Rückweg ist die vorherige geprüfte Version146; keine Datenbankrücksetzung erforderlich.
