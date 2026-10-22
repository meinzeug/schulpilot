# Kostenlose 30-Tage-Testphase: Backend und Freigabe

Stand: 22.10.2026, Kandidat für den gemeinsamen Release 1.22.1+91.
Diese Dokumentation bestätigt die lokale Implementierung und die genannten
Tests. Sie behauptet keine bereits erfolgte Produktionsfreigabe der Testphase
oder zahlungspflichtiger Angebote. Build, Gesamtlauf und Deployment werden im
gemeinsamen [Releasebericht](RELEASE_91_2026_10_22.md) nachgewiesen.

## Anspruch und Beginn

Neue öffentliche Passwort- und Google-Registrierungen erhalten grundsätzlich
`commerce_required=true`, zunächst keine KI-Aufrufe und höchstens ein
Kinderkonto. Ohne freigegebene Testphase oder wirksamen bezahlten Tarif entsteht
kein unbegrenzter Pilotzugang. Bestehende Familien, ihre Tarife und ausdrücklich
gesetzte Betreibergrenzen werden nicht nachträglich verändert.

Nur bei wirksamem `StoreSettings.trial_enabled` wird für eine neu registrierte,
nicht künstliche Familie ein ausstehender Anspruch gespeichert. Dafür müssen
Betreibername, Anschrift, Support-E-Mail und funktionsfähiger E-Mail-Versand
vorliegen. Bankdaten und Umsatzsteuerbehandlung bleiben Voraussetzungen des
bezahlten Verkaufs und werden durch die kostenlose Testphase nicht ersetzt.

`commerce.activate_trials()` setzt den Beginn genau einmal nach bestätigter
E-Mail; das Ende liegt exakt 2.592.000 Sekunden später. Bei einem autoritativ
bestätigten Google-Postfach kann dies unmittelbar erfolgen. Andere Postfächer
benötigen weiterhin die eigene E-Mail-Bestätigung. Familiensperre und erneute
Prüfung von Elternrolle, Eigentümerschaft und Anspruch verhindern einen zweiten
Beginn bei konkurrierenden Bestätigungslinks. Ein bereits zugesagter Anspruch
bleibt bei einer späteren Sperre für neue Testregistrierungen erhalten.

## Grenzen und bezahlter Zugang

Der Anspruch speichert höchstens ein Kind sowie die vorhandenen Installations-
Höchstwerte für KI-Aufrufe und USD-Budget zum Registrierungszeitpunkt. Bei der
lesenden Bestandsprüfung waren dies 100 Aufrufe und 2.000.000 USD-Mikroeinheiten
(2 USD). Dies sind Obergrenzen, keine Zusage von 100 erfolgreichen Erzeugungen:
vorhandene globale und kindbezogene Grenzen, Reservierungen, Anbieterfreigaben
und unklare Gebühren gelten unverändert.

Die gesamte Testphase verwendet genau einen Verbrauchsschlüssel
`<family_id>:trial`. Monatswechsel und spätere Änderungen der Installationswerte
setzen diesen Verbrauch nicht zurück. Unbekannte Kosten behalten die normale
konservative Reservierung. Es werden weder Kontingente freigegeben noch globale
Budgets erhöht. Tests reservieren ausschließlich in isolierten Datenbanken und
rufen keinen Anbieter auf.

Eine wirksame bezahlte Laufzeit hat wie bisher Vorrang. Bestellung,
Vertragsfassung, Zahlungsreferenz, Überweisungsdaten, manuelle Bankprüfung und
bisheriger Laufzeitbeginn bleiben unverändert. Es gibt keinen neuen automatischen
Auftrag, keine automatische Verlängerung und keinen verschobenen Kaufmodus.
Ein Kauf oder eine Zahlung setzt den gespeicherten Testanspruch nicht zurück;
eine bezahlte Laufzeit kann nach dem bestehenden Verfahren bereits vor seinem
Ende beginnen. Ausdrückliche bestehende Betreibergrenzen bezahlter Familien
behalten ihre bisherige Wirkung.

## Schnittstellen

