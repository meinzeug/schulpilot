import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/heart_pump_graphic.dart';

void main() {
  testWidgets('heart model exposes two child-controlled, accessible steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HeartPumpGraphic({
              'title': 'Herz',
              'labels': ['Herz', 'Blut', 'Körper'],
              'source_excerpt': 'Das Herz pumpt Blut durch den Körper.',
            }),
          ),
        ),
      ),
    );
    expect(find.text('Das Herz pumpt Blut.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Vereinfachtes Schema: Das Herz pumpt Blut.'),
      findsOneWidget,
    );
    await tester.tap(find.text('2 · Körper'));
    await tester.pumpAndSettle();
    expect(
      find.text('Das Blut wird durch den Körper gepumpt.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Vereinfachtes Schema: Das Blut wird durch den Körper gepumpt.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
