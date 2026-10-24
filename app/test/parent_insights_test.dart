import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_homework_screen.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/ui.dart';

import 'parent_hierarchy_test_tools.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json insight({bool ready = true}) => {
  'child_name': 'Künstliches Testkind',
  'can_manage': true,
  'eligible': true,
  'settings': {'enabled': false, 'revision': 0},
  'stale': true,
  'plan_applies': true,
  'totals': {},
  'history': [],
  'topics': [topic()],
  'latest': ready
      ? {
          'id': 'review',
          'finished': 1792569000,
          'observations': {
            'topics': [topic()],
            'topic_count': 1,
            'selected_topic_count': 1,
          },
          'report': {
            'summary': 'Künstlicher gespeicherter Bericht. Ein neuer Schritt hilft beim Verstehen.',
            'findings': [
              {
                'topic_ref': 't',
                'need': 'support',
                'interpretation': 'Unterstützung war nötig.',
                'next_check': 'Eine neue Aufgabe alleine versuchen.',
              },
            ],
            'plan': [
              {
                'topic_ref': 't',
                'action': 'explain',
                'purpose': 'Die Bedeutung der Bruchteile klären.',
                'expected_result': 'Den nächsten Schritt erklären.',
              },
            ],
          },
        }
      : null,
};
Json topic() => {
  'ref': 't',
  'subject': 'Mathematik',
  'topic': 'Bruchaddition',
  'independent_tasks': 2,
  'assisted_tasks': 1,
  'needs_practice_tasks': 1,
  'uncertain_tasks': 1,
};
Json plan() => {
  'child': {
    'display_name': 'Künstliches Testkind',
    'preferences': {
      'daily_minutes': 20,
      'weekly_minutes': 100,
      'session_minutes': 10,
      'break_minutes': 5,
    },
  },
  'can_manage': true,
  'pagination': {'page': 1, 'pages': 1},
  'instructional_plans': [],
  'recent_round_topics': [],
  'plan': {'week': []},
  'topics': [
    {
      'id': 'assignment',
      'subject': 'Mathematik',
      'topic': 'Bruchaddition',
      'source_status': 'confirmed',
      'source_kind': 'parent_topic',
      'mandatory': true,
      'done': false,
      'recent_units': [],
    },
  ],
};
Json homework() => {
  'child_name': 'Künstliches Testkind',
  'total': 1,
  'next_cursor': null,
  'photos': [
    {
      'id': 'photo',
      'subject': 'Mathematik',
      'topic': 'Flächen',
      'created': 1792569000,
      'confirmed': true,
      'marked_done': 1,
      'task_count': 2,
      'tasks': [
        {'title': 'Fläche berechnen', 'marked': true},
        {'title': 'Rechenweg erklären', 'marked': false},
      ],
    },
  ],
};

AppState account(MockClient client) =>
    AppState(
        api: Api(base: 'https://example.invalid/api', client: client),
      )
      ..user = {
        'id': 'parent',
        'role': 'parent',
        'display_name': 'Künstlicher Elternzugang',
        'families': [],
      };
