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
