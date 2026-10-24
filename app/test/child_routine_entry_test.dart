import 'page_tools_test_helpers.dart' as page_tools;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/ui.dart';

Json childDay() {
  final data = jsonDecode(
    File('test/fixtures/child_home.json').readAsStringSync(),
  ) as Json;
  data['daily_capture'] = {'status': 'empty'};
  data['plan']['voluntary'] = <Json>[];
  data['plan']['can_continue_voluntarily'] = true;
  data['plan']['goal_required'] = true;
  data['plan']['daily_goal_met'] = false;
  data['plan']['daily_active_seconds'] = 120;
  data['plan']['daily_goal_minutes'] = 20;
  return data;
}

Json collection({String? scheduled, bool completed = false}) => {
  'date': '2026-10-14',
  'page': 1,
  'pages': 1,
  'page_size': 20,
  'total': 1,
  'subjects': [
    {'value': 'Mathematik', 'count': 1},
  ],
  'paused': false,
  'free_day': false,
  'items': [
    {
      'id': 'own-round',
      'kind': 'unit',
      'subject': 'Mathematik',
      'topic': 'Eigene Brüche',
      'status': completed ? 'completed' : 'not_started',
      'question_count': 4,
      'closed_questions': completed ? 4 : 0,
      'created': 1700000000,
      'scheduled_for': ?scheduled,
    },
  ],
};

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> mount(
  WidgetTester tester,
  Json data,
  List<http.Request> requests, {
  double width = 390,
  bool learning = false,
  bool parent = false,
  Json? listing,
  int startStatus = 200,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (request.method == 'POST') {
                expect(
                  request.url.path.endsWith('/start'),
                  true,
                  reason: 'No AI, confirmation or answer may run implicitly.',
                );
                return startStatus == 200
                    ? jsonResponse({
                        'id': request.url.path.split('/')[3],
                        'status': 'active',
                      })
                    : jsonResponse({
                        'detail': 'Dein Lernkontingent ist aufgebraucht.',
                      }, startStatus);
              }
              expect(request.method, 'GET');
              if (request.url.path.endsWith('/learning')) {
                return jsonResponse(listing ?? collection());
              }
              return jsonResponse(data);
            }),
          ),
        )
        ..user = parent
            ? {
                'id': 'own-parent',
                'role': 'parent',
                'families': [
                  {'id': 'own-family', 'permission': 'owner'},
                ],
              }
            : {
                'id': 'own-child',
                'role': 'child',
                'display_name': 'Mika',
                'child_id': data['child']['id'],
              };
  final router = GoRouter(
    initialLocation: learning ? '/learn/${data['child']['id']}' : '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/learn/:id',
        builder: (_, _) => CollectionScreen(
          state,
          childId: data['child']['id'],
          learning: true,
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Gespeicherte Runde')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Heutige Fotos')),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Seite prüfen')),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, _) =>
            const Scaffold(body: Text('Reservierte Vorbereitung')),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Heftsammlung')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void addResume(Json data) {
  data['units'] = [
    {
      'id': 'saved-resume',
      'kind': 'unit',
      'topic': 'Brüche fortsetzen',
      'subject': 'Mathematik',
      'status': 'paused',
      'question_count': 5,
      'closed_questions': 2,
    },
  ];
  data['plan']['voluntary'] = data['units'];
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Saved resume stays primary beside today photos and old source review at $width px',
      (tester) async {
        final data = childDay(), requests = <http.Request>[];
        addResume(data);
        data['pending_preparations'] = [
          {
            'day_id': 'older-day',
            'date': '2026-10-13',
            'status': 'needs_review',
          },
        ];
        await mount(tester, data, requests, width: width);
        final card = tester.widget<ChildTodayHero>(find.byType(ChildTodayHero));
        expect(card.eyebrow, 'Deine Lernstation');
        expect(card.title, 'Brüche fortsetzen');
        expect(
          find.textContaining('2 von 5 Aufgaben abgeschlossen'),
          findsOneWidget,
        );
        expect(find.text('Heutige Seiten scannen'), findsOneWidget);
        expect(
          tester.getRect(find.text('Heutige Seiten scannen')).bottom,
          lessThan(764),
          reason: 'Daily photos remain visible beside the primary saved round.',
        );
        final learn = find
            .ancestor(
              of: find.text('Weiterlernen'),
              matching: find.byType(FilledButton),
            )
            .first;
        final scan = find
            .ancestor(
              of: find.text('Heutige Seiten scannen'),
              matching: find.byType(InkWell),
            )
            .first;
        expect(learn.hitTestable(), findsOneWidget);
        expect(scan.hitTestable(), findsOneWidget);
        expect(tester.getSize(learn).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(scan).height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(learn).bottom,
          lessThan(tester.getRect(scan).top),
        );
        expect(
          tester.getRect(scan).bottom,
          lessThan(
            tester.getRect(find.byKey(const ValueKey('child-home-search'))).top,
          ),
        );
        expect(find.text('Heftseiten prüfen'), findsOneWidget);
        expect(find.text('Anderes Thema'), findsOneWidget);
        expect(find.text('Verstehen · Üben · Rückblick'), findsOneWidget);
        expect(requests.where((request) => request.method == 'POST'), isEmpty);
        await tap(tester, 'Weiterlernen');
        expect(find.text('Gespeicherte Runde'), findsOneWidget);
        expect(
          requests
              .where((request) => request.method == 'POST')
              .map((request) => request.url.path),
          ['/api/units/saved-resume/start'],
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Choosing another topic shows real rounds before search controls at $width px',
      (tester) async {
        final requests = <http.Request>[];
        await mount(tester, childDay(), requests, width: width);
        await tap(tester, 'Anderes Thema');
        expect(find.text('Eigene Brüche'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byKey(const ValueKey('page-tools-button')), findsOneWidget);
        expect(find.text('Suchen & filtern'), findsNothing);
        expect(requests.every((request) => request.method == 'GET'), true);
        await tap(tester, 'Eigene Brüche');
        expect(find.text('Gespeicherte Runde'), findsOneWidget);
        expect(find.text('Einheit starten'), findsNothing);
        expect(
          requests
              .where((request) => request.method == 'POST')
              .map((request) => request.url.path),
          ['/api/units/own-round/start'],
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Today photos remain one explicit secondary action during a saved round',
    (tester) async {
      final data = childDay(), requests = <http.Request>[];
      addResume(data);
      await mount(tester, data, requests, width: 320);
      await tap(tester, 'Heutige Seiten scannen');
      expect(find.text('Heutige Fotos'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Missing summary counts never invent a next question number', (
    tester,
  ) async {
    final data = childDay();
    addResume(data);
    data['units'][0].remove('question_count');
    data['units'][0].remove('closed_questions');
    await mount(tester, data, []);
    expect(
      tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).subtitle,
      'Mathematik',
    );
    expect(find.textContaining('Aufgaben abgeschlossen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'An orphaned page review stays reachable without hiding the saved round',
    (tester) async {
      final data = childDay(), requests = <http.Request>[];
      addResume(data);
      data['materials'][0]['confirmed'] = false;
      data['materials'][0]['status'] = 'extracted';
      await mount(tester, data, requests, width: 320);
      expect(
        tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).title,
        'Brüche fortsetzen',
      );
      await tap(tester, 'Heftseite prüfen');
      expect(find.text('Eigene Seite prüfen'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'The last saved feedback remains the next step after a completed round',
    (tester) async {
      final data = childDay(), requests = <http.Request>[];
      data['plan']['today'] = <Json>[];
      data['plan']['daily_goal_met'] = true;
      data['feedback_resume'] = {
        'id': 'finished-round',
        'kind': 'unit',
        'status': 'completed',
        'pending_feedback': true,
        'subject': 'Mathematik',
        'topic': 'Brüche',
        'question_count': 4,
        'closed_questions': 4,
      };
      await mount(tester, data, requests, width: 320);
      expect(
        tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).title,
        'Deine letzte Antwort',
      );
      expect(find.text('Freiwillig weiterlernen'), findsNothing);
      await tap(tester, 'Rückmeldung ansehen');
      expect(find.text('Gespeicherte Runde'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A running generation opens only its saved status and cannot reserve another one',
    (tester) async {
      final data = childDay(), requests = <http.Request>[];
      data['plan']['today'] = [
        {
          'id': 'own-source',
          'kind': 'material',
          'subject': 'Mathematik',
          'topic': 'Brüche',
        },
      ];
      data['learning_preparation'] = {'id': 'own-job', 'status': 'running'};
      await mount(tester, data, requests);
      expect(find.text('Deine Runde wird vorbereitet.'), findsOneWidget);
      expect(find.text('Weiterlernen'), findsNothing);
      await tap(tester, 'Vorbereitung ansehen');
      expect(find.text('Reservierte Vorbereitung'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A prepared unstarted round remains available while another round is being generated',
    (tester) async {
      final data = childDay(), requests = <http.Request>[];
      data['learning_preparation'] = {'id': 'own-job', 'status': 'queued'};
      await mount(tester, data, requests);
      expect(
        tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).title,
        'Brüche',
      );
      expect(find.text('Runde wird vorbereitet'), findsOneWidget);
      await tap(tester, 'Weiterlernen');
      expect(find.text('Gespeicherte Runde'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST').length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Child search is optional and collapsing it dismisses the keyboard without resetting real filters',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, childDay(), requests, learning: true, width: 320);
      await page_tools.openPageTools(tester, 'learning-tools');
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'eigene');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requests.last.url.queryParameters['q'], 'eigene');
      await page_tools.closePageTools(tester, 'learning-tools');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Filter zurücksetzen'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Future parent start dates remain unavailable rather than being treated as a time goal',
    (tester) async {
      final requests = <http.Request>[];
      await mount(
        tester,
        childDay(),
        requests,
        learning: true,
        listing: collection(scheduled: '2026-10-15'),
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A server quota failure stays visible without a hidden second start',
    (tester) async {
      final requests = <http.Request>[];
      await mount(
        tester,
        childDay(),
        requests,
        learning: true,
        startStatus: 429,
      );
      await tap(tester, 'Eigene Brüche');
      expect(
        find.text('Dein Lernkontingent ist aufgebraucht.'),
        findsOneWidget,
      );
      expect(find.text('Gespeicherte Runde'), findsNothing);
      expect(requests.where((request) => request.method == 'POST').length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Parent collection tools remain available through the shared header options',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, childDay(), requests, learning: true, parent: true);
      expect(find.byType(TextField), findsNothing);
      final before = requests.length;
      await page_tools.openPageTools(tester, 'learning-tools');
      expect(requests.length, before);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PagedCollection),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
        findsOneWidget,
      );
      expect(find.text('Suchen & filtern'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
