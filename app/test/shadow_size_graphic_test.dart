import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/shadow_size_graphic.dart';
import 'package:schulpilot/ui.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'shadow comparison is touch and screen-reader usable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ShadowSizeGraphic(const {
                  'title': 'Licht und Schatten',
                  'labels': ['Lampe', 'Gegenstand', 'Wand', 'Schatten'],
                }),
              ),
            ),
          ),
        );
        expect(find.textContaining('Schatten ist kleiner.'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Schatten ist kleiner')),
          findsWidgets,
        );
        await tester.tap(find.text('Näher dran'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Schatten ist größer.'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Schatten ist größer')),
          findsWidgets,
        );
        await tester.tap(find.text('Weiter weg'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Schatten ist kleiner.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
