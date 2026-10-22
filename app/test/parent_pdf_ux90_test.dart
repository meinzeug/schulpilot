import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parent_pdf_filters_ux88_test.dart' as pdf;
import 'parent_filters_ux88_test.dart' show choose;
import 'parent_messages_ux88_test.dart' as messages;

Finder rowChoice(String subject) {
  final panel = find
      .ancestor(
        of: find.textContaining('$subject · Note').first,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'Panel',
        ),
      )
      .first;
  return find.descendant(
    of: panel,
    matching: find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Übernahme',
    ),
  );
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scrolling = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  for (
    var i = 0;
    i < 30 && tester.state<ScrollableState>(scrolling).position.pixels > 1;
    i++
  ) {
    await tester.drag(scrolling, const Offset(0, 700));
    await tester.pumpAndSettle();
  }
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: scrolling,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> decision(
  WidgetTester tester,
  String subject,
  String option,
) async {
  await reveal(tester, find.textContaining('$subject · Note'));
  await messages.tap(tester, rowChoice(subject));
  await tester.pumpAndSettle();
  await messages.tap(tester, find.textContaining(option).last);
  await tester.pumpAndSettle();
}

Future<void> impact(WidgetTester tester, String prefix) async {
  await reveal(tester, find.textContaining(prefix));
  expect(find.textContaining(prefix), findsOneWidget);
}

void main() {
  testWidgets(
    'PK042 decision filter displays actual selected writes rather than hiding pending rows silently',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      await choose(
        tester,
        'Deine Übernahmeauswahl',
        'Übernahmen und Änderungen',
      );
      expect(find.text('Mathematik · Note 4'), findsOneWidget);
      expect(find.text('Biologie · Note 3'), findsNothing);
      await impact(tester, 'Übernahme der gesamten Vorschau: 1 neu');
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PK043 undo restores last explicit local grade choice without a network write',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      await decision(tester, 'Mathematik', 'Nicht übernehmen');
      await impact(tester, 'Übernahme der gesamten Vorschau: 0 neu');
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      if (find.text('Letzte Zuordnung zurücknehmen').evaluate().isEmpty) {
        await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      }
      await tap(tester, find.text('Letzte Zuordnung zurücknehmen'));
      await impact(tester, 'Übernahme der gesamten Vorschau: 1 neu');
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PK044 skipping only displayed PDF changes preserves hidden unresolved entries until explicit confirm',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      await choose(tester, 'Fach in der PDF', 'Mathematik');
      await tap(tester, find.text('Angezeigte Übernahmen auslassen'));
      expect(find.textContaining('1 angezeigte neue'), findsOneWidget);
      await messages.tap(tester, find.text('Diese Positionen auslassen'));
      await tester.pumpAndSettle();
      expect(f.requests, hasLength(1));
      await impact(tester, 'Übernahme der gesamten Vorschau: 0 neu');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('PDF-Filter zurücksetzen'));
      if (find.text('Letzte Zuordnung zurücknehmen').evaluate().isEmpty) {
        await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      }
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      if (find.text('Letzte Zuordnung zurücknehmen').evaluate().isEmpty) {
        await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      }
      await tap(tester, find.text('Letzte Zuordnung zurücknehmen'));
      await impact(tester, 'Übernahme der gesamten Vorschau: 1 neu');
    },
  );
  testWidgets(
    'PK045 same stored grade cannot be linked twice before submitting an invalid confirmation',
    (tester) async {
      final f = pdf.Fixture();
      final rows = f.data['items'] as List;
      rows[0]['status'] = 'possible_match';
      rows[0]['matches'] = [...rows[2]['matches']];
      await f.mount(tester);
      await decision(tester, 'Mathematik', 'Schon erfasst');
      await decision(tester, 'Biologie', 'Schon erfasst');
      await reveal(
        tester,
        find.textContaining('Eine vorhandene Note ist mehreren PDF-Positionen'),
      );
      expect(
        find.textContaining('Eine vorhandene Note ist mehreren PDF-Positionen'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNull,
      );
      expect(f.requests, hasLength(1));
      await tap(tester, find.text('Mehrfache Zuordnungen ansehen'));
      expect(
        find.textContaining('Mathematik · 1. Halbjahr · Position 1'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'PK046 current-grade reparse requires explicit action and a new idempotency key without confirmation',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      final first = f.requests.single.headers['idempotency-key'];
      await tap(tester, find.text('PDF mit aktuellem Stand neu prüfen'));
      expect(f.requests, hasLength(1));
      await messages.tap(tester, find.text('Neue Vorschau erstellen'));
      await tester.pumpAndSettle();
      expect(f.requests, hasLength(2));
      expect(f.requests.last.headers['idempotency-key'], isNot(first));
      expect(f.requests.where((r) => r.url.path.endsWith('/confirm')), isEmpty);
    },
  );
  testWidgets(
    'PK047 PDF subject overview makes its actual source counts a local filter',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Fächer dieser PDF im Überblick'));
      expect(
        find.text('1 gelesene Einträge · 1 Zuordnungen offen'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(ListTile, 'Biologie'));
      await tester.scrollUntilVisible(
        find.text('Biologie · Note 3'),
        140,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Biologie · Note 3'), findsOneWidget);
      expect(find.text('Mathematik · Note 4'), findsNothing);
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PK042 PK044 PDF whole-preview impact and actions fit 320 at 200 percent',
    (tester) async {
      final f = pdf.Fixture();
      await f.mount(tester, width: 320, scale: 2);
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      await choose(
        tester,
        'Deine Übernahmeauswahl',
        'Bewusst nicht übernehmen',
      );
      await impact(tester, 'Übernahme der gesamten Vorschau: 1 neu');
      await reveal(
        tester,
        find.textContaining('0 von 3 PDF-Einträgen angezeigt'),
      );
      expect(
        find.textContaining('0 von 3 PDF-Einträgen angezeigt'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
