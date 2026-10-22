# Getrennter Reparaturauftrag: technische Grenze und Abnahme

Stand 22.10.2026. Ein bewusster Adminauftrag erstellt einen **prüfpflichtigen Patch**. Weder Modellantwort, erfolgreiche Metadatenabfrage noch grüner Einzeltest bedeutet, dass Produktion repariert oder ein Patch übernommen wurde. Es gibt keinen automatischen Apply-, Git-, Deployment- oder Providerwechsel.

## Zugang, Kontext und Kosten

`operator_incidents.py` liefert ausschließlich freigegebene technische Fehlerklassen, Funktionsnamen, Commit-/Releasebezug und begrenzte Betriebszähler. Kinder-/Familien-/Jobkennungen, Antworten, Bilder, Fragen, Providertexte und Stack-Locals werden nicht übergeben. Ein Auftrag ist an Fehlersnapshot, tatsächlich ausgelieferten Quellcommit, Katalogfingerprint und genau die auslösende widerrufbare Adminsitzung gebunden. Der Dispatcher prüft diese Grenzen vor und nach dem Auftrag erneut.

Die Auswahl `gpt-6.1-sol` und `max` muss im tatsächlichen `model/list` der separaten gepinnten Codex CLI 0.162.1 enthalten sein. Der Katalog wird ohne Shellwerkzeuge unter der eigenen Reparaturanmeldung gelesen. Keine Auswahlliste ersetzt diesen Nachweis; Metadaten allein belegen keine erfolgreiche Inferenz. Es gibt keinen Lernworker-Fallback und keine globale Anbieterumstellung.

Maximal ein Reparaturauftrag läuft gleichzeitig. Höchstens zwei neue bewusste Aufträge pro Tag und fünf pro Stunde; idempotente Wiederaufnahme und angenommene Alias-Schlüssel starten keinen weiteren Auftrag. Ein Auftrag reserviert zwölfmal die bestehende Einzelreservierung innerhalb **desselben bestehenden globalen Monatslimits**, zusätzlich unter einem getrennten Tagesbudget. Kein Kind oder Haushalt wird dafür erfunden. Kontoabrechnung bleibt USD-unbekannt und behält die volle Reservierung. Nur eine nachgewiesene Nichtübermittlung darf die Geldreservierung freigeben; Anzahl und Audit bleiben erhalten. Kein automatischer Retry.

Das getrennte Reparaturfenster umfasst höchstens 240 Sekunden und zwölf Responses-Anfragen; Vorher-/Nachherprüfungen teilen dieses Fenster. Diese ausdrücklich begründete Operatorgrenze verändert weder 145 Sekunden noch einen Responses-Aufruf des Lernworkers. Modellphase und Proxyberechtigung enden vor dem reservierten Abschlussprüffenster. Such-/MCP-/sonstige gehostete Werkzeuge sind gesperrt; lokale Werkzeuge laufen nur in der folgenden Containergrenze.

## Credentialbroker und Werkzeugcontainer

Der native Dienst `schulpilot-repair.service` läuft als eigener Unixbenutzer. Ausschließlich dieser Broker und sein werkzeugloser Metadatenprozess lesen die eigenen privaten Anmeldedaten. Eine bestehende Lernworker-`auth.json` wird **nicht kopiert**: unabhängig rotierende Kopien desselben Refresh-Tokens könnten den vorhandenen Zugang beeinträchtigen. Der eigene explizite Geräte-Anmeldeflow verändert keine vorhandenen Anmeldedateien.

Der rootlose Einmalcontainer erhält nur:

- begrenzte öffentliche Quelltexte ohne `.git`, private Laufzeitdaten oder Betreibergeheimnisse, schreibgeschützt als Baseline;
- einen begrenzten schreibbaren tmpfs-Workspace (96 MiB), ein tmpfs für temporäre Dateien (128 MiB);
- neutrale Fehlerdaten und genau einen zeitlich begrenzten Unix-Proxy mit Dummycredential.

