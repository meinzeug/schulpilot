import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:schulpilot/preparation_card.dart';
import 'package:schulpilot/ui.dart';

void main() {
  testWidgets('A processing preparation remains a named actionable card', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: PreparationCard(
                childId: 'artificial-child',
                preparation: {
                  'status': 'processing',
                  'day_id': 'artificial-day',
                  'date': '2026-10-22',
                },
              ),
            ),
          ),
          GoRoute(
            path: '/after-school/:child',
            builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final node = tester.getSemantics(find.byType(ListTile));
      final data = node.getSemanticsData();
      expect(data.role, isNot(ui.SemanticsRole.loadingSpinner));
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(data.label, contains('Deine Fotos sind abgegeben.'));
      expect(data.label, contains('Vorbereitung ansehen'));
      tester.binding.performSemanticsAction(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: node.id,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ziel /after-school/artificial-child?day=artificial-day'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
    }
  });
}
