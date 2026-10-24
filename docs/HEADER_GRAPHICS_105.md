# Headergrafiken105 · violette Schulbuddy-Familie

## Maßgeblicher finaler Nutzerauftrag

Glocke und Avatarhintergrund folgen den aktuellen Schulbuddyfarben mit **dominanten violett/purpurnen Flächen**, kleinen Cyanakzenten und dunkelblau/violetter Tiefe. Die zuvor erzeugte leuchtblaue Dominanz wurde auf unmittelbare Nutzerkorrektur verworfen. Die Glocke bleibt eine frei stehende plastische Glocke ohne Kachel/Rand; die runde Avatarplakette hat eine breite blanke dunkelviolette Mitte für einen echten weißen Dart-/Flutter-Buchstaben oder das bewusst hochgeladene private Profilfoto. Kein Buchstabe und kein Foto wurde generiert.

Stand 2026-10-24T09:22:12.213916+00:00. Mit dem eingebauten `image_gen`-Werkzeug und `transparent_background: true` erzeugt bzw. editiert. Kein CLI-/API-Fallback, keine fremden Figuren, Nutzerfotos oder Simpleclub-Assets. Verwendeter [Imagegen-Skill](/home/dennis/.codex/skills/.system/imagegen/SKILL.md).

Alle finalen Master wurden mit `view_image` angesehen, PNG/RGBA und Alpha ausschließlich lesend geprüft und bytegleich aus dem jeweiligen generierten Original kopiert. Keine nachträgliche kreative Bildbearbeitung, Hintergrundfüllung, Alphabereinigung oder Master-Skalierung. Technische kleinere Ausgaben sind ausdrücklich gesondert beauftragt und unten getrennt dokumentiert.

## Finaler Glockenmaster

- Projektdatei: `app/assets/brand/schulpilot-bell-105.png`.
- Generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-75b66437-6c0b-4734-a783-c5b9ebf0f602.png`.
- PNG/RGBA, 1254×1254 Pixel, 1034026 Bytes.
- SHA-256: `bedccd35c5e38edc3ecd0277972db53205846317639df6c9e54748a753c9acd3`.
- Alpha0–255; 893152 von 1572516 Pixeln vollständig transparent.
- Sichtbare Kontur bei Alpha≥16: `(127, 99, 1127, 1122)`; höchster äußerster Rand-Alpha: 1. Vereinzelte fast transparente erzeugte Randpixel bleiben unverändert erhalten.

## Finaler Avatarhintergrund

- Projektdatei: `app/assets/brand/schulpilot-avatar-105.png`.
- Generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-582d2229-be35-43d3-9970-7a2c5fc28fd5.png`.
- PNG/RGBA, 1254×1254 Pixel, 1331264 Bytes.
- SHA-256: `4219c47aefaac32c732c1c5f0806096ff2f2ec126633f10a3c1f311d898cdc07`.
- Alpha0–255; 662428 von 1572516 Pixeln vollständig transparent.
- Sichtbare Kontur bei Alpha≥16: `(85, 92, 1169, 1161)`; höchster äußerster Rand-Alpha: 1. Vereinzelte fast transparente erzeugte Randpixel bleiben unverändert erhalten.

## Eigene Referenzen und verworfene Vorläufer

Die reine Farb-Neugestaltung verwendete jeweils das zuvor eigene erzeugte Asset als Editziel und die tatsächlich verwendete eigene `app/assets/illustrations/learning-companion.png` als Stilreferenz(SHA-256`51c202855298bdf9a0656f4974408a24c81182c9d262ee4a0dbd3c65b951df06`). Beide lokalen Referenzen wurden vor den Edits angesehen. Form, leerer Innenbereich und freigestellte Komposition bleiben; der neue generierte Alphakanal wird unverändert übernommen, keine bitidentische Alphaform des Vorläufers behauptet.

