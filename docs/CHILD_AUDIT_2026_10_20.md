# Kinderzugang: vollständige Funktionsprüfung · 20.10.2026

Betreiberauftrag: alle Funktionen im angemeldeten Kinderzugang prüfen und
belegte Fehler/Bedienprobleme beheben. Zielversion 1.14.3+63. Produktionskonto
nur lesend prüfen; keine Testantworten, Hilfewünsche, Nachrichten, Änderungen
an Wörtern/Noten oder neuen KI-Aufträge in seinem Bestand. Schreibende Abläufe
verwenden künstliche, getrennte lokale Daten. Keine privaten Kennungen,
Antworten, Fotos oder Zugangsdaten in Git.

## Befunde und Korrekturen

- **Alte Lernplanreste:** Nicht erzeugte Etappen mit gelöschten Heftquellen
  erschienen weiterhin unter Lernen und in Tages-/Wochenvorschlägen. Gemeinsame
  reine Leseprojektion prüft eigene bestätigte Quellen; dangling Rundenkennungen
  werden nicht zu neuen Erzeugungswünschen. Vorhandene eigene Runden bleiben
  erreichbar. Der Foto-Löschweg, Aufbewahrung und Materialjournal-Restore
  bereinigen auch die geplanten Etappen und deren Umfangsmetadaten.
- **Kontrollierte Altbereinigung:** Der bestehende lokale Operatorweg zeigt
  zusätzlich die Zahl nicht erzeugter Planreste, bindet sie in den Digest,
  sperrt Einheit → Kind → Aufträge/Tage und prüft vor Anwendung neu. Keine KI,
  keine Antworten-/Kostenumschreibung und keine Änderung gültiger manueller
  Wörter oder Elternaufträge. GETs ändern weiterhin keine gespeicherten Pläne.
- **Sprachfehler im Dialog:** Ein Seiten-SnackBar ist hinter einer Erklärung
  oder einem Eingabeblatt verdeckt. Echte Sprachfehler erscheinen dort jetzt
  darüber und führen zum Text zurück. Erfolgreich erkannter Text bleibt
  korrigierbar; kein Autoplay, keine automatische Übermittlung und kein
  erfolgreicher Hörreiz bei fehlender Stimme.
- **Fotozoom:** Große Tasten für Vergrößern, Verkleinern und Zurücksetzen,
  sichtbarer/ansagbarer Prozentwert, 1–8-fache Grenzen. Vergrößerung um die
  tatsächliche Bildmitte, Rücksetzung bei Quellen-/Kontowechsel. Gesten bleiben
  verfügbar. Kein weiterer Bildabruf, öffentlicher Cache oder KI-Auftrag.
- **Neuigkeiten:** Gelöschte Sprachrunden mit gespeichertem Jobtombstone nicht
  erneut als bereit anbieten. Auch alte Clients bekommen nur vorhandene Ziele
  desselben Kindes; gelöschte/fremde/malformed Ziele führen zum bestehenden
  Familienbereich. Menschliche Nachrichten bleiben erhalten/lesbar. Mehr als
  zwei Fächer werden in kurzen Vorbereitungszeilen mit Auslassung gekennzeichnet.

## Prüfumfang und Methoden

