# Eigene interaktive Lernlabore · 109

Status: gezielt in den gemeinsamen112-Stand integriert und mit künstlichen Daten im lokalen Browser bedient. Gezielte SDK-/Backendprüfungen sind in docs/SOURCES.md dokumentiert; Produktion und Releasebelege werden separat geprüft. Die Labore sind lokale Erkundungen und erzeugen keine Antworten, Versuche, Kompetenzbelege oder eigenen Aktivitätsereignisse.

## Endlicher Vertrag

Ein bereits freigegebener `Graphic`-Block kann `kind: "lab"` und `lab` tragen:

```json
{"version":1,"recipe_id":"physics.force_motion","recipe_version":1,"parameters":{"mass_kg":2,"acceleration_m_s2":2}}
```

```json
{"version":1,"recipe_id":"german.sentence_shift","recipe_version":1,"parameters":{"example_id":"mira_reads"}}
```

`lab_recipe.dart` akzeptiert ausschließlich diese IDs/Versionen, die exakten Schlüssel und endliche, begrenzte Parameter. Es verarbeitet keine Providerkoordinaten, Bild-URLs, Funktionen oder ausführbaren Code. `learning_lab.dart` verteilt auf die eigenen Renderer. Unbekannte oder gesperrte Daten ergeben einen sichtbaren Hinweis; die gespeicherte Erklärung bleibt der Rückweg.

Quellenvalidierung, Rezeptdigest und öffentliche Projektion liegen im Backend. Ein Curriculumverweis ist kein individueller Leistungsbeleg. Das Physikbeispiel benötigt passende belegte Parameter; das deutsche Beispiel wird ausdrücklich als eigenes kuratiertes Zusatzbeispiel gekennzeichnet. Kein Fotozitat wird daraus erfunden. Normale Aufgaben mit `given` werden nicht durch den Laborrenderer freigeschaltet. Ein `given`-Labor ist nur im bereits offenen strukturierten Erklärschritt vorgesehen; Hinweise und Lösungen behalten ihre bisherige öffentliche Stagefilterung.

## Physik: Kraft und Bewegung

Das Modell beschreibt die Translation des Schwerpunkts aus der Ruhe bei konstanter resultierender Kraft ohne Reibung:

- `F = m · a`, Masse in kg, Beschleunigung in m/s², Kraft in N.
- `s = ½ · a · t²`, Zeit in s, Weg in m.
- Masse 0,5–10 kg; Beschleunigung 0–4 m/s²; endliche Laufdauer 2 s; feste Bahnskala 0–8 m.
- Eine Massenänderung hält bei gleichem `a` den aktuellen Zeitpunkt und Weg fest und ändert nur die benötigte Kraft. Eine Beschleunigungsänderung beginnt ein neues Experiment bei `t = 0`.
- Start/Pause, Zurücksetzen auf gespeicherte Parameter, halbe Sekundenschritte und Zeitregler bleiben bewusste Eingaben. Kein automatischer Start oder Wiederholungszyklus.
- Reduzierte Bewegung und barrierefreie Navigation schalten kontinuierliche Wiedergabe aus; Schritte und Zeitregler bleiben. Tastatur: Pfeile am fokussierten Experiment, Leertaste für Start/Pause, R zum Zurücksetzen; Modifikatortasten werden durchgereicht.

Die Kugelposition und Kraftpfeillänge werden in Flutter berechnet. Die Kegel sind stationäre Zielmarken. Es gibt ausdrücklich keine Stoß-, Rotations-, Reibungs- oder Punkteberechnung. Angezeigte Dezimalwerte sind gerundet. Das Hintergrundbild trägt keine physikalischen Messwerte.

## Deutsch: Satzgliedgruppen verschieben

Das eigene Beispiel lautet „Mira liest am Morgen ein Buch“. Es besitzt vier feste Gruppen und vier einzeln freigegebene Anordnungen:

1. Mira · liest · am Morgen · ein Buch.
2. Am Morgen · liest · Mira · ein Buch.
3. Ein Buch · liest · Mira · am Morgen.
4. Mira · liest · ein Buch · am Morgen.

Eine Gruppe lässt sich als Ganzes auswählen oder ziehen. Der Knopf „An den Anfang“ und vier beschriftete Beispielauswahlen bieten eine Alternative zum Ziehen; Tastaturpfeile wechseln zwischen den freigegebenen Beispielen. Die Wortgrenzendemonstration `am | Morgen` ist ein ausdrücklich kuratiertes Gegenbeispiel zu dieser Wortgruppe. Es erfolgt keine Grammatikbewertung beliebiger Sätze. Das finite Verb steht in diesen Aussagesätzen an zweiter Satzgliedstelle; daraus wird keine Regel für alle Prädikate oder Satzarten abgeleitet.

