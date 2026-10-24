# Quellengebundene grafische Erklärschritte

Stand: Implementierung 107 im isolierten Arbeitsstand. Die hier beschriebenen lokalen Tests sind kein Nachweis einer erfolgreichen echten Modellerzeugung, eines Live-Deployments oder einer vollständigen Lehrplanabdeckung.

## Datenkette

1. Der ausdrücklich gestartete normale Lernauftrag lädt seine autorisierten, bestätigten Materialrevisionen. `source_lineage.learning_source` liefert nur die als Lehrgrundlage nutzbaren Blöcke; ausgeschlossene Schülerfehler, ungeklärte Korrekturen und Lesefehler werden nicht stillschweigend zum Musterwissen.
2. `visual_references.with_visual_context` bindet diese Inhalte an `p1`, `p2` usw. und wählt tatsächlich gespeicherte eigene Grafikrezepte. Fehlt bei ausgewählten Seiten für eine Themen-/Paketgruppe jeder nutzbare Block, endet der Auftrag vor dem Modellaufruf. Ein bestehender ausdrücklicher Elternauftrag ohne Foto bleibt ein eigener Vertragsfall.
3. `learning_entry` ergänzt den serverseitig gewählten Einstieg und tatsächliche Kompetenzbelege. `with_foundation_context` bindet ausschließlich über `competences.resolve_reference` aufgelöste eigene Grundlagenregeln samt serverberechnetem Probe-Beispiel als `r1`, `r2` usw. Diese Belege tragen sichtbar „Zusatzwissen · eigene kuratierte Grundlagenregel“ und erhalten keine fingierte Material-ID.
4. Das endgültige Providerschema verlangt für den neuen gebundenen Grafikpfad Einführungs- und Frage-Schritte. Jeder Schritt enthält Text, eine bestehende finite `PresentationV1`, eine erlaubte Rezept-ID/Version, Quellenrefs und eine Offenlegungsstufe. Frageanzahl, Antwortprüfung, Reservierung und Token-/Zeitgrenzen bleiben im jeweiligen bestehenden Auftrag.
5. Nach dem Transport prüfen die vorhandenen Fach-/Szenenvalidatoren sowie `visual_references.validate_steps` die Quellen, Fach-/Gruppenzuordnung, Referenzversion und Parameter. Danach werden Rechte und aktuelle Quellenfassungen vor der Speicherung erneut geprüft.
6. `UnitVisualSnapshot` speichert die gebundenen Schritte getrennt von den vorhandenen Fragen und Antworten. `unit_data` und die Erklärungsantwort projizieren ausschließlich zulässige Offenlegungsstufen. Flutter stellt einen aktuellen Schritt mit seinem Text und seiner Grafik zusammen dar.

Der vorhandene externe Medienkatalog bleibt ein anderer Datenbestand. Ein Video-/Textverweis ist kein Grafikrezept und kein Kompetenznachweis.

## Register und Tabellen

Migration `0036` ergänzt:

| Tabelle | Inhalt |
| --- | --- |
| `visual_reference_versions` | Eigene unveränderliche Rezept-ID, Ganzzahlversion, SHA-256 und Rezeptdaten. |
| `unit_visual_snapshots` | Private Einführungsschritte, fragebezogene Schritte, Quellen-/Referenzbindungen, Status, Grund und Receipts einer gespeicherten Runde. |
| `unit_visual_positions` | Private technische Leseposition je Einheit und angemeldetem Nutzer, Quellen-Signatur, CAS-Revision und Änderungszeit. |

`reference/visual-v1.json` enthält 17 eigene Rezepte. Sie decken unter anderem Brüche, Satzglieder/Zeitfolgen, Reflexion/Stromkreis, Teilchen/Moleküle, Pflanze/Zelle, Wasser-/Orientierungsmodelle sowie Funktions-, Daten- und Logikdarstellungen ab. Ein streng belegtes allgemeines Phasen-/Beziehungsrezept ist für alle 24 bestehenden Fachprofile verfügbar. Das bedeutet weder 24 vollständig kuratierte Fachlehrpläne noch eine Grafik für jede denkbare Aussage.

