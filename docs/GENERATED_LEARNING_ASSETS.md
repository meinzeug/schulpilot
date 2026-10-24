# Geteilte KI-Lernbausteine

Dieser erste vertikale Pfad erzeugt **unbewertete KI-Erklärungen und Erkundungsimpulse**, keine geprüften Antwortschlüssel und keine Schulnoten. Die vorhandenen kuratierten VisualReference-Rezepte bleiben getrennt. Technisch validierte KI-Beispiele gelten weiterhin als `factual_status: unassessed`.

## Öffentliche Grundlage und unveränderliche Version

`LearningAssetSpec` akzeptiert ausschließlich Fach aus den vorhandenen 24 Rendererprofilen, vorhandene Rezept-ID/-Version, echte öffentliche Grundlagen-IDs und/oder öffentliche Katalogthemen-ID, `de-DE` und ein explizites Niveauband. Es gibt **kein** Feld für freie Themen, Heft-/Unittexte, Antworten, Namen oder private Quellen. Das vorhandene kurze Rendererlabel „Lerntechniken“ wird serverseitig an die tatsächliche Fach-ID „Lern- und Arbeitstechniken“ gebunden; weitere Client-Aliase sind nicht erlaubt.

Der Server löst alle IDs selbst auf. Der Build-Key ist SHA-256 über den vollständigen kanonischen öffentlichen Stand einschließlich Regelinhalt/-version/-digest, Katalogthema/-snapshot/-titel, Rezeptversion/-digest sowie Builder-, Ausgabe- und Renderervertrag. Private Konten, Familien, Kinder, Sitzungen und Aufgaben beeinflussen diesen Schlüssel nicht. Katalogtitel sind Navigation, **kein Fachbeleg**. Tatsächliche kuratierte Regeln bleiben als Herkunft gespeichert; selbst erzeugte Beispielzahlen/-beziehungen sind ausdrücklich unbewertete KI-Beispiele und keine fingierten Quellenzitate.

`learning_asset_builds` beansprucht diesen Schlüssel atomar. `learning_asset_instances` bindet die persönliche Nutzung und Idempotenz getrennt an Autor und Kind. Ein erfolgreicher Build veröffentlicht genau eine unveränderliche `VisualReference`-Version mit `scope: exploration_only`, `subjects: []`, Template und öffentlicher Herkunft. `subjects: []` verhindert auch beim früheren Leser ohne Scopeprüfung, dass ein solches Beispiel als kuratiertes Aufgabenrezept ausgewählt wird. Der neue Leser schließt diese Zeilen bereits in SQL aus.

## Bewusster Ablauf

1. `GET /api/learning-assets/catalogue`: Profile, echte Fach-ID-Zuordnung, vorhandene Rezepte, öffentliche Grundlagen und höchstens 100 Katalogthemen pro Seite; Empfehlungen stammen aus der bestehenden Kandidatensuche über ausschließlich öffentlichen Text. `topic_subject` und `page` grenzen die Themen ein.
2. `GET /api/learning-assets/lookup`: öffentliche Auswahl prüfen, ohne Aufbau, Reservierung oder KI.
3. `POST /api/children/{child_id}/learning-assets/prepare`: geschlossener Selector, `X-Schulpilot-Account` und eigener `Idempotency-Key` (16–80 Zeichen). Die vorhandene `visual-v1`-Clientfähigkeit ist erforderlich. Antwort ist eine **private Instanz**, kein fremder Jobbezug. Ein fertiger Treffer benötigt keinen Anbieteraufruf und keine Reservierung; ein paralleler Treffer übernimmt auch keine fremde Abrechnung.
4. Bei einem Miss: Child→Build sperren, einen normalen begrenzten Job samt vorhandener Unit-Reservierung erzeugen. Nur wenn die **unveränderte bestehende Routenauswahl tatsächlich Sol ergibt**, darf der Aufbau starten; sonst sperrt die Funktion. Keine neue Route oder Budget-/Tokenanhebung.
5. Der Worker gibt alle DB-Verbindungen/Sperren vor dem Anbieteraufruf frei. Er sendet nur den erneut kanonisierten öffentlichen Selectorstand. Actor/Sitzung/Familienrecht/Tarif, öffentliche Versionen und Providerrevision werden vor und nach dem Aufruf geprüft. Nach einem wartenden Childlock müssen Erfolgs- **und** Fehlerpfad den frischen Jobstatus erneut lesen; eine terminale Maintenanceentscheidung wird nicht überschrieben.
6. `GET /api/learning-asset-instances/{id}` und `GET /api/children/{child_id}/learning-assets` lesen ausschließlich eigene Instanzen. Die zweite Route liefert `{items: [...]}` mit maximal 50 Einträgen. Beide prüfen Actor, Familienrecht und `visual-v1`; sie starten keine KI.

