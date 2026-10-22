# Zweite zusätzliche Runde – gemeinsame Bedienung

**55 eigenständige umgesetzte Maßnahmen** gegenüber `3df2849`; die früheren321 sind ausgeschlossen. Fünf gekoppelte Unterfälle werden nicht zusätzlich gezählt. RR046 ist eine nicht umgesetzte Idee und zählt nicht.

Abschlussstand: **1.21.1+89** ist als Release `20261022T134524Z-03e3bfe` aus Quellcommit `03e3bfeffd654ff169ebf2daceb6537476cadf03` ausgeliefert. Die automatisierten Verhaltenstests verwenden synthetische Daten und Mock-Transporte; Kategorien im Lernstand wurden zusätzlich gegen isoliertes PostgreSQL geprüft. Die abschließende Browserprüfung verwendete ausschließlich die eigene künstliche Familie. Keine Änderung an Providerfreigaben, Reservierungen, Quoten oder privatem Inhaltszugriff.

| ID | Änderung | Konkrete Stelle | Verhaltenstest | Status |
|---|---|---|---|---|
| RR001 | Gemeinsame Aktionskarte mit klarer Zielzeile, ganzer Trefferfläche, Tastatur/Fokus und begrenzter Aktivierung | ui.dart: ActionPanel / _ActionPanelState | action_panel_ux88_test.dart | tested |
| RR002 | Öffentliche Stoff-sammeln-Karte erklärt den tatsächlichen Foto-/Bestätigungsweg | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR003 | Öffentliche Verstehen-und-üben-Karte führt zur Erklärung der betreuten Runde | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR004 | Öffentliche Wiederholkarte öffnet die Erklärung belegbasierter Wiederholung | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR005 | Öffentliche Tagesplankarte erklärt Vorschlag, Elternauftrag und aktive Zeit | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR006 | Öffentliche Hilfekarte erklärt die gestuften Hilfen und selbstständige Anwendung | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR007 | Öffentliche Elternkarte erklärt nachvollziehbare Aufgabenbelege statt unbelegter Kompetenzzahlen | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR008 | Betreiber-/Kontaktangaben zeigen Laden, sichere Fehlermeldung und bewussten Lese-Retry | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR009 | Darstellungswechsel lädt Betreiberangaben nicht erneut | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | coupled → RR008 |
| RR010 | Eltern gelangen aus Löschinformationen zuerst zur Daten-/Exportverwaltung | account_deletion_screen.dart: AccountDeletionScreen | public_cards_ux88_test.dart | tested |
| RR011 | Direkt geöffnete Löschseite besitzt einen eindeutigen Rückweg | account_deletion_screen.dart: AccountDeletionScreen | public_cards_ux88_test.dart | tested |
| RR012 | Neuigkeiten lassen sich lokal gezielt nach ungelesen filtern | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR013 | Leerer Ungelesen-Filter bietet den sichtbaren Rückweg zum geladenen Verlauf | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | coupled → RR012 |
| RR014 | Mehrfaches Öffnen einer Neuigkeit löst nur eine aktive Lesemarkierung aus | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR015 | Spät gespeicherte Lesemarkierung verdrängt keine danach geöffnete Seite | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR016 | Bereits gelesene Neuigkeit schreibt dieselbe Lesemarkierung nicht nochmals | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR017 | Offene Neuigkeitenaktion und Filter werden beim Kontowechsel verworfen | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | coupled → RR012 |
| RR018 | Glocke und Neuigkeiten benennen das tatsächliche fachliche Linkziel | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR019 | Datenschutzhinweis verspricht keine veralteten kostenlosen OpenRouter-Modelle | auth_screens.dart: LandingScreen / InformationScreen | public_cards_ux88_test.dart | tested |
| RR020 | Lernstandkategorien öffnen und filtern tatsächlich passende beantwortete Aufgaben vor Aggregation | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | tested |
| RR021 | Gespeicherte alte Lernstandkarten können keine veränderte Übersicht mehr steuern | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | tested |
| RR022 | Lernstand lädt nur unter genauer aktueller Konto-/Familienbindung | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | tested |
| RR023 | Lernstand merkt sich die tatsächlich serverseitig begrenzte Listenseite | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | tested |
| RR024 | Rundendatum im Lernstand benennt den letzten Übungszeitpunkt korrekt | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | tested |
| RR025 | Alter Server ohne Kategorienunterstützung zeigt keinen ungefilterten Bestand als gefiltert | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | coupled → RR020 |
| RR026 | Leere Lernstandkategorie lässt sich ausdrücklich wieder verlassen | progress_screen.dart: ProgressScreen; backend/schulpilot/learning_progress.py: read_ledger / learning_progress | progress_cards_ux88_test.dart; backend/tests/test_practice_progress.py | coupled → RR020 |
| RR027 | Android-Download startet durch die ganze Karte mit laufendem Aktivierungsstatus | download_panel.dart: AndroidDownload | workspace_download_cards_ux88_test.dart | tested |
| RR028 | Wechsel der API lädt die dazugehörigen Downloadmetadaten neu | download_panel.dart: AndroidDownload | workspace_download_cards_ux88_test.dart | tested |
| RR029 | Registrierung erlaubt Datenschutzlesen mit Rückkehr zum unveränderten Entwurf | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR030 | Offensichtlich fehlerhafte Eltern-E-Mail wird vor unnötigem Versand korrigierbar erkannt | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR031 | Geheime Zugangs-/Betriebsfelder deaktivieren Smart Quotes/Dashes und Tastatur-Personalisierung | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR032 | Einmalcode lässt sich bewusst ansehen und wird bei neuem Link wieder verdeckt | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR033 | Vergessener Kinderzugang führt zur passenden Hilfe über berechtigte Eltern | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR034 | Wiederherstellung besitzt einen sichtbaren Weg zur manuellen Codeeingabe | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR035 | Fehlender Bestätigungslink ist über den bestehenden begrenzten Versandweg erneut anforderbar | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR036 | Abgelaufener Reset besitzt einen neuen Wiederherstellungsweg ohne alten Code | auth_screens.dart: AuthScreen; google_login.dart; settings_screen.dart / installation_screen.dart | auth_recovery_ux88_test.dart | tested |
| RR037 | Anrufansicht und verspätete Metadaten bleiben an genaue Sitzung/Familie gebunden | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR038 | Bloßes Laden eines Anruflinks lehnt keinen Anruf ab und startet keine Aufnahme | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR039 | Fehlgeschlagene Anruf-Metadaten bieten einen ausdrücklich rein lesenden Retry | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR040 | Alter Anruflink führt zum tatsächlich bereits geöffneten Gespräch | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR041 | Nach beendetem Elternanruf führt eine Aktion zur richtigen privaten Kindernachricht | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR042 | Überholte Familienhilfe-/Medienbestätigungen schließen ausschließlich ihre eigene Route | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart; family_call_dock_test.dart | tested |
| RR043 | Gespeicherte alte Gesprächssteuerung kann kein neueres Gespräch beenden oder verändern | family_call_screen.dart; family_call_service.dart: open | family_call_continuity_ux88_test.dart | tested |
| RR044 | Rollenlogo und Kopfpfad bieten einen klaren Rückweg zur jeweiligen Übersicht | ui.dart: WorkspaceShell / _WorkspaceSidebar / _WorkspaceRail / _WorkspaceHeader | workspace_download_cards_ux88_test.dart | tested |
| RR045 | Sidebar, Rail und mobile Menüaktionen verwerfen überholte Konto-/Familienklicks | ui.dart: WorkspaceShell / _WorkspaceSidebar / _WorkspaceRail / _WorkspaceHeader | workspace_download_cards_ux88_test.dart | tested |
| RR046 | Wissenschaftliche Grafikvergrößerung wurde erwogen, hier nicht implementiert | nicht geändert | kein Nachweis | not_implemented |
| RR047 | Neuigkeiten benennen Server-Zeitfenster, Listenbegrenzung und Umfang der Glockenvorschau | notification_panel.dart: NotificationsScreen; ui.dart: NotificationBell; notification_inbox.dart | notification_cards_ux88_test.dart | tested |
| RR048 | Materiallösch-/OCR-Bestätigung ist zusätzlich an die ausgewählte Familie und sichtbare Ursprungsroute gebunden | material_actions.dart: _confirmAccountAction / deleteNotebookPages / deleteLearningRound / reprocessNotebookPage | private_context_cards_ux88_test.dart | tested |
| RR049 | OCR-Status nimmt keine späte alte Sitzungsantwort in den neuen Kontext auf | material_actions.dart: MaterialProcessingScreen | private_context_cards_ux88_test.dart | tested |
| RR050 | OCR-Status folgt beim Widgetwechsel der tatsächlich neuen Material-/Auftragsreferenz | material_actions.dart: MaterialProcessingScreen | private_context_cards_ux88_test.dart | tested |
| RR051 | Private Fotodaten werden bei Familien-/Sitzungswechsel vor neu authentifiziertem Lesen verworfen | notebook_photo.dart: NotebookPhoto / zoomNotebookPhoto | private_context_cards_ux88_test.dart | tested |
| RR052 | Fotoansicht übernimmt eine neue AppState/API-Instanz und entfernt alte Listener | notebook_photo.dart: NotebookPhoto / zoomNotebookPhoto | private_context_cards_ux88_test.dart | tested |
| RR053 | Gespeicherte alte Zoom-/Retry-Aktionen verändern keine andere private Seite | notebook_photo.dart: NotebookPhoto / zoomNotebookPhoto | private_context_cards_ux88_test.dart | tested |
| RR054 | Vollbildfoto schließt beim Kontextwechsel ausschließlich die eigene Route | notebook_photo.dart: NotebookPhoto / zoomNotebookPhoto | private_context_cards_ux88_test.dart | tested |
| RR055 | Fachauswahl schließt bei Familienwechsel und alte Schließen-Aktion verdrängt keinen neuen Dialog | subject_picker.dart: SubjectField / _SubjectChoices | private_context_cards_ux88_test.dart | tested |
| RR056 | Bisher gewähltes Fach steht unabhängig von der alphabetischen Position zuerst; die bestehende Auswahlsemantik bleibt erhalten | subject_picker.dart: SubjectField / _SubjectChoices | private_context_cards_ux88_test.dart | tested |
| RR057 | Lernvorbereitung verwirft gespeicherte Ergebnisse bei Familienwechsel | learning_preparation_screen.dart: LearningPreparationScreen | private_context_cards_ux88_test.dart | tested |
| RR058 | Überdeckte Vorbereitungsseiten pollen beim Wiederöffnen der App nicht im Hintergrund | material_actions.dart / learning_preparation_screen.dart: didChangeAppLifecycleState | private_context_cards_ux88_test.dart | tested |
| RR059 | Geladene Neuigkeiten lassen sich lokal nach Titel und Zieltext durchsuchen; Lesemarkierung betrifft nur angezeigte Treffer | notification_panel.dart: NotificationsScreen | notification_cards_ux88_test.dart | tested |
| RR060 | Eltern können ihre geladenen Neuigkeiten auf ein bestimmtes Kind eingrenzen | notification_panel.dart: NotificationsScreen | notification_cards_ux88_test.dart | tested |
| RR061 | Geladene Neuigkeiten lassen sich gezielt nach Anlass wie Hilfewunsch oder Live-Gespräch eingrenzen | notification_panel.dart: NotificationsScreen | notification_cards_ux88_test.dart | tested |

