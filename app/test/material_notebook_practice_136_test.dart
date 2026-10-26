import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

import 'child_sources_input_ux87_test.dart' as sources;

Future<(AppState, List<http.Request>, GoRouter)> open(
  WidgetTester tester, {
  bool supported = true,
  String role = 'child',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(request.method, 'POST');
              expect(request.url.path, '/api/children/child/units');
              return http.Response(
                jsonEncode({'id': 'new-job', 'status': 'queued'}),
                202,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..familyId = 'family'
        ..user = {
          'id': 'test-actor',
          'role': role,
          'child_id': 'child',
          'families': [
            {'id': 'family', 'permission': 'owner'},
          ],
        };
  final data = sources.page('source-one', saved: true)
    ..addAll({
      'revision': 7,
      'purpose': 'notebook',
      'synthetic': false,
      'has_image': false,
      'subject_id': '11111111111111111111111111111111',
      'supports_notebook_practice': supported,
      'fixed_example': false,
      'fixture_id': null,
    });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: MaterialReview(
              state,
              data,
              onRefresh: () {},
              simpleChild: true,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, _) =>
            const Scaffold(body: Text('Gespeicherte Vorbereitung')),
      ),
      GoRoute(
        path: '/library/:child',
        builder: (_, _) => const Scaffold(body: Text('Hefte auswählen')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router, theme: appTheme()),
  );
  await tester.pumpAndSettle();
  return (state, requests, router);
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['child', 'parent']) {
    testWidgets(
      'Material action selects only its current revision and opens durable preparation: $role',
      (tester) async {
        final (_, requests, _) = await open(tester, role: role);
        await tap(
          tester,
          role == 'child'
              ? 'Jetzt lernen'
              : 'Lerneinheit für das Kind vorbereiten',
        );
        expect(find.text('1 Heftseite ausgewählt'), findsOneWidget);
        expect(requests, isEmpty);
        await tap(tester, 'Runde vorbereiten');
        expect(requests.length, 1);
        expect(jsonDecode(requests.single.body), {
          'material_id': 'source-one',
          'notebook_sources': [
            {'id': 'source-one', 'revision': 7},
          ],
          'question_count': 2,
        });
        expect(requests.single.headers['X-Schulpilot-Account'], 'test-actor');
        expect(requests.single.headers['Idempotency-Key'], isNotEmpty);
        expect(find.text('Gespeicherte Vorbereitung'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cancel and account change cannot create an implicit whole-day request',
    (tester) async {
      final (state, requests, _) = await open(tester);
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Zurück');
      expect(requests, isEmpty);
      await tap(tester, 'Jetzt lernen');
      state.user = {
        'id': 'different-child',
        'role': 'child',
        'child_id': 'other',
      };
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Runde vorbereiten'), findsNothing);
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Older backend without explicit selection metadata leads to notebooks without AI',
    (tester) async {
      final (_, requests, _) = await open(tester, supported: false);
      await tap(tester, 'Jetzt lernen');
      expect(find.text('Hefte auswählen'), findsOneWidget);
      expect(requests, isEmpty);
    },
  );
}
