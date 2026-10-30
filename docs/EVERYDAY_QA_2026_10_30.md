# Fortsetzung des künstlichen Alltagstests – 30. Oktober 2026

Der Test bleibt isoliert: künstliches Eltern-/Kinderkonto, eigene künstliche
Fotos, SQLite und eine ausschließlich im Testprozess fortgeschriebene Uhr.
Produktivzeit und echte Kinderantworten werden dafür nicht verändert. Die
Smartphoneprüfung erfolgt mit 390×844 Pixeln im tatsächlichen Browser.

## Wiederaufnahme offener Verarbeitung

Bei älteren Testtagen enthielt der gespeicherte Vorbereitungsstatus noch eine
Auftragskennung, deren Datensatz bereits durch die 30-Tage-Wartung gelöscht
worden war. Das erklärt den fehlenden Auftragsbeleg, nicht die ursprünglichen
Anbieter- oder Grafikfehler. Seiten und Fehlversuchszähler waren weiterhin da.

`preparation_retention.py` erhält nun für einen weiterhin offenen eigenen
Schultag den aktuellen Auftragsbeleg sowie Paketbelege derselben Planrevision.
Die zugehörigen noch benötigten Verbrauchsbelege bleiben ebenfalls verfügbar.
Die regulären 30/90-Tage-Fristen gelten für andere abgeschlossene Vorgänge;
die bestehende Obergrenze von 365 Tagen bleibt auch für geschützte Belege
verbindlich. Fachfremde Pläne und andere Kinder erhalten diesen Schutz nicht.
Diese Aufbewahrung erlaubt keinen neuen Anbieteraufruf und setzt keine
Fehlversuchszähler zurück. Quellenlöschung und Familienlöschung bleiben erhalten.

Fehlt bei einer laufenden Vorbereitung bereits der Auftragsdatensatz, zeigt
der reine Statusabruf eine Unterbrechung. Der Worker hält denselben Status fest,
statt einen unbekannten früheren Anbieteraufruf automatisch erneut zu senden.
GET bleibt schreibfrei. Bereits gelöschte Belege werden nicht erfunden.

Eine nachträglich ausdrücklich erkannte und bestätigte Abschrift wird auch vor
dem ersten Paketplan als neue Quellrevision angezeigt. Der alte Erkennungsfehler
bleibt erhalten, die aktuelle Quelle kann bewusst neu vorbereitet werden.

## Tatsächlicher Browserdurchlauf

Der künstliche Deutsch-Testtag vom 12.11. war nach zwei Verbindungsfehlern ohne
Abschrift geblieben. Über die vorhandene Materialansicht wurde das gespeicherte
Foto ausdrücklich erneut gelesen, vollständig angesehen und bestätigt. Es
entstand keine ersatzweise erfundene Abschrift und keine zweite Fotoquelle.
Anschließend wurde der alte Schultag über seine normale Oberfläche neu
vorbereitet. Ein Lernweg mit zwei Aufgaben zu Subjekt und Prädikat wurde bereit.

Die echte OCR meldete laut Generierungsbeleg 11.403ms und 0,000853USD; die
Paketantwort 24.558ms und 0,002462USD, jeweils Abschlussgrund `stop` und
`verified_generation`. Die Zeiten sind Anbieterzeiten einzelner Aufrufe,
keine allgemeine Laufzeitzusage. Die frühere Fehlergeschichte bleibt erhalten.

Die Aufgabe zum Subjekt akzeptierte die konkrete Wortgruppe „Der Hund“. Die
absichtliche Antwort „im Park“ auf die Prädikatfrage wurde abgewiesen. Geöffnete
Erklärung und Hinweis wurden als Unterstützung geführt. Der Hinweis führte zur
Frage „Was geschieht im Satz?“ statt sofort die Lösung zu verraten.
Die Runde wurde danach vollständig abgeschlossen: zwei unterstützte/erneute
richtige Lösungen, zwei erhaltene falsche Versuche und ein Angebot zum gezielten
Weiterüben. Der offene Zeit-Mindestwert verhinderte den Ergebniszugang nicht.

