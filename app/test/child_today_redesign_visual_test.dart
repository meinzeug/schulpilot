import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/ui.dart';

// Local synthetic rendering evidence; no OCR, provider or physical-device test.
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('render Today tools using app fonts in $brightness', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final font in ['Nunito', 'SpaceGrotesk']) {
          await (FontLoader(
            font,
          )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(496, 900);
      await tester.binding.setSurfaceSize(const Size(496, 900));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: boundaryKey,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: context.palette.cream,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: ChildTodayTools(
                        learningTime: ChildTodayProgress(
                          activeMinutes: 2.3,
                          goalMinutes: 20,
                          goalRequired: true,
                          goalMet: false,
                          completed: 1,
                          description: 'Künstlicher gespeicherter Zeitstand: 2,3 von 20 Minuten.',
                          onOpen: () {},
                        ),
                        pageSummary: '10 gespeicherte Seiten',
                        onPlan: () {},
                        onMessages: () {},
                        onHelp: () {},
                        onNotebooks: () {},
                        onInfo: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../artifacts/today-redesign/tools-${brightness.name}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