| Schnittstelle | Ergänzung und Wirkung |
| --- | --- |
| `GET /api/store/catalog` | Öffentliche `trial`-Projektion: `enabled`, `duration_days=30`, `children`, `calls`, `payment_required=false`, `auto_renew=false`, `starts_on="verified_email"`, `notice`. Keine Bank- oder privaten Budgetdaten. Reiner GET. |
| `GET /api/admin/store` | Bestehender berechtigter und auditierter Konfigurationsleseweg liefert `trial_enabled` und `trial_missing` als Liste der tatsächlichen kostenlosen Voraussetzungen. Bezahlte Voraussetzungen bleiben getrennt in `missing`; eine fertige Testfreigabe schaltet den Bankverkauf nicht frei. |
| `PUT /api/admin/store` | Bestehender revisionsgebundener Betreiberweg mit zusätzlichem `trial_enabled`. Fehlende Voraussetzungen verhindern die Aktivierung. Alte Clients ohne Feld erhalten den gespeicherten Zustand. Tatsächliche Aktivierung setzt `ever_trial_enabled` monoton, ohne die Historie bezahlter Freigaben vorzutäuschen. |
| `POST /api/auth/register` | Einheitlicher öffentlicher `access_notice` für neue und bereits bekannte E-Mails; keine zusätzliche Kontoauskunft. Anspruch nur für wirklich neu angelegte geeignete Familien. |
| `POST /api/auth/verify` | Einmalige Aktivierung nach eigener Mailprüfung innerhalb der vorhandenen Transaktion. Wiederholung verändert Beginn und Ende nicht. |
| Bestehender Google-OIDC-Abschluss | Neue Familien verwenden dieselbe Anspruchslogik; eigene Mailprüfung für nicht autoritative Postfächer bleibt erhalten. Neue Anmeldungen erhalten den passenden öffentlichen Zugangshinweis. |
| `GET /api/families/{id}/usage` | Vorhandene berechtigte Verbrauchsansicht enthält `access` und bei Testphase ihre Daten. Bereits von den Kontoeinstellungen geladen; kein neuer Provideraufruf erforderlich. |
| `GET /api/families/{id}/orders` | Vorhandener berechtigter Bestellweg enthält `access`; aktive Testphase und gegebenenfalls spätere bezahlte Laufzeit bleiben unterscheidbar. Keine Werbung für Käufe im Kinder- oder Play-Zugang daraus ableiten. |
| `GET /api/families/{id}/export` | `family.json` enthält die eigenen minimalen Testanspruchsdaten, keine interne Eigentümer-ID. Bestehende Exportrechte bleiben gleich. |

`commerce.access()` unterscheidet den bisherigen Bestand (`existing`), wirksame
bezahlte Laufzeit (`active`), aktuelle Testphase (`trial`), spätere bezahlte
Laufzeit (`scheduled`), abgelaufene Testphase (`trial_expired`) und fehlendes
Lernrecht (`inactive`). Die private `trial`-Projektion enthält Status, Beginn,
Ende, Dauer, Kinder-/Aufruflimit und USD-Budget. Öffentliche Werbung darf allein
aus der gültigen öffentlichen Freigabe abgeleitet werden; ein älteres Backend
ohne `trial` ist kein Freigabenachweis.

## Speicherung, Export, Löschung und Rückweg

Migration `0029` auf `0028` ergänzt `store_configuration.ever_trial_enabled`
und `family_trials`. Eine Familie hat höchstens einen Anspruch. Datenbankprüfungen
sichern nichtnegative Grenzen und die feste Laufzeit. Die Migration enthält
keine Rückbefüllung bestehender Familien und keine Änderungen ihrer Kontingente
oder Zahlungsbelege.

Der Anspruch ist minimale Kontoberechtigung, kein Lernbeleg. Er bleibt auch nach
Ablauf bis zur Familienlöschung erhalten, damit sich die Frist nicht erneut
starten lässt. Die Trialfrist verwendet ausdrücklich nicht `Family.expires`:
das bestehende automatische Entfernen abgelaufener künstlicher Demos löscht keine
echten Testfamilien. Der Ablauf sperrt neue KI-Aufträge; gespeicherte Inhalte
bleiben über ihre bisherigen Berechtigungen verfügbar. Die bestehende
Aufbewahrung von Lernbelegen wird dadurch nicht verlängert.

Normales `DELETE /api/account` entfernt den Anspruch über den Familien-Fremdschlüssel
mit `ON DELETE CASCADE`; der bestehende Familien-Verbrauchsschlüsselpfad entfernt
auch `<family_id>:trial`. Wiederherstellungen wenden das authentifizierte
Löschjournal über `erasure.reconcile()` und denselben `remove_family()`-Pfad an.
Gesetzlich erforderliche bezahlte Belege bleiben nach bisheriger Regel ohne
Kontozuordnung erhalten. Der Familienexport enthält die Anspruchsdaten.

Schema-Auf- und -Rückmigration sind in SQLite und PostgreSQL gegen historische
Familien, bezahlte Bestellungen und gespeicherte Betreiberkonfiguration geprüft.
Dies beweist noch keine Kompatibilität älteren Anwendungscodes mit einer unter91
neu gespeicherten Konfiguration: Das strenge frühere `StoreSettings`-Schema kennt
`trial_enabled` im verschlüsselten JSON nicht. Auch ein gespeichertes `false`
kann damit den alten Konfigurationslesepfad stören. Das additive Datenbankschema
allein macht einen Rückweg daher nicht sicher.