## Mobile Bedienung

- In den Aufgaben-Karten eines abgeschlossenen Rückblicks öffnet „Erklärung
  mit Grafik“ die gespeicherte Lösung genau dieser Aufgabe. Der bestehende
  sitzungs-, quellen- und kindgebundene Freigabeweg wird weiterverwendet.
  Bloßes Aufklappen lädt keine Erklärung; frühere Antworten, Hilfen und Lernzeit
  werden beim Lesen eines abgeschlossenen Ergebnisses nicht geändert.
- Die zusätzliche Coach-Prosa heißt „Mehr zur Rückmeldung“ und ist dadurch von
  der fachlichen Erklärung unterscheidbar.
- Eine Satzgrafik stellt die unveränderten Wörter in Leserichtung als kompakte
  umbrochene Gruppe dar. Die bisherige hohe nummerierte Liste und die doppelte
  Punktliste entfallen. Ausschließlich bereits freigegebene Markierungen werden
  beschriftet; Grammatikrollen werden nicht im Client erraten.
- Der Hinweis auf Zifferntasten erscheint ab 720px. Die Tastaturbedienung bleibt
  erhalten; schmale Touchansichten verlieren diese unnötigen Textzeilen.

Die direkte Dezimalgrafik wurde bei 390px geöffnet und schrittweise bedient;
lokaler Screenshot: `artifacts/monthly-qa-20261030/75-rueckblick-direkte-grafik-390.png`.
Weitere nach dem endgültigen Build geprüfte Ansichten werden im lokalen
Testverzeichnis festgehalten. Bilder werden nicht als private Uploads ins Git
übernommen.
`76-deutsch-november-repariert-390.png` zeigt den tatsächlichen Abschluss und
die Unterscheidung zwischen bearbeitet und selbstständig gelöst.
`77-satzgrafik-kompakt-390.png` zeigt die anschließend tatsächlich geöffnete
kompakte Wortdarstellung im vollständigen Erklärdialog.

## Gefundener Fehler in der Anschlussrunde

Der erste ausdrücklich angeforderte Deutsch-Folgeauftrag wurde trotz vollständiger
Modellantwort verworfen. Die Quelle nennt „Subjekt: Der Hund“, die Grafik markierte
aber „Der“ und „Hund“ in getrennten Wortkästen. Die bisherige Rollenprüfung suchte
für jedes Einzelwort einen eigenen Rollenbeleg und verwarf dadurch „Hund“.
Ein kurzer Präfix wie „Der“ wurde dagegen zu großzügig akzeptiert.

`sentence_role_evidence.py` prüft nun die vollständige zusammenhängende markierte
Wortgruppe gegen eine ausdrücklich belegte Rollenangabe. Die Wörter und die
Modellantwort werden dabei nicht verändert. Einzelne Teilwörter, widersprüchliche
Rollen und verneinte Angaben reichen nicht aus. Die bisherige Sperre von
Rollenmarkierungen in ungesehener Einführung bleibt erhalten.

Die vollständige tatsächliche künstliche Fehlantwort bestand nach diesem Fix
eine rein lesende Gegenprüfung. Danach wurde der vorhandene reguläre einmalige
Wiederholungsbutton im Browser verwendet. Der echte Folgeauftrag gelang in
27.217ms mit zwei Aufgaben und den unveränderten Zielkennungen g1/g2; die Grafik
enthält die belegten Wortgruppen und passenden Rollen. Gemeldete Auftragskosten
0,044196USD. Der alte Fehlversuch und sein Verbrauch wurden nicht überschrieben.

171 Prüfungen für Rollenbelege, Fachgrafiken und Referenzen bestanden. Die
Gesamt-CI des Zwischenstands202 wies außerdem fünf vorhandene Importformatierungen
und veraltete UI-Erwartungen aus; die Backendtests wurden dort wegen der
Formatprüfung noch nicht gestartet. Diese Formatierungen wurden korrigiert,
die UI-Erwartungen an die bereits vorhandene Unterscheidung selbstständiger
und unterstützter Runden angepasst. Alle53 betroffenen Flutterfälle bestanden.
Die kanonischen24 Fachprofile werden einschließlich ihrer ausdrücklich bekannten
Aliase geprüft; Aliase verlangen keine zusätzlichen erfundenen Fachfixtures.
Der neue vollständige CI-Lauf wird getrennt von diesen lokalen Tests bewertet.

