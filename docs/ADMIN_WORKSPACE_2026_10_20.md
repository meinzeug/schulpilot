# Einheitlicher Betriebsbereich

Die Administration ist ein sachliches Operationscockpit in zwei vollständigen
Cyberpunk-Varianten: dunkle Arbeitsflächen mit hellen Texten und eine helle
Variante mit dunklen Texten. Alle eigenen Farben stammen aus `context.palette`;
Farbwechsel verändern keine Daten, fachlichen Fotos oder Berechtigungen.
`AdminWorkspaceHeader` in `app/lib/admin_workspace_ui.dart` verwendet einen
offenen typografischen Kopf. Das kleine lokale Circuitmotiv ist dekorativ und
behauptet weder Leistung noch Telemetrie. Eine zweite globale Linkleiste wurde
entfernt: Die gemeinsame Shell navigiert zwischen Betrieb, Einrichtung, Verkauf
und Push. Unterseiten haben lediglich einen Rückweg zur Betriebsübersicht.
`AdminContextTabs` ordnet die lokalen Arbeitsbereiche einheitlich ein.

## Abgestimmte Gestaltungsentscheidung

Kinderbereich, Elternbereich und Administration wurden zwischen den drei
Designagenten abgestimmt. Gemeinsamer Kern sind die Shell, Typografie,
thematischen Flächen, zugänglicher Fokus sowie die Verbindung aus Zustand,
Bedeutung und nächster Handlung. Die Kinderansicht ist eine Lernstation mit
echtem aktuellem Lernschritt und Fotoeingang; Eltern sehen Lernbelege und
Hilfebedarf. Die Administration priorisiert Betriebsprobleme. Weder erfundene
Lernpunkte noch künstliche Auslastungskurven gehören zu diesem Konzept.

