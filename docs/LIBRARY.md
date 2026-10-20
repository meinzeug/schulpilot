# Bibliothek und Lernraum

Ab 1.2.0 öffnen „Meine Heftseiten“ und der Navigationspunkt „Hefte“ die eigene Bibliothek. Sie lädt pro Anfrage 20 Metadateneinträge, keine Fotos oder vollständigen Abschriften. Suche durchsucht Titel, Thema und bestätigten beziehungsweise noch zu prüfenden Quelltext innerhalb des eigenen Kinderzugangs. Fach, Bestätigungsstand, Datum und Sortierung lassen sich kombinieren; 10/20/50 Ergebnisse pro Seite. Leere Fächer bleiben als „Fach noch offen“ auffindbar. Prozent-/Unterstrichzeichen werden wörtlich gesucht; deutsche Groß-/Kleinschreibung funktioniert auch mit der Testdatenbank.

Zeitraumfilter verwenden bei zugeordneten Seiten den Unterrichtstag, sonst den Uploadtag in der eingestellten Zeitzone. Anfang/Ende zählen einschließlich. Der Rücksprung aus einer Heftseite erhält Filter und Seite; fällt die letzte Seite nach Löschung weg, liefert die API eine gültige letzte Seite. Suchbegriffe und Filter werden ausschließlich im laufenden angemeldeten Client gehalten und bei Kontowechsel/Logout verworfen.

„Lernen“ trennt offene Runden, spätere Aufträge/Wiederholungen und abgeschlossene Einheiten. Fachsuche und begrenzte Ergebnisse gelten auch dort. Die Darstellung sortiert Einträge; Elternprioritäten, verfügbare Zeit und die tatsächlich nächste Aktion auf „Heute“ werden nicht neu geplant. Zukunftstermine und Lernpausen erzeugen durch bloßes Öffnen keinen Auftrag. Fortschrittszahlen stammen aus gespeicherten Antwortversuchen, einschließlich unklarer Bewertungen und ausgeschöpfter Versuche; „abgeschlossen“ ist kein Beherrschungsnachweis.

Innerhalb einer fertigen Runde sind Rückblick, Lernweg und frühere Antworten einzelne Ansichten. Aktive Runden zeigen direkt Fach und aktuelle Aufgabe. Die doppelte Seitenüberschrift und wiederholte Navigationsschaltflächen entfallen; die feste Navigation bleibt erreichbar. Antwortfeedback wartet weiterhin auf ausdrückliches „Weiter“.

Auch Eltern lesen Materialien und Lernverlauf über die paginierten Listen. Lernaufträge können eine bestätigte Seite über denselben suchbaren Picker verknüpfen, unabhängig von der Startseitenvorschau. Einzelansichten enthalten weiterhin berechtigte Antworten, Hinweise, Erklärungen und Heftfragen.

## API

- GET `/api/children/{child}/materials`: q,subject,topic,status=all/review/confirmed,sort=subject/newest/oldest,since,until,page,page_size. Ein ausdrücklich leeres subject wählt noch nicht zugeordnete Seiten.
- GET `/api/children/{child}/learning`: q,subject,section=ready/later/completed,sort,page,page_size. Geplante Einträge werden aus der bestehenden Planung abgeleitet; abgeschlossene Runden werden in der Datenbank paginiert. Antworten/Quelltexte sind keine Listenfelder.
- GET `/api/children/{child}/overview?compact=true`: kleine aktuelle Vorschau und Gesamtzahl der Materialien. Der bisherige Standard ohne diesen Parameter bleibt für installierte ältere Clients erhalten.

Alle drei Wege prüfen bestehende Kinder-/Familienrechte im Backend; ein Administrator hat keinen privaten Inhaltszugriff. GET bleibt ohne KI-Erzeugung und Reservierung. Uvicorn-Zugriffslogs bleiben deaktiviert; Suchbegriffe gehören nicht in technische Logs. Kein neues Datenbankschema und keine neue Flutter-/Backendabhängigkeit.

Ab1.11.1+51 bietet jede gespeicherte Runde in „Lernen“ einen Papierkorb, auch
begonnene und abgeschlossene Runden. POST /units/{id}/delete-preview nennt die
Antwortversuche; POST /units/{id}/delete verlangt den sitzungsgebundenen,
zehn Minuten gültigen Snapshot. Abbrechen schreibt keine Löschung. Die Aktion
löscht nur die gewählte Runde mit ihren Belegen; Heftseiten, andere Runden und
Elternaufträge bleiben. Quellenlöschung entfernt dagegen alle verknüpften Runden,
siehe NOTEBOOKS.md. Rein geplante Wiederholungen sind keine gespeicherten Runden.

Prüfungen: `backend/tests/test_library.py`, `app/test/collection_screen_test.dart` und bestehende Kinder-/Rundenregressionen. Tatsächlich gebaute Versionen und Live-Abnahme: [STATUS.md](STATUS.md).

Die öffentliche UI-Prüfung verwendet ausschließlich einen eigenen temporären Demohaushalt mit 601 künstlichen Seiten, ohne externe KI. `.venv/bin/python qa/prepare_library.py --prepare` richtet ihn über normale Anmeldung und einen eng geprüften lokalen Operator-Seed ein; ein vorhandener privater Prüfstand wird nicht überschrieben. `node qa/library.mjs` bedient das echte Flutter-Web einschließlich vier fester Demoaufgaben. `.venv/bin/python qa/android_library.py` verwendet danach dieselben eigenen Daten in der bereits über den regulären Updater installierten APK im dedizierten Emulator. Nach Abschluss löscht `.venv/bin/python qa/prepare_library.py --cleanup` den ganzen Prüfhaushalt über die normale API und prüft den Widerruf beider Sitzungen. Private Zugangsdaten liegen nur in der ignorierten Datei mit Rechten `0600`; keine echten Haushalte verwenden. Die Skripte benötigen die vorhandenen Entwicklungszugänge und führen keine öffentliche Debug-Schnittstelle ein.
