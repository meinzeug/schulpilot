# Widerruf: Erklärung, Zahlungssperre und Rückzahlung getrennt

Die Implementierung speichert eine eindeutige Erklärung mit Name, Bestellreferenz, Kontaktadresse und serverseitigem Eingangszeitpunkt. Sie bestätigt den Eingang als herunterladbaren Text und versucht genau einmal die Übermittlung dieser Bestätigung über den bestehenden TLS-Mailweg. `mail_status=accepted` bedeutet ausschließlich Annahme durch den Mailserver; eine tatsächliche Zustellung wird damit nicht behauptet.

Eine öffentliche Erklärung ist zunächst **ungeprüft**. Sie liest keine Bestellung und verändert weder Familienrechte noch Zahlungsstatus. Eine bereits bezahlte Bestellung wird durch keine dieser Funktionen als erstattet markiert. Tatsächliche Rückzahlungen und die Prüfung ihrer Belege bleiben ein eigener Finanzvorgang.

## Schnittstellen

Alle Pfade unter `/api`. JSON-Antworten und Belege sind privat und werden nicht gecacht. Normale Request-/CSRF-/Größenregeln gelten weiter. Es gibt keine Tokens in Querystrings und keinen öffentlichen Bestell-Suchendpunkt.

- `POST /orders/{order_id}/withdrawals`: angemeldeter verifizierter Elternzugang mit aktueller Ownerberechtigung, kein Testraum, kein Kinder- oder Betriebsadminzugang. Body: `request_key` (16–60 Zeichen `[A-Za-z0-9_-]`), `buyer_name` (2–160 Zeichen, ohne Steuerzeichen), `contact_email` und `confirm:true`. Die E-Mail muss der aktuell bestätigten E-Mail dieses Elternkontos entsprechen. Unter derselben Familiensperre wie Zahlungen werden Sitzung, Rolle und Ownerberechtigung erneut geprüft.
- `GET /orders/{order_id}/withdrawal`: dieselbe Ownerprüfung. Antwort `{"withdrawal":null}` oder der gespeicherte Eingangsbeleg. Keine E-Mail, KI, Zahlung oder automatische Wiederholung.
- `POST /withdrawals/public`: dieselben Eingaben, zusätzlich `order_reference` (1–80 Zeichen). Kein Login erforderlich; kein Lookup privater Bestell-, Familien- oder Nutzerdaten. Erklärung und Kontakt werden verschlüsselt gespeichert. Antwort immer `received_unverified`/`payment_hold:false`; keine Preis-, Bestell-ID-, Familien- oder Laufzeitdaten aus einer tatsächlichen Bestellung.
- `GET /admin/withdrawals`: explizite Betriebsrolle; begrenzte erwachsene Vertragserklärungen, keine Lerninhalte oder Kindnamen. Optional `status`, `limit` (1–50) und der zurückgegebene opake `before`-Cursor. Der Cursor enthält Zeit und ID, damit Eingänge derselben Sekunde nicht übersprungen werden. Lesezugriff wird ohne Inhalte auditiert.
- `POST /admin/withdrawals/{public_id}/link`: `order_reference` und bewusstes `identity_verified:true`. Der Operator muss die Identität außerhalb des ungeprüften Drittformulars tatsächlich geprüft haben. Exakter Referenz-Digest und vorhandene eindeutige Bestellreferenz müssen passen. Danach Familiensperre, erneute Sitzung-/Rollenprüfung und gesperrte Bestell-/Erklärungszeilen. Eine Wiederholung derselben Zuordnung ist idempotent. Es wird keine Rückzahlung ausgelöst.

Erster Erklärungseingang liefert201, identische Wiederholung200. Abweichende Eingaben unter demselben Schlüssel liefern409 und überschreiben keinen Beleg. Eine zweite Erklärung desselben Owners zur selben Bestellung ersetzt den gespeicherten Beleg ebenfalls nicht. Öffentliche und authentifizierte Schlüsselbereiche sind getrennt; eine gespeicherte öffentliche Erklärung kann keine fremde authentifizierte Erklärung präventiv belegen.

Antwortfelder für das Eingangsformular:

```json
{
  "id": "<zufällige Beleg-ID>",
  "status": "received_unverified | received_verified | review_required",
  "received_at": 0,
  "received_at_iso": "<UTC-Zeitpunkt>",
  "mail_status": "pending | sending | accepted | failed",
  "receipt_text": "<dauerhafter Eingangsbeleg>",
  "payment_hold": false,
  "refund_executed": false,
  "notice": "<klarer Statushinweis>",
  "mail_notice": "<ehrlicher Übergabestatus>"
}
```