Die Seedfunktion fügt Versionen idempotent hinzu und verweigert eine Änderung des Inhalts unter gleicher ID/Version. Persistierte Schritte tragen den Rezept-Digest und einen separaten `parameter_digest` der tatsächlich öffentlichen Darstellung. Materialrefs enthalten aktuelle Revisionen und stabile Block-IDs. Eigene Grundlagenrefs enthalten eine eigene Registerversion/Digest und bleiben von fotografierten Quellen unterscheidbar. Auch nicht unmittelbar in einem Schritt zitierte, für den Auftrag ausgewählte Materialrevisionen bleiben in den privaten `source_bindings` gebunden.

## Schrittvertrag und Offenlegung

Ein Modellschritt besitzt `id`, `text`, nullable `competence_id`, `disclosure`, `presentation`, `reference` und `source_refs`. Einführungen haben höchstens drei Schritte, Frageerklärungen höchstens zwei. IDs sind höchstens 32 Zeichen lang. Text und alle Grafikblöcke eines Schritts müssen dieselbe Offenlegungsstufe tragen.

Einführungen verwenden `given`; Frage-Schritte verwenden passende Hinweisstufen oder `solution`. Ungeöffnete Hinweis-/Lösungsschritte und ihre Texte werden nicht öffentlich projiziert. Eine ausdrücklich geöffnete fragebezogene Erklärung ist durch das bestehende gespeicherte Erklärungsereignis belegt. Private wörtliche `source_excerpt`-Felder werden wie bei bestehenden Fachgrafiken entfernt. Berechtigte Elternvorschau bleibt von der Kinderbearbeitung getrennt.

Der neue Vorwissenseinstieg zeigt vor den Probe-Antworten eine neutrale Einleitung. Nach der Probe öffnet der Anschluss den gespeicherten allgemeinen Zusammenhang; er fordert nicht die Lösung der nächsten Anwendungsfrage als Beispiel an. Ablaufstatus „bearbeitet“ bedeutet keine fachliche Beherrschung. Kompetenzbeobachtungen referenzieren vorhandene originale Antworten, nicht Animation, Medienklick, Leseposition oder Modellbehauptung.

## Gespeicherte Altrunden

`explanation_visual_status` unterscheidet `ready`, `incomplete` und `legacy_text`; `explanation_visual_reason` beschreibt etwa fehlende Schritte, nicht auflösbare Fach-/Referenzbindung, ungültige Grafik oder geänderte Quellen. Alter Text bleibt lesbar. Er wird nicht als fertig grafisch aufbereitete Erklärung ausgegeben.

Ein ausdrücklicher `POST /units/{id}/visual-explanation` mit `Idempotency-Key` fordert eine endliche zusätzliche Grafikaufbereitung an. Sie benutzt die reguläre Unit-Anbieterroute, Reservierung, Familientarife und Grenze eines aktiven Kinderauftrags. Der kompakte Auftrag erstellt einen Einführungsschritt und einen Schritt pro bereits gespeicherter Frage, höchstens für acht Fragen. Ein zweiter Versuch verlangt eine neue bewusste Anfrage; es gibt keine automatische Wiederholung.

Das Ergebnis schreibt ausschließlich den Sidecar. Begonnene/pausierte Fragen, Antworten, Versuche und Status werden nicht ersetzt. Eine berechtigte Elternanfrage erzeugt keine Kinderaktivität. Synthetische feste Demoaufgaben lösen darüber keinen zusätzlichen Modellauftrag aus. Reine GETs und Statuspolls starten keine KI.

## Lokale Darstellung und Position

`LearningExplanation`/`SavedVisualExplanation` zeigen jeweils den aktuellen gespeicherten Text und dessen Grafik zusammen. Ältere reine Texterklärungen behalten den vorhandenen Lesepfad. Erklärungsschrittwechsel, Vor-/Zurück, Vorlesen und die vorhandene Vergrößerung bleiben bedienbar; Antwortentwürfe und IME werden nicht durch einen neuen Eingabevertrag ersetzt.

