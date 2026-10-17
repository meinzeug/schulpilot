# Codex-Lernprovider

## Modelle und Reasoning im Adminbereich

Bei Codex bietet das Anbieterformular die Modelle der eigenen isolierten CLI als Auswahl an. Die Denkstufen stammen aus `supportedReasoningEfforts` des Katalogs. Bei einem abweichenden Bildmodell gilt die gemeinsame Auswahl beider Modelle. Die gewählte Stufe wird gespeichert und sowohl an `model_reasoning_effort` der CLI als auch an `reasoning.effort` der tatsächlichen Anbieteranfrage weitergegeben. Andere Anbieter behalten ihre bisherigen Modellfelder.

Der geschützte Katalogaufruf startet keine Lernanfrage und legt keinen Thread oder Turn an. Anmeldung und Metadatenabfrage bleiben im eigenen Worker; Zugangsdaten erscheinen nicht im Client. Der Erstassistent verwendet denselben Katalog nur mit gültigem Einrichtungscookie. Katalogausfälle verändern eine gespeicherte Auswahl nicht. Katalogeinträge sind keine Garantie für Modellberechtigung oder funktionierende Bild-/Schemaausgaben; Änderungen durchlaufen weiterhin den regulären künstlichen Prüflauf. Größeres Reasoning erhöht weder Zeit- noch Kosten-/Aufruflimits.

