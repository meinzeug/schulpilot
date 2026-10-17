import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/daily_plan_panel.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/learning_navigation.dart';
import 'package:schulpilot/study_path_panel.dart';
import 'package:schulpilot/ui.dart';

Json overview() {
  final data = jsonDecode(
    File('test/fixtures/child_home.json').readAsStringSync(),
  ) as Json;
  data['daily_capture'] = {'status': 'skipped', 'page_count': 0};
  (data['plan'] as Json).addAll({
    'daily_goal_minutes': 20,
    'weekly_goal_minutes': 100,
    'daily_active_seconds': 0,
    'weekly_active_seconds': 0,
    'daily_goal_met': false,
    'weekly_goal_met': false,
    'daily_remaining_minutes': 20,
    'weekly_remaining_minutes': 100,
    'goal_required': true,
    'optional_learning': true,
    'can_continue_voluntarily': true,
    'voluntary': <Json>[],
    'week': <Json>[],
  });
  return data;
}

http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> mountHome(
  WidgetTester tester,
  Json data, {
  required List<http.Request> requests,
  double width = 390,
  bool quotaExhausted = false,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (request.method == 'POST' &&
                  request.url.path.endsWith('/start')) {
                return quotaExhausted
                    ? jsonResponse({
                        'detail': 'Dein Lernkontingent ist aufgebraucht.',
                      }, 429)
                    : jsonResponse({'status': 'active'});
              }
              expect(
                request.method,
                'GET',
                reason: 'Home must not generate work automatically.',
              );
              return jsonResponse(data);
            }),
          ),
        )
        ..user = {
          'id': 'artificial-child-user',
          'role': 'child',
          'display_name': 'Mika',
          'child_id': data['child']['id'],
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Lernrunde')),
      ),
      GoRoute(
        path: '/learn/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigener Lernraum')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Heftfotos')),
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
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void makeVoluntary(Json data) {
  final plan = data['plan'] as Json;
  plan['voluntary'] = plan['today'];
  plan['today'] = <Json>[];
  plan['available_minutes'] = 0;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'fulfilled daily goal permits only an explicit voluntary start at $width px',
      (tester) async {
        final data = overview();
        makeVoluntary(data);
        (data['plan'] as Json).addAll({
          'daily_goal_met': true,
          'daily_remaining_minutes': 0,
          'daily_active_seconds': 1200,
        });
        final requests = <http.Request>[];
        await mountHome(tester, data, requests: requests, width: width);
        expect(find.text('Freiwillig weiterlernen'), findsOneWidget);
        expect(
          find.textContaining(
            'Tagesziel geschafft · Heute ca. 20 von 20 Min. aktiv',
          ),
          findsOneWidget,
        );
        expect(find.text('Jetzt lernen'), findsNothing);
        expect(requests.where((request) => request.method != 'GET'), isEmpty);
        await tap(tester, 'Freiwillig weiterlernen');
        expect(find.text('Eigene Lernrunde'), findsOneWidget);
        expect(
          requests
              .where((request) => request.method == 'POST')
              .map((request) => request.url.path),
          ['/api/units/${data['plan']['voluntary'][0]['id']}/start'],
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final pause in [false, true]) {
    testWidgets(
      'free or paused calendar permits a voluntary stored round ($pause)',
      (tester) async {
        final data = overview();
        makeVoluntary(data);
        (data['plan'] as Json).addAll({
          'free_day': !pause,
          'paused': pause,
          'goal_required': false,
        });
        final requests = <http.Request>[];
        await mountHome(tester, data, requests: requests);
        expect(find.text('Freiwillig weiterlernen'), findsOneWidget);
        expect(find.textContaining('ohne festes Lernziel'), findsOneWidget);
        expect(requests.where((request) => request.method == 'POST'), isEmpty);
        await tap(tester, 'Freiwillig weiterlernen');
        expect(find.text('Eigene Lernrunde'), findsOneWidget);
        expect(requests.where((request) => request.method == 'POST').length, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'estimated completed portions never mark an unmet actual goal as fulfilled',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      (data['plan'] as Json).addAll({
        'daily_active_seconds': 30,
        'daily_used_minutes_approx': 20,
        'planned_minutes': 20,
        'completed_today': 1,
        'daily_goal_met': false,
      });
      data['units'][0]['estimated_minutes'] = 20;
      final requests = <http.Request>[];
      await mountHome(tester, data, requests: requests);
      expect(
        find.text('Tagesziel offen · Heute ca. 0,5 von 20 Min. aktiv'),
        findsOneWidget,
      );
      expect(find.textContaining('Tagesziel geschafft'), findsNothing);
      expect(find.text('Für heute geschafft!'), findsNothing);
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a finished estimated twenty minute round still requires eight real minutes after twelve active minutes',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      (data['plan'] as Json).addAll({
        'daily_active_seconds': 720,
        'daily_used_minutes_approx': 20,
        'completed_today': 1,
        'daily_remaining_minutes': 8,
        'daily_goal_met': false,
      });
      data['units'][0]['estimated_minutes'] = 20;
      data['units'][0]['status'] = 'completed';
      data['plan']['voluntary'][0]['estimated_minutes'] = 20;
      data['plan']['voluntary'][0]['id'] = 'next-saved-round';
      final requests = <http.Request>[];
      await mountHome(tester, data, requests: requests, width: 320);
      expect(
        find.text('Tagesziel offen · Heute ca. 12 von 20 Min. aktiv'),
        findsOneWidget,
      );
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(find.text('Freiwillig weiterlernen'), findsNothing);
      expect(find.textContaining('Tagesziel geschafft'), findsNothing);
      expect(find.text('Für heute geschafft!'), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'nearly fulfilled raw seconds do not display a rounded-up completed target',
    (tester) async {
      final data = overview();
      (data['plan'] as Json).addAll({
        'daily_active_seconds': 1199,
        'daily_used_minutes_approx': 20,
        'daily_goal_met': false,
      });
      await mountHome(tester, data, requests: []);
      expect(
        find.text('Tagesziel offen · Heute ca. 19,9 von 20 Min. aktiv'),
        findsOneWidget,
      );
      expect(find.textContaining('Tagesziel geschafft'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a met weekly goal does not claim the still open daily goal is done',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      (data['plan'] as Json).addAll({
        'weekly_goal_met': true,
        'weekly_remaining_minutes': 0,
        'weekly_active_seconds': 6000,
        'daily_active_seconds': 60,
      });
      await mountHome(tester, data, requests: []);
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(find.textContaining('Tagesziel geschafft'), findsNothing);
      expect(
        find.text('Tagesziel offen · Heute ca. 1 von 20 Min. aktiv'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('future parent work is not used as the voluntary next action', (
    tester,
  ) async {
    final data = overview();
    makeVoluntary(data);
    data['plan']['voluntary'][0]['scheduled_for'] = '2026-10-16';
    data['plan']['daily_goal_met'] = true;
    data['plan']['daily_active_seconds'] = 1200;
    final requests = <http.Request>[];
    await mountHome(tester, data, requests: requests);
    expect(find.text('Freiwillig weiterlernen'), findsNothing);
    expect(find.text('Mein Lernen öffnen'), findsOneWidget);
    await tap(tester, 'Mein Lernen öffnen');
    expect(find.text('Eigener Lernraum'), findsOneWidget);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'voluntary start preserves actual server quota errors without retry',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      data['plan']['daily_goal_met'] = true;
      data['plan']['daily_active_seconds'] = 1200;
      final requests = <http.Request>[];
      await mountHome(tester, data, requests: requests, quotaExhausted: true);
      await tap(tester, 'Freiwillig weiterlernen');
      expect(
        find.text('Dein Lernkontingent ist aufgebraucht.'),
        findsOneWidget,
      );
      expect(find.text('Eigene Lernrunde'), findsNothing);
      expect(requests.where((request) => request.method == 'POST').length, 1);
      expect(find.textContaining('kaufen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a voluntary start does not relabel recorded homework as an optional assignment',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      data['plan']['daily_goal_met'] = true;
      data['plan']['daily_active_seconds'] = 1200;
      data['plan']['voluntary'][0]['mandatory'] = true;
      data['plan']['voluntary'][0]['assignment_kind'] = 'homework';
      await mountHome(tester, data, requests: []);
      expect(find.text('Freiwillig weiterlernen'), findsOneWidget);
      expect(
        find.textContaining('Notierte Hausaufgabe · Mathematik'),
        findsOneWidget,
      );
      expect(data['plan']['voluntary'][0]['mandatory'], true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'explicit server unavailability is not overridden by voluntary data',
    (tester) async {
      final data = overview();
      makeVoluntary(data);
      data['plan']['can_continue_voluntarily'] = false;
      final requests = <http.Request>[];
      await mountHome(tester, data, requests: requests);
      expect(find.text('Freiwillig weiterlernen'), findsNothing);
      expect(find.text('Weiterlernen'), findsNothing);
      expect(find.text('Mein Lernen öffnen'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'parent planning labels minimum goals and actual weekly activity',
    (tester) async {
      final plan = overview()['plan'] as Json;
      plan['weekly_active_seconds'] = 659;
      plan['weekly_used_minutes_approx'] = 100;
      await tester.binding.setSurfaceSize(const Size(320, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  LearningGoalPanel(plan: plan),
                  DailyPlanPanel(plan: plan),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Mindestziele: 20 Min. am Tag · 100 Min. pro Woche.',
        ),
        findsOneWidget,
      );
      expect(find.text('10:59 / 100 Min.'), findsOneWidget);
      expect(find.textContaining('Zeitgrenzen:'), findsNothing);
      expect(
        find.textContaining('zählen mit ihrer geplanten Zeit zum Ziel'),
        findsNothing,
      );
      expect(
        find.textContaining('Zum Ziel zählt aktive Lernzeit'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a next stage stays one explicit action without declaring an unmet goal optional',
    (tester) async {
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            requests.add(request);
            return jsonResponse({
              'available': true,
              'id': 'day',
              'day_id': 'day',
              'total_questions': 4,
              'completed_questions': 2,
              'ready_questions': 0,
              'blocks': [
                {
                  'id': 'first',
                  'title': 'Neue künstliche Runde',
                  'phase': 'understand',
                  'question_count': 2,
                  'status': 'planned',
                },
              ],
              'next_block_id': 'first',
              'can_continue': true,
              'stale': false,
            });
          }),
        ),
      )..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudyPathPanel(state, 'child', 'day'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nächste Etappe'), findsOneWidget);
      expect(
        find.text('Die nächste Runde beginnt, wenn du sie auswählst.'),
        findsOneWidget,
      );
      expect(requests.every((request) => request.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'fixed start dates are respected without guessing a collection timezone',
    () {
      expect(
        planItemDue({'date': '2026-10-14'}, {'scheduled_for': '2026-10-15'}),
        false,
      );
      expect(
        planItemDue({'date': '2026-10-14'}, {'scheduled_for': '2026-10-14'}),
        true,
      );
      expect(planItemDue({}, {'scheduled_for': '2026-10-15'}), true);
    },
  );
}
