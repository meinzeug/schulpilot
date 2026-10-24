# Fachhefter und Fotoalbum

## Ablauf und Architektur

„Hefte“ öffnet den festen Fachstamm mit echten Bildassets für24 Fächer. Die
fotorealistischen Pappschnellhefter wurden mit dem eingebauten Bildwerkzeug
erzeugt; schwarze handschriftliche Fachnamen, je Fach ein eigenes Motiv.
Dateien: `app/assets/folders/*.webp`, vollständige Prompts/Herkunft in
`docs/NOTEBOOK_ASSETS.json`. Zusätzlich „Mein Heft“ als neutrales Bild für
eigene private Fächer und noch unzugeordnete Seiten. Keine privaten Fachnamen
oder Kinderbilder an das Bildwerkzeug.25 WebP-Dateien zusammen784.908Bytes,
640×640, Original-PNGs außerhalb von Git in artifacts/folder-covers erhalten.

Ein Fachhefter ist die Ansicht der eigenen Materialseiten eines stabilen
Fachs, keine zweite Inhaltskopie oder neue Lernplattform. Suche, „Meine
Fächer“ und Karten-/Listenansicht; leere Fächer bleiben öffnbar. Die bisherige
gefilterte Materialliste ist unter „Alle Heftseiten“ erreichbar. Profile ohne
ein einziges Material verwenden denselben unabhängigen Fachstamm.

Route `/library/{childId}/subject/{subjectId}`, einschließlich `unassigned`
für noch nicht zugeordnete Seiten. Die vorhandene authentifizierte Material-
API erhält einen zusätzlichen validierten subject_id-Filter. Alte Label-
Filter bleiben kompatibel. Metadaten: Fach-ID, Revision und has_image, niemals
Speicherpfad oder vollständiger Quelltext. Alle Listen/status GETs bleiben
ohne neue KI, Antworten, Lernzeit oder Fortschritt.

## Bedienung

Blättern zeigt das tatsächliche private Heftfoto vollständig, mit Pfeilen,
langsamen/schnellen Wischgesten, Tastaturpfeilen/PageUp/PageDown/Home/End und
direktem Seitensprung. Sanfter Blättereffekt mit Perspektive/Fade; bei
reduzierter Bewegung ohne Animation. Vergrößern öffnet das echte Foto mit
Pinch-/Mauszoom. Quelle/Text und bestehendes Lernen sind über die normale
berechtigte Detailseite erreichbar; ungeprüfte Seiten führen zur Prüfung.
Seit1.6.1 kompakte Leserleiste, Suche erst auf Wunsch und A4-angepasste
Fotohöhe. Belegte/ausgewählte Fächer zuerst, ohne die übrigen auszublenden.

Kachel- und Listenübersicht zeigen reale Fotos und Datum/Prüfstatus. Maximal20
Metadatensätze pro Abruf, stabile created/id-Sortierung, Suche im vorhandenen
Text, Datums-/Prüfstatusfilter und älteste/neueste Reihenfolge. Kein Vorladen
aller Bilder einer wachsenden Sammlung. Bilder nur bei Anzeige laden,
Vorschauen begrenzt dekodieren und Cacheeinträge beim Dispose/Logout evictieren.
Keine Foto-URLs mit Tokens, keine öffentliche oder persistente Clientablage.
Leere Fächer, Netzfehler und fehlende Fotos mit expliziter erneuter Aktion.

## Rechte und Prüfung

Familie/Kind weiter aus der Sitzung; Kinder können weder fremde Seiten noch
private Geschwisterfächer über erratene IDs öffnen. Eltern nach bestehenden
Familienrechten, Administratoren ohne private Inhalte. Überholte Antworten
nach Kontowechsel/Logout verwerfen, Fotos sofort aus dem Widget entfernen.
Ansicht/Filter/Position ausschließlich kontogebunden im Arbeitsspeicher.