| Funktion | Ausgeführte Prüfung |
| --- | --- |
| Heute, Plan, freiwillige Fortsetzung | Reales Kindkonto gelesen; Tagesminimum, tatsächliche abgeschlossene Runden und pausierte Runde abgeglichen. Plan-/Termin-/Quellregeln zusätzlich isoliert. Die sechs abgeschlossenen Runden waren tatsächlich gespeichert, kein erfundener Zählerfehler. |
| Lernen, Suche, Filter, Seiten, Gruppierung | Reale Sammlung und Lernstand geöffnet; vollständige Backend-/Widgetprüfungen für Filter, Kontowechsel, Seitenteilung und Rollen. Alte Planreste reproduziert. |
| Auswahl, Bruch-/Lückentext, Zuordnung, Kurzantwort | Ganze feste künstliche Vier-Aufgaben-Runde im lokalen echten Browser: falsche Antwort, Tipp, weiterer Versuch, richtige Antworten und Ergebnis vor offenem Zeitminimum. Kein echter Kinderbeleg geändert. |
| Erklärungen, Hilfen, Wiederaufnahme | Erklärung, Schritt-/Tippablauf, gespeicherte Rückmeldung nach Reload und Unterstützungseinstufung; künstliche Fach-/Formel-/Grafiktests aus vollständiger Suite. |
| Hefte, Album, Originalfoto, Zoom | Reales Album/Zoom/Rückweg gelesen; neue Zoomsteuerung bei 320 px und doppelter Schrift, Grenzen und Quellenwechsel isoliert. |
| Fotoauswahl, Blobzugriff, Drehen, Zuschnitt | Künstliches JPEG im regulären Produktions-Fotoassistenten bis zum Zuschnitt geöffnet und gedreht. Vor Übernahme abgebrochen: neun Tagesseiten gespeichert, null vorgemerkt. Kein Upload und keine OCR dadurch. |
| Abgeben, OCR, Bestätigen, Pakete, Status/Retry | Vollständige isolierte API-/Widgettests für Idempotenz, Quellen-/Sitzungsprüfung, Fehler und Hintergrundfortsetzung. Externe OCR/Erzeugung in dieser erneuten Bedienprüfung nicht wiederholt; bisherige Anbieterabnahme unverändert. |
| Wörter, Import, Korrektur, Abrufmodi | Reale Übersicht und 10er-Dialog gelesen, keine Aufdeckung/Korrektur gestartet. Ganze isolierte Modus-/Import-/Revision-/Wiedervorlageprüfungen einschließlich fünf/zehn/fünfzehn Aufgaben. |
| Sprachwerkstatt, Dialog, Grammatik, Probe | Bestehende vollständige Widget-/Backendtests für Entwürfe, Kriterien, Quellen, einzelne bewusste Schritte, Limits und Wiederholung. Kein zusätzlicher externer Modellauftrag. |
| Heftfragen, Zitate, Lerntipps, Medienrückkehr | Vollständige isolierte Tests für gespeicherte Zitate, private Quellen, Hilfezuordnung, gestufte Offenlegung und explizite Folgeaufträge. |
| Nachrichten, Hilfe, Wünsche | Reale Menü-/Readernavigation ohne Versand; isolierte Schreib-/Rollen-/Kontextprüfungen einschließlich ungültiger Altverweise. |
| Glocke, Lesen, Push-Freigabe | Reale Neuigkeiten und gesperrtes Geräte-Opt-in ohne Elternfreigabe gesehen; Lesen/Mehrgeräte/Entzug/Ruhezeiten mit künstlichen Tests. |
| Konto, Geräte, Datenschutz, Abmelden | Reale Geräte-/Elternrechte gelesen, keine echte Sitzung widerrufen. Isolierte Auth-/Konten-/Widerrufs-/Lösch-/Exporttests. |
| Mobil, große Schrift, Tastatur, Kontowechsel | Vollständige Flutter-Suite einschließlich 320/390/1440 px, doppelter Schrift, später Antworten und Cache-/Lifecycleprüfungen. |

## Tests

900 Fluttertests vollständig bestanden. Flutteranalyse und Ruff ohne Befund.
Vollständiger isolierter PostgreSQL-Pytestlauf: 1.247 bestanden in 1.047,05 s.
Die äußere Ausführung meldete danach Abschlussstatus143; die temporäre Datenbank
war vollständig entfernt, kein zurückgebliebener Testcluster. Diesen Status
nicht als reguläres Wrapper-Exit0 ausgeben. Nach den letzten Änderungen an
Neuigkeiten zusätzlich 30 passende PostgreSQL-Prüfungen mit Abschlussstatus0
bestanden; Mengen überschneiden sich. Drei vorhandene Deprecation-Warnungen im
Gesamtlauf (Testclient/Alembic), keine fachlichen Testfehler.

Kein angeschlossenes Androidgerät/Emulator. Signierter Build und automatisierte
Plattformgrenzen ersetzen keine neue native Installations-/Mikrofon-/sichtbare
FCM-Zustellabnahme. Keine gehörte Audioausgabe, vollständige WCAG-Zertifizierung
oder gemessene Lernwirkung behauptet. Keine neue Inferenz und keine Veränderung
von Anbieterroute, Reservierung, Budget oder bisherigem Kostennachweis.

## Bereitstellung

Abschließende Artefakt-/Deploymentprüfung und tatsächliche Altbereinigung folgen
nach dem Build. Geplanter Code-Rückweg ist 1.14.2+62 /
`20261020T132931Z-091b791`, Schema0023. Wiederherstellung mindestens1.14.3
verwenden, um zusätzlich die geplanten Etappen nach Quellenlöschung zu bereinigen.
Keine Sicherung über neuere Antworten/Löschungen zurückspielen.
