import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_workspace_density_test.dart' as f;

// Synthetic renderer evidence. Root verifies the deployed browser separately.
void main() {
  for (final page in [
    'learn',
    'homework',
    'vocabulary',
    'library',
    'settings',
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('render compact $page in $brightness', (tester) async {
        final key = GlobalKey();
        await f.mount(
          tester,
          page,
          const Size(390, 844),
          1,
          brightness: brightness,
          boundary: key,
        );
        await tester.runAsync(() async {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final box =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await box.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/ux91/mobile-$page-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }, skip: kIsWeb);
    }
  }
}
