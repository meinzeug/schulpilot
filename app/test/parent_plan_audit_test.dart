import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/parent_homework_screen.dart';
import 'package:schulpilot/ui.dart';

import 'parent_insights_test.dart' as fixture;

void main() {
  testWidgets(
    'Parent can explicitly finish a topic and still find its history',
    (tester) async {
      var completed = false;
      final requests = <http.Request>[];
      final state = fixture.account(
        MockClient((r) async {
          requests.add(r);
          if (r.method == 'POST') {
            expect(r.url.path, endsWith('/assignments/assignment/complete'));
            expect(r.body, '{"revision":1}');
            completed = true;
            return fixture.response({});
          }
          if (r.url.path.endsWith('/parent-insights')) {
            return fixture.response(fixture.insight(ready: false));
          }
          final plan = fixture.plan();
          final topic = plan['topics'][0] as Map;
          topic['revision'] = completed ? 2 : 1;
          topic['done'] = completed;
          if (completed &&
              r.url.queryParameters['include_completed'] != 'true') {
            plan['topics'] = [];
          }
          return fixture.response(plan);
        }),
      );
      await fixture.open(tester, state, 'plan');
      await fixture.tap(tester, 'Meine Themen');
      await fixture.tap(tester, 'Als erledigt markieren');
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await fixture.tap(tester, 'Abbrechen');
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await fixture.tap(tester, 'Als erledigt markieren');
      await fixture.tap(tester, 'Bestätigen');
      expect(requests.where((r) => r.method == 'POST').length, 1);
      expect(find.text('Als erledigt markieren'), findsNothing);
      final status = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Auftragsstatus',
      );
      await tester.ensureVisible(status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      await fixture.tap(tester, 'Offene und erledigte Themen');
      expect(requests.last.url.queryParameters['include_completed'], 'true');
      expect(find.text('Als abgeschlossen markiert'), findsOneWidget);
      expect(find.text('Als erledigt markieren'), findsNothing);
    },
  );

  testWidgets(
    'Read-only parents can inspect topics without completion controls',
    (tester) async {
      final state = fixture.account(
        MockClient((r) async {
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/parent-insights')) {
            return fixture.response({
              ...fixture.insight(ready: false),
              'can_manage': false,
            });
          }
          return fixture.response({...fixture.plan(), 'can_manage': false});
        }),
      );
      await fixture.open(tester, state, 'plan');
      await fixture.tap(tester, 'Meine Themen');
      expect(find.text('Mathematik · Bruchaddition'), findsOneWidget);
      expect(find.text('Als erledigt markieren'), findsNothing);
      expect(find.text('KI-Runde vorbereiten'), findsNothing);
      expect(find.text('Ziel & Termin bearbeiten'), findsNothing);
    },
  );

  testWidgets(
    'Switching children clears the old homework identity immediately',
    (tester) async {
      final nextChild = Completer<http.Response>();
      final state = fixture.account(
        MockClient((r) async {
          if (r.url.path.contains('/children/second/')) return nextChild.future;
          return fixture.response({
            ...fixture.homework(),
            'child_name': 'Erstes Testkind',
          });
        }),
      );
      final router = GoRouter(
        initialLocation: '/homework/first',
        routes: [
          GoRoute(
            path: '/homework/:child',
            builder: (_, s) => ParentHomeworkScreen(
              state,
              childId: s.pathParameters['child']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Erstes Testkind'), findsWidgets);
      router.go('/homework/second');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Erstes Testkind'), findsNothing);
      expect(find.text('Fläche berechnen'), findsNothing);
      nextChild.complete(
        fixture.response({
          ...fixture.homework(),
          'child_name': 'Zweites Testkind',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Zweites Testkind'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