## Prüfungen und verbleibender Umfang

Regressionsprüfungen decken Auftrags-/Kostenbelege, alte offene Schultage,
unveränderte Fehlversuchszähler, schreibfreie Statusabrufe, fremde Kinder,
normale Ablauffristen und die 365-Tage-Grenze ab. Flutter prüft den direkten
Aufgabengrafikzugang einschließlich später Sitzungs-/Quellenwechsel und die
Wortdarstellung bei 320/390px mit einfacher und doppelter Schriftgröße.
Der endgültige Backendumfang bestand mit 69 erfolgreichen SQLite-Fällen und
einem PostgreSQL-spezifisch übersprungenen Fall; dieselben 70 Fälle bestanden
anschließend vollständig mit einem separaten PostgreSQL16 über einen privaten
Unix-Socket. 37 Flutterfälle für Rückblick/Grafiken sowie 19 Fälle für den
Aufgabenraum bestanden. Die statische Analyse meldete keine Probleme.

Ein bereits veralteter UI-Test erwartete bei einer selbstständig gelösten Runde
„Selbst ausprobieren“. Der bestehende Produktpfad nennt diese Aktion seit vor
dieser Änderung „Weitere Übung öffnen“; die Behauptung wurde entsprechend den
gespeicherten selbstständigen Antworten korrigiert.

Die vollständige 30-Tage-Abnahme ist weiterhin offen. Insbesondere die früheren
Geschichte-/Zahlengeraden-/Dezimal-Fehlversuche werden durch diesen erfolgreichen
Deutschpfad nicht nachträglich zu Erfolgen. Eine native Android-Zustellung wurde
nicht beobachtet; der Gerätetest ist auf Nutzerwunsch ausgenommen.

## Betrieb und Rückweg

Keine Datenbankmigration und keine Änderung von Modell, Anbieterroute,
Reservierung oder Wiederholungskontingent. Der Code-Rückweg ist der vorherige
kompatible Release 1.38.46. Dieser Rückweg enthält bereits den Leser für die
neue Dezimalgrafik; ältere inkompatible Leser nicht an dessen Stelle einsetzen.

## Weitere Befunde: Reihenfolge, Lesefokus und Unterstützungsnachweis

Der künstliche 04.11. hatte eine abgeschlossene Mathematikrunde, eine bereits
bereite Geschichtsrunde und weitere erst geplante Etappen. Der Tagesrückblick
wählte trotzdem die neu zu erzeugende Mathematiketappe zuerst. `study_path.py`
bevorzugt innerhalb dieses ausdrücklich geöffneten Tages nun eine vom bestehenden
Plan tatsächlich angebotene gespeicherte Runde. Elternpflichten und begonnene
Runden gehen weiter vor; Freigabetermine und fachliche Vorgänger werden nicht
übersprungen. GET verändert weder den Plan noch Antworten und startet keine KI.

Der normale erneute Vorbereitungsweg erstellte den noch fehlenden Geschichtsteil,
ohne die vorhandene Mathematikrunde oder deren Antworten zu ersetzen. Im Browser
wurde die echte gespeicherte Einführung geöffnet. Vollständige Originalsätze
stehen nun in kompakten Lesekarten; die beiden Schritte ändern die Hervorhebung,
nicht den Wortlaut oder eine erfundene zeitliche Reihenfolge. Screenshot:
`artifacts/monthly-qa-20261030/79-geschichte-lesekarten-390.png`.