Das Root-Dateisystem ist schreibgeschützt, Netzwerk `none`, alle Capabilities entfernt, keine neuen Privilegien, höchstens 96 Prozesse, 1 GiB RAM und eine CPU. Kein Hostverzeichnis wird dem Modell schreibbar eingebunden. Keine Docker-/Podman-/SSH-/Git-/Datenbank-/Deployment-Sockets und keine echten Authdateien oder Tokens befinden sich im Werkzeugcontainer. Die CLI erhält ein frisches Home, `exec --sandbox danger-full-access --skip-git-repo-check --ephemeral --ignore-rules`; ein neues Git-Repository wird nicht angelegt. Dies ist ausdrücklich ein fester Container-only-Modus: der tatsächliche CLI0.162.1-Sandboxaufruf im vorhandenen Container brach ohne Inferenz mit Exit101 wegen fehlendem `bwrap` ab. Es gibt keine versprochene zweite innere Sandbox und keinen automatischen Modusfallback. Vor jedem CLI-Aufruf prüft der Agent `/run/.containerenv`, tatsächlich schreibgeschütztes Root-Dateisystem, echte begrenzte tmpfs-Mounts für `/workspace` und `/tmp`, schreibgeschützte Eingaben, `NoNewPrivs=1`, effektive/Bounding-Capabilities0, ausschließlich Loopback und keine aktive IPv4-/IPv6-Default-Route. Bei Abweichung endet er vor dem Modellaufruf. `agent.py --self-test` prüft dieselbe Grenze und eine lokale Shell ohne CLI-/Modellaufruf.

Der Hostbroker akzeptiert ausschließlich den festen Modell-/Reasoningpfad. Er ersetzt eingehende Authheader durch seine eigene Anmeldung, hält diese außerhalb der Werkzeuggrenze, erzwingt `store=false` und bietet keine allgemeine Internetweiterleitung. Höchstens vier Proxyhandler, begrenzte Request-/Responsegrößen, Socket-Readtimeouts, Gesamtfrist und aktives Schließen aller Verbindungen am Jobende begrenzen unvollständige Anfragen. Upstreamfehler werden ohne Rohtexte weitergegeben.

## Patch- und Prüfgrenze

Das Werkzeug gibt ein größenbegrenztes Allowlist-Archiv aus. Gzip wird **vor** dem TAR-Parser begrenzt dekomprimiert; Dateizahl, Gesamt-/Einzelgröße, Pfade, UTF-8, NUL, Links und Manifesthashes werden geprüft. Nur `.py`/`.dart` in bestehenden Anwendung-/Testverzeichnissen dürfen im Patch stehen. Bereits vorhandene Tests dürfen weder geändert noch gelöscht werden; neue Tests sind möglich. Abhängigkeiten und Betriebsdateien dürfen nicht geändert werden. Der Patch entsteht außen durch einen Diff gegen die unveränderliche Baseline, maximal 512 KiB; Dummyberechtigung und erkennbare private Schlüssel werden abgewiesen. Artefakte werden privat und gehasht gespeichert. Download und Review prüfen Größe/Hash erneut. Auch ein genehmigtes Review wendet nichts an.

Für `instructional_decisions.process` laufen sechs feste `pytest`-Beobachtungen vor und nach der Modellphase. Die Assertions und der Zähler leben im vertrauenswürdigen Brokerprozess und importieren **keinen** Candidatecode. Dieser führt nur begrenzte primitive JSON-RPCs für `schema_refs`/`validate` in separaten frischen, netzlosen Containern aus. Er kann weder Beobachterdateien, Prüfbericht noch Zähler erreichen. Die Fälle prüfen geschlossene Aufgaben, neue Verständnisprüfung, erlaubte Auswahl, fehlende Ressourcen, Ablaufkanten und weiterhin mögliche offene Übung; sie entsprechen gezielten Verträgen aus `test_decision_schema_incidents.py` und `test_instructional_decisions.py`.

Das sind gezielte Funktionsprüfungen, **keine vollständige PostgreSQL-/HTTP-/Flutter-Regression oder Sicherheitsattestation beliebiger Änderungen**. Unbekannte Funktionen und Dartänderungen melden `executed=false`, keine erfundenen bestandenen Tests. Vollständige Tests, Analyse, Diff-/Geheimnisprüfung und menschliches Review bleiben vor jeder Übernahme erforderlich. Vorher-/Nachherzähler stammen ausschließlich vom Beobachter, niemals aus Modellprosa.