## Scope und Darstellung

Beide Renderer binden lokale Zustände an AppState, Benutzerobjekt und Benutzer-ID, Familie, Sitzungstoken, Quelle und aktuelle Route. Hintergrund oder eine überdeckende Route pausieren Bewegung und machen gespeicherte Callbacks ungültig. Quellenwechsel setzt den lokalen Zustand zurück. Ohne angemeldeten Zustand bleiben nur statische, bereits freigegebene Beispiele sichtbar. Innerhalb eines gespeicherten strukturierten Erklärschritts mit stabiler Schritt-ID wird die endliche Ansicht über die vorhandene private `UnitVisualPosition` gespeichert, getrennt von Antworten, Lernzeit und Kompetenz. `position.lab_view` enthält entweder Masse, Beschleunigung und Zeitpunkt in 50-ms-Schritten oder eine bekannte Satzanordnung mit gewählter Gruppe und Wortgrenzendemonstration. Nur gespeicherte Ausgangswerte beziehungsweise feste 0,5-kg-/0,25-m/s²-Schritte sind zulässig. Beim Lesen wird nichts geschrieben. Explizite Änderungen speichern per bestehendem CAS; die Animation aktualisiert während des Laufens nur den RAM-/Tutorkontext. Pause und Ende sowie die autorisierte Rückkehr nach einer Hintergrundpause speichern den letzten begrenzten Zustand. Eine laufende Simulation wird niemals wieder automatisch gestartet.

`LearningGraphicScope` transportiert diesen Zustand zur bereits geöffneten Erklärung und ihrem Schulbuddy-Kontext. Dort bleibt `graphic_phase` für Labore `initial`; zusätzlich wird `lab_view` als begrenzter kanonischer JSON-String übertragen. Der Server prüft Rezept, Version, Quellen-/Offenlegungsstatus und Werte erneut und berechnet die beschriebenen Experimentfakten selbst. Diese werden ausdrücklich als unbewertete Erkundung behandelt. Ein alleinstehendes Hinweis-Labor ohne stabile Erklärungsschritt-ID bleibt lokal; dafür wird keine künstliche Position erfunden. Es werden weder beliebiger Clienttext noch neue Formeln, Koordinaten oder Leistungsbelege angenommen. Grafikzoom hält denselben Zustand und übernimmt Änderungen erst über den weiterhin gültigen Erklärungskontext; die technische Position wird nach dem autorisierten Rückweg gespeichert.

Die Fähigkeit `labs-v1` ist im Backend ein ausdrücklicher Clientvertrag. Alte Clients dürfen ein gespeichertes Labor nicht still als vollständig unterstützte Erklärung übernehmen. Die gemeinsame künstliche Fixture `testdata/learning_labs_v1.json` enthält ausschließlich echte öffentliche Backendprojektionen, einschließlich der leeren Projektion vor der Hinweisfreigabe, und dokumentiert `provider_calls: 0`.

Die eigenen Testdateien `force_lab_109_test.dart`, `sentence_shift_lab_109_test.dart` und `lab_view_109_test.dart` prüfen Physik-/Satzgrenzen, tatsächliche Bedienung, Zustandsübertragung, Wiederherstellung, Session-/Quellenwechsel und öffentliche Fixtureprojektionen. Sie bestanden als Teil des tatsächlichen220-Fälle-Gates einschließlich320/390px und großer Schrift. Im lokalen Browser wurden Masse und Zeitschritt sowie die Satzumstellung tatsächlich verändert. Ein neuer Tab übernahm die gespeicherte Satzanordnung; Smartphone und800px-Tablet wurden abfotografiert. Dies sind künstliche Modelle, keine echte KI- oder OCR-Abnahme. Werte und Bedienelemente haben Vorrang. Der optionale Robotercoach erscheint nur bei ausreichend Platz. Grafikzoom nutzt für Labore die vorhandene responsive Breite statt einer 600-px-Zwangsfläche.

## Bildherkunft

Beide Bilder wurden mit dem integrierten `image_gen` neu erzeugt. Es wurden keine Simpleclub-Bilddateien, Screenshots oder Maskottchen als Eingabebilder verwendet. Die sichtbare Grundidee eines interaktiven Kraftversuchs und einer Satzgliedprobe ist eine Funktionsreferenz; die Illustrationen, Texte, Daten und Fluttergeometrie sind eigenständig.

