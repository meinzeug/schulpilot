# Architektur und Daten

## Aufbau

- `app/lib`: Flutter-Client mit gemeinsamen Komponenten für Web/Android, HTTP-API, GoRouter und nativer sicherer Sitzungsablage. Web: HttpOnly-/Secure-/SameSite-Strict-Cookie; kein Sitzungstoken in LocalStorage.
- `backend/schulpilot`: modularer FastAPI-Monolith. `auth`, `families`, `learning`, `materials`, `providers`, `admin`; SQLAlchemy mit PostgreSQL im Betrieb. Alembic führt versionierte Schemaänderungen aus; Produktion benötigt vorab migriertes Schema.
- Ein separater, unprivilegierter Prozess bearbeitet die persistente DB-Auftragswarteschlange. Keine zusätzliche Redis-/RabbitMQ-Instanz. Atomare Auftragsübernahme, höchstens ein Anbieteraufruf je Auftrag, kein Wiederanlauf abgebrochener Anbieteraufrufe.
- Private Bilder liegen außerhalb des Webroots unter zufälligen Dateinamen. Zugriff ausschließlich über authentifizierte API mit Familien-/Kinderprüfung. JPEG/PNG/WebP, höchstens 10 MB/16 Megapixel, serverseitige Neucodierung ohne Metadaten.

## Berechtigungen

Elternregistrierung erzeugt Elternkonto und eigene Familie; verifizierte E-Mail und Volljährigkeitsbestätigung erforderlich. Kinder werden durch berechtigte Eltern angelegt und melden sich mit eigenem eindeutigem Benutzernamen und mindestens zwölfstelligem Passwort an. Keine Kinder-E-Mail, kein alleiniger Kurz-PIN.

Familieninhaber: Kinder, Lernvorgaben, Einladungen, Rechteentzug. Eingeladene Eltern haben ausdrücklich `view` (Familieninhalte lesen) oder `manage` (zusätzlich Kinder/Planung/Nachrichten verwalten). Nur der Inhaber verwaltet weitere Elternrechte. Einladungen sind adressgebunden, einmalig, zwei Tage gültig und widerrufbar; bestehende Elternkonten bestätigen zusätzlich ihr Passwort. Alle Familienzuordnungen werden serverseitig geprüft. Familien-IDs aus dem Client verleihen keine Rechte.

Kinder: ausschließlich eigenes Material, eigene Einheiten und Familiennachrichten für diesen Lernraum. Keine Geschwister, Elternvorgaben, Provider, Tarife oder Accountverwaltung. Eltern bearbeiten keine Kinderantworten. Administratoren: Provider, Betriebskennungen, Tarife und Auditprotokoll; keine privaten Kinderinhalte. Admin-Anmeldung erfordert TOTP mit Wiederverwendungsschutz.

Passwörter: Argon2id (64 MiB, drei Durchläufe); begrenzte Parallelität. Sitzungen: zufällige 384-Bit-Tokens, nur Hash in der DB, maximal 30 Tage (Admin ein Tag), sieben Tage Inaktivität; maximal zehn Geräte; Logout/Reset/Rechteentzug widerrufen Sitzungen. Einmalige Links: 256 Bit, nur Hash gespeichert; Wiederherstellung eine Stunde, Verifikation ein Tag. Links nutzen URL-Fragmente statt Queryparameter. Schreibzugriffe prüfen Ursprung und eigenen Sicherheitsheader. Rate Limits liegen persistent in der DB. Fehlermeldungen und technische Logs enthalten keine eingegebenen Geheimnisse/Antworten.

## Lernen und Planung

Der Import ist ein überprüfbarer Ablauf: Bild → Erkennungsauftrag → erkannter Stoff/Unsicherheiten/notierte Hausaufgaben → ausdrückliche Bestätigung → validierte Aufgabenstruktur → native Flutter-Komponenten → deterministische Antworten/Hinweise → gespeicherter Verlauf und Wiederholung. Die Aufgabenformate sind Auswahl, Lücke, eindeutige Zuordnung und kurze Texteingabe. Lösungsschlüssel werden dem Kinderclient nicht ausgeliefert; Zuordnungsoptionen enthalten keine fertigen Paare. Nicht eindeutig passende freie Texte sind unsicher bewertbar. Unsicherheit wird nicht automatisch als Verständnisproblem gezählt.

Eltern setzen Lerntage, Fach-Lerntage, Tages-/Wochenumfang, Höchstdauer, Pausen, Schwerpunkte, konkrete Wiederholungsziele, Aufträge und Prüfungstermine. Planung priorisiert verbindliche Ziele und Termine und begrenzt den Tagesumfang, ohne versäumte Tage zu addieren. Konflikte erscheinen mit Vorschlägen. Urlaub/Krankheit/Lernpause verhindern einen stillen Aufgabenstau. Eine abgeschlossene Übung schließt ein verbindliches Elternziel nicht automatisch; dies entscheiden Eltern ausdrücklich. Material-/Auftragsrevisionen schützen laufende Generierung vor inzwischen geänderten Zielen.

Fortschritt unterscheidet nicht begonnen, begonnen/pausiert, unterstützt richtig, selbstständig richtig und erst an einem späteren Tag erneut selbstständig richtig. Einzelantworten erzeugen keine Beherrschungsbehauptung. Aktivitätszeit: Heartbeat nur im sichtbaren, aktiven Client nach jüngster Interaktion; Server verwirft Lücken über 45 Sekunden und begrenzt einzelne Intervalle auf 25 Sekunden. Einheiten pausieren am eingestellten Zeitlimit und beachten die gewünschte Pause. Zeiten bleiben Näherungen und sind keine manipulationssichere Anwesenheitsmessung. Tages-/Wochentexte werden deterministisch aus gespeicherten Aktivitäten gebildet, ohne erfundene Leistungen oder Diagnosen.

Erinnerungen werden höchstens einmal pro Lerntag als allgemeine In-App-Nachricht erstellt, beachten Zeitzone/Ruhezeit/Pause und enthalten keine sensiblen Inhalte. Keine Push-/E-Mail-Erinnerungen in diesem Stand. Hilfewünsche werden gesammelt in der Familie angezeigt; falsche Einzelantworten lösen keine externen Benachrichtigungen aus.

## Aufbewahrung und Löschung

Testfamilien: 24 Stunden. Materialien, Einheiten/Antworten, Aktivitäten und Nachrichten: höchstens 365 Tage. Abgeschlossene technische Aufträge: 30 Tage. Abgelaufene Sitzungen/Einmallinks: weitere sieben Tage; Rate-Limit-Buckets nach Ende. Lernstand und offene Elternziele bleiben im aktiven Familienkonto bis zur Löschung erhalten. Verbrauchsbuchungen dienen der nachvollziehbaren Kontingentabrechnung; keine vollständigen Inhalte darin. Administrationsprotokolle enthalten Akteur, Aktion, Betriebskennung und Zeitpunkt.

Eltern können Kinder samt Daten/Sitzungen löschen und den Familienexport (JSON + Bilder im ZIP) herunterladen. Löschung des Familieninhabers entfernt dessen Familie einschließlich Kinderkonten und entzieht eingeladenen Eltern Zugriff. Löschung eingeladener Eltern entfernt deren Mitgliedschaften. Datenbank-Fremdschlüssel erzwingen Kaskaden; Dateien werden anschließend entfernt. Sicherungen rotieren nach 14 Tagen. Wiederherstellungen benötigen einen Abgleich zwischenzeitlicher Löschungen; ein belastbarer externer Löschabgleich und Offsite-Sicherungen sind vor Echtbetrieb noch einzurichten.
