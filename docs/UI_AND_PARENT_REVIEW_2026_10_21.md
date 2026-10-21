# Gemeinsame Kinderseiten, Header und Elternauswertung

Version1.18.4+78, Produktcommit7367ee4d95e6af398195962496a16968c2faddcf.
Produktionsnachweis und Rückweg stehen im aktuellen Kopf von STATUS.md.

## Oberfläche

Hausaufgabenübersicht, einzelne Hausaufgabe, Hefte und Hefterdetail verwenden die
gemeinsamen Kinderbausteine aus child_section_ui.dart. Fotoeinstieg, beschriftete
Suche/Filter, Reiter und Rückwege folgen Lernen, Wörter und Konto. Bestehende
Import-, OCR-, Quellen-, Entwurfs- und Elternabläufe bleiben bestehen. Meine Fächer
enthält nur Fächer mit Seiten; unzugeordnete Seiten bleiben erreichbar. Die
Kartenanzahl und -höhe passen sich großer Schrift an, statt Text abzuschneiden.

Die gemeinsame Glocke zeigt maximal vier vorhandene Meldungen und Alle anzeigen.
Einträge werden ausschließlich durch bewussten Klick gelesen und öffnen das
bisherige geprüfte Ziel. Betreiber erhalten keinen Familienposteingang. Das
Kontomenü öffnet Einstellungen beziehungsweise die reguläre Abmeldung.
Kontowechsel schließen Menüs; verspätete erfolgreiche oder401-Abmeldeantworten
dürfen keine neuere Sitzung löschen, auch bei erneuter Anmeldung desselben Kontos.

130 gemeinsame Fluttertests bestanden: notebook, collection, homework, header,
notification_inbox, browser_workspace, child_sections_design und appearance.
320px mit zweifacher Schrift sowie hell/dunkel eingeschlossen. Flutteranalyse
der elf betroffenen UI-/Testdateien sauber. Tatsächlicher Browserdurchlauf unter
1101×884 mit einem ausschließlich künstlichen lokalen Kind und Elternzugang:
Hausaufgaben-/Hefterköpfe, Filter, Detailrückwege, Glockenvorschau, Alle anzeigen,
bewusster Meldungsklick samt Lesemarkierung, Einstellungen und Abmeldung geprüft.
Browsergrößenüberschreibung änderte die tatsächliche Viewportgröße nicht; mobile
Prüfung in dieser Arbeitseinheit deshalb Widgetnachweis, keine native Sichtabnahme.
Lokaler Provider war abgeschaltet, kein Worker oder KI-Schlüssel vorhanden.
Lokale Zugangsdaten, Datenbankkopie und private Anbieterdiagnosekopien entfernt.
Bildnachweise in artifacts/child-header78 sind ausschließlich künstlich.

## Konkreter Elternauswertungsfehler

Die ausdrücklich beauftragte, auditierte Untersuchung des betroffenen Berichts
belegt: Anbieteraufruf erfolgreich und strukturiert lesbar, anschließende lokale
Validierung gescheitert. Der Anbieter-Log bestätigte2006Eingabe-/1999Ausgabetokens
und0,001201USD. Der Antwortinhalt wurde nicht gespeichert; welche damalige Regel
ihn genau ablehnte, ist nicht beweisbar. Keine privaten Modelltexte nachprotokolliert.

Unabhängig davon bestand eine reproduzierbare Vertragslücke: Das private Schema
erlaubte pro Thema alle Bedarfskategorien sowie Klärung ohne offene Bewertung,
die fachliche Prüfung nach dem bezahlten Aufruf zu Recht verwarf.

- `parent_insights.finding_needs`: erlaubte Kategorien aus gespeicherten Zählern.
- `bind_schema`: dieselben topic_ref-/Kategoriepaare und erlaubten Planaktionen
  vor Transport festlegen, identische Berechtigungen platzsparend gruppieren.
- `validate`: Belegprüfung bleibt streng; bekannte und doppelte Themen,
  unbelegte Klärung, Aufgabenblöcke sowie unsichere Inhalte abweisen.
- `ReviewValidationError`/`process`: invalid_output und sieben feste
  validation_reason-Kategorien, ohne private Pydantic-Fehlerwerte oder Inhalt.

33 gemeinsame PostgreSQLfälle und14 SQLitefälle bestanden; überlappende Läufe
werden nicht addiert. Alle15 nichtleeren Belegkombinationen, sieben
Ablehnungskategorien, Erhalt der Antworten/Abrechnung und echter Adapterpfad mit
einem Mocktransportaufruf geprüft. Normale Modell-/Upstream-/Datenschutzbindung
und No-Fallback bleiben erhalten. Keine Rohantworten an den Provider hinzugefügt.
Keine Schemaänderung der Datenbank, Strategieversion parent-review-3 bleibt.
Kein automatischer Reparaturaufruf; die allgemeine nächste Auswertung benötigt
neue Belege beziehungsweise einen bewussten regulären zweiten Versuch.

Nach Deployment wurde die konkret beauftragte Reparatur einmal über die weiterhin
gültige ursprüngliche Elternsitzung angefordert. Privater einmaliger Operatorhelper,
kein öffentlicher Bypass: Child-Sperre, Berechtigungen, unveränderte Belegsignatur,
genau ein früherer Fehlversuch, feste Idempotenz sowie normale Tarif-/Budget-/
Providerreservierung. Regulärer Worker: ein Aufruf, ein Jobversuch,0,001337USD,
keine unbekannten Kosten. Neuer Bericht ready, fachlich erneut validiert, aktuelle
Elternansicht und Lernplanverwendung rein lesend bestätigt. Alte Antwort-/Bericht-/
Job-/Usage-Datensätze vor/nach per privatem Hashabgleich unverändert; Operatoraudits
geprüft. Frühere0,001201USD bleiben erhalten. Keine Sitzungsreaktivierung,
Versuchs-/Budgetrücksetzung oder automatische Reparaturkette. Privater Helper und
Hashcheckpoint anschließend entfernt; nur endliche Statusnachweise bleiben lokal.
