import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'camera_recovery.dart';
import 'material_actions.dart';
import 'learning_tips.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'ideas100_source_tools.dart';
import 'material_words.dart';
import 'subject_picker.dart';
import 'learning_content.dart';
import 'notebook_photo.dart';

Future<void> importMaterial(
  BuildContext context,
  AppState state,
  String childId,
) async {
  final owner = state.user;
  if (state.isDemo) {
    if (!await confirmDialog(
      context,
      'Künstliches Testblatt mit echter KI erkennen?',
      'Der Server erstellt ein festes Bild ohne persönliche Daten. Dieses Bild wird vom eingerichteten KI-Dienst gelesen. Keine eigenen Fotos oder Texte werden verwendet.',
    )) {
      return;
    }
    if (!context.mounted ||
        !identical(owner, state.user) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final material = await state.api.post(
      '/children/$childId/materials/synthetic-fixture',
    );
    if (context.mounted && identical(owner, state.user)) {
      state.refreshState();
      openRoute(context, '/material/${material['id']}');
    }
    return;
  }
  final status = await state.api.get('/status');
  if (!context.mounted || !identical(owner, state.user)) return;
  if (status['real_data_enabled'] != true) {
    throw ApiError(
      'Der Import echter Materialien ist bis zur dokumentierten Datenschutzfreigabe gesperrt.',
    );
  }
  if (status['ai_available'] != true) {
    throw ApiError(
      status['ai_block_reason'] ?? 'Zurzeit ist kein geeigneter KI-Dienst verfügbar. Bitte später erneut versuchen.',
    );
  }
  if (!context.mounted) return;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.photo_camera_outlined),
            title: Text('Hefteintrag fotografieren'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined),
            title: Text('Bild auswählen'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  if (!identical(owner, state.user)) return;
  await rememberCameraSource(state, childId);
  Uint8List? cropped;
  try {
    if (!context.mounted || !identical(owner, state.user)) return;
    cropped = await pickMaterialPhoto(context, source, state: state);
  } finally {
    if (identical(owner, state.user)) await clearCameraSource(state);
  }
  if (cropped == null) return;
  if (!identical(owner, state.user)) return;
  final material = await state.api.upload(childId, cropped);
  if (context.mounted && identical(owner, state.user)) {
    state.refreshState();
    openRoute(context, '/material/${material['id']}');
  }
}

Future<Uint8List?> pickMaterialPhoto(
  BuildContext context,
  ImageSource source, {
  AppState? state,
}) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 3200,
    maxHeight: 3200,
    imageQuality: 90,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;
  return cropMaterialPhoto(context, bytes, state: state);
}

class CropFrame {
  final double left, top, right, bottom;
  final int turns;
  const CropFrame({
    this.left = 0,
    this.top = 0,
    this.right = 1,
    this.bottom = 1,
    this.turns = 0,
  });
}

Future<Uint8List?> cropMaterialPhoto(
  BuildContext context,
  Uint8List bytes, {
  AppState? state,
  CropFrame? initialFrame,
  ValueChanged<CropFrame>? onFrameChanged,
  int? batchIndex,
  int? batchTotal,
}) async {
  if (bytes.length > 10 * 1024 * 1024) {
    throw ApiError('Das Bild darf höchstens 10 MB groß sein.');
  }
  final owner = state?.user, family = state?.familyId, token = state?.api.token;
  bool current() =>
      context.mounted &&
      (state == null ||
          (owner != null &&
              identical(state.user, owner) &&
              state.familyId == family &&
              state.api.token == token));
  if (!current()) return null;
  final route = DialogRoute<Uint8List>(
    context: context,
    builder: (_) => CropDialog(
      bytes,
      initialFrame: initialFrame,
      onFrameChanged: onFrameChanged,
      batchIndex: batchIndex,
      batchTotal: batchTotal,
      isCurrent: current,
    ),
  );
  void changed() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state?.addListener(changed);
  try {
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  } finally {
    state?.removeListener(changed);
  }
}

class CropDialog extends StatefulWidget {
  final Uint8List bytes;
  final CropFrame? initialFrame;
  final ValueChanged<CropFrame>? onFrameChanged;
  final int? batchIndex, batchTotal;
  final bool Function()? isCurrent;
  const CropDialog(
    this.bytes, {
    super.key,
    this.initialFrame,
    this.onFrameChanged,
    this.batchIndex,
    this.batchTotal,
    this.isCurrent,
  });
  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  double left = 0, top = 0, right = 1, bottom = 1;
  int quarterTurns = 0;
  int? dragCorner;
  bool encoding = false;
  String photoView = 'edit';
  final undoFrames = <CropFrame>[], redoFrames = <CropFrame>[];
  late final Uint8List originalPreview = preview;
  late final double originalAspect = image == null
      ? 1
      : image!.width / image!.height;
  CropFrame get frame => CropFrame(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    turns: quarterTurns,
  );
  void rememberFrame() {
    if (encoding || widget.isCurrent?.call() == false) return;
    undoFrames.add(frame);
    if (undoFrames.length > 20) undoFrames.removeAt(0);
    redoFrames.clear();
  }

  void publishFrame() => widget.onFrameChanged?.call(frame);
  void restoreFrame(CropFrame value) {
    image = orientedImage();
    if (image != null && value.turns != 0) {
      image = img.copyRotate(image!, angle: value.turns * 90);
    }
    quarterTurns = value.turns;
    left = value.left;
    top = value.top;
    right = value.right;
    bottom = value.bottom;
    if (image != null) {
      preview = Uint8List.fromList(img.encodeJpg(image!, quality: 85));
    }
    photoView = 'edit';
    publishFrame();
  }

  Uint8List clippedPreview() {
    if (image == null) return preview;
    final cut = img.copyCrop(
      image!,
      x: (left * image!.width).floor(),
      y: (top * image!.height).floor(),
      width: math.max(1, ((right - left) * image!.width).floor()),
      height: math.max(1, ((bottom - top) * image!.height).floor()),
    );
    return Uint8List.fromList(img.encodeJpg(cut, quality: 85));
  }

  @override
  void initState() {
    super.initState();
    originalPreview;
    originalAspect;
    if (widget.initialFrame != null) restoreFrame(widget.initialFrame!);
  }

  late img.Image? image = orientedImage();
  img.Image? orientedImage() {
    final decoded = img.decodeImage(widget.bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    return oriented.width > 1100 || oriented.height > 1100
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? 1100 : null,
            height: oriented.height > oriented.width ? 1100 : null,
          )
        : oriented;
  }