Die Bestätigung enthält ausschließlich die abgegebene Erklärung, den serverseitigen Zeitstempel und die zur Erklärung angegebenen Vertrags-/Kontaktdaten. Ein öffentlicher Eingang verrät auch bei zufällig gültiger Referenz keine weiteren Bestelldaten. Die Verwaltungsansicht darf nach bewusster Berechtigungsprüfung die verschlüsselt gespeicherte erwachsene Erklärung lesen.

## Zahlungssperre und Parallelität

`order_withdrawals.payment_hold(db, order_id)` ist eine reine Leseprüfung auf eine **verifizierte** gespeicherte Erklärung mit Zahlungssperre. Ungeprüfte öffentliche Erklärungen nehmen an dieser Abfrage nicht teil. Der Payment-/Bankpfad muss die bestehende Familiensperre halten und die Sperre vor Capture, Verbuchung/Aktivierung und bei der Auswahl der nutzbaren Bestellung beachten.

Ein rechtzeitig verifizierter Eingang hält weitere Zahlungen/Freischaltungen dieser Bestellung an. Eine sicher unbezahlte offene Bestellung kann unter der Sperre auf `cancelled` wechseln und ihren offenen Bestellslot freigeben. Ein schon ausgelöster oder unklarer Capture bleibt dagegen als unklarer Finanzvorgang erhalten. Das ist weder eine bestätigte Stornierung noch eine Rückzahlung. Ein bezahlter Beleg bleibt `paid`; ursprüngliche Zahlungssnapshots, Buchungen und Lernnachweise werden nicht umgeschrieben.

Bei späterer bewusster Zuordnung einer öffentlichen Erklärung zählt deren ursprünglicher Eingangszeitpunkt. Eine frühere Erklärung kann deshalb nach der Identitätsprüfung eine Sperre begründen, auch wenn die manuelle Prüfung später erfolgt. Bereits gespeicherte Ownerbelege werden dabei nicht neu datiert oder überschrieben; der frühere verifizierte Zeitpunkt wird separat als `effective_received` geführt.

## Frist und Grenzen der Automatik

Die automatische Standardprüfung zählt14Kalendertage nach dem Berliner Tag des Vertragsabschlusses bis zum Tagesende. Wochenenden werden bis Montag verlängert. Ein gewünschter früher Leistungsbeginn führt hier zu keinem automatischen Entzug von Verbraucherrechten.

Die Automatik ist **keine vollständige rechtliche Fristentscheidung**: regionale Feiertage, besondere Belehrungs-/Vertragssituationen und andere Ausnahmen werden nicht abschließend berechnet. Eingänge außerhalb des automatischen Fensters werden dauerhaft angenommen und klar als `review_required` geführt. Das ist keine rechtliche Ablehnung. Die individuelle rechtliche Prüfung und gegebenenfalls eine daraus folgende Zahlungssperre/Erstattung erfordern eine bewusste Betreiberbearbeitung. Die Anwendung behauptet keine vollständige Rechtskonformitäts- oder Fristprüfung.

