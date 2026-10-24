import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/page_tools.dart';

import 'page_tools_104_test_helpers.dart';

/// Follow the actual header group, retaining the legacy standalone tile path.
String parentToolTitle104(String title) =>
    title == 'PDF-Einträge gezielt prüfen'
    ? 'PDF-Vorschau suchen & filtern'
    : title;

PageToolsGroup? parentTool104(WidgetTester tester, String title) {
  final groups = tester
      .widgetList<PageToolsGroup>(
        find.byType(PageToolsGroup, skipOffstage: false),
      )
      .where((group) => group.title == parentToolTitle104(title));
  return groups.isEmpty ? null : groups.first;
}

bool hasParentDetails104(WidgetTester tester, String title) =>
    parentTool104(tester, title) != null ||
    find.text(title).evaluate().isNotEmpty;

Future<void> openParentDetails103(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  final group = parentTool104(tester, title);
  if (group != null &&
      find.byKey(const ValueKey('page-tools-button')).evaluate().isNotEmpty) {
    if (find
        .byKey(ValueKey('page-tools-open:${group.id}'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await openPageTool104(tester, group.id);
    return;
  }
  final label = find.text(parentToolTitle104(title)).first;
  final tile = find
      .ancestor(of: label, matching: find.byType(ExpansionTile))
      .first;
  final focus = find.descendant(
    of: tile,
    matching: find.byType(ExcludeFocus, skipOffstage: false),
    skipOffstage: false,
  );
  if (focus.evaluate().isNotEmpty &&
      !tester.widget<ExcludeFocus>(focus.first).excluding) {
    return;
  }
  final content = group == null
      ? null
      : find.byKey(ValueKey('page-tools-body:${group.id}'));
  if (content != null &&
      content.evaluate().isNotEmpty &&
      !tester.widget<Offstage>(content).offstage) {
    return;
  }
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Future<void> toggleParentDetails104(WidgetTester tester, String title) async {
  await tester.pumpAndSettle();
  final group = parentTool104(tester, title);
  if (group != null) {
    final fallback = find.byKey(ValueKey('page-tools-fallback:${group.id}'));
    if (fallback.evaluate().isNotEmpty) {
      final label = find
          .descendant(of: fallback, matching: find.text(group.title))
          .first;
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      expect(label.hitTestable(), findsOneWidget);
      await tester.tap(label);
      await tester.pumpAndSettle();
      return;
    }
    final close = find.byKey(ValueKey('page-tools-close:${group.id}'));
    if (close.evaluate().isNotEmpty) {
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      return;
    }
    await openParentDetails103(tester, title);
    return;
  }
  final label = find.text(title).first;
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