Die bisherige Unabhängigkeitsprüfung behandelte jede früher geöffnete andere
Erklärung als möglichen Lösungshinweis, auch beim lokal berechneten neuen
Bruchbeispiel mit anderem Ergebnis. Neue endliche Rechen-Erklärschritte speichern
nun einen eng begrenzten Offenlegungsbeleg. Nur wenn jeder tatsächlich geöffnete
andere Schritt einen gültigen Beleg hat und der neue geprüfte Ergebniswert darin
nicht vorkommt, entfällt diese pauschale Unsicherheit. Beliebige Prosa, Grafiken,
Sprachaufgaben, Altbelege und zuvor gezeigte gleiche Ergebniswerte bleiben
konservativ. Hinweise zur aktuellen Aufgabe zählen weiterhin als Hilfe. Kein
bereits gespeicherter Versuch wird nachträglich verändert.

Öffentliche Fachaliase wie `Engl.` und `DaZ` erhalten die vorhandenen kanonischen
Darstellungs- und Laborverträge; neue öffentliche Cacheanfragen verwenden dieselbe
kanonische Identität. Private historische Fachbezeichnungen bleiben Snapshots.
Der Katalog führt die tatsächlich vorhandenen Herz- und Schattenrenderer nun
auch vollständig in seiner zentralen Artenliste.

Die vollständige CI des vorherigen Commitstands war nicht grün. Neben den
Unabhängigkeits- und Aliasfehlern enthielt sie veraltete Assertions für frühere
Transportfehlerphasen, ausschließlich voraussetzungsbezogene Altverträge sowie
Schema-Snapshots vor der zusätzlichen Referenzprüfung. Diese Assertions wurden
an den tatsächlichen weiterhin strengen Vertrag angepasst. Die reine künstliche
23-Seiten-Serializerfixture reserviert ausdrücklich 0,25 statt 0,15 USD; dies
ändert keine Anbieter- oder Kontoeinstellung. Ein separater übergroßer Request
muss weiterhin vor Versand und ohne Kosten abgewiesen werden. Die
Einheits-Sizingfixture berücksichtigt den durch weitere Grafikverträge größeren
Request; ihr Kostenlimit bleibt unverändert 0,25 USD.

Gezielte lokale Prüfungen: 416 Tests für Transport, Grafikschemata, Profile,
Referenzen, öffentliche Bausteine und Auswahlindizes; 33 für adaptive Abläufe,
Modellkurzpläne, Lernwissen und Lösungsoffenlegung; weitere 88 für
Offenlegungsgrenzen, Wortschatzschutz, Fachaliase und Tagesprioritäten bestanden.
Die neuen Lesekarten wurden zusätzlich mit realen Fonts bei 390px sowie 320px
und doppelter Textgröße im Widgettest geprüft. Dies ist keine abgeschlossene
30-Tage- oder Android-Geräteabnahme.

## Dezimalzahlen auf dem Zahlenstrahl

Der künstliche13.11. hatte zuerst eine vollständig beantwortete, aber wegen
fehlender wörtlicher Szenenbelege verworfene Anbieterantwort und danach einen
8.000-Token-Abbruch. Für die beiden tatsächlich fotografierten Aussagen fehlte
ein passender endlicher Grafikvertrag. Eine Bruch- oder Additionsgrafik ersetzt
diesen Inhalt nicht.

`package_prepared_midpoints.py` erkennt ausschließlich vollständige Aussagen
der Form „0,5 liegt genau zwischen0und1.“ mit Original-Leerzeichen, zwei
aufsteigenden ganzzahligen Rändern und einer rechnerisch exakten Dezimalmitte.
Verneinungen, ungefähre oder unlesbare Angaben und falsche Mittelpunkte werden
nicht in eine richtige Quelle umgeschrieben. Das neue unveränderliche Rezept
`math.decimal.number_line_midpoint@1` bindet eine vorhandene Szene mit drei
Originalzahlen. Flutter erhält erst nach exaktem Abgleich einen Darstellungsmarker
und berechnet den Zahlenstrahl lokal; der Anbieter liefert keine Koordinaten.
Die beiden bewussten Schritte heben die Mitte beziehungsweise beide Ränder
hervor. Keine automatische Animation oder Leistungsbewertung durch Erkunden.

