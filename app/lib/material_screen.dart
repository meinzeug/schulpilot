import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'learning_tips.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'material_words.dart';
import 'subject_picker.dart';

Future<void> importMaterial(
  BuildContext context,
  AppState state,
  String childId,
) async {
  final owner = state.user?['id'];
  if (state.isDemo) {
    if (!await confirmDialog(
      context,
      'Künstliches Testblatt mit echter KI erkennen?',
      'Der Server erstellt ein festes Bild ohne persönliche Daten. Dieses Bild wird an das konfigurierte kostenlose OpenRouter-Modell gesendet. Keine eigenen Fotos oder Texte werden verwendet.',
    )) {
      return;
    }
    final material = await state.api.post(
      '/children/$childId/materials/synthetic-fixture',
    );
    if (context.mounted && owner == state.user?['id']) {
      state.refreshState();
      openRoute(context, '/material/${material['id']}');
    }
    return;
  }
  final status = await state.api.get('/status');
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
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Hefteintrag fotografieren'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Bild auswählen'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  final cropped = await pickMaterialPhoto(context, source);
  if (cropped == null) return;
  final material = await state.api.upload(childId, cropped);
  if (context.mounted && owner == state.user?['id']) {
    state.refreshState();
    openRoute(context, '/material/${material['id']}');
  }
}

Future<Uint8List?> pickMaterialPhoto(
  BuildContext context,
  ImageSource source,
) async {
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
  return cropMaterialPhoto(context, bytes);
}

Future<Uint8List?> cropMaterialPhoto(
  BuildContext context,
  Uint8List bytes,
) async {
  if (bytes.length > 10 * 1024 * 1024) {
    throw ApiError('Das Bild darf höchstens 10 MB groß sein.');
  }
  return showDialog<Uint8List>(
    context: context,
    builder: (ctx) => CropDialog(bytes),
  );
}

