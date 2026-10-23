# Kompakte Oberfläche 102 — Routen- und Änderungsinventar

Stand: 23.10.2026. **Implementiert, Abnahmeläufe laufen, noch nicht 102 veröffentlicht.**

Dieser Arbeitsstand erfasst alle **47 konkreten URL-Muster** des Routers in
`app/lib/main.dart`: 40 direkt ausgeschriebene Muster und die sieben einzeln
aufgelösten Authentifizierungsmodi. Die Nummerierung unten zählt jedes Muster
genau einmal. Queryparameter, rollenabhängige Unteransichten und Dialoge sind
keine zusätzlichen Routen. Die Rollenangabe beschreibt den vorgesehenen
Oberflächenkontext; bestehende Routerweiterleitungen und serverseitige Rechte
bleiben maßgeblich.

Das Inventar beruht auf Quellcode und dem aktuellen lokalen Diff. Es ist keine
Behauptung, alle 47 Routen bereits im echten Browser oder mit allen Rollen live
abgenommen zu haben. Test-, Build-, CI-, Vorschau- und Livefreigaben werden nach
Abschluss der laufenden Gates ergänzt. Im gelesenen Zwischenstand sind **44
Produktdateien unter `app/lib`** geändert; der zunächst gemeldete Stand von 43
Dateien ist durch die zusätzliche Verdichtung von `ai_cost_panel.dart` erweitert.

## Referenz und Umfang