Die offiziellen [Todoist-Funktionen](https://www.todoist.com/features) erläutern
die Trennung zwischen heute relevanter Arbeit, späterer Planung und Details im
Aufgabenkontext. Daraus folgt die Konzentration auf eine aktuelle Handlung.
Der [Linear-Designbericht](https://linear.app/now/how-we-redesigned-the-linear-ui)
beschreibt konsistente Navigation, Ausrichtung und weniger visuelles Rauschen.
Die [Linear-Administrationsüberarbeitung](https://linear.app/changelog/2024-12-18-personalized-sidebar)
trennt Einstellungsbereiche und verwendet filterbare Verwaltungstabellen.
Diese Prinzipien begründen die gemeinsame Hierarchie; es werden keine
Produktgrafiken kopiert. Die Recherche ist keine Nutzbarkeitsstudie mit Kindern.

## Arbeitsbereiche

- **Übersicht:** wartende, laufende und überfällige Aufträge sowie Pushfehler,
  Worker-Signal und offene Löschprotokolle aus dem vorhandenen Betriebsendpunkt.
  Ein ausgeschriebenes Triageband steht vor dem asymmetrischen Auftragsleitstand.
  Fehlendes Worker-Signal bleibt ausdrücklich unbekannt; normale Einzelwerte
  werden nicht als umfassender positiver Gesundheitsstatus ausgegeben. Es gibt
  keine erfundene Verlaufskurve. KI-Steuerung und Aktionszeilen stehen auf großen
  Bildschirmen nebeneinander, auf kleinen untereinander.
  Providerstatus und Formular sind unabhängig von den anderen Bereichen geladen.
  Eine fehlgeschlagene Providerabfrage verdeckt daher weder Betriebswerte noch
  Familienverwaltung oder Notfallstopp.
- **KI-Konfiguration:** vorhandenes revisionsgebundenes Providerformular und
  geprüfter Modellmix. Reiterwechsel erhalten die vorhandenen Formularzustände
  durch `Offstage` und sperren den Tastaturfokus versteckter Bereiche. Öffnen und
  Wechseln speichern, prüfen oder generieren nichts.
  Die ausdrücklich ausgelöste Verbindungsprüfung bezeichnet nun eindeutig die
  gespeicherte Konfiguration und erhält ungespeicherte Werte einschließlich des
  optional eingegebenen Schlüssels im Formular. Sie sendet den Entwurf nicht.
  Die bisherige kostenlose Vorlage steht als optionaler Entwurf unter
  „Andere Vorlage vorbereiten“; sie wird nicht als aktiver Standard beworben.
- **Familientarife:** lokale Suche in den berechtigt geladenen Betriebsdaten,
  lesbare Kennungen und eigene große Bearbeitungsaktion unterhalb der Angaben.
  Breite Ansichten zeigen die Betriebswerte als Tabelle; schmale Ansichten
  behalten gut erreichbare Einzelaktionen. Die Entscheidung richtet sich ab
  800 Pixel nach der tatsächlich verfügbaren Inhaltsbreite, einschließlich
  platznehmender Navigation und Seitenabstände.
  Kein Zugriff auf private Lernmaterialien oder Antworten.
  Abbrechen verändert keinen Ladezustand; nach echtem Speichern wird nur die
  Familienliste aktualisiert. Andere Formularentwürfe bleiben erhalten. Der
  Tarifdialog kann bei kleiner Höhe oder eingeblendeter Tastatur scrollen.
- **Protokoll:** lokale Suche nach Aktion oder Zielkennung, klar getrennte
  Einträge mit lokal formatiertem Zeitpunkt. Fehlende Zeitpunkte bleiben offen.
- **KI-Kosten:** eigener Bereich für Modellverbrauch, Reservierungen,
  beschriftete Budgetzustände und unbekannte Abrechnungen. Die vorhandenen
  serverseitigen Angaben zu durchschnittlichen zugeordneten Auftragskosten je
  abgeschlossener Runde werden mit ihrer Begrenzung angezeigt. Künstliche
  Anbieterprüfungen bleiben separat; daraus werden keine vollständigen Kosten
  je beherrschtem Lernziel abgeleitet.

Der Notfallstopp ist unabhängig vom Provider-Ladezustand erreichbar und visuell
mit Fehlerton, Stopp-Symbol und ausdrücklicher Beschriftung hervorgehoben. Er
sendet weiterhin ausschließlich nach Betätigung seinen bestehenden POST.

## Unterseiten

Bei **Zahlungen** stehen die Bestellungen zuerst. Statusfilter unterscheiden
offene Zahlungen, freigeschaltete und beendete Bestellungen. Bankabgleich und
Erstattung behalten die bestehenden Bestätigungen und Backendprüfungen.
Der Reiter „Verkauf einrichten“ ist getrennt. Statusfilter und Reiterwechsel
erhalten ungespeicherte Eingaben durch `Offstage` mit `ExcludeFocus`.
Statusfilter lösen vor dem Wechsel den Eingabefokus, damit eine versteckte
Zahlungseingabe nicht weiter die Bildschirmtastatur offen hält.

Die **Push-Prüfung** trennt Betreiberfreigabe, Geräte/Versand sowie Konfiguration
und Nachweise. FCM-Annahme und sichtbare Zustellung bleiben ausdrücklich
unterschiedliche Belege. Es wird kein Testversand durch Seitenaufruf ausgelöst.
Auf großen Bildschirmen stehen Versand und Nachweise nebeneinander.

Die bestehenden **Betriebseinstellungen** erhalten dieselbe Bereichsauswahl.
Ersteinrichtungsassistent, Entwürfe, lokale Installationssperre und ausdrücklich
betätigte Prüfungen bleiben in ihrem bisherigen Ablauf.

## Prüfung

`app/test/admin_workspace_test.dart` ergänzt die Regression, dass ein
Providerfehler weder Betriebsübersicht noch Familientarife blockiert.
Zusätzliche Fälle sichern den Entwurf nach Verbindungsprüfung und nach
abgebrochenem beziehungsweise gespeichertem Familientarifdialog.
`app/test/admin_subpages_design_test.dart` enthält künstliche Fälle für
320/390/1440 Pixel in beiden Varianten, reine GET-Navigation, erhaltene Tarif-/Zahlungsentwürfe,
Statusfilter, große Schrift, ehrliche Push-Angaben und begrenzte Kostenzuordnung.
Triageflächen und die breite Familientabelle werden ebenfalls mit beiden
Helligkeitsvarianten geprüft. Die Größenfixtures setzen die tatsächliche
FlutterView-Größe mit Pixelverhältnis eins, sodass MediaQuery und Layout dieselbe
Breite sehen.
Die bestehenden Provider-, Einrichtungsentwurfs- und Kontrasttests bleiben
maßgeblich. Testergebnisse und Browserprüfung werden erst nach der zentralen
Integration im Releaseprotokoll ausgewiesen.

Keine Backendberechtigungen, Providerfreigaben, Budgets, Schlüssel, Käufe,
Modellrouten oder Produktionskonfigurationen werden durch die Gestaltung
geändert.

Anmelde-/Altlink-Rückweg: main.dart führt authentifizierte Administratoren von
`/` und `/app` unmittelbar nach `/admin`. Die frühere zusätzliche Einstiegsseite
ist damit kein Umweg vor dem Betriebscockpit. Zwei Routerregressionen prüfen den
Start auch bei nicht erreichbarer Providerabfrage und ohne schreibende Aufträge.