Nicht mehr finale blaue Glocke: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-22b04af3-1780-4a3b-a29f-4bf03d605d82.png`(SHA-256`1963fb719df7ee34e544d7a37cad48135db997ae30874c79e765db5cecc13cc3`). Nicht mehr finale blaue Avatarplakette: gleicher Originalordner,`exec-d58c86d7-d091-4833-ad3c-fd52fc7323d1.png`(SHA-256`2aee4ed4d254d67312b1c5185bc25624b56a957c0d0d66fe7fb30884d434908e`). Diese Originale bleiben erhalten, sind aber nicht die ausgelieferten Master.

## Vollständiger finaler Glocken-Prompt

```text
Use case: precise-object-edit.
Asset type: final original Schulpilot notification bell header graphic.
Input image1 is the current OWN bell: edit target. Input image2 is the current OWN Schulbuddy LearningCompanion: reference ONLY for purple/cyan material language.
Change ONLY the bell COLOR PALETTE, preserving its exact centered bell silhouette, front-facing slight-depth form, loop, round clapper, polished volume, full canvas, transparent padding and alpha cutout composition.
DIRECT USER CORRECTION: the bell must be predominantly VIOLET/PURPLE, with rich #8B5CF6 and #A855F7 shell, lavender highlights and dark purple/deep blue shaded depth. Cyan remains only as thin limited accent edges. Replace the current dominant bright electric-blue body. It must visibly belong to a coherent PURPLE Schulbuddy icon family, clear and refined at24–28px.
One isolated bell, no enclosing tile, no circle badge, no border, no floor, no ground shadow, no rectangular backdrop. No new objects, face, robot, hat, text, letters or watermark.
Keep genuinely TRANSPARENT PNG background everywhere outside the bell and within its top-loop gap.
```

## Vollständiger finaler Avatar-Prompt

```text
Use case: precise-object-edit.
Asset type: final original Schulpilot account initial avatar BACKGROUND, with no generated initial.
Input image1 is the current OWN circular avatar medallion: edit target. Input image2 is the current OWN Schulbuddy LearningCompanion: reference ONLY for purple/cyan material language.
Change ONLY the COLOR PALETTE, preserving the circular straight-on medallion silhouette, softly beveled rim, completely BLANK broad center, entire canvas and transparent padding.
DIRECT USER CORRECTION: make the medallion dominantly VIOLET/PURPLE: rim in rich #8B5CF6 and #A855F7 with subtle lavender light, dark purple shadows and a very small cyan accent on its inner edge. No dominant bright electric blue. The broad flat center must become quiet very DARK VIOLET/plum, roughly #21123F, with no shine crossing its center. Keep at least68percent circle-diameter as empty dark center, ready for a genuine WHITE letter drawn later by Flutter.
Genuinely TRANSPARENT PNG outside the circle. The circle interior stays dark and opaque. No square tile, surrounding frame, floor, ground shadow, extra object, robot or hat.
Absolutely NO letter, text, monogram, number, character, symbol, face, person, photo or watermark. Do not invent the user's initial.
```

## Technische256px-Headerexporte

`scripts/export_header_graphics.py` erzeugt drei proportionale256px-PNGs (Glocke, Avatar und fliegender Schulbuddy) aus dem vollständigen jeweiligen Mastercanvas: ausschließlich Pillow-LANCZOS-Resampling und PNG-Speicherung mit `optimize=True`. Kein Zuschnitt, keine Hintergrundfüllung, Umfärbung oder Alphabereinigung. Der Alphakanal wird wie die übrigen Kanäle resampelt; alle Masterbytes bleiben unverändert. Das Headerwerkzeug greift nicht in die17separaten Brand-/Startup-Plattformexporte ein.

| Runtimeasset unter app/ | Format | Größe | Bytes | SHA-256 |
| --- | --- | --- | --- | --- |
| `assets/brand/schulpilot-bell-header.png` | PNG/RGBA,Alpha0–255 | 256×256 | 58758 | `63f115bdd7653afd5978d05a368201ee7cea8b42f49a6c856b3cf728c8908113` |
| `assets/brand/schulpilot-avatar-header.png` | PNG/RGBA,Alpha0–255 | 256×256 | 66865 | `fea86bb7aa4a7985a0dc14063f644f7990b440330c4ce8f59d16dedd43255b31` |

Aufruf im Projektstamm:`.venv/bin/python scripts/export_header_graphics.py`. Fünf isolierte Fälle sichern Masterbytes, volle Proportionen, RGBA-/LANCZOS-Pixel, identische Wiederholung, alle unveränderten vorherigen Exporte bei ungültigem zweiten Master und tatsächlich gespeicherte kleine Headerdateien. Im gemeinsamen finalen Lauf mit den Brand-/Spritetests:14bestanden, Exit0, Log`/tmp/schulpilot105-final-flying-brand-tests.log`. Ruff für die beiden Skripte und beiden eigenen Testdateien ist grün(Exit0).

## Finaler Schulbuddy: fliegende Buchfigur bleibt erhalten

Direkte jüngste Nutzerkorrektur: die bestehende geflügelte Buch-/Roboterfigur bleibt der Schulbuddy. Die ursprüngliche Silhouette, Flugpose und Blickrichtung mit sichtbaren Buchseiten, Lesezeichenantenne, beiden Origamiflügeln, zwei Armen/Händen, kleinen Finnen und cyanfarbenem Bauch-Antrieb bleiben erkennbar erhalten. Ausschließlich die dunkelblaue äußere Hülle wurde stilistisch etwas violetter und mit passenden Materiallichtern versehen. Kein Doktorhut, kein Headset und kein neuer reiner Kopf. Das ursprüngliche `app/assets/illustrations/learning-companion.png` wurde nicht verändert.

- Finaler Master: `app/assets/brand/schulbuddy-ai-105.png`, PNG/RGBA,1254×1254Pixel,1058023Bytes.
- Unverändertes generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-b6fb1136-6057-4b6b-9641-140a480ec6e2.png`.
- Master-SHA-256: `ed644b4a8d1a410a04d0a17912bdb7c95ff47729e877931547bf61d032deae02`.
- Alpha0–255,1060322vollständig transparente Pixel; sichtbare Kontur bei Alpha≥16:`(13,170,1242,1039)`.
- Laufzeitexport: `assets/brand/schulbuddy-mark.png` unter `app/`,256×256PNG/RGBA,Alpha0–255,62801Bytes.
- Laufzeit-SHA-256: `10f396724ff219d51bb86e27ec439ef47bdfb7990749033c13f19b8c225852b6`.