Die gemeinsame Aktionskarte zählt einmal, einschließlich ihrer Tastatur-, Fokus-, Semantik-, Schriftgrößen-, Busy- und Fehlerbehandlung. Native/Web-Varianten oder mehrere Kategorien werden nicht als weitere Maßnahmen gezählt. Formularkarten und Bereiche mit mehreren getrennten Aktionen behalten bewusst getrennte Bedienelemente.

Frühere Prüflogs: `artifacts/ux88/root-new-combined.log` (Vorversuch), `public-cards-final.log`, `preparation-covered-verified.log`, `progress-backend-tests.log`. Fehlgeschlagene Vorversuche bleiben erhalten; maßgeblich sind die abgeschlossenen Nachweise unten.

Nachweis Neuigkeitensuche/-filter: `artifacts/ux88/notification-filters-verified.log`,35/35 inklusive Regressionen.

## Gemeinsamer Abschluss für 1.21.1+89

- Vollständiger nativer Flutterlauf: **2009 bestanden**, fünf ausschließlich webrelevante Fälle übersprungen; `artifacts/ux89/flutter-final.log`. Vollständige Analyse ohne Befund: `artifacts/ux89/flutter-analyze-final.log`.
- Vollständiges Backend auf isoliertem PostgreSQL16: **1593 bestanden**; `artifacts/ux88/backend-full.log`. Im Backend wurde danach nur die Versionsnummer geändert. Überlappende Bereichs- und Gesamttests werden nicht addiert.
- Signierte APK und Play-AAB, tatsächliche Version, festgelegter Signierer und fehlende Play-Installerberechtigung bestätigt: `artifacts/ux89/release-check.json`. Öffentlicher APK-Download sowie ausgeliefertes JavaScript stimmen in Hash und Größe mit den lokalen Dateien überein: `artifacts/ux89/public-check.json`, `artifacts/ux89/web-check.json`.
- Tatsächlicher Browser89, ausschließlich eigene künstliche Familie: Kindersitzung überlebt Neuladen; die Eltern-Lernzeitkarte besitzt Rolle `button`, erhält die genauen Zeitziele und öffnet die ausgewählte Wochenansicht. Beide Rollen wurden regulär abgemeldet: `artifacts/ux89/browser-checks.json`.
- Eigene künstliche Familie über den normalen Löschweg bereinigt; beide Anmeldungen danach mit401 abgewiesen, alte Sitzung widerrufen. Keine externen KI-Aufrufe und kein Pushversand: `artifacts/ux89/cleanup.json`.
- GitHub-Lauf [39772352507](https://github.com/meinzeug/schulpilot/actions/runs/39772352507) startete Flutter und Backend wegen einer Billing-Kontosperre nicht. Dies ist kein erfolgreicher gehosteter CI-Lauf; die lokalen Abschlussnachweise stehen oben. Quelle: `artifacts/ux89/github-ci-source.json`.

Die Browsernachkorrektur der dekorativen Fortschrittsrollen in89 und zusätzliche Negativfälle bleiben bestehenden Maßnahmen zugeordnet; die Zahl55 steigt dadurch nicht. Der Browserbeleg ist begrenzt auf die eigene synthetische Familie und die dokumentierten Wege. Er ersetzt keine vollständige Screenreader-/WCAG-Abnahme, neue physische Androidabnahme, Live-Providerprüfung oder Pushzustellbeobachtung. Der übergreifende Abschluss steht in [UX_300_ROUND2_2026_10_22.md](UX_300_ROUND2_2026_10_22.md).
