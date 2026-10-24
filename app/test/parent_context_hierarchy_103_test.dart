import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/parent_child_navigation.dart';

import 'mobile_parent_child_navigation_test.dart' as navigation;
import 'parent_cards_ux88_test.dart' as plan;

Finder contextIcon103(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

final planModes103 = find.byKey(const ValueKey('parent-plan-modes'));

Future<void> inspectAreaChoices103(WidgetTester tester, Finder picker) async {
  await navigation.tap(tester, picker);
  for (final destination in ParentChildNavigation.destinations) {
    final option = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownMenuItem<String> && widget.value == destination.$1,
    );
    expect(option, findsOneWidget);
    expect(
      find.descendant(of: option, matching: find.text(destination.$2)),
      findsOneWidget,
    );
  }
  // Selecting the already active section closes the menu without navigation.
  await navigation.tap(tester, find.text('Lernplan').last);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in ['Nunito', 'Roboto']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('parent context uses one growing row at $width / $scale', (
        tester,
      ) async {
        final f = navigation.Fixture();
        await f.mount(tester, size: Size(width, 844), scale: scale);
        final context = find.byKey(
          const ValueKey('compact-parent-child-navigation'),
        );
        final row = find.byKey(const ValueKey('parent-child-context-row'));
        expect(context, findsOneWidget);
        expect(row, findsOneWidget);
        expect(tester.getSize(context).height, tester.getSize(row).height);
        final name = tester.widget<Text>(find.text(navigation.childName));
        expect(name.maxLines, isNull);
        expect(name.overflow, isNot(TextOverflow.ellipsis));
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text(navigation.description), findsNothing);
        expect(find.text('Anderes Kind'), findsNothing);
        for (final label in [
          'Zur Familie',
          'Aktualisieren',
          'Bereiche und Kindwechsel',
        ]) {
          final control = contextIcon103(label);
          expect(control, findsOneWidget);
          final size = tester.getSize(control);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        final before = f.requests.length;
        await navigation.tap(
          tester,
          contextIcon103('Bereiche und Kindwechsel'),
        );
        final picker = find.byType(DropdownButtonFormField<String>);
        expect(picker, findsOneWidget);
        expect(find.text(navigation.description), findsOneWidget);
        expect(find.text('Anderes Kind'), findsOneWidget);
        await inspectAreaChoices103(tester, picker);
        expect(f.requests.length, before);
        await navigation.tap(
          tester,
          contextIcon103('Bereiche und Kindwechsel'),
        );
        expect(picker, findsNothing);
        expect(find.text(navigation.description), findsNothing);
        expect(find.text('Anderes Kind'), findsNothing);
        expect(tester.getSize(context).height, tester.getSize(row).height);
        expect(f.requests.length, before);
        expect(f.refreshes, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('plan modes remain one scrollable row at $width / $scale', (
        tester,
      ) async {
        final f = plan.Fixture();
        await f.mount(tester, '/parent-plan/child', width: width, scale: scale);
        expect(planModes103, findsOneWidget);
        final tabs = tester.widget<ChildSectionTabs>(planModes103);
        expect(tabs.selected, 'topics');
        final scroll = find.descendant(
          of: planModes103,
          matching: find.byType(SingleChildScrollView),
        );
        expect(scroll, findsOneWidget);
        expect(
          tester.widget<SingleChildScrollView>(scroll).scrollDirection,
          Axis.horizontal,
        );
        final positions = <double>[];
        for (final label in [
          'Meine Themen',
          'Woche & Vorgaben',
          'KI-Lernweg',
        ]) {
          final button = find.descendant(
            of: planModes103,
            matching: find.widgetWithText(OutlinedButton, label),
          );
          expect(button, findsOneWidget);
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          positions.add(tester.getTopLeft(button).dy);
        }
        for (final y in positions) {
          expect(y, closeTo(positions.first, 0.01));
        }
        for (final (label, id, number) in [
          ('Woche & Vorgaben', 'week', 2),
          ('KI-Lernweg', 'ai', 0),
          ('Meine Themen', 'topics', 1),
        ]) {
          final button = find.descendant(
            of: planModes103,
            matching: find.widgetWithText(OutlinedButton, label),
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(tester.widget<ChildSectionTabs>(planModes103).selected, id);
          expect(
            f.state.collectionViews['parent-plan:child']?['section'],
            number,
          );
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(f.requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'areas remain reachable without permission to pick another child',
    (tester) async {
      final f = navigation.Fixture();
      f.state.familyId = null;
      await f.mount(tester, size: const Size(320, 844));
      expect(contextIcon103('Bereiche öffnen'), findsOneWidget);
      expect(contextIcon103('Bereiche und Kindwechsel'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await navigation.tap(tester, contextIcon103('Bereiche öffnen'));
      final picker = find.byType(DropdownButtonFormField<String>);
      expect(picker, findsOneWidget);
      await inspectAreaChoices103(tester, picker);
      expect(find.text('Anderes Kind'), findsNothing);
      expect(f.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final changed in ['account', 'family']) {
    testWidgets('an old More callback cannot open a new $changed context', (
      tester,
    ) async {
      final f = navigation.Fixture();
      await f.mount(tester, size: const Size(390, 844));
      final oldMore = tester
          .widget<IconButton>(contextIcon103('Bereiche und Kindwechsel'))
          .onPressed!;
      if (changed == 'account') {
        f.state.user = {...f.state.user!};
      } else {
        f.state.familyId = 'new-family';
      }
      f.refreshing.value = true;
      // The deliberate loading indicator keeps animating; inspect the next
      // frame rather than waiting for an idle animation tree.
      await tester.pump();
      final before = f.requests.length;
      oldMore();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Anderes Kind'), findsNothing);
      expect(f.requests.length, before);
      expect(f.refreshes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop keeps its direct plan mode chips', (tester) async {
    final f = plan.Fixture();
    await f.mount(tester, '/parent-plan/child', width: 1440);
    expect(planModes103, findsNothing);
    for (final label in ['Meine Themen', 'Woche & Vorgaben', 'KI-Lernweg']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Meine Themen'))
          .selected,
      isTrue,
    );
    expect(f.requests.every((request) => request.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
