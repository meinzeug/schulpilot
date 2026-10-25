import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

const childId = '11111111111111111111111111111111';
const changedDay = '22222222222222222222222222222222';

Json overview() => {
  'child': {
    'id': childId,
    'display_name': 'Beispielkind',
    'preferences': {'daily_minutes': 20},
  },
  'plan': {
    'date': '2026-10-25',
    'today': <Json>[],
    'voluntary': <Json>[],
    'can_continue_voluntarily': true,
    'goal_required': true,
    'daily_goal_met': false,
    'daily_active_seconds': 120,
    'daily_goal_minutes': 20,
    'weekly_active_seconds': 120,
    'weekly_goal_minutes': 100,
    'completed_today': 0,
    'blocked_study_paths': [
      {
        'day_id': changedDay,
        'date': '2026-10-24',
        'reason_code': 'source_changed',
      },
    ],
  },
  'daily_capture': {'status': 'skipped'},
  'material_count': 2,
  'materials': <Json>[],
  'units': <Json>[],
  'messages': <Json>[],
};

Future<List<http.Request>> mount(WidgetTester tester, Json data) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 844);
  await tester.binding.setSurfaceSize(const Size(320, 844));
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(
                request.method,
                'GET',
                reason:
                    'Opening saved views never starts AI or records an answer.',
              );
              return http.Response(
                jsonEncode(data),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-child-user',
          'role': 'child',
          'child_id': childId,
          'display_name': 'Beispielkind',
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/library/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Heftsammlung ${route.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, route) => Scaffold(
          body: Text(
            'Quellenprüfung ${route.pathParameters['id']} ${route.uri.queryParameters['day']}',
          ),
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, route) => Scaffold(
          body: Text('Gespeicherte Runde ${route.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'A blocked old day offers current notebooks with a separate valid review hint',
    (tester) async {
      final data = overview();
      data['plan']['blocked_study_paths'].addAll([
        {'day_id': changedDay, 'reason_code': 'source_changed'},
        {'day_id': '../../other-child', 'reason_code': 'source_changed'},
        {'day_id': '33333333333333333333333333333333', 'reason_code': 'other'},
      ]);
      final requests = await mount(tester, data);
      final hero = tester.widget<ChildTodayHero>(find.byType(ChildTodayHero));
      expect(hero.title, 'Mit deinen Heften weiterlernen');
      expect((hero.action as ActionButton).label, 'Hefte öffnen');
      expect(find.text('Ein Lernweg braucht Prüfung'), findsOneWidget);
      expect(find.text('Freiwillig weiterlernen'), findsNothing);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Hefte öffnen');
      expect(find.text('Heftsammlung $childId'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('The separate blocked-day hint opens only its own saved day', (
    tester,
  ) async {
    final requests = await mount(tester, overview());
    expect(
      find.text(
        'Die Heftseiten haben sich geändert. Deine Antworten bleiben gespeichert.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Ein Lernweg braucht Prüfung');
    expect(find.text('Quellenprüfung $childId $changedDay'), findsOneWidget);
    expect(requests.every((request) => request.method == 'GET'), true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An available mandatory saved unit stays primary even after the time goal',
    (tester) async {
      final data = overview();
      final unit = <String, dynamic>{
        'id': 'saved-round',
        'kind': 'unit',
        'status': 'paused',
        'subject': 'Mathematik',
        'topic': 'Gespeicherte Bruchrunde',
        'mandatory': true,
        'question_count': 4,
        'closed_questions': 2,
      };
      data['units'] = [unit];
      data['plan']['today'] = [unit];
      data['plan']['daily_goal_met'] = true;
      final requests = await mount(tester, data);
      final hero = tester.widget<ChildTodayHero>(find.byType(ChildTodayHero));
      expect(hero.title, 'Gespeicherte Bruchrunde');
      expect(hero.subtitle, contains('Elternauftrag'));
      expect((hero.action as ActionButton).label, 'Weiterlernen');
      expect(find.text('Hefte öffnen'), findsNothing);
      expect(find.text('Ein Lernweg braucht Prüfung'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unread saved feedback stays ahead of available and blocked learning paths',
    (tester) async {
      final data = overview();
      data['plan']['daily_goal_met'] = true;
      data['plan']['voluntary'] = [
        {
          'id': 'available-round',
          'kind': 'unit',
          'status': 'paused',
          'subject': 'Mathematik',
          'topic': 'Nächste Bruchrunde',
        },
      ];
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
      final requests = await mount(tester, data);
      final hero = tester.widget<ChildTodayHero>(find.byType(ChildTodayHero));
      expect(hero.title, 'Deine letzte Antwort');
      expect((hero.action as ActionButton).label, 'Rückmeldung ansehen');
      expect(find.text('Hefte öffnen'), findsNothing);
      await tap(tester, 'Rückmeldung ansehen');
      expect(find.text('Gespeicherte Runde finished-round'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), true);
      expect(tester.takeException(), isNull);
    },
  );
}