Neue Backendtests plus bestehende Bibliotheks-/Fachtests:33 PostgreSQLtests
bestanden21,35s, darunter1205 Seiten, Aliaszusammenführung im Filter, leere
Fächer, fehlende Fotos, Geschwisterschutz und keine erzeugten Jobs/Aktivitäten.
Neue und bestehende Sammlungswidgettests:17 bestanden,320/1280px, große
Schrift, reduzierte Bewegung, Zoom, Seitensprung über Metadatenseiten,
langsame Wischgeste/Tastatur, Kontowechsel während Fotodownload.
Zusätzlich vollständige875 PostgreSQLtests511,43s und326 Fluttertests
erfolgreich. Nach dem abschließenden Clientcheck gegen ignorierte Fachfilter
älterer Backends die17 betroffenen Widgettests/Analyse erneut bestanden und
Web/Direct-APK/Play-AAB neu gebaut. Anschließend für den kompakteren37-Leser
alle328 Fluttertests/Analyse und57 Backendregressionen bestanden.
Keine Abhängigkeiten/SDKs aktualisiert.

Öffentliche/native Abnahme1.6.1+37 bestanden mit26 ausschließlich künstlichen Foto-
Uploads über die normale API, zwei echten reservierten OCR-Aufträgen und
ausdrücklicher Bestätigung zweier Mathematikseiten.24 Seiten bleiben ehrlich
unzugeordnet; keine Datenbankinjektion, kein beliebiger Debug-Endpunkt, keine
erfundenen Kinderantworten. Chrome390/1440px mit normalem Kinder-/Elternlogin,
Fotopaging/Zoom/Ansichten, Sprung über Metadatenseiten und Netzfehler mit
expliziter Wiederaufnahme geprüft. Null JavaScriptfehler/Album-Schreibaufrufe.
Native reguläre Flutter-APK37 im API36-Emulator mit Fotos/Blättern/Zoom,
Ansichten, Seitensprung, App-Neustart und Logout bestanden. Reales OTA36->37
und drei Startchecks bestanden; kein physischer Gerätetest daraus abgeleitet.
Export/all26 privaten Fotos/keine Lernbelege geprüft, eigene Familie regulär
gelöscht, alte Sitzungen401, geschützten Checkpoint entfernt, Emulator beendet.
`scripts/prepare_notebook_smoke.py`, `qa/notebooks_web.mjs`,
`qa/android_notebooks.py`, `qa/notebooks_cleanup.py`; aktuelle Releasewerte
in STATUS/Handoff. Vollständiger Katalogimport und gemeinsame Lerntipps sind seit1.7.0+38
zusätzlich bereitgestellt und im normalen künstlichen Web-Fotoablauf geprüft;
siehe CATALOG_INTEGRATION.md und den aktuellen Nachweis in STATUS/Handoff.

Regression1.7.0+38: zwei neue künstliche Fotos tatsächlich im normalen
Kinder-Fotoassistenten ausgewählt, zugeschnitten, abgegeben, mit reservierten
OCR-Aufträgen erkannt und ausdrücklich bestätigt. Web390/1440px und reguläre
native Flutter-APK38/API36: echtes Album/Blättern/Zoom/Kacheln/Liste bestanden,
zusätzliche Lerntipps/Themenbrowser korrekt. Reales OTA37->38 und drei Startchecks,
Neustart/Logout sowie Export/Löschung desselben Testhaushalts bestanden. Keine
neuen KI-Aufträge durch Albumansichten; keine Linkaufrufe als Lernerfolg gezählt.

## Kompakte Hefter-Werkzeuge ab1.7.1+39/1.7.2+40