Jede neue Frage ist bereits vor dem Aufruf an einen anderen belegten Satz,
seine Randzahlen und die private richtige Mitte gebunden. Bei zu wenigen
unterschiedlichen Beispielen oder inkompatiblen festen Vorwissensfragen wird
dieser spezielle Vertrag nicht verwendet. Alle bisherigen Schema-, Quellen-,
Offenlegungs-, Antworten- und Kostenprüfungen bleiben bestehen.

Nach belegtem Codefix wurde genau ein lokaler, auditierter und regulär
reservierter Reparaturauftrag im künstlichen Konto ausgeführt. Der alte
Auftragsdatensatz war vor dem Aufbewahrungsfix gelöscht; seine weiterhin aktuelle
Quellen-/Teilplanung wurde geprüft, beide Fehlversuchszähler erhalten und eine
aktuelle gültige Kindersitzung verwendet. Keine alte Sitzung reaktiviert,
keine echte Quelle oder Antwort verändert und kein öffentlicher Retry-Bypass.
Die echte Anbieterantwort lieferte zwei vollständige Aufgaben mit `stop`,
22.175ms gemeldeter Anbieterzeit und0,002125USD zunächst gemeldeten Kosten.
Der Lernweg wurde bereitgestellt und im390px-Browser geöffnet. Die erste
ununterstützte Antwort1,5 wurde richtig gewertet. Screenshot der tatsächlich
geöffneten Grafik: `82-zahlenstrahl-echte-ki-390.png` im lokalen Testverzeichnis.

Nach dem Vorwissenscheck stand zuvor schon das nächste Antwortfeld auf dem
Bildschirm, während der Hauptbutton zunächst die Erklärung öffnete. Dieser
Übergang zeigt jetzt eine eindeutige Verstehen-Karte. Die Eingabe folgt nach
der Erklärung; vorhandene Antwortbelege bleiben erhalten. Screenshot:
`81-klarer-erklaerungswechsel-390.png`.

Prüfungen:221 gezielte Backendfälle für die neue Bindung, alte vorbereitete
Grafiken, Referenzen und Paketausgabe sowie28 Flutterfälle für Zahlenstrahl,
Übergang und gespeicherte Aufgabenerklärungen bestanden. Die zuvor geprüften
26 Szenen-/Lesekartenfälle blieben erhalten; beide neuen Zahlenstrahlansichten
bestehen bei390px sowie320px mit doppelter Schrift und reduzierter Bewegung.

## Zahlenstrahl: Bewertung und gezieltes Nachlernen

Die absichtlich falsche Eingabe0,6 auf die Frage nach der Mitte zwischen0und1
blieb zunächst unklar. Der neue eng begrenzte Bewertungsweg prüft die exakte
Frage, den unveränderlichen Referenzvertrag und die Zahlenstrahldaten gemeinsam.
Dezimalpunkt/-komma und mathematisch gleichwertige einzelne Zahlen sind möglich;
eine falsche Zahl wird falsch bewertet, unbekannte Prosa bleibt unklar. Eine
explizite Neubewertung im Browser korrigierte diesen Versuch auf falsch und
erhielt seine ursprüngliche Antwort, Hilfen und vorherige Bewertung im Audit.
Der Rückblick zählt eine danach geschlossene Runde weiterhin als vollständig
bearbeitet; falsche Lösungen werden dadurch nicht richtig.

Die gezielte Anschlussrunde bleibt an das tatsächlich betroffene Lernziel und
seinen Quellensatz gebunden. Sie fragt nach Mitte/Rand und gleichen/verschiedenen
Abständen, statt dieselbe Zahlenfrage umzuschreiben. Kernfragen und Antworten
stehen vor dem Aufruf fest; bekannte Zielkennungen bleiben erhalten. Ein
erschöpfter endlicher Fragenvorrat wird vor dem Versand ohne neue Kosten gemeldet.

