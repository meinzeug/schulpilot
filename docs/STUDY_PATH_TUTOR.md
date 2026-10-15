# Lernreise und Fragen zum Heft

Ab 1.1.0 ist das erste Tagespaket eine Einstiegsrunde. Der gesamte Lernweg wird aus allen bestätigten Seiten geplant: zwei Aufgaben bei sehr kurzen Seiten, mindestens vier bei normalem Textumfang, bei höherer Wortdichte bis zwölf je Seite, höchstens 120 geplante Aufgaben. Die Transkription stammt aus der Bilderkennung; die Wortzahl ist ein nachvollziehbares Umfangssignal und keine Aussage über jeden Inhalt einer fotografierten A4-Seite. Bereits erzeugte, quellenaktuelle Runden zählen mit ihren tatsächlichen Fragen mit. Vorhandene Antworten bleiben erhalten.

Weitere Aufgaben entstehen in kleinen Etappen von zwei bis fünf Fragen: Verstehen, Fehlerdetektiv, Anwenden und Erinnern. Jede Etappe benötigt eine bewusste Aktion, eine atomare Kontingentreservierung und eine validierte KI-Antwort. Geplante Aufgaben sind ausdrücklich noch nicht erzeugt. Fehlversuche, Hinweise und KI-Rückblicke führen daneben zum gezielten Nachlernen; spätere Abrufproben verwenden die bestehenden mehrtägigen Fortschrittskriterien. Kein Beherrschungsversprechen, keine erfundenen Leistungen.

Jede weitere Etappe erhält wörtliche Abschnitte aus den bestätigten Quellen und konkrete unterschiedliche Denkaufträge. Ein einfacher Wortvergleich priorisiert bisher wenig abgefragte Passagen; er beweist keine vollständige fachliche Abdeckung. Bereits gestellte Fragen sind ausdrücklich ausgeschlossen. Identische Fragen innerhalb derselben Etappe und normalisierte Wiederholungen vorhandener Tagesfragen werden verworfen, niemals durch Vorlagen ersetzt.

Die Etappe „Erinnern“ startet direkt mit Fragen. Ihre Erklärung wird erst auf ausdrückliche Hilfe oder nach Abschluss sichtbar; angeforderte Erklärung zählt als Unterstützung. Die Quellen- und Elternvorgaben gelten dabei ebenso wie bei den anderen Etappen. So wird eine Abrufübung nicht bereits durch die vorgeschaltete Lösung aufgelöst.

Elternaufträge, Fachlerntage, verfügbare Tages-/Wochenzeit und Pausen bestimmen die Fortsetzung. Was heute nicht passt, bleibt gespeichert. Versäumte Tage erhöhen die Aufgabenanzahl nicht. Quellenänderungen markieren die Lernreise als veraltet; ausdrückliches Neuplanen erhält vorhandene Antworten. Vergangene Tage dürfen weiter gelernt werden, ihre Fotozusammenstellung bleibt schreibgeschützt.

Die Seitenansicht, eine fertige Einheit und das Tagespaket bieten „Frag nach“. Eine Frage bezieht sich auf genau einen eigenen Schultag, eine eigene Einheit oder eine einzelne bestätigte Seite. Der Worker verwendet nur diesen Stoff und höchstens vier vorherige Rückfragen. Antworten enthalten überprüfte Textbelege; nicht belegte Inhalte oder unklare Fragen werden ausdrücklich gekennzeichnet. Berechtigte Eltern sehen den gespeicherten Verlauf. Fragen sind keine zusätzlichen Leistungsnachweise.

Eine erfolgreich beantwortete Heftfrage zählt als genutzte Erklärung für bereits begonnene aktive oder pausierte Einheiten mit denselben bestätigten Quellen. Eine danach richtige Antwort ist damit unterstützt; frühere Antworten und abgeschlossene Einheiten werden nicht rückwirkend verändert. Fehler, reine Klärungsfragen und Antworten außerhalb des Materials erzeugen keine Hilfe-Markierung. Gleichzeitiger Aufgabenabschluss und Quellenlöschung verwenden dieselbe Sperrreihenfolge; das Löschen einer Quelle entfernt auch deren Tutorantworten und Zitate.

Vorlesen und Mikrofon sind freiwillig. Die Geräte-/Browserdienste können Sprache online verarbeiten; vor Aufnahme erscheint ein Hinweis. SCHULPILOT lädt selbst keine Audiodateien hoch und speichert keine. Erkannter Text bleibt vor dem Senden bearbeitbar. Hintergrund, Routenwechsel, Abmeldung und Entfernen der Ansicht stoppen die Sprachsession. Fehlende Dienste blockieren Tippen/Lesen nicht.

## API und Betrieb

- GET `/api/school-days/{day}/study-path`: reine Ansicht ohne Erstellung/KI-Aufruf.
- POST derselben Adresse: explizite, idempotente Plananlage oder Neuplanung.
- POST `/api/school-days/{day}/blocks/{block}` mit Idempotency-Key: nächste Etappe, höchstens drei bewusste Versuche pro Block. Normale `/api/jobs/{id}` liefern Ergebnis und Status.
- POST `/api/children/{child}/tutor/questions` mit Idempotency-Key: Frage und genau ein `day_id`, `material_id` oder `unit_id`; optional `reply_to` im selben Verlauf. GET derselben Adresse mit dem gewählten Scope: paginierter Verlauf für Kind/berechtigte Eltern.
- Keine öffentlichen Tokensende-, Debug- oder Providerendpunkte. Anbieterwechsel, automatische Wiederholungen und freie Demo-Eingaben bleiben gesperrt. KI-Verbrauch pro Funktion/Familie/Kind wird normal erfasst.

Migration `0011` ergänzt `school_days.learning_plan` und `tutor_turns`. Quellen-/Familien-/Sitzungs-/Tarif-/Konfigurationsprüfung erfolgt vor und nach externer Verarbeitung. Widerruf oder Logout verhindert die Übernahme einer noch laufenden Tutorantwort. Physisch entfernte Sitzungen setzen die Historienreferenz auf null; der gespeicherte private Lernverlauf bleibt bis zur regulären Löschung erhalten. Quellenlöschung entfernt zugehörige Tutor-Zitate auch aus Einheiten-/Tagesfragen. Export, Löschjournal/Wiederherstellung und 365-Tage-Aufbewahrung berücksichtigen die neuen Inhalte.

Vor Migration sichern. Ein Code-Rückweg darf die additive Migration stehen lassen; vor dem Wechsel laufende `study_block`, `tutor` und `coach_practice`-Jobs beenden lassen. Alte Worker kennen diese Jobarten nicht. Kein automatisches Datenbank-Downgrade durchführen.

Tests: `backend/tests/test_study_path.py`, `test_tutor.py`, `test_coaching_stages.py`; Flutter `tutor_sheet_test.dart`, `lesson_voice_test.dart` und bestehende Kinderabläufe. Aktuell tatsächlich ausgeführte Abnahmen stehen in [STATUS.md](STATUS.md). Quellen und gepinnte Sprachpakete: [SOURCES.md](SOURCES.md).
