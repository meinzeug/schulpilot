import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'ui.dart';

Future<void> importMaterial(
  BuildContext context,
  AppState state,
  String childId,
) async {
  if (state.isDemo) {
    throw ApiError(
      'Der synthetische Testraum enthält ein festes Beispiel. Bitte keine echten Fotos oder Kinderdaten hochladen.',
    );
  }
  final status = await state.api.get('/status');
  if (status['real_data_enabled'] != true) {
    throw ApiError(
      'Der Import echter Materialien ist bis zur dokumentierten Datenschutzfreigabe gesperrt.',
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
  if (source == null) return;
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 3200,
    maxHeight: 3200,
    imageQuality: 90,
    requestFullMetadata: false,
  );
  if (file == null) return;
  final bytes = await file.readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw ApiError('Das Bild darf höchstens 10 MB groß sein.');
  }
  if (!context.mounted) return;
  final cropped = await showDialog<Uint8List>(
    context: context,
    builder: (ctx) => CropDialog(bytes),
  );
  if (cropped == null) return;
  final material = await state.api.upload(childId, cropped);
  if (context.mounted) openRoute(context, '/material/${material['id']}');
}

class CropDialog extends StatefulWidget {
  final Uint8List bytes;
  const CropDialog(this.bytes, {super.key});
  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  double left = 0, top = 0, right = 1, bottom = 1;
  late final img.Image? image = orientedImage();
  img.Image? orientedImage() {
    final decoded = img.decodeImage(widget.bytes);
    return decoded == null ? null : img.bakeOrientation(decoded);
  }