Ein Folgeauftrag scheiterte an der Vermischung vorbereiteter Grafikkennungen mit
der separaten dynamischen Grafiktabelle. Der Transport erkennt nun ausschließlich
die im jeweiligen Schema ausdrücklich aufgezählten vorbereiteten Kennungen und
prüft weiterhin tatsächliche Tabellenverweise, unbenutzte Einträge und Kollisionen.
Ein weiterer fehlgeschlagener Versuch überschritt die alte500KB-Gesamtgrenze;
sein ursprünglicher Antwortkörper wurde nicht erhalten. Seine konkrete Ursache
und tatsächlichen Kosten sind unbekannt, die Reservierung bleibt erhalten.
Nach nachgewiesenem Fix gelang genau ein auditierter, normal reservierter
synthetischer Reparaturauftrag:13.038ms,0,001707USD gemeldet, vollständige
Antwort von12.084Bytes. Die beiden richtigen Antworten wurden im390px-Browser
abgegeben und der Rückblick abgeschlossen. Screenshot84 im lokalen Testordner.

## Antwortumschlag und Kostenbeleg

OpenRouter wird weiterhin mit `reasoning.effort=medium` und `exclude=true`
angesprochen. In einer tatsächlich erfolgreichen künstlichen Antwort waren
trotzdem verschlüsselte `reasoning_details` enthalten; nur Typen und Größen
wurden untersucht, keine Gedankeninhalte ausgewertet. Dies beweist nicht die
Ursache des früheren500KB-Abbruchs.

Der gesamte OpenRouter-JSON-Umschlag ist jetzt auf4MB begrenzt. Innerhalb dieser
Grenze werden zuerst vorhandene Usage-/Generierungsbelege erfasst und die nicht
verwendeten Reasoning-Felder entfernt. Für den verbleibenden Umschlag gilt weiter
500KB; Lerntext, Schemas, Tokenlimits, Route, Wiederholungsgrenzen und Reservierung
werden nicht gelockert. Über4MB bleibt der Auftrag verworfen und bei fehlendem
Beleg konservativ unbekannt abgerechnet. Fünf künstliche Transportfälle prüfen
große verschlüsselte Metadaten, große sichtbare Inhalte, fremde Metadaten,
Gesamtgrenze und Belegerhalt. Kein automatischer zweiter Modellaufruf.

## Letzter fehlender Paket-Tag und fehlerhafter Altbestand

Die künstliche Dezimalquellenprüfung des09.12. bestätigte die vorhandene
`math.decimal.column_sum`-Bindung. Der alte Ausgabeversuch enthielt eine
verstümmelte Frage mit einem anderen Ergebnis; er wird nicht nachträglich gültig
umgeschrieben. Nach dem gesondert belegten Fix der festen Fragekerne wurde genau
ein weiterer lokaler Reparaturauftrag für diesen konkreten Fehler auditiert und
regulär reserviert. Alle drei früheren Versuche bleiben erhalten, Zähler3→4.
Die neue Antwort war vollständig (`stop`),16.339ms und0,024816USD gemeldet.
Sie erzeugte zwei verschiedene neue Aufgaben; weder fotografierte Beispiele
noch ältere Aufgaben wurden wiederholt.

Der Browserdurchlauf prüfte8.6 als Antwort auf2,6+6 und anschließend5,7 auf2,7+3.
Die Erklärung zeigt tatsächlich das Originalbeispiel2,4+1,3 mit schrittweiser
Zehntel-/Einerrechnung. Beide Antworten und der Abschluss sind gespeichert;
selbstständiger Erstversuch und angeleitete Anwendung bleiben unterschieden.
Screenshots85/86 im lokalen Testordner.

Beim Öffnen einer früher angelegten Runde des10.12. erschien noch die interne
Korrekturmarkierung „oops bad character Need fix“. Der vorhandene Generatorguard
verhindert neue solche Pakete, repariert aber keinen Altbestand. Eine zusätzliche
rein lesende Prüfung erkennt genau diesen belegten Marker in erzeugter Prosa.
Sie verändert weder Originalfragen noch Antworten. Start/Antwort/Lernzeit sind
für diese offene fehlerhafte Runde gesperrt; die Kinderansicht führt direkt zur
eigenen Heftseite für eine bewusst angeforderte neue Übung. Eltern können den
ursprünglichen Inhalt mit Warnung weiter nachvollziehen. Dies ist keine pauschale
semantische Nachprüfung sämtlicher historischer Aufgaben.