Vor dem Update muss der exakte private Konfigurationsstand gesichert werden.
Ein unmittelbarer Rückweg vor der ersten neuen Konfigurationsspeicherung ist
gegen diesen Stand zu prüfen. Nach neuen91-Buchungen oder Testansprüchen benötigt
ein älterer Code eine bewusst geprüfte Operator-Migration beziehungsweise einen
kompatiblen Konfigurationslesepfad; alte Konfiguration darf nicht einfach über
neuere Änderungen geschrieben werden. Anspruchsdaten und aktuelle Zahlungsbelege
dürfen dabei nicht verloren gehen. Migration, gesicherte Konfiguration und
tatsächlich genutzte Funktionen gehören gemeinsam zur Rückwegprüfung.
Auch die öffentliche Registrierungsentscheidung ist Teil dieser Prüfung:
Vorheriger Code kann bei nie freigegebenem Shop noch einen Pilotzugang vergeben.
Technische Schema-Verträglichkeit beweist deshalb nicht, dass der Rückweg die
neue gesperrte Voreinstellung für Registrierungen erhält.

## Nachweise und Grenzen

Gezielter PostgreSQL-Block im getrennten Commerce-Arbeitsbaum: **71 bestanden**,
eine bereits vorhandene Starlette/httpx-Abkündigungswarnung. Enthalten sind
Trial-, bestehende Commerce-, Konto-, Google-, Provider- sowie SQLite- und
PostgreSQL-Migrationsfälle; die separat gemeldeten Migrationsfälle sind darin
bereits enthalten und werden nicht doppelt gezählt. Derselbe Zielblock bestand
nach der Übernahme auch im Hauptarbeitsstand: **71 bestanden in 79,97 Sekunden**,
dieselbe eine Warnung. Das lokale Protokoll liegt unter
`artifacts/commerce-launch/backend-main-final.log`. Dies ist eine erneute Prüfung
derselben Fälle und keine zusätzliche Fallzahl.

Der anschließende vollständige Vier-Shard-Lauf erfasste **1.898 unterschiedliche
Backendfälle: 1.896 bestanden, zwei fehlgeschlagen, keine übersprungenen Fälle**.
Das Manifest belegt unveränderte Test- und Implementierungsdateien während des
gesamten Laufs. Der historische Pilot-Testhelfer verwendete Umgebungs- statt
gespeicherter Betreiberwerte; seine Rekonstruktion und Testbezeichnung sind
gezielt korrigiert. Im Binary-Installationstest lief der bisherige
Zehn-Sekunden-Prozess unter Last regulär ab; die beiden Busy-Fixtures warten
jetzt über eine offene Eingabepipe bis zu ihrer ausdrücklichen Beendigung.
Die tatsächlichen Inode-, Hash-, Dateityp- und Prozessschutzprüfungen bleiben
erhalten. Diese fehlgeschlagene erste Vollprüfung wird nicht nachträglich als
grün bezeichnet.

Nach unabhängiger Quellprüfung wurden außerdem die aktive Datenbank-Zeitpaar-
Prüfung um ausdrückliches `ends IS NOT NULL` ergänzt sowie die von der Oberfläche
benötigte `trial_missing`-Metadatenliste tatsächlich an die Admin-API angebunden.
Echte negative SQLite-/PostgreSQL-Inserts und ein zusätzlicher API-Vertragsfall
prüfen diese Grenzen. Ein gezielter Nachlauf über Trial, bestehende Commerce-,
Konto-, Google-, Provider-, Migration-, Installation- und Operatorreparaturfälle
bestand nach diesen begrenzten Korrekturen mit **175 bestanden in 175,85 Sekunden**
und derselben einen Starlette/httpx-Warnung
(`artifacts/ux91/backend-final-corrections.log`). Darin ist der bisherige
71er-Zielblock mit dem neuen API-Vertragsfall (jetzt72) enthalten; überlappende
Fälle werden nicht zu einer künstlichen Gesamtsumme addiert. Alle geänderten
Backend-/Testdateien bestehen Ruff und `git diff --check`.

```sh
TMPDIR=/dev/shm .venv/bin/python scripts/test_postgres.py \
  backend/tests/test_family_trial.py \
  backend/tests/test_commerce.py \
  backend/tests/test_accounts.py \
  backend/tests/test_google_login.py \
  backend/tests/test_providers.py \
  backend/tests/test_family_trial_migration.py \
  backend/tests/test_grade_migration.py
```

Die vorhandenen Lern-/Datenschutztests markieren ihre bewusst historischen
Pilotfamilien ausschließlich im Testhelfer. Sie sind kein Nachweis heutiger
öffentlicher Registrierung. Neue Registrierungs-, Trial- und Sperrtests verwenden
die öffentliche Route ohne diesen historischen Testdatenbestand.

Die lesende Produktionsprüfung ergab noch keine hinterlegten Betreiber-, Bank-
oder Steuerangaben und keine freigeschalteten Verkaufsangebote. Der vorhandene
E-Mail-Versand allein ersetzt diese Angaben nicht. Es wurde keine echte Familie
registriert, keine Bestellung erzeugt, kein Zahlungseingang gebucht und keine
Produktionsfreigabe geändert. Die öffentliche UI-Abnahme und der tatsächliche
Release erfolgen koordiniert und werden erst danach als abgeschlossen angegeben.