Die Startansicht zeigt eine einzelne Icon-Leiste statt permanenter Suchbox und
mehrzeiliger Filter. Lupe öffnet die Suche bewusst; Schließen entfernt die Suche
und gibt den Platz wieder frei. „Meine Fächer“ zeigt als sichtbar ausgewählter
Filter ausschließlich Hefter mit vorhandenen Seiten. Auch ausgewählte
Unterrichtsfächer bleiben bei null Seiten ausgeblendet; die Ablage
„Noch zuordnen“ bleibt bei vorhandenen Seiten erreichbar. Ein Icon schaltet zwischen Kacheln und Liste um, die Kamera
führt zum bisherigen Fotoimport. Das Menü bündelt Alle Heftseiten, Wörter,
Aktualisieren und im Elternzugang den Rückweg zum Lernüberblick. Alle Icons
haben Tooltips/Zugänglichkeitsnamen und weiterhin ausreichend große Trefferflächen.
Die Wörter bleiben im regulären Menü. Gespeicherte Suchbegriffe bleiben sichtbar,
aber öffnen beim Wiederaufruf keine Tastatur. Ansichten/Filter bleiben reine GETs.

Die Fachsuche verwendet ab40 keine Tastatur-Autokorrektur oder Vorschläge.
Fachnamen dürfen beim Bestätigen der Suche nicht durch anderssprachige
Wörterbuchvorschläge verändert werden; Texteingaben in Lernaufgaben bleiben
von dieser Suchfeldeinstellung unberührt.

Abnahme40:26 betroffene Fluttertests/Analyse sowie öffentliche Browserbedienung
390/529/1440px und native Flutter-APK40/API36 bestanden. Erste Hefter bei224px
(mobil),249px(desktop). Zwei normale künstliche Uploads ohne OCR geprüft;
Minefilter verbirgt auch ausgewählte leere Fächer und erhält unzugeordnete
Seiten. Reales OTA39->40 und drei Startchecks bestanden. Testhaushalt nach
Export regulär gelöscht, alte Sitzungen401. Details/aktuelle Artefakte in
STATUS/Handoff; keine physische Geräte-, Audio- oder Push-Abnahme abgeleitet.

## Heftaktionen ab1.11.0+50

Der ausdrückliche Auftrag vom20.10.2026 erweitert die frühere Löschregel: Kinder
können eigene bestätigte Seiten in der Heftsammlung entfernen. Papierkorb und
„Mit KI neu lesen“ stehen direkt über dem Albumfoto und an den Kachel-/Listen-
seiten. Die Detailansicht bietet dieselben Aktionen. Eltern benötigen weiterhin
Verwaltungsrechte; Lese-Eltern und Betriebsadministratoren bekommen keinen
privaten Schreibzugriff. Feste KI-Beispielseiten bleiben geschützt.

Die Liste bietet „Seiten auswählen“, „Alle auswählen“, „Auswahl löschen“ und
„Alles löschen“. Alle meint den gesamten aktuellen Hefter beziehungsweise Filter,
auch jenseits der sichtbaren20 Datensätze. Einzelne Auswahl höchstens500 IDs,
gefilterte Gesamtauswahl höchstens5.000 Seiten; größere Sammlungen nach Fach oder
Datum eingrenzen. Eine serverseitige Vorschau zeigt die genaue Anzahl. Ihr
verschlüsselter Token gilt zehn Minuten, gebunden an Anmeldung, Kind, Filter und
Snapshot. Neue/geänderte Seiten, Rechteänderung oder laufende Verarbeitung führen
zur vollständigen Ablehnung; keine stille Teillöschung. Einheitensperren vor Kind,
stabile Reihenfolge, Löschjournal und bestehende Quellen-/Tutor-/Wortlöschung
werden wiederverwendet. In Version50 blieben gespeicherte Übungen und Antworten;
der folgende ausdrückliche Betreiberauftrag ändert dies ab51 wie unten beschrieben.
Auswahl wird bei Filter-/Kontowechsel verworfen. Die eigene Prüfseitenroute des
Fotoassistenten behält ihre bisherigen Tages- und Fortsetzungsprüfungen.

Neues Einlesen ist eine bewusste KI-Aktion mit Rückfrage und Idempotenzschlüssel:
Das private Foto wird in eine neue unbestätigte Quelle kopiert und genau ein
normal reservierter OCR-Auftrag angelegt. Die alte Quelle und ihre Antworten
werden nicht überschrieben. Quelle, Sitzung, Familienrechte, Tarif und Provider-
revision werden vor und nach der externen Verarbeitung geprüft. Keine neue
Datenbankmigration; Herkunft und Quellrevision stehen im bestehenden Jobpayload.

