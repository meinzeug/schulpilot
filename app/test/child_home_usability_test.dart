import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

Json _overview() =>
    jsonDecode(File('test/fixtures/child_home.json').readAsStringSync())
        as Json;

Future<GoRouter> _openHome(
  WidgetTester tester,
  Json data, {
  List<http.Request>? requests,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests?.add(request);
              return http.Response(
                jsonEncode(request.method == 'GET' ? data : {'id': 'saved'}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'child-user',
          'display_name': 'Mika',
          'role': 'child',
          'child_id': data['child']['id'],
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftfotos-Ziel')),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Lernrunde-Ziel')),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftseite prüfen')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  addTearDown(router.dispose);
  return router;
}

void main() {
  testWidgets(
    'Child sees one clear learning action; saved content opens on demand',
    (tester) async {
      final requests = <http.Request>[];
      final data = _overview();
      await _openHome(tester, data, requests: requests);

      expect(find.byType(FocusCard), findsOneWidget);
      expect(find.text('Jetzt lernen'), findsOneWidget);
      expect(find.text('Nach der Schule starten'), findsNothing);
      expect(find.text('Synthetischer Hefteintrag · Brüche'), findsNothing);
      expect(find.text('Was steht heute an?'), findsNothing);
      expect(tester.getRect(find.text('Jetzt lernen')).bottom, lessThan(650));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Meine Heftseiten'));
      await tester.tap(find.text('Meine Heftseiten'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetischer Hefteintrag · Brüche'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Empty plan guides directly to photos instead of a learning error',
    (tester) async {
      final data = _overview();
      data['plan']['today'] = [];
      data['materials'] = [];
      data['units'] = [];
      final requests = <http.Request>[];
      await _openHome(tester, data, requests: requests);

      expect(find.text('Jetzt lernen'), findsNothing);
      await tester.tap(find.text('Nach der Schule starten'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.text('Heftfotos-Ziel')))
            .pathParameters['id'],
        data['child']['id'],
      );
      expect(find.text('Heftfotos-Ziel'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Independent child help does not require typing a message', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    await _openHome(tester, data, requests: requests);
    await tester.tap(find.text('Ich brauche Hilfe'));
    await tester.pumpAndSettle();
    expect(find.text('Deine Frage (freiwillig)'), findsOneWidget);
    await tester.tap(find.text('Um Hilfe bitten'));
    await tester.pumpAndSettle();

    final sent = requests.where((r) => r.method == 'POST').toList();
    expect(sent, hasLength(1));
    expect(
      sent.single.url.path,
      '/api/children/${data['child']['id']}/messages',
    );
    expect(jsonDecode(sent.single.body), {
      'kind': 'help',
      'body': 'Ich brauche Unterstützung beim Lernen.',
    });
    expect(find.text('Hilfewunsch gesendet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A pending review resumes without creating another AI request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    data['plan']['today'] = [];
    data['units'][0]['status'] = 'completed';
    data['units'][0]['coaching'] = {'status': 'pending'};
    await _openHome(tester, data, requests: requests);
    await tester.tap(find.text('Rückblick ansehen'));
    await tester.pumpAndSettle();
    expect(
      GoRouterState.of(tester.element(find.text('Lernrunde-Ziel')))
          .pathParameters['id'],
      data['units'][0]['id'],
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Child AI report exposes uncertainty and keeps details collapsed',
    (tester) async {
      final state = AppState()
        ..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachingPanel(
                state: state,
                unit: {
                  'id': 'unit',
                  'subject': 'Mathematik',
                  'topic': 'Brüche',
                  'questions': [
                    {'id': 'q1', 'prompt': 'Was ist ein Nenner?'},
                  ],
                  'coaching': {
                    'status': 'ready',
                    'decision': 'repair',
                    'next_unit_id': 'next',
                    'provider': 'openrouter',
                    'report': {
                      'summary': 'Alle gespeicherten Einzelheiten.',
                      'practice_focus': ['Den Nenner noch einmal erklären.'],
                      'explanation': 'Der Nenner steht unter dem Bruchstrich.',
                      'question_reviews': [
                        {
                          'question_id': 'q1',
                          'assessment_kind': 'ai_opinion',
                          'feedback': 'Eine Umschreibung ist denkbar.',
                        },
                      ],
                    },
                  },
                },
                refresh: () async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Weiter üben'), findsOneWidget);
      expect(find.text('Eine Antwort ist noch unklar.'), findsOneWidget);
      expect(find.text('Alle gespeicherten Einzelheiten.'), findsNothing);
      expect(
        find.text('Der Nenner steht unter dem Bruchstrich.'),
        findsNothing,
      );
      await tester.tap(find.text('Erklärung ansehen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Der Nenner steht unter dem Bruchstrich.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