`LearningGraphicScope` transportiert nur einen endlichen lokalen Grafikzustand. Brüche unterstützen Kreis/Balken und Ganzes/Nenner/Zähler; Szenen unterstützen gespeicherte Phasen, bewusstes Abspielen, Pause und Scrubbing. Funktions-/Daten-/Logikexploration verwendet nur vorhandene geprüfte Parameter. Bereits freigegebene `given`-Blöcke erhalten diese Exploration ausschließlich innerhalb eines gespeicherten Erklärschritts; bestehende globale Offenlegungsregeln werden nicht pauschal gelockert. Reduzierte Bewegung und Hintergrund-/Routen-/Kontenwechsel stoppen die vorhandenen Animationen.

`GET /units/{id}/visual-position` liest die private Position. `PUT` speichert nur eine ausdrückliche Änderung mit `source_signature`, CAS-`revision` und einer validierten Position. `X-Schulpilot-Account` bindet beide Aufrufe an das tatsächlich angemeldete Konto, auch bei einem Cookiewechsel in einem anderen Tab. Vor dem Schreiben werden Anmeldung und Zugriffsrechte unter den bestehenden Einheit-/Kind-Sperren erneut geprüft.

Eine Position enthält nur `explanation_kind`, nullable `question_id`, `explanation_step_id`, `graphic_index` und einen erlaubten `graphic_phase`. Sie kann keine ungeöffnete Lösung freischalten. Höchstens acht Positionen je Nutzer bleiben bis 30 Tage erhalten; überholte Quellenpositionen werden beim Lesen ignoriert. GETs speichern nichts. Die Position erzeugt keine Antwort, Zeit oder Kompetenz; Unit-/User-Löschung und private Exporte/Aufbewahrung führen sie getrennt mit.

Der tatsächliche gespeicherte Lernweg erscheint am breiten Desktop rechts und mobil als bewusst geöffnete Ansicht. Ohne Backendplan wird kein Weg erfunden. Bearbeitungsposition und vorhandene Antwortbelege sind getrennt beschriftet.

## Schulbuddy

Die sichtbare Erklärung publiziert nur ihre serverauflösbaren IDs: `explanation_kind`, `explanation_step_id`, `graphic_index` und `graphic_phase`. Erlaubt sind `initial`, finite Bruchfoki sowie tatsächlich vorhandene Szenen- und wissenschaftliche Auswahlindizes. Der Backendresolver liest die wirklich freigegebenen gespeicherten Texte/Parameter; der Client schickt keine beliebigen Grafiktexte, Formeln oder Koordinaten als neue Wahrheit. Auch die vergrößerte Erklärung behält diese Bindung. Chatentwürfe und Antworten bleiben an ihren bisherigen Kontext gebunden.

## Grenzen und Prüfstand

- Quellenbindung und finite Parameterprüfung sind keine vollständige semantische Fachprüfung beliebiger freier Prosa. Es gibt insbesondere enge Bruchwert-/Gleichungs-, Winkel- und benannte Grundseiten-/Höhenprüfungen; die bestehenden Fachvalidatoren bleiben zusätzlich aktiv.
- Szenen benötigen belegte Beziehungen, mindestens zwei Phasen und eine tatsächliche Veränderung von Hervorhebung oder Beziehungen. Unveränderte dekorative Wortkästen ergeben keinen gültigen Phasenbeleg.
- Nicht jede feste Fachfamilie ist animiert. Beispielsweise bleiben Reflexions-, Teilchen- oder Pflanzenfamilien fachliche statische Vektoren. Echte lokale Interaktion ist für die beschriebenen Bruch-, Szenen-, Funktions-, Daten- und Logikpfade vorhanden.
- Der lokale Backendlauf `schulpilot107-visual-final-gate.log` bestand 196 künstliche bzw. gemockte Fälle. Darunter sind tatsächliche Adapter-Schema-/Receipttransporte ohne externen Anbieteraufruf, Sidecar-Rechte-/Quellenwechsel und Positions-CAS/Privatheit. Die Fluttertests sind gesondert von Root abzunehmen. Daraus folgt kein behaupteter Live-, OCR- oder echter Modellerfolg.
