import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/page_tools.dart';

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

String _groupId(WidgetTester tester, String? id) =>
    id ??
    tester.widgetList<PageToolsGroup>(find.byType(PageToolsGroup)).first.id;
Finder _body(String id) =>
    find.byKey(ValueKey('page-tools-body:$id'), skipOffstage: false);
Finder _fallback(WidgetTester tester, String id) {
  final group = tester
      .widgetList<PageToolsGroup>(find.byType(PageToolsGroup))
      .firstWhere((widget) => widget.id == id);
  return find.byWidgetPredicate(
    (widget) =>
        widget is ExpansionTile &&
        widget.title is Text &&
        (widget.title as Text).data == group.title,
  );
}

Future<void> openPageTools(WidgetTester tester, [String? groupId]) async {
  final id = _groupId(tester, groupId);
  if (!tester.widget<Offstage>(_body(id)).offstage) return;
  final buttons = find.byKey(const ValueKey('page-tools-button'));
  if (buttons.evaluate().isEmpty) {
    await _tap(tester, _fallback(tester, id));
  } else {
    await _tap(tester, buttons.first);
    await _tap(tester, find.byKey(ValueKey('page-tools-choice:$id')));
  }
  expect(tester.widget<Offstage>(_body(id)).offstage, isFalse);
}

Future<void> closePageTools(WidgetTester tester, [String? groupId]) async {
  final id = _groupId(tester, groupId);
  if (tester.widget<Offstage>(_body(id)).offstage) return;
  final close = find.byKey(ValueKey('page-tools-close:$id'));
  await _tap(tester, close.evaluate().isEmpty ? _fallback(tester, id) : close);
  expect(tester.widget<Offstage>(_body(id)).offstage, isTrue);
}

/// Keeps legacy component fixtures explicit while full pages use the new host.
Future<void> togglePageTools(WidgetTester tester, [String? groupId]) async {
  final legacy = find.byKey(const ValueKey('child-mobile-filter-toggle'));
  if (legacy.evaluate().isNotEmpty) {
    await _tap(tester, legacy);
    return;
  }
  final id = _groupId(tester, groupId);
  if (tester.widget<Offstage>(_body(id)).offstage) {
    await openPageTools(tester, id);
  } else {
    await closePageTools(tester, id);
  }
}
