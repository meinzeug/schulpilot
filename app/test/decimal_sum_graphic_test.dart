import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/decimal_sum_graphic.dart';
import 'package:schulpilot/ui.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('decimal columns at $width and text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: DecimalSumGraphic({
                    'numbers': [125, 23, 2],
                  }),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('Die Kommas stehen untereinander. Beginne ganz rechts.'),
          findsOneWidget,
        );
        for (final label in [
          'Hundertstel: 5 + 3 = 8',
          'Zehntel: 2 + 2 = 4',
          'Einer: 1 + 0 = 1',
        ]) {
          await tester.ensureVisible(find.text('Nächste Stelle'));
          await tester.tap(find.text('Nächste Stelle'));
          await tester.pumpAndSettle();
          expect(find.text(label), findsOneWidget);
        }
        expect(find.bySemanticsLabel(RegExp('Ergebnis: 1,48')), findsOneWidget);
        await tester.tap(find.byTooltip('Vorherige Stelle'));
        await tester.pumpAndSettle();
        expect(find.text('Zehntel: 2 + 2 = 4'), findsOneWidget);
        await tester.tap(find.byTooltip('Zurücksetzen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Beginne ganz rechts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
