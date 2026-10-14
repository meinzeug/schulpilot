Aktueller Freigabestand: Der Betreiber hat die Anbieter- und Datenschutzfreigabe am 14.10.2026 ausdrücklich erteilt. [APPROVALS.md](APPROVALS.md) dokumentiert dies. OpenRouter mit kostenlosen Modellen ist ausdrücklich als Standard beauftragt. Die aktuelle Konfiguration, die zusätzliche ZDR-Einstellung und der technische Freigabetest stehen in [AI_STANDARD.md](AI_STANDARD.md). `production_block_reason` sperrt technisch ungeprüfte Routen getrennt von der Betreiberfreigabe. Keine erneute Betreiberzustimmung erforderlich, kein heimlicher Providerwechsel. Die folgenden Einrichtungsregeln bleiben als allgemeine Schutzvorgaben bestehen.

# KI-Anbieter und Freigabegrenzen

## Aktueller Stand

Es ist kein kostenpflichtiger KI-Anbieter öffentlich aktiviert. Keine Kundenschlüssel erforderlich; später konfigurieren ausschließlich Betreiber die serverseitigen Zugänge. Die synthetische Demo ist eine separate feste Übungsquelle, kein Fallback bei Providerfehlern und keine vorgetäuschte OCR.

OpenAI verwendet `POST /v1/responses` mit Bildinput, `text.format`/JSON Schema, festem Ausgabelimit, ohne Werkzeuge und `store:false`. OpenRouter verwendet `POST /api/v1/chat/completions`, JSON Schema, Bildinput und ausschließlich das festgelegte Modell sowie `provider.only` für einen ausdrücklich freigegebenen Upstream (`upstream=<slug>` im Fähigkeitsnachweis), `allow_fallbacks:false`, `require_parameters:true`, `data_collection:deny` und die gespeicherte Einstellung `openrouter_require_zdr`. Im ausdrücklich freigegebenen Free-Standard gilt `zdr:false`; bestehende Installationen behalten ihre bisherige Einstellung bis zum Operatorwechsel. Die Datensammlung bleibt gesperrt. Die normale Konfiguration enthält keine erfundenen Modellnamen oder Preise. Übungen und Bildextraktion können ausdrücklich verschiedene Modelle/Upstreams verwenden; diese werden gespeichert und angezeigt. Preisobergrenzen müssen sämtliche ausgewählten Modelle abdecken. Modellfähigkeiten und Preisobergrenzen werden mit Quelle/Datum hinterlegt. Der Metadaten-Verbindungstest löst keine Lernanfrage aus und behauptet keinen bestandenen Bild-/Schematest.

Alle Ausgaben durchlaufen zusätzlich Pydantic- und Aufgabenvalidierung. Unvollständige Antworten, Ablehnungen, unbekannte Typen, doppelte IDs oder ungültige Zuordnungen werden verworfen. Kein Wechsel zu einem anderen Anbieter, kein automatischer Wiederholungsversuch. Materialtexte sind Daten, keine Anweisungen; die normalen API-Adapter haben keine Werkzeuge. Fehlermeldungen enthalten weder Providerantworten noch Schlüssel oder private Eingaben.

## Kostenkontrolle

Eine Transaktion reserviert Aufrufanzahl und konservative Mikro-USD-Obergrenze im Familien- und Unternehmens-Monatskonto. Bedingte Datenbankupdates verhindern Überschreitung unter Parallelität; Auftrags-ID und Idempotency-Key verhindern doppelte Verarbeitung. Auch Fehlversuche sind im Aufruflimit enthalten. Konfigurierte Ein-/Ausgabepreisobergrenzen plus vollständige Byte-Obergrenze des Requests und Ausgabetokenlimit werden vor dem Versand geprüft. Dies ist bewusst konservativ, besonders bei Bildern.

