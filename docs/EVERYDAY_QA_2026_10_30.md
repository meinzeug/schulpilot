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