`/material/{id}/processing/{jobId}` beobachtet den bestehenden Auftrag nur mit
GETs. Reload, Rückkehr aus dem Hintergrund oder „Status neu laden“ startet keine
weitere KI. Nach Erfolg „Seite prüfen“ → „Stimmt, weiter“ → ausdrücklich neue
Lernrunde vorbereiten. Bei Wortseiten bleibt die eigene Vokabelvorschau mit
Einzelbestätigung erhalten. Fehler bleiben sichtbar; kein Dummy und kein
automatischer Retry. Auch nach App-Neustart führt der Materialstatus zurück zum
vorhandenen Auftrag. Die neue Fassung ist als eigene gespeicherte Quelle in der
Sammlung erreichbar; gewünschte alte Fotos können danach bewusst gelöscht werden.

Additive API-Endpunkte:

- `POST /children/{id}/materials/delete-preview`: IDs oder all_matching+Filter.
- `POST /children/{id}/materials/bulk-delete`: bestätigter Auswahl-Token.
- `POST /materials/{id}/reprocess`: Quellrevision+Idempotency-Key.
- Materialdetail: has_image, fixed_example, processing_job; Jobdetail zusätzlich
  material_id. Keine Dateipfade, Anbieterzugänge oder privaten Schlüssel.

Tatsächlich ausgeführte Prüfungen, öffentliche Version und verbleibende Grenzen
stehen in STATUS.md und NOTEBOOK_ACTIONS_QA.md. Widget-/Mockprüfungen sind kein
Nachweis echter KI-Erkennung oder physischer Gerätetests.

## Zusammenhängendes Löschen ab1.11.1+51

Die bestätigte Seitenlöschung entfernt auch direkt verknüpfte Lernrunden,
Mehrquellenrunden und über Vorgänger-/Wurzelverweise verknüpfte Folgeübungen.
Die serverseitige Vorschau nennt die genaue Zahl der Seiten, Runden und
gespeicherten Antwortversuche. Bei einer Mehrquellenrunde bleiben andere Fotos
erhalten; ihre gemeinsame Runde wird vollständig entfernt. Quellen-, Runden-,
Antwort-, Hilfe- und Rückblickänderungen nach der Vorschau sperren die Löschung.
Laufende KI-Verarbeitung sperrt weiterhin die gesamte Aktion.

Neue Clients senden delete_linked_units=true mit dem bestätigten Auswahltoken.
Ältere Clients mit dem bisherigen Versprechen, Antworten zu behalten, werden
bei verknüpften Übungen mit einem Aktualisierungshinweis abgewiesen. Auch die
alte direkte DELETE-Route löscht solche Seiten nicht unbemerkt.

Attempts, Rückblicke, Tutorbezüge, Entwürfe, Lerntipps und zugehörige Aktivitäten
werden über bestehende Fremdschlüssel gelöscht. Lernplanblöcke werden entfernt,
nicht als neue Erzeugungswünsche freigestellt. Abgeleitete Themen-/Wortstände
werden aus verbleibenden Übungsbelegen neu berechnet. Elternaufträge und echte
KI-Verbräuche/Reservierungen bleiben erhalten; abgeschlossene Jobaufträge behalten
ihre Idempotenzkennung mit bereinigtem Inhalt.

Das authentifizierte Löschjournal kennt zusätzlich scope=unit. Wiederherstellungen
müssen mindestens diesen journalfähigen Stand verwenden. Ein Code-Rückweg auf50
braucht einen gesonderten Rückbau, der die neue Journalprüfung und Rundenbereinigung
erhält; alte Wiederherstellungswerkzeuge würden den unbekannten Scope ablehnen.
Keine Rücksicherung über neuere Antworten oder Löschungen durchführen.