Von OpenRouter gemeldete endliche, nichtnegative Usage-Kosten werden übernommen. Andernfalls werden bekannte Tokenzahlen mit der dokumentierten Preisobergrenze verrechnet und als Schätzung gekennzeichnet, nicht als Rechnung. Fehlende Usage/Kosten bleiben `null`/unbekannt und behalten die volle Reservierung. Eine unerwartete Überschreitung aktiviert den Notfallstopp. Anbieterprojekt-Limits sind zusätzlich erforderlich, insbesondere wenn dasselbe Providerkonto anderswo verwendet wird; unsere DB kann fremde Aufrufe nicht begrenzen. Konfigurationsrevisionen verhindern das Ausführen alter Jobs mit inzwischen anderen Modellen/Preisen.

## Freigaben und technische Aktivierung

Die Freigabe erfordert **beides**: lokal `REAL_DATA_APPROVED=true` mit `PRIVACY_EVIDENCE`, und eine anbieterspezifische Freigabe/Nachweise in der Admin-Konfiguration. Zusätzlich müssen Modellfähigkeiten, Preisobergrenzen und Schlüssel vorhanden und der Notfallstopp aufgehoben sein. Eine Familien-Demo-Markierung macht beliebige hochgeladene Texte/Bilder nicht synthetisch; echte Uploads in Demo-Familien sind deshalb gesperrt.

Die Betreiberentscheidung zu Anbieter, Datenschutz und kostenlosem Standard ist dokumentiert. Konkrete Vertrags-, Aufbewahrungs-, Regions- und Minderjährigenbedingungen bleiben betreiberseitig zu erfüllen; tatsächliche synthetische Live-Anbietertests sind zusätzlich Voraussetzung der technischen Aktivierung. Die offizielle OpenAI-Unter-18-Dokumentation verlangt besondere Schutzmaßnahmen und ZDR vor bestimmten Verarbeitungen personenbezogener Kinderdaten; `store:false` allein erfüllt das nicht. OpenRouter-Einstellungen ersetzen keine Prüfung aller beteiligten Upstreams und Konto-/Cacheeinstellungen. Die Prüfung ist keine erteilte juristische oder vertragliche Freigabe.

## Codex CLI, experimentell

Die dokumentierte nichtinteraktive Schnittstelle `codex exec` und die installierte Version **0.162.1** wurden anhand offizieller Dokumentation und `--help` geprüft. Implementiert ist ein separater Unix-Socket-Adapter und Worker unter `workers/codex/`; **nicht auf dem App-Server aktiviert oder mit echten Zugangsdaten ausgeführt**.

Der Worker benötigt einen separat geprüften Rootless-Podman-Container, einen verifizierten CLI-Release-Binary 0.162.1, einen eigenen kommerziellen API-Projektschlüssel sowie Nutzungs-/Datenschutzfreigabe. Containerbasis ist per SHA-256 fixiert. Das Containerfile erwartet das CLI-Binary als ignorierte Datei `codex` im Build-Kontext; es ist absichtlich nicht enthalten. Der Server hat derzeit keinen eingerichteten Podman-/Docker-Worker. Die Vorlage wird vor einer Aktivierung an Benutzerabbildung, Socket-Gruppenrechte und Netzwerkregeln angepasst und überprüft.

Kein Host-Home, Repository, Docker-Socket, SSH-, Hetzner-, GitHub-, Entwicklungs- oder Deploymentzugang wird eingebunden. Container: read-only, ohne Fähigkeiten, begrenzter Speicher/CPU/PIDs, pro Auftrag geleertes temporäres Verzeichnis, keine parallel gespeicherten Familien. API ausschließlich Unix-Socket, kein öffentlicher Listener und keine frei wählbaren Befehle. Programmaufruf per fester Argumentliste und stdin, niemals Shell-Interpolation.