Der öffentliche Build-DTO enthält niemals Job-/Actor-/Sitzungs-/Familien-IDs, Fehlerdetails, Verbrauch oder Kosten. Vor `ready` bleiben `asset` und `reference` null. Die Instanz enthält zusätzlich Fach und öffentlichen Titel, sodass auch wartende/fehlgeschlagene Einträge verständlich sind. Persönliche Schlüssel werden bei Wiederholung unverändert aufgelöst; derselbe Schlüssel für eine andere Kind-/Specbindung führt zu 409. Neue Instanzen sind separat auf 60/h je Actor begrenzt, bezahlte Misses auf 10/h, zusätzlich zu allen bestehenden Limits. Demo-Familien dürfen Treffer nutzen, aber keine neue reguläre KI starten.

## Technische Freigabe und Grenzen

Die Antwort enthält einen kurzen Text, genau eine endliche bestehende `Presentation` und 1–3 offene Denkimpulse **ohne** Antworten, Bewertung oder Kompetenzangaben. Bestehende Profil-, Zitat-, Zahlen-, Pfeil-, Offenlegungs- und Geometrieprüfungen bleiben aktiv. Szenen sind zusätzlich auf 2–4 Objekte und 2–3 tatsächlich verschiedene Phasen begrenzt; reine unveränderte Wortkästen werden abgewiesen. Das Wire-Schema verwendet bestehende JSON-Schema-Referenzen und bleibt kompakt. Unvollständige Anbieterantworten, insbesondere `finish_reason: length`, werden verworfen. Es gibt keinen Fallback, automatischen Retry oder zusätzlichen Modellaufruf.

Diese Prüfung beweist Datenform und innere Darstellungskonsistenz, **keine unabhängige Fachwahrheit**. Ein KI-Beispiel darf nicht als Fachquelle einer privaten benotbaren Übung dienen. Eine solche spätere Nutzung bräuchte einen eigenen fachlichen Review und den bestehenden Quellen-/Antwortvertrag; dieser erste Pfad bietet sie ausdrücklich nicht an. Die 24 Profilprüfungen belegen die Vertragsbreite einer deklarativen Szene, nicht 24 Fachinhaltsabnahmen und keinen vollständigen Lehrplan.

Der veröffentlichte Datensatz behält Builder-/Renderer-/Ausgabeschemaversion, die gespeicherte Modellroutenauswahl und – nur wenn tatsächlich vorhanden – einen geschlossenen Transportbeleg mit Modell/Provider sowie Schema-/Prompthashes. Job-, Kosten- oder Kontodaten gelangen nicht in diesen öffentlichen Beleg. Fehlende Transportbelege werden nicht erfunden.

## Fehler, Aufbewahrung und Rückweg

Fehlgeschlagene Builds sind für diesen Schlüssel terminal: auch ein nachgewiesen nicht versandter Auftrag wird derzeit nicht automatisch oder durch bloß erneutes Öffnen neu gestartet. Ein fehlender oder bereits terminaler Creatorjob wird nur lesend als `failed` projiziert, statt Mitnutzer unbegrenzt warten zu lassen; unbekannte Abrechnung wird dabei nicht freigegeben. Eine spätere bewusste Reparatur ist **noch nicht Bestandteil** dieses Vertrags.

