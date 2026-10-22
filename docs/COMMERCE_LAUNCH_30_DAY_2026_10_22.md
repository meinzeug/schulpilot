# Öffentlicher Einstieg mit 30-tägiger Testphase

Frontend im isolierten Commerce-Worktree, anschließend nur disjunkte Frontenddateien nach main übertragen. Veröffentlichung dieser Oberfläche ist keine Freigabe der Testphase oder des Verkaufs. Der Nutzer reicht die erforderlichen Betreiberangaben später nach; beide Freigaben bleiben bis zur vollständigen Konfiguration und bewussten Aktivierung gesperrt. Kein Produktions- oder Freigabenachweis durch diese lokale Prüfung.
Die bezahlten Angebote bleiben bis zur vollständigen Betreiber-/Bank-/Steuerkonfiguration und ausdrücklichen Veröffentlichung gesperrt. Katalogpreise sind alleinige Quelle; vorbereitete Preise werden als Vorschau gekennzeichnet. Keine Anbieter-, Bank- oder Steuerdaten wurden erfunden.

## Kostenlos ausprobieren

`GET /store/catalog` liefert den öffentlichen, revisionsgebundenen Verkaufskatalog und `trial`. Die Oberfläche verspricht 30 kostenlose Tage ausschließlich bei `enabled=true`, `duration_days=30`, `starts_on=verified_email`, `payment_required=false`, `auto_renew=false` und gültigen Kinder-/Aufrufgrenzen. Ein fehlendes Feld, ein altes Backend, Laden oder ein Fehler erzeugt keine aktive Testzusage. Die Landingpage bietet einen kostenlosen Elternkontoeinstieg weiterhin an und erklärt einen noch nicht freigegebenen Testzugang offen. Aktualisieren ist ein bewusster GET ohne Auftrag oder Kostenreservierung.

Kinderzahl und KI-Schritte kommen aus dem Katalog; aktuell plant der Backendvertrag einen Kinderzugang und höchstens 100 Schritte für die gesamte Testphase. Ein Monatswechsel setzt dieses Kontingent nicht zurück. Zusätzlich gelten Anbieter-, Kosten- und Systemgrenzen. Aufbewahrungsregeln und eigene Kinderzugänge bleiben bestehen. KI kann Fehler machen; die Seite verspricht weder Notenverbesserung noch einen garantierten Lernerfolg. Keine erfundenen Bewertungen, Kundenanzahlen oder Erfolgsgeschichten.

Die Registrierung übermittelt dieselben vorhandenen fünf Felder und löst keine Bestellung aus. Erst die verifizierte E-Mail startet eine vom Backend vorbereitete Testphase. Die einheitliche Registrierungsrückmeldung verrät nicht, ob ein Konto existiert; ein zusätzlicher serverseitiger `access_notice` bleibt sichtbar. Nach dem Absenden zeigt die Oberfläche den E-Mail-Schritt und sendet ohne erneute ausdrückliche Bearbeitung nicht nochmals. Linkcodes bleiben im Fragment, der vorhandene sichere Checkout-Rückweg bleibt erhalten.

Auch neue Googlekonten behalten den öffentlichen Zugangshinweis bis zum eigenen
Weiterklick. Eine bereits bestätigte Sitzung wird regulär gespeichert; die
Bestätigung navigiert ausschließlich lokal und sendet den Googleabschluss
nicht erneut. Bei notwendiger eigener Mailprüfung bleibt der Hinweis vor dem
Bestätigungseinstieg sichtbar. Alte Antworten ohne Hinweis behalten ihren Weg.
Kontowechsel, andere Abläufe und überdeckte Routen verwerfen alte Aktionen.
28 native Anmelde-/Hinweisregressionen und neun Chromefälle bestehen. Die
native Push-Routenprüfung verwendet den tatsächlichen sichtbaren Zielzustand,
weil GoRouter bei imperativem Push absichtlich die zugrunde liegende URL erhält.

## Tatsächlicher Familienzugang

Die vorhandene Inhaberansicht liest `GET /families/{family_id}/orders`. `access.state=trial` zeigt gespeicherten Beginn und Endtermin sowie das Gesamtkontingent. `trial_expired` verwendet den gespeicherten Trial-Endtermin, auch wenn keine bezahlte Laufzeit existiert. Der bezahlte aktive Tarif bleibt maßgeblich; eine alte Trialzeile wird nicht als parallele aktive Berechtigung ausgegeben. Die Anzeige erteilt keine Rechte und startet keine KI.

