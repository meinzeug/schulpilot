# Betreiberfreigabe und technische Verfügbarkeit

Am 14.10.2026 hat der Auftraggeber ausdrücklich erklärt: „anbieter und datenschutz freigabe ist erteilt“.
Diese Betreiberentscheidung wird für SCHULPILOT dokumentiert und bei der Konfiguration berücksichtigt. Eine erneute Zustimmung wird dafür nicht verlangt. Dieses Protokoll behauptet nicht, dass Vertragsunterlagen oder eine unabhängige Rechtsprüfung im Repository vorliegen.

Die Entscheidung umfasst die beauftragte serverseitige KI-Verarbeitung und die vorbereitete Google-/Push-Anbindung. Technische Schutzvorgaben bleiben bestehen: keine Trainingsfreigabe für echte Inhalte, geschützte Providerroute, keine privaten Inhalte in Push, keine Analytics, keine Weitergabe von Schlüsseln.

## Konkrete Endpunktprüfung

Zwei ausdrückliche synthetische Prüfaufrufe am 14.10.2026:

| Funktion | Modell / fest gewählter Upstream | Schutzvorgaben | Ergebnis |
| --- | --- | --- | --- |
| Bilderkennung | dots-studio/dots-3-note-preview:free / atlas-cloud/fp8 | data_collection=deny, zdr=true, Preisgrenze 0 | HTTP 404, kein Endpunkt für die Routingvorgaben |
| Aufgaben | nvidia/nemotron-3-super-120b-a12b:free / nvidia | data_collection=deny, zdr=true, Preisgrenze 0 | HTTP 404, kein Endpunkt für die Routingvorgaben |

Es wurden ausschließlich feste künstliche Bilder/Texte gesendet. Keine echten Kinderinhalte, kein Ersatzanbieter und keine bezahlten Endpunkte. Kosten der abgelehnten Anfragen sind nicht belegt und werden nicht als nachgewiesene Nullkosten bezeichnet.

Die globale Betreiberfreigabe und die Anbieterfreigabe werden separat von `production_block_reason` geführt. Private Speicherung ist freigegeben; die inkompatible externe KI-Route bleibt technisch gesperrt. Die ausdrücklichen kostenlosen synthetischen Testwege bleiben verfügbar.

Erneute kostenlose technische Prüfung nach einer Konfigurationsänderung:

```bash
ssh dorfspy 'python3 /opt/schulpilot/current/deploy/admin.py probe-private-route'
```

Dieser lokale Befehl führt höchstens zwei feste synthetische kostenlose Anfragen aus und speichert den technischen Befund. Er erteilt keine neue rechtliche Freigabe und aktiviert keine kostenpflichtigen Modelle.

Fehlende Firebase-/Play-Projektzugänge und vollständige Betreiberangaben sind eigenständige Voraussetzungen. Eine Betreiberfreigabe ersetzt keine Zugangsdaten oder noch unbekannte Anschrift.
