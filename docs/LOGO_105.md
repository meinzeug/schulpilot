# Schulpilot105 · violetter Kopf und eigene Startupfigur

## Maßgebliche aktuelle Nutzeraufträge

1. Das Standardlogo für Header/Marke ist **nur der freundliche aufrechte frontale Roboterkopf ohne jeden Hut und ohne Körper**. Dominant violett/purpur, Cyanaugen und kleine Cyanakzente, dunkle blau/violette Tiefe. Die frühere Pflicht zum schwarzen Hut am Headerlogo ist ausdrücklich aufgehoben.
2. **Nur beim Web-/APK-Appstart** erscheint die gleiche Figurenidentität als vollständiger kompakter Roboter mit Körper und schwarzem Doktorhut. Ganze Figur frontal/aufrecht, eine kleine freundliche Begrüßung.
3. Die zusätzliche echte Bildfolge zeigt Hand zum Hut, physischen Hutgriff und Anheben, ein kurzes Zwinkern, Augenöffnung und Rückkehr des Huts. Keine bloße Nick-/Schwebeersatzanimation.

Stand 2026-10-24T09:22:12.213916+00:00. Mit dem eingebauten `image_gen`-Werkzeug und `transparent_background: true` erzeugt bzw. editiert. Kein CLI-/API-Fallback, keine fremden Figuren, Nutzerfotos oder Simpleclub-Assets. Verwendeter [Imagegen-Skill](/home/dennis/.codex/skills/.system/imagegen/SKILL.md).

Alle finalen Master wurden mit `view_image` angesehen, PNG/RGBA und Alpha ausschließlich lesend geprüft und bytegleich aus dem jeweiligen generierten Original kopiert. Keine nachträgliche kreative Bildbearbeitung, Hintergrundfüllung, Alphabereinigung oder Master-Skalierung. Technische kleinere Ausgaben sind ausdrücklich gesondert beauftragt und unten getrennt dokumentiert.

## Finales Standardlogo: Kopf ohne Hut

- Projektdatei: `app/assets/brand/schulpilot-ai-105.png`.
- Generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-de708cfc-595e-420b-9cdb-62ec89470116.png`.
- PNG/RGBA, 1254×1254 Pixel, 997676 Bytes.
- SHA-256: `7f0e01760fff433b43994369356d4bd4347433facea42a45d0c872b7ea0ba487`.
- Alpha0–255; 932410 von 1572516 Pixeln vollständig transparent.
- Sichtbare Kontur bei Alpha≥16: `(79, 270, 1174, 1013)`; höchster äußerster Rand-Alpha: 1. Vereinzelte fast transparente erzeugte Randpixel bleiben unverändert erhalten.

## Finaler statischer Startupmaster: ganze Figur mit schwarzem Hut

- Projektdatei: `app/assets/brand/schulpilot-startup-105.png`.
- Generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-57e39287-6439-4565-ae83-fa6f6da271b2.png`.
- PNG/RGBA, 1254×1254 Pixel, 1253187 Bytes.
- SHA-256: `e9b7b0bf399d89180baa4685fd842d7be5502ee09d1e164bbf834c5ff22eb32e`.
- Alpha0–255; 889394 von 1572516 Pixeln vollständig transparent.
- Sichtbare Kontur bei Alpha≥16: `(186, 70, 1075, 1201)`; höchster äußerster Rand-Alpha: 1. Vereinzelte fast transparente erzeugte Randpixel bleiben unverändert erhalten.

## Startup-Bildfolge: Hutheben und Zwinkern

