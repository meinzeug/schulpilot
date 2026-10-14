import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/unit_screen.dart';
import 'package:schulpilot/ui.dart';

void main() {
  for (final provider in ['synthetic', 'openrouter']) {
    testWidgets('Synthetic content truthfully discloses provider $provider', (
      tester,
    ) async {
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'id': 'unit',
              'subject': 'Mathematik',
              'topic': 'Brüche',
              'status': 'active',
              'synthetic': true,
              'provider': provider,
              'model': 'isolated-test-model',
              'explanation': 'Synthetische Testerklärung.',
              'questions': [
                {
                  'id': 'q1',
                  'type': 'choice',
                  'prompt': 'Wie heißt die untere Zahl?',
                  'options': ['Nenner', 'Zähler'],
                  'attempts': [],
                  'hints_used': 0,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final state = AppState(api: api)
        ..user = {'id': 'test-child', 'role': 'child', 'child_id': 'child'};
      final router = GoRouter(
        initialLocation: '/unit/unit',
        routes: [
          GoRoute(
            path: '/unit/:id',
            builder: (_, _) => UnitScreen(state, unitId: 'unit'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      if (provider == 'synthetic') {
        expect(
          find.textContaining('Keine externe KI beteiligt'),
          findsOneWidget,
        );
        expect(
          find.textContaining('tatsächlich mit KI erstellt'),
          findsNothing,
        );
      } else {
        expect(
          find.textContaining('tatsächlich mit KI erstellt'),
          findsOneWidget,
        );
        expect(find.textContaining('Keine externe KI beteiligt'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
  }
}
