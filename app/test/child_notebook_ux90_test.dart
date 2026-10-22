import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/notebook_photo.dart';

import 'notebook_test.dart' as fixture;

Finder label(String value) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == value,
);
void main() {
  testWidgets(
    'CK022 grid photo and summary select pages without leaving selection mode',
    (tester) async {
      final (_, _, requests) = await fixture.open(tester);
      await fixture.tap(tester, find.text('Kacheln'));
      await fixture.tap(tester, find.text('Seiten auswählen'));
      await fixture.tap(tester, find.byType(NotebookPhoto).first);
      expect(find.text('1 Seite ausgewählt'), findsOneWidget);
      expect(find.text('Text & Lernen'), findsNothing);
      await fixture.tap(tester, find.text('Lernstoff 0').first);
      expect(find.text('1 Seite ausgewählt'), findsNothing);
      expect(find.text('Kacheln'), findsWidgets);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK023 album pager and management remain usable at 320px and double text',
    (tester) async {
      await fixture.open(tester, width: 320, textScale: 2, photos: false);
      expect(tester.takeException(), isNull);
      await fixture.tap(tester, find.byTooltip('Nächste Seite'));
      expect(find.text('2 von 47'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('CK024 old zoom callback cannot open an outgoing album photo', (
    tester,
  ) async {
    await fixture.open(tester);
    final old = tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Vergrößern'),
        )
        .onPressed!;
    await fixture.tap(tester, find.byTooltip('Nächste Seite'));
    old();
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('2 von 47'), findsWidgets);
    await fixture.tap(tester, find.text('Vergrößern'));
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
  testWidgets(
    'CK025 notebook search respects the real 120 character server limit',
    (tester) async {
      final (_, _, requests) = await fixture.open(tester, photos: false);
      await fixture.tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(label('In diesem Hefter suchen'), 'x' * 140);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(label('In diesem Hefter suchen'));
      expect(field.controller!.text.length, 120);
      final query = requests
          .where((r) => r.url.path.endsWith('/materials'))
          .last
          .url
          .queryParameters['q'];
      expect(query, 'x' * 120);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