- Projektdatei: `app/assets/brand/schulpilot-startup-frames-105.png`.
- Generiertes Original: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-cf9831b2-0c56-47e7-856a-a2f1efdac47e.png`.
- PNG/RGBA, 1774×887 Pixel, 1569594 Bytes.
- SHA-256: `b37b7e7515e0c4931165c5fd3ad9b6b5ca452c7bb540ae8238b0386656208428`.
- Alpha0–255; 881318 von 1573538 Pixeln vollständig transparent.
- Sichtbare Kontur bei Alpha≥16: `(70, 12, 1696, 865)`; höchster äußerster Rand-Alpha: 0. Vereinzelte fast transparente erzeugte Randpixel bleiben unverändert erhalten.

Die Bildfolge enthält4Spalten×2Zeilen, zeilenweise gelesen, ohne Beschriftung/Gitter. Das Original ist1774×887Pixel (exakt2:1); daher sind die acht gleich großen UV-Zellen jeweils443,5×443,5Pixel. Der Renderer kann `Rect.fromLTWH(column * width / 4, row * height / 2, width / 4, height / 2)` verwenden. Transparente Innenränder trennen jede vollständige Figur vom Zellrand; keine Zelle ist angeschnitten.

Visuell geprüfter Ablauf:1Hut auf/Körper ruht;2Hand zum Hut;3Hand greift;4Hut angehoben und beide Augen offen;5genau ein Auge zwinkert;6beide Augen offen;7Hut zurück auf den Kopf;8Hand gelöst/Ruhe. Der Hut bleibt während des Anhebens mit der Hand verbunden. Das generierte Original hat einen kleinen Restversatz der Fußbaseline von etwa3Pixeln zwischen den Zeilen; keine pixelgenaue Registratur oder bereits abgenommene Animationsruhe wird behauptet. Bei160dpentspricht das ungefähr1dp. Die eigentliche Sprite-Laufzeit, reduzierte Bewegung und Browser-/Geräteabnahme übernimmt der Integrator.

## Eigene Referenzen und verworfene Vorläufer

Der Kopfedit verwendete den vorherigen eigenen Kopf-/Hutentwurf als Ziel und den tatsächlich in `LearningCompanionIllustration` verwendeten eigenen `app/assets/illustrations/learning-companion.png` als Stilreferenz. Diese Illustration hat SHA-256`51c202855298bdf9a0656f4974408a24c81182c9d262ee4a0dbd3c65b951df06`. Ihr Buch/Körper/Flügel wurden nicht in den Kopf übernommen. Die Startupfigur verwendet ausschließlich das neue Kopf-Original als Identitätsreferenz; das Sprite wiederum ausschließlich das neue Startup-Original. Alle lokalen Referenzen wurden vor dem jeweiligen Edit mit `view_image` geöffnet.

Verworfener früherer Headerkopf MIT Hut: `/home/dennis/.codex/generated_images/01a165ad-c32d-7101-b681-81de003d3b05/exec-74ac697c-2ffe-4aa0-9f84-dd6921d160b7.png`, SHA-256`be31bfc0b80f933e2067eb8bb06f248a83b5996761b9ff10f4fdee5a75693f1f`. Er ist kein aktuelles Header- oder Startupasset. Noch frühere Ganzkörperentwürfe`exec-f815948d-6907-479c-af3f-34c969f449a7.png` und`exec-5361d206-e780-46d5-b61c-ae4f69b8e061.png` im selben generierten Originalverzeichnis sind ebenfalls verworfen. Originale bleiben außerhalb des Projekts erhalten; andere alte Projektassets wurden nicht gelöscht.

## Vollständiger finaler Kopf-Prompt

```text
Use case: precise-object-edit.
Asset type: final original Schulpilot transparent PNG HEAD logo for a 32px app icon.
Input image1 is the current OWN robot head with cap: edit target. Image2 is the current OWN Schulbuddy LearningCompanion illustration: reference ONLY for violet/purple material style, cyan eyes and friendly character language. Do not copy its wings, book, limbs or tilted pose.
DIRECT FINAL USER CORRECTION: REMOVE THE ENTIRE BLACK HAT AND TASSEL. Only the isolated robot HEAD. Absolutely NO hat of any sort, antenna, head accessory, cap remnants, body, neck, shoulders, arms, hands, legs or other objects.
Make the head perfectly UPRIGHT and STRAIGHT FRONTAL, bilaterally balanced: both eyes same size, ears same size, horizontal eye line and level top/bottom. No rightward lean, no rotation, no three-quarter perspective. The head should look even warmer and friendlier, with large soft luminous cyan eyes, kind gently raised brows and a small natural happy smile.
Final coherent family colors: dominant rich VIOLET and PURPLE outer shell, approximately #8B5CF6 and #A855F7 with softly lit lavender edges; CYAN only as smaller accent trims and eyes; dark deep blue/purple face screen and depth. Do not retain the existing dominant bright BLUE or cyan outer shell. Purple surfaces must be unmistakably dominant in the colored shell. Smooth restrained premium 3D shading consistent with the owned Schulbuddy reference, no noisy detail. Clear simple head silhouette at tiny icon size.
Composition: single centered head on a square canvas, about80percent width, equal comfortable transparent margins, entire ears and head visible.
Genuinely TRANSPARENT PNG background outside the head. No background tile, circle, border, floor, shadow plane, outer glow or backdrop. No text, letter, number, logo or watermark. Preserve actual alpha transparency.
```

## Vollständiger Startup-Prompt

```text
Use case: precise-object-edit / identity-preserve.
Asset type: a separate transparent PNG Schulpilot STARTUP mascot for Web and Android. The standard header logo stays head-only; this requested startup variant is a complete full-body robot with a BLACK academic cap.
Input: the supplied OWN NEW upright purple Schulpilot robot HEAD is the exact identity reference. Preserve that head's friendly large cyan eyes, level eyebrows, happy small cyan smile, purple/lavender shell, cyan thin trims, dark navy/purple screen and symmetrical round ear pieces. Do not redesign the face.
Extend this exact character into a compact friendly WHOLE ROBOT with a small rounded violet/purple torso, short rounded purple legs and feet, and two small rounded arms/hands. One hand may make a modest welcoming open-palmed wave while the whole figure, head and shoulders remain STRAIGHT UPRIGHT FRONTAL, balanced and not leaning. Both eyes/ears stay equal sized, eye line completely horizontal. Head large and dominant, body simple and secondary.
Place a prominent truly BLACK academic mortarboard graduation hat with black tassel securely on its head. Soft edge highlight within the black hat makes it readable on both dark navy and white surfaces. Rich VIOLET/PURPLE shell matching the reference, cyan only small trim accents, dark blue/purple shadows. Premium restrained polished 3D material; cute and approachable without excessive detail. No book, wings, antenna, extra props, text, letters, numbers, logo or watermark.
COMPOSITION: one centered complete front-facing robot, entire black cap and tassel, both hands and both feet fully visible, contained within the central76percent of square canvas height and at most76percent width. Comfortable transparent padding on EVERY side, including above hat and below feet. No cropping.
Background: actual TRANSPARENT PNG alpha outside the full silhouette and between limbs, no floor, no ground shadow, backdrop, rectangle, circular badge, enclosing border or outer glow.
```

## Vollständiger Sprite-Prompt

```text
Use case: precise-object-edit / identity-preserve.
Asset type: a genuine eight-frame transparent PNG SPRITESHEET for a short Schulpilot startup character animation.
Input: the supplied OWN purple full-body robot with black graduation mortarboard is the exact character identity and material reference. Preserve identical purple/lavender head and body shell, cyan eyes and thin accents, black cap and tassel, friendly face, proportions, feet, ears and hands. No new design.
TECHNICAL LAYOUT: one wide2:1 transparent image, ideally2048×1024 pixels, EXACTLY4equal columns by2equal rows =8square cells. All cells SAME SIZE, NO gaps, NO grid lines, NO borders, NO text or frame numbers. Read in row-major order left-to-right across top row, then left-to-right across bottom row.
Each cell contains ONE complete identical robot centered at exactly the same X coordinate and body scale. Feet share the SAME baseline at88percent of cell height in EVERY frame. Head stays perfectly frontal level and upright. No zoom, camera movement, jump, lean or character duplication inside a cell. Plenty of transparent space above the hat for the lifted pose. At rest the complete robot occupies around62percent of cell height; even when lifting the cap all pixels stay inside its own cell. Both feet, entire ears, hands, and cap always fit without crop or overlap into neighboring cells.
ACTION is a real physical tipping of the black hat, with the robot's anatomical RIGHT HAND (viewer-left hand) actually gripping and carrying its brim throughout the lift:
Frame1 (top-left): cap sits on head, both eyes open, friendly smile, right hand relaxed near torso.
Frame2: right arm bends upward, hand approaching cap brim; cap still on head.
Frame3: right hand visibly grips brim at viewer-left edge; cap still in contact with head.
Frame4: right hand lifts entire cap clearly ABOVE the head, leaving a visible transparent gap; eyes both open.
Frame5 (bottom-left): cap stays held above head with same hand, LEFT EYE (viewer-right eye) closes into one curved cyan wink, other eye remains open; happy small smile.
Frame6: wink reopens so both eyes open; hand still holds lifted cap.
Frame7: right hand lowers cap back onto head, hand remains in contact with brim.
Frame8 (bottom-right): cap rests on head, right hand released and relaxed again, both eyes open, same friendly resting pose as frame1.
Never let the cap float without a gripping hand, never generate extra hands, never replace hat-lifting with a wave. All frames maintain the same frontal character, shapes, colors and lighting; only specified arm/hat/eyelid motion changes.
Actual TRANSPARENT PNG alpha background everywhere outside each isolated figure and between limbs, no square backdrop, floor, ground shadow, outer glow, letters, labels, numerals, arrows, props or watermark. Render an animation production sheet, not a comic or storyboard.
```

## Getrennte technische Exporte

`scripts/export_brand.py` behält `MASTER=app/assets/brand/schulpilot-ai-105.png` für Mark/Favicon/installierbare Web-/Androidicons sowie den Play-Store-Export. Ausschließlich vier Ziele verwenden `STARTUP_MASTER=app/assets/brand/schulpilot-startup-105.png`:

- `app/web/brand.png` für den HTML-Start.
- `app/assets/brand/schulpilot-startup.png` für den Flutter-Start (512×512,transparent).
- `app/android/app/src/main/res/drawable-nodpi/schulpilot_logo.png`.
- `app/android/app/src/main/res/drawable-nodpi/schulpilot_splash_logo.png`.

Damit gibt es17technische Brandexporte. Vollständige Canvasproportionen und die bisherigen Safe-Mask-Faktoren bleiben erhalten. Kein Zuschnitt oder Farbersatz im Master; transparente Ausgaben bleiben RGBA. Nur die bereits vorhandenen installierbaren Icon-/Storeziele erhalten den bisherigen deterministischen Hintergrund`#101E24`. Web/Flutter-/nativeSplash-Vordergrundbilder bleiben transparent. Das Spritesheet ist das unveränderte generierte Original und kein zusammengebauter Pseudobewegungsexport.

Gezielte Prüfung:14Pythonfälle bestanden, Exit0, Log`/tmp/schulpilot105-final-brand-tests.log`; darunter Kopffigur-vs-Startupquellen, beide unveränderte Master,17Exporte, Mask-Safe-Foreground, acht transparente vollständige UV-Zellen und die separaten Headerexporte. Ruff für beide Exportskripte und ihre beiden Testdateien ist grün (Exit0). Keine Flutter-/Dart-SDK-, Git- oder Deploymentbefehle in diesem Assetauftrag. Reale Layout-/Animationsabnahme ist davon getrennt.