Die primäre Editreferenz war ausschließlich die eigene bestehende fliegende Figur `app/assets/illustrations/learning-companion.png` (SHA-256`51c202855298bdf9a0656f4974408a24c81182c9d262ee4a0dbd3c65b951df06`); das neue eigene `app/assets/brand/schulpilot-ai-105.png` (SHA-256`7f0e01760fff433b43994369356d4bd4347433facea42a45d0c872b7ea0ba487`) diente ausschließlich als Material-/Palettenreferenz. Beide wurden zuerst mit `view_image` geöffnet. Built-in Imagegen mit `transparent_background:true`; das Ergebnis ebenfalls angesehen und vor dem endgültigen Kopieren von Root ausdrücklich visuell bestätigt. Keine zusätzliche kreative Nachbearbeitung. Der256px-Export erfolgt reproduzierbar über denselben LANCZOS-Headerexporter mit nun drei Einträgen. Die Glocken-/Avatar-Master und ihre256px-Runtimeexporte wurden vor/nach diesem Schritt per SHA-256 als bytegleich bestätigt.

**Verworfen und nicht final integriert:** der zuvor kurz erzeugte Kopf-mit-Headset-Entwurf `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-3af48b8a-1da9-43f8-9870-739526e6f477.png`. Seine beiden neu angelegten Projektkopien wurden auf ausdrückliche Korrektur vor einer Runtimeintegration nach `/tmp/schulpilot105-discarded-headset/` verschoben. Sie gehören nicht zum finalen Projektbestand. Dieser verworfene Entwurf wurde nicht als fliegender Schulbuddy ausgegeben.

### Vollständiger finaler Schulbuddy-Prompt

```text
Use case: precise-object-edit / identity-preserve.
Asset type: transparent Schulpilot SCHULBUDDY FLYING BOOK-ROBOT icon, preserving an existing original character.
Image1 is the PRIMARY EDIT TARGET: the exact existing OWN flying BOOK-ROBOT with visible cream book pages on top, purple bookmark antenna, dark face screen with cyan eyes, two origami-like purple wings, two articulated arms/hands, small fins and a cyan belly thruster. It has a deliberate diagonal flying pose and specific gaze. PRESERVE THAT COMPLETE ORIGINAL FIGURE, exact full silhouette, all wing/finger/fin/book-page shapes, proportions, pose, tilt, gaze, facial expression, geometry, framing, canvas and every object. It must remain the flying book robot; do NOT turn it into a plain head or a humanoid standing mascot.
Image2 is ONLY a palette/material-light reference: the OWN new upright violet logo head. DO NOT COPY its head shape, straight pose, plain ears or any geometry.
Make ONLY a restrained MATERIAL/COLOR adjustment to image1: shift the dark-blue outer book-cover/armor shell somewhat toward rich deep VIOLET/PURPLE, with the softly polished violet/lavender highlights and small cyan accents of image2. Keep the original dark navy face screen, large bright cyan eyes, cream paper pages, existing lavender origami wings and cyan thruster recognizably the same. Preserve internal detail and all colors that identify the original parts. Premium soft3D lighting in the same family, not neon overpainting.
Strict invariants: NO new hat or graduation cap, NO headset or microphone, NO body/arm/wing removal, NO antenna removal, NO speech bubbles, NO new particles, extra accessories, letters, text, numbers, watermark, badge, border, floor or background. The primary character's design and original pose must remain visibly unchanged.
Keep genuine TRANSPARENT PNG alpha outside the entire full flying silhouette, between arms/wings/fins and around the bookmark. No opaque tile or backdrop. All existing extremities stay fully inside the canvas. This is a small styling/color edit of the ORIGINAL FLYING CHARACTER, not a redesign.
```

Finale technische Abnahme:14gezielte synthetische Pythonfälle bestanden (Exit0,3.58s), Log`/tmp/schulpilot105-final-flying-brand-tests.log`; die fünf Headerfälle prüfen jetzt alle drei Master/Laufzeitexporte. Ruff für beide Exportskripte und ihre beiden Testdateien grün (Exit0). Kein Flutter-/Dart-SDK, Git, Versions- oder Deploymentbefehl in diesem Schritt. Die endgültige36px-Header-/Chatdarstellung und Bedienprüfung übernimmt Root separat.

## Integrationsgrenze

Die Glocke ist für ungefähr24–28dp innerhalb eines mindestens48dp großen beschrifteten Bedienelements vorgesehen. Die Avatarplakette liefert ausschließlich den Hintergrund: tatsächlicher Buchstabe/Foto, Semantik, Kontobindung, Upload und Bedienung verbleiben in Flutter. Sichtbarkeit, Schriftkontrast und Headerlayout werden durch den Integrator separat geprüft. Die Assetprüfung behauptet keine bereits abgeschlossene Browser-/Geräteabnahme und verändert weder private Daten noch KI-/Lernverträge.