  late final Uint8List preview = image == null
      ? widget.bytes
      : Uint8List.fromList(img.encodeJpg(image!, quality: 85));
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Persönliche Angaben abschneiden'),
    content: SizedBox(
      width: 590,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Notice(
              'Schneide Namen, Schule und andere persönliche Angaben aus dem sichtbaren Bild aus. Das Bild verlässt dein Gerät erst nach „Zuschneiden & hochladen“.',
            ),
            SizedBox(
              height: 250,
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
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _CropPainter(
                              Rect.fromLTRB(left, top, right, bottom),
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
                    child: Text(item.$1, style: const TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Slider(
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
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      ActionButton(
        label: 'Zuschneiden & hochladen',
        onPressed: () async {
          if (image == null) {
            throw ApiError(
              'Dieses Bildformat konnte nicht gelesen werden. Bitte JPEG oder PNG auswählen.',
            );
          }
          // Bake orientation before cropping; encode without EXIF/XMP metadata.
          final oriented = img.bakeOrientation(image!);
          final cropped = img.copyCrop(
            oriented,
            x: (left * oriented.width).round(),
            y: (top * oriented.height).round(),
            width: math.max(1, ((right - left) * oriented.width).floor()),
            height: math.max(1, ((bottom - top) * oriented.height).floor()),
          );
          final clean = img.Image.from(cropped)..exif.clear();
          final resized = clean.width > 1600 || clean.height > 1600
              ? img.copyResize(
                  clean,
                  width: clean.width >= clean.height ? 1600 : null,
                  height: clean.height > clean.width ? 1600 : null,
                )
              : clean;
          final encoded = Uint8List.fromList(
            img.encodeJpg(resized, quality: 88),
          );
          if (context.mounted) Navigator.pop(context, encoded);
        },
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
    title: 'Erst prüfen. Dann lernen.',
    subtitle: 'Wir kennen nur dieses Material. Unsicheres wird bestätigt; Übungen bleiben von notierten Hausaufgaben getrennt.',
    child: LoadView<Json>(
      key: ValueKey(version),
      load: () => widget.state.api.get('/materials/${widget.materialId}'),
      builder: (data, refresh) => _MaterialForm(
        widget.state,
        data,
        onRefresh: () => setState(() => version++),
      ),
    ),
  );
}

class _MaterialForm extends StatefulWidget {
  final AppState state;
  final Json data;
  final VoidCallback onRefresh;
  const _MaterialForm(this.state, this.data, {required this.onRefresh});
  @override
  State<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends State<_MaterialForm> {
  late final subject = TextEditingController(text: widget.data['subject']);
  late final topic = TextEditingController(text: widget.data['topic']);
  late final content = TextEditingController(text: widget.data['content']);
  late final homework = TextEditingController(
    text: (widget.data['homework'] as List).join('\n'),
  );
  bool checked = false;
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
    final synthetic = d['synthetic'] == true;
    final readonly = widget.state.isParent && !widget.state.canManage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(
              synthetic
                  ? 'Festes synthetisches Beispiel'
                  : 'Privates Unterrichtsmaterial',
            ),
            Tag(
              d['confirmed']
                  ? 'Bestätigter Lernstoff'
                  : 'Bestätigung erforderlich',
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (synthetic)
          const Notice(
            'Dieses Beispiel wurde vorbereitet. Es wurde kein Foto erkannt und kein KI-Anbieter aufgerufen. Die Demo-Übungen basieren ausschließlich auf diesem festen Text.',
            icon: Icons.science_outlined,
          )
        else
          Panel(
            child: LoadView<Uint8List>(
              load: () => widget.state.api.bytes('/materials/${d['id']}/image'),
              builder: (bytes, _) =>
                  Image.memory(bytes, height: 350, fit: BoxFit.contain),
            ),
          ),
        if (d['status'] == 'uploaded')
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
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Was steht in diesem Material?'),
              for (final item in [
                (subject, 'Fach', 1),
                (topic, 'Thema', 1),
                (content, 'Erkannter Unterrichtsstoff', 8),
                (
                  homework,
                  'Nur ausdrücklich notierte Hausaufgaben – eine pro Zeile',
                  3,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextField(
                    controller: item.$1,
                    readOnly: synthetic || readonly,
                    maxLines: item.$3,
                    decoration: InputDecoration(
                      labelText: item.$2,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              if ((d['homework'] as List).isEmpty)
                const Text(
                  'Keine ausdrücklich notierten Hausaufgaben in diesem Material erfasst.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              if (!readonly) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ich habe den Stoff geprüft und alle unsicheren Stellen geklärt.',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: checked,
                  onChanged: (v) => setState(() => checked = v ?? false),
                ),
                const SizedBox(height: 12),
                ActionButton(
                  label: d['confirmed']
                      ? 'Bestätigung speichern'
                      : 'Stoff bestätigen',
                  icon: Icons.check_rounded,
                  onPressed: () async {
                    if (!checked) {
                      throw ApiError(
                        'Bitte den Stoff prüfen und die Bestätigung aktivieren.',
                      );
                    }
                    await widget.state.api.put(
                      '/materials/${d['id']}/confirm',
                      {
                        'subject': subject.text,
                        'topic': topic.text,
                        'content': content.text,
                        'homework': homework.text
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(),
                        'uncertainties_resolved': true,
                      },
                    );
                    widget.onRefresh();
                    if (context.mounted) {
                      toast(context, 'Stoff bestätigt und gespeichert.');
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (d['confirmed'])
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Bereit für eine kleine Lerneinheit?'),
                const Text(
                  'Aus dem bestätigten Stoff entstehen strukturierte Übungen. Diese sind keine Behauptung über alle Hausaufgaben oder den gesamten Unterricht.',
                ),
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
        if (widget.state.isParent && widget.state.canManage)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: ActionButton(
              label: 'Material löschen',
              secondary: true,
              icon: Icons.delete_outline,
              onPressed: () async {
                if (await confirmDialog(
                  context,
                  'Material löschen?',
                  'Das private Bild und der bestätigte Stoff werden gelöscht. Bereits erzeugte Übungen bleiben im Lernverlauf erhalten.',
                )) {
                  await widget.state.api.delete('/materials/${d['id']}');
                  if (context.mounted) context.go('/app');
                }
              },
            ),
          ),
      ],
    );
  }
}
