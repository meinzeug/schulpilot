import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

void main() {
  testWidgets(
    'The introduction comes before exercises and its saved acknowledgement survives reopening',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var seen = false;
        var acknowledgements = 0;
        final api = Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/introduction')) {
              expect(request.method, 'POST');
              seen = true;
              acknowledgements++;
            } else {
              expect(request.method, 'GET');
            }
            return http.Response(
              jsonEncode({
                'id': 'unit',
                'subject': 'Englisch',
                'topic': 'Tiere',
                'status': 'active',
                'synthetic': true,
                'provider': 'synthetic',
                'model': 'fixed',
                'introduction_seen': seen,
                'explanation': 'Cat heißt Katze. Künstliche Erklärung.',
                'questions': [
                  {
                    'id': 'q1',
                    'type': 'choice',
                    'prompt': 'Was bedeutet cat?',
                    'options': ['Katze', 'Hund'],
                    'attempts': [],
                    'hints_used': 0,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final state = AppState(api: api)
          ..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};
        GoRouter router() => GoRouter(
          initialLocation: '/unit/unit',
          routes: [
            GoRoute(
              path: '/unit/:id',
              builder: (_, _) => UnitScreen(state, unitId: 'unit'),
            ),
          ],
        );
        final first = router();
        await tester.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: first),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('1. Verstehen, jetzt'), findsOneWidget);
        expect(find.text('Was bedeutet cat?'), findsNothing);
        final next = find.text('Weiter zu den Übungen');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('Was bedeutet cat?'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        first.dispose();
        final reopened = router();
        await tester.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: reopened),
        );
        await tester.pumpAndSettle();
        expect(find.text('Was bedeutet cat?'), findsOneWidget);
        expect(find.text('Weiter zu den Übungen'), findsNothing);
        expect(acknowledgements, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        reopened.dispose();
      } finally {
        semantics.dispose();
      }
    },
  );
}