| Laufzeitdatei | Maße/Format | SHA-256 |
| --- | --- | --- |
| `app/assets/illustrations/force-lab-track-109.png` | 1672 × 941 RGB | `70931441115ba477476f0a7cdc4c2325f2a9a8f26cbbb01e994c8166fa4581f0` |
| `app/assets/illustrations/force-lab-coach-109.png` | 1312 × 1199 RGBA, Alpha 0–255 | `345958f58e2fe142b023ab297e12f5d2e18c932de80ae30a68d931949eda32ba` |

Die PNGs wurden unverändert aus den Generierungsergebnissen kopiert. Das bereits registrierte Verzeichnis `assets/illustrations/` benötigt keine neue Abhängigkeit. Die Ausgabegröße des Coaches wird zur Laufzeit begrenzt und dekorativ von Semantik und Treffertests ausgenommen.

### Prompt: Laborhintergrund

```text
Use case: scientific-educational.
Asset type: original illustrated background for a mobile-wide interactive physics laboratory in the German learning app Schulpilot. This is a background plate, not a finished diagram.
Primary request: a beautiful, polished, friendly 2.5D orthographic bowling / force laboratory with one clear straight rolling track running left to right across the middle. The learner will later move a ball and change mass and force using real Flutter controls; leave the entire rolling surface unobstructed for those coded overlays.
Scene: compact tabletop laboratory with a long smooth satin track, subtle lane edge rails, softly bevelled acrylic and metal, a simple quiet navy environment. The lane should read immediately even when the whole image is displayed at about 320 pixels wide. Slight elevated three-quarter orthographic viewpoint; keep the travel direction almost horizontal and the play area broad, straight and usable, from roughly the left fifth to the right fifth.
Style: premium playful educational 3D illustration, carefully modelled rounded surfaces, natural dimensional soft shadows, restrained glow, visually precise and calm, no clutter.
Palette: charcoal navy #101E24 background, rich violet and purple construction, cyan and turquoise edge highlights; high contrast between the empty rolling track and its surroundings. Warm, welcoming light.
Composition: wide landscape, approximately 16:9. The complete lab fits with generous safe margins. The clean track occupies the central horizontal band and leaves some negative space above and below for future Flutter overlays.
Constraints: entirely original design. No logos, no mascots, no copied reference assets. NO TEXT, no numbers, no letters, no formula, no UI, no buttons, no controls, no chart or tick marks. NO BALL, no pins, no moving object, no baked-in ball position, no arrows, no trajectory, no motion trail, no perspective distortion or curved path. Dynamic ball, pins, force vectors, labels and values will all be drawn separately in code.
```

### Prompt: optionaler Laborcoach

```text
Use case: scientific-educational.
Asset type: optional supporting character for a mobile interactive physics laboratory, isolated transparent PNG. This is an original small teaching coach illustration, not a new logo.
Primary request: a friendly compact little AI laboratory robot that can sit at the left side of a force-and-bowling experiment and invite the learner to explore. Full body, three-quarter view facing toward the right, with a welcoming open hand gently indicating the experiment to its right. Keep the gesture restrained and the silhouette clear at small size.
Style: premium polished playful 2.5D educational illustration, rounded carefully modelled shapes, soft studio lighting and subtle highlights, visually consistent with a calm navy laboratory with violet construction and cyan edge lighting.
Design: rich violet/purple rounded shell, charcoal navy joints and small body, expressive cyan-lit eyes in a dark visor, two small arms and two sturdy feet. Upright and attentive, approachable rather than mechanical. No resemblance to any existing commercial mascot. Small simple silhouette and a generous transparent safety margin around every part.
Palette: dominant violet and purple, charcoal navy #101E24, controlled bright cyan highlights. Genuine transparent background, no environment, no ground rectangle.
Constraints: NO HAT, no wings, no book, no headset, no text, no letters, no numbers, no formula, no logo, no badge, no embedded speech bubble, no UI, no bowling ball or pins, no educational claim. No long antenna and no cropped limbs. Pose points right without touching any unseen object. All explanations and interaction will be implemented separately in code.
```

## Weitere Fächer

Der Rezeptdispatcher ist absichtlich endlich. Künftige Labore benötigen eine neue bekannte Rezept-ID/Version, einen fachlich geprüften Parametervertrag, echte Quellen-/Zusatzwissensbindung, Backend- und Frontendtests und denselben Stagefilter. Vorhandene Funktionsgraphen, Messpunkte, Molekül-/Zellmodelle, Szenen und Textproben sollen dabei wiederverwendet werden. Diese zwei Labore bedeuten weder vollständige Lehrplanabdeckung noch eine interaktive Simulation für jedes Fach.