Die CLI erhält nur einen einmaligen lokalen Gatewaytoken, keinen Upstream-Schlüssel. Der interne Gateway lässt **höchstens einen** Upstream-Responses-Aufruf pro Auftrag zu, entfernt sämtliche Werkzeuge, erzwingt Modell/Schema/Ausgabelimit/`store:false` und prüft die Kostenobergrenze einschließlich CLI-Kontext. Shell, Unified Exec und Websuche sind zusätzlich deaktiviert. Wiederholungen werden abgelehnt. Authentifizierung erfolgt über einen eigenen API-Schlüssel im Worker, nicht über die Entwicklungs-`auth.json` oder ein weitergegebenes ChatGPT-Abonnement. Nutzung als kommerzieller Lernprovider bleibt bis zur vertraglichen Prüfung gesperrt.


## Frühere synthetische Tests und abgegrenzter Testpfad

`SYNTHETIC_AI_ENABLED=true` erlaubt ausschließlich einen separaten festen Testpfad. Nur synthetische Familien können das serverseitig gezeichnete Blatt `fractions-v1` anlegen. Eigene Bilder bleiben dort verboten; der Adapter ersetzt beim Test sämtliche Aufrufertexte, Bilder, Namen, Ziele und Aktivitäten durch Konstanten. Auch die Bestätigung erlaubt keine freien Änderungen. Die echte Datenschutzfreigabe wird dadurch nicht gesetzt.

Früher am 14.10.2026 mit dem ausdrücklich freigegebenen OpenRouter-Schlüssel getestet (historischer Testbefund, nicht die aktuelle Standardroute):

- Bilder: `dots-studio/dots-3-note-preview:free`, ausschließlich `atlas-cloud/fp8`. Der erste Prompt lieferte eine unbrauchbare Zusammenfassung. Nach Trennung der Extraktionsanweisung wurden Begriffe, Regeln und Bruchbeispiel korrekt erkannt.
- Einheiten: `nvidia/nemotron-3-super-120b-a12b:free`, ausschließlich `nvidia`. Tatsächlich gültige strukturierte Einheit mit überprüften Lösungen. Dots-Ausgaben mit doppelten IDs/falscher Lösung wurden nicht als erfolgreiche Einheit übernommen. Kein stiller Modellwechsel: separate, sichtbare Konfiguration nach Funktion.

Alle fünf direkten Diagnose-Aufrufe meldeten `usage.cost=0`. Zwei Dots-Übungsausgaben bestanden die Validierung nicht; der frühe Bildversuch war trotz Schema inhaltlich unzureichend. Diese Fehler sind Teil des Testbefunds. Die erfolgreiche Extraktion und Nvidia-Einheit ersetzen keine umfassende pädagogische Qualitätsabnahme.

Jeder Test prüft erneut den exakt gewählten Endpunkt im offiziellen `/models/.../endpoints`-Katalog (Preis 0, Schema, bei Bedarf Bild). Zusätzlich erzwingt die Anfrage `:free`, `max_price` für Prompt/Completion/Request gleich 0, feste Providerbindung und keine Fallbacks. Ein atomarer unternehmensweiter Tageszähler begrenzt Tests standardmäßig auf 40; Familienkontingente, Fehlerzählung und Notfallstopp gelten zusätzlich. Keine automatische Wiederholung.

Nur der konstante synthetische Testpfad darf `data_collection:allow` verwenden. Das ist keine Datenschutzfreigabe für freie Eingaben. Die normale Route und `probe-private-route` erzwingen `data_collection:deny` und die ausdrücklich gespeicherte ZDR-Einstellung. Beide Freigabestufen bleiben erforderlich. Fehlende Kosten bleiben unbekannt.

Historischer Test-Import (setzt die Anbieterfreigabe zurück und ist nicht für die Aktivierung des normalen Standards gedacht): `deploy/admin.py configure-free-tests` liest den Schlüssel ausschließlich von stdin, prüft die Endpunkte und speichert ihn verschlüsselt. `~/or.txt` bleibt privat auf dem Entwicklungsrechner und außerhalb des Repositorys. Die SSH-Übertragung erfolgt ohne Schlüssel im Kommandozeilenargument.