Weitere gezielte Prüfungen:128 Anbieter-/Kosten-/Transport- und Altbestandsfälle
bestanden;21 Aufgabenraum-Widgetfälle einschließlich Quellen-Ausweg und
unterbundener Heartbeats bestanden. Ein unterbrochener Lauf auf langsamer
Dateiablage ist kein zusätzlicher vollständiger Testlauf; dieselbe Testauswahl
wurde anschließend in einer eigenen temporären RAM-Datenbank abgeschlossen.

Die reale Altfrage enthielt unmittelbar vor `oops` ein arabisches Schriftzeichen.
Die frühere Unicode-Wortgrenze erkannte diesen konkreten Übergang nicht. Sowohl
Generatorguard als auch Altbestandsprüfung erfassen jetzt den vollständigen
Korrekturmarker auch in dieser beobachteten Form; gewöhnliches englisches
„Oops! I made a mistake.“ bleibt erlaubt.27 gezielte Fälle dazu bestanden.
Die erneute vollständige passende UI-Auswahl bestand mit70 Fällen; Flutter
Analyze meldete keine Probleme.146 weitere Backendfälle für Zahlenstrahl,
Dezimalbindung, Transport und Altbestand bestanden. Ein zunächst falsch
angegebener Flutter-Testdateiname war ein Aufruffehler; er ist kein bestandener
Test und wurde durch den korrekten vollständigen Lauf ersetzt.

Der Quellen-Ausweg wurde tatsächlich im390px-Browser benutzt. Von der eigenen
bestätigten Heftseite wurde über „Jetzt lernen“ genau eine reguläre Zweierübung
angefordert. Die neue Runde wurde bereit; die Glocke erhöhte ihren In-App-Stand
von16auf17. Screenshot88 hält diese Bereitschaft fest. Dies ist weiterhin kein
Beleg einer sichtbaren FCM-Zustellung auf einem physischen Gerät.

## Abschluss der vorbereiteten Schultage und nächste Empfehlung

Die unabhängige rein lesende Zählung erfasst für02.11.–11.12. exakt30
Schultage und32 bestätigte Materialseiten. Alle30 Vorbereitungen sind bereit.
Jeder dieser Tage hat mindestens eine abgeschlossene quellengebundene Runde.
29Tage haben sämtliche ursprünglichen gespeicherten Einstiegsrunden abgeschlossen;
beim10.12. bleibt die fehlerhafte Altrunde absichtlich pausiert erhalten und eine
über dieselbe bestätigte Quelle regulär angeforderte Ersatzrunde ist abgeschlossen.
Die beiden zusätzlichen pausierten Layout-/Inhalts-Testkopien und ein Pilot vor
dem Monat sind keine weiteren erledigten Schultage. Dies belegt weder sämtliche
künftigen Etappen noch tägliche20Minuten an allen30Tagen oder eine Lehrplanabnahme.
Zwei künstliche Eltern-Notenimporte sind angewendet, insgesamt vier Noteneinträge.

Die reale Heute-Prüfung nach Abschluss der Ersatzrunde fand noch eine falsche
Empfehlung: „Weiterlernen“ versuchte die gesperrte Altrunde erneut zu starten.
Der Planer entfernt jetzt genau die offen erkannten fehlerhaften Runden aus der
nächsten Empfehlung. Der ursprüngliche Verlauf bleibt erreichbar. Verknüpfte
verbindliche Elternaufträge werden wieder als Auftrag angeboten, nicht erledigt
oder unsichtbar gesetzt. Eine eigene gebündelte DB-Vorfilterung lädt nur mögliche
Korrekturmarker statt sämtlicher Aufgaben der kompakten Startansicht. Prüfung
und Auswahl bleiben kindgebunden und schreibfrei.67 Plan-/Tages-/Altbestandsfälle
sowie ein zusätzlicher gezielter Zweierlauf bestanden. Der Browser zeigte danach
eine andere tatsächlich vorhandene offene Runde; Screenshot90. Die zuvor
gebauten204-Artefakte wurden dafür vor Veröffentlichung angehalten und werden
vollständig aus dem abschließenden Commit neu erstellt.
