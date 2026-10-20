import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/science_graphic.dart';
import 'package:schulpilot/ui.dart';

import 'render_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFormulaFonts);
  final cases =
      (jsonDecode(
                File('../testdata/science_graphics_v1.json').readAsStringSync(),
              )['cases']
              as List)
          .cast<Map<String, dynamic>>();
  test('Plot labels remove relative zero noise without erasing small real measurements', () {
    expect(ScienceGraphic.tickLabel(-8e-15, 12), '0');
    expect(ScienceGraphic.tickLabel(1e-15, 4e-15), '1e-15');
    expect(ScienceGraphic.number(0.123456789), '0,123456789');
    final branch = ScienceGraphic(
      Map<String, dynamic>.from(
        cases.firstWhere(
          (c) => c['id'] == 'PROCESS02',
        )['question']['presentation']['blocks'][0],
      ),
    );
    expect(
      branch.connectionsDescription,
      'Prüfung führt zu Fall A; Prüfung führt zu Fall B',
    );
  });
  for (final width in [320.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final sample in cases) {
        testWidgets('${sample['id']} real task/help model $width at $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final presentation = Map<String, dynamic>.from(
            sample['question']['presentation'],
          );
          Widget page(Set<String> stages) => MaterialApp(
            theme: appTheme().copyWith(
              textTheme: appTheme().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: RepaintBoundary(
                      key: const ValueKey('graphic'),
                      child: SubjectPresentation(presentation, stages: stages),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(page({'given'}));
          await tester.pumpAndSettle();
          expect(find.byType(ScienceGraphic), findsNothing);
          await tester.pumpWidget(page({'given', 'hint1', 'solution'}));
          await tester.pumpAndSettle();
          expect(find.byType(ScienceGraphic), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (width == 320 && scale == 1) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('graphic')),
              );
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '../artifacts/science-graphics/${sample['id']}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