Future<GoRouter> open(
  WidgetTester tester,
  AppState state,
  String page, {
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: '/$page',
    routes: [
      GoRoute(
        path: '/insights',
        builder: (_, s) => PageFrame(
          state: state,
          title: 'Lernstand',
          child: ParentInsightsPanel(state, childId: 'child'),
        ),
      ),
      GoRoute(
        path: '/plan',
        builder: (_, s) => ParentPlanScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/homework',
        builder: (_, s) => ParentHomeworkScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, s) =>
            const Scaffold(body: Text('Gespeicherter Vorbereitungsstatus')),
      ),
      GoRoute(
        path: '/progress/:child',
        builder: (_, s) => Scaffold(
          body: Text(
            'Belege ${s.uri.queryParameters['fach']} ${s.uri.queryParameters['thema']}',
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  return router;
}

Future<void> tap(WidgetTester tester, String label) async {
  const management = {
    'Als erledigt markieren',
    'Ziel & Termin bearbeiten',
    'Als neues Ziel kopieren',
    'Auftrag entfernen',
  };
  if (management.contains(label) && find.text(label).evaluate().isEmpty) {
    await openParentDetails103(tester, 'Auftrag verwalten');
  }
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 1440.0]) {
      for (final page in ['insights', 'homework', 'plan']) {
        testWidgets('$page uses read-only views at $width in $brightness', (
          tester,
        ) async {
          final calls = <http.Request>[];
          final state = account(
            MockClient((r) async {
              calls.add(r);
              expect(r.method, 'GET');
              if (r.url.path.endsWith('/parent-insights')) {
                return response(insight());
              }
              if (r.url.path.endsWith('/learning-plan')) {
                return response(plan());
              }
              if (r.url.path.endsWith('/homework-review')) {
                return response(homework());
              }
              return response({'available': false});
            }),
          );
          await open(
            tester,
            state,
            page,
            width: width,
            scale: width == 320 ? 2 : 1,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          expect(calls.where((r) => r.method != 'GET'), isEmpty);
          if (page == 'insights') {
            expect(find.text('Hier lohnt ein genauer Blick'), findsOneWidget);
            expect(
              find.textContaining('Es gibt einen neueren Lernstand.'),
              findsOneWidget,
            );
          }
          if (page == 'homework') {
            expect(find.text('1 von 2 abgehakt'), findsOneWidget);
          }
        });
      }
    }
  }

  testWidgets(
    'Explicit review and daily grant use separate requests, reload only GET',
    (tester) async {
      final calls = <http.Request>[];
      final state = account(
        MockClient((r) async {
          calls.add(r);
          if (r.method == 'PUT') {
            expect(jsonDecode(r.body), {'revision': 0, 'enabled': true});
            return response({});
          }
          if (r.method == 'POST') {
            expect(r.headers['Idempotency-Key'], isNotEmpty);
            return response({}, 202);
          }
          if (r.url.path.endsWith('/parent-insights')) {
            return response(insight());
          }
          return response({'available': false});
        }),
      );
      await open(tester, state, 'insights');
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await openParentDetails103(tester, 'Regelmäßige KI-Auswertung');
      await tap(tester, 'Regelmäßig mit KI auswerten');
      await tap(tester, 'Jetzt mit KI auswerten');
      expect(calls.where((r) => r.method == 'PUT').length, 1);
      expect(calls.where((r) => r.method == 'POST').length, 1);
      await tester.ensureVisible(find.byTooltip('Lernkompass neu laden'));
      await tester.tap(find.byTooltip('Lernkompass neu laden'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets('An unconfirmed transport keeps one idempotency key', (
    tester,
  ) async {
    final keys = <String>[];
    final state = account(
      MockClient((r) async {
        if (r.method == 'POST') {
          keys.add(r.headers['Idempotency-Key']!);
          throw Exception('Synthetic disconnected response');
        }
        return response(insight(ready: false));
      }),
    );
    await open(tester, state, 'insights');
    await tap(tester, 'Jetzt mit KI auswerten');
    await tap(tester, 'Anfrage abgleichen');
    expect(keys.length, 2);
    expect(keys.toSet().length, 1);
  });

  testWidgets('A parent prepares one topic then sees saved status', (
    tester,
  ) async {
    var posts = 0;
    final state = account(
      MockClient((r) async {
        if (r.method == 'POST') {
          posts++;
          expect(r.url.path, endsWith('/assignments/assignment/prepare'));
          return response({'kind': 'job', 'id': 'job'}, 202);
        }
        if (r.url.path.endsWith('/parent-insights')) {
          return response(insight(ready: false));
        }
        return response(plan());
      }),
    );
    await open(tester, state, 'plan');
    await tap(tester, 'Meine Themen');
    await tap(tester, 'KI-Runde vorbereiten');
    expect(posts, 1);
    expect(find.text('Gespeicherter Vorbereitungsstatus'), findsOneWidget);
  });

  testWidgets('Homework filters and topic evidence links stay read-only', (
    tester,
  ) async {
    final filters = <String>[];
    final state = account(
      MockClient((r) async {
        expect(r.method, 'GET');
        if (r.url.path.endsWith('/homework-review')) {
          filters.add(r.url.queryParameters['state']!);
          return response(homework());
        }
        if (r.url.path.endsWith('/parent-insights')) return response(insight());
        return response({'available': false});
      }),
    );
    final router = await open(tester, state, 'homework');
    await toggleParentDetails104(tester, 'Suche & Hausaufgabenfilter');
    await tap(tester, 'Mit Häkchen');
    expect(filters, ['all', 'worked']);
    router.go('/insights');
    await tester.pumpAndSettle();
    await tap(tester, 'Übungsbelege zu Bruchaddition ansehen');
    expect(find.text('Belege Mathematik Bruchaddition'), findsOneWidget);
  });

  testWidgets('Account change removes private report immediately', (
    tester,
  ) async {
    final state = account(MockClient((r) async => response(insight())));
    await open(tester, state, 'insights');
    expect(find.text('KI-Lernkompass'), findsOneWidget);
    state.user = {'id': 'other', 'role': 'parent'};
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('KI-Lernkompass'), findsNothing);
  });

  testWidgets(
    'Returning from a covered parent view refreshes saved status only',
    (tester) async {
      var reads = 0;
      var pending = false;
      final state = account(
        MockClient((r) async {
          expect(r.method, 'GET');
          reads++;
          return response({
            ...insight(),
            if (pending) 'pending': {'status': 'running'},
          });
        }),
      );
      final router = await open(tester, state, 'insights');
      pending = true;
      await tester.tap(find.byTooltip('Lernkompass neu laden'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Die neue Auswertung wird vorbereitet.'),
        findsOneWidget,
      );

      router.push('/progress/child?fach=Mathematik&thema=Bruchaddition');
      await tester.pumpAndSettle();
      final coveredReads = reads;
      await tester.pump(const Duration(seconds: 5));
      expect(reads, coveredReads);

      pending = false;
      router.pop();
      await tester.pumpAndSettle();
      expect(reads, coveredReads + 1);
      expect(
        find.textContaining('Die neue Auswertung wird vorbereitet.'),
        findsNothing,
      );
    },
  );

  testWidgets('The learning plan does not offer a link to itself', (
    tester,
  ) async {
    final state = account(
      MockClient((r) async {
        if (r.url.path.endsWith('/parent-insights')) return response(insight());
        if (r.url.path.endsWith('/learning-plan')) return response(plan());
        return response({'available': false});
      }),
    );
    await open(tester, state, 'plan');
    await tap(tester, 'KI-Lernweg');
    expect(find.text('KI-Lernkompass'), findsOneWidget);
    expect(find.text('Lernplan öffnen'), findsNothing);
  });
}
