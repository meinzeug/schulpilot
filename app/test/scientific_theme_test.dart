import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/science_graphic.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

import 'render_fonts.dart';

class _Pixels {
  final int width, height;
  final Uint8List bytes;
  const _Pixels(this.width, this.height, this.bytes);
  Color at(int x, int y) {
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }

  int count(Color color, [Rect? region]) {
    final area =
        region ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    var result = 0;
    for (
      var y = area.top.ceil().clamp(0, height).toInt();
      y < area.bottom.floor().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.ceil().clamp(0, width).toInt();
        x < area.right.floor().clamp(0, width);
        x++
      ) {
        if (at(x, y) == color) result++;
      }
    }
    return result;
  }

  int readableOn(Color background, [Rect? region]) {
    final area =
        region ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    var result = 0;
    for (
      var y = area.top.ceil().clamp(0, height).toInt();
      y < area.bottom.floor().clamp(0, height);
      y++
    ) {
      for (
        var x = area.left.ceil().clamp(0, width).toInt();
        x < area.right.floor().clamp(0, width);
        x++
      ) {
        final pixel = at(x, y);
        if (pixel.a == 1 && _contrast(pixel, background) >= 4.5) result++;
      }
    }
    return result;
  }
}

Future<_Pixels> _pixels(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = _Pixels(
    image.width,
    image.height,
    Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ),
  );
  image.dispose();
  return result;
}

Future<_Pixels> _paint(
  CustomPainter painter,
  Color background, {
  Size size = const Size(320, 250),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(background, BlendMode.src);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  return _pixels(image);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  Brightness brightness,
) async {
  final theme = appTheme(brightness: brightness);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return ((first > second ? first : second) + .05) /
      ((first < second ? first : second) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFormulaFonts);
  final science =
      (jsonDecode(
                File('../testdata/science_graphics_v1.json').readAsStringSync(),
              )['cases']
              as List)
          .cast<Map<String, dynamic>>();
  final subjects =
      (jsonDecode(
                File('../testdata/subject_cases_v1.json').readAsStringSync(),
              )['cases']
              as List)
          .cast<Map<String, dynamic>>();
  Map<String, dynamic> block(List<Map<String, dynamic>> cases, String id) =>
      Map<String, dynamic>.from(
        cases.firstWhere(
          (value) => value['id'] == id,
        )['question']['presentation']['blocks'][0],
      );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final palette = AppPalette(isDark: brightness == Brightness.dark);
    for (final sample in [
      ('MOLE01', const Rect.fromLTWH(146, 95, 28, 30)),
      ('CELL01', const Rect.fromLTWH(96, 86, 32, 28)),
      ('PROCESS01', const Rect.fromLTWH(146, 10, 28, 28)),
    ]) {
      testWidgets(
        '${sample.$1} labels remain visible on scientific shapes in ${brightness.name}',
        (tester) async {
          final data = block(science, sample.$1),
              before = jsonEncode(block(science, sample.$1));
          await _mount(tester, ScienceGraphic(data), brightness);
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.byWidgetPredicate(
                          (widget) =>
                              widget is CustomPaint &&
                              widget.painter is SciencePainter,
                        ),
                      )
                      .painter!
                  as SciencePainter;
          final pixels = await tester.runAsync(
            () => _paint(painter, palette.surfaceLow),
          );
          final fill = sample.$1 == 'CELL01'
              ? palette.mint
              : palette.panelSurface;
          expect(
            pixels!.readableOn(fill, sample.$2),
            greaterThan(2),
            reason: 'The real font must paint a readable atom/number label.',
          );
          expect(pixels.count(fill, sample.$2), greaterThan(20));
          expect(_contrast(palette.ink, fill), greaterThanOrEqualTo(4.5));
          expect(
            jsonEncode(data),
            before,
            reason:
                'Theme switching cannot rewrite scientific values or labels.',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    for (final sample in [
      ('LER02', const Rect.fromLTWH(145, 95, 30, 30), true),
      ('KUN02', const Rect.fromLTWH(20, 20, 32, 30), false),
    ]) {
      testWidgets(
        '${sample.$1} numbered diagram labels have paired theme surfaces in ${brightness.name}',
        (tester) async {
          final data = block(subjects, sample.$1),
              before = jsonEncode(block(subjects, sample.$1));
          await _mount(tester, SubjectGraphic(data), brightness);
          final painter = tester
              .widget<CustomPaint>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.painter is SubjectVectorPainter,
                ),
              )
              .painter!;
          final pixels = await tester.runAsync(
            () =>
                _paint(painter, palette.surfaceLow, size: const Size(320, 220)),
          );
          final fill = sample.$3 ? palette.panelSurface : palette.cyanSurface;
          expect(pixels!.readableOn(fill, sample.$2), greaterThan(2));
          expect(pixels.count(fill, sample.$2), greaterThan(20));
          expect(_contrast(palette.ink, fill), greaterThanOrEqualTo(4.5));
          expect(jsonEncode(data), before);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    for (final role in ['boundary', 'io', 'process']) {
      testWidgets(
        '$role flow node paints readable text and its paired surface in ${brightness.name}',
        (tester) async {
          await _mount(
            tester,
            RepaintBoundary(
              key: const ValueKey('flow'),
              child: FlowNode(text: 'Prüfe x > 2', role: role),
            ),
            brightness,
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('flow')),
          );
          final pixels = await tester.runAsync(
            () async => _pixels(await boundary.toImage()),
          );
          expect(pixels!.readableOn(palette.panelSurface), greaterThan(10));
          expect(pixels.count(palette.panelSurface), greaterThan(200));
          expect(
            _contrast(palette.ink, palette.panelSurface),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'Piano retains literal white and black keys in ${brightness.name}',
      (tester) async {
        final data = block(subjects, 'MUS02'),
            before = jsonEncode(block(subjects, 'MUS02'));
        await _mount(tester, SubjectGraphic(data), brightness);
        final painter = tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.painter is SubjectVectorPainter,
              ),
            )
            .painter!;
        final pixels = await tester.runAsync(
          () => _paint(painter, palette.surfaceLow, size: const Size(320, 220)),
        );
        expect(
          pixels!.at(20, 150),
          Colors.white,
          reason: 'White keys are lesson content, not a dark-theme surface.',
        );
        expect(
          pixels.at(40, 60),
          Colors.black,
          reason: 'Black keys must not become light UI ink.',
        );
        expect(jsonEncode(data), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('Scientific painters repaint when only the theme variant changes', () {
    const light = AppPalette(isDark: false), dark = AppPalette(isDark: true);
    final data = block(science, 'MOLE01');
    expect(
      SciencePainter(
        data,
        light.ink,
        14,
        'Roboto',
        palette: dark,
      ).shouldRepaint(
        SciencePainter(data, light.ink, 14, 'Roboto', palette: light),
      ),
      isTrue,
    );
    final subject = block(subjects, 'LER02');
    expect(
      SubjectVectorPainter(
        subject,
        light.ink,
        1,
        'Roboto',
        palette: dark,
      ).shouldRepaint(
        SubjectVectorPainter(subject, light.ink, 1, 'Roboto', palette: light),
      ),
      isTrue,
    );
    expect(
      PollinationPainter(
        0,
        palette: dark,
      ).shouldRepaint(PollinationPainter(0, palette: light)),
      isTrue,
    );
  });
}
