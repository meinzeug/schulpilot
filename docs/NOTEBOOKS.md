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
Web/Direct-APK/Play-AAB neu gebaut. Diese Komponentenprüfungen sind noch kein
öffentlicher oder nativer Nachweis. Keine Abhängigkeiten/SDKs aktualisiert.

Öffentliche Abnahme vorbereitet mit26 ausschließlich künstlichen Foto-
Uploads über die normale API, zwei echten reservierten OCR-Aufträgen und
ausdrücklicher Bestätigung zweier Mathematikseiten.24 Seiten bleiben ehrlich
unzugeordnet; keine Datenbankinjektion, kein beliebiger Debug-Endpunkt, keine
erfundenen Kinderantworten. Checkpoint geschützt außerhalb von Git.
`scripts/prepare_notebook_smoke.py`, `qa/notebooks_web.mjs`; native Abnahme,
reguläre Familienlöschung sowie tatsächlicher Release in STATUS/Handoff
nachführen. Vollständiger Katalogimport/Lerntipps sind ein eigener noch offener
Ausbau, siehe CATALOG_INTEGRATION.md; nicht mit der Fachhefteransicht gleichsetzen.
