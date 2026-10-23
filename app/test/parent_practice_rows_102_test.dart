import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/ui.dart';

const evidence = {
  'practiced_tasks': 10,
  'independent_tasks': 4,
  'assisted_tasks': 3,
  'needs_practice_tasks': 2,
  'uncertain_tasks': 0,
  'reflection_tasks': 1,
  'attempts': 14,
  'practiced_rounds': 3,
  'completed_rounds': 2,
  'ongoing_rounds': 1,
};

Future<void> mountSummary(
  WidgetTester tester,
  List<String> selections, {
  required double width,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ParentPracticeSummary(
            evidence,
            onCategorySelected: selections.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder rowFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  for (final configuration in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets(
      '102 mobile evidence rows keep counts and whole-row actions at $configuration',
      (tester) async {
        final selections = <String>[];
        await mountSummary(
          tester,
          selections,
          width: configuration.$1,
          scale: configuration.$2,
        );
        expect(find.text('Passende Aufgaben ansehen'), findsNothing);
        expect(find.byTooltip('Passende Aufgaben ansehen'), findsNWidgets(4));
        expect(find.text('0 Bewertung offen'), findsOneWidget);
        expect(find.text('Ohne Richtig/Falsch-Bewertung'), findsOneWidget);
        for (final item in [
          ('4 alleine gelöst', 'independent'),
          ('3 mit Hilfe gelöst', 'assisted'),
          ('2 weiter üben', 'needs_practice'),
          ('1 eigener Beitrag', 'reflection'),
        ]) {
          final row = rowFor(item.$1);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(row);
          expect(bounds.height, greaterThanOrEqualTo(48));
          if (configuration.$2 == 1) {
            expect(bounds.height, lessThan(112));
          }
          // Activate the outer edge, rather than only the count or title text.
          await tester.tapAt(Offset(bounds.right - 8, bounds.center.dy));
          await tester.pumpAndSettle();
          expect(selections.last, item.$2);
        }
        final disabled = rowFor('0 Bewertung offen');
        await tester.ensureVisible(disabled);
        await tester.pumpAndSettle();
        expect(tester.widget<InkWell>(disabled).onTap, isNull);
        expect(tester.widget<InkWell>(disabled).canRequestFocus, isFalse);
        expect(selections, [
          'independent',
          'assisted',
          'needs_practice',
          'reflection',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('102 desktop evidence retains its existing action cards', (
    tester,
  ) async {
    await mountSummary(tester, <String>[], width: 1440);
    expect(find.byType(ActionPanel), findsNWidgets(5));
    expect(find.text('Passende Aufgaben ansehen'), findsNWidgets(5));
    expect(find.text('4 alleine gelöst'), findsOneWidget);
    expect(find.text('0 Bewertung offen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