Native/Play-Eltern sehen Testende mit Uhrzeit und die gespeicherten angerechneten/verbleibenden KI-Schritte im vorhandenen Kontingentbereich der Einstellungen (`GET /families/{id}/usage`). Kein zusätzlicher Request, kein Kaufmenü. Fehlende alte API-Felder erfinden keinen Trialstatus; unvollständige Trialdaten bieten nur eine bewusste GET-Aktualisierung. Die Elternrolle bleibt Voraussetzung. Ein Monatswechsel setzt den Testverbrauch nicht zurück.

Die Betreiberansicht bietet einen eigenen ausdrücklichen Trialschalter mit den eigenen Voraussetzungen (Betreiberidentität/SMTP, ohne Bankpflicht). Er verändert zunächst ausschließlich den Entwurf; das bestehende revisionsgebundene Speichern veröffentlicht die Einstellung. Dirtyprüfung und Serverabgleich enthalten den neuen Schalter. Ältere APIs lassen ihn deaktiviert und erhalten kein unbekanntes Schreibfeld. Die separate kostenpflichtige Freigabe und der bisherige Zahlungsablauf bleiben bestehen.

## Freiwilliger bezahlter Zugang

Eine bezahlte Laufzeit ist eine separate vorausbezahlte Bestellung per Überweisung. Die bestehenden Vertragsannahme-, Idempotenz-, Bestellsnapshot-, Widerrufs-, Bankprüfungs- und Freischaltwege bleiben erhalten. Die Oberfläche ergänzt ausdrücklich: Eine bezahlte Laufzeit kann nach geprüfter Zahlung und gegebenenfalls der Widerrufsfrist bereits während einer Testphase beginnen. Es gibt keinen neu erfundenen Start nach Testende, keine automatische Umwandlung, Verlängerung oder Abbuchung. Checkout übermittelt weiterhin nur `plan_id`, `catalog_revision`, `request_key`, `accept_terms`, `early_start`.

Öffentliche Kataloginformationen sind keine Bestellfreigabe. Bei gesperrtem Verkauf sind Karten nicht bestellbar. Kinder-, Demo- und native/Play-Oberflächen werben weiterhin keine bezahlten Käufe. Der künstliche Testraum bleibt ausdrücklich vom regulären Familienzugang getrennt.

## Prüfumfang

`app/test/commerce_trial_launch_test.dart` verwendet ausschließlich künstliche MockClient-Antworten: Freigabefelder, Laden/Fehler/GET-Wiederholung, 320/390/1280 px einschließlich großer Schrift und beiden Erscheinungsbildern, Registrierung, sichere Rückwege, Trialende, bezahlter Vorrang, Katalogpreise, gesperrter Verkauf und unveränderter Checkoutauftrag. Nach exklusivem Testslot: neue19 Fälle im nativen Runner17 bestanden/2 ausschließlich Web übersprungen; im echten Chrome-Runner dieselben19/19 bestanden. Diese überlappenden Läufe werden nicht als zusätzliche unabhängige Tests addiert. Nahe Auth-/Store-/Public-/Elterneinstellungsregressionen113 bestanden/5 Webskips. Targeted Analyse aller vier betroffenen Bibliotheken und der neuen Testdatei ohne Befund. Die fixierte Paketauflösung lief mit --enforce-lockfile. Belege liegen unter artifacts/ux91/commerce-frontend/. Der erste lokale Retry-Callbackfehler ist behoben und samt Erstlog erhalten; die zusätzliche Registrierungsretryprüfung ist grün. Der Chrome-Runner meldete beim Beenden einen bereits nicht mehr existierenden Prozess; PID-Abwesenheit wurde separat geprüft. Keine Warnung wurde unterdrückt.

Die tatsächliche Browserabnahme und Operatorfreigabe führt Root nach Integration und Veröffentlichung aus. Eine Widgetprüfung ist weder vollständige WCAG-Abnahme noch echte Zahlungs-/E-Mail-/Lernerfolgsprüfung.

## Gelesene Primärquellen

Am 22.10.2026 direkt gelesen: [W3C zu Beschriftungen und Anweisungen](https://www.w3.org/WAI/WCAG22/Understanding/labels-or-instructions.html), [Bestätigen und Korrigieren wichtiger Transaktionen](https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html) und [Trefferflächen](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html). Daraus folgen klare Bedingungen vor dem Formular, ein sichtbarer nächster Schritt, eine freiwillige getrennte Bestellentscheidung und vorhandene große gemeinsame Bedienelemente. Keine rechtliche Prüfung oder Zertifizierung wird daraus abgeleitet.
