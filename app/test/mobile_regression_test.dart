import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

http.Response _json(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AppState _childState(MockClient client) =>
    AppState(
        api: Api(base: 'https://example.invalid/api', client: client),
      )
      ..user = {
        'id': 'artificial-child-account',
        'role': 'child',
        'child_id': 'child',
        'display_name': 'Testkind',
        'real_data_enabled': true,
        'synthetic': false,
      };

void _viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Json _completedUnit(String coachStatus) => {
  'id': 'completed',
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'status': 'completed',
  'synthetic': false,
  'provider': 'openrouter',
  'model': 'artificial-test-model',
  'explanation': 'Ein künstlicher gespeicherter Unterrichtstext.',
  'round_kind': 'learning',
  'questions': [
    {
      'id': 'q1',
      'type': 'short',
      'prompt': 'Künstliche Aufgabe: Wie viel ist 1/4 + 1/4?',
      'attempts': [
        {'answer': '1/2', 'outcome': 'correct', 'assisted': false},
      ],
      'hints_used': 0,
    },
  ],
  'coaching': {
    'status': coachStatus,
    'decision': 'spaced_review',
    'reason': 'Für später ist eine Wiederholung geplant.',
    'provider': 'openrouter',
    'model': 'artificial-test-model',
    'next_unit_id': null,
    'next_review': '2026-10-15',
    'can_retry': false,
    'report': coachStatus == 'ready'
        ? {
            'summary':
                'Gespeicherter Rückblick nach wiederhergestellter Verbindung.',
            'strengths': <String>[],
            'practice_focus': <String>[],
            'explanation': 'Die beiden Viertel ergeben ein Halb.',
            'question_reviews': <Json>[],
          }
        : <String, dynamic>{},
  },
};

Json _day({
  String id = 'today',
  String date = '2026-10-14',
  bool readOnly = false,
  List<Json> pages = const [],
}) => {
  'id': id,
  'child_id': 'child',
  'date': date,
  'stage': 'collecting',
  'read_only': readOnly,
  'max_pages': 24,
  'confirmed_count': 0,
  'synthetic': false,
  'pages': pages,
  'units': <Json>[],
  'active_job': null,
  'last_error': null,
  'plan': {'groups': <Json>[], 'notices': <String>[], 'estimated_minutes': 0},
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('A successful coach poll recovers from a transient GET failure', (
    tester,
  ) async {
    _viewport(tester, 390);
    var reads = 0;
    final methods = <String>[];
    final state = _childState(
      MockClient((request) async {
        methods.add(request.method);
        expect(request.url.path, '/api/units/completed');
        reads++;
        if (reads == 2) {
          return _json({
            'detail': 'Vorübergehend nicht erreichbar.',
          }, status: 503);
        }
        return _json(_completedUnit(reads == 1 ? 'pending' : 'ready'));
      }),
    );
    final router = GoRouter(
      initialLocation: '/unit/completed',
      routes: [
        GoRoute(
          path: '/unit/:id',
          builder: (_, route) =>
              UnitScreen(state, unitId: route.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Vorübergehend nicht erreichbar.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final report = find.text('Mein Rückblick');
    await tester.ensureVisible(report);
    await tester.tap(report);
    await tester.pumpAndSettle();
    expect(
      find.text('Gespeicherter Rückblick nach wiederhergestellter Verbindung.'),
      findsOneWidget,
    );
    expect(find.text('Vorübergehend nicht erreichbar.'), findsNothing);
    expect(reads, 3);
    expect(methods, everyElement('GET'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets(
    'Unreadable collecting page keeps replace action usable at 320px',
    (tester) async {
      _viewport(tester, 320);
      final artificialPng = image.encodePng(image.Image(width: 2, height: 2));
      final page = <String, dynamic>{
        'id': 'unreadable',
        'page_number': 1,
        'subject': '',
        'topic': '',
        'status': 'unreadable',
        'confirmed': false,
        'synthetic': false,
        'fixture_id': null,
        'quality_warnings': <String>[],
      };
      final state = _childState(
        MockClient((request) async {
          expect(request.method, 'GET');
          if (request.url.path == '/api/children/child/school-day/today') {
            return _json({
              'day': _day(pages: [page]),
            });
          }
          if (request.url.path == '/api/materials/unreadable/image') {
            return http.Response.bytes(
              artificialPng,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          fail('Unexpected request: ${request.method} ${request.url.path}');
        }),
      );
      final router = GoRouter(
        initialLocation: '/after-school/child',
        routes: [
          GoRoute(
            path: '/after-school/:id',
            builder: (_, route) =>
                SchoolDayScreen(state, childId: route.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final replace = find.text('Ersetzen');
      expect(replace, findsOneWidget);
      await tester.ensureVisible(replace);
      await tester.pumpAndSettle();
      expect(replace.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets('Today navigation opens new photos outside the archived day', (
    tester,
  ) async {
    _viewport(tester, 390);
    final paths = <String>[];
    final state = _childState(
      MockClient((request) async {
        expect(request.method, 'GET');
        paths.add(request.url.path);
        switch (request.url.path) {
          case '/api/children/child/overview':
            final home = jsonDecode(
              File('test/fixtures/child_home.json').readAsStringSync(),
            ) as Json;
            home['child']['id'] = 'child';
            home['plan']['today'] = [];
            home['plan']['later'] = [];
            home['units'] = [];
            home['materials'] = [];
            return _json(home);
          case '/api/school-days/archive':
            return _json(
              _day(id: 'archive', date: '2026-10-13', readOnly: true),
            );
          case '/api/children/child/school-day/today':
            return _json({'day': _day()});
          case '/api/app-release':
            return _json({'available': false});
          case '/api/status':
            return _json({
              'real_data_enabled': true,
              'ai_available': true,
              'synthetic_demo_available': false,
            });
          default:
            fail('Unexpected request: ${request.method} ${request.url.path}');
        }
      }),
    );
    await tester.pumpWidget(SchulpilotApp(state));
    await tester.pumpAndSettle();
    final router =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter;
    router.go('/after-school/child?day=archive');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mehr zu diesem Tag'));
    await tester.tap(find.text('Mehr zu diesem Tag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-13'), findsOneWidget);
    expect(find.text('Erste Seite fotografieren'), findsNothing);

    await tester.tap(find.text('Heute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heutige Seiten scannen'));
    await tester.pumpAndSettle();
    final details = find.text('Mehr zu diesem Tag');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-14'), findsOneWidget);
    expect(find.textContaining('2026-10-13'), findsNothing);
    expect(find.text('Erste Seite fotografieren'), findsOneWidget);
    expect(paths, contains('/api/children/child/school-day/today'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
