import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pressPageTool104(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

/// Follows the actual named menu entry; never opens a hidden body by state access.
Future<void> openPageTool104(WidgetTester tester, String id) async {
  if (find.byKey(ValueKey('page-tools-open:$id')).evaluate().isNotEmpty) {
    return;
  }
  final button = find.byKey(const ValueKey('page-tools-button')).first;
  await pressPageTool104(tester, button);
  expect(find.byKey(const ValueKey('page-tools-menu')), findsOneWidget);
  final choice = find.byKey(ValueKey('page-tools-choice:$id'));
  expect(choice, findsOneWidget);
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  expect(tester.getSize(choice).height, greaterThanOrEqualTo(48));
  await pressPageTool104(tester, choice);
  expect(find.byKey(const ValueKey('page-tools-menu')), findsNothing);
  expect(find.byKey(ValueKey('page-tools-open:$id')), findsOneWidget);
}

Future<void> closePageTool104(WidgetTester tester, String id) =>
    pressPageTool104(tester, find.byKey(ValueKey('page-tools-close:$id')));
