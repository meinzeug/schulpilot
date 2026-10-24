import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_section_ui.dart';

/// Follow the named tool entry before testing its existing functional controls.
Future<void> openParentDetails103(WidgetTester tester, String title) async {
  final label = find.text(title).first;
  final tile = find
      .ancestor(of: label, matching: find.byType(ExpansionTile))
      .first;
  final focus = find
      .descendant(
        of: tile,
        matching: find.byType(ExcludeFocus, skipOffstage: false),
        skipOffstage: false,
      )
      .first;
  if (!tester.widget<ExcludeFocus>(focus).excluding) {
    return;
  }
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pumpAndSettle();
}

/// Read the same selected mode across mobile tabs and desktop chips.
bool parentPlanModeSelected103(WidgetTester tester, String label) {
  final mobile = find.byKey(const ValueKey('parent-plan-modes'));
  if (mobile.evaluate().isNotEmpty) {
    final tabs = tester.widget<ChildSectionTabs>(mobile);
    final id = tabs.tabs.singleWhere((tab) => tab.label == label).id;
    return tabs.selected == id;
  }
  return tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
      .selected;
}

/// The section chooser is deliberately behind More on compact child contexts.
Future<void> openParentChildAreas103(WidgetTester tester) async {
  final picker = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Bereich öffnen',
  );
  if (picker.evaluate().isNotEmpty) return;
  final more = find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        (widget.tooltip == 'Bereiche und Kindwechsel' ||
            widget.tooltip == 'Bereiche öffnen'),
  );
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  await tester.tap(more);
  await tester.pumpAndSettle();
}