### Kinder-Voreinstellung ab 1.13.0

Ohne gespeicherte Ansichtspräferenz ist „Meine Fächer“ im Kinderzugang bereits
aktiv. Damit erscheinen zuerst Fächer mit tatsächlich vorhandenen Seiten und
gegebenenfalls „Noch zuordnen“. Alle Fächer bleiben über den vorhandenen Filter
zugänglich. Eine im selben angemeldeten Konto bewusst gespeicherte volle Ansicht
hat Vorrang; Eltern behalten die bisherige Voreinstellung. Keine Fachzuordnung,
Quellenbestätigung oder KI durch Öffnen/Umschalten der Ansicht.

### Durchgängiger Fotoassistent und Altbestand ab 1.14.2+62

Auch der Fotoassistent und die Prüfung unbestätigter Tagesseiten verwenden nun
dieselbe gezählte, revisionsgebundene Löschvorschau wie das Fotoalbum. Alte direkte
Tagesseiten-DELETEs mit verknüpften Runden werden abgewiesen. Explizite historische
Quellenbindungen über Aufträge, Sprachprojekte und die gespeicherte Wortrevision
werden mit erfasst. Aktuell bearbeitete Wörter binden alte Runden nicht um.

Die 365-Tage-Seitenbereinigung und ein Restore alter reiner Materialjournale
entfernen ebenfalls abhängige Runden. Ein lokaler, explizit kindgebundener
Operatorweg erlaubt die geprüfte Altbestandsbereinigung; kein privater Admin-API-
Zugang und kein KI-Auftrag. Vorschau, exakter Bestandsdigest, Sperren und Audit
sichern die Ausführung. Einzelheiten und Journal-/Rückwegregeln stehen in
[SOURCE_DELETION_2026_10_20.md](SOURCE_DELETION_2026_10_20.md).

### Geplante Etappen und Fotozoom ab 1.14.3+63

Auch noch nicht erzeugte Etappen dürfen nach Quellenlöschung nicht als weitere
Aufgaben angeboten werden. Eigene gültige Quell-IDs und gespeicherte Runden
werden in Tagesplanung, Sammlung und Lernreise lesend geprüft. Die Lösch-,
Aufbewahrungs- und Restorepfade entfernen unverbundene Planblöcke; der lokale
Altbereinigungsdigest zählt sie separat. Kein automatisches Neuplanen/Generieren
beim Lesen.

Der Vollbildzoom hat zusätzliche große Plus-/Minus-/Zurücksetzen-Tasten und
einen Prozentwert, weiterhin maximal8-fach. Bildwechsel/Logout verwerfen
Matrix und private Bildbytes; Zoomen löst keine neuen Bild-/KI-Anfragen aus.
Abnahme und Grenzen in CHILD_AUDIT_2026_10_20.md.

## Hefteroptionen104 ·24.10.2026

Der fachbezogene Kopf bündelt die Zusatzwerkzeuge im Drei-Punkte-Menü
„Hefteroptionen“: Blättern/Kacheln/Liste, Suche, Filter mit Reihenfolge und
Zeitraum, bewusstes Aktualisieren und Themen entdecken. Im normalen Leser
bleiben Rückweg, Fach, Foto hinzufügen und die Seitenwahl vor dem Inhalt.
Aktive Such-/Status-/Zeitraumfilter bleiben sichtbar und einzeln aufhebbar.

Die Suche verwendet einen lokalen Entwurf; erst Übernehmen oder Enter
wendet ihn an. Abbrechen erhält die bisherige Auswahl. Geschlossene Menüs
belegen keinen Inhaltsraum. Konto, Sitzung, Familie, Fach, Quellenrevision
und aktuelle Hostroute werden vor der Folgeaktion erneut geprüft.
Ansichtwechsel ändern weder Lernstand noch Metadatenfilter; benötigte
private Fotovorschauen dürfen beim Anzeigen normal nachgeladen werden.
Die Elternansicht behält ihren berechtigten Kinder-/Familienkontext.