Die erneute angemeldete simpleclub-Referenzprüfung durch Root umfasste die
[Startseite](https://app.simpleclub.com/home) am Desktop bei **1280 × 800 px** und
mobil bei **390 × 844 px**, außerdem die mobile Bibliothek. Der mobile
Lernplandialog wurde betrachtet und abgebrochen. Es wurden dabei keine Pläne
oder Referenzassets gespeichert. Daraus übertragen werden kompakte Kopfzeilen,
ein klarer nächster Schritt, kurze lokale Such-/Filterbereiche, ruhigere Karten
und geringere dekorative Abstände. Eigene Marke, Schriftdateien, Piktogramme,
Inhalte und Renderer bleiben bestehen. Die Runde ergänzt die frühere
[Gestaltungsbasis](DESIGN_SYSTEM.md); sie ist keine vollständige Übernahme des
simpleclub-Produkts oder seiner Aufgaben.

## Gemeinsame Grundlage

- `ui.dart`: Seitentitel 24 px mobil beziehungsweise 28 px am Desktop;
  Abschnittsüberschriften 18 px, größere Zwischenräume auf einen Rhythmus von
  12/16/20 px verdichtet. `Panel` und `ActionPanel` erhalten standardmäßig
  16 px Innenabstand unter 720 px, sonst 18 px, sowie Radius 16 px. Explizite vom Standard abweichende
  Innenabstände bleiben erhalten.
- Eingabefelder, Karten, Dialoge und Buttons verwenden die gemeinsame ruhigere
  Form. Buttons behalten mindestens 48 px große Trefferflächen und dürfen bei
  großer Schrift wachsen. Die lokale Nunito-Schrift und natürliche
  Textskalierung bleiben erhalten; Dichte entsteht nicht durch eine
  TextScalerbegrenzung.
- Der Browserrahmen bündelt Bereichsnavigation und Tastaturzugang im vorhandenen
  Kopf, statt eine weitere Inhaltszeile davor zu stapeln. Rail, Rollenwechsel,
  Fokuswege und die geschützte untere mobile Freifläche bleiben erhalten.
- `ChildSectionHero`, `ParentWorkspaceHero`, `AdminWorkspaceHeader` und deren
  Abschnitts-/Aktionsbausteine verwenden kleinere Titel, Dekoration und Abstände.
  Sie wirken auch auf Routen ohne individuellen großen Umbau.
- Neue Filter-Disclosures in Eltern-/Betriebslisten sind lokal. `maintainState`
  erhält Eingaben; `ExcludeFocus` sperrt geschlossene Formularbereiche. Der
  gepinnte Flutter-Baustein stellt vollständig geschlossene Inhalte zusätzlich
  mittels `Offstage` aus Darstellung, Trefferprüfung und Semantikbaum. Das
  Auf-/Zuklappen selbst sendet keinen Request. Aktive Filter und Ergebnisse
  bleiben außerhalb beziehungsweise in der Zusammenfassung erkennbar.

## Vollständiges Routeninventar

| Nr. | Rolle / Kontext | URL-Muster | Screen | Konkrete Änderung in 102 oder gemeinsamer Rahmen |
| --- | --- | --- | --- | --- |
| 01 | Elternanmeldung | `/auth/google/start` | `GoogleCompletionScreen(start: true)` | Kein individueller Flowumbau; gemeinsame Typografie, Felder, Buttons und Karten aus `ui.dart`. Google-/Code-/Rückkehrprüfungen bleiben bestehen. |
| 02 | Elternanmeldung | `/auth/google/complete` | `GoogleCompletionScreen` | Derselbe gemeinsame Themenrahmen; vorhandene Callback-, Sitzungs- und Verknüpfungszustände bleiben lesbar und unverändert. |
| 03 | Ersteinrichtung mit Installationsfreigabe | `/setup` | `InstallationScreen(initial: true)` | Einstiegspolster 18 px statt 24, Markenabstand 20 statt 36 px, Schritte/Formularabschnitte mit 12/16 px statt 20/24 px; Freigabe und bewusster Abschluss bleiben erforderlich. |
| 04 | Administration | `/admin/settings` | `InstallationScreen(initial: false)` | Kompakter `AdminWorkspaceHeader`, 16 px Abstand zum Inhalt und 12/16-px-Formularrhythmus; Provider-/Mail-/Einrichtungsentwürfe und Prüfaktionen bleiben erhalten. |
| 05 | Öffentlich | `/` | `LandingScreen` | Überschrift 24/28 px statt 42/64, kürzere Kopf-/Bereichsabstände, Vorschaufläche Radius 16 und 20 px Polster; reale Anmeldung, Demo und Testbedingungen bleiben erreichbar. |
| 06 | Öffentlich / Eltern, Web | `/angebote` | `OffersScreen` | `StoreSection` mit 28-px-Preisen statt 38, 12/16/20-px-Abständen und ruhigerem Zeilenmaß; Tarif-, Laufzeit- und Testhinweise bleiben vollständig. |
| 07 | Öffentlich / Vertragsinformation | `/bedingungen` | `OffersScreen(terms: true)` | Gemeinsamer kompakter Store-/Text-/Kartenrahmen; Vertragstexte und vorhandene Zustandskennzeichnung werden nicht gekürzt. |
| 08 | Angemeldeter Webzugang für Bestellung | `/bestellen/:id` | `CheckoutScreen` | Gemeinsame Store-/Formulartypografie und kompakter Panelrahmen; konkrete Bestellung, Bestätigung und Berechtigungen bleiben unverändert. |
| 09 | Angemeldeter Webzugang | `/bestellungen` | `OrdersScreen` | 16 statt 24 px Abstand vor Listeninformationen und gemeinsamer Kartenrahmen; Ausschnittsgrenze, Status und Aktionen bleiben erkennbar. |
| 10 | Administration | `/admin/verkauf` | `StoreAdminScreen` | 16-px-Abstände um Kontextreiter/Formgruppen, gemeinsame kompakte Storekarten und Adminüberschrift; bestehende Formularentwürfe und bewusste Speicherschritte erhalten. |
| 11 | Administration | `/admin/push` | `PushAdminScreen` | Kompakter Adminkopf, 16 statt 28 px Anfangsabstand und 12 statt 20 px zwischen mobilen Gruppen; Versand-/Geräte-/Fehlerzustände bleiben sichtbar. |
| 12 | Öffentlich / Anmeldung | `/login` | `AuthScreen(mode: login)` | Formularaußenabstand 16 statt 22 px, interne Abstände 16 px und gemeinsames Felddesign; Passwort-/Google-/Weiterleitungslogik unverändert. |
| 13 | Öffentlich / Registrierung | `/register` | `AuthScreen(mode: register)` | Derselbe kompakte Formularrahmen; Testangebot, Bedingungen, E-Mail-Bestätigung und bewusste Registrierung bleiben erhalten. |
| 14 | Öffentlich / Wiederherstellung | `/recovery` | `AuthScreen(mode: recovery)` | Derselbe 16-px-Rahmen und natürliche große Schrift; Wiederherstellungsaktion und Rückmeldung unverändert. |
| 15 | Öffentlich / Bestätigung erneut senden | `/resend` | `AuthScreen(mode: resend)` | Derselbe kompakte Formular-/Hinweisrahmen; vorhandene Versand- und Rückmeldebedingungen bleiben erhalten. |
| 16 | Öffentlich / Passwort zurücksetzen | `/reset` | `AuthScreen(mode: reset)` | Gemeinsame kompakte Eingabeflächen; vollständige Link-URI, Einmalcode und Passwortprüfung bleiben unverändert. |
| 17 | Öffentlich / E-Mail bestätigen | `/verify` | `AuthScreen(mode: verify)` | Gemeinsamer kompakter Formularrahmen; Code-/Link-, Lade-, Fehler- und Erfolgszustände bleiben unverändert. |
| 18 | Einladung | `/invite` | `AuthScreen(mode: invite)` | Gemeinsamer kompakter Formularrahmen; vorhandene Einladungs-/Code-/Kontozuordnung bleibt bindend. |
| 19 | Kinder / Eltern; Admin wird weitergeleitet | `/app` | `DashboardScreen` | Kind: 24/28-px-Begrüßung, kompakter echter nächster Schritt, Suche und flachere Werkzeug-/Zeitzeilen mit integriertem Themenwechsel. Eltern: kleinere Kinderidentität, 16/20-px-Abstände und gemeinsamer Elternkopf. |
| 20 | Kinder / Eltern | `/messages/:id` | `MessagesScreen`, beim Kind `ChildMessagesHub` | 16-px-Abstände zwischen Kopf, Reitern und Inhalt statt 20/24; gemeinsame kompakte Aktionszeilen, vorhandene Nachricht-/Hilfewunschaktionen unverändert. |
| 21 | Kinder / Eltern | `/child/:id` | `ChildDetailScreen` | Kind nutzt den kompakten Heuteinhalt. Eltern erhalten flachere Ergebniszeilen, 24-px-Zähler, kompakte einspaltige Kategoriezeilen mit vollständiger Kartenaktion, kleinere Kinder-/Kontextnavigation, lokale Verlaufsfilter und bewusst aufklappbare kompakte KI-Details mit gespeichertem Status/Datum; Quellen- und Antwortbelege bleiben getrennt. |
| 22 | Kinder / berechtigte Elternansicht | `/after-school/:id` | `SchoolDayScreen` | Foto-, Prüfung-, Vorbereitungs- und Paketabschnitte mit 16 statt 20/24 px, Radius 16 an der Fotofläche; Upload, Unsicherheiten und ausdrückliche Quellenbestätigung bleiben erhalten. |
| 23 | Kinder / berechtigte Elternansicht | `/after-school/:id/history` | `SchoolDayHistory` | Kompakter gemeinsamer Seitenkopf/Panelrahmen und 16 statt 20 px im Lade-/Rückwegabschnitt; echte Tagesgruppen und Pagination unverändert. |
| 24 | Kinder / berechtigte Elternansicht | `/library/:id` | `CollectionScreen`, `NotebookShelf` | Filterdialog 16 px; Fachliste mindestens 72 statt 80 px. Bewusste Kachelansicht 176/196 statt 244/280 px Basishöhe mit Skalierungszuwachs; echte Seitenzahlen und Öffnen erhalten. |
| 25 | Kinder / berechtigte Elternansicht | `/library/:id/subject/:subjectId` | `NotebookScreen` | 16-px-Dialogpolster und Radius 16; gemeinsame kompakte Kopf-/Filter-/Kartenbasis. Eigene Fotos, Blättern, Suche und gespeicherte Ansicht bleiben unverändert. |
| 26 | Eltern | `/parent-plan/:childId` | `ParentPlanScreen` | 18-px-Unterabschnittstitel statt 20, 12-px-Abstände vor Filtern/Inhalt; kompakter Elternkopf und Kinderkontext. Vorschlag, Auftrag und Termin bleiben getrennt. |
| 27 | Eltern | `/parent-homework/:childId` | `ParentHomeworkScreen` | Mobile Suche/Filter in lokaler Disclosure; aktive Filter, Selbstangabenwarnung und Ergebnisse bleiben sichtbar. Controller, gespeicherte Ansichten und reine Listenabrufe erhalten. |
| 28 | Kinder / berechtigte Elternansicht | `/homework/:childId` | `HomeworkScreen` | Gemeinsamer kompakter `ChildSectionHero`, Reiter-/Panel-/Aktionsrahmen; vorhandene Aufgaben, Fotos und Statusbezeichnungen bleiben vollständig. |
| 29 | Kinder / berechtigte Elternansicht | `/homework/:childId/:materialId` | `HomeworkDetailScreen` | 16 statt 20 px vor eigener Frage und gemeinsame kompakte Hilfs-/Formularkarten. Antworten, Entwürfe, Häkchenbedeutung und Hilfefreigaben unverändert. |
| 30 | Kinder / berechtigte Elternansicht | `/learn/:id` | `CollectionScreen(learning: true)` | Gemeinsamer kompakter Lernkopf und Kartenrahmen, 16-px-Filterdialog sowie kleinere Ladepolster; gespeicherte Runden und vorhandene Such-/Statusfilter erhalten. |
| 31 | Kinder / berechtigte Elternansicht | `/material/:id/processing/:jobId` | `MaterialProcessingScreen` in `material_actions.dart` | Kein individueller Ablaufumbau; gemeinsame kompakte `PageFrame`-/Panel-/Buttonbasis. Bestehende GET-Statusansicht startet keinen neuen Erkennungsauftrag. |
| 32 | Kinder / berechtigte Elternansicht | `/material/:id` | `MaterialScreen`, `MaterialReview` | 16-px-Abstände an Lernaktionen und gemeinsamer Rahmen. Der bereits kompakte feste 101-Quellenleser mit eigenem Inhaltsscrollbereich bleibt bewusst unverändert. |
| 33 | Kinder / berechtigte Elternansicht | `/progress/:id` | `ProgressScreen` | 16 statt 24 px zwischen Kopf, Belegtext und Abschnitten; kompakte gemeinsame Titel/Flächen. Kategorien, tatsächliche Versuche und Hilfen bleiben unverändert. |
| 34 | Eltern | `/grades/:id` | `GradesScreen` | 16-/12-px-Abschnittsrhythmus, Notenwert 20 statt 23 px und kompakte Kindernavigation. PDF-Importdialog zusätzlich 16-px-Polster/20-px-Titel; lokale PDF-Prüfung unverändert. |
| 35 | Kinder / berechtigter Elternrückblick | `/unit/:id` | `UnitScreen`, `LearningRoom` | Nur Neben-/Hilfstitel 20 px, Sprachcue 22 px und Feedbackpolster 16 px. Offene Aufgabenfläche, 20-px-Prompt, 17-px-Lesetext, Antwortkarten, Footer und 101-Retry-/Introguards bleiben bestehen. |
| 36 | Eltern; Kind wird zur eigenen Sammlung geleitet | `/words` | `FamilyVocabularyScreen` | Gemeinsamer kompakter Seiten-/Kinderkontext-/Panelrahmen; keine neue Wortabfrage, Offenlegung oder Bewertungsregel. |
| 37 | Kinder / Eltern | `/vocabulary/:id` | `VocabularyScreen` | Lesekartentitel 24 statt 28 px, 16-px-Abschnittsabstände und gemeinsamer kompakter Kopf. Aufdecken, bestätigte Wortpaare und bestehende Übungsaktionen unverändert. |
| 38 | Kinder / Eltern | `/language-projects/:id` | `LanguageWorkshop` | 16 statt 20/24 px an Zielwahl, gespeicherten Projekten und Fortsetzung; gemeinsamer kompakter Kopf. Locale, Wortauswahl und bewusster Projektstart unverändert. |
| 39 | Kinder / berechtigte Elternansicht | `/learning-preparation/:childId/:jobId` | `LearningPreparationScreen` | Statussymbol 32 statt 46 px, Statusüberschrift 22 statt 25 px und 16-px-Abstände; Warte-/Fehler-/Wiederaufnahmezustände bleiben vollständig. |
| 40 | Kinder / Eltern / Administration | `/settings` | `SettingsScreen`; Kind: `ChildAccount` | Kind: 16-px-Abschnittsabstände und kompakte Sharedflächen. Eltern/Admin: 16-px-Gruppenabstände, kompakte Passwortdialoge, bestehende Geräteeinstellungen/Privatsphäre; keine automatische Speicherung. |
| 41 | Kinder / Eltern | `/family-call/:id` | `FamilyCallScreen` | Radius 16 am Videobereich und 16-px-Abstände zwischen Gesprächsgruppen; Medienfreigaben, sichtbares Beenden und Verbindungszustände unverändert. |
| 42 | Kinder / Eltern; Admin wird zum Pushbetrieb geleitet | `/notifications` | `NotificationsScreen` | Lokale Such-/Filter-Disclosure und 12-px-Abstand zur Gerätegruppe. Ungelesenchips, tatsächliche Meldungen und bewusste Lesemarkierung bleiben erhalten. |
| 43 | Administration | `/admin` | `AdminScreen` | Kompakter gemeinsamer Betriebskopf, 16-/12-px-Gruppenabstände, lokale Familienlistenfilter und verdichtete Kosten-/Routingkarten. Notfallstopp und bewusste Betreiberaktionen bleiben erhalten. |
| 44 | Administration | `/operator-incidents` | `OperatorIncidentsScreen` | Suche/Fehlerfilter lokal einklappbar, Ergebnisse bleiben sichtbar; Detailabstand 12 statt 20 px und gemeinsamer Betriebskopf. Reparatur-/Bestätigungs-/Snapshotguards unverändert. |
| 45 | Öffentlich | `/privacy` | `InformationScreen(kind: privacy)` | Außenpolster 16 statt 24 px und gemeinsamer ruhiger Text-/Panelrahmen; vollständige Datenschutzabschnitte und vorhandene Auswahl bleiben erhalten. |
| 46 | Öffentlich | `/about` | `InformationScreen(kind: about)` | Außen-/Abschnittsabstände 16 statt 24 px, gemeinsame kompakte Typografie und Karten; vorhandene Funktions- und Rechtshinweise bleiben vollständig. |
| 47 | Öffentlich / berechtigter Elternweg | `/account-deletion` | `AccountDeletionScreen` | Außenpolster und Informationsabstände 16 statt 24/20 px; Löschumfang, Aufbewahrung, Passwortbedarf und bewusster Weg zur Datenverwaltung bleiben erhalten. |

## Unteransichten und bewusst erhaltene Arbeitsflächen

Die 47 Routen enthalten weitere sichtbare Arbeitsflächen. Auch diese sind im
Änderungsumfang berücksichtigt, ohne sie als zusätzliche URL-Muster zu zählen:

- Eltern: Kinderwahl und -navigation, Profil-/Auftragsdialoge, Ergebnisübersicht,
  Lernkompass und Aktivitätsverlauf werden durch `parent_child_picker.dart`,
  `parent_child_navigation.dart`, `parent_profile_dialog.dart`,
  `parent_assignment_dialog.dart`, `parent_overview.dart`,
  `parent_insights_panel.dart` und `parent_activity_timeline.dart` verdichtet.
  Der kompakte KI-Lernkompass startet geschlossen mit tatsächlichem Status und
  gespeicherten Datum; die große eigenständige Ansicht bleibt geöffnet. Das
  lokale Öffnen erzeugt keinen neuen KI-Auftrag.
- Administration: Verkaufsformulare, Betriebs-/Auditdialoge sowie Kosten- und
  Routingkarten nutzen kleinere Überschriften und Innenabstände in
  `store_screens.dart`, `parent_operator_audit.dart`, `settings_screen.dart` und
  `ai_cost_panel.dart`. Die lokalen Filter-Disclosures verbergen keine
  Fehler-/Betriebsresultate und ersetzen keine Bestätigung einer Änderung.
- Lernhilfe: `tutor_sheet.dart` verwendet 16 px Innenraum und 20 px Kopftitel;
  fachliche Antworten bleiben mit 17 px und Zeilenhöhe 1,5 lesbar. Die
  bereits vorhandenen Lern-/Quellenrenderer werden nicht durch eine neue
  kompaktere Fachlogik ersetzt.
- Öffentlicher Testzugang: `public_trial.dart` strafft nur den Abstand vor der
  bewussten Aktion; Laufzeit, E-Mail-Start, fehlende automatische Verlängerung
  und Kontingenthinweise bleiben lesbar.
- `notification_inbox.dart` ist ein Zustands-/Cachebaustein ohne eigene
  Oberfläche und bleibt unverändert. Die sichtbaren Neuigkeiten und
  Geräteoptionen liegen in `notification_panel.dart`.
- Der gute 101-Quellenleser bleibt mit festem Header/Werkzeugbereich und separat
  scrollendem Dokument erhalten. Ebenso bleiben Aufgaben-/Erklärungskörper,
  Formeln, Antwortkarten, feste Hauptaktion/Hilfe und der bewusste Abschluss der
  Lernrunde bestehen. 102 verkleinert dort nur unterstützende Metadaten und
  Kartenabstände.
- Die Router-Fehleransicht ist kein zusätzliches URL-Muster. Ihr bestehender
  Rückweg bleibt erhalten und erhält die gemeinsame Buttongestaltung.

## Abnahmegrenzen und laufende Nachweise

Die neue Darstellung wird in den fokussierten Dateien
`compact_workspace_102_test.dart`, `today_density_102_test.dart`,
`compact_child_pages_102_test.dart`, `management_density_102_test.dart`,
`compact_admin_queue_102_test.dart`, `parent_insights_compact_102_test.dart` und
`parent_practice_rows_102_test.dart` sowie
passenden Bestandsregressionen geprüft. Dazu gehören tatsächliche Seiten- und
Dialoginteraktionen, 320/390-px-Ansichten, große Schrift und unveränderte
bewusste Aktionen. Die Abnahmeläufe sind beim Anlegen dieses Dokuments noch
nicht vollständig abgeschlossen. Einzelne zwischenzeitlich grüne Läufe sind
keine vollständige Releasefreigabe.

Das Today-Ziel einer deutlich kleineren Hauptkarte, unter anderem die
ungefähr 220-px-Obergrenze bestimmter Testfixtures bei normaler Schrift, ist ein
**Prüfziel**, hier kein behauptetes Messergebnis. Lange echte Titel und große
Schrift dürfen natürliche zusätzliche Höhe und Scrollen benötigen. Die
Gesamtseiten werden nicht über abgeschnittene Texte oder verkleinerte
Trefferflächen verdichtet.

Unverändert bindend sind Familien-/Rollen-/Token-/Quellen-/Route-/Lifecycleguards,
Entwürfe, bestehende Antworten, explizite Quellenbestätigung und Feedback-ACK,
Hilfenutzung, Bewertung, Lernzeit, Mindestziele, Providerreservierungen und
Kontingente. Reine Listen-/Suchabrufe bleiben lesend; Darstellung oder
Disclosurezustand darf keine neue KI, automatische Antwortprüfung oder
Speicherung auslösen. Es wurden keine Backend- oder Antwortverträge für diese
Gestaltungsrunde geändert.

Root ergänzt nach den laufenden Gates die konkreten Logs/Ergebnisse,
Vorschau-/Browserbelege sowie erst nach erfolgreicher Veröffentlichung die
Quellen-, Versions- und Livebindung. Bis dahin bleibt der oben genannte Status
maßgeblich.
