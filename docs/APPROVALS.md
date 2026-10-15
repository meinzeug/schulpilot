# Betreiberfreigabe und technische Verfügbarkeit

Am 14.10.2026 hat der Auftraggeber ausdrücklich erklärt: „anbieter und datenschutz freigabe ist erteilt“.
Diese Betreiberentscheidung wird für SCHULPILOT dokumentiert und bei der Konfiguration berücksichtigt. Eine erneute Zustimmung wird dafür nicht verlangt. Dieses Protokoll behauptet nicht, dass Vertragsunterlagen oder eine unabhängige Rechtsprüfung im Repository vorliegen.

Die Entscheidung umfasst die beauftragte serverseitige KI-Verarbeitung. Die Google-/Push-Anbindung ist technisch beauftragt; der spätere ausdrückliche Firebase-Übergabeauftrag verlangt jedoch eine eigene konkrete Prüfung und Betreiberentscheidung vor allgemeinem Push-Versand. `PUSH_APPROVED` bleibt deshalb ausgeschaltet. Ein vorhandener Schlüssel oder eine erfolgreiche FCM-Validierung ersetzt diese Entscheidung nicht. Technische Schutzvorgaben bleiben bestehen: keine Trainingsfreigabe für echte Inhalte, geschützte Providerroute, keine privaten Inhalte in Push, keine Analytics, keine Weitergabe von Schlüsseln.

## Nachfolgender Auftrag zum Produktionsstart

Nach der Übergabe mit ausdrücklich ausgewiesener ausgeschalteter Push-Freigabe hat der Betreiber am 14.10.2026 angewiesen: „warum test apk? das muss alles endlich in production übergehen“. Dieser nachfolgende Auftrag wird als Betreiberentscheidung zum regulären Betrieb einschließlich freiwilliger Firebase-Benachrichtigungen umgesetzt. Das ersetzt die vorherige vorläufige Push-Sperre für diese Installation; neue Installationen und reine Cloud-Prüfwerkzeuge dürfen weiterhin keine automatische Freigabe erteilen. Die tatsächliche Aktivierung wird auditierbar mit dem vorhandenen technischen App-/API-/Key-Nachweis und Verweis auf die Datenschutzprüfung gespeichert. [Konkrete Bedingungen und Grenzen](PRODUCTION.md). Keine unabhängige Rechtsprüfung, unbekannte Vertragspartei oder physische Geräteabnahme wird dadurch erfunden.

## Historische Endpunktprüfung mit zusätzlicher ZDR-Pflicht

Zwei ausdrückliche synthetische Prüfaufrufe am 14.10.2026:

| Funktion | Modell / fest gewählter Upstream | Schutzvorgaben | Ergebnis |
| --- | --- | --- | --- |
| Bilderkennung | dots-studio/dots-3-note-preview:free / atlas-cloud/fp8 | data_collection=deny, zdr=true, Preisgrenze 0 | HTTP 404, kein Endpunkt für die Routingvorgaben |
| Aufgaben | nvidia/nemotron-3-super-120b-a12b:free / nvidia | data_collection=deny, zdr=true, Preisgrenze 0 | HTTP 404, kein Endpunkt für die Routingvorgaben |

Es wurden ausschließlich feste künstliche Bilder/Texte gesendet. Keine echten Kinderinhalte, kein Ersatzanbieter und keine bezahlten Endpunkte. Kosten der abgelehnten Anfragen sind nicht belegt und werden nicht als nachgewiesene Nullkosten bezeichnet.

Die globale Betreiberfreigabe und die Anbieterfreigabe werden separat von `production_block_reason` geführt. Die nachfolgenden Erkenntnisse ersetzen die damalige technische Sperrentscheidung für den neu gewählten Standard; die obigen HTTP-404-Ergebnisse mit ZDR bleiben als historische Testergebnisse erhalten.

## Ausdrücklich beauftragter kostenloser Standard

Anschließend bestätigte der Auftraggeber: „openrouter mit free modellen wird standard. freigabe erteilt.“ Zusätzlich soll der reguläre KI-Lernablauf ausdrücklich mit Kinderaccounts funktionieren. Die erneute Zustimmung wird nicht verlangt.

Die getrennte synthetische Prüfung ergab: `dots-studio/dots-3-note-preview:free` / `atlas-cloud/fp8` funktioniert für Bild und Text mit **data_collection=deny, zdr=false und Preisgrenze 0**. Dagegen antworteten die geprüften Nvidia- und Liquid-Free-Textendpunkte mit diesen Filtern mit HTTP 404. Der Standard wechselt deshalb ausdrücklich für Bild und Text auf Dots/AtlasCloud, ohne Datensammlung zu erlauben. ZDR wird zusätzlich nicht erzwungen und nicht behauptet.

Ein lokaler auditierter Operatorwechsel und die erfolgreiche dreiteilige Bild-/Aufgaben-/Tagespaketprüfung sind vor technischer Aktivierung erforderlich. Einrichtung, Datenregeln und angekündigtes Preview-Ende: [AI_STANDARD.md](AI_STANDARD.md). Tatsächlich durchgeführte öffentliche Abnahme: [STATUS.md](STATUS.md).

Erneute kostenlose technische Prüfung nach einer Konfigurationsänderung:

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py probe-private-route'
```

Dieser lokale Befehl führt genau drei feste synthetische kostenlose Anfragen für Bild, Einheit und Tagespaket aus und speichert den technischen Befund. Er erteilt keine neue rechtliche Freigabe und aktiviert keine kostenpflichtigen Modelle.

Der Firebase-Projektzugang und ein minimal berechtigtes Senderkonto sind inzwischen eingerichtet; tatsächliche Prüfergebnisse stehen in `CHATGPT_HANDOFF.txt`. Play-Console-Zugang und vollständige Betreiberangaben bleiben eigenständige Voraussetzungen. Eine Betreiberfreigabe ersetzt weder Zugangsdaten noch eine unbekannte Anschrift.

## Betreiberentscheidung vom 15.10.2026: Codex mit Websuche

Der Betreiber beauftragt ausdrücklich, den KI-Provider dauerhaft auf Codex CLI umzustellen und Codex mit `--search` auszuführen. Er übernimmt bei Bedarf die manuelle Verbindung auf dem Server. Diese Anbieterauswahl ersetzt die frühere OpenRouter-Free-Auswahl; kein impliziter Fallback. Die technische Aktivierung bleibt bis zur eigenen isolierten Anmeldung und dem gezählten synthetischen Bild-/Aufgaben-/Pakettest gesperrt. Es werden keine Entwicklungszugänge übernommen und keine Konto-/Vertragsrechte aus bloßer Anmeldung behauptet. Siehe [CODEX.md](CODEX.md).