Instanzen werden nach 365 Tagen entfernt und bei Child-/Autorlöschung kaskadiert. Persönliche Exportdaten sind nach Autor getrennt; das Kinderexport enthält die kindeigenen Instanzen, Elternexports ergänzen nur die anfordernde Elternperson. Öffentliche Versionen bleiben ohne Privatbindung erhalten. Das Löschen eines Creatorjobs setzt nur den internen FK auf null. Keine Ansicht schreibt Lernzeit, Attempt, Mastery oder Unitantworten.

Unterbrochene Assetaufträge werden vor der allgemeinen Wartung in begrenzten
Einzeltransaktionen mit denselben Child→Build-Sperren beendet. Ein inzwischen
fertig veröffentlichter Auftrag wird nicht rückwirkend abgebrochen. Trifft eine
Modellantwort erst nach dem Abbruch ein, bleibt der Auftrag terminal. Ihre
validierte Generationkennung wird ausschließlich am privaten Verbrauchsbeleg
erhalten, damit der bestehende OpenRouter-Metadatenabgleich den tatsächlichen
Preis nachtragen kann. Dies startet weder eine zweite Erzeugung noch eine neue
Verbuchung der ursprünglichen Reservierung.

Migration `0040_shared_learning_assets` ist additiv nach 0039 und erzeugt genau zwei Tabellen. Ein Code-Rollback vor dieser Migration benötigt eine bewusste Behandlung noch wartender neuer Jobarten und der Migrations-Headkompatibilität; der alte Worker kennt `learning_asset` nicht. Die vorsorgliche leere Rezept-Fächerliste schützt zusätzlich den alten Kandidatenleser, ersetzt aber keine abgestimmte Betriebsrückkehr.

## Nachweise

Die gemeinsame Flutter-Ansicht liegt unter `/discover/:childId` und ist unter
„Lernen“ über „Themen mit Grafiken entdecken“ erreichbar. Sie zeigt zunächst
Fach und Thema; Darstellung und Stufe sind aufklappbar. Das gewählte Fach wird
bereits beim ersten Laden serverseitig gefiltert, weitere Themen werden bewusst
seitenweise nachgeladen. Ein unsicher beantworteter Start behält seinen
Idempotenzschlüssel. Gespeicherte Themen und Statusabfragen verwenden nur GETs;
überdeckte Ansichten und der Hintergrund senden keine neuen Erzeugungsaufträge.
Alte Konto-, Familien- und Kindkontexte übernehmen keine späten Antworten.

Die persönliche Themenliste bleibt serverseitig erhalten. Der innere
Animationszustand dieses neuen Erkundungswegs ist zunächst lokal; eine
geräteübergreifende CAS-Speicherung dieses Zustands gehört noch nicht zu diesem
Vertrag. Die vorhandene technische Speicherung normaler Lernrunden bleibt
davon getrennt erhalten.

Schulbuddy erhält über die eigene Instanzkennung die tatsächlich gespeicherte
Erkundung. Der Server prüft Autor, Kind, Familienrecht, aktuellen Build und
Referenzdigest; frei vom Client gelieferte Grafik- oder Erklärungstexte sind
nicht erlaubt. Die Grafik bleibt ausdrücklich ein ungeprüftes KI-Beispiel,
keine fachliche Quelle. Auch die vergrößerte Ansicht bietet einen festen
Tutorzugang außerhalb der verschiebbaren Grafikfläche. Der Tutor sieht das
gesamte gespeicherte Beispiel, zunächst keine zusätzliche lokale Animationsphase.
Dieser Chat erzeugt keinen Hilfebeleg für eine parallel offene Lernaufgabe.

Neue synthetische API-/Worker-/Adaptertests und echte Alembic-Upgradeprüfungen liegen in `backend/tests/test_learning_assets.py` und `test_learning_assets_migration.py`. Sie prüfen den vollständigen Aufbau-/Trefferpfad, Parallelität, Rechte-/Versionswechsel, terminale Sperrraces, Zurückweisung privater Eingaben und Outputkürzung sowie erhaltene künstliche Bestandsdaten. Konkrete finale Laufzahlen stehen im Übergabebericht. Keine echten Kinderinhalte, externen Anbieteraufrufe oder Live-Buildqualitätsbehauptungen sind Teil dieser Tests.