  late Uint8List preview = image == null
      ? widget.bytes
      : Uint8List.fromList(img.encodeJpg(image!, quality: 85));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.batchIndex == null
          ? 'Passt das Foto?'
          : 'Foto ${widget.batchIndex} von ${widget.batchTotal} prüfen',
    ),
    content: SizedBox(
      width: 590,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Namen bitte abschneiden. Der Text soll gut lesbar sein.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in const [
                  ('edit', 'Zuschnitt bearbeiten'),
                  ('original', 'Original ansehen'),
                  ('crop', 'Ergebnis ansehen'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: photoView == id,
                    onSelected: encoding
                        ? null
                        : (_) => setState(() => photoView = id),
                  ),
                IconButton(
                  tooltip: 'Zuschnitt rückgängig',
                  onPressed: undoFrames.isEmpty || encoding
                      ? null
                      : () => setState(() {
                          redoFrames.add(frame);
                          restoreFrame(undoFrames.removeLast());
                        }),
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Zuschnitt wiederholen',
                  onPressed: redoFrames.isEmpty || encoding
                      ? null
                      : () => setState(() {
                          undoFrames.add(frame);
                          restoreFrame(redoFrames.removeLast());
                        }),
                  icon: const Icon(Icons.redo),
                ),
              ],
            ),
            if (widget.batchIndex != null)
              const Text(
                'Jedes Foto hat einen eigenen Zuschnitt. Bereits übernommene Fotos bleiben erhalten.',
              ),
            TextButton.icon(
              onPressed: image == null || encoding
                  ? null
                  : () => setState(() {
                      rememberFrame();
                      image = img.copyRotate(image!, angle: 90);
                      quarterTurns = (quarterTurns + 1) % 4;
                      preview = Uint8List.fromList(
                        img.encodeJpg(image!, quality: 85),
                      );
                      final oldLeft = left,
                          oldTop = top,
                          oldRight = right,
                          oldBottom = bottom;
                      left = 1 - oldBottom;
                      top = oldLeft;
                      right = 1 - oldTop;
                      bottom = oldRight;
                      publishFrame();
                    }),
              icon: Icon(Icons.rotate_right),
              label: Text('Um 90° drehen'),
            ),
            TextButton.icon(
              onPressed: image == null || encoding
                  ? null
                  : () => setState(() {
                      rememberFrame();
                      left = top = 0;
                      right = bottom = 1;
                      publishFrame();
                    }),
              icon: Icon(Icons.crop_free_rounded),
              label: Text('Ganzes Foto verwenden'),
            ),
            if (image == null)
              Notice(
                'Dieses Bild kann nicht gelesen werden. Wähle bitte ein anderes Foto als JPEG oder PNG.',
                warning: true,
              ),
            if (image != null)
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .40).clamp(
                  240,
                  420,
                ),
                child: LayoutBuilder(
                  builder: (context, size) => Center(
                    child: AspectRatio(
                      aspectRatio: photoView == 'original'
                          ? originalAspect
                          : photoView == 'crop' && image != null
                          ? image!.width *
                                (right - left) /
                                (image!.height * (bottom - top))
                          : image == null
                          ? 1
                          : image!.width / image!.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            photoView == 'original'
                                ? originalPreview
                                : photoView == 'crop'
                                ? clippedPreview()
                                : preview,
                            fit: BoxFit.fill,
                          ),
                          if (photoView == 'edit')
                            LayoutBuilder(
                              builder: (context, bounds) => Semantics(
                                label: 'Zuschneiderahmen. Ziehe eine Ecke. Darunter kannst du die Ränder mit Reglern verändern.',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: image == null || encoding
                                      ? null
                                      : (event) {
                                          final corners = [
                                            Offset(left, top),
                                            Offset(right, top),
                                            Offset(left, bottom),
                                            Offset(right, bottom),
                                          ];
                                          final point = Offset(
                                            event.localPosition.dx /
                                                bounds.maxWidth,
                                            event.localPosition.dy /
                                                bounds.maxHeight,
                                          );
                                          var nearest = 0;
                                          for (
                                            var i = 1;
                                            i < corners.length;
                                            i++
                                          ) {
                                            if ((corners[i] - point).distance <
                                                (corners[nearest] - point)
                                                    .distance) {
                                              nearest = i;
                                            }
                                          }
                                          final offset =
                                              corners[nearest] - point;
                                          final pixelDistance = Offset(
                                            offset.dx * bounds.maxWidth,
                                            offset.dy * bounds.maxHeight,
                                          ).distance;
                                          if (pixelDistance <= 32) {
                                            rememberFrame();
                                          }
                                          dragCorner = pixelDistance <= 32
                                              ? nearest
                                              : null;
                                        },
                                  onPanUpdate: image == null || encoding
                                      ? null
                                      : (event) => setState(() {
                                          final x =
                                              (event.localPosition.dx /
                                                      bounds.maxWidth)
                                                  .clamp(0.0, 1.0);
                                          final y =
                                              (event.localPosition.dy /
                                                      bounds.maxHeight)
                                                  .clamp(0.0, 1.0);
                                          if (dragCorner == 0 ||
                                              dragCorner == 2) {
                                            left = x.clamp(0.0, right - .1);
                                          }
                                          if (dragCorner == 1 ||
                                              dragCorner == 3) {
                                            right = x.clamp(left + .1, 1.0);
                                          }
                                          if (dragCorner == 0 ||
                                              dragCorner == 1) {
                                            top = y.clamp(0.0, bottom - .1);
                                          }
                                          if (dragCorner == 2 ||
                                              dragCorner == 3) {
                                            bottom = y.clamp(top + .1, 1.0);
                                          }
                                        }),
                                  onPanEnd: (_) {
                                    dragCorner = null;
                                    publishFrame();
                                  },
                                  onPanCancel: () {
                                    dragCorner = null;
                                    publishFrame();
                                  },
                                  child: CustomPaint(
                                    painter: _CropPainter(
                                      Rect.fromLTRB(left, top, right, bottom),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(height: 16),
            ExpansionTile(
              title: Text('Bild zuschneiden'),
              children: [
                for (final item in [
                  (
                    'Linker Rand',
                    left,
                    0.0,
                    right - .1,
                    (double v) => setState(() => left = v),
                  ),
                  (
                    'Oberer Rand',
                    top,
                    0.0,
                    bottom - .1,
                    (double v) => setState(() => top = v),
                  ),
                  (
                    'Rechter Rand',
                    right,
                    left + .1,
                    1.0,
                    (double v) => setState(() => right = v),
                  ),
                  (
                    'Unterer Rand',
                    bottom,
                    top + .1,
                    1.0,
                    (double v) => setState(() => bottom = v),
                  ),
                ])
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(item.$1, style: TextStyle(fontSize: 12)),
                      ),
                      Expanded(
                        child: Slider(
                          label:
                              '${item.$1}: ${(item.$2 * 100).round()} Prozent',
                          semanticFormatterCallback: (value) =>
                              '${item.$1}: ${(value * 100).round()} Prozent',
                          value: item.$2,
                          min: item.$3,
                          max: item.$4,
                          onChangeStart: encoding
                              ? null
                              : (_) => rememberFrame(),
                          onChangeEnd: encoding ? null : (_) => publishFrame(),
                          onChanged: encoding ? null : item.$5,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: encoding
            ? null
            : () {
                if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                  publishFrame();
                  Navigator.pop(context);
                }
              },
        child: Text(image == null ? 'Anderes Foto wählen' : 'Abbrechen'),
      ),
      ActionButton(
        label: 'Zuschnitt übernehmen',
        enabled: image != null && !encoding,
        onPressed: () async {
          final cropRoute = ModalRoute.of(context);
          if (!mounted ||
              encoding ||
              cropRoute?.isCurrent != true ||
              widget.isCurrent?.call() == false) {
            return;
          }
          publishFrame();
          if (image == null) {
            throw ApiError(
              'Dieses Bildformat konnte nicht gelesen werden. Bitte JPEG oder PNG auswählen.',
            );
          }
          final values = <String, dynamic>{
            'bytes': widget.bytes,
            'turns': quarterTurns,
            'left': left,
            'top': top,
            'right': right,
            'bottom': bottom,
          };
          setState(() => encoding = true);
          try {
            // Paint feedback before the bounded local encoding operation.
            await Future<void>.delayed(Duration(milliseconds: 32));
            final encoded = await compute(encodeMaterialCrop, values);
            if (context.mounted && cropRoute?.isCurrent == true) {
              Navigator.pop(context, encoded);
            }
          } finally {
            if (mounted) setState(() => encoding = false);
          }
        },
      ),
    ],
  );
}

Uint8List encodeMaterialCrop(Map<String, dynamic> value) {
  var source = img.bakeOrientation(img.decodeImage(value['bytes'])!);
  if (value['turns'] != 0) {
    source = img.copyRotate(source, angle: (value['turns'] as int) * 90);
  }
  final cropped = img.copyCrop(
    source,
    x: ((value['left'] as double) * source.width).round(),
    y: ((value['top'] as double) * source.height).round(),
    width: math.max(
      1,
      (((value['right'] as double) - (value['left'] as double)) * source.width)
          .floor(),
    ),
    height: math.max(
      1,
      (((value['bottom'] as double) - (value['top'] as double)) * source.height)
          .floor(),
    ),
  );
  final clean = img.Image.from(cropped)..exif.clear();
  final resized = clean.width > 1600 || clean.height > 1600
      ? img.copyResize(
          clean,
          width: clean.width >= clean.height ? 1600 : null,
          height: clean.height > clean.width ? 1600 : null,
        )
      : clean;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

class MaterialTaskDialog extends StatefulWidget {
  final List<Json> items;
  final bool hasDuplicate;
  const MaterialTaskDialog({
    super.key,
    required this.items,
    this.hasDuplicate = false,
  });

  @override
  State<MaterialTaskDialog> createState() => _MaterialTaskDialogState();
}

class _MaterialTaskDialogState extends State<MaterialTaskDialog> {
  late final choices = <String, String>{
    for (final row in widget.items)
      row['key']: row['classification'] ?? 'unclear',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Was ist wirklich aufgegeben?'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nur bestätigte Hausaufgaben kommen verbindlich in deinen Plan. Beispiele bleiben im Heft.',
            ),
            if (widget.hasDuplicate) ...[
              SizedBox(height: 12),
              Notice(
                'Ein ähnliches Blatt ist schon gespeichert. Du kannst zurückgehen und das doppelte Foto entfernen. Gleiche Aufträge desselben Tages zählen nur einmal.',
                warning: true,
              ),
            ],
            for (final item in widget.items) ...[
              SizedBox(height: 18),
              Text(item['text'], style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: choices[item['key']],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'So wurde es in der Schule gesagt',
                ),
                items: [
                  DropdownMenuItem(
                    value: 'homework',
                    child: Text('Als Hausaufgabe aufgegeben'),
                  ),
                  DropdownMenuItem(
                    value: 'example',
                    child: Text('Beispiel oder Übung im Unterricht'),
                  ),
                  DropdownMenuItem(
                    value: 'unclear',
                    child: Text('Das weiß ich noch nicht'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => choices[item['key']] = value!),
              ),
              if (choices[item['key']] == 'unclear')
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Bleibt im Heft und wird vorerst nicht verbindlich eingeplant.',
                    style: TextStyle(color: context.palette.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context);
          }
        },
        child: Text('Zurück'),
      ),
      FilledButton(
        onPressed: () {
          if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
          Navigator.pop(context, <Json>[
            for (final entry in choices.entries)
              {'key': entry.key, 'classification': entry.value},
          ]);
        },
        child: Text(
          widget.hasDuplicate && widget.items.isEmpty
              ? 'Seite bewusst behalten'
              : 'Auswahl übernehmen',
        ),
      ),
    ],
  );
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  _CropPainter(this.crop);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .6));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(point, 9, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        9,
        Paint()
          ..color = teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop;
}

class MaterialScreen extends StatefulWidget {
  final AppState state;
  final String materialId;
  const MaterialScreen(this.state, {super.key, required this.materialId});
  @override
  State<MaterialScreen> createState() => _MaterialScreenState();
}

class _MaterialScreenState extends State<MaterialScreen> {
  int version = 0;
  late final account = widget.state.user;
  late final family = widget.state.familyId;
  late final session = widget.state.api.token;
  bool get current =>
      mounted &&
      account != null &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      session == widget.state.api.token;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (!current && mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: widget.state.isChild ? 'Dein Lernstoff' : 'Heftseite',
    subtitle: widget.state.isChild ? 'Schau kurz, ob der Text stimmt.' : null,
    child: !current
        ? SizedBox.shrink()
        : LoadView<Json>(
            key: ValueKey((version, widget.materialId, ObjectKey(account))),
            load: () => widget.state.api.get('/materials/${widget.materialId}'),
            builder: (data, refresh) => !current
                ? SizedBox.shrink()
                : MaterialReview(
                    widget.state,
                    data,
                    simpleChild: widget.state.isChild,
                    onRefresh: () {
                      if (current) setState(() => version++);
                    },
                  ),
          ),
  );
}

class MaterialReview extends StatefulWidget {
  final AppState state;
  final Json data;
  final VoidCallback onRefresh;
  final VoidCallback? onDeleted;
  final bool showUnitAction;
  final bool simpleChild;
  const MaterialReview(
    this.state,
    this.data, {
    super.key,
    required this.onRefresh,
    this.onDeleted,
    this.showUnitAction = true,
    this.simpleChild = false,
  });
  @override
  State<MaterialReview> createState() => _MaterialReviewState();
}

class _MaterialReviewState extends State<MaterialReview>
    with WidgetsBindingObserver {
  late final subject = TextEditingController(text: widget.data['subject']);
  late final topic = TextEditingController(text: widget.data['topic']);
  late final content = TextEditingController(text: widget.data['content']);
  late final homework = TextEditingController(
    text: (widget.data['homework'] as List).join('\n'),
  );
  bool editing = false, confirmedHere = false;
  bool changing = false, sourceConflict = false, restoredCorrection = false;
  int? correctionRevision;
  String get correctionKey =>
      'source_correction:${widget.data['child_id']}:${widget.data['id']}';
  DialogRoute<List<Json>>? taskPreviewRoute;
  final sourceToolRoutes = <DialogRoute<dynamic>, String>{};
  bool foreground = true;
  GoRouter? toolRouter;
  String? toolLocation;
  void toolRouteChanged() {
    if (sourceToolRoutes.isNotEmpty &&
        toolRouter?.routeInformationProvider.value.uri.toString() !=
            toolLocation) {
      closeSourceTools();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, toolRouter)) {
      toolRouter?.routeInformationProvider.removeListener(toolRouteChanged);
      if (toolRouter != null) closeSourceTools();
      toolRouter = router;
      toolRouter?.routeInformationProvider.addListener(toolRouteChanged);
    }
  }

  String get sourceToolSnapshot => jsonEncode([
    widget.data['id'],
    widget.data['revision'],
    widget.data['content'],
    widget.data['source_blocks'],
    widget.data['uncertainties'],
    content.text,
  ]);
  void closeSourceTools() {
    final routes = sourceToolRoutes.keys.toList();
    sourceToolRoutes.clear();
    Future<void>.microtask(() {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  Future<T?> showSourceTool<T>(
    Widget Function(BuildContext, DialogRoute<T>) builder,
  ) async {
    if (!current || !foreground || ModalRoute.of(context)?.isCurrent == false) {
      return null;
    }
    final snapshot = sourceToolSnapshot;
    toolLocation = toolRouter?.routeInformationProvider.value.uri.toString();
    late DialogRoute<T> route;
    route = DialogRoute<T>(
      context: context,
      builder: (ctx) {
        if (!current || !foreground || snapshot != sourceToolSnapshot) {
          return const SizedBox.shrink();
        }
        return builder(ctx, route);
      },
    );
    sourceToolRoutes[route] = snapshot;
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      await route.completed;
      sourceToolRoutes.remove(route);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!foreground) {
      closeSourceTools();
      final route = taskPreviewRoute;
      taskPreviewRoute = null;
      Future<void>.microtask(() {
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
    }
  }

  Future<void> discardCorrection() async {
    if (!current || changing || !dirty) return;
    final data = widget.data,
        draftSnapshot = jsonEncode([
          subject.text,
          topic.text,
          content.text,
          homework.text,
        ]);
    final accepted = await showSourceTool<bool>(
      (ctx, route) => AlertDialog(
        scrollable: true,
        title: Text('Eigene Korrektur zurücknehmen?'),
        content: Text(
          'Nur deine noch nicht bestätigten Änderungen auf diesem Gerät werden durch den gespeicherten Seitentext ersetzt. Die gespeicherte Heftseite bleibt erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && current && route.isCurrent) {
                Navigator.pop(ctx, false);
              }
            },
            child: Text('Weiter verbessern'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted && current && route.isCurrent) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('Gespeicherten Text wiederherstellen'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !sourceCurrent(data) ||
        draftSnapshot !=
            jsonEncode([
              subject.text,
              topic.text,
              content.text,
              homework.text,
            ])) {
      return;
    }
    setState(() {
      resetSource();
      restoredCorrection = false;
    });
    widget.state.collectionViews.remove(correctionKey);
  }

  Future<void> copySourceText() async {
    if (!current || content.text.trim().isEmpty) return;
    final data = widget.data, text = content.text;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted && sourceCurrent(data)) {
        toast(
          context,
          'Der aktuelle Seitentext liegt jetzt in der Zwischenablage.',
        );
      }
    } catch (_) {
      if (mounted && sourceCurrent(data)) {
        toast(
          context,
          'Kopieren klappt hier gerade nicht. Dein Text bleibt erhalten.',
        );
      }
    }
  }

  List<dynamic>? readingBlocks(Json data, String text) {
    if (text != data['content'] || data['source_blocks'] is! List) return null;
    // Freeze this exact source snapshot. LearningContent still verifies that
    // every supplied block reconstructs the complete visible text exactly.
    return List<dynamic>.from(jsonDecode(jsonEncode(data['source_blocks'])));
  }

  Widget sourceReadingTools() {
    final data = widget.data;
    final hasText = content.text.trim().isNotEmpty;
    final hasNotebook =
        data['subject_id'] is String &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(data['subject_id']);
    final actions = <String, String>{
      if (data['has_image'] == true && hasText)
        'photo': 'Foto und Text vergleichen',
      if (dirty) 'correction': 'Korrektur mit gespeichertem Text vergleichen',
      if (hasText) 'copy': 'Aktuellen Seitentext kopieren',
      if (hasNotebook) 'notebook': 'Zugehörigen Fachhefter öffnen',
    };
    return Row(
      children: [
        if (hasText)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.find_in_page_outlined),
                label: const Text('Im Seitentext nachsehen'),
                onPressed: () {
                  if (!sourceCurrent(data)) return;
                  final text = content.text, snapshot = sourceToolSnapshot;
                  showSourceTool<void>(
                    (ctx, route) => _SourceTextReader(
                      text: text,
                      blocks: readingBlocks(data, text),
                      uncertainties: data['uncertainties'] as List? ?? [],
                      isCurrent: () =>
                          sourceCurrent(data) && snapshot == sourceToolSnapshot,
                      onClose: () {
                        if (ctx.mounted &&
                            sourceCurrent(data) &&
                            snapshot == sourceToolSnapshot &&
                            route.isCurrent) {
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        if (actions.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Weitere Seitentextwerkzeuge',
            icon: const Icon(Icons.more_horiz),
            itemBuilder: (_) => [
              for (final entry in actions.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onSelected: (action) {
              if (!sourceCurrent(data)) return;
              if (action == 'copy') {
                copySourceText();
                return;
              }
              if (action == 'notebook') {
                openRoute(
                  context,
                  '/library/${data['child_id']}/subject/${data['subject_id']}',
                );
                return;
              }
              final snapshot = sourceToolSnapshot;
              void close(BuildContext ctx, DialogRoute<void> route) {
                if (ctx.mounted &&
                    sourceCurrent(data) &&
                    snapshot == sourceToolSnapshot &&
                    route.isCurrent) {
                  Navigator.pop(ctx);
                }
              }

              if (action == 'photo') {
                final text = content.text;
                showSourceTool<void>(
                  (ctx, route) => _MaterialCompareDialog(
                    title: 'Foto und Seitentext',
                    onClose: () => close(ctx, route),
                    firstLabel: 'Dein Heftfoto',
                    secondLabel: 'Aktueller Seitentext',
                    firstChoice: 'Foto',
                    secondChoice: 'Text',
                    first: LayoutBuilder(
                      builder: (context, constraints) => SizedBox(
                        height: (MediaQuery.sizeOf(context).height * .45).clamp(
                          120.0,
                          400.0,
                        ),
                        child: NotebookPhoto(
                          widget.state,
                          materialId: data['id'],
                          zoomable: true,
                        ),
                      ),
                    ),
                    second: LearningContent(
                      text,
                      blocks: readingBlocks(data, text),
                    ),
                  ),
                );
              } else if (action == 'correction') {
                final before = '${data['content'] ?? ''}', after = content.text;
                showSourceTool<void>(
                  (ctx, route) => _MaterialCompareDialog(
                    title: 'Korrektur vergleichen',
                    onClose: () => close(ctx, route),
                    firstLabel: 'Gespeicherter Seitentext',
                    secondLabel: 'Dein Korrekturentwurf',
                    firstChoice: 'Original',
                    secondChoice: 'Entwurf',
                    first: LearningContent(
                      before,
                      blocks: readingBlocks(data, before),
                    ),
                    second: LearningContent(
                      after,
                      blocks: readingBlocks(data, after),
                    ),
                    notice: 'Der Vergleich speichert keine Korrektur.',
                  ),
                );
              }
            },
          ),
      ],
    );
  }

  bool get dirty =>
      subject.text != widget.data['subject'] ||
      topic.text != widget.data['topic'] ||
      content.text != widget.data['content'] ||
      homework.text != (widget.data['homework'] as List).join('\n');
  void retainCorrection() {
    if (!current) return;
    widget.state.collectionViews.remove(correctionKey);
    if (!dirty || confirmedHere || widget.data['confirmed'] == true) return;
    if (content.text.runes.length > 24000 ||
        topic.text.runes.length > 160 ||
        homework.text.length > 12000) {
      return;
    }
    widget.state.collectionViews[correctionKey] = {
      'account': account,
      'revision': correctionRevision,
      'subject': subject.text,
      'topic': topic.text,
      'content': content.text,
      'homework': homework.text,
    };
    final keys = widget.state.collectionViews.keys
        .where((key) => key.startsWith('source_correction:'))
        .toList();
    while (keys.length > 10) {
      widget.state.collectionViews.remove(keys.removeAt(0));
    }
  }

  void validateCorrection() {
    if (topic.text.runes.length > 160) {
      throw ApiError(
        'Das Thema darf höchstens 160 Zeichen haben. Dein Text bleibt hier erhalten.',
      );
    }
    if (content.text.runes.length > 24000) {
      throw ApiError(
        'Der Seitentext darf höchstens 24.000 Zeichen haben. Dein Text bleibt hier erhalten.',
      );
    }
    final lines = homework.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.length > 20 || lines.any((s) => s.runes.length > 500)) {
      throw ApiError(
        'Bis zu 20 Aufgaben mit je höchstens 500 Zeichen sind möglich. Dein Text bleibt hier erhalten.',
      );
    }
  }

  late final account = widget.state.user;
  late final family = widget.state.familyId;
  late final sessionToken = widget.state.api.token;
  bool get current =>
      mounted &&
      account != null &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      sessionToken == widget.state.api.token;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    correctionRevision = widget.data['revision'] as int?;
    widget.state.addListener(accountChanged);
    final saved = widget.state.collectionViews[correctionKey];
    if (widget.data['confirmed'] != true &&
        saved != null &&
        identical(saved['account'], account)) {
      subject.text = saved['subject'];
      topic.text = saved['topic'];
      content.text = saved['content'];
      homework.text = saved['homework'];
      restoredCorrection = true;
      correctionRevision = saved['revision'] as int?;
      sourceConflict = correctionRevision != widget.data['revision'];
      editing = true;
    }
  }

  void accountChanged() {
    if (!current && mounted) {
      closeSourceTools();
      widget.state.collectionViews.remove(correctionKey);
      final old = taskPreviewRoute;
      if (old != null) {
        Future<void>.microtask(() {
          if (old.isActive) old.navigator?.removeRoute(old);
        });
      }
      setState(() {
        for (final c in [subject, topic, content, homework]) {
          c.clear();
        }
        selectedWords = [];
      });
    }
  }

  void resetSource() {
    correctionRevision = widget.data['revision'] as int?;
    subject.text = widget.data['subject'] ?? '';
    topic.text = widget.data['topic'] ?? '';
    content.text = widget.data['content'] ?? '';
    homework.text = (widget.data['homework'] as List).join('\n');
    selectedWords = [];
    editedWordPreview = null;
    previewSubject = previewTopic = previewContent = null;
    wordLocale = null;
    reverseWords = false;
    confirmedHere = false;
    sourceConflict = false;
  }

  @override
  void didUpdateWidget(covariant MaterialReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sourceToolRoutes.values.any(
      (snapshot) => snapshot != sourceToolSnapshot,
    )) {
      closeSourceTools();
    }
    if (oldWidget.data['id'] != widget.data['id'] ||
        oldWidget.data['revision'] != widget.data['revision']) {
      closeSourceTools();
      final route = taskPreviewRoute;
      taskPreviewRoute = null;
      if (route != null) {
        Future<void>.microtask(() {
          if (route.isActive) route.navigator?.removeRoute(route);
        });
      }
    }
    if (oldWidget.data['id'] != widget.data['id']) {
      resetSource();
      editing = false;
    } else if (oldWidget.data['revision'] != widget.data['revision']) {
      final changed =
          subject.text != (oldWidget.data['subject'] ?? '') ||
          topic.text != (oldWidget.data['topic'] ?? '') ||
          content.text != (oldWidget.data['content'] ?? '') ||
          homework.text != (oldWidget.data['homework'] as List).join('\n');
      if (changed) {
        sourceConflict = true;
      } else {
        resetSource();
      }
    }
  }

  String? wordLocale;
  bool reverseWords = false;
  Json? editedWordPreview;
  List<Json> selectedWords = [];
  String? previewSubject, previewTopic, previewContent;

  bool sourceCurrent(Json source) =>
      current &&
      foreground &&
      ModalRoute.of(context)?.isActive != false &&
      source['id'] == widget.data['id'] &&
      source['revision'] == widget.data['revision'];

  bool get editedPreviewCurrent =>
      previewSubject == subject.text &&
      previewTopic == topic.text &&
      previewContent == content.text;

  Json? get wordPreview {
    if (editedPreviewCurrent) return editedWordPreview;
    final value = widget.data['vocabulary_preview'];
    if (value is! Map ||
        content.text != widget.data['content'] ||
        topic.text != widget.data['topic'] ||
        subject.text != widget.data['subject']) {
      return null;
    }
    return Json.from(value);
  }

  String get selectedWordLocale {
    final language = wordPreview?['language'];
    if (wordLocale != null &&
        (language == null || wordLocale!.startsWith('$language-'))) {
      return wordLocale!;
    }
    return switch (language) {
      'fr' => 'fr-FR',
      'es' => 'es-ES',
      'la' => 'la',
      _ => 'en-GB',
    };
  }

  Json get wordConfirmation => {
    'target_locale': selectedWordLocale,
    'language_confirmed': true,
    'reverse': reverseWords,
    'revision': widget.data['revision'],
    'selections': selectedWords,
  };

  Future<void> savePageOnly() async {
    setState(() => selectedWords = []);
    await confirmPage();
  }

  Widget saveWithoutWords() => TextButton.icon(
    onPressed: () => change(savePageOnly),
    icon: Icon(Icons.description_outlined),
    label: Text('Nur Heftseite speichern'),
  );

  Widget wordPreviewPanel({bool saved = false}) => MaterialWordsPanel(
    key: ValueKey(jsonEncode([wordPreview, selectedWordLocale, reverseWords])),
    preview: wordPreview!,
    enabled: !changing,
    locale: selectedWordLocale,
    reverse: reverseWords,
    actionLabel: saved ? 'Wörter übernehmen' : 'Stimmt, weiter',
    onLocale: (value) => setState(() {
      wordLocale = value;
      selectedWords = [];
    }),
    onReverse: () => setState(() {
      reverseWords = !reverseWords;
      selectedWords = [];
    }),
    onSelections: (value) => setState(() => selectedWords = value),
  );

  Widget savedWordPanel() => Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: LoadView<Json>(
      revision: (
        widget.data['id'],
        widget.data['revision'],
        ObjectKey(account),
      ),
      load: () =>
          widget.state.api.get('/materials/${widget.data['id']}/vocabulary'),
      builder: (status, refresh) {
        final stored = status['confirmed_words'] as int? ?? 0;
        final pending = status['review_words'] as int? ?? 0;
        final canWrite = widget.state.isChild || widget.state.canManage;
        if (stored + pending == 0 && !canWrite) return SizedBox.shrink();
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stored + pending > 0) ...[
                Text(
                  '${counted(stored, 'Wort', 'Wörter')} gespeichert${pending > 0 ? ' · $pending noch prüfen' : ''}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12),
                if ((status['unpaired_lines'] as num? ?? 0) > 0)
                  Text(
                    '${status['unpaired_lines']} weitere Zeilen wurden nicht als Wortpaare übernommen.',
                    style: TextStyle(color: context.palette.warningInk),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openRoute(
                    context,
                    '/vocabulary/${widget.data['child_id']}?material=${widget.data['id']}',
                  ),
                  icon: Icon(Icons.translate_rounded),
                  label: Text(pending > 0 ? 'Wörter prüfen' : 'Wörter öffnen'),
                ),
              ] else if (canWrite) ...[
                wordPreviewPanel(saved: true),
                SizedBox(height: 12),
                ActionButton(
                  label: 'Wörter übernehmen',
                  icon: Icons.playlist_add_check_rounded,
                  enabled: selectedWords.isNotEmpty,
                  onPressed: () async {
                    if (!current) return;
                    final owner = widget.state.user;
                    await widget.state.api.post(
                      '/materials/${widget.data['id']}/vocabulary',
                      wordConfirmation,
                    );
                    if (mounted && identical(owner, widget.state.user)) {
                      refresh();
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Future<void> change(Future<void> Function() action) async {
    if (changing || !current) return;
    if (sourceConflict) {
      toast(
        context,
        'Die gespeicherte Seite wurde geändert. Lade zuerst die neue Fassung.',
      );
      return;
    }
    setState(() => changing = true);
    try {
      await action();
    } finally {
      if (current) {
        setState(() => changing = false);
      } else {
        changing = false;
      }
    }
  }

  Future<void> deletePage() async {
    final d = widget.data;
    final owner = widget.state.user;
    final deleted = await deleteNotebookPages(
      context,
      widget.state,
      childId: d['child_id'],
      ids: [d['id']],
      // Preserve the wizard's next-page/archived-last-page decision before
      // global listeners reload the newly reduced page list.
      onDeleted: widget.onDeleted,
    );
    if (!deleted ||
        !mounted ||
        !identical(owner, widget.state.user) ||
        d['id'] != widget.data['id'] ||
        d['revision'] != widget.data['revision']) {
      return;
    }
    if (widget.onDeleted == null) {
      context.go('/library/${d['child_id']}');
    }
  }

  Widget pageActions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (widget.data['processing_job'] is Map &&
          [
            'queued',
            'running',
            'failed',
          ].contains(widget.data['processing_job']['status']))
        TextButton.icon(
          onPressed: () => openRoute(
            context,
            '/material/${widget.data['id']}/processing/${widget.data['processing_job']['id']}',
          ),
          icon: Icon(Icons.hourglass_top_rounded),
          label: Text('Einlesen ansehen'),
        ),
      if (materialCanReprocess(widget.state, widget.data))
        ActionButton(
          label: 'Mit KI neu lesen',
          secondary: true,
          icon: Icons.document_scanner_outlined,
          onPressed: () => change(() async {
            await reprocessNotebookPage(
              context,
              widget.state,
              widget.data,
              onRefresh: widget.state.refreshState,
            );
          }),
        ),
      if (materialCanDelete(widget.state, widget.data)) deleteButton(),
    ],
  );

  bool get extractionRunning =>
      widget.data['processing_job'] is Map &&
      ['queued', 'running'].contains(widget.data['processing_job']['status']);

  Widget deleteButton() => ActionButton(
    label: 'Seite löschen',
    secondary: true,
    icon: Icons.delete_outline_rounded,
    onPressed: () => change(deletePage),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    toolRouter?.routeInformationProvider.removeListener(toolRouteChanged);
    closeSourceTools();
    retainCorrection();
    final old = taskPreviewRoute;
    if (old != null) {
      Future<void>.microtask(() {
        if (old.isActive) old.navigator?.removeRoute(old);
      });
    }
    widget.state.removeListener(accountChanged);
    for (final c in [subject, topic, content, homework]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox.shrink();
    if (sourceConflict) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Notice(
              'Diese Heftseite wurde inzwischen geändert. Deine Korrektur steht noch hier; lade die neue Fassung, bevor du sie bestätigst.',
              warning: true,
            ),
            Text(
              'Deine noch nicht gespeicherte Korrektur',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('${subject.text} · ${topic.text}'),
            LearningContent(content.text),
            if (homework.text.isNotEmpty) Text(homework.text),
            OutlinedButton(
              onPressed: () {
                if (current) setState(resetSource);
              },
              child: Text('Gespeicherte Seite laden'),
            ),
          ],
        ),
      );
    }
    final d = widget.data;
    if (widget.simpleChild && widget.state.isChild) return childReview(context);
    final synthetic = d['synthetic'] == true;
    final liveFixture = d['fixture_id'] != null;
    final readonly = widget.state.isParent && !widget.state.canManage;
    final canConfirm =
        !readonly &&
        d['status'] != 'unreadable' &&
        !(widget.state.isChild && d['confirmed'] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(synthetic ? 'Beispielseite' : 'Deine Heftseite'),
            Tag(
              d['confirmed']
                  ? 'Bestätigter Lernstoff'
                  : 'Bestätigung erforderlich',
            ),
          ],
        ),
        SizedBox(height: 12),
        pageActions(),
        if (dirty && !confirmedHere)
          Semantics(
            liveRegion: true,
            child: Notice(
              restoredCorrection
                  ? 'Deine Korrektur ist hier wieder aufgenommen. Mit „Stimmt, weiter“ übernimmst du sie.'
                  : 'Deine Korrektur ist noch nicht übernommen. Mit „Stimmt, weiter“ speicherst du den geprüften Text.',
            ),
          ),
        SizedBox(height: 12),
        if (liveFixture)
          Notice(
            'Beispielseite · mit KI erkannt. Der Beispieltext ist unveränderlich.',
            icon: Icons.science_outlined,
          ),
        if (synthetic && !liveFixture)
          Notice(
            'Vorbereitete Beispielseite · ohne KI-Erkennung.',
            icon: Icons.science_outlined,
          ),
        if ((!synthetic || liveFixture) && d['has_image'] != false)
          Panel(
            child: LoadView<Uint8List>(
              revision: (d['id'], d['revision'], ObjectKey(account)),
              load: () => widget.state.api.bytes('/materials/${d['id']}/image'),
              builder: (bytes, _) => SizedBox(
                height: 350,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        if (d['status'] == 'uploaded' && !readonly && !extractionRunning)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: ActionButton(
              label: 'Material erkennen lassen',
              icon: Icons.document_scanner_outlined,
              onPressed: () async {
                if (!sourceCurrent(d)) return;
                await widget.state.api.job('/materials/${d['id']}/extract');
                if (sourceCurrent(d)) widget.onRefresh();
              },
            ),
          ),
        for (final uncertainty in d['uncertainties'] as List)
          Notice(uncertainty, warning: true),
        SizedBox(height: 18),
        if (d['status'] == 'unreadable') ...[
          Notice(
            'Das Foto ist nicht lesbar. Bitte im Fotoassistenten neu aufnehmen.',
            warning: true,
          ),
          OutlinedButton.icon(
            onPressed: () =>
                openRoute(context, '/after-school/${d['child_id']}'),
            icon: Icon(Icons.add_a_photo_outlined),
            label: Text('Neues Foto machen'),
          ),
        ],
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Was steht in diesem Material?'),
              sourceReadingTools(),
              if (!editing) ...[
                LearningContent(
                  content.text,
                  figureBuilder: d['has_image'] == true
                      ? (index, _) => NotebookFigure(widget.state, d, index)
                      : null,
                  blocks: content.text == d['content']
                      ? d['source_blocks'] as List?
                      : null,
                ),
                if (canConfirm && !synthetic)
                  TextButton.icon(
                    onPressed: changing
                        ? null
                        : () => setState(() => editing = true),
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Erkannten Text verbessern'),
                  ),
              ],
              if (editing)
                TextButton.icon(
                  onPressed: changing
                      ? null
                      : () => setState(() => editing = false),
                  icon: Icon(Icons.menu_book_outlined),
                  label: Text('Leseansicht'),
                ),
              if (editing)
                for (final item in [
                  (subject, 'Fach', 1),
                  (topic, 'Thema', 1),
                  (content, 'Erkannter Unterrichtsstoff', 8),
                  (homework, 'Erkannte Aufgaben (eine pro Zeile)', 3),
                ])
                  Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: item.$1 == subject
                        ? SubjectField(
                            widget.state,
                            childId: d['child_id'],
                            controller: subject,
                            enabled: !changing && !synthetic && canConfirm,
                            changed: () => setState(() {}),
                          )
                        : TextField(
                            controller: item.$1,
                            maxLength: item.$1 == content
                                ? 24000
                                : item.$1 == topic
                                ? 160
                                : null,
                            maxLengthEnforcement: MaxLengthEnforcement.none,
                            onChanged: (_) => setState(() {}),
                            readOnly: changing || synthetic || !canConfirm,
                            maxLines: item.$3,
                            decoration: InputDecoration(
                              labelText: item.$2,
                              alignLabelWithHint: true,
                            ),
                          ),
                  ),
              if ((d['homework'] as List).isEmpty)
                Text(
                  'Hier wurden keine Aufgabenangaben erkannt.',
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
              if (canConfirm && dirty && !synthetic)
                TextButton.icon(
                  onPressed: changing ? null : discardCorrection,
                  icon: Icon(Icons.undo_rounded),
                  label: Text('Eigene Korrektur zurücknehmen'),
                ),
              if (canConfirm) ...[
                if (wordPreview != null) ...[
                  wordPreviewPanel(),
                  SizedBox(height: 16),
                ],
                SizedBox(height: 12),
                ActionButton(
                  label: d['confirmed']
                      ? 'Bestätigung speichern'
                      : 'Stimmt, weiter',
                  icon: Icons.check_rounded,
                  onPressed: () => change(confirmPage),
                ),
                if (wordPreview != null) saveWithoutWords(),
              ],
            ],
          ),
        ),
        SizedBox(height: 22),
        if (d['confirmed'] == true && wordPreview != null) savedWordPanel(),
        if (d['confirmed'] && widget.showUnitAction)
          Panel(
            color: context.palette.mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Bereit für eine kleine Lerneinheit?'),
                Text('Übe deinen bestätigten Stoff.'),
                SizedBox(height: 16),
                if (!readonly)
                  ActionButton(
                    label: widget.state.isChild
                        ? 'Jetzt Einheit vorbereiten & lernen'
                        : 'Lerneinheit für das Kind vorbereiten',
                    icon: Icons.auto_stories_outlined,
                    onPressed: () async {
                      if (!sourceCurrent(d)) return;
                      final childId = d['child_id'] as String;
                      final result = await widget.state.api.job(
                        '/children/$childId/units',
                        {'material_id': d['id']},
                      );
                      if (!mounted || !sourceCurrent(d)) return;
                      if (widget.state.isChild) {
                        await widget.state.api.post(
                          '/units/${result['unit_id']}/start',
                        );
                      }
                      if (context.mounted && sourceCurrent(d)) {
                        openRoute(context, '/unit/${result['unit_id']}');
                      }
                    },
                  ),
              ],
            ),
          ),
        if (d['confirmed'] == true && d['synthetic'] != true)
          TextButton.icon(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: Text('Fragen zu dieser Heftseite'),
            onPressed: () => showTutorSheet(
              context,
              widget.state,
              childId: d['child_id'],
              materialId: d['id'],
            ),
          ),
        if (d['synthetic'] != true &&
            ['review', 'confirmed'].contains(d['status']))
          LearningTips(
            widget.state,
            childId: d['child_id'],
            kind: 'material',
            resourceId: d['id'],
          ),
      ],
    );
  }

  Future<void> confirmPage() async {
    validateCorrection();
    if (!current || sourceConflict) return;
    final d = widget.data;
    final owner = widget.state.user;
    if (d.containsKey('vocabulary_preview') &&
        !editedPreviewCurrent &&
        (subject.text != d['subject'] ||
            topic.text != d['topic'] ||
            content.text != d['content'])) {
      final draftSubject = subject.text,
          draftTopic = topic.text,
          draftContent = content.text;
      final response = await widget.state.api.post(
        '/materials/${d['id']}/vocabulary-preview',
        {'subject': draftSubject, 'topic': draftTopic, 'content': draftContent},
      );
      if (!mounted ||
          !identical(owner, widget.state.user) ||
          d['id'] != widget.data['id'] ||
          d['revision'] != widget.data['revision'] ||
          subject.text != draftSubject ||
          topic.text != draftTopic ||
          content.text != draftContent) {
        return;
      }
      setState(() {
        previewSubject = subject.text;
        previewTopic = topic.text;
        previewContent = content.text;
        editedWordPreview = response['preview'] is Map
            ? Json.from(response['preview'])
            : null;
      });
      if (editedWordPreview != null) {
        toast(context, 'Wortpaare aktualisiert. Bitte noch einmal prüfen.');
        return;
      }
    }
    final body = <String, dynamic>{
      'subject': subject.text,
      'topic': topic.text,
      'content': content.text,
      'homework': homework.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'uncertainties_resolved': true,
      if (widget.data['revision'] is int) 'revision': widget.data['revision'],
      if (wordPreview?['requires_pair_confirmation'] == true &&
          selectedWords.isNotEmpty)
        'vocabulary': wordConfirmation,
    };
    if (d['supports_task_confirmation'] == true &&
        d['synthetic'] != true &&
        d['purpose'] != 'homework') {
      final preview = await widget.state.api.post(
        '/materials/${d['id']}/task-preview',
        body,
      );
      if (!mounted ||
          !identical(owner, widget.state.user) ||
          d['id'] != widget.data['id'] ||
          d['revision'] != widget.data['revision']) {
        return;
      }
      final items = (preview['items'] as List? ?? [])
          .map((r) => Json.from(r))
          .toList();
      final duplicates = (preview['duplicates'] as List? ?? []);
      if (items.isNotEmpty || duplicates.isNotEmpty) {
        final route = DialogRoute<List<Json>>(
          context: context,
          builder: (_) => MaterialTaskDialog(
            items: items,
            hasDuplicate: duplicates.isNotEmpty,
          ),
        );
        taskPreviewRoute = route;
        final decisions = await Navigator.of(
          context,
          rootNavigator: true,
        ).push(route);
        if (identical(taskPreviewRoute, route)) taskPreviewRoute = null;
        if (decisions == null ||
            !mounted ||
            !identical(owner, widget.state.user) ||
            d['id'] != widget.data['id'] ||
            d['revision'] != widget.data['revision']) {
          return;
        }
        body['task_decisions'] = decisions;
      }
    }
    final result = await widget.state.api.put(
      '/materials/${d['id']}/confirm',
      body,
    );
    if (!mounted ||
        !identical(owner, widget.state.user) ||
        d['id'] != widget.data['id'] ||
        d['revision'] != widget.data['revision']) {
      return;
    }
    widget.state.collectionViews.remove(correctionKey);
    setState(() => confirmedHere = true);
    widget.state.refreshState();
    if (result['vocabulary_transfer'] is Map) {
      final words = result['vocabulary_transfer'];
      toast(
        context,
        '${counted(words['confirmed_words'] as num? ?? 0, 'Wort', 'Wörter')} gespeichert${(words['review_words'] as num? ?? 0) > 0 ? ' · ${words['review_words']} noch prüfen' : ''}.',
      );
    }
    widget.onRefresh();
  }

  Widget childReview(BuildContext context) {
    final d = widget.data;
    final synthetic = d['synthetic'] == true;
    final confirmed = d['confirmed'] == true || confirmedHere;
    final languageMaterial = [
      'englisch',
      'english',
      'französisch',
      'francais',
      'spanisch',
    ].contains((d['subject'] ?? '').toString().trim().toLowerCase());
    final uncertainties = d['uncertainties'] as List? ?? [];
    final canConfirm = !confirmed && d['status'] == 'review';
    final longText =
        content.text.length > 120 || content.text.split('\n').length > 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pageActions(),
        if (dirty && !confirmedHere)
          Semantics(
            liveRegion: true,
            child: Notice(
              restoredCorrection
                  ? 'Deine Korrektur ist hier wieder aufgenommen. Mit „Stimmt, weiter“ übernimmst du sie.'
                  : 'Deine Korrektur ist noch nicht übernommen. Mit „Stimmt, weiter“ speicherst du den geprüften Text.',
            ),
          ),
        SizedBox(height: 10),
        if ((!synthetic || d['fixture_id'] != null) &&
            d['has_image'] != false) ...[
          Panel(
            padding: EdgeInsets.all(12),
            child: LoadView<Uint8List>(
              revision: (d['id'], d['revision'], ObjectKey(account)),
              load: () => widget.state.api.bytes('/materials/${d['id']}/image'),
              builder: (bytes, _) => Semantics(
                button: true,
                label: 'Heftfoto vergrößern',
                child: InkWell(
                  onTap: () => zoomNotebookPhoto(context, widget.state, d),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(bytes, fit: BoxFit.contain),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(
                            Icons.zoom_in_rounded,
                            color: context.palette.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
        ],
        if (d['status'] == 'uploaded' && !extractionRunning)
          ActionButton(
            label: 'Text lesen lassen',
            onPressed: () async {
              if (!sourceCurrent(d)) return;
              await widget.state.api.job('/materials/${d['id']}/extract');
              if (sourceCurrent(d)) widget.onRefresh();
            },
          )
        else if (d['status'] == 'unreadable')
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice(
                'Das Foto ist nicht lesbar. Nimm die Seite bitte noch einmal auf.',
                warning: true,
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    openRoute(context, '/after-school/${d['child_id']}'),
                icon: Icon(Icons.add_a_photo_outlined),
                label: Text('Neues Foto machen'),
              ),
            ],
          )
        else
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${subject.text} · ${topic.text}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (synthetic) ...[
                  SizedBox(height: 8),
                  Text(
                    'Beispielseite',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                SizedBox(height: 14),
                sourceReadingTools(),
                LearningContent(
                  content.text,
                  figureBuilder: !longText && d['has_image'] == true
                      ? (index, _) => NotebookFigure(widget.state, d, index)
                      : null,
                  blocks: content.text == d['content']
                      ? d['source_blocks'] as List?
                      : null,
                  compact: longText,
                ),
                if (longText)
                  ExpansionTile(
                    title: Text('Ganzen Text lesen'),
                    children: [
                      LearningContent(
                        content.text,
                        figureBuilder: d['has_image'] == true
                            ? (index, _) =>
                                  NotebookFigure(widget.state, d, index)
                            : null,
                        blocks: content.text == d['content']
                            ? d['source_blocks'] as List?
                            : null,
                      ),
                    ],
                  ),
                if (homework.text.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text(
                    'Aufgaben auf dieser Seite',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(homework.text),
                ],
                if (canConfirm && !synthetic)
                  TextButton.icon(
                    onPressed: changing
                        ? null
                        : () => setState(() => editing = !editing),
                    icon: Icon(
                      editing ? Icons.close_rounded : Icons.edit_outlined,
                      size: 18,
                    ),
                    label: Text(
                      editing ? 'Korrektur schließen' : 'Etwas verbessern',
                    ),
                  ),
                if (editing)
                  for (final field in [
                    (subject, 'Fach', 1),
                    (topic, 'Thema', 1),
                    (content, 'Text auf der Seite', 6),
                    (homework, 'Erkannte Aufgaben', 3),
                  ])
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: field.$1 == subject
                          ? SubjectField(
                              widget.state,
                              childId: d['child_id'],
                              controller: subject,
                              enabled: !changing && !synthetic && canConfirm,
                              changed: () => setState(() {}),
                            )
                          : TextField(
                              controller: field.$1,
                              maxLength: field.$1 == content
                                  ? 24000
                                  : field.$1 == topic
                                  ? 160
                                  : null,
                              maxLengthEnforcement: MaxLengthEnforcement.none,
                              readOnly: changing,
                              onChanged: (_) => setState(() {}),
                              maxLines: field.$3,
                              decoration: InputDecoration(
                                labelText: field.$2,
                                alignLabelWithHint: true,
                              ),
                            ),
                    ),
                if (canConfirm) ...[
                  SizedBox(height: 16),
                  if (wordPreview != null) ...[
                    wordPreviewPanel(),
                    SizedBox(height: 16),
                  ],
                  if (uncertainties.isNotEmpty) ...[
                    Text(
                      'Hier bitte genau hinschauen:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final uncertainty in uncertainties)
                      Notice('$uncertainty', warning: true),
                  ],
                  SizedBox(height: 10),
                  ActionButton(
                    label: 'Stimmt, weiter',
                    icon: Icons.check_rounded,
                    onPressed: () => change(confirmPage),
                  ),
                  if (wordPreview != null) saveWithoutWords(),
                ] else if (confirmed) ...[
                  SizedBox(height: 14),
                  Tag('Text übernommen'),
                ],
              ],
            ),
          ),
        if (d['confirmed'] == true && wordPreview != null) savedWordPanel(),
        if (canConfirm && dirty && !synthetic)
          TextButton.icon(
            onPressed: changing ? null : discardCorrection,
            icon: Icon(Icons.undo_rounded),
            label: Text('Eigene Korrektur zurücknehmen'),
          ),
        if (confirmed && widget.showUnitAction) ...[
          SizedBox(height: 16),
          ActionButton(
            label: languageMaterial ? 'Wörter & Sprache üben' : 'Jetzt lernen',
            icon: Icons.play_arrow_rounded,
            onPressed: () async {
              if (!sourceCurrent(d)) return;
              if (languageMaterial) {
                openRoute(
                  context,
                  '/vocabulary/${d['child_id']}?material=${d['id']}',
                );
                return;
              }
              final result = await widget.state.api.job(
                '/children/${d['child_id']}/units',
                {'material_id': d['id']},
              );
              if (!sourceCurrent(d)) return;
              await widget.state.api.post('/units/${result['unit_id']}/start');
              if (context.mounted && sourceCurrent(d)) {
                openRoute(context, '/unit/${result['unit_id']}');
              }
            },
          ),
        ],
        if (confirmed && d['synthetic'] != true) ...[
          SizedBox(height: 12),
          TextButton.icon(
            icon: Icon(Icons.translate_rounded),
            label: Text('Wörter aus dieser Seite'),
            onPressed: () => openRoute(
              context,
              '/vocabulary/${d['child_id']}?material=${d['id']}',
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: Text('Frag nach'),
            onPressed: () => showTutorSheet(
              context,
              widget.state,
              childId: d['child_id'],
              materialId: d['id'],
            ),
          ),
        ],
        if (d['synthetic'] != true &&
            ['review', 'confirmed'].contains(d['status']))
          LearningTips(
            widget.state,
            childId: d['child_id'],
            kind: 'material',
            resourceId: d['id'],
          ),
      ],
    );
  }
}

/// Only material tools use this surface: unrelated notebook/collection dialogs
/// retain their existing layout and contract.
class _MaterialReadingSurface extends StatelessWidget {
  final Widget child;
  const _MaterialReadingSurface({required this.child});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 720) {
      return Dialog.fullscreen(child: SafeArea(child: child));
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1000,
        height: math.min(900.0, size.height - 48),
        child: child,
      ),
    );
  }
}

class _SourceTextReader extends StatelessWidget {
  final String text;
  final List<dynamic>? blocks;
  final List uncertainties;
  final VoidCallback onClose;
  final bool Function() isCurrent;
  const _SourceTextReader({
    required this.text,
    required this.onClose,
    required this.isCurrent,
    this.blocks,
    this.uncertainties = const [],
  });
  @override
  Widget build(BuildContext context) => _MaterialReadingSurface(
    child: Ideas100SourceReader(
      text: text,
      blocks: blocks,
      uncertainties: uncertainties,
      onClose: onClose,
      isCurrent: isCurrent,
    ),
  );
}

class _MaterialCompareDialog extends StatefulWidget {
  final String title, firstLabel, secondLabel, firstChoice, secondChoice;
  final String? notice;
  final Widget first, second;
  final VoidCallback onClose;
  const _MaterialCompareDialog({
    required this.title,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstChoice,
    required this.secondChoice,
    required this.first,
    required this.second,
    required this.onClose,
    this.notice,
  });
  @override
  State<_MaterialCompareDialog> createState() => _MaterialCompareState();
}

class _MaterialCompareState extends State<_MaterialCompareDialog> {
  int side = 0;
  @override
  Widget build(BuildContext context) => _MaterialReadingSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Vergleich schließen',
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              Widget pane(String label, Widget child) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  child,
                ],
              );
              final wide =
                  constraints.maxWidth >= 760 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          for (final (i, label) in [
                            widget.firstChoice,
                            widget.secondChoice,
                          ].indexed)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Semantics(
                                  selected: side == i,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: side == i
                                          ? context.palette.mint
                                          : null,
                                      minimumSize: const Size(48, 48),
                                    ),
                                    onPressed: () {
                                      if (mounted &&
                                          ModalRoute.of(context)?.isCurrent ==
                                              true) {
                                        setState(() => side = i);
                                      }
                                    },
                                    child: Text(label),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.notice != null) ...[
                            Text(widget.notice!),
                            const SizedBox(height: 12),
                          ],
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: pane(widget.firstLabel, widget.first),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: pane(
                                    widget.secondLabel,
                                    widget.second,
                                  ),
                                ),
                              ],
                            )
                          else
                            pane(
                              side == 0
                                  ? widget.firstLabel
                                  : widget.secondLabel,
                              side == 0 ? widget.first : widget.second,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