Nach einem Prozessneustart werden laufende Datenbankaufträge als `failed/interrupted` beendet, aktive Claims freigegeben und unbekannte Kostenreservierungen erhalten. Eigene alte markierte Container und Jobverzeichnisse werden vor neuen Aufträgen bereinigt. Aufträge werden nicht automatisch wiederholt.

## Release und eigener Login

Erst nach Quellfreeze, Commit und sauberem Git-Arbeitsbaum (ignorierte Buildartefakte ausgenommen):

```sh
.venv/bin/python scripts/prepare_repair_source.py --commit "$(git rev-parse HEAD)" --output artifacts/repair-source.tar.gz
```

Das reproduzierbare Paket wird nur aus exakt diesen Gitblobs gebaut, enthält keinen Gitbestand und muss zusammen mit `release.json` in die Wurzel **desselben** Releases. Der Dispatcher verweigert abweichende oder fehlende Pakete. Es ist kein öffentlicher Download.

Der Operator installiert aus dem neuen Release (Installer ist nicht automatisch Teil eines normalen Updates):

```sh
sudo python3 /opt/schulpilot/current/deploy/install_repair.py
sudo schulpilot-repair login
sudo schulpilot-repair status
```

`login --device-auth` wurde anhand der tatsächlich installierten CLI0.162.1-Hilfe geprüft. Der interaktive Einmalcode gehört ausschließlich in diesen Operatorflow. `status` zeigt nur Credentialpresence und ausdrücklich keinen Inferenznachweis. Bestehende Lernanmeldung, Schlüssel und Suchfreigabe bleiben unverändert. Der Installer erstellt das gepinnte Werkzeugimage mit vorhandener Backend-`requirements.lock` und dem lokal verifizierten `pytest==9.1.1`, installiert Broker und Dispatcher, startet aber **keinen** Dispatcher und keine Inferenz.

Vor bewusster Dispatcheraktivierung: Migration0028, passendes Paket und Manifest, private Datenverzeichnisse sowie `OPERATOR_REPAIR_SOCKET=/run/schulpilot-repair/control.sock` im API-Environment prüfen. Nach gesicherter Konfiguration nur betroffene Dienste neu starten. Die API benötigt denselben Socketwert, damit der Adminzugang den separaten Katalog erreicht. Danach explizit:

```sh
sudo systemctl enable --now schulpilot-repair-dispatcher.service
```

Der Dispatcher hat einen eigenen Prozess und eine PostgreSQL-Sitzungssperre gegen doppelte Recoveryinstanzen, damit Reparaturen normale Lernaufträge nicht blockieren. Fehlende Anmeldung oder Prüfung bedeutet nicht verfügbar; kein stiller Ersatz.

## Echte künstliche End-to-End-Probe nach Installation

Der lokale Operator kann genau einen regulär reservierten Probeauftrag mit einer bestehenden synthetischen Adminsitzung auslösen. Token ausschließlich über stdin, niemals Argument oder Log:

```sh
/opt/schulpilot/current/venv/bin/python -m schulpilot.operator_repair_probe --session-stdin --request-key '<einmaliger-nicht-geheimer-Schluessel>'
```

Der Befehl liest eine Tokenzeile und meldet ausschließlich Auftrag-ID/Status. Ein HTTP-Client kann den Probe-Fixtureparameter nicht wählen. Der Worker schaltet genau eine bekannte `decision_closed`-Schutzbedingung **nur in der kopierten** `instructional_decisions.py` aus; Produktionsdateien und Daten bleiben unverändert. Der Probeauftrag akzeptiert ausschließlich einen Patch dieser Quelldatei. Unveränderliche externe Tests müssen vorher **5 bestanden/1 fehlgeschlagen**, nach einem passenden Modellfix **6 bestanden/0 fehlgeschlagen** melden. Der echte Modelltransport muss `gpt-6.1-sol/max` verwenden; bei Unverfügbarkeit abbrechen, keine Substitution oder automatische Wiederholung. Patch und Kostenbeleg prüfen; nichts anwenden. Ein späterer Produktfehler braucht seinen eigenen regulären Auftrag.