class CropDialog extends StatefulWidget {
  final Uint8List bytes;
  const CropDialog(this.bytes, {super.key});
  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  double left = 0, top = 0, right = 1, bottom = 1;
  int quarterTurns = 0;
  int? dragCorner;
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
    title: const Text('Passt das Foto?'),
    content: SizedBox(
      width: 590,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Namen bitte abschneiden. Der Text soll gut lesbar sein.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            TextButton.icon(
              onPressed: image == null
                  ? null
                  : () => setState(() {
                      image = img.copyRotate(image!, angle: 90);
                      quarterTurns = (quarterTurns + 1) % 4;
                      preview = Uint8List.fromList(
                        img.encodeJpg(image!, quality: 85),
                      );
                      left = top = 0;
                      right = bottom = 1;
                    }),
              icon: const Icon(Icons.rotate_right),
              label: const Text('Um 90° drehen'),
            ),
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * .40).clamp(240, 420),
              child: LayoutBuilder(
                builder: (context, size) => Center(
                  child: AspectRatio(
                    aspectRatio: image == null
                        ? 1
                        : image!.width / image!.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(preview, fit: BoxFit.fill),
                        LayoutBuilder(
                          builder: (context, bounds) => Semantics(
                            label: 'Zuschneiderahmen. Ziehe eine Ecke. Darunter kannst du die Ränder mit Reglern verändern.',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: image == null
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
                                      for (var i = 1; i < corners.length; i++) {
                                        if ((corners[i] - point).distance <
                                            (corners[nearest] - point)
                                                .distance) {
                                          nearest = i;
                                        }
                                      }
                                      dragCorner = nearest;
                                    },
                              onPanUpdate: image == null
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
                                      if (dragCorner == 0 || dragCorner == 2) {
                                        left = x.clamp(0.0, right - .1);
                                      }
                                      if (dragCorner == 1 || dragCorner == 3) {
                                        right = x.clamp(left + .1, 1.0);
                                      }
                                      if (dragCorner == 0 || dragCorner == 1) {
                                        top = y.clamp(0.0, bottom - .1);
                                      }
                                      if (dragCorner == 2 || dragCorner == 3) {
                                        bottom = y.clamp(top + .1, 1.0);
                                      }
                                    }),
                              onPanEnd: (_) => dragCorner = null,
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
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Bild zuschneiden'),
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
                        child: Text(
                          item.$1,
                          style: const TextStyle(fontSize: 12),
                        ),
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
                          onChanged: item.$5,
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
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      ActionButton(
        label: 'Zuschnitt übernehmen',
        onPressed: () async {
          if (image == null) {
            throw ApiError(
              'Dieses Bildformat konnte nicht gelesen werden. Bitte JPEG oder PNG auswählen.',
            );
          }
          // Give the busy indicator a frame; native encoding runs off the UI
          // isolate. Web's compute still runs on the browser's event loop.
          await Future<void>.delayed(const Duration(milliseconds: 32));
          final encoded = await compute(encodeMaterialCrop, <String, dynamic>{
            'bytes': widget.bytes,
            'turns': quarterTurns,
            'left': left,
            'top': top,
            'right': right,
            'bottom': bottom,
          });
          if (context.mounted) Navigator.pop(context, encoded);
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
    title: const Text('Was ist wirklich aufgegeben?'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nur bestätigte Hausaufgaben kommen verbindlich in deinen Plan. Beispiele bleiben im Heft.',
            ),
            if (widget.hasDuplicate) ...[
              const SizedBox(height: 12),
              const Notice(
                'Ein ähnliches Blatt ist schon gespeichert. Du kannst zurückgehen und das doppelte Foto entfernen. Gleiche Aufträge desselben Tages zählen nur einmal.',
                warning: true,
              ),
            ],
            for (final item in widget.items) ...[
              const SizedBox(height: 18),
              Text(
                item['text'],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: choices[item['key']],
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'So wurde es in der Schule gesagt',
                ),
                items: const [
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
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Bleibt im Heft und wird vorerst nicht verbindlich eingeplant.',
                    style: TextStyle(color: muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Zurück'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, <Json>[
          for (final entry in choices.entries)
            {'key': entry.key, 'classification': entry.value},
        ]),
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
  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: widget.state.isChild ? 'Dein Lernstoff' : 'Heftseite',
    subtitle: widget.state.isChild ? 'Schau kurz, ob der Text stimmt.' : null,
    child: LoadView<Json>(
      key: ValueKey(version),
      load: () => widget.state.api.get('/materials/${widget.materialId}'),
      builder: (data, refresh) => MaterialReview(
        widget.state,
        data,
        simpleChild: widget.state.isChild,
        onRefresh: () => setState(() => version++),
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

class _MaterialReviewState extends State<MaterialReview> {
  late final subject = TextEditingController(text: widget.data['subject']);
  late final topic = TextEditingController(text: widget.data['topic']);
  late final content = TextEditingController(text: widget.data['content']);
  late final homework = TextEditingController(
    text: (widget.data['homework'] as List).join('\n'),
  );
  bool editing = false, confirmedHere = false;
  bool changing = false;
  String? wordLocale;
  bool reverseWords = false;
  Json? editedWordPreview;
  List<Json> selectedWords = [];
  String? previewSubject, previewTopic, previewContent;

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
    icon: const Icon(Icons.description_outlined),
    label: const Text('Nur Heftseite speichern'),
  );

  Widget wordPreviewPanel({bool saved = false}) => MaterialWordsPanel(
    key: ValueKey(jsonEncode([wordPreview, selectedWordLocale, reverseWords])),
    preview: wordPreview!,
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
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: LoadView<Json>(
      revision: widget.data['revision'],
      load: () =>
          widget.state.api.get('/materials/${widget.data['id']}/vocabulary'),
      builder: (status, refresh) {
        final stored = status['confirmed_words'] as int? ?? 0;
        final pending = status['review_words'] as int? ?? 0;
        final canWrite = widget.state.isChild || widget.state.canManage;
        if (stored + pending == 0 && !canWrite) return const SizedBox.shrink();
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stored + pending > 0) ...[
                Text(
                  '$stored Wörter gespeichert${pending > 0 ? ' · $pending noch prüfen' : ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if ((status['unpaired_lines'] as num? ?? 0) > 0)
                  Text(
                    '${status['unpaired_lines']} weitere Zeilen wurden nicht als Wortpaare übernommen.',
                    style: const TextStyle(color: warningInk),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openRoute(
                    context,
                    '/vocabulary/${widget.data['child_id']}?material=${widget.data['id']}',
                  ),
                  icon: const Icon(Icons.translate_rounded),
                  label: Text(pending > 0 ? 'Wörter prüfen' : 'Wörter öffnen'),
                ),
              ] else if (canWrite) ...[
                wordPreviewPanel(saved: true),
                const SizedBox(height: 12),
                ActionButton(
                  label: 'Wörter übernehmen',
                  icon: Icons.playlist_add_check_rounded,
                  enabled: selectedWords.isNotEmpty,
                  onPressed: () async {
                    final owner = widget.state.user?['id'];
                    await widget.state.api.post(
                      '/materials/${widget.data['id']}/vocabulary',
                      wordConfirmation,
                    );
                    if (mounted && owner == widget.state.user?['id']) {
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
    if (changing) return;
    changing = true;
    try {
      await action();
    } finally {
      changing = false;
    }
  }

  Future<void> deletePage() async {
    final d = widget.data;
    if (!await confirmDialog(
      context,
      'Seite löschen?',
      d['confirmed'] == true
          ? 'Das Foto und der Text werden gelöscht. Deine bisherigen Übungen bleiben erhalten.'
          : 'Dieses Foto und der erkannte Text werden gelöscht.',
    )) {
      return;
    }
    if (!mounted) return;
    final dayId = d['school_day_id'];
    await widget.state.api.delete(
      dayId != null && d['confirmed'] != true
          ? '/school-days/$dayId/pages/${d['id']}'
          : '/materials/${d['id']}',
    );
    if (!mounted) return;
    if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      context.go('/app');
    }
  }

  Widget deleteButton() => ActionButton(
    label: 'Seite löschen',
    secondary: true,
    icon: Icons.delete_outline_rounded,
    onPressed: () => change(deletePage),
  );

  bool get fixedDayExample =>
      widget.data['synthetic'] == true &&
      widget.data['school_day_id'] != null &&
      widget.data['fixture_id'] != null;
  @override
  void dispose() {
    for (final c in [subject, topic, content, homework]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 22),
        if (liveFixture)
          const Notice(
            'Beispielseite · mit KI erkannt. Der Beispieltext ist unveränderlich.',
            icon: Icons.science_outlined,
          ),
        if (synthetic && !liveFixture)
          const Notice(
            'Vorbereitete Beispielseite · ohne KI-Erkennung.',
            icon: Icons.science_outlined,
          ),
        if (!synthetic || liveFixture)
          Panel(
            child: LoadView<Uint8List>(
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
        if (d['status'] == 'uploaded' && !readonly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: ActionButton(
              label: 'Material erkennen lassen',
              icon: Icons.document_scanner_outlined,
              onPressed: () async {
                await widget.state.api.job('/materials/${d['id']}/extract');
                widget.onRefresh();
              },
            ),
          ),
        for (final uncertainty in d['uncertainties'] as List)
          Notice(uncertainty, warning: true),
        const SizedBox(height: 18),
        if (d['status'] == 'unreadable')
          const Notice(
            'Das Foto ist nicht lesbar. Bitte im Fotoassistenten neu aufnehmen.',
            warning: true,
          ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Was steht in diesem Material?'),
              for (final item in [
                (subject, 'Fach', 1),
                (topic, 'Thema', 1),
                (content, 'Erkannter Unterrichtsstoff', 8),
                (homework, 'Erkannte Aufgaben (eine pro Zeile)', 3),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: item.$1 == subject
                      ? SubjectField(
                          widget.state,
                          childId: d['child_id'],
                          controller: subject,
                          enabled: !synthetic && canConfirm,
                          changed: () => setState(() {}),
                        )
                      : TextField(
                          controller: item.$1,
                          onChanged: (_) => setState(() {}),
                          readOnly: synthetic || !canConfirm,
                          maxLines: item.$3,
                          decoration: InputDecoration(
                            labelText: item.$2,
                            alignLabelWithHint: true,
                          ),
                        ),
                ),
              if ((d['homework'] as List).isEmpty)
                const Text(
                  'Hier wurden keine Aufgabenangaben erkannt.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              if (canConfirm) ...[
                if (wordPreview != null) ...[
                  wordPreviewPanel(),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 12),
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
        const SizedBox(height: 22),
        if (d['confirmed'] == true && wordPreview != null) savedWordPanel(),
        if (d['confirmed'] && widget.showUnitAction)
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Bereit für eine kleine Lerneinheit?'),
                const Text('Übe deinen bestätigten Stoff.'),
                const SizedBox(height: 20),
                if (!readonly)
                  ActionButton(
                    label: widget.state.isChild
                        ? 'Jetzt Einheit vorbereiten & lernen'
                        : 'Lerneinheit für das Kind vorbereiten',
                    icon: Icons.auto_stories_outlined,
                    onPressed: () async {
                      final childId = d['child_id'] as String;
                      final result = await widget.state.api.job(
                        '/children/$childId/units',
                        {'material_id': d['id']},
                      );
                      if (widget.state.isChild) {
                        await widget.state.api.post(
                          '/units/${result['unit_id']}/start',
                        );
                      }
                      if (context.mounted) {
                        openRoute(context, '/unit/${result['unit_id']}');
                      }
                    },
                  ),
              ],
            ),
          ),
        if (d['confirmed'] == true && d['synthetic'] != true)
          TextButton.icon(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Fragen zu dieser Heftseite'),
            onPressed: () => showTutorSheet(
              context,
              widget.state,
              childId: d['child_id'],
              materialId: d['id'],
            ),
          ),
        if (!readonly &&
            !fixedDayExample &&
            ((widget.state.isParent && widget.state.canManage) ||
                (widget.state.isChild && d['confirmed'] != true)))
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: deleteButton(),
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
    final d = widget.data;
    final owner = widget.state.user?['id'];
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
          owner != widget.state.user?['id'] ||
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
    if (d['supports_task_confirmation'] == true && d['synthetic'] != true) {
      final preview = await widget.state.api.post(
        '/materials/${d['id']}/task-preview',
        body,
      );
      if (!mounted || owner != widget.state.user?['id']) return;
      final items = (preview['items'] as List? ?? [])
          .map((r) => Json.from(r))
          .toList();
      final duplicates = (preview['duplicates'] as List? ?? []);
      if (items.isNotEmpty || duplicates.isNotEmpty) {
        final decisions = await showDialog<List<Json>>(
          context: context,
          builder: (_) => MaterialTaskDialog(
            items: items,
            hasDuplicate: duplicates.isNotEmpty,
          ),
        );
        if (decisions == null ||
            !mounted ||
            owner != widget.state.user?['id']) {
          return;
        }
        body['task_decisions'] = decisions;
      }
    }
    final result = await widget.state.api.put(
      '/materials/${d['id']}/confirm',
      body,
    );
    if (!mounted || owner != widget.state.user?['id']) return;
    setState(() => confirmedHere = true);
    widget.state.refreshState();
    if (result['vocabulary_transfer'] is Map) {
      final words = result['vocabulary_transfer'];
      toast(
        context,
        '${words['confirmed_words']} Wörter gespeichert${(words['review_words'] as num? ?? 0) > 0 ? ' · ${words['review_words']} noch prüfen' : ''}.',
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
        if (!synthetic || d['fixture_id'] != null) ...[
          Panel(
            padding: const EdgeInsets.all(12),
            child: LoadView<Uint8List>(
              load: () => widget.state.api.bytes('/materials/${d['id']}/image'),
              builder: (bytes, _) => Semantics(
                button: true,
                label: 'Heftfoto vergrößern',
                child: InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: InteractiveViewer(
                              maxScale: 5,
                              child: Image.memory(bytes),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Schließen'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(bytes, fit: BoxFit.contain),
                        const Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(Icons.zoom_in_rounded, color: teal),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (d['status'] == 'uploaded')
          ActionButton(
            label: 'Text lesen lassen',
            onPressed: () async {
              await widget.state.api.job('/materials/${d['id']}/extract');
              widget.onRefresh();
            },
          )
        else if (d['status'] == 'unreadable')
          const Notice(
            'Das Foto ist nicht lesbar. Nimm die Seite bitte noch einmal auf.',
            warning: true,
          )
        else
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${subject.text} · ${topic.text}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (synthetic) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Beispielseite',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  content.text,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                  maxLines: longText ? 7 : null,
                  overflow: longText
                      ? TextOverflow.ellipsis
                      : TextOverflow.clip,
                ),
                if (longText)
                  ExpansionTile(
                    title: const Text('Ganzen Text lesen'),
                    children: [
                      Text(content.text, style: const TextStyle(height: 1.5)),
                    ],
                  ),
                if (homework.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Aufgaben auf dieser Seite',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(homework.text),
                ],
                if (canConfirm && !synthetic)
                  TextButton.icon(
                    onPressed: () => setState(() => editing = !editing),
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
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field.$1 == subject
                          ? SubjectField(
                              widget.state,
                              childId: d['child_id'],
                              controller: subject,
                              enabled: !synthetic && canConfirm,
                              changed: () => setState(() {}),
                            )
                          : TextField(
                              controller: field.$1,
                              onChanged: (_) => setState(() {}),
                              maxLines: field.$3,
                              decoration: InputDecoration(
                                labelText: field.$2,
                                alignLabelWithHint: true,
                              ),
                            ),
                    ),
                if (canConfirm) ...[
                  const SizedBox(height: 16),
                  if (wordPreview != null) ...[
                    wordPreviewPanel(),
                    const SizedBox(height: 16),
                  ],
                  if (uncertainties.isNotEmpty) ...[
                    const Text(
                      'Hier bitte genau hinschauen:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final uncertainty in uncertainties)
                      Notice('$uncertainty', warning: true),
                  ],
                  const SizedBox(height: 10),
                  ActionButton(
                    label: 'Stimmt, weiter',
                    icon: Icons.check_rounded,
                    onPressed: () => change(confirmPage),
                  ),
                  if (wordPreview != null) saveWithoutWords(),
                ] else if (confirmed) ...[
                  const SizedBox(height: 14),
                  const Tag('Text übernommen'),
                ],
              ],
            ),
          ),
        if (!confirmed && !fixedDayExample) ...[
          const SizedBox(height: 12),
          deleteButton(),
        ],
        if (d['confirmed'] == true && wordPreview != null) savedWordPanel(),
        if (confirmed && widget.showUnitAction) ...[
          const SizedBox(height: 20),
          ActionButton(
            label: languageMaterial ? 'Wörter & Sprache üben' : 'Jetzt lernen',
            icon: Icons.play_arrow_rounded,
            onPressed: () async {
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
              await widget.state.api.post('/units/${result['unit_id']}/start');
              if (context.mounted) {
                openRoute(context, '/unit/${result['unit_id']}');
              }
            },
          ),
        ],
        if (confirmed && d['synthetic'] != true) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.translate_rounded),
            label: const Text('Wörter aus dieser Seite'),
            onPressed: () => openRoute(
              context,
              '/vocabulary/${d['child_id']}?material=${d['id']}',
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Frag nach'),
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
