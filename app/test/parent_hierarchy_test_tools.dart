import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