Die echte Modellprobe führt der Operator erst nach eigener Anmeldung und
quellgebundenem Deployment durch. Ein Katalogeintrag ersetzt diesen Nachweis nicht.

## Aktueller technischer Nachweis

Die getrennte Staginginstallation ist ausgeführt. Der wirkliche rootlose
Container bestand `agent.py --self-test`: Runtimegrenzen und lokaler Shellzugriff
im begrenzten Workspace bestätigt, **null Modellaufrufe**
(`artifacts/ux90/repair-outer-selftest.json`). Die Installation startet keinen
Dispatcher; der bisherige API-/Lernbetrieb bleibt auf seinem Release.
Ein bei laufendem eigenem Login beobachteter `ETXTBSY`-Installationsfehler ist
durch atomaren Binaryaustausch behoben. Sieben direkte Fälle belegen unveränderte
laufende Prozesse, identischen Inode bei identischem Binary und geschützte
Dateitypen. Die vorherigen61 Regressionen und13 Runtimeguardfälle sind ebenfalls
grün; überlappende Tests werden nicht addiert.

Die persönliche Reparaturanmeldung und der echte Sol/max-Reparaturauftrag sind
noch offen. Weder der reine Katalog noch die Shellprobe werden als erfolgreiche
KI-Reparatur ausgegeben.

## Primärquelle

[Offizielle Codex-Dokumentation: Non-interactive mode, permissions and safety](https://learn.chatgpt.com/docs/non-interactive-mode#permissions-and-safety), am22.10.2026 gelesen. Verwendete Flags zusätzlich gegen die tatsächlich installierte CLI0.162.1 (`exec --help`, `login --help`) geprüft; neuere Dokumentationsoptionen werden nicht blind vorausgesetzt.


## Deployment und Rückweg

`scripts/deploy.sh` validiert das vorhandene Paket vor jedem Remoteschritt bytegenau gegen die sauberen HEAD-Blobs, lädt es ausschließlich nach `<release>/repair-source.tar.gz` und setzt `root:schulpilot`/`0640`. Es wird weder nach `web` noch `downloads` kopiert. Bereits installierte Reparaturdienste werden **vor** Aktivierung und Migration gestoppt. Erst nach passendem aktivem Release und erfolgreicher API-Healthprüfung werden ausschließlich die vorher aktiven Reparaturdienste wieder gestartet; fehlende oder absichtlich inaktive Dienste bleiben unangetastet. Die normale Aktualisierung installiert den Reparaturbroker nicht neu.

Scheitert Aktivierung, Migration oder Healthprüfung, bleiben Broker und Dispatcher gestoppt, auch wenn der vorhandene Aktivator die Quellverknüpfung zurücksetzt. Das ist eine beabsichtigte Sperre: kein alter Dispatcher darf mit einem unbekannten Schema-/Quellstand weiterarbeiten. Vor manuellem Rollback beide Reparaturdienste stoppen; Datenbankschema, Release-Manifest, passendes Quellpaket und Dienstkompatibilität prüfen. Dann ausschließlich kompatible zuvor aktive Dienste bewusst starten. Laufende Reparaturen werden beim nächsten gültigen Dispatcherstart als unterbrochen auditiert, nicht automatisch neu begonnen. Vor Betreiberupdates des Brokerimages/-codes beide eigenen Reparaturdienste bewusst stoppen und danach gezielt wieder starten; Lernworker-Policy und Anmeldung bleiben unverändert.

[Offizielle Codex-Sandboxdokumentation: Container als äußere Isolationsgrenze](https://learn.chatgpt.com/docs/agent-approvals-security#os-level-sandbox), am22.10.2026 tatsächlich gelesen; die dokumentierte Container-only-Option ersetzt hier eine nicht verfügbare innere bwrap-Schicht, ohne Hostrechte zu erweitern.