Primärquellen für Erklärung, Frist und dauerhafte Bestätigung: [§355BGB](https://www.gesetze-im-internet.de/bgb/__355.html), [§356BGB](https://www.gesetze-im-internet.de/bgb/__356.html), [§356aBGB](https://www.gesetze-im-internet.de/bgb/__356a.html) und [§193BGB](https://www.gesetze-im-internet.de/bgb/__193.html). Die öffentliche HTML-Funktion/Bestätigungsaktion und ihre Sichtbarkeit gehören zur getrennt integrierten Weboberfläche.

## Mail, Missbrauchsgrenzen und Betriebsfehler

Die Erklärung wird **vor** einem SMTP-Versuch committed. Ein atomarer Statuswechsel `pending→sending` erlaubt höchstens einen automatischen Sendeversuch. Bei Fehler bleibt der Beleg erhalten; GETs und identische Wiederholungen lösen keinen weiteren Versuch aus. Ein Prozessabbruch kann einen unbestätigten `sending`-Stand hinterlassen. Dieser wird nicht als erfolgreiche Zustellung ausgegeben. Es wird kein unendlicher Retry oder zusätzlicher Maildienst eingeführt.

Öffentliche Eingänge sind begrenzt auf100Anfragen/Stunde global,10/IP/Stunde und3/Kontakt-E-Mail/Stunde. IP und E-Mail werden in den Ratelimit-Schlüsseln nur gehasht verwendet. Authentifizierte Eingänge sind auf10/Owner/Stunde begrenzt, bewusste Adminzuordnungen auf30/Admin/Stunde. Namen, E-Mail, Eingaben, Belege und Mail-/Provider-Rohfehler werden nicht protokolliert. Audit enthält nur Aktion und interne zufällige Vorgangs-ID.

## Daten, Export, Löschung und Migration

`0031_order_withdrawals.py` folgt auf `0030_payments.py`. Beide neuen Tabellen sind additiv; es gibt keine Bestands- oder Rechtsstatus-Rückfüllung. Erklärungen liegen verschlüsselt mit dem bestehenden Masterkey, Referenz-/Kontaktdigests dienen ausschließlich kontrollierter Zuordnung und Missbrauchsbegrenzung. Keine Daten fließen an eine KI oder an Push.

- `withdrawals_export(db,family_id)` liefert eine Liste mit `order_id`/`source`, Eingangsmetadaten und vollständigem Beleg. Der Aufrufer muss die Ownerberechtigung geprüft haben. Der Export ist niemals Bestandteil eines Kinderexports und enthält keine fremden öffentlichen Eingänge.
- `erase_family_withdrawals(db,family_id)` läuft vor der Bestellanonymisierung. Sicher unbezahlte Bestellungen ohne Zahlungsversuch verlieren ihre gekoppelten Erklärungen. Bezahlte/erstattete Bestellungen **und alle wegen vorhandenen PaymentAttempt als Finanzbeleg erhaltenen Bestellungen** behalten ihre Erklärung gekoppelt; der direkte Ownerverweis wird entfernt. Keine unklare mögliche Abbuchung wird durch Kontolöschung zum beleglosen Vorgang.
- `maintenance(db)` entfernt unzugeordnete/nicht finanziell gebundene öffentliche Erklärungen nach365Tagen. An bezahlte oder noch erforderliche Finanzbelege gekoppelte Erklärungen folgen deren Bestellaufbewahrung. Der bestehende Buchungspfad hält bezahlte Belege nach seiner Achtjahresregel; ungeklärte Zahlungsversuche müssen gesondert geklärt werden. Löschung der führenden Bestellung kaskadiert die eigene Bestellerklärung; öffentliche Verknüpfungen werden getrennt entfernt/verfallen nach der begrenzten Regel.

Ein Rückweg auf0030 entfernt die neuen Erklärungstabellen und darf nach tatsächlichen Eingängen nicht ohne vorherige geschützte Sicherung/Erhalt dieser Belege verwendet werden. Bestehende bezahlte Bestellsnapshots bleiben durch die reine additive Migration unverändert; das ersetzt keine Prüfung der übrigen neuen Paymentkonfiguration bei einem Code-Rollback.

## Nachweise

Nur künstliche Profile, gemocktesSMTP und isolierte Datenbanken, keine echten Widerrufe/Zahlungen/Mails oder Anbieteraufrufe.

- `backend/tests/test_order_withdrawals.py`: verifizierter Owner, falsche E-Mail/Rollen/Familienrechte/Testraum, idempotente und widersprüchliche Schlüssel, kein erfundener Refund, Frist-/Reviewstatus, Kalender-/Wochenendgrenze, dauerhafter Beleg trotz Mailfehler, öffentlicher Eingang ohne privaten Lookup, bestätigte Adminzuordnung, Seitennavigation gleicher Sekunde, tatsächliche parallele Familiensperre/Zahlungsfreigabe, paralleler öffentlicher Eingang, Finanzaufbewahrung und Rechteänderung während Sperrwartezeit.
- `backend/tests/test_order_withdrawal_migration.py`: tatsächlicher0030↔0031-Roundtrip aufSQLite undPostgreSQL, exakte Spalten, keine Rückfüllung, unveränderte bezahlte Bestellsnapshots und passende Kaskade.
- ZwischenlaufSQLite:13grün/2nurPG-Konkurrenzfälle übersprungen. Erster kompletter isolierterPG-Zielblock:19/19grün. Finaler isolierterPG-Zielblock mit zwei zusätzlichen Sperrwartezeit-Rechtefällen:21/21grün (21,22Sekunden, ein bestehenderStarlette/httpx-Kompatibilitätshinweis). Ruff für alle eigenenPythondateien sauber. Logs: `artifacts/ux93/withdrawals-{sqlite,postgres-first,postgres-final}.log` im Hauptarbeitsbereich.

Diese Tests sind keine echte Mailzustellung, echte Providerzahlung oder abgeschlossene Produktions-/Rechtsabnahme. Übernahme, vollständige Integrationstests und Deployment erfolgen anschließend durch Root.