Migration 0013 ergänzt `provider_config.reasoning_effort` mit `medium`. Bestehende Modelle, Revisionen und Freigaben bleiben erhalten. Eine andere Denkstufe zählt wie eine Modelländerung zur revisionsgebundenen Konfiguration. [Offizielle Metadaten](https://learn.chatgpt.com/docs/app-server#list-models-modellist), [Katalog ist kein Berechtigungsnachweis](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server#using-codex-app-server).

Betreiberauftrag vom 15.10.2026: Codex CLI dauerhaft für die gemeinsame Web-/Android-API auswählen, mit `--search`. Die frühere OpenRouter-Free-Auswahl wird damit ausdrücklich ersetzt. Gespeicherte und begonnene Einheiten werden dabei nicht neu geschrieben. Ein Modellwechsel allein beweist keine fachlich richtigen Aufgaben.

## Anmeldung auf dem Server

```sh
ssh -t dorfspy 'sudo schulpilot-codex login'
```

Der lokale Helfer startet **ausschließlich** `codex login --device-auth` als separater Benutzer `schulpilot-codex`, mit der fixierten CLI 0.162.1 und eigenem `CODEX_HOME`. URL und Anmeldecode erscheinen nur im eigenen interaktiven Terminal. Es gibt keinen öffentlichen Anmelde-/Befehlsendpunkt und keine Übernahme der Entwicklungsanmeldung. Die manuelle Anmeldung darf bei Bedarf erneut ausgeführt werden.

Die Datei `/var/lib/schulpilot-codex/auth/auth.json` ist nur für diesen Benutzer zugänglich (Verzeichnis 0700, Datei 0600). Sie enthält Zugangsdaten und gehört weder in Chat noch Git, Downloads oder Backups anderer Anwendungen. Der Backendbenutzer kann sie nicht lesen. Nach dem Login startet der Helfer einen gezählten, gespeicherten Betreiber-Prüfauftrag. Drei tatsächliche erfolgreiche Aufrufe für künstliches Bild, Lerneinheit und Tagespaket heben die technische Sperre auf. Ein vorhandenes Login allein aktiviert die Verarbeitung nicht. Den Prüfauftrag zeigt die bestehende Adminansicht an; es entstehen keine fingierten Kinderantworten.

```sh
sudo schulpilot-codex status  # Nur Anmeldeart, kein Schlüssel oder Token
sudo schulpilot-codex probe   # Begrenzten künstlichen Prüflauf erneut beauftragen
sudo schulpilot-codex logout  # Eigene Anmeldung entfernen, keine Ersatzroute
```

`status` prüft das Vorhandensein der Anmeldung, keine erfolgreiche Anbieteranfrage. Konkrete Modellberechtigung und echte Antworten können erst nach dem eigenen Login geprüft werden. `gpt-6.1-sol` ist die dokumentierte feste Auswahl; ein nicht berechtigtes Konto führt zu einem Fehler, keinem anderen Modell.

Falls der Betreiber bereits manuell unter dem eigenen Benutzer `schulpilot-codex` im Standardverzeichnis angemeldet hat, übernimmt `sudo schulpilot-codex adopt-login` ausschließlich dessen geschützte Anmeldung. Der Import verwirft zuerst alle Rootrechte, öffnet Verzeichnisse und Dateien mit `O_NOFOLLOW` und `dir_fd`, prüft UID/0700-Verzeichnisse/0600-Datei und schreibt eine neue exklusive 0600-Kopie aus validiertem JSON. Es gibt keinen Hardlink auf die Rohquelle. Die unveränderte Quelldatei wird anschließend entfernt; eine bereits vorhandene Zielanmeldung wird niemals überschrieben. Bei erkannten Änderungen bleibt die Quelle erhalten und die eigene neue Kopie wird entfernt. Vollständige atomare Inode-Prüfung plus Namenslöschung ist unter POSIX nicht möglich; deshalb keine parallele manuelle Anmeldung/Tokenaktualisierung während des Imports. Der Helfer verwendet auf diesen Workerpfaden keine Rootrechte.

## Installation und Updates

Der App-Server verwendet Podman 4.9.3 als Rootless-Runtime unter eigenem Benutzer. `deploy/install_codex.py` baut aus dem fixierten Basisimage, der eigenen kleinen Python-Lockdatei und dem nativen CLI-Binary 0.162.1. Dessen SHA-256 wird vor jedem Build gegen den dokumentierten Wert geprüft. Das Binary stammt aus der lokal installierten fixierten offiziellen npm-Plattformdistribution; keine Entwicklungsdateien oder Anmeldedaten werden mitkopiert.

Erstinstallation nach Bereitstellung des nativen Binaries:

```sh
sudo python3 /opt/schulpilot/current/deploy/install_codex.py --binary /geschuetzter/pfad/codex
```

Reproduzierbare Folgeinstallationen verwenden `/opt/schulpilot-codex/bin/codex`. Ein Fingerprint verhindert unnötige Containerbuilds. `scripts/deploy.sh` liefert die Workersourcen mit und aktualisiert einen bereits eingerichteten Codexdienst. Der Container läuft anhand seiner tatsächlichen unveränderlichen Image-ID, nicht anhand eines veränderbaren Tags. Dienst: `schulpilot-codex.service`, automatischer Start; nur SCHULPILOT wird geändert.

Lokale Einstellungen in `/etc/schulpilot/environment`:

```text
CODEX_APPROVED=true
CODEX_SOCKET=/run/schulpilot-provider/codex.sock
CODEX_AUTH_MODE=account
CODEX_WEB_SEARCH=false
```

`CODEX_AUTH_MODE` ist eine lokale Betriebsentscheidung und wird nicht durch öffentliche Requests oder einen Konto-/Modellfehler geändert. `deploy/admin.py configure-codex` speichert die Anbieterauswahl revisionsgebunden in der Datenbank, zunächst technisch gesperrt. `probe-codex` verwendet den vorhandenen Betreiberauftrag mit festen synthetischen Vorlagen. Globale Anbieter-/Datenschutzfreigabe, Notfallstopp und Kontingente gelten weiterhin. Nach Änderungen an lokalen Einstellungen nur API und Lernworker neu starten.

`CODEX_WEB_SEARCH` ist eine ausdrückliche Betreiber-Richtlinie. Bei Kontoanmeldung ist der Standard `false`, bei API-Schlüsseln `true`. Der Installer überträgt ausschließlich diese beiden nicht geheimen Werte in eine eigene Policydatei des Rootless-Launchers; die App-Umgebung wird niemals eingebunden oder weitergereicht. Nach einer Policyänderung den isolierten Codexdienst über den Installer sowie API/Lernworker neu starten. Backend und privater Worker müssen dieselbe Suchrichtlinie bestätigen, bevor ein Prüflauf möglich ist.

Für schulpilot.dorfspy.de hat der Betreiber am 15.10.2026 ausdrücklich Konto-Websuche zusätzlich erlaubt: **ein Codex-Aufruf mit Zeitlimit; die Zahl interner Suchaufrufe ist vorher nicht hart begrenzbar**. Deshalb ist dort `CODEX_WEB_SEARCH=true` ausdrücklich gesetzt und mit einer eigenen Policy-Auditaktion protokolliert. Bestehende Zeit-, Aufruf-, Familien- und Unternehmenslimits bleiben bestehen; diese Freigabe ist keine Nullkostenbehauptung und kein Nachweis eines erfolgreichen Lernlaufs.

Der CLI-Aufruf behält `--search`; der Gateway erlaubt ausschließlich die durch die Betreiber-Richtlinie freigegebenen Werkzeuge. Bei `false` werden `tools: []` und `tool_choice: none` gesendet: Bildauswertung, Aufgaben und Heftfragen bleiben vollständig an die bereitgestellten Unterlagen gebunden. Die Betreiberansicht und der private Healthcheck unterscheiden `cli_search` vom tatsächlich verfügbaren `search`. Fotoerkennung erhält unabhängig von der allgemeinen Suchrichtlinie keine Webwerkzeuge.

## Isolation und Websuche

- Kein öffentlicher Port: Unix-Socket 0660 in gruppenbeschränktem Verzeichnis 0750.
- Container ohne Rootrechte, Capabilities, Hostnetzwerk, Projekt-, Upload-, SSH-, GitHub-, Deployment- oder Dockerzugänge. Nur eigene Anmeldedateien und der Auftrags-Socket sind eingebunden; Root-Dateisystem ist schreibgeschützt.
- Äußerer Dienst begrenzt Speicher auf 550 MiB, CPU auf 80 % eines Kerns und Prozesse auf 160. Ein aktiver Auftrag; keine gleichzeitig gehaltenen Familienaufträge.
- Je Auftrag temporäres Home und Arbeitsverzeichnis, leere Umgebung, `--ephemeral`, `--sandbox read-only`, `--ask-for-approval never`, feste Argumentliste und stdin. Keine Shell-Interpolation. CLI-Eventausgabe und Fehlerausgabe werden verworfen; private temporäre Dateien werden nach dem Auftrag gelöscht. Nur eine aktualisierte eigene Anmeldung wird sicher zurückgeschrieben.
- Der private Gateway bindet Modell, vertrauenswürdige Systemanweisung, Lernpayload und Ausgabeschema serverseitig. Höchstens **ein** Upstream-Responses-Aufruf, keine automatischen Retries oder Fortsetzung. Als Werkzeug ist ausschließlich die ausdrücklich freigegebene gehostete Websuche zulässig; Shell, Dateizugriff, Plugins und andere Modellwerkzeuge werden nicht weitergereicht. `--search` und `web_search=live` sind im CLI fest gesetzt; die tatsächliche Freigabe erfolgt zusätzlich im Gateway.
- Im API-Schlüsselbetrieb erzwingt `max_tool_calls: 1` höchstens einen Suchaufruf. Die dokumentierte ChatGPT-Responses-Route unterstützt dieses Feld ausdrücklich **nicht**. Im Konto-Standard sind deshalb alle Webwerkzeuge ausgeschaltet. Eine ausdrückliche Betreiberentscheidung für `CODEX_WEB_SEARCH=true` im Kontobetrieb erlaubt gehostete Suche innerhalb genau einer Antwort und 145 Sekunden; es gibt dann **keine vorab erzwungene Obergrenze der Suchanzahl**. Die gemeldeten Suchaufrufe werden nachträglich gezählt. Eine Nachkontrolle oder ein Abbruch ist kein Beleg, dass vorher keine weiteren Suchen ausgeführt wurden.
- Suche dient der Gegenprüfung allgemeiner Fachbegriffe. Keine privaten Namen, Antworten oder Heftzitate als Suchanfrage. Webseite und Upload bleiben unzuverlässige Daten. Aufgaben dürfen keine unerklärten Begriffe, unbelegten Zwischenannahmen oder widersprüchlichen Hauptlösungen verlangen. Zusätzliche Webinformationen werden nicht zu bereits gelerntem Heftwissen.
- Die bestehenden Schema-, Auswahlindex-, Rechen-, Quellen-, Lernziel-, Aufgabenanzahl- und Rollenprüfungen gelten auch für Codex. Dies ist kein vollständiger Beweis semantischer Richtigkeit.

## Abrechnung und bekannte Grenzen

**Kontoanmeldung:** Es werden keine API-Rechnungskosten erfunden. Auch bei Tokenzahlen bleibt der Geldbetrag `null`/unbekannt und die volle bestehende Reservierung erhalten. Familien-/Unternehmenslimits, atomare Reservierungen, Fehlversuchzählung und Codex-Kontolimits bleiben aktiv. Die Anwendung verändert diese Limits nicht heimlich. Ein Codex-Konto kann verbrauchsabhängige Kontoguthaben verwenden; die Integration behauptet keine kostenlose Nutzung. `max_output_tokens` und `max_tool_calls` sind laut offizieller Dokumentation für den ChatGPT-Responses-Transport nicht unterstützt; dort begrenzen eine Antwort, 145 Sekunden Prozesszeit und 200 kB fertiges JSON den Auftrag. Die Suchrichtlinie steht oben. Die feste ChatGPT-Codex-Route der CLI ist versionsabhängig; ein echter Login-/Bild-/Schematest bleibt erforderlich. Kontovertragsbedingungen und Datenschutz hängen vom tatsächlich angemeldeten Konto/Workspace ab; eine reine Anmeldedatei ist kein Nachweis.

Ab Migration 0012 werden tatsächlich gemeldete `search_calls` erfolgreicher Codex-Antworten pro Verbrauchsdatensatz gespeichert und berechtigten Eltern ausgegeben; Betreiberproben enthalten denselben Messwert im Bericht. `null` bedeutet unbekannt, `0` eine tatsächlich gemeldete Antwort ohne Suche. Vorherige Datensätze und abgebrochene Antworten bleiben unbekannt; die frühere erfolgreiche Betreiberprobe wird nicht rückwirkend mit erfundenen Suchzahlen ergänzt.

**Optionaler API-Betrieb:** `CODEX_AUTH_MODE=api_key` plus ausdrücklich dokumentierte Preise und `configure-codex` verwenden API-Abrechnung. `schulpilot-codex login-api` nimmt den eigenen Projektschlüssel verdeckt über stdin an. Die Anmeldung allein wechselt keine Abrechnungsart. Der Gateway prüft vor Versand die komplette Byte-Obergrenze, Ausgabetoken, konservativ 128.000 Such-Kontexttoken sowie höchstens 0,01 USD Suchgebühr gegen die Reservierung. Tokenkosten plus tatsächlich gemeldeter Suchanzahl werden geschätzt; fehlende Usage bleibt unbekannt. Keine automatische Erhöhung von Familien-/Unternehmensbudgets. Ein API-Schlüssel ersetzt keine gegebenenfalls erforderlichen OpenAI-Freigaben für Kinderdaten.

Offizielle Dokumentation, tatsächlich geöffnet am 15.10.2026: [nichtinteraktiver Betrieb](https://learn.chatgpt.com/docs/non-interactive-mode), [CLI-Argumente mit `--search`](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [Anmeldearten](https://learn.chatgpt.com/docs/auth), [Modelle](https://learn.chatgpt.com/docs/models), [Websuche](https://developers.openai.com/api/docs/guides/tools-web-search), [Preise](https://developers.openai.com/api/docs/pricing). OpenAI empfiehlt API-Schlüssel für programmatische Workflows; der ausdrücklich gewünschte manuelle Kontoweg ist davon getrennt und weiterhin als experimentell dokumentiert.

Für die Transportkorrektur zusätzlich tatsächlich geöffnet am 15.10.2026: [ChatGPT-Anmeldung durch einen Gateway](https://learn.chatgpt.com/docs/enterprise/sign-in-with-chatgpt-through-a-gateway), [nicht unterstützte ChatGPT-Responses-Felder](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations#responses-api-requirements) und [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol). `tool_choice` steuert die Werkzeugauswahl; `search_context_size` den Kontextumfang. Keines ersetzt eine dokumentierte vorab erzwungene Suchanzahl.

## Prüfung und Rückweg

`backend/tests/test_codex_worker.py` prüft Containerpflicht, eigene Anmeldung, Eingabegrenzen, nur gehostete Suche, Kostenreservierung, einmaligen Gatewayaufruf und Auth-Refresh. Zwei Tests führen die echte installierte CLI mit ausschließlich künstlichen Anmeldedateien und simuliertem Upstream aus. Das ist kein echter OpenAI-Login-/Zustellnachweis.

Die Fehlerdiagnose des privaten Unix-Socket-Healthchecks enthält ausschließlich HTTP-Status, Aufrufanzahl, CLI-Exitcode und einen bekannten Parameternamen. `detail`, `error` und Klartextfehler werden nur im Speicher gegen diese feste Liste geprüft; private Fehlertexte, Zugangsdaten und Nutzereingaben werden niemals übernommen. Regressionstests prüfen die JSON-Diagnose auf Echo-Lecks.

`scripts/check_codex_container.py` prüft denselben echten CLI-Transport im gestarteten Rootless-Container mit simuliertem Upstream, ohne permanente Anmeldung oder Kinderinhalte zu verändern. Beispiel: Datei über stdin an `podman exec -i schulpilot-codex python -` unter dem eigenen Workerbenutzer senden.

Vor der Umschaltung Datenbank und betroffene Umgebung sichern. `configure-codex` legt zusätzlich ausschließlich die bisherige Providerzeile unter `/var/lib/schulpilot/operator-backups/provider-before-codex-*.json` ab (0600, Schlüssel nur als vorhandener verschlüsselter Wert). Für einen Rückweg nur diese Konfiguration unter dem lokalen Operator zurücksetzen; keine inzwischen entstandenen Kinderantworten mit einer alten Gesamtdatenbank überschreiben. Zurückrollen: dokumentiertes vorheriges Backendrelease aktivieren und gesicherte Providerkonfiguration/Umgebung nur durch den lokalen Operator wiederherstellen. Keine begonnenen Einheiten ändern. Ein normales Deployment setzt weder die Datenbankauswahl zurück noch aktiviert es OpenRouter als Ersatz. Rootless-Container kann separat gestoppt werden; andere DorfSpy-Dienste bleiben unabhängig.

Zusätzliche Distributionsprüfung am 15.10.2026: `@openai/codex@0.162.1-linux-x64` von registry.npmjs.org heruntergeladen, SHA-512 gegen die Registry-Integrität geprüft und das native Binary im Archiv auf denselben SHA-256-Wert wie die installierte CLI geprüft. Rootless-Hostkonto hat eine eigene Gruppe und nachweislich keinen Lesezugriff auf App-Umgebung oder App-Daten.
